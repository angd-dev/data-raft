import Foundation
import DataLiteCoder

/// A protocol for database services that support row encoding and decoding.
///
/// Conforming types provide `RowEncoder` and `RowDecoder` instances for serializing
/// and deserializing model types to and from SQLite row representations.
///
/// This enables strongly typed, reusable, and safe access to database records
/// using Swift's `Codable` system.
public protocol RowDatabaseServiceProtocol: DatabaseServiceProtocol {
    /// The encoder used to serialize values into database rows.
    var encoder: RowEncoder { get }

    /// The decoder used to deserialize database rows into typed models.
    var decoder: RowDecoder { get }
}
