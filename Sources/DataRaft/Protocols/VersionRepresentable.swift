import Foundation

/// A constraint that defines the requirements for a type used as a database schema version.
///
/// This type alias specifies the minimal set of capabilities a version type must have
/// to participate in schema migrations. Conforming types must be:
///
/// - `Equatable`: to check whether two versions are equal
/// - `Comparable`: to compare versions and determine ordering
/// - `Hashable`: to use versions as dictionary keys or in sets
/// - `Sendable`: to ensure safe use in concurrent contexts
///
/// Use this alias as a base constraint when defining custom version types
/// for use with ``VersionStorage``.
///
/// ```swift
/// struct SemanticVersion: VersionRepresentable {
///     let major: Int
///     let minor: Int
///     let patch: Int
///
///     static func < (lhs: Self, rhs: Self) -> Bool {
///         if lhs.major != rhs.major {
///             return lhs.major < rhs.major
///         }
///         if lhs.minor != rhs.minor {
///             return lhs.minor < rhs.minor
///         }
///         return lhs.patch < rhs.patch
///     }
/// }
/// ```
public typealias VersionRepresentable = Equatable & Comparable & Hashable & Sendable
