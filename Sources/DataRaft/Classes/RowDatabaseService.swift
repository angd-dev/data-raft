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
    
    /// Initializes a new `RowDatabaseService` instance with a connection provider,
    /// row encoder, decoder, and an optional dispatch queue.
    ///
    /// This initializer allows deferred creation of the database connection via the
    /// `provider` closure. It also lets you specify custom `RowEncoder` and `RowDecoder`
    /// instances for serializing and deserializing model data.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a valid `Connection`. May throw if the connection
    ///     cannot be established.
    ///   - encoder: An instance of `RowEncoder` used to encode model data into SQLite rows.
    ///     Defaults to a new `RowEncoder`.
    ///   - decoder: An instance of `RowDecoder` used to decode SQLite rows into model data.
    ///     Defaults to a new `RowDecoder`.
    ///   - queue: An optional dispatch queue used for synchronizing access. If `nil`,
    ///     a default internal serial queue is created.
    /// - Throws: Rethrows any error thrown by the connection provider.
    public init(
        provider: @escaping ConnectionProvider,
        encoder: RowEncoder = RowEncoder(),
        decoder: RowDecoder = RowDecoder(),
        queue: DispatchQueue? = nil
    ) rethrows {
        self.encoder = encoder
        self.decoder = decoder
        try super.init(
            provider: provider,
            queue: queue
        )
    }

    /// Creates a new `RowDatabaseService` instance using an existing connection,
    /// with optional custom row encoder, decoder, and dispatch queue.
    ///
    /// This convenience initializer wraps the given `Connection` in a provider closure
    /// and delegates initialization to the designated initializer.
    ///
    /// - Parameters:
    ///   - connection: An existing `Connection` instance to use.
    ///   - encoder: A custom `RowEncoder` for serialization. Defaults to a new instance.
    ///   - decoder: A custom `RowDecoder` for deserialization. Defaults to a new instance.
    ///   - queue: An optional dispatch queue used for synchronizing access. If `nil`,
    ///     a default internal serial queue is created.
    public convenience init(
        connection: Connection,
        encoder: RowEncoder = RowEncoder(),
        decoder: RowDecoder = RowDecoder(),
        queue: DispatchQueue? = nil
    ) {
        self.init(
            provider: { connection },
            encoder: encoder,
            decoder: decoder,
            queue: queue
        )
    }
}
