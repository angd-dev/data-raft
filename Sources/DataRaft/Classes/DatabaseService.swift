import Foundation
import DataLiteC
import DataLiteCore

/// Base service for working with a database.
///
/// `DatabaseService` provides a unified interface for performing operations using a database
/// connection, with built-in support for transactions, reconnection, and optional encryption
/// key management.
///
/// The service ensures thread-safe execution by serializing access to the connection through
/// an internal queue. This enables building modular and safe data access layers without
/// duplicating low-level logic.
///
/// The connection is established lazily on first use (e.g., within `perform`), not during
/// initialization. If a key provider is set, the key is applied as part of establishing or
/// restoring the connection.
///
/// Below is an example of creating a service for managing notes:
///
/// ```swift
/// final class NoteService: DatabaseService {
///     func insertNote(_ text: String) throws {
///         try perform { connection in
///             let stmt = try connection.prepare(sql: "INSERT INTO notes (text) VALUES (?)")
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
/// All operations are executed on an internal serial queue, ensuring thread safety. If a
/// decryption error (`SQLITE_NOTADB`) is detected, the service may reopen the connection and
/// retry the transactional block exactly once. If the error occurs again, it is propagated
/// without further retries.
///
/// ## Encryption Key Management
///
/// If a ``keyProvider`` is set, the service uses it to obtain and apply an encryption key when
/// establishing or restoring the connection. If an error occurs while obtaining or applying the
/// key, the provider is notified through
/// ``DatabaseServiceKeyProvider/databaseService(_:didReceive:)``.
///
/// ## Reconnection
///
/// Automatic reconnection is available only during transactional blocks executed with
/// ``perform(in:closure:)``. If a decryption error (`SQLITE_NOTADB`) occurs during a
/// transaction and the provider allows reconnection, the service obtains a new key, creates a
/// new connection, and retries the block once. If the second attempt fails or reconnection is
/// disallowed, the error is propagated without further retries.
///
/// ## Topics
///
/// ### Initializers
///
/// - ``ConnectionProvider``
/// - ``ConnectionConfig``
/// - ``init(provider:config:keyProvider:queue:)``
/// - ``init(connection:config:keyProvider:queue:)``
///
/// ### Key Management
///
/// - ``DatabaseServiceKeyProvider``
/// - ``keyProvider``
///
/// ### Database Operations
///
/// - ``DatabaseServiceProtocol/Perform``
/// - ``perform(_:)``
/// - ``perform(in:closure:)``
open class DatabaseService: DatabaseServiceProtocol, @unchecked Sendable {
    // MARK: - Types
    
    /// A closure that creates a new database connection.
    ///
    /// `ConnectionProvider` is used for deferred connection creation.
    /// It allows encapsulating initialization logic, configuration, and
    /// error handling when opening the database.
    ///
    /// - Returns: An initialized `Connection` instance.
    /// - Throws: An error if the connection cannot be created or configured.
    public typealias ConnectionProvider = () throws -> Connection
    
    /// A closure used to configure a newly created connection.
    ///
    /// Called after the connection is established (and after key application if present).
    /// Can be used to set PRAGMA options or perform other initialization logic.
    ///
    /// - Parameter connection: The newly created connection.
    /// - Throws: Any error if configuration fails.
    public typealias ConnectionConfig = (Connection) throws -> Void
    
    // MARK: - Properties
    
    private let provider: ConnectionProvider
    private let config: ConnectionConfig?
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    
    private var cachedConnection: Connection?
    private var connection: Connection {
        get throws {
            guard let cachedConnection else {
                let connection = try connect()
                cachedConnection = connection
                return connection
            }
            return cachedConnection
        }
    }
    
    /// Encryption key provider.
    ///
    /// Used to obtain and apply a key when establishing or restoring a connection. The key is
    /// requested on first access to the connection and on reconnection if needed.
    public weak var keyProvider: DatabaseServiceKeyProvider?
    
    // MARK: - Inits
    
