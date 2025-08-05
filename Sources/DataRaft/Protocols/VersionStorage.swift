import Foundation
import DataLiteCore

/// A protocol that defines how the database version is stored and retrieved.
///
/// This protocol decouples the concept of version representation from
/// the way the version is stored. It enables flexible implementations
/// that can store version values in different forms and places.
///
/// The associated `Version` type determines how the version is represented
/// (e.g. as an integer, a semantic string, or a structured object), while the
/// conforming type defines how that version is persisted.
///
/// Use this protocol to implement custom strategies for version tracking:
/// - Store an integer version in SQLite's `user_version` field.
/// - Store a string in a dedicated metadata table.
/// - Store structured data in a JSON column.
///
/// To define your own versioning mechanism, implement `VersionStorage`
/// and choose a `Version` type that conforms to ``VersionRepresentable``.
///
/// You can implement this protocol to define a custom way of storing the version
/// of a database schema. For example, the version could be a string stored in a metadata table.
///
/// Below is an example of a simple implementation that stores the version string
/// in a table named `schema_version`.
///
/// ```swift
/// final class StringVersionStorage: VersionStorage {
///     typealias Version = String
///
///     func prepare(_ connection: Connection) throws {
///         let script: SQLScript = """
///         CREATE TABLE IF NOT EXISTS schema_version (
///             version TEXT NOT NULL
///         );
///
///         INSERT INTO schema_version (version)
///         SELECT '0.0.0'
///         WHERE NOT EXISTS (SELECT 1 FROM schema_version);
///         """
///         try connection.execute(sql: script)
///     }
///
///     func getVersion(_ connection: Connection) throws -> Version {
///         let query = "SELECT version FROM schema_version LIMIT 1"
///         let stmt = try connection.prepare(sql: query)
///         guard try stmt.step(), let value: Version = stmt.columnValue(at: 0) else {
///             throw DatabaseError.message("Missing version in schema_version table.")
///         }
///         return value
///     }
///
///     func setVersion(_ connection: Connection, _ version: Version) throws {
///         let query = "UPDATE schema_version SET version = ?"
///         let stmt = try connection.prepare(sql: query)
///         try stmt.bind(version, at: 0)
///         try stmt.step()
///     }
/// }
/// ```
///
/// This implementation works as follows:
///
/// - `prepare(_:)` creates the `schema_version` table if it does not exist, and ensures that it
///   contains exactly one row with an initial version value (`"0.0.0"`).
///
/// - `getVersion(_:)` reads the current version string from the single row in the table.
///   If the row is missing, it throws an error.
///
/// - `setVersion(_:_:)` updates the version string in that row. A `WHERE` clause is not necessary
///   because the table always contains exactly one row.
///
/// ## Topics
///
/// ### Associated Types
///
/// - ``Version``
///
/// ### Instance Methods
///
/// - ``prepare(_:)``
/// - ``getVersion(_:)``
/// - ``setVersion(_:_:)``
public protocol VersionStorage {
    /// A type representing the database schema version.
    associatedtype Version: VersionRepresentable
    
    /// Prepares the storage mechanism for tracking the schema version.
    ///
    /// This method is called before any version operations. Use it to create required tables
    /// or metadata structures needed for version management.
    ///
    /// - Important: This method is executed within an active migration transaction.
    ///   Do not issue `BEGIN` or `COMMIT` manually. If this method throws an error,
    ///   the entire migration process will be aborted and rolled back.
    ///
    /// - Parameter connection: The database connection used for schema preparation.
    /// - Throws: An error if preparation fails.
    func prepare(_ connection: Connection) throws
    
    /// Returns the current schema version stored in the database.
    ///
    /// This method must return a valid version previously stored by the migration system.
    ///
    /// - Important: This method is executed within an active migration transaction.
    ///   Do not issue `BEGIN` or `COMMIT` manually. If this method throws an error,
    ///   the entire migration process will be aborted and rolled back.
    ///
    /// - Parameter connection: The database connection used to fetch the version.
    /// - Returns: The version currently stored in the database.
    /// - Throws: An error if reading fails or the version is missing.
    func getVersion(_ connection: Connection) throws -> Version
    
    /// Stores the given version as the current schema version.
    ///
    /// This method is called at the end of the migration process to persist
    /// the final schema version after all migration steps have completed successfully.
    ///
    /// - Important: This method is executed within an active migration transaction.
    ///   Do not issue `BEGIN` or `COMMIT` manually. If this method throws an error,
    ///   the entire migration process will be aborted and rolled back.
    ///
    /// - Parameters:
    ///   - connection: The database connection used to write the version.
    ///   - version: The version to store.
    /// - Throws: An error if writing fails.
    func setVersion(_ connection: Connection, _ version: Version) throws
}

public extension VersionStorage {
    /// A default implementation that performs no preparation.
    ///
    /// Override this method if your storage implementation requires any setup,
    /// such as creating a version table or inserting an initial value.
    ///
    /// If you override this method and it throws an error, the migration process
    /// will be aborted and rolled back.
    func prepare(_ connection: Connection) throws {}
}
