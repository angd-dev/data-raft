import Foundation
import DataLiteCore

#if os(Windows)
    import WinSDK
#endif

/// A service that executes ordered database schema migrations.
///
/// ## Overview
///
/// This class manages migration registration and applies them sequentially to update the database
/// schema. Each migration corresponds to a specific version and runs only once, ensuring that
/// schema upgrades are applied in a consistent, deterministic way.
///
/// Migrations are executed within an exclusive transaction — if any step fails, the entire process
/// is rolled back, leaving the database unchanged.
///
/// `MigrationService` coordinates the migration process by:
/// - Managing a registry of unique migrations.
/// - Reading and writing the current schema version through a ``VersionStorage`` implementation.
/// - Executing SQL scripts in ascending version order.
///
/// It is safe for concurrent use. Internally, it uses a POSIX mutex to ensure thread-safe
/// registration and execution.
///
/// ## Usage
///
/// ```swift
/// let connection = try Connection(location: .inMemory, options: .readwrite)
/// let storage = UserVersionStorage<SemanticVersion>()
/// let service = MigrationService(provider: { connection }, storage: storage)
///
/// try service.add(Migration(version: "1.0.0", byResource: "v1_0_0.sql")!)
/// try service.add(Migration(version: "1.0.1", byResource: "v1_0_1.sql")!)
/// try service.migrate()
/// ```
///
/// ## Topics
///
/// ### Initializers
///
/// - ``init(provider:config:queue:storage:)``
/// - ``init(provider:config:queue:)``
///
/// ### Migration Management
///
/// - ``add(_:)``
/// - ``migrate()``
public final class MigrationService<
    Storage: VersionStorage
>:
    ConnectionService,
    MigrationServiceProtocol,
    @unchecked Sendable
{
    // MARK: - Typealiases
    
    /// The type representing schema version ordering.
    public typealias Version = Storage.Version
    
    // MARK: - Properties
    
    private let storage: Storage
    private var migrations = Set<Migration<Version>>()
    
    #if os(Windows)
        private var mutex = SRWLOCK()
    #else
        private var mutex = pthread_mutex_t()
    #endif
    
    // MARK: - Inits
    
    /// Creates a migration service with a specified connection configuration and version storage.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a new database connection.
    ///   - config: An optional configuration closure called after the connection is established.
    ///   - queue: An optional target queue for internal database operations.
    ///   - storage: The version storage responsible for reading and writing schema version data.
    public init(
        provider: @escaping ConnectionProvider,
        config: ConnectionConfig? = nil,
        queue: DispatchQueue? = nil,
        storage: Storage
    ) {
        self.storage = storage
        super.init(provider: provider, config: config, queue: queue)
        
        #if os(Windows)
            InitializeSRWLock(&mutex)
        #else
            pthread_mutex_init(&mutex, nil)
        #endif
    }
    
    /// Creates a migration service using the default version storage.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a new database connection.
    ///   - config: An optional configuration closure called after the connection is established.
    ///   - queue: An optional target queue for internal database operations.
    public required init(
        provider: @escaping ConnectionProvider,
        config: ConnectionConfig? = nil,
        queue: DispatchQueue? = nil
    ) {
        self.storage = .init()
        super.init(provider: provider, config: config, queue: queue)
        
        #if os(Windows)
            InitializeSRWLock(&mutex)
        #else
            pthread_mutex_init(&mutex, nil)
        #endif
    }
    
    deinit {
        #if !os(Windows)
            pthread_mutex_destroy(&mutex)
        #endif
    }
    
    // MARK: - Unsupported
    
    @available(*, unavailable)
    public override func setNeedsReconnect() -> Bool {
        fatalError("Reconnection is not supported for MigrationService.")
    }
    
    @available(*, unavailable)
    public override func perform<T>(_ closure: Perform<T>) throws -> T {
        fatalError("Direct perform is not supported for MigrationService.")
    }
    
    // MARK: - Migration Management
    
    /// Registers a new migration, ensuring version and script URL uniqueness.
    ///
    /// - Parameter migration: The migration to register.
    /// - Throws: ``MigrationError/duplicateMigration(_:)`` if a migration with the same version or
    ///   script URL is already registered.
    public func add(_ migration: Migration<Version>) throws(MigrationError<Version>) {
        #if os(Windows)
            AcquireSRWLockExclusive(&mutex)
            defer { ReleaseSRWLockExclusive(&mutex) }
        #else
            pthread_mutex_lock(&mutex)
            defer { pthread_mutex_unlock(&mutex) }
        #endif
        
        guard
            !migrations.contains(where: {
                $0.version == migration.version
                    || $0.scriptURL == migration.scriptURL
            })
        else {
            throw .duplicateMigration(migration)
        }
        
        migrations.insert(migration)
    }
    
    /// Executes all pending migrations in ascending version order.
    ///
    /// The service retrieves the current version from ``VersionStorage``, selects migrations with
    /// higher versions, sorts them, and executes their scripts inside an exclusive transaction.
    ///
    /// - Throws: ``MigrationError/emptyMigrationScript(_:)`` if a migration script is empty.
    /// - Throws: ``MigrationError/migrationFailed(_:_:)`` if a migration fails to execute or the
    ///   version update cannot be persisted.
    public func migrate() throws(MigrationError<Version>) {
        #if os(Windows)
            AcquireSRWLockExclusive(&mutex)
            defer { ReleaseSRWLockExclusive(&mutex) }
        #else
            pthread_mutex_lock(&mutex)
            defer { pthread_mutex_unlock(&mutex) }
        #endif
        
        do {
            try super.perform { connection in
                do {
                    try connection.beginTransaction(.exclusive)
                    try migrate(with: connection)
                    try connection.commitTransaction()
                } catch {
                    if !connection.isAutocommit {
                        try connection.rollbackTransaction()
                    }
                    throw error
                }
            }
        } catch let error as MigrationError<Version> {
            throw error
        } catch {
            throw .migrationFailed(nil, error)
        }
    }
}

// MARK: - Private

private extension MigrationService {
    func migrate(with connection: ConnectionProtocol) throws {
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
}
