import Foundation

public struct Migration<Version: VersionRepresentable>: Hashable {
    // MARK: - Properties
    
    public let version: Version
    public let scriptURL: URL
    
    // MARK: - Inits
    
    public init(version: Version, scriptURL: URL) {
        self.version = version
        self.scriptURL = scriptURL
    }
    
    public init?(
        version: Version,
        byResource name: String?,
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
