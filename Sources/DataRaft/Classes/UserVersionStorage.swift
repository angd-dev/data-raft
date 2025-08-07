import Foundation
import DataLiteCore

/// A database version storage that uses the `user_version` field.
///
/// This class implements ``VersionStorage`` by storing version information
/// in the SQLite `PRAGMA user_version` field. It provides a lightweight,
/// type-safe way to persist versioning data in a database.
///
/// The generic `Version` type must conform to both ``VersionRepresentable``
/// and `RawRepresentable`, where `RawValue == UInt32`. This allows
/// converting between stored integer values and semantic version types
/// defined by the application.
public final class UserVersionStorage<
    Version: VersionRepresentable & RawRepresentable
>: Sendable, VersionStorage where Version.RawValue == UInt32 {
    /// Errors related to reading or decoding the version.
    public enum Error: Swift.Error {
        /// The stored `user_version` could not be decoded into a valid `Version` case.
        case invalidStoredVersion(UInt32)
    }
    
    // MARK: - Inits
    
    /// Creates a new user version storage instance.
    public init() {}
    
    // MARK: - Methods
    
    /// Returns the current version stored in the `user_version` field.
    ///
    /// This method reads the `PRAGMA user_version` value and attempts to
    /// decode it into a valid `Version` value. If the stored value is not
    /// recognized, it throws an error.
    ///
    /// - Parameter connection: The database connection.
    /// - Returns: A decoded version value of type `Version`.
    /// - Throws: ``Error/invalidStoredVersion(_:)`` if the stored value
    ///   cannot be mapped to a valid `Version` instance.
    public func getVersion(
        _ connection: Connection
    ) throws -> Version {
        let raw = UInt32(bitPattern: connection.userVersion)
        guard let version = Version(rawValue: raw) else {
            throw Error.invalidStoredVersion(raw)
        }
        return version
    }
    
    /// Stores the given version in the `user_version` field.
    ///
    /// This method updates the `PRAGMA user_version` field
    /// with the raw `UInt32` value of the provided `Version`.
    ///
    /// - Parameters:
    ///   - connection: The database connection.
    ///   - version: The version to store.
    public func setVersion(
        _ connection: Connection,
        _ version: Version
    ) throws {
        connection.userVersion = .init(
            bitPattern: version.rawValue
        )
    }
}
