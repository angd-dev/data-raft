import Foundation
import DataLiteCore

/// A protocol for providing encryption keys to database services.
///
/// `DatabaseServiceKeyProvider` allows you to externalize the logic for supplying encryption
/// keys to `DatabaseService` instances. This separation enables flexible and secure
/// key management strategies, such as per-user keys, passphrase rotation, or
/// hardware-backed protection.
///
/// The key provider is assigned to a `DatabaseService` instance to support
/// automatic key application during initialization or reconnection.
///
/// You can also implement runtime key unlocking (e.g., via Secure Enclave or biometrics)
/// by throwing errors when the key is unavailable or access is denied.
public protocol DatabaseServiceKeyProvider: AnyObject {
    /// Returns the encryption key for the given database service instance.
    ///
    /// Implementers can return a static key, derive it from service metadata,
    /// or fetch it from secure storage. If the key is unavailable, this method
    /// may throw an error to signal failure.
    ///
    /// - Parameter service: The database service requesting the key.
    /// - Returns: A `Connection.Key` representing the encryption key.
    /// - Throws: An error if the key cannot be retrieved.
    func databaseServiceKey(_ service: DatabaseService) throws -> Connection.Key
}
