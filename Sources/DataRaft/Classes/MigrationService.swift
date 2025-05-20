import Foundation
import DataLiteCore

public final class MigrationService<Storage: VersionStorage>: DatabaseService {
    public typealias Version = Storage.Version
    
    public enum Error: Swift.Error {
        case duplicateMigration(version: Version, url: URL)
        case migrationFailed(version: Version, url: URL, error: Swift.Error)
    }
    
    // MARK: - Properties
    
    private let storage: Storage
    private var migrations = Set<Migration<Version>>()
    
    // MARK: - Inits
    
    public init(
        storage: Storage,
        connection: Connection,
        queue: DispatchQueue? = nil
    ) {
        self.storage = storage
        super.init(connection: connection, queue: queue)
    }
    
    // MARK: - Methods
    
    public func add(_ migration: Migration<Version>) throws {
        guard !migrations.contains(where: {
            $0.version == migration.version
            || $0.scriptURL == migration.scriptURL
        }) else {
            throw Error.duplicateMigration(
                version: migration.version,
                url: migration.scriptURL
            )
        }
        migrations.insert(migration)
    }
    
    public func migrate() throws {
        try perform(in: .exclusive) { connection in
            try storage.prepare(connection)
            let version = try storage.getVersion(connection)
            
            try migrations.filter {
                $0.version > version
            }.sorted {
                $0.version < $1.version
            }.forEach {
                do {
                    let script = try SQLScript(contentsOf: $0.scriptURL)
                    try connection.execute(sql: script)
                } catch {
                    throw Error.migrationFailed(
                        version: $0.version,
                        url: $0.scriptURL,
                        error: error
                    )
                }
                try storage.setVersion(connection, $0.version)
            }
        }
    }
}
