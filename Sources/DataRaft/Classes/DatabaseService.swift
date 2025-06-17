import Foundation
import DataLiteCore

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
    // MARK: - Properties
    
    private let connection: Connection
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    
    // MARK: - Inits
    
    /// Creates a new database service with the given connection and optional execution context.
    ///
    /// If no queue is provided, an internal serial dispatch queue with `.utility` quality of service
    /// is created to ensure safe access to the database connection.
    ///
    /// If a custom queue is provided, it is used as the target queue for the internal serial queue.
    /// This allows the caller to influence execution priority or scheduling characteristics
    /// without compromising thread safety.
    ///
    /// - Parameters:
    ///   - connection: The database connection to use.
    ///   - queue: An optional dispatch queue to use as a target for internal serialization.
    ///     If `nil`, a default internal serial queue is used.
    public init(connection: Connection, queue: DispatchQueue? = nil) {
        self.connection = connection
        self.queue = .init(for: Self.self, qos: .utility)
        self.queue.setSpecific(key: queueKey, value: ())
        if let queue = queue {
            self.queue.setTarget(queue: queue)
        }
    }
    
    // MARK: - Methods
    
    /// Executes the given closure with the underlying database connection.
    ///
    /// If the current thread is already executing on the service’s queue,
    /// the closure is executed directly. Otherwise, it is dispatched synchronously
    /// on the internal queue.
    ///
    /// - Parameter closure: A closure that receives the active `Connection`.
    /// - Returns: The result of the closure.
    /// - Throws: Any error thrown by the closure.
    public func perform<T>(_ closure: (Connection) throws -> T) rethrows -> T {
        switch DispatchQueue.getSpecific(key: queueKey) {
        case .none: return try queue.sync { try closure(connection) }
        case .some: return try closure(connection)
        }
    }
    
    /// Executes the given closure within a database transaction, if not already inside one.
    ///
    /// If the connection is in autocommit mode, the method wraps the closure
    /// in a transaction using the specified transaction type. If the connection
    /// is already inside a transaction, the closure is executed as-is.
    ///
    /// If the closure throws, the transaction is rolled back. Otherwise, it is committed.
    ///
    /// - Parameters:
    ///   - transaction: The transaction type to begin.
    ///   - closure: A closure that receives the active `Connection`.
    /// - Returns: The result of the closure.
    /// - Throws: Any error thrown by the closure or by the transaction commands.
    public func perform<T>(
        in transaction: SQLiteTransactionType,
        closure: (Connection) throws -> T
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
                    throw error
                }
            }
        } else {
            try perform(closure)
        }
    }
}
