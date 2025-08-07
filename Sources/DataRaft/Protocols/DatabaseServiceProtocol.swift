import Foundation
import DataLiteCore

/// A protocol that defines a common interface for working with a database connection.
///
/// `DatabaseServiceProtocol` abstracts the core operations required to safely interact with a
/// SQLite-compatible database. Conforming types provide thread-safe execution of closures with a live
/// `Connection`, optional transaction support, reconnection logic, and pluggable encryption key
/// management via a ``DatabaseServiceKeyProvider``.
///
/// This protocol forms the foundation for safe, modular service layers on top of a database.
///
/// ## Topics
///
/// ### Key Management
///
/// - ``DatabaseServiceKeyProvider``
/// - ``keyProvider``
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
public protocol DatabaseServiceProtocol: AnyObject {
    /// A closure that performs a database operation using an active connection.
    ///
    /// The `Perform<T>` type alias defines a closure signature for a database operation that
    /// receives a live `Connection` and returns a value or throws an error. This enables
    /// callers to express discrete, atomic database operations for execution via
    /// ``perform(_:)`` or ``perform(in:closure:)``.
    ///
    /// - Parameter connection: The active database connection.
    /// - Returns: The result of the operation.
    /// - Throws: Any error thrown during execution of the operation.
    typealias Perform<T> = (Connection) throws -> T
    
    /// The object responsible for providing encryption keys for the database connection.
    ///
    /// When assigned, the key provider will be queried for a key and applied to the current
    /// connection, if available. If key retrieval or application fails, the error is reported
    /// via `databaseService(_:didReceive:)` and not thrown from the setter.
    ///
    /// - Important: Setting this property does not guarantee that the connection becomes available;
    ///   error handling is asynchronous via callback.
    var keyProvider: DatabaseServiceKeyProvider? { get set }
    
    /// Re-establishes the database connection using the stored provider.
    ///
    /// If a `keyProvider` is set, the method attempts to retrieve and apply a key
    /// to the new connection. All errors encountered during connection creation or
    /// key application are thrown. If an error occurs that is related to encryption key
    /// retrieval or application, it is also reported to the `DatabaseServiceKeyProvider`
    /// via its `databaseService(_:didReceive:)` callback.
    ///
    /// - Throws: Any error that occurs during connection creation or key application.
    func reconnect() throws
    
    /// Executes the given closure with a live connection in a thread-safe manner.
    ///
    /// All invocations are serialized to prevent concurrent database access.
    ///
    /// - Parameter closure: The database operation to perform.
    /// - Returns: The result produced by the closure.
    /// - Throws: Any error thrown by the closure.
    func perform<T>(_ closure: Perform<T>) rethrows -> T
    
    /// Executes the given closure within a transaction.
    ///
    /// If no transaction is active, a new transaction of the specified type is started. The closure
    /// is executed atomically: if it succeeds, the transaction is committed; if it throws, the
    /// transaction is rolled back. If a transaction is already active, the closure is executed
    /// without starting a new one.
    ///
    /// - Parameters:
    ///   - transaction: The type of transaction to begin (e.g., `deferred`, `immediate`, `exclusive`).
    ///   - closure: The database operation to perform within the transaction.
    /// - Returns: The result produced by the closure.
    /// - Throws: Any error thrown by the closure or transaction control statements.
    func perform<T>(
        in transaction: TransactionType,
        closure: Perform<T>
    ) rethrows -> T
}
