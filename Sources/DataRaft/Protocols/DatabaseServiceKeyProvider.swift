import Foundation
import DataLiteCore

/// A protocol for supplying encryption keys to `DatabaseService` instances.
///
/// `DatabaseServiceKeyProvider` encapsulates all responsibilities for managing encryption keys
/// for one or more `DatabaseService` instances. It allows a database service to delegate key
/// retrieval, secure storage, rotation, and access control, enabling advanced security strategies
/// such as per-user key derivation, hardware-backed keys, biometric authentication, or ephemeral
/// in-memory secrets.
///
/// The provider is queried automatically by the database service whenever a new connection
/// is created or re-established (for example, during service initialization, after a reconnect,
/// or when the service requests a key rotation).
///
/// Error handling and diagnostics related specifically to encryption or key operations
/// (such as when a key is unavailable, authentication is denied, or decryption fails)
/// are reported to the provider via the optional ``databaseService(_:didReceive:)`` callback.
/// The provider is **not** notified of generic database or connection errors unrelated to
/// encryption.
///
/// - Important: This protocol is **exclusively** for cryptographic key management.
///   It must not be used for generic database error handling or for concerns unrelated to
///   encryption, authorization, or key lifecycle.
///
/// ## Key Availability
///
/// There are two distinct scenarios for returning a key:
///
/// - **No Encryption Needed:**
///   Return `nil` if the target database does not require encryption (i.e., should be opened
///   in plaintext mode). This is not an error; the database service will attempt to open the
///   database without a key. If the database is in fact encrypted, this will result in a
///   decryption error at the SQLite level (e.g., `SQLITE_NOTADB`), which is handled by the
///   database service as a normal failure.
///
/// - **Key Temporarily Unavailable:**
///   Also return `nil` if the key is *temporarily* unavailable for any reason (for example,
///   the user has not yet authenticated, the device is locked, a remote key is still loading,
///   or UI authorization has not been granted).
///   Returning `nil` in this case means the database service will not attempt to open
///   the database with a key. This will not trigger an error callback.
///   When the key later becomes available (for example, after user authentication or
///   successful network retrieval), **the provider is responsible for calling**
///   ``DatabaseService/reconnect()`` on the service to re-attempt the operation with the key.
///
/// - **Error Situations:**
///   Only throw an error if a *permanent* or *unexpected* failure occurs (for example,
///   a hardware security error, a fatal storage problem, or a cryptographic failure
///   that cannot be resolved by waiting or user action).
///   Thrown errors will be reported to the provider via the error callback, and may be
///   surfaced to the UI or logs.
///
/// - Tip: Never throw for temporary unavailability (such as "user has not unlocked" or
///   "still waiting for user action")—just return `nil` in these cases.
///   Use thrown errors only for non-recoverable or unexpected failures.
///
/// ## Error Callback
///
/// The method ``databaseService(_:didReceive:)`` will be called only for errors thrown by
/// ``databaseServiceKey(_:)`` or by the key application process (such as if the key fails
/// to decrypt the database).
/// It will *not* be called for generic database or connection errors.
///
/// Implement this method if you wish to log, recover from, or respond to permanent key-related
/// failures (such as prompting the user, resetting state, or displaying errors).
public protocol DatabaseServiceKeyProvider: AnyObject {
    /// Returns the encryption key to be applied to the given database service.
    ///
    /// This method is invoked by the `DatabaseService` during connection initialization,
    /// reconnection, or explicit key rotation. Implementations may return a static key,
    /// derive it from external data, fetch it from secure hardware, or perform required
    /// user authentication.
    ///
    /// - Parameter service: The requesting database service.
    /// - Returns: A `Connection.Key` representing the encryption key, or `nil` if encryption is
    ///   not required for this database or the key is temporarily unavailable. Returning `nil`
    ///   will cause the database service to attempt opening the database in plaintext mode.
    ///   If the database is actually encrypted, access will fail with a decryption error.
    /// - Throws: Only throw for unrecoverable or unexpected errors (such as hardware failure,
    ///   fatal storage issues, or irrecoverable cryptographic errors). Do **not** throw for
    ///   temporary unavailability; instead, return `nil` and call ``DatabaseService/reconnect()``
    ///   later when the key becomes available.
    ///
    /// - Note: This method may be called multiple times during the lifecycle of a service,
    ///   including after a failed decryption attempt or key rotation event.
    func databaseServiceKey(_ service: DatabaseService) throws -> Connection.Key?
    
    /// Notifies the provider that the database service encountered an error
    /// related to key retrieval or application.
    ///
    /// This method is called **only** when the service fails to retrieve or apply an
    /// encryption key (e.g., if ``databaseServiceKey(_:)`` throws, or if the key fails
    /// to decrypt the database due to a password/key mismatch).
    ///
    /// Use this callback to report diagnostics, trigger recovery logic, prompt the user
    /// for authentication, or update internal state.
    /// By default, this method does nothing; implement it only if you need to respond
    /// to key-related failures.
    ///
    /// - Parameters:
    ///   - service: The database service reporting the error.
    ///   - error: The error encountered during key retrieval or application.
    func databaseService(_ service: DatabaseService, didReceive error: Error)
    
    /// Informs the service whether it should attempt to reconnect automatically.
    ///
    /// Return `true` if the service should retry connecting (for example, if the key may
    /// become available shortly). By default, returns `false`.
    ///
    /// - Parameter service: The database service.
    /// - Returns: `true` to retry, `false` to abort.
    func databaseServiceShouldReconnect(_ service: DatabaseService) -> Bool
}

public extension DatabaseServiceKeyProvider {
    /// Default no-op implementation for key-related error reporting.
    func databaseService(_ service: DatabaseService, didReceive error: Error) {}
    
    /// Default implementation disables automatic reconnect attempts.
    func databaseServiceShouldReconnect(_ service: DatabaseService) -> Bool {
        false
    }
}
