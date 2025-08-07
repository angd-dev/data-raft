import Foundation

/// Protocol for managing and running database schema migrations.
public protocol MigrationServiceProtocol: AnyObject {
    /// Type representing the schema version for migrations.
    associatedtype Version: VersionRepresentable
    
    /// Provider of encryption keys for the database service.
    var keyProvider: DatabaseServiceKeyProvider? { get set }
    
    /// Adds a migration to be executed by the service.
    ///
    /// - Parameter migration: The migration to register.
    /// - Throws: ``MigrationError/duplicateMigration(_:)`` if a migration with
    ///   the same version or script URL is already registered.
    func add(_ migration: Migration<Version>) throws(MigrationError<Version>)
    
    /// Runs all pending migrations in ascending version order.
    ///
    /// - Throws: ``MigrationError/emptyMigrationScript(_:)`` if a migration
    ///   script is empty.
    /// - Throws: ``MigrationError/migrationFailed(_:_:)`` if a script execution
    ///   or version update fails.
    func migrate() throws(MigrationError<Version>)
}

@available(iOS 13.0, *)
@available(macOS 10.15, *)
public extension MigrationServiceProtocol where Self: Sendable {
    /// Asynchronously runs all pending migrations in ascending order.
    ///
    /// Performs the same logic as ``migrate()``, but runs asynchronously.
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
