import Foundation
import DataLiteCore

/// A service responsible for managing and applying database migrations in a versioned manner.
///
/// `MigrationService` allows registering and executing SQL migrations sequentially based on their
/// version. It ensures that each migration is applied only once and in the correct order, depending
/// on the current version of the database.
///
/// This service is generic over a `VersionStorage` implementation, which defines how the current
/// database version is stored and retrieved. All migration scripts must be uniquely identified by
/// their version and script URL to prevent accidental duplication.
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
/// You can define custom version representations and storage strategies by implementing
/// your own `Version` and `VersionStorage` types.
///
/// The version type must conform to ``VersionRepresentable``, which includes `Equatable`,
/// `Comparable`, `Hashable`, and `Sendable`. This enables sorting and identity checks.
///
/// The storage type must conform to ``VersionStorage`` and define how the version is persisted,
/// such as using a table, pragma, or custom metadata.
///
/// For example, you can:
///
/// - Use a semantic version like `"1.0.0"`
/// - Use an integer (`Int`) for simple numeric progression
/// - Store the version in a custom table (e.g., `schema_version`)
///
/// This allows you to fully control both how versions are compared and where they are stored.
public final class MigrationService<Storage: VersionStorage> {
    /// A type representing the version of the schema, as defined by the underlying storage.
    ///
    /// This alias simplifies access to the version type used throughout the migration service.
    /// The actual type is provided by the associated `Version` type of the `VersionStorage`
    /// implementation.
    public typealias Version = Storage.Version
    
    /// An error that can occur during the migration process.
    public enum Error: Swift.Error {
        /// Indicates that a migration with the same version or script URL was already registered.
        case duplicateMigration(Migration<Version>)
        
        /// Indicates that a migration failed to execute.
        case migrationFailed(Migration<Version>?, Swift.Error)
        
        /// Indicates that a migration script is empty.
        case emptyMigrationScript(Migration<Version>)
    }
    
    // MARK: - Properties
    
    private let service: DatabaseService
    private let storage: Storage
    private var migrations = Set<Migration<Version>>()
    
    // MARK: - Inits
    
    /// Creates a new instance of `MigrationService` with the given version storage and connection.
    ///
    /// - Parameters:
    ///   - storage: An instance that implements how the database version is stored and retrieved.
    ///   - connection: A database connection used to execute migration scripts.
    ///   - queue: An optional dispatch queue used to serialize database access.
    ///            If `nil`, the default internal queue is used.
    public init(
        storage: Storage,
        connection: Connection,
        queue: DispatchQueue? = nil
    ) {
        self.service = .init(
            connection: connection,
            queue: queue
        )
        self.storage = storage
    }
    
    // MARK: - Methods
    
    /// Registers a new migration to be executed during the migration process.
    ///
    /// A migration must have a unique combination of version and script URL.
    ///
    /// - Parameter migration: The migration to register.
    /// - Throws: ``Error/duplicateMigration(_:)`` if the migration has already been registered.
    public func add(_ migration: Migration<Version>) throws {
        guard !migrations.contains(where: {
            $0.version == migration.version
            || $0.scriptURL == migration.scriptURL
        }) else {
            throw Error.duplicateMigration(migration)
        }
        migrations.insert(migration)
    }
    
    /// Applies all pending migrations in the order of ascending version.
    ///
    /// This method checks the current schema version using the provided storage,
    /// selects all migrations with a higher version, and executes them in order.
    /// If any migration fails, the process is aborted and all changes are rolled back.
    ///
    /// After all migrations succeed, the final version is written to the storage.
    ///
    /// - Throws: ``Error/migrationFailed(_:_:)``
    ///   if a migration fails to execute or version update fails.
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
