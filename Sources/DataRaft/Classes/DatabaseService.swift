import Foundation
import DataLiteCore
import DataLiteC

/// A base class for services that operate on a database connection.
///
/// `DatabaseService` provides a shared interface for executing operations on a `Connection`,
/// with support for transaction handling and optional request serialization.
///
/// Subclasses can use this base to coordinate safe, synchronous access to the database
/// without duplicating concurrency or transaction logic.
///
/// For example, you can define a custom service for managing notes:
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
/// This approach allows you to build reusable service layers on top of a safe, transactional,
/// and serialized foundation.
///
/// ## Error Handling
///
/// All database access is serialized using an internal dispatch queue to ensure thread safety.
/// If a database corruption or decryption failure is detected (e.g., `SQLITE_NOTADB`), the
/// service attempts to re-establish the connection and, in case of transaction blocks,
/// retries the entire transaction block exactly once. If the problem persists, the error
/// is rethrown.
///
/// ## Encryption Key Management
///
/// If a `keyProvider` is set, the service will use it to retrieve and apply encryption keys
/// when establishing or re-establishing a database connection. Any error that occurs while
/// retrieving or applying the encryption key is reported to the provider via
/// `databaseService(_:didReceive:)`. Non-encryption-related errors (e.g., file access
/// issues) are not reported to the provider.
///
/// ## Reconnect Behavior
///
/// The service can automatically reconnect to the database, but this happens only in very specific
/// circumstances. Reconnection is triggered only when you run a transactional operation using
/// ``perform(in:closure:)``, and a decryption error (`SQLITE_NOTADB`) occurs during
/// the transaction. Even then, reconnection is possible only if you have set a ``keyProvider``,
/// and only if the provider allows it by returning `true` from its
/// ``DatabaseServiceKeyProvider/databaseServiceShouldReconnect(_:)-84qfz``
/// method.
///
/// When this happens, the service will ask the key provider for a new encryption key, create a new
/// database connection, and then try to re-run your transaction block one more time. If the second
/// attempt also fails with the same decryption error, or if reconnection is not allowed, the error is
/// returned to your code as usual, and no further attempts are made.
///
/// It's important to note that reconnection and retrying of transactions never happens outside of
/// transactional operations, and will never be triggered for other types of errors. All of this logic
/// runs on the service’s internal queue, so you don’t have to worry about thread safety.
///
/// - Important: Because a transaction block can be executed more than once when this
///   mechanism is triggered, make sure that your block is idempotent and doesn't cause any
///   side effects outside the database itself.
///
/// ## Topics
///
/// ### Initializers
///
/// - ``init(provider:queue:)``
/// - ``init(connection:queue:)``
///
/// ### Key Management
///
/// - ``DatabaseServiceKeyProvider``
/// - ``keyProvider``
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
    /// A closure that provides a new database connection when invoked.
    ///
    /// `ConnectionProvider` is used to defer the creation of a `Connection` instance
    /// until it is actually needed. It can throw errors if the connection cannot be
    /// established or configured correctly.
    ///
    /// - Returns: A valid `Connection` instance.
    /// - Throws: Any error encountered while opening or configuring the connection.
    public typealias ConnectionProvider = () throws -> Connection
    
    // MARK: - Properties
    
    private let provider: ConnectionProvider
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private var connection: Connection
    
    /// Provides the encryption key for the database connection.
    ///
    /// When this property is set, the service synchronously retrieves and applies an encryption
    /// key from the provider to the current database connection on the service’s internal queue,
    /// ensuring thread safety.
    ///
    /// If an error occurs during key retrieval or application (for example, if biometric
    /// authentication is cancelled, the key is unavailable, or decryption fails due to an
    /// incorrect key), the service notifies the provider by calling
    /// ``DatabaseServiceKeyProvider/databaseService(_:didReceive:)-xbrk``.
    ///
    /// This mechanism enables external management of encryption keys, supporting scenarios such
    /// as key rotation, user-specific encryption, or custom error handling.
    public weak var keyProvider: DatabaseServiceKeyProvider? {
        didSet {
            withConnection { connection in
                try? applyKey(to: connection)
            }
        }
    }
    
    // MARK: - Inits
    
    /// Creates a new `DatabaseService` with the specified connection provider and dispatch queue.
    ///
    /// This initializer immediately invokes the `provider` closure to establish the initial database
    /// connection. An internal serial queue is created for synchronizing database access. If a
    /// `queue` is provided, it is set as the target of the internal queue, allowing you to control
    /// scheduling and quality of service.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a new `Connection` instance. May throw on failure.
    ///   - queue: An optional dispatch queue to target for internal serialization. If `nil`,
    ///     a dedicated serial queue with `.utility` QoS is created.
    /// - Throws: Any error thrown by the `provider` during initial connection setup.
    public init(
        provider: @escaping ConnectionProvider,
        queue: DispatchQueue? = nil
    ) rethrows {
        self.provider = provider
        self.connection = try provider()
        self.queue = .init(for: Self.self, qos: .utility)
        self.queue.setSpecific(key: queueKey, value: ())
        if let queue = queue {
            self.queue.setTarget(queue: queue)
        }
    }
    
    /// Creates a new `DatabaseService` using the given connection provider and optional queue.
    ///
    /// This convenience initializer wraps the provided autoclosure in a `ConnectionProvider`
    /// and delegates to the designated initializer. It is useful when passing a simple
    /// connection expression.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a `Connection` instance and may throw.
    ///   - queue: An optional dispatch queue used as a target for internal serialization. If `nil`,
    ///     a default serial queue with `.utility` QoS is created internally.
    /// - Throws: Rethrows any error thrown by the connection provider.
    public convenience init(
        connection provider: @escaping @autoclosure ConnectionProvider,
        queue: DispatchQueue? = nil
    ) rethrows {
        try self.init(provider: provider, queue: queue)
    }
    
    // MARK: - Methods
    
    /// Re-establishes the database connection using the stored connection provider.
    ///
    /// This method synchronously creates a new ``Connection`` instance by invoking the original
    /// provider on the service’s internal queue. If a ``keyProvider`` is set, the service attempts
    /// to retrieve and apply an encryption key to the new connection.
    /// If any error occurs during key retrieval or application, the provider is notified via
    /// ``DatabaseServiceKeyProvider/databaseService(_:didReceive:)-xbrk``,
    /// and the error is rethrown.
    ///
    /// The new connection replaces the existing one only if all steps succeed without errors.
    ///
    /// This operation is always executed on the internal dispatch queue (see ``perform(_:)``)
    /// to ensure thread safety.
    ///
    /// - Throws: Any error thrown during connection creation or while retrieving or applying
    ///   the encryption key. Only encryption-related errors are reported to the ``keyProvider``.
    public func reconnect() throws {
        try withConnection { _ in
            let connection = try provider()
            try applyKey(to: connection)
            self.connection = connection
        }
    }
    
    /// Executes the given closure using the active database connection.
    ///
    /// Ensures thread-safe access to the underlying ``Connection`` by synchronizing execution on
    /// the service’s internal serial dispatch queue. If the call is already running on this queue,
    /// the closure is executed directly to avoid unnecessary dispatching.
    ///
    /// - Parameter closure: A closure that takes the active connection and returns a result.
    /// - Returns: The value returned by the closure.
    /// - Throws: Any error thrown by the closure.
    public func perform<T>(_ closure: Perform<T>) rethrows -> T {
        try withConnection(closure)
    }
    
    /// Executes a closure inside a transaction if the connection is in autocommit mode.
    ///
    /// If the connection is in autocommit mode, starts a new transaction of the specified type,
    /// executes the closure within it, and commits the transaction on success. If the closure
    /// throws, the transaction is rolled back.
    ///
    /// If the closure throws a `Connection.Error` with code `SQLITE_NOTADB` and reconnecting is
    /// allowed, the service attempts to reconnect and retries the entire transaction block once.
    ///
    /// If already inside a transaction (not in autocommit mode), executes the closure directly
    /// without starting a new transaction.
    ///
    /// - Parameters:
    ///   - transaction: The type of transaction to begin.
    ///   - closure: A closure that takes the active connection and returns a result.
    /// - Returns: The value returned by the closure.
    /// - Throws: Any error thrown by the closure, transaction control statements, or reconnect logic.
    ///
    /// - Important: The closure may be executed more than once. Ensure it is idempotent.
    public func perform<T>(
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

private extension DatabaseService {
    var shouldReconnect: Bool {
        keyProvider?.databaseServiceShouldReconnect(self) ?? false
    }
    
    func withConnection<T>(_ closure: Perform<T>) rethrows -> T {
        switch DispatchQueue.getSpecific(key: queueKey) {
        case .none: try queue.asyncAndWait { try closure(connection) }
        case .some: try closure(connection)
        }
    }
    
    func applyKey(to connection: Connection) throws {
        do {
            if let key = try keyProvider?.databaseServiceKey(self) {
                let sql = "SELECT count(*) FROM sqlite_master"
                try connection.apply(key)
                try connection.execute(raw: sql)
            }
        } catch {
            keyProvider?.databaseService(self, didReceive: error)
            throw error
        }
    }
}
