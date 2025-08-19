import Foundation
import DataLiteCore
import DataLiteC

/// Base service for working with a database.
///
/// `DatabaseService` provides a unified interface for performing operations
/// using a database connection, with built-in support for transactions,
/// reconnection, and optional encryption key management.
///
/// The service ensures thread-safe execution by serializing access to the
/// connection through an internal queue. This enables building modular and safe
/// data access layers without duplicating low-level logic.
///
/// Below is an example of creating a service for managing notes:
///
/// ```swift
/// final class NoteService: DatabaseService {
///     func insertNote(_ text: String) throws {
///         try perform { connection in
///             let stmt = try connection.prepare(
///                 sql: "INSERT INTO notes (text) VALUES (?)"
///             )
///             try stmt.bind(text, at: 0)
///             try stmt.step()
///         }
///     }
///
///     func fetchNotes() throws -> [String] {
///         try perform { connection in
///             let stmt = try connection.prepare(sql: "SELECT text FROM notes")
///             var result: [String] = []
///             while try stmt.step() {
///                 if let text: String = stmt.columnValue(at: 0) {
///                     result.append(text)
///                 }
///             }
///             return result
///         }
///     }
/// }
///
/// let connection = try Connection(location: .inMemory, options: .readwrite)
/// let service = NoteService(connection: connection)
///
/// try service.insertNote("Hello, world!")
/// let notes = try service.fetchNotes()
/// print(notes) // ["Hello, world!"]
/// ```
///
/// ## Error Handling
///
/// All operations are executed on an internal serial queue, ensuring thread safety.
/// If an encryption error (`SQLITE_NOTADB`) is detected, the service may reopen the
/// connection and retry the transactional block exactly once. If the error occurs again,
/// it is propagated without further retries.
///
/// ## Encryption Key Management
///
/// If a ``keyProvider`` is set, the service uses it to obtain and apply an encryption
/// key when creating or restoring a connection. If an error occurs while obtaining
/// or applying the key, the provider is notified through
/// ``DatabaseServiceKeyProvider/databaseService(_:didReceive:)``.
///
/// ## Reconnection
///
/// Automatic reconnection is available only during transactional blocks executed with
/// ``perform(in:closure:)``. If a decryption error (`SQLITE_NOTADB`) occurs during
/// a transaction and the provider allows reconnection, the service obtains a new key,
/// creates a new connection, and retries the block once. If the second attempt fails
/// or reconnection is disallowed, the error is propagated without further retries.
///
/// ## Topics
///
/// ### Initializers
///
/// - ``init(provider:keyProvider:queue:)``
/// - ``init(connection:keyProvider:queue:)``
///
/// ### Key Management
///
/// - ``DatabaseServiceKeyProvider``
/// - ``keyProvider``
/// - ``applyKeyProvider()``
///
/// ### Connection Management
///
/// - ``ConnectionProvider``
/// - ``reconnect()``
///
/// ### Database Operations
///
/// - ``DatabaseServiceProtocol/Perform``
/// - ``perform(_:)``
/// - ``perform(in:closure:)``
open class DatabaseService: DatabaseServiceProtocol, @unchecked Sendable {
    /// A closure that creates a new database connection.
    ///
    /// `ConnectionProvider` is used for deferred connection creation.
    /// It allows encapsulating initialization logic, configuration, and
    /// error handling when opening the database.
    ///
    /// - Returns: An initialized `Connection` instance.
    /// - Throws: An error if the connection cannot be created or configured.
    public typealias ConnectionProvider = () throws -> Connection
    
    // MARK: - Properties
    
    private let provider: ConnectionProvider
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private var connection: Connection
    
    /// Encryption key provider.
    ///
    /// Used to obtain and apply a key when creating or restoring a connection.
    public weak var keyProvider: DatabaseServiceKeyProvider?
    
    // MARK: - Inits
    
    /// Creates a new database service.
    ///
    /// Calls `provider` to create the initial connection and configures
    /// the internal serial queue for thread-safe access to the database.
    ///
    /// The internal queue is always created with QoS `.utility`. If the `queue`
    /// parameter is provided, it is used as the target queue for the internal one.
    ///
    /// If a `keyProvider` is set, the encryption key is applied immediately
    /// after the initial connection is created.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a new connection.
    ///   - keyProvider: An optional encryption key provider.
    ///   - queue: An optional target queue for the internal one.
    /// - Throws: An error if the connection cannot be created or configured.
    public init(
        provider: @escaping ConnectionProvider,
        keyProvider: DatabaseServiceKeyProvider? = nil,
        queue: DispatchQueue? = nil
    ) throws {
        self.provider = provider
        self.keyProvider = keyProvider
        self.connection = try provider()
        self.queue = .init(for: Self.self, qos: .utility)
        self.queue.setSpecific(key: queueKey, value: ())
        if let queue = queue {
            self.queue.setTarget(queue: queue)
        }
        if self.keyProvider != nil {
            try applyKey(to: self.connection)
        }
    }
    