    /// Creates a new database service.
    ///
    /// Configures the internal serial queue for thread-safe access to the database.
    /// The connection is **not** created during initialization. It is established
    /// lazily on first use (for example, inside `perform`).
    ///
    /// The internal queue is always created with QoS `.utility`. If the `queue`
    /// parameter is provided, it is used as the target queue for the internal one.
    ///
    /// If a `keyProvider` is set, the encryption key will be applied when the
    /// connection is established or restored.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a new connection.
    ///   - config: An optional configuration closure called after the connection
    ///     is created (and after key application if present).
    ///   - keyProvider: An optional encryption key provider.
    ///   - queue: An optional target queue for the internal one.
    public init(
        provider: @escaping ConnectionProvider,
        config: ConnectionConfig? = nil,
        keyProvider: DatabaseServiceKeyProvider? = nil,
        queue: DispatchQueue? = nil
    ) {
        self.provider = provider
        self.config = config
        self.keyProvider = keyProvider
        self.queue = .init(for: Self.self, qos: .utility)
        self.queue.setSpecific(key: queueKey, value: ())
        if let queue = queue {
            self.queue.setTarget(queue: queue)
        }
    }
    
    /// Creates a new database service.
    ///
    /// The connection is created lazily on first use. If a `keyProvider` is set,
    /// the key will be applied when the connection is established.
    ///
    /// - Parameters:
    ///   - provider: An expression that creates a new connection.
    ///   - config: An optional configuration closure called after the connection
    ///     is created (and after key application if present).
    ///   - keyProvider: An optional encryption key provider.
    ///   - queue: An optional target queue for the internal one.
    public convenience init(
        connection provider: @escaping @autoclosure ConnectionProvider,
        config: ConnectionConfig? = nil,
        keyProvider: DatabaseServiceKeyProvider? = nil,
        queue: DispatchQueue? = nil
    ) {
        self.init(
            provider: provider,
            config: config,
            keyProvider: keyProvider,
            queue: queue
        )
    }
    
    // MARK: - Methods
    
    /// Executes a closure with the current connection.
    ///
    /// Ensures thread-safe access by running the closure on the internal serial queue.
    /// The connection is created lazily if needed.
    ///
    /// - Parameter closure: A closure that takes the active connection.
    /// - Returns: The value returned by the closure.
    /// - Throws: An error if the connection cannot be created or if the closure throws.
    final public func perform<T>(_ closure: Perform<T>) throws -> T {
        try withConnection(closure)
    }
    
    /// Executes a closure inside a transaction if the connection is in autocommit mode.
    ///
    /// If the connection is in autocommit mode, starts a new transaction of the specified
    /// type, executes the closure, and commits changes on success. If the closure throws
    /// an error, the transaction is rolled back.
    ///
    /// If the closure throws `Connection.Error` with code `SQLITE_NOTADB` and reconnection
    /// is allowed, the service attempts to create a new connection, reapply the key, and
    /// retries the transaction block once. If the second attempt fails or reconnection
    /// is disallowed, the error is propagated without further retries.
    ///
    /// If a transaction is already active (connection not in autocommit mode), the closure
    /// is executed directly without starting a new transaction.
    ///
    /// - Parameters:
    ///   - transaction: The type of transaction to start.
    ///   - closure: A closure that takes the active connection and returns a result.
    /// - Returns: The value returned by the closure.
    /// - Throws: Errors from connection creation, key application, configuration,
    ///   transaction management, or from the closure itself.
    /// - Important: The closure may be executed more than once. Ensure it is idempotent.
    final public func perform<T>(
        in transaction: TransactionType,
        closure: Perform<T>
    ) throws -> T {
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
    
    func withConnection<T>(_ closure: Perform<T>) throws -> T {
        switch DispatchQueue.getSpecific(key: queueKey) {
        case .none: try queue.asyncAndWait { try closure(connection) }
        case .some: try closure(connection)
        }
    }
    
    func reconnect() throws {
        cachedConnection = try connect()
    }
    
    func connect() throws -> Connection {
        let connection = try provider()
        try applyKey(to: connection)
        try config?(connection)
        return connection
    }
    
    func applyKey(to connection: Connection) throws {
        guard let keyProvider = keyProvider else { return }
        do {
            let key = try keyProvider.databaseService(keyFor: self)
            let sql = "SELECT count(*) FROM sqlite_master"
            try connection.apply(key)
            try connection.execute(raw: sql)
        } catch {
            keyProvider.databaseService(self, didReceive: error)
            throw error
        }
    }
}
