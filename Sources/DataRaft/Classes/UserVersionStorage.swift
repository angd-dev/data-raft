import Foundation
import DataLiteCore

/// A version storage that persists schema versions in SQLite’s `user_version` field.
///
/// ## Overview
///
/// `UserVersionStorage` provides a lightweight, type-safe implementation of ``VersionStorage`` that
/// stores version data using the SQLite `PRAGMA user_version` mechanism. This approach is simple,
/// efficient, and requires no additional tables.
///
/// The generic ``Version`` type must conform to both ``VersionRepresentable`` and
/// `RawRepresentable`, with `RawValue == UInt32`. This enables conversion between stored integer
/// values and the application’s semantic version type.
///
/// ## Topics
///
/// ### Errors
///
/// - ``Error``
///
/// ### Instance Methods
///
/// - ``getVersion(_:)``
/// - ``setVersion(_:_:)``
public final class UserVersionStorage<
    Version: VersionRepresentable & RawRepresentable
>: Sendable, VersionStorage where Version.RawValue == UInt32 {
    
    /// Errors related to reading or decoding the stored version.
    public enum Error: Swift.Error {
        /// The stored `user_version` value could not be decoded into a valid ``Version``.
        ///
        /// - Parameter value: The invalid raw `UInt32` value.
        case invalidStoredVersion(UInt32)
    }
    
    // MARK: - Inits
    
    /// Creates a new instance of user version storage.
    public init() {}
    
    // MARK: - Version Management
    
    /// Returns the current schema version stored in the `user_version` field.
    ///
    /// Reads the `PRAGMA user_version` value and attempts to decode it into a valid ``Version``.
    /// If decoding fails, this method throws an error.
    ///
    /// - Parameter connection: The active database connection.
    /// - Returns: The decoded version value.
    /// - Throws: ``Error/invalidStoredVersion(_:)`` if the stored value cannot
    ///   be mapped to a valid version case.
    public func getVersion(_ connection: ConnectionProtocol) throws -> Version {
        let raw = UInt32(bitPattern: connection.userVersion)
        guard let version = Version(rawValue: raw) else {
            throw Error.invalidStoredVersion(raw)
        }
        return version
    }
    
    /// Stores the specified schema version in the `user_version` field.
    ///
    /// Updates the SQLite `PRAGMA user_version` value with the raw `UInt32` representation of the
    /// provided ``Version``.
    ///
    /// - Parameters:
    ///   - connection: The active database connection.
    ///   - version: The version to store.
    public func setVersion(_ connection: ConnectionProtocol, _ version: Version) throws {
        connection.userVersion = .init(bitPattern: version.rawValue)
    }
}
