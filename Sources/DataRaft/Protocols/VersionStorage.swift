import Foundation
import DataLiteCore

/// ## Topics
///
/// ### Associated Types
///
/// - ``Version``
///
/// ### Instance Methods
///
/// - ``prepare(_:)``
/// - ``getVersion(_:)``
/// - ``setVersion(_:_:)``
public protocol VersionStorage {
    associatedtype Version: VersionRepresentable
    
    func prepare(_ connection: Connection) throws
    func getVersion(_ connection: Connection) throws -> Version
    func setVersion(_ connection: Connection, _ version: Version) throws
}

public extension VersionStorage {
    func prepare(_ connection: Connection) throws {}
}
