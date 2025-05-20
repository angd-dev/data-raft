import Foundation
import DataLiteCore

public class UserVersionStorage<
    Version: VersionRepresentable & RawRepresentable
>: VersionStorage where Version.RawValue == UInt32 {
    public enum Error: Swift.Error {
        case invalidStoredVersion(UInt32)
    }
    
    // MARK: - Inits
    
    public init() {}
    
    // MARK: - Methods
    
    public func getVersion(
        _ connection: Connection
    ) throws -> Version {
        let raw = UInt32(bitPattern: connection.userVersion)
        guard let version = Version(rawValue: raw) else {
            throw Error.invalidStoredVersion(raw)
        }
        return version
    }
    
    public func setVersion(
        _ connection: Connection,
        _ version: Version
    ) throws {
        connection.userVersion = .init(
            bitPattern: version.rawValue
        )
    }
}
