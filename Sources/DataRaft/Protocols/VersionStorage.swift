import Foundation
import DataLiteCore

/// A type that defines how a database schema version is stored and retrieved.
///
/// ## Overview
///
/// This protocol separates the concept of version representation from its persistence mechanism,
/// allowing flexible implementations that store version values in different formats or locations.
///
/// The associated ``Version`` type specifies how the version is represented (for example, as an
/// integer, a semantic string, or a structured object), while the conforming type defines how that
/// version is persisted.
///
/// ## Usage
///
/// Implement this type to define a custom strategy for schema version tracking:
/// - Store an integer version in SQLite’s `user_version` field.
/// - Store a string in a dedicated metadata table.
/// - Store structured data in a JSON column.
///
/// The example below shows an implementation that stores the version string in a `schema_version`
/// table:
///
/// ```swift
/// final class StringVersionStorage: VersionStorage {
///     typealias Version = String
///
///     func prepare(_ connection: ConnectionProtocol) throws {
///         let script = """
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
///     func getVersion(_ connection: ConnectionProtocol) throws -> Version {
///         let query = "SELECT version FROM schema_version LIMIT 1"
///         let stmt = try connection.prepare(sql: query)
///         guard try stmt.step(), let value: Version = stmt.columnValue(at: 0) else {
///             throw DatabaseError.message("Missing version in schema_version table.")
///         }
///         return value
///     }
///
///     func setVersion(_ connection: ConnectionProtocol, _ version: Version) throws {
///         let query = "UPDATE schema_version SET version = ?"
///         let stmt = try connection.prepare(sql: query)
///         try stmt.bind(version, at: 0)
///         try stmt.step()
///     }
/// }
/// ```
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
    /// The type representing the database schema version.
    associatedtype Version: VersionRepresentable
    
    /// Creates a new instance of the version storage.
    init()
    
    /// Prepares the storage mechanism for tracking the schema version.
    ///
    /// Called before any version operations. Use this method to create required tables or metadata
    /// structures for version management.
    ///
    /// - Important: Executed within an active migration transaction. Do not issue `BEGIN` or
    ///   `COMMIT` manually. If this method throws an error, the migration process will be aborted
    ///   and rolled back.
    ///
    /// - Parameter connection: The database connection used for schema preparation.
    /// - Throws: An error if preparation fails.
    func prepare(_ connection: ConnectionProtocol) throws
    
    /// Returns the current schema version stored in the database.
    ///
    /// Must return a valid version previously stored by the migration system.
    ///
    /// - Important: Executed within an active migration transaction. Do not issue `BEGIN` or
    ///   `COMMIT` manually. If this method throws an error, the migration process will be aborted
    ///   and rolled back.
    ///
    /// - Parameter connection: The database connection used to fetch the version.
    /// - Returns: The version currently stored in the database.
    /// - Throws: An error if reading fails or the version is missing.
    func getVersion(_ connection: ConnectionProtocol) throws -> Version
    
    /// Stores the given version as the current schema version.
    ///
    /// Called at the end of the migration process to persist the final schema version after all
    /// migration steps complete successfully.
    ///
    /// - Important: Executed within an active migration transaction. Do not issue `BEGIN` or
    ///   `COMMIT` manually. If this method throws an error, the migration process will be aborted
    ///   and rolled back.
    ///
    /// - Parameters:
    ///   - connection: The database connection used to write the version.
    ///   - version: The version to store.
    /// - Throws: An error if writing fails.
    func setVersion(_ connection: ConnectionProtocol, _ version: Version) throws
}

public extension VersionStorage {
    func prepare(_ connection: ConnectionProtocol) throws {}
}
