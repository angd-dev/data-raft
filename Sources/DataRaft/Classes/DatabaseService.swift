import Foundation
import DataLiteCore
import DataLiteC

/// A base database service handling transactions and event notifications.
///
/// ## Overview
///
/// `DatabaseService` provides a foundational layer for performing transactional database operations
/// within a thread-safe execution context. It automatically posts lifecycle notifications — such as
/// commit, rollback, and content changes — allowing observers to react to database updates in real
/// time. By default, it routes events through ``Foundation/NotificationCenter/database`` so that
/// clients can subscribe via a dedicated channel. This service is designed to be subclassed by
/// higher-level data managers that encapsulate domain logic while relying on consistent connection
/// and transaction handling.
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
/// - ``databaseWillCommit``
/// - ``databaseDidRollback``
/// - ``databaseDidPerform``
open class DatabaseService:
    ConnectionService,
    DatabaseServiceProtocol,
    ConnectionDelegate,
    @unchecked Sendable
{
    // MARK: - Properties
    
    private let center: NotificationCenter
    
    /// Notification posted after the database content changes.
    ///
    /// Observers listen to this event to refresh cached data or update dependent components once
    /// modifications are committed. The notification’s `userInfo` may include
    /// ``Foundation/Notification/UserInfoKey/action`` describing the SQLite action.
    public static let databaseDidChange = Notification.Name("DatabaseService.databaseDidChange")
    
    /// Notification posted immediately before a transaction commits.
    ///
    /// Observers can perform validation or prepare for an upcoming state change while the
    /// transaction is still in progress.
    public static let databaseWillCommit = Notification.Name("DatabaseService.databaseWillCommit")
    
    /// Notification posted after a transaction rolls back.
    ///
    /// Observers use this event to revert in-memory state or reset caches that rely on pending
    /// changes.
    public static let databaseDidRollback = Notification.Name("DatabaseService.databaseDidRollback")
    
    /// Notification posted after any database operation completes, regardless of outcome.
    ///
    /// The service emits this event after finishing a `perform(_:)` block so observers can
    /// synchronize state even when the operation is read-only or aborted.
    ///
    /// - Important: Confirm that the associated transaction was not rolled back before relying on
    ///   side effects.
    public static let databaseDidPerform = Notification.Name("DatabaseService.databaseDidPerform")
    
    // MARK: - Inits
    
    /// Creates a database service that posts lifecycle events to the provided notification center.
    ///
    /// The underlying connection handling matches ``ConnectionService``; the connection is created
    /// lazily and all work executes on the managed serial queue.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a new database connection.
    ///   - config: An optional configuration closure called after the connection is established and
    ///     the encryption key is applied.
    ///   - queue: An optional target queue for the internal serial queue.
    ///   - center: A notification center for posting database events.
    public init(
        provider: @escaping ConnectionProvider,
        config: ConnectionConfig? = nil,
        queue: DispatchQueue? = nil,
        center: NotificationCenter
    ) {
        self.center = center
        super.init(provider: provider, config: config, queue: queue)
    }
    
    /// Creates a database service that posts lifecycle events to the shared database notification
    /// center.
    ///
    /// The connection is established lazily on first access and all work executes on the internal
    /// queue defined in ``ConnectionService``.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a new database connection.
    ///   - config: An optional configuration closure called after the connection is established and
    ///     the encryption key is applied.
    ///   - queue: An optional target queue for the internal serial queue.
    public required init(
        provider: @escaping ConnectionProvider,
        config: ConnectionConfig? = nil,
        queue: DispatchQueue? = nil
    ) {
        self.center = .database
        super.init(provider: provider, config: config, queue: queue)
    }
    
    // MARK: - Performing Operations
    
    /// Executes a closure with a managed database connection and posts a completion notification.
    ///
    /// The override mirrors ``ConnectionService/perform(_:)`` for queue-confined execution while
    /// ensuring ``DatabaseService/databaseDidPerform`` is delivered after the closure completes.
    ///
    /// - Parameter closure: The operation to execute using the open connection.
    /// - Returns: The value returned by the closure.
    /// - Throws: Errors thrown by the closure or underlying connection.
    public override func perform<T>(_ closure: Perform<T>) throws -> T {
        try super.perform { connection in
            defer { center.post(name: Self.databaseDidPerform, object: self) }
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
    
    /// Posts ``DatabaseService/databaseDidChange`` when the database content updates.
    ///
    /// - Parameters:
    ///   - connection: The connection that performed the change.
    ///   - action: The SQLite action describing the modification.
    public func connection(_ connection: any ConnectionProtocol, didUpdate action: SQLiteAction) {
        let userInfo = [Notification.UserInfoKey.action: action]
        center.post(name: Self.databaseDidChange, object: self, userInfo: userInfo)
    }
    
    /// Posts ``DatabaseService/databaseWillCommit`` before a transaction commits.
    ///
    /// - Parameter connection: The connection preparing to commit.
    public func connectionWillCommit(_ connection: any ConnectionProtocol) throws {
        center.post(name: Self.databaseWillCommit, object: self)
    }
    
    /// Posts ``DatabaseService/databaseDidRollback`` after a transaction rollback.
    ///
    /// - Parameter connection: The connection that rolled back.
    public func connectionDidRollback(_ connection: any ConnectionProtocol) {
        center.post(name: Self.databaseDidRollback, object: self)
    }
    
    // MARK: - Internal Methods
    
    override func connect() throws -> any ConnectionProtocol {
        let connection = try super.connect()
        connection.add(delegate: self)
        return connection
    }
}
