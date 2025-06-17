import Foundation
import DataLiteCore

/// Represents a database migration step associated with a specific version.
///
/// Each `Migration` contains a reference to a migration script file (usually a `.sql` file) and the
/// version to which this script corresponds. The script is expected to be bundled with the application.
///
/// You can initialize a migration directly with a URL to the script, or load it from a resource
/// embedded in a bundle.
public struct Migration<Version: VersionRepresentable>: Hashable, Sendable {
    // MARK: - Properties
    
    /// The version associated with this migration step.
    public let version: Version
    
    /// The URL pointing to the migration script (e.g., an SQL file).
    public let scriptURL: URL
    
    /// The SQL script associated with this migration.
    ///
    /// This computed property reads the contents of the file at `scriptURL` and returns it as a
    /// `SQLScript` instance. Use this to access and execute the migration's SQL commands.
    ///
    /// - Throws: An error if the script file cannot be read or is invalid.
    public var script: SQLScript {
        get throws {
            try SQLScript(contentsOf: scriptURL)
        }
    }
    
    // MARK: - Inits
    
    /// Creates a migration with a specified version and script URL.
    ///
    /// - Parameters:
    ///   - version: The version this migration corresponds to.
    ///   - scriptURL: The file URL to the migration script.
    public init(version: Version, scriptURL: URL) {
        self.version = version
        self.scriptURL = scriptURL
    }
    
    /// Creates a migration by locating a script resource in the specified bundle.
    ///
    /// This initializer attempts to locate a script file in the provided bundle using the specified
    /// resource `name` and optional `extension`. The `name` parameter may include or omit the file extension.
    ///
    /// - If `name` includes an extension (e.g., `"001_init.sql"`), pass `extension` as `nil` or an empty string.
    /// - If `name` omits the extension (e.g., `"001_init"`), specify the extension separately
    ///   (e.g., `"sql"`), or leave it `nil` if the file has no extension.
    ///
    /// - Important: Passing a name that already includes the extension while also specifying a non-`nil`
    ///   `extension` may result in failure to locate the file.
    ///
    /// - Parameters:
    ///   - version: The version this migration corresponds to.
    ///   - name: The resource name of the script file. May include or omit the file extension.
    ///   - extension: The file extension, if separated from the name. Defaults to `nil`.
    ///   - bundle: The bundle in which to search for the resource. Defaults to `.main`.
    ///
    /// - Returns: A `Migration` if the resource file is found; otherwise, `nil`.
    public init?(
        version: Version,
        byResource name: String,
        extension: String? = nil,
        in bundle: Bundle = .main
    ) {
        guard let url = bundle.url(
            forResource: name,
            withExtension: `extension`
        ) else { return nil }
        self.init(version: version, scriptURL: url)
    }
}
