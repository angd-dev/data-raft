import Foundation
import DataLiteCore

/// A protocol for supplying encryption keys to `DatabaseService` instances.
///
/// `DatabaseServiceKeyProvider` allows database services to delegate the responsibility of
/// retrieving, managing, and applying encryption keys. This enables separation of concerns
/// and allows for advanced strategies such as per-user key derivation, secure hardware-backed
/// storage, or biometric access control.
///
/// When assigned to a `DatabaseService`, the provider is queried automatically whenever a
/// connection is created or re-established (e.g., during service initialization or reconnect).
///
/// You can also implement error handling or diagnostics via the optional
/// ``databaseService(_:didReceive:)`` method.
///
/// - Tip: You may throw from ``databaseServiceKey(_:)`` to indicate that the key is temporarily
///   unavailable or access is denied.
public protocol DatabaseServiceKeyProvider: AnyObject {
    /// Returns the encryption key to be applied to the given database service.
    ///
    /// This method is invoked by the `DatabaseService` during initialization or reconnection
    /// to retrieve the encryption key that should be applied to the new connection.
    ///
    /// Implementations may return a static key, derive it from metadata, or load it from
    /// secure storage. If the key is unavailable (e.g., user not authenticated, system locked),
    /// this method may throw to indicate failure.
    ///
    /// - Parameter service: The requesting database service.
    /// - Returns: A `Connection.Key` representing the encryption key.
    /// - Throws: Any error indicating that the key cannot be retrieved.
    func databaseServiceKey(_ service: DatabaseService) throws -> Connection.Key

    /// Notifies the provider that the database service encountered an error while applying a key.
    ///
    /// This method is called when the service fails to retrieve or apply the encryption key.
    /// You can use it to report diagnostics, attempt recovery, or update internal state.
    ///
    /// The default implementation is a no-op.
    ///
    /// - Parameters:
    ///   - service: The database service reporting the error.
    ///   - error: The error encountered during key retrieval or application.
    func databaseService(_ service: DatabaseService, didReceive error: Error)
}

public extension DatabaseServiceKeyProvider {
    /// Default no-op implementation of error handling callback.
    ///
    /// This allows conforming types to ignore the error reporting mechanism
    /// if they do not need to respond to key failures.
    func databaseService(_ service: DatabaseService, didReceive error: Error) {}
}
