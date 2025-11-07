import Foundation
import DataLiteCoder

/// A database service that provides model encoding and decoding support.
///
/// ## Overview
///
/// `ModelDatabaseService` extends ``DatabaseService`` by integrating `RowEncoder` and `RowDecoder`
/// to simplify model-based interactions with the database. Subclasses can encode Swift types into
/// SQLite rows and decode query results back into strongly typed models.
///
/// This enables a clean, type-safe persistence layer for applications that use Codable or custom
/// encodable/decodable types.
///
/// `ModelDatabaseService` serves as a foundation for higher-level model repositories and services.
/// It inherits all transactional and thread-safe behavior from ``DatabaseService`` while adding
/// automatic model serialization.
///
/// ## Usage
///
/// ```swift
/// struct User: Codable {
///     let id: Int
///     let name: String
/// }
///
/// final class UserService: ModelDatabaseService, @unchecked Sendable {
///     func fetchUser() throws -> User? {
///         try perform(in: .deferred) { connection in
///             let stmt = try connection.prepare(sql: "SELECT * FROM users")
///             guard try stmt.step(), let row = stmt.currentRow() else {
///                 return nil
///             }
///             return try decoder.decode(User.self, from: row)
///         }
///     }
///
///     func insertUser(_ user: User) throws {
///         try perform(in: .immediate) { connection in
///             let row = try encoder.encode(user)
///             let columns = row.columns.joined(separator: ", ")
///             let placeholders = row.namedParameters.joined(separator: ", ")
///             let sql = "INSERT INTO users (\(columns)) VALUES (\(placeholders))"
///             let stmt = try connection.prepare(sql: sql)
///             try stmt.execute([row])
///         }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Properties
///
/// - ``encoder``
/// - ``decoder``
///
/// ### Initializers
///
/// - ``init(provider:config:queue:center:encoder:decoder:)``
/// - ``init(provider:config:queue:)``
/// - ``init(connection:config:queue:)``
open class ModelDatabaseService: DatabaseService, @unchecked Sendable {
    // MARK: - Properties
    
    /// The encoder used to serialize models into row representations.
    public let encoder: RowEncoder
    
    /// The decoder used to deserialize database rows into model instances.
    public let decoder: RowDecoder
    
    // MARK: - Inits
    
    /// Creates a model-aware database service.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a new database connection.
    ///   - config: Optional configuration for the connection.
    ///   - queue: The dispatch queue used for serializing database operations.
    ///   - center: The notification center used for database events. Defaults to `.database`.
    ///   - encoder: The encoder for converting models into SQLite rows.
    ///   - decoder: The decoder for converting rows back into model instances.
    public init(
        provider: @escaping ConnectionProvider,
        config: ConnectionConfig? = nil,
        queue: DispatchQueue? = nil,
        center: NotificationCenter = .database,
        encoder: RowEncoder,
        decoder: RowDecoder
    ) {
        self.encoder = encoder
        self.decoder = decoder
        super.init(
            provider: provider,
            config: config,
            queue: queue,
            center: center
        )
    }
    
    /// Creates a model-aware database service using default encoder and decoder instances.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a new database connection.
    ///   - config: Optional configuration for the connection.
    ///   - queue: The dispatch queue used for serializing database operations.
    public required init(
        provider: @escaping ConnectionProvider,
        config: ConnectionConfig? = nil,
        queue: DispatchQueue? = nil
    ) {
        self.encoder = .init()
        self.decoder = .init()
        super.init(
            provider: provider,
            config: config,
            queue: queue
        )
    }
    
    /// Creates a model-aware database service from a connection autoclosure.
    ///
    /// - Parameters:
    ///   - provider: A connection autoclosure that returns a database connection.
    ///   - config: Optional configuration for the connection.
    ///   - queue: The dispatch queue used for serializing database operations.
    public required convenience init(
        connection provider: @escaping @autoclosure ConnectionProvider,
        config: ConnectionConfig? = nil,
        queue: DispatchQueue? = nil
    ) {
        self.init(
            provider: provider,
            config: config,
            queue: queue
        )
    }
}
