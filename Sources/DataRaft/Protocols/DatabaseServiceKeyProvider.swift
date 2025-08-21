import Foundation
import DataLiteCore

/// A protocol for providing encryption keys to a database service.
///
/// `DatabaseServiceKeyProvider` is responsible for managing encryption keys used
/// by a database service. This makes it possible to implement different strategies for storing
/// and retrieving keys: static, dynamic, hardware-backed, biometric, and others.
///
/// - The service requests a key when establishing or restoring a connection.
/// - If decryption fails, the service may ask the provider whether it should attempt to reconnect.
/// - If applying a key fails (for example, the key does not match or the
///   ``databaseService(keyFor:)`` method throws an error), this error is reported
///   to the provider through ``databaseService(_:didReceive:)``.
///
/// - Important: The provider does not receive notifications about general database errors.
///
/// ## Topics
///
/// ### Instance Methods
///
/// - ``databaseService(keyFor:)``
/// - ``databaseService(shouldReconnect:)``
/// - ``databaseService(_:didReceive:)``
public protocol DatabaseServiceKeyProvider: AnyObject, Sendable {
    /// Returns the encryption key for the specified database service.
    ///
    /// This method must either return a valid encryption key or throw an error if
    /// the key cannot be retrieved.
    ///
    /// - Parameter service: The service requesting the key.
    /// - Returns: The encryption key.
    /// - Throws: An error if the key cannot be retrieved.
    func databaseService(keyFor service: DatabaseServiceProtocol) throws -> Connection.Key
    
    /// Indicates whether the service should attempt to reconnect if applying the key fails.
    ///
    /// - Parameter service: The database service.
    /// - Returns: `true` to attempt reconnection. Defaults to `false`.
    func databaseService(shouldReconnect service: DatabaseServiceProtocol) -> Bool
    
    /// Notifies the provider of an error that occurred while retrieving or applying the key.
    ///
    /// - Parameters:
    ///   - service: The database service reporting the error.
    ///   - error: The error encountered during key retrieval or application.
    func databaseService(_ service: DatabaseServiceProtocol, didReceive error: Error)
}

public extension DatabaseServiceKeyProvider {
    func databaseService(shouldReconnect service: DatabaseServiceProtocol) -> Bool { false }
    func databaseService(_ service: DatabaseServiceProtocol, didReceive error: Error) {}
}
