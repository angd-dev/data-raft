import Foundation

/// A type that manages and executes database schema migrations.
///
/// ## Overview
///
/// Conforming types are responsible for registering migration steps, applying encryption keys
/// (if required), and executing pending migrations in ascending version order. Migrations ensure
/// that the database schema evolves consistently across application versions without manual
/// intervention.
///
/// ## Topics
///
/// ### Associated Types
/// - ``Version``
///
/// ### Properties
/// - ``keyProvider``
///
/// ### Instance Methods
/// - ``add(_:)``
/// - ``migrate()``
/// - ``migrate()-18x5r``
public protocol MigrationServiceProtocol: AnyObject, Sendable {
    /// The type representing a schema version used for migrations.
    associatedtype Version: VersionRepresentable
    
    /// The provider responsible for supplying encryption keys to the service.
    var keyProvider: ConnectionServiceKeyProvider? { get set }
    
    /// Registers a migration to be executed by the service.
    ///
    /// - Parameter migration: The migration to register.
    /// - Throws: ``MigrationError/duplicateMigration(_:)`` if a migration with the same version
    ///   or script URL is already registered.
    func add(_ migration: Migration<Version>) throws(MigrationError<Version>)
    
    /// Executes all pending migrations in ascending version order.
    ///
    /// - Throws: ``MigrationError/emptyMigrationScript(_:)`` if a migration script is empty.
    /// - Throws: ``MigrationError/migrationFailed(_:_:)`` if a migration step fails to execute
    ///   or update the stored version.
    func migrate() throws(MigrationError<Version>)
}

@available(iOS 13.0, macOS 10.15, *)
public extension MigrationServiceProtocol {
    /// Asynchronously executes all pending migrations in ascending version order.
    ///
    /// Performs the same logic as ``migrate()``, but runs asynchronously on a background task with
    /// `.utility` priority.
    ///
    /// - Throws: ``MigrationError/emptyMigrationScript(_:)`` if a migration script is empty.
    /// - Throws: ``MigrationError/migrationFailed(_:_:)`` if a migration step fails to execute
    ///   or update the stored version.
    func migrate() async throws {
        try await Task(priority: .utility) {
            try self.migrate()
        }.value
    }
}
