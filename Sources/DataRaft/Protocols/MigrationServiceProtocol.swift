import Foundation

public protocol MigrationServiceProtocol: AnyObject {
    associatedtype Version: VersionRepresentable
    
    var keyProvider: DatabaseServiceKeyProvider? { get set }
    
    func add(_ migration: Migration<Version>) throws(MigrationError<Version>)
    func migrate() throws(MigrationError<Version>)
}

@available(iOS 13.0, *)
@available(macOS 10.15, *)
public extension MigrationServiceProtocol where Self: Sendable {
    /// Executes all pending migrations asynchronously in ascending version order.
    ///
    /// This method performs the same migration logic as ``migrate()``, but
    /// offloads the work to a background thread using Swift concurrency.
    ///
    /// - Throws: ``MigrationError/migrationFailed(_:_:)`` if a migration script fails or if updating the version fails.
    /// - Throws: ``MigrationError/emptyMigrationScript(_:)`` if a migration script is empty.
    func migrate() async throws {
        try await Task(priority: .utility) {
            try self.migrate()
        }.value
    }
}
