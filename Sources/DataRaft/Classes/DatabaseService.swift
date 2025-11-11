import Foundation
import DataLiteCore
import DataLiteC

/// A base database service that handles transactions and posts change notifications.
///
/// ## Overview
///
/// `DatabaseService` provides a lightweight transactional layer for performing database operations
/// within a thread-safe execution context. It automatically detects modifications to the database
/// and posts a ``databaseDidChange`` notification database updates, allowing observers to react to
/// updates.
///
/// This class is intended to be subclassed by higher-level data managers that encapsulate domain
/// logic while relying on consistent connection and transaction handling.
///
/// ## Usage
///
/// ```swift
/// final class NoteService: DatabaseService {
///     func insertNote(_ text: String) throws {
///         try perform(in: .deferred) { connection in
///             let sql = "INSERT INTO notes (text) VALUES (?)"
///             let stmt = try connection.prepare(sql: sql)
///             try stmt.bind(text, at: 0)
///             try stmt.step()
///         }
///     }
/// }
///
/// let connection = try Connection(location: .inMemory, options: [])
/// let service = NoteService(connection: connection)
/// try service.insertNote("Hello, world!")
/// ```
///
/// ## Topics
///
/// ### Initializers
///
/// - ``ConnectionService/ConnectionProvider``
/// - ``ConnectionService/ConnectionConfig``
/// - ``init(provider:config:queue:center:)``
/// - ``init(provider:config:queue:)``
///
/// ### Performing Operations
///
/// - ``ConnectionServiceProtocol/Perform``
/// - ``perform(_:)``
/// - ``perform(in:closure:)``
///
/// ### Connection Delegate
///
/// - ``connection(_:didUpdate:)``
/// - ``connectionWillCommit(_:)``
/// - ``connectionDidRollback(_:)``
///
/// ### Notifications
///
/// - ``databaseDidChange``
open class DatabaseService:
    ConnectionService,
    DatabaseServiceProtocol,
    ConnectionDelegate,
    @unchecked Sendable
{
    // MARK: - Properties
    
    private let center: NotificationCenter
    
    /// Notification posted after the database content changes with this service.
    public static let databaseDidChange = Notification.Name("DatabaseService.databaseDidChange")
    
    // MARK: - Inits
    
    /// Creates a database service with a specified notification center.
    ///
    /// Configures an internal serial queue for thread-safe access to the database. The connection
    /// itself is not created during initialization — it is established lazily on first use (for
    /// example, inside ``perform(_:)``).
    ///
    /// The internal queue is created with QoS `.utility`. If `queue` is provided, it becomes the
    /// target of the internal queue.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a new database connection.
    ///   - config: An optional configuration closure called after the connection is established and
    ///     the encryption key is applied.
    ///   - queue: An optional target queue for the internal one.
    ///   - center: The notification center used to post database change notifications.
    public init(
        provider: @escaping ConnectionProvider,
        config: ConnectionConfig? = nil,
        queue: DispatchQueue? = nil,
        center: NotificationCenter
    ) {
        self.center = center
        super.init(provider: provider, config: config, queue: queue)
    }
    
    /// Creates a database service using the default database notification center.
    ///
    /// Configures an internal serial queue for thread-safe access to the database. The connection
    /// itself is not created during initialization — it is established lazily on first use (for
    /// example, inside ``perform(_:)``).
    ///
    /// The service posts change notifications through ``Foundation/NotificationCenter/databaseCenter``,
    /// which provides a shared channel for observing database events across the application.
    ///
    /// The internal queue is created with QoS `.utility`. If `queue` is provided, it becomes the
    /// target of the internal queue.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a new database connection.
    ///   - config: An optional configuration closure called after the connection is established and
    ///     the encryption key is applied.
    ///   - queue: An optional target queue for the internal one.
    public required init(
        provider: @escaping ConnectionProvider,
        config: ConnectionConfig? = nil,
        queue: DispatchQueue? = nil
    ) {
        self.center = .databaseCenter
        super.init(provider: provider, config: config, queue: queue)
    }
    
    // MARK: - Performing Operations
    
    /// Executes a closure within the context of a managed database connection.
    ///
    /// Runs the operation on the service’s internal queue and ensures that the connection is valid
    /// before use. If the connection is unavailable or fails during execution, this method throws
    /// an error.
    ///
    /// After the closure completes, if the database content has changed, the service posts a
    /// ``databaseDidChange`` notification through its configured notification center.
    ///
    /// - Parameter closure: The operation to perform using the connection.
    /// - Returns: The result produced by the closure.
    /// - Throws: An error thrown by the closure or the connection.
    public override func perform<T>(_ closure: Perform<T>) throws -> T {
        try super.perform { connection in
            let changes = connection.totalChanges
            defer {
                if changes != connection.totalChanges {
                    center.post(name: Self.databaseDidChange, object: self)
                }
            }
            return try closure(connection)
        }
    }
    
    /// Executes a closure inside a transaction when the connection operates in autocommit mode.
    ///
    /// The method begins the requested `TransactionType`, runs the closure, and commits the
    /// transaction on success. Failures trigger a rollback. If the SQLite engine reports
    /// `SQLITE_NOTADB` and the key provider allows reconnection, the service re-establishes the
    /// connection and retries the closure once, mirroring the behavior described in
    /// ``DatabaseServiceProtocol``.
    ///
    /// - Parameters:
    ///   - transaction: The type of transaction to start (for example, `.deferred`).
    ///   - closure: The work to run while the transaction is active.
    /// - Returns: The value returned by the closure.
    /// - Throws: Errors from the closure, transaction handling, or connection management.
    ///
    /// - Important: The closure may be executed more than once if a reconnection occurs. Ensure it
    ///   performs only database operations and does not produce external side effects (such as
    ///   sending network requests or posting notifications).
    public func perform<T>(
        in transaction: TransactionType,
        closure: Perform<T>
    ) throws -> T {
        try perform { connection in
            guard connection.isAutocommit else {
                return try closure(connection)
            }
            
            do {
                try connection.beginTransaction(transaction)
                let result = try closure(connection)
                try connection.commitTransaction()
                return result
            } catch {
                if !connection.isAutocommit {
                    try connection.rollbackTransaction()
                }
                
                guard
                    let error = error as? SQLiteError,
                    error.code == SQLITE_NOTADB,
                    setNeedsReconnect()
                else {
                    throw error
                }
                
                return try perform { connection in
                    do {
                        try connection.beginTransaction(transaction)
                        let result = try closure(connection)
                        try connection.commitTransaction()
                        return result
                    } catch {
                        if !connection.isAutocommit {
                            try connection.rollbackTransaction()
                        }
                        throw error
                    }
                }
            }
        }
    }
    
    // MARK: - ConnectionDelegate
    
    /// Handles database updates reported by the active connection.
    ///
    /// Called after an SQL statement modifies the database content. Subclasses can override this
    /// method to observe specific actions (for example, inserts, updates, or deletes).
    ///
    /// - Important: This method must not execute SQL statements or otherwise alter the connection
    ///   state.
    ///
    /// - Parameters:
    ///   - connection: The connection that performed the update.
    ///   - action: The SQLite action describing the change.
    open func connection(_ connection: any ConnectionProtocol, didUpdate action: SQLiteAction) {
    }
    
    /// Called immediately before the connection commits a transaction.
    ///
    /// Subclasses can override this method to perform validation or consistency checks prior to
    /// committing. Throwing an error cancels the commit and triggers a rollback.
    ///
    /// - Important: This method must not execute SQL statements or otherwise alter the connection
    ///   state.
    ///
    /// - Parameter connection: The connection preparing to commit.
    /// - Throws: An error to cancel the commit and roll back the transaction.
    open func connectionWillCommit(_ connection: any ConnectionProtocol) throws {
    }
    
    /// Called after the connection rolls back a transaction.
    ///
    /// Subclasses can override this method to handle cleanup or recovery logic following a
    /// rollback.
    ///
    /// - Important: This method must not execute SQL statements or otherwise alter the connection
    /// state.
    ///
    /// - Parameter connection: The connection that rolled back the transaction.
    open func connectionDidRollback(_ connection: any ConnectionProtocol) {
    }
    
    // MARK: - Internal Methods
    
    override func connect() throws -> any ConnectionProtocol {
        let connection = try super.connect()
        connection.add(delegate: self)
        return connection
    }
}
