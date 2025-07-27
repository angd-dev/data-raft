import Testing
import DataLiteCore
@testable import DataRaft

@Suite struct MigrationServiceTests {
    private typealias MigrationService = DataRaft.MigrationService<DatabaseService, VersionStorage>
    
    private var connection: Connection!
    private var migrationService: MigrationService!
    
    init() throws {
        let connection = try Connection(location: .inMemory, options: .readwrite)
        self.connection = connection
        self.migrationService = .init(service: .init(connection: connection), storage: .init())
    }
    
    @Test func addMigration() throws {
        let migration1 = Migration<Int32>(version: 1, byResource: "migration_1", extension: "sql", in: .module)!
        let migration2 = Migration<Int32>(version: 2, byResource: "migration_2", extension: "sql", in: .module)!
        let migration3 = Migration<Int32>(version: 3, byResource: "migration_2", extension: "sql", in: .module)!
        
        #expect(try migrationService.add(migration1) == ())
        #expect(try migrationService.add(migration2) == ())
        
        do {
            try migrationService.add(migration3)
            Issue.record("Expected duplicateMigration error for version \(migration3.version)")
        } catch MigrationService.Error.duplicateMigration(let migration) {
            #expect(migration == migration3)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test func migrate() throws {
        let migration1 = Migration<Int32>(version: 1, byResource: "migration_1", extension: "sql", in: .module)!
        let migration2 = Migration<Int32>(version: 2, byResource: "migration_2", extension: "sql", in: .module)!
        
        try migrationService.add(migration1)
        try migrationService.add(migration2)
        try migrationService.migrate()
        
        #expect(connection.userVersion == 2)
    }
    
    @Test func migrateWithError() throws {
        let migration1 = Migration<Int32>(version: 1, byResource: "migration_1", extension: "sql", in: .module)!
        let migration2 = Migration<Int32>(version: 2, byResource: "migration_2", extension: "sql", in: .module)!
        let migration3 = Migration<Int32>(version: 3, byResource: "migration_3", extension: "sql", in: .module)!
        
        try migrationService.add(migration1)
        try migrationService.add(migration2)
        try migrationService.add(migration3)
        
        do {
            try migrationService.migrate()
            Issue.record("Expected migrationFailed error for version \(migration3.version)")
        } catch MigrationService.Error.migrationFailed(let migration, _) {
            #expect(migration == migration3)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        
        #expect(connection.userVersion == 0)
    }
    
    @Test func migrateWithEmptyMigration() throws {
        let migration1 = Migration<Int32>(version: 1, byResource: "migration_1", extension: "sql", in: .module)!
        let migration2 = Migration<Int32>(version: 2, byResource: "migration_2", extension: "sql", in: .module)!
        let migration4 = Migration<Int32>(version: 4, byResource: "migration_4", extension: "sql", in: .module)!
        
        try migrationService.add(migration1)
        try migrationService.add(migration2)
        try migrationService.add(migration4)
        
        do {
            try migrationService.migrate()
            Issue.record("Expected migrationFailed error for version \(migration4.version)")
        } catch MigrationService.Error.emptyMigrationScript(let migration) {
            #expect(migration == migration4)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        
        #expect(connection.userVersion == 0)
    }
}

private extension MigrationServiceTests {
    struct VersionStorage: DataRaft.VersionStorage {
        typealias Version = Int32
        
        func getVersion(_ connection: Connection) throws -> Version {
            connection.userVersion
        }
        
        func setVersion(_ connection: Connection, _ version: Version) throws {
            connection.userVersion = version
        }
    }
}
