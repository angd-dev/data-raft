import Foundation
import DataLiteCore

open class DatabaseService {
    // MARK: - Properties
    
    private let connection: Connection
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    
    // MARK: - Inits
    
    public init(connection: Connection, queue: DispatchQueue? = nil) {
        self.connection = connection
        self.queue = queue ?? .init(for: Self.self)
        self.queue.setSpecific(key: queueKey, value: ())
    }
    
    // MARK: - Methods
    
    public func perform<T>(_ closure: (Connection) throws -> T) rethrows -> T {
        switch DispatchQueue.getSpecific(key: queueKey) {
        case .none: return try queue.sync { try closure(connection) }
        case .some: return try closure(connection)
        }
    }
    
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
