import Foundation
import DataLiteCore

/// A type that extends connection management with transactional database operations.
///
/// ## Overview
///
/// This type builds on ``ConnectionServiceProtocol`` by adding the ability to execute closures
/// within explicit transactions. Conforming types manage transaction boundaries and ensure that all
/// operations within a transaction are committed or rolled back consistently.
///
/// ## Topics
///
/// ### Performing Operations
///
/// - ``ConnectionServiceProtocol/Perform``
/// - ``perform(in:closure:)``
public protocol DatabaseServiceProtocol: ConnectionServiceProtocol {
    /// Executes a closure inside a transaction if the connection is in autocommit mode.
    ///
    /// If the connection operates in autocommit mode, this method starts a new transaction of the
    /// specified type, executes the closure, and commits the changes on success. If the closure
    /// throws an error, the transaction is rolled back.
    ///
    /// Implementations may attempt to re-establish the connection and reapply the encryption key if
    /// an error indicates a lost or invalid database state (for example, `SQLiteError` with code
    /// `SQLITE_NOTADB`). In such cases, the service can retry the transaction block once after a
    /// successful reconnection. If reconnection fails or is disallowed by the key provider, the
    /// original error is propagated.
    ///
    /// If a transaction is already active, the closure is executed directly without starting a new
    /// transaction.
    ///
    /// - Parameters:
    ///   - transaction: The type of transaction to start.
    ///   - closure: A closure that takes the active connection and returns a result.
    /// - Returns: The value returned by the closure.
    /// - Throws: Errors from connection creation, key application, configuration, transaction
    ///   management, or from the closure itself.
    ///
    /// - Important: The closure may be executed more than once if a reconnection occurs. Ensure it
    ///   performs only database operations and does not produce external side effects (such as
    ///   sending network requests or posting notifications).
    func perform<T>(in transaction: TransactionType, closure: Perform<T>) throws -> T
}
