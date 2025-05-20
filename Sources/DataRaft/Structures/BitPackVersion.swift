import Foundation

public struct BitPackVersion: VersionRepresentable, RawRepresentable, CustomStringConvertible {
    public enum Error: Swift.Error {
        case majorOverflow(UInt32)
        case minorOverflow(UInt32)
        case patchOverflow(UInt32)
        
        public var localizedDescription: String {
            switch self {
            case .majorOverflow(let value):
                "Major version overflow: \(value). Allowed range: 0...4095"
            case .minorOverflow(let value):
                "Minor version overflow: \(value). Allowed range: 0...4095"
            case .patchOverflow(let value):
                "Patch version overflow: \(value). Allowed range: 0...255"
            }
        }
    }
    
    // MARK: - Properties
    
    public let rawValue: UInt32
    
    public var major: UInt32 { (rawValue >> 20) & 0xFFF }
    public var minor: UInt32 { (rawValue >> 8) & 0xFFF }
    public var patch: UInt32 { rawValue & 0xFF }
    
    public var description: String {
        "\(major).\(minor).\(patch)"
    }
    
    // MARK: - Inits
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    public init(major: UInt32, minor: UInt32, patch: UInt32 = 0) throws {
        guard major < (1 << 12) else { throw Error.majorOverflow(major) }
        guard minor < (1 << 12) else { throw Error.minorOverflow(minor) }
        guard patch < (1 << 8) else { throw Error.patchOverflow(patch) }
        self.init(rawValue: (major << 20) | (minor << 8) | patch)
    }
    
    // MARK: - Comparable
    
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - ExpressibleByStringLiteral

@available(iOS 16.0, *)
@available(macOS 13.0, *)
extension BitPackVersion: ExpressibleByStringLiteral {
    public enum ParseError: Swift.Error {
        case invalidFormat(String)
        
        public var localizedDescription: String {
            switch self {
            case .invalidFormat(let str):
                "Invalid version format: \(str). Expected something like '1.2' or '1.2.3'."
            }
        }
    }
    
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
    
    public init(stringLiteral value: String) {
        try! self.init(version: value)
    }
}