    /// Creates a new database service.
    ///
    /// - Parameters:
    ///   - provider: An expression that creates a new connection.
    ///   - keyProvider: An optional encryption key provider.
    ///   - queue: An optional target queue for the internal one.
    /// - Throws: An error if the connection cannot be created or configured.
    public convenience init(
        connection provider: @escaping @autoclosure ConnectionProvider,
        keyProvider: DatabaseServiceKeyProvider? = nil,
        queue: DispatchQueue? = nil
    ) throws {
        try self.init(provider: provider, keyProvider: keyProvider, queue: queue)
    }
    
    // MARK: - Methods
    
    /// Applies the encryption key from `keyProvider` to the current connection.
    ///
    /// The method executes synchronously on the internal queue. If the key provider
    /// is missing, the method does nothing. If the key has already been successfully
    /// applied, subsequent calls have no effect. To apply a new key, use ``reconnect()``.
    ///
    /// If an error occurs while obtaining or applying the key, it is thrown further
    /// and also reported to the provider via
    /// ``DatabaseServiceKeyProvider/databaseService(_:didReceive:)``.
    ///
    /// - Throws: An error while obtaining or applying the key.
    final public func applyKeyProvider() throws {
        try withConnection { connection in
            try applyKey(to: connection)
        }
    }
    
    /// Establishes a new database connection.
    ///
    /// Creates a new `Connection` using the stored connection provider and,
    /// if a ``keyProvider`` is set, applies the encryption key. The new connection
    /// replaces the previous one only if it is successfully created and configured.
    ///
    /// If an error occurs while obtaining or applying the key, it is thrown further
    /// and also reported to the provider via
    /// ``DatabaseServiceKeyProvider/databaseService(_:didReceive:)``.
    ///
    /// Executed synchronously on the internal queue, ensuring thread safety.
    ///
    /// - Throws: An error if the connection cannot be created or the key cannot
    ///   be obtained/applied.
    final public func reconnect() throws {
        try withConnection { _ in
            let connection = try provider()
            try applyKey(to: connection)
            self.connection = connection
        }
    }
    
    /// Executes a closure with the active connection.
    ///
    /// Runs the `closure` on the internal serial queue, ensuring
    /// thread-safe access to the `Connection`.
    ///
    /// - Parameter closure: A closure that takes the active connection.
    /// - Returns: The value returned by the closure.
    /// - Throws: Any error thrown by the closure.
    final public func perform<T>(_ closure: Perform<T>) rethrows -> T {
        try withConnection(closure)
    }
    
    /// Executes a closure inside a transaction if the connection is in autocommit mode.
    ///
    /// If the connection is in autocommit mode, starts a new transaction of the
    /// specified type, executes the closure, and commits changes on success.
    /// If the closure throws an error, the transaction is rolled back.
    ///
    /// If the closure throws `Connection.Error` with code `SQLITE_NOTADB`
    /// and reconnection is allowed, the service attempts to reconnect and retries
    /// the transaction block once.
    ///
    /// If a transaction is already active (connection not in autocommit mode),
    /// the closure is executed directly without starting a new transaction.
    ///
    /// - Parameters:
    ///   - transaction: The type of transaction to start.
    ///   - closure: A closure that takes the active connection and returns a result.
    /// - Returns: The value returned by the closure.
    /// - Throws: Any error thrown by the closure, transaction management, or
    ///   reconnection logic.
    /// - Important: The closure may be executed more than once. Ensure it is idempotent.
    final public func perform<T>(
        in transaction: TransactionType,
        closure: Perform<T>
    ) rethrows -> T {
        try withConnection { connection in
            if connection.isAutocommit {
                do {
                    try connection.beginTransaction(transaction)
                    let result = try closure(connection)
                    try connection.commitTransaction()
                    return result
                } catch {
                    try connection.rollbackTransaction()
                    guard let error = error as? Connection.Error,
                          error.code == SQLITE_NOTADB,
                          shouldReconnect
                    else { throw error }
                    
                    try reconnect()
                    
                    return try withConnection { connection in
                        do {
                            try connection.beginTransaction(transaction)
                            let result = try closure(connection)
                            try connection.commitTransaction()
                            return result
                        } catch {
                            try connection.rollbackTransaction()
                            throw error
                        }
                    }
                }
            } else {
                return try closure(connection)
            }
        }
    }
}

// MARK: - Private

private extension DatabaseService {
    var shouldReconnect: Bool {
        keyProvider?.databaseService(shouldReconnect: self) ?? false
    }
    
    func withConnection<T>(_ closure: Perform<T>) rethrows -> T {
        switch DispatchQueue.getSpecific(key: queueKey) {
        case .none: try queue.asyncAndWait { try closure(connection) }
        case .some: try closure(connection)
        }
    }
    
    func applyKey(to connection: Connection) throws {
        guard let keyProvider = keyProvider else { return }
        do {
            if let key = try keyProvider.databaseService(keyFor: self) {
                let sql = "SELECT count(*) FROM sqlite_master"
                try connection.apply(key)
                try connection.execute(raw: sql)
            }
        } catch {
            keyProvider.databaseService(self, didReceive: error)
            throw error
        }
    }
}
