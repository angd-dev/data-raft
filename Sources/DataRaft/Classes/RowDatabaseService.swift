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
open class RowDatabaseService:
    DatabaseService,
    RowDatabaseServiceProtocol,
    @unchecked Sendable
{
    // MARK: - Properties
    
    /// The encoder used to serialize values into row representations.
    public let encoder: RowEncoder
    
    /// The decoder used to deserialize row values into strongly typed models.
    public let decoder: RowDecoder
    
    // MARK: - Inits
    
    /// Creates a new `RowDatabaseService`.
    ///
    /// This initializer accepts a closure that supplies the database connection. If no encoder
    /// or decoder is provided, default instances are used.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a `Connection` instance. May throw an error.
    ///   - encoder: The encoder used to serialize models into SQLite-compatible rows.
    ///     Defaults to a new encoder.
    ///   - decoder: The decoder used to deserialize SQLite rows into typed models.
    ///     Defaults to a new decoder.
    ///   - queue: An optional dispatch queue used for serialization. If `nil`, an internal
    ///     serial queue with `.utility` QoS is created.
    /// - Throws: Any error thrown by the connection provider.
    public convenience init(
        connection provider: @escaping @autoclosure ConnectionProvider,
        encoder: RowEncoder = RowEncoder(),
        decoder: RowDecoder = RowDecoder(),
        queue: DispatchQueue? = nil
    ) throws {
        try self.init(
            provider: provider,
            encoder: encoder,
            decoder: decoder,
            queue: queue
        )
    }
    
    /// Designated initializer for `RowDatabaseService`.
    ///
    /// Initializes a new instance with the specified connection provider, encoder, decoder,
    /// and an optional dispatch queue for synchronization.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a `Connection` instance. May throw an error.
    ///   - encoder: A custom `RowEncoder` used for encoding model data. Defaults to a new encoder.
    ///   - decoder: A custom `RowDecoder` used for decoding database rows. Defaults to a new decoder.
    ///   - queue: An optional dispatch queue for serializing access to the database connection.
    ///     If `nil`, a default internal serial queue with `.utility` QoS is used.
    /// - Throws: Any error thrown by the connection provider.
    public init(
        provider: @escaping ConnectionProvider,
        encoder: RowEncoder = RowEncoder(),
        decoder: RowDecoder = RowDecoder(),
        queue: DispatchQueue? = nil
    ) throws {
        self.encoder = encoder
        self.decoder = decoder
        try super.init(
            provider: provider,
            queue: queue
        )
    }
}
