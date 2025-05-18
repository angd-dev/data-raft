import Foundation
import DataLiteCore

/// A protocol that defines a common interface for working with a database connection.
///
/// Conforming types provide methods for executing closures with a live `Connection`, optionally
/// wrapped in transactions. These closures are guaranteed to execute in a thread-safe and
/// serialized manner. Implementations may also support reconnecting and managing encryption keys.
public protocol DatabaseServiceProtocol: AnyObject {
    /// A closure that performs a database operation using an active connection.
    ///
    /// The `Perform<T>` alias defines the signature for a database operation block
    /// that receives a live `Connection` and either returns a result or throws an error.
    /// It is commonly used to express atomic units of work in ``perform(_:)`` or
    /// ``perform(in:closure:)`` calls.
    ///
    /// - Parameter T: The result type returned by the closure.
    /// - Returns: A value of type `T` produced by the closure.
    /// - Throws: Any error that occurs during execution of the database operation.
    typealias Perform<T> = (Connection) throws -> T
    
    /// The object responsible for providing encryption keys for the database connection.
    ///
    /// When assigned, the key provider will be queried for a new key and applied to the current
    /// connection, if available.
    var keyProvider: DatabaseServiceKeyProvider? { get set }
    
    /// Re-establishes the database connection using the stored provider.
    ///
    /// If a `keyProvider` is set, the returned connection will attempt to apply a new key.
    ///
    /// - Throws: Any error that occurs during connection creation or key application.
    func reconnect() throws
    
    /// Executes the given closure with a live connection.
    ///
    /// - Parameter closure: The operation to execute.
    /// - Returns: The result produced by the closure.
    /// - Throws: Any error thrown during execution.
    func perform<T>(_ closure: Perform<T>) rethrows -> T
    
    /// Executes the given closure within a transaction.
    ///
    /// If no transaction is active, a new one is started and committed or rolled back as needed.
    ///
    /// - Parameters:
    ///   - transaction: The transaction type to begin.
    ///   - closure: The operation to execute within the transaction.
    /// - Returns: The result produced by the closure.
    /// - Throws: Any error thrown by the closure or transaction.
    func perform<T>(
        in transaction: TransactionType,
        closure: Perform<T>
    ) rethrows -> T
}
