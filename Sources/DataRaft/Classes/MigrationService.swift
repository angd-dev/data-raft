import Foundation
import DataLiteCore

/// A service responsible for managing and applying database migrations in a versioned manner.
///
/// `MigrationService` manages a collection of migrations identified by versions and script URLs,
/// and applies them sequentially to update the database schema. It ensures that each migration
/// is applied only once, and in the correct version order based on the current database version.
///
/// This service is generic over a `VersionStorage` implementation that handles storing and
/// retrieving the current database version. Migrations must have unique versions and script URLs
/// to prevent duplication.
///
/// ```swift
/// let connection = try Connection(location: .inMemory, options: .readwrite)
/// let storage = UserVersionStorage<BitPackVersion>()
/// let service = MigrationService(storage: storage, connection: connection)
///
/// try service.add(Migration(version: "1.0.0", byResource: "v_1_0_0.sql")!)
/// try service.add(Migration(version: "1.0.1", byResource: "v_1_0_1.sql")!)
/// try service.add(Migration(version: "1.1.0", byResource: "v_1_1_0.sql")!)
/// try service.add(Migration(version: "1.2.0", byResource: "v_1_2_0.sql")!)
///
/// try service.migrate()
/// ```
///
/// ### Custom Versions and Storage
///
/// You can customize versioning by providing your own `Version` type conforming to
/// ``VersionRepresentable``, which supports comparison, hashing, and identity checks.
///
/// The storage backend (`VersionStorage`) defines how the version is persisted, such as
/// in a pragma, table, or metadata.
///
/// This allows using semantic versions, integers, or other schemes, and storing them
/// in custom places.
public final class MigrationService<Service: DatabaseServiceProtocol, Storage: VersionStorage> {
    /// The version type used by this migration service, derived from the storage type.
    public typealias Version = Storage.Version
    
    /// Errors that may occur during migration registration or execution.
    public enum Error: Swift.Error {
        /// A migration with the same version or script URL was already registered.
        case duplicateMigration(Migration<Version>)
        
        /// Migration execution failed, with optional reference to the failed migration.
        case migrationFailed(Migration<Version>?, Swift.Error)
        
        /// The migration script is empty.
        case emptyMigrationScript(Migration<Version>)
    }
    
    // MARK: - Properties
    
    private let service: Service
    private let storage: Storage
    private var migrations = Set<Migration<Version>>()
    
    /// The encryption key provider delegated to the underlying database service.
    public weak var keyProvider: DatabaseServiceKeyProvider? {
        get { service.keyProvider }
        set { service.keyProvider = newValue }
    }
    
    // MARK: - Inits
    
    /// Creates a new migration service with the given database service and version storage.
    ///
    /// - Parameters:
    ///   - service: The database service used to perform migrations.
    ///   - storage: The version storage implementation used to track the current schema version.
    public init(
        service: Service,
        storage: Storage
    ) {
        self.service = service
        self.storage = storage
    }
    
    // MARK: - Migration Management
    
    /// Registers a new migration.
    ///
    /// Ensures that no other migration with the same version or script URL has been registered.
    ///
    /// - Parameter migration: The migration to register.
    /// - Throws: ``Error/duplicateMigration(_:)`` if the migration version or script URL duplicates an existing one.
    public func add(_ migration: Migration<Version>) throws {
        guard !migrations.contains(where: {
            $0.version == migration.version
            || $0.scriptURL == migration.scriptURL
        }) else {
            throw Error.duplicateMigration(migration)
        }
        migrations.insert(migration)
    }
    
    /// Executes all pending migrations in ascending version order.
    ///
    /// This method retrieves the current schema version from the storage, filters and sorts
    /// pending migrations, executes each migration script within a single exclusive transaction,
    /// and updates the schema version on success.
    ///
    /// If a migration script is empty or a migration fails, the process aborts and rolls back changes.
    ///
    /// - Throws: ``Error/migrationFailed(_:_:)`` if a migration script fails or if updating the version fails.
    public func migrate() throws {
        do {
            try service.perform(in: .exclusive) { connection in
                try storage.prepare(connection)
                let version = try storage.getVersion(connection)
                let migrations = migrations
                    .filter { $0.version > version }
                    .sorted { $0.version < $1.version }
                
                for migration in migrations {
                    let script = try migration.script
                    guard !script.isEmpty else {
                        throw Error.emptyMigrationScript(migration)
                    }
                    do {
                        try connection.execute(sql: script)
                    } catch {
                        throw Error.migrationFailed(migration, error)
                    }
                }
                
                if let version = migrations.last?.version {
                    try storage.setVersion(connection, version)
                }
            }
        } catch let error as Error {
            throw error
        } catch {
            throw Error.migrationFailed(nil, error)
        }
    }
}
