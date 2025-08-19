import Foundation
import DataLiteCore

/// A protocol for a database service.
///
/// `DatabaseServiceProtocol` defines the core capabilities required for
/// reliable interaction with a database. Conforming implementations provide
/// execution of client closures with a live connection, transaction wrapping,
/// reconnection logic, and flexible encryption key management.
///
/// This enables building safe and extensible service layers on top of
/// a database.
///
/// ## Topics
///
/// ### Key Management
///
/// - ``DatabaseServiceKeyProvider``
/// - ``keyProvider``
/// - ``applyKeyProvider()``
///
/// ### Connection Management
///
/// - ``reconnect()``
///
/// ### Database Operations
///
/// - ``Perform``
/// - ``perform(_:)``
/// - ``perform(in:closure:)``
public protocol DatabaseServiceProtocol: AnyObject, Sendable {
    /// A closure executed with an active database connection.
    ///
    /// Used by the service to safely provide access to `Connection`
    /// within the appropriate execution context.
    ///
    /// - Parameter connection: The active database connection.
    /// - Returns: The value returned by the closure.
    /// - Throws: An error if the closure execution fails.
    typealias Perform<T> = (Connection) throws -> T
    
    /// The encryption key provider for the database service.
    ///
    /// Enables external management of encryption keys.
    /// When set, the service can request a key when establishing or
    /// restoring a connection, and can also notify about errors
    /// encountered while applying a key.
    var keyProvider: DatabaseServiceKeyProvider? { get set }
    
    /// Applies the encryption key from the current provider.
    ///
    /// Calls the configured ``keyProvider`` to obtain a key and applies
    /// it to the active connection. If the key is unavailable or an
    /// error occurs while applying it, the method throws.
    ///
    /// - Throws: An error if the key cannot be retrieved or applied.
    func applyKeyProvider() throws
    
    /// Reopens the database connection.
    ///
    /// Creates a new connection using the provider and applies the
    /// encryption key if ``keyProvider`` is set. Typically used when
    /// the previous connection has become invalid.
    ///
    /// - Throws: An error if the new connection cannot be created or the key cannot be applied.
    func reconnect() throws
    
    /// Executes the given closure with an active connection.
    ///
    /// The closure receives the connection and may perform any
    /// database operations within the current context.
    ///
    /// - Parameter closure: The closure that accepts a connection.
    /// - Returns: The value returned by the closure.
    /// - Throws: An error if one occurs during closure execution.
    func perform<T>(_ closure: Perform<T>) rethrows -> T
    
    /// Executes the given closure within a transaction.
    ///
    /// If the connection is in autocommit mode, the method automatically
    /// begins a transaction, executes the closure, and commits the changes.
    /// In case of failure, the transaction is rolled back.
    ///
    /// - Parameters:
    ///   - transaction: The type of transaction to begin.
    ///   - closure: The closure that accepts a connection.
    /// - Returns: The value returned by the closure.
    /// - Throws: An error if one occurs during closure execution.
    func perform<T>(in transaction: TransactionType, closure: Perform<T>) rethrows -> T
}
