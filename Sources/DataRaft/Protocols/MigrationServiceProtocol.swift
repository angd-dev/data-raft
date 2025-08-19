import Foundation

/// Protocol for managing and executing database schema migrations.
///
/// Conforming types are responsible for registering migrations, applying
/// encryption keys (if required), and executing pending migrations in
/// ascending version order.
///
/// Migrations ensure that the database schema evolves consistently across
/// application versions without requiring manual intervention.
public protocol MigrationServiceProtocol: AnyObject, Sendable {
    /// Type representing the schema version used for migrations.
    associatedtype Version: VersionRepresentable
    
    /// Encryption key provider for the database service.
    var keyProvider: DatabaseServiceKeyProvider? { get set }
    
    /// Applies an encryption key to the current database connection.
    ///
    /// - Throws: Any error that occurs while retrieving or applying the key.
    func applyKeyProvider() throws
    
    /// Recreates the database connection and reapplies the encryption key if available.
    ///
    /// - Throws: Any error that occurs while creating the connection or applying the key.
    func reconnect() throws
    
    /// Registers a migration to be executed by the service.
    ///
    /// - Parameter migration: The migration to register.
    /// - Throws: ``MigrationError/duplicateMigration(_:)`` if a migration with
    ///   the same version or script URL is already registered.
    func add(_ migration: Migration<Version>) throws(MigrationError<Version>)
    
    /// Executes all pending migrations in ascending version order.
    ///
    /// - Throws: ``MigrationError/emptyMigrationScript(_:)`` if a migration
    ///   script is empty.
    /// - Throws: ``MigrationError/migrationFailed(_:_:)`` if a script execution
    ///   or version update fails.
    func migrate() throws(MigrationError<Version>)
}

@available(iOS 13.0, *)
@available(macOS 10.15, *)
public extension MigrationServiceProtocol {
    /// Asynchronously executes all pending migrations in ascending order.
    ///
    /// Performs the same logic as ``migrate()``, but runs asynchronously
    /// on a background task with `.utility` priority.
    ///
    /// - Throws: ``MigrationError/emptyMigrationScript(_:)`` if a migration
    ///   script is empty.
    /// - Throws: ``MigrationError/migrationFailed(_:_:)`` if a script execution
    ///   or version update fails.
    func migrate() async throws {
        try await Task(priority: .utility) {
            try self.migrate()
        }.value
    }
}
