import Foundation

/// A semantic version packed into a 32-bit unsigned integer.
///
/// This type stores a `major.minor.patch` version using bit fields inside a single `UInt32`:
///
/// - 12 bits for `major` in the 0...4095 range
/// - 12 bits for `minor`in the 0...4095 range
/// - 8 bits for `patch` in the 0...255 range
///
/// ## Topics
///
/// ### Errors
///
/// - ``Error``
/// - ``ParseError``
///
/// ### Creating a Version
///
/// - ``init(rawValue:)``
/// - ``init(major:minor:patch:)``
/// - ``init(version:)``
/// - ``init(stringLiteral:)``
///
/// ### Instance Properties
///
/// - ``rawValue``
/// - ``major``
/// - ``minor``
/// - ``patch``
/// - ``description``
public struct BitPackVersion: VersionRepresentable, RawRepresentable, CustomStringConvertible {
    /// An error related to invalid version components.
    public enum Error: Swift.Error {
        /// An error for a major component that exceeds the allowed range.
        case majorOverflow(UInt32)
        
        /// An error for a minor component that exceeds the allowed range.
        case minorOverflow(UInt32)
        
        /// An error for a patch component that exceeds the allowed range.
        case patchOverflow(UInt32)
        
        /// A message describing the reason for the error.
        public var localizedDescription: String {
            switch self {
            case .majorOverflow(let value):
                "Major version overflow: \(value). Allowed range: 0...4095."
            case .minorOverflow(let value):
                "Minor version overflow: \(value). Allowed range: 0...4095."
            case .patchOverflow(let value):
                "Patch version overflow: \(value). Allowed range: 0...255."
            }
        }
    }
    
    // MARK: - Properties
    
    /// The packed 32-bit value that encodes the version.
    public let rawValue: UInt32
    
    /// The major component of the version.
    public var major: UInt32 { (rawValue >> 20) & 0xFFF }
    
    /// The minor component of the version.
    public var minor: UInt32 { (rawValue >> 8) & 0xFFF }
    
    /// The patch component of the version.
    public var patch: UInt32 { rawValue & 0xFF }
    
    /// A string representation in the form `"major.minor.patch"`.
    public var description: String {
        "\(major).\(minor).\(patch)"
    }
    
    // MARK: - Inits
    
    /// Creates a version from a packed 32-bit unsigned integer.
    ///
    /// - Parameter rawValue: A bit-packed version value.
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    /// Creates a version from individual components.
    ///
    /// - Parameters:
    ///   - major: The major component in the 0...4095 range.
    ///   - minor: The minor component in the 0...4095 range.
    ///   - patch: The patch component in the 0...255 range. Defaults to `0`.
    ///
    /// - Throws: ``Error/majorOverflow(_:)`` if `major` is out of range.
    /// - Throws: ``Error/minorOverflow(_:)`` if `minor` is out of range.
    /// - Throws: ``Error/patchOverflow(_:)`` if `patch` is out of range.
    public init(major: UInt32, minor: UInt32, patch: UInt32 = 0) throws {
        guard major < (1 << 12) else { throw Error.majorOverflow(major) }
        guard minor < (1 << 12) else { throw Error.minorOverflow(minor) }
        guard patch < (1 << 8) else { throw Error.patchOverflow(patch) }
        self.init(rawValue: (major << 20) | (minor << 8) | patch)
    }
    
    // MARK: - Comparable
    
    /// Compares two versions by their packed 32-bit values.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - ExpressibleByStringLiteral

@available(iOS 16.0, *)
@available(macOS 13.0, *)
extension BitPackVersion: ExpressibleByStringLiteral {
    /// An error related to parsing a version string.
    public enum ParseError: Swift.Error {
        /// A string that doesn't match the expected version format.
        case invalidFormat(String)
        
        /// A message describing the format issue.
        public var localizedDescription: String {
            switch self {
            case .invalidFormat(let str):
                "Invalid version format: \(str). Expected something like '1.2' or '1.2.3'."
            }
        }
    }
    
    /// Creates a version by parsing a string like `"1.2"` or `"1.2.3"`.
    ///
    /// - Parameter version: A version string in the form `x.y` or `x.y.z`.
    ///
    /// - Throws: ``ParseError/invalidFormat(_:)`` if the string format is invalid.
    /// - Throws: `Error` if any component is out of range.
    public init(version: String) throws {
        let regex = /^(0|[1-9]\d*)\.(0|[1-9]\d*)(?:\.(0|[1-9]\d*))?$/
        guard version.wholeMatch(of: regex) != nil else {
            throw ParseError.invalidFormat(version)
        }
        
        let parts = version.split(separator: ".")
            .compactMap { UInt32($0) }
        
        try self.init(
            major: parts[0],
            minor: parts[1],
            patch: parts.count == 3 ? parts[2] : 0
        )
    }
    
    /// Creates a version from a string literal like `"1.2"` or `"1.2.3"`.
    ///
    /// - Warning: Crashes if the string format is invalid.
    /// Use ``init(version:)`` for safe parsing.
    public init(stringLiteral value: String) {
        try! self.init(version: value)
    }
}
