import Foundation
import DataLiteCore

/// A type that provides encryption keys to a database connection service.
///
/// ## Overview
///
/// This type manages how encryption keys are obtained and applied when establishing or restoring a
/// connection. Implementations can use static, dynamic, hardware-backed, or biometric key sources.
///
/// - The service requests a key when establishing or restoring a connection.
/// - If decryption fails, the service may ask whether it should attempt to reconnect.
/// - If applying a key fails (for example, the key is invalid or ``connectionService(keyFor:)``
///   throws), the error is reported through ``connectionService(_:didReceive:)``.
///
/// - Important: The provider does not receive general database errors.
///
/// ## Topics
///
/// ### Providing Keys and Handling Errors
///
/// - ``connectionService(keyFor:)``
/// - ``connectionService(shouldReconnect:)``
/// - ``connectionService(_:didReceive:)``
public protocol ConnectionServiceKeyProvider: AnyObject, Sendable {
    /// Returns the encryption key for the specified database service.
    ///
    /// - Parameter service: The service requesting the key.
    /// - Returns: The encryption key.
    /// - Throws: An error if the key cannot be retrieved.
    func connectionService(keyFor service: ConnectionServiceProtocol) throws -> Connection.Key
    
    /// Indicates whether the service should attempt to reconnect if applying the key fails.
    ///
    /// - Parameter service: The database service.
    /// - Returns: `true` to attempt reconnection. Defaults to `false`.
    func connectionService(shouldReconnect service: ConnectionServiceProtocol) -> Bool
    
    /// Notifies the provider of an error that occurred during key retrieval or application.
    ///
    /// - Parameters:
    ///   - service: The database service reporting the error.
    ///   - error: The error encountered during key retrieval or application.
    func connectionService(_ service: ConnectionServiceProtocol, didReceive error: Error)
}
