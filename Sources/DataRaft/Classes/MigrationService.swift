import Foundation
import DataLiteCore

/// Thread-safe service for executing ordered database schema migrations.
///
/// `MigrationService` stores registered migrations and applies them sequentially
/// to update the database schema. Each migration runs only once, in version order,
/// based on the current schema version stored in the database.
///
/// The service is generic over:
/// - `Service`: a database service conforming to ``DatabaseServiceProtocol``
/// - `Storage`: a version storage conforming to ``VersionStorage``
///
/// Migrations are identified by version and script URL. Both must be unique
/// across all registered migrations.
///
/// Execution is performed inside a single `.exclusive` transaction, ensuring
/// that either all pending migrations are applied successfully or none are.
/// On error, the database state is rolled back to the original version.
///
/// This type is safe to use from multiple threads.
///
/// ```swift
/// let connection = try Connection(location: .inMemory, options: .readwrite)
/// let storage = UserVersionStorage<BitPackVersion>()
/// let service = MigrationService(service: connectionService, storage: storage)
///
/// try service.add(Migration(version: "1.0.0", byResource: "v_1_0_0.sql")!)
/// try service.add(Migration(version: "1.0.1", byResource: "v_1_0_1.sql")!)
/// try service.migrate()
/// ```
///
/// ### Custom Versions and Storage
///
/// You can supply a custom `Version` type conforming to ``VersionRepresentable``
/// and a `VersionStorage` implementation that determines how and where the
/// version is persisted (e.g., `PRAGMA user_version`, metadata table, etc.).
public final class MigrationService<
    Service: DatabaseServiceProtocol,
    Storage: VersionStorage
>:
    MigrationServiceProtocol,
    @unchecked Sendable
{
    /// Schema version type used for migration ordering.
    public typealias Version = Storage.Version
    
    private let service: Service
    private let storage: Storage
    private var mutex = pthread_mutex_t()
    private var migrations = Set<Migration<Version>>()
    
    /// Encryption key provider delegated to the underlying database service.
    public weak var keyProvider: DatabaseServiceKeyProvider? {
        get { service.keyProvider }
        set { service.keyProvider = newValue }
    }
    
    /// Creates a migration service with the given database service and storage.
    ///
    /// - Parameters:
    ///   - service: Database service used to execute migrations.
    ///   - storage: Version storage for reading and writing schema version.
    public init(
        service: Service,
        storage: Storage
    ) {
        self.service = service
        self.storage = storage
        pthread_mutex_init(&mutex, nil)
    }
    
    deinit {
        pthread_mutex_destroy(&mutex)
    }
    
    /// Registers a new migration, ensuring version and script URL uniqueness.
    ///
    /// - Parameter migration: The migration to register.
    /// - Throws: ``MigrationError/duplicateMigration(_:)`` if the migration's
    ///   version or script URL is already registered.
    public func add(_ migration: Migration<Version>) throws(MigrationError<Version>) {
        pthread_mutex_lock(&mutex)
        defer { pthread_mutex_unlock(&mutex) }
        guard !migrations.contains(where: {
            $0.version == migration.version
            || $0.scriptURL == migration.scriptURL
        }) else {
            throw .duplicateMigration(migration)
        }
        migrations.insert(migration)
    }
    
    /// Executes all pending migrations inside a single exclusive transaction.
    ///
    /// This method retrieves the current schema version from storage, then determines
    /// which migrations have a higher version. The selected migrations are sorted in
    /// ascending order and each one's SQL script is executed in sequence. When all
    /// scripts complete successfully, the stored version is updated to the highest
    /// applied migration.
    ///
    /// If a script is empty or execution fails, the process aborts and the transaction
    /// is rolled back, leaving the database unchanged.
    ///
    /// - Throws: ``MigrationError/emptyMigrationScript(_:)`` if a script is empty.
    /// - Throws: ``MigrationError/migrationFailed(_:_:)`` if execution or version
    ///   update fails.
    public func migrate() throws(MigrationError<Version>) {
        pthread_mutex_lock(&mutex)
        defer { pthread_mutex_unlock(&mutex) }
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
                        throw MigrationError.emptyMigrationScript(migration)
                    }
                    do {
                        try connection.execute(sql: script)
                    } catch {
                        throw MigrationError.migrationFailed(migration, error)
                    }
                }
                
                if let version = migrations.last?.version {
                    try storage.setVersion(connection, version)
                }
            }
        } catch let error as MigrationError<Version> {
            throw error
        } catch {
            throw .migrationFailed(nil, error)
        }
    }
}
