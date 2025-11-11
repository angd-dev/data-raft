import Foundation

/// A database migration step for a specific schema version.
///
/// ## Overview
///
/// Each migration links a version identifier with a script file that modifies the database schema.
/// Scripts are typically bundled with the application and executed sequentially during version
/// upgrades.
///
/// ## Topics
///
/// ### Properties
/// - ``version``
/// - ``scriptURL``
/// - ``script``
///
/// ### Initializers
/// - ``init(version:scriptURL:)``
/// - ``init(version:byResource:extension:in:)``
public struct Migration<Version: VersionRepresentable>: Hashable, Sendable {
    // MARK: - Properties
    
    /// The version associated with this migration step.
    public let version: Version
    
    /// The file URL of the migration script (for example, an SQL file).
    public let scriptURL: URL
    
    /// The migration script as a string.
    ///
    /// Reads the contents of the file at ``scriptURL`` and trims surrounding whitespace and
    /// newlines.
    ///
    /// - Throws: An error if the script file cannot be read.
    public var script: String {
        get throws {
            try String(contentsOf: scriptURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    // MARK: - Inits
    
    /// Creates a migration with the specified version and script URL.
    ///
    /// - Parameters:
    ///   - version: The version this migration corresponds to.
    ///   - scriptURL: The URL of the script file to execute.
    public init(version: Version, scriptURL: URL) {
        self.version = version
        self.scriptURL = scriptURL
    }
    
    /// Creates a migration by locating a script resource in the specified bundle.
    ///
    /// Searches the given bundle for a script resource matching the provided name and optional file
    /// extension.
    ///
    /// - Parameters:
    ///   - version: The version this migration corresponds to.
    ///   - name: The resource name of the script file. Can include or omit its extension.
    ///   - extension: The file extension, if separate from the name. Defaults to `nil`.
    ///   - bundle: The bundle in which to look for the resource. Defaults to `.main`.
    ///
    /// - Returns: A `Migration` instance if the resource is found; otherwise, `nil`.
    public init?(
        version: Version,
        byResource name: String,
        extension: String? = nil,
        in bundle: Bundle = .main
    ) {
        guard let url = bundle.url(forResource: name, withExtension: `extension`) else {
            return nil
        }
        self.init(version: version, scriptURL: url)
    }
}
