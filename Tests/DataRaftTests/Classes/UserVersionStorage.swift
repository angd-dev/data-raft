import Testing
import DataLiteCore
@testable import DataRaft

@Suite struct UserVersionStorageTests {
    private var connection: Connection!
    
    init() throws {
        connection = try .init(location: .inMemory, options: .readwrite)
    }
    
    @Test func getVersion() throws {
        connection.userVersion = 123
        let storage = UserVersionStorage<Version>()
        let version = try storage.getVersion(connection)
        #expect(version == Version(rawValue: 123))
    }
    
    @Test func getVersionWithError() {
        connection.userVersion = 123
        let storage = UserVersionStorage<NilVersion>()
        do {
            _ = try storage.getVersion(connection)
            Issue.record("Expected failure for invalid stored version")
        } catch UserVersionStorage<NilVersion>.Error.invalidStoredVersion(let version) {
            #expect(version == UInt32(bitPattern: connection.userVersion))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test func setVersion() throws {
        let storage = UserVersionStorage<Version>()
        let version = Version(rawValue: 456)
        try storage.setVersion(connection, version)
        #expect(connection.userVersion == 456)
    }
}

private extension UserVersionStorageTests {
    struct Version: RawRepresentable, VersionRepresentable, Equatable {
        let rawValue: UInt32
        
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    struct NilVersion: RawRepresentable, VersionRepresentable {
        let rawValue: UInt32
        
        init?(rawValue: UInt32) {
            return nil
        }
        
        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}
