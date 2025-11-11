import Foundation

/// A type that describes a database schema version.
///
/// ## Overview
///
/// Types conforming to this alias can be compared, checked for equality, hashed, and safely used
/// across concurrent contexts. Such types are typically used to track and manage schema migrations.
///
/// ## Conformance
///
/// Conforming types must implement:
/// - `Equatable` — for equality checks
/// - `Comparable` — for ordering versions
/// - `Hashable` — for dictionary/set membership
/// - `Sendable` — for concurrency safety
///
/// ## Usage
///
/// Use this type alias when defining custom version types for use with ``VersionStorage``.
///
/// ```swift
/// struct SemanticVersion: VersionRepresentable {
///     let major: Int
///     let minor: Int
///     let patch: Int
///
///     static func < (lhs: Self, rhs: Self) -> Bool {
///         if lhs.major != rhs.major { return lhs.major < rhs.major }
///         if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
///         return lhs.patch < rhs.patch
///     }
/// }
/// ```
public typealias VersionRepresentable = Equatable & Comparable & Hashable & Sendable
