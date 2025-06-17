import Foundation
import DataLiteCore
import DataLiteCoder

/// A database service that provides built-in row encoding and decoding.
///
/// `RowDatabaseService` extends `DatabaseService` by adding support for
/// value serialization using `RowEncoder` and deserialization using `RowDecoder`.
///
/// This enables subclasses to perform type-safe operations on models
/// encoded from or decoded into SQLite row representations.
///
/// For example, a concrete service might define model-aware fetch or insert methods:
///
/// ```swift
/// struct User: Codable {
///     let id: Int
///     let name: String
/// }
///
/// final class UserService: RowDatabaseService {
///     func fetchUsers() throws -> [User] {
///         try perform(in: .deferred) { connection in
///             let stmt = try connection.prepare(sql: "SELECT * FROM users")
///             let rows = try stmt.execute()
///             return try decoder.decode([User].self, from: rows)
///         }
///     }
///
///     func insertUser(_ user: User) throws {
///         try perform(in: .deferred) { connection in
///             let row = try encoder.encode(user)
///             let columns = row.columns.joined(separator: ", ")
///             let parameters = row.namedParameters.joined(separator: ", ")
///             let stmt = try connection.prepare(
///                 sql: "INSERT INTO users (\(columns)) VALUES (\(parameters))"
///             )
///             try stmt.execute(rows: [row])
///         }
///     }
/// }
/// ```
///
/// `RowDatabaseService` encourages a reusable, type-safe pattern for
/// model-based interaction with SQLite while preserving thread safety
/// and transactional integrity.
open class RowDatabaseService: DatabaseService {
    // MARK: - Properties
    
    /// The encoder used to serialize values into row representations.
    public let encoder: RowEncoder
    
    /// The decoder used to deserialize row values into strongly typed models.
    public let decoder: RowDecoder
    
    // MARK: - Inits
    
    /// Creates a new row-aware database service with the given connection and encoders.
    ///
    /// - Parameters:
    ///   - connection: The database connection to use.
    ///   - encoder: A custom `RowEncoder` to use for serialization. Defaults to a new instance.
    ///   - decoder: A custom `RowDecoder` to use for deserialization. Defaults to a new instance.
    ///   - queue: An optional dispatch queue for controlling access concurrency.
    public init(
        connection: Connection,
        encoder: RowEncoder = RowEncoder(),
        decoder: RowDecoder = RowDecoder(),
        queue: DispatchQueue? = nil
    ) {
        self.encoder = encoder
        self.decoder = decoder
        super.init(connection: connection, queue: queue)
    }
}
