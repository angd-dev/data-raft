import Foundation
import Testing
import DataLiteC
import DataLiteCore
import DataRaft

class DatabaseServiceTests: DatabaseServiceKeyProvider, @unchecked Sendable {
    private let keyOne = Connection.Key.rawKey(Data([
        0xe8, 0xd7, 0x92, 0xa2, 0xa1, 0x35, 0x56, 0xc0,
        0xfd, 0xbb, 0x2f, 0x91, 0xe8, 0x0b, 0x4b, 0x2a,
        0xa2, 0xd7, 0x78, 0xe9, 0xe5, 0x87, 0x05, 0xb4,
        0xe2, 0x1a, 0x42, 0x74, 0xee, 0xbc, 0x4c, 0x06
    ]))
    
    private let keyTwo = Connection.Key.rawKey(Data([
        0x9f, 0x45, 0x23, 0xbf, 0xfe, 0x11, 0x3e, 0x79,
        0x42, 0x21, 0x48, 0x7c, 0xb6, 0xb1, 0xd5, 0x09,
        0x34, 0x5f, 0xcb, 0x53, 0xa3, 0xdd, 0x8e, 0x41,
        0x95, 0x27, 0xbb, 0x4e, 0x6e, 0xd8, 0xa7, 0x05
    ]))
    
    private let fileURL: URL
    private let service: DatabaseService
    
    private lazy var currentKey = keyOne
    
    init() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        
        let service = DatabaseService(provider: {
            try Connection(
                path: fileURL.path,
                options: [.create, .readwrite]
            )
        })
        
        self.fileURL = fileURL
        self.service = service
        self.service.keyProvider = self
        
        try self.service.perform { connection in
            try connection.execute(sql: """
            CREATE TABLE IF NOT EXISTS Item (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL
            )
            """)
        }
    }
    
    deinit {
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    func databaseService(keyFor service: any DatabaseServiceProtocol) throws -> Connection.Key {
        currentKey
    }
    
    func databaseService(shouldReconnect service: any DatabaseServiceProtocol) -> Bool {
        true
    }
}

extension DatabaseServiceTests {
    @Test func testSuccessPerformTransaction() throws {
        try service.perform(in: .deferred) { connection in
            #expect(connection.isAutocommit == false)
            let stmt = try connection.prepare(
                sql: "INSERT INTO Item (name) VALUES (?)",
                options: []
            )
            try stmt.bind("Book", at: 1)
            try stmt.step()
        }
        try service.perform { connection in
            let stmt = try connection.prepare(
                sql: "SELECT COUNT(*) FROM Item",
                options: []
            )
            try stmt.step()
            #expect(connection.isAutocommit)
            #expect(stmt.columnValue(at: 0) == 1)
        }
    }
    
    @Test func testNestedPerformTransaction() throws {
        try service.perform(in: .deferred) { _ in
            try service.perform(in: .deferred) { connection in
                #expect(connection.isAutocommit == false)
                let stmt = try connection.prepare(
                    sql: "INSERT INTO Item (name) VALUES (?)",
                    options: []
                )
                try stmt.bind("Book", at: 1)
                try stmt.step()
            }
        }
        try service.perform { connection in
            let stmt = try connection.prepare(
                sql: "SELECT COUNT(*) FROM Item",
                options: []
            )
            try stmt.step()
            #expect(connection.isAutocommit)
            #expect(stmt.columnValue(at: 0) == 1)
        }
    }
    
    @Test func testRollbackPerformTransaction() throws {
        struct DummyError: Error, Equatable {}
        #expect(throws: DummyError(), performing: {
            try self.service.perform(in: .deferred) { connection in
                #expect(connection.isAutocommit == false)
                let stmt = try connection.prepare(
                    sql: "INSERT INTO Item (name) VALUES (?)",
                    options: []
                )
                try stmt.bind("Book", at: 1)
                try stmt.step()
                throw DummyError()
            }
        })
        try service.perform { connection in
            let stmt = try connection.prepare(
                sql: "SELECT COUNT(*) FROM Item",
                options: []
            )
            try stmt.step()
            #expect(connection.isAutocommit)
            #expect(stmt.columnValue(at: 0) == 0)
        }
    }
    
    @Test func testSuccessReconnectPerformTransaction() throws {
        let connection = try Connection(
            path: fileURL.path,
            options: [.readwrite]
        )
        try connection.apply(currentKey)
        try connection.rekey(keyTwo)
        currentKey = keyTwo
        
        try service.perform(in: .deferred) { connection in
            #expect(connection.isAutocommit == false)
            let stmt = try connection.prepare(
                sql: "INSERT INTO Item (name) VALUES (?)",
                options: []
            )
            try stmt.bind("Book", at: 1)
            try stmt.step()
        }
        try service.perform { connection in
            let stmt = try connection.prepare(
                sql: "SELECT COUNT(*) FROM Item",
                options: []
            )
            try stmt.step()
            #expect(stmt.columnValue(at: 0) == 1)
        }
    }
    
    @Test func testFailReconnectPerformTransaction() throws {
        let connection = try Connection(
            path: fileURL.path,
            options: [.readwrite]
        )
        try connection.apply(currentKey)
        try connection.rekey(keyTwo)
        let error = Connection.Error(
            code: SQLITE_NOTADB,
            message: "file is not a database"
        )
        #expect(throws: error, performing: {
            try self.service.perform(in: .deferred) { connection in
                #expect(connection.isAutocommit == false)
                let stmt = try connection.prepare(
                    sql: "INSERT INTO Item (name) VALUES (?)",
                    options: []
                )
                try stmt.bind("Book", at: 1)
                try stmt.step()
            }
        })
        let stmt = try connection.prepare(
            sql: "SELECT COUNT(*) FROM Item",
            options: []
        )
        try stmt.step()
        #expect(connection.isAutocommit)
        #expect(stmt.columnValue(at: 0) == 0)
    }
}
