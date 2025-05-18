import Testing
import Foundation

@testable import DataRaft

@Suite struct MigrationTests {
    @Test func initWithURL() {
        let version = DummyVersion(rawValue: 1)
        let url = URL(fileURLWithPath: "/tmp/migration.sql")
        let migration = Migration(version: version, scriptURL: url)
        
        #expect(migration.version == version)
        #expect(migration.scriptURL == url)
    }
    
    @Test func initFromBundle_success() throws {
        let bundle = Bundle.module  // или другой, если тестовая ресурсная цель другая
        let version = DummyVersion(rawValue: 2)
        
        let migration = Migration(
            version: version,
            byResource: "migration_1",
            extension: "sql",
            in: bundle
        )
        
        #expect(migration != nil)
        #expect(migration?.version == version)
        #expect(migration?.scriptURL.lastPathComponent == "migration_1.sql")
    }
    
    @Test func initFromBundle_failure() {
        let version = DummyVersion(rawValue: 3)
        
        let migration = Migration(
            version: version,
            byResource: "NonexistentFile",
            extension: "sql",
            in: .main
        )
        
        #expect(migration == nil)
    }
    
    @Test func hashableEquatable() {
        let version = DummyVersion(rawValue: 5)
        let url = URL(fileURLWithPath: "/tmp/migration.sql")
        
        let migration1 = Migration(version: version, scriptURL: url)
        let migration2 = Migration(version: version, scriptURL: url)
        
        #expect(migration1 == migration2)
        #expect(migration1.hashValue == migration2.hashValue)
    }
}

private extension MigrationTests {
    struct DummyVersion: VersionRepresentable {
        let rawValue: UInt32
        
        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
        
        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}
