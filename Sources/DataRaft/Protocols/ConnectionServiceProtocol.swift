import Foundation
import DataLiteCore

/// A type that manages the lifecycle of a database connection.
///
/// ## Overview
///
/// Conforming types implement the mechanisms required to open, configure, reconnect, and safelyuse
/// a database connection across multiple threads or tasks. This abstraction allows higher-level
/// services to execute operations without dealing with low-level connection handling.
///
/// ## Topics
///
/// ### Key Management
///
/// - ``ConnectionServiceKeyProvider``
/// - ``keyProvider``
///
/// ### Connection Lifecycle
///
/// - ``setNeedsReconnect()``
///
/// ### Performing Operations
///
/// - ``Perform``
/// - ``perform(_:)``
public protocol ConnectionServiceProtocol: AnyObject, Sendable {
    /// A closure type that performs an operation using an active database connection.
    ///
    /// - Parameter connection: The active database connection used for the operation.
    /// - Returns: The result produced by the closure.
    /// - Throws: Any error thrown by the closure or connection layer.
    typealias Perform<T> = (ConnectionProtocol) throws -> T
    
    /// The provider responsible for supplying encryption keys to the service.
    var keyProvider: ConnectionServiceKeyProvider? { get set }
    
    /// Marks the service as requiring reconnection before the next operation.
    ///
    /// The reconnection behavior depends on the key provider’s implementation of
    /// ``ConnectionServiceKeyProvider/connectionService(shouldReconnect:)``.
    ///
    /// - Returns: `true` if the reconnection flag was set; otherwise, `false`.
    @discardableResult
    func setNeedsReconnect() -> Bool
    
    /// Executes a closure within the context of an active database connection.
    ///
    /// Implementations ensure that a valid connection is available before executing the operation.
    /// If the connection is not available or fails, this method throws an error.
    ///
    /// - Parameter closure: The operation to perform using the connection.
    /// - Returns: The result produced by the closure.
    /// - Throws: Any error thrown by the closure or the underlying connection.
    func perform<T>(_ closure: Perform<T>) throws -> T
}
