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
open class DatabaseService: DatabaseServiceProtocol {
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
    private var connection: Connection
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    
    /// The object that provides the encryption key for the database connection.
    ///
    /// When this property is set, the service attempts to retrieve an encryption key from the
    /// provider and apply it to the current database connection. This operation is performed
    /// synchronously on the service’s internal queue to ensure thread safety.
    ///
    /// If an error occurs during key retrieval or application, the service notifies the provider
    /// by calling `databaseService(_:didReceive:)`.
    ///
    /// This enables external management of encryption keys, including features such as key rotation,
    /// user-scoped encryption, or error handling delegation.
    ///
    /// - Important: The service does not retry failed key applications. Ensure the provider is
    ///   correctly configured and able to supply a valid key when needed.
    public weak var keyProvider: DatabaseServiceKeyProvider? {
        didSet {
            perform { connection in
                do {
                    if let key = try keyProvider?.databaseServiceKey(self) {
                        try connection.apply(key)
                    }
                } catch {
                    keyProvider?.databaseService(self, didReceive: error)
                }
            }
        }
    }
    
    // MARK: - Inits
    
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
    
    // MARK: - Methods
    
    /// Re-establishes the database connection using the stored connection provider.
    ///
    /// This method creates a new `Connection` instance by invoking the original provider. If a
    /// `keyProvider` is set, the method attempts to retrieve and apply an encryption key to the new
    /// connection. The new connection replaces the existing one.
    ///
    /// The operation is executed synchronously on the internal dispatch queue via `perform(_:)`
    /// to ensure thread safety.
    ///
    /// - Throws: Any error thrown during connection creation or while retrieving or applying the
    ///   encryption key.
    public func reconnect() throws {
        try perform { _ in
            let connection = try provider()
            if let key = try keyProvider?.databaseServiceKey(self) {
                try connection.apply(key)
            }
            self.connection = connection
        }
    }
    
    /// Executes the given closure using the active database connection.
    ///
    /// This method ensures thread-safe access to the underlying `Connection` by synchronizing
    /// execution on an internal serial dispatch queue. If the call is already on that queue, the
    /// closure is executed directly to avoid unnecessary dispatching.
    ///
    /// If the closure throws a `SQLiteError` with code `SQLITE_NOTADB` (e.g., when the database file
    /// is corrupted or invalid), the service attempts to re-establish the connection by calling
    /// ``reconnect()``. The error is still rethrown after reconnection.
    ///
    /// - Parameter closure: A closure that takes the active connection and returns a result.
    /// - Returns: The value returned by the closure.
    /// - Throws: Any error thrown by the closure or during reconnection logic.
    public func perform<T>(_ closure: Perform<T>) rethrows -> T {
        do {
            switch DispatchQueue.getSpecific(key: queueKey) {
            case .none: return try queue.asyncAndWait { try closure(connection) }
            case .some: return try closure(connection)
            }
        } catch {
            switch error {
            case let error as Connection.Error:
                if error.code == SQLITE_NOTADB {
                    try reconnect()
                }
                fallthrough
            default:
                throw error
            }
        }
    }
    
    /// Executes a closure inside a transaction if the connection is in autocommit mode.
    ///
    /// If the current connection is in autocommit mode, a new transaction of the specified type
    /// is started, and the closure is executed within it. If the closure completes successfully,
    /// the transaction is committed. If an error is thrown, the transaction is rolled back.
    ///
    /// If the thrown error is a `SQLiteError` with code `SQLITE_NOTADB`, the service attempts to
    /// reconnect and retries the entire transaction block exactly once.
    ///
    /// If the connection is already within a transaction (i.e., not in autocommit mode),
    /// the closure is executed directly without starting a new transaction.
    ///
    /// - Parameters:
    ///   - transaction: The type of transaction to begin (e.g., `deferred`, `immediate`, `exclusive`).
    ///   - closure: A closure that takes the active connection and returns a result.
    /// - Returns: The value returned by the closure.
    /// - Throws: Any error thrown by the closure, transaction control statements,
    ///   or reconnect logic.
    public func perform<T>(
        in transaction: TransactionType,
        closure: Perform<T>
    ) rethrows -> T {
        if connection.isAutocommit {
            try perform { connection in
                do {
                    try connection.beginTransaction(transaction)
                    let result = try closure(connection)
                    try connection.commitTransaction()
                    return result
                } catch {
                    try connection.rollbackTransaction()
                    guard let error = error as? Connection.Error,
                          error.code == SQLITE_NOTADB
                    else { throw error }
                    
                    try reconnect()
                    
                    return try perform { connection in
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
            }
        } else {
            try perform(closure)
        }
    }
}
