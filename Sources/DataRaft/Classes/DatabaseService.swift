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
open class DatabaseService {
    /// A closure that provides a new database connection when invoked.
    ///
    /// `ConnectionProvider` is used to defer the creation of a `Connection` instance
    /// until it is actually needed. It can throw errors if the connection cannot be
    /// established or configured correctly.
    ///
    /// - Returns: A valid `Connection` instance.
    /// - Throws: Any error encountered while opening or configuring the connection.
    public typealias ConnectionProvider = () throws -> Connection
    
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
    public typealias Perform<T> = (Connection) throws -> T
    
    // MARK: - Properties
    
    private let provider: ConnectionProvider
    private var connection: Connection
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    
    /// The object that provides the encryption key for the database connection.
    ///
    /// When this property is set, the service attempts to retrieve the encryption key from the provider
    /// and apply it to the current database connection. The operation is performed synchronously
    /// on the service’s internal queue to ensure thread safety.
    ///
    /// This allows external management of encryption keys, enabling features such as
    /// dynamic key rotation or user-scoped keys.
    ///
    /// If retrieving or applying the key fails, the error is silently ignored.
    /// Use caution to ensure the key provider is properly configured to avoid connection errors.
    public weak var keyProvider: DatabaseServiceKeyProvider? {
        didSet {
            try? perform { connection in
                if let key = try keyProvider?.databaseServiceKey(self) {
                    try connection.apply(key)
                }
            }
        }
    }
    
    // MARK: - Inits
    
    /// Initializes a new database service with a connection provider and an optional dispatch queue.
    ///
    /// The connection provider closure is called immediately to obtain the initial connection.
    /// An internal serial queue is created for synchronizing access to the connection.
    /// If a custom queue is provided, it is set as the target queue for the internal serial queue,
    /// allowing control over execution priority and scheduling.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a `Connection` instance and may throw.
    ///   - queue: An optional dispatch queue to use as a target for internal serialization.
    ///     If `nil`, a default internal serial queue with `.utility` QoS is used.
    /// - Throws: Rethrows any error thrown by the connection provider.
    public init(provider: @escaping ConnectionProvider, queue: DispatchQueue? = nil) rethrows {
        self.provider = provider
        self.connection = try provider()
        self.queue = .init(for: Self.self, qos: .utility)
        self.queue.setSpecific(key: queueKey, value: ())
        if let queue = queue {
            self.queue.setTarget(queue: queue)
        }
    }
    
    /// Convenience initializer that creates a new database service from an existing connection,
    /// optionally specifying a dispatch queue for serialization.
    ///
    /// This calls the designated initializer internally, wrapping the provided connection
    /// in a closure provider. The dispatch queue behavior is the same as in the designated initializer.
    ///
    /// - Parameters:
    ///   - connection: The existing database connection to use.
    ///   - queue: An optional dispatch queue to use as a target for internal serialization.
    ///     If `nil`, a default internal serial queue with `.utility` QoS is used.
    public convenience init(connection: Connection, queue: DispatchQueue? = nil) {
        self.init(provider: { connection }, queue: queue)
    }
    
    // MARK: - Methods
    
    /// Re-establishes the database connection by invoking the connection provider.
    ///
    /// This method attempts to create a new `Connection` instance using the stored
    /// `ConnectionProvider` closure. If a `keyProvider` is set, the service retrieves
    /// the encryption key from the provider and applies it to the new connection.
    ///
    /// The existing connection is then replaced with the newly created one.
    ///
    /// The operation is executed synchronously on the internal queue via ``perform(_:)``
    /// to ensure thread safety.
    ///
    /// - Throws: Any error thrown during connection creation or key application.
    public func reconnect() throws {
        try perform { _ in
            let connection = try provider()
            if let key = try keyProvider?.databaseServiceKey(self) {
                try connection.apply(key)
            }
            self.connection = connection
        }
    }
    
    /// Executes the given closure using the underlying database connection.
    ///
    /// This method ensures that all database operations are executed in a
    /// thread-safe manner by serializing access on an internal dispatch queue.
    ///
    /// If the current thread is already running on the service’s queue,
    /// the closure is executed immediately to avoid deadlocks or unnecessary context switches.
    /// Otherwise, the closure is dispatched synchronously onto the internal queue.
    ///
    /// If the closure throws an `SQLiteError` with the code `SQLITE_NOTADB`
    /// (indicating the database file is corrupted or not a database),
    /// this method attempts to reconnect by reinitializing the connection
    /// and then rethrows the error.
    ///
    /// - Parameter closure: A closure that receives the active `Connection`
    ///   and returns a generic result.
    /// - Returns: The result returned by the closure.
    /// - Throws: Any error thrown by the closure, including errors from reconnect attempts.
    public func perform<T>(_ closure: Perform<T>) rethrows -> T {
        do {
            switch DispatchQueue.getSpecific(key: queueKey) {
            case .none: return try queue.sync { try closure(connection) }
            case .some: return try closure(connection)
            }
        } catch let error as SQLiteError {
            if error.code == SQLITE_NOTADB {
                try reconnect()
            }
            throw error
        } catch {
            throw error
        }
    }
    
    /// Executes the given closure inside a database transaction if not already within one.
    ///
    /// If the current connection is in autocommit mode, this method begins a new transaction
    /// of the specified type, executes the closure, and then commits the transaction.
    /// If the closure throws an error, the transaction is rolled back.
    ///
    /// If the connection is already inside a transaction, the closure is executed directly
    /// without starting a new one.
    ///
    /// In case an `SQLiteError` with code `SQLITE_NOTADB` is thrown during transaction execution,
    /// the connection is re-established, and the transaction is retried exactly once —
    /// **but only if the transaction was originally started by this method**.
    ///
    /// - Parameters:
    ///   - transaction: The type of SQLite transaction to begin.
    ///   - closure: A closure that receives the active `Connection` and returns a result.
    /// - Returns: The result returned by the closure.
    /// - Throws: Any error thrown by the closure or transaction control statements.
    public func perform<T>(
        in transaction: SQLiteTransactionType,
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
                    guard let error = error as? SQLiteError,
                          error.code == SQLITE_NOTADB
                    else { throw error }
                    
                    try reconnect()
                    
                    try connection.beginTransaction(transaction)
                    let result = try closure(connection)
                    try connection.commitTransaction()
                    return result
                }
            }
        } else {
            try perform(closure)
        }
    }
}
