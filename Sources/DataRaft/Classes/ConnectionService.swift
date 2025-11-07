import Foundation
import DataLiteCore

/// A base service responsible for establishing and maintaining a database connection.
///
/// ## Overview
///
/// `ConnectionService` provides a managed execution environment for database operations. It handles
/// connection creation, configuration, encryption key application, and optional reconnection based
/// on the associated key provider’s policy.
///
/// This class guarantees thread-safe access by executing all operations within a dedicated dispatch
/// queue. Subclasses may extend it with additional behaviors, such as transaction management or
/// lifecycle event posting.
///
/// ## Topics
///
/// ### Creating a Service
///
/// - ``ConnectionProvider``
/// - ``ConnectionConfig``
/// - ``init(provider:config:queue:)``
/// - ``init(connection:config:queue:)``
///
/// ### Key Management
///
/// - ``ConnectionServiceKeyProvider``
/// - ``keyProvider``
///
/// ### Connection Lifecycle
///
/// - ``setNeedsReconnect()``
///
/// ### Performing Operations
///
/// - ``ConnectionServiceProtocol/Perform``
/// - ``perform(_:)``
open class ConnectionService:
    ConnectionServiceProtocol,
    @unchecked Sendable
{
    // MARK: - Typealiases
    
    /// A closure that creates a new database connection.
    ///
    /// Used for deferred connection creation. Encapsulates initialization logic, configuration, and
    /// error handling when opening the database.
    ///
    /// - Returns: An initialized connection instance.
    /// - Throws: An error if the connection cannot be created or configured.
    public typealias ConnectionProvider = () throws -> ConnectionProtocol
    
    /// A closure that configures a newly created connection.
    ///
    /// Called after the connection is established and, if applicable, after the encryption key has
    /// been applied. Use this closure to set PRAGMA options or perform additional initialization
    /// logic.
    ///
    /// - Parameter connection: The newly created connection to configure.
    /// - Throws: An error if configuration fails.
    public typealias ConnectionConfig = (ConnectionProtocol) throws -> Void
    
    // MARK: - Properties
    
    private let provider: ConnectionProvider
    private let config: ConnectionConfig?
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    
    private var shouldReconnect: Bool {
        keyProvider?.connectionService(shouldReconnect: self) ?? false
    }
    
    private var needsReconnect: Bool = false
    private var cachedConnection: ConnectionProtocol?
    
    private var connection: ConnectionProtocol {
        get throws {
            guard let cachedConnection, !needsReconnect else {
                let connection = try connect()
                cachedConnection = connection
                needsReconnect = false
                return connection
            }
            return cachedConnection
        }
    }
    
    /// The provider responsible for supplying encryption keys to the service.
    ///
    /// The key provider may determine whether reconnection is allowed and supply
    /// the encryption key when the connection is established or restored.
    public weak var keyProvider: ConnectionServiceKeyProvider?
    
    // MARK: - Inits
    
    /// Creates a new connection service.
    ///
    /// Configures an internal serial queue for thread-safe access to the database. The connection
    /// itself is not created during initialization — it is established lazily on first use (for
    /// example, inside ``perform(_:)``).
    ///
    /// The internal queue is created with QoS `.utility`. If `queue` is provided, it becomes the
    /// target of the internal queue.
    ///
    /// - Parameters:
    ///   - provider: A closure that returns a new database connection.
    ///   - config: An optional configuration closure called after the connection is established and
    ///     the encryption key is applied.
    ///   - queue: An optional target queue for the internal one.
    public required init(
        provider: @escaping ConnectionProvider,
        config: ConnectionConfig? = nil,
        queue: DispatchQueue? = nil
    ) {
        self.provider = provider
        self.config = config
        self.queue = .init(for: Self.self, qos: .utility)
        self.queue.setSpecific(key: queueKey, value: ())
        if let queue = queue {
            self.queue.setTarget(queue: queue)
        }
    }
    
    /// Creates a new connection service using an autoclosure-based provider.
    ///
    /// This initializer provides a convenient way to wrap an existing connection expression in an
    /// autoclosure. The connection itself is not created during initialization — it is established
    /// lazily on first use.
    ///
    /// - Parameters:
    ///   - provider: An autoclosure that returns a new database connection.
    ///   - config: An optional configuration closure called after the connection is established and
    ///     the encryption key is applied.
    ///   - queue: An optional target queue for the internal one.
    public required convenience init(
        connection provider: @escaping @autoclosure ConnectionProvider,
        config: ConnectionConfig? = nil,
        queue: DispatchQueue? = nil
    ) {
        self.init(provider: provider, config: config, queue: queue)
    }
    
    // MARK: - Connection Lifecycle
    
    /// Marks the service as requiring reconnection before the next operation.
    ///
    /// The reconnection behavior depends on the key provider’s implementation of
    /// ``ConnectionServiceKeyProvider/connectionService(shouldReconnect:)``. If reconnection is
    /// allowed, the next access to the connection will create and configure a new one.
    ///
    /// - Returns: `true` if the reconnection flag was set; otherwise, `false`.
    @discardableResult
    public func setNeedsReconnect() -> Bool {
        switch DispatchQueue.getSpecific(key: queueKey) {
        case .none:
            return queue.sync { setNeedsReconnect() }
        case .some:
            guard shouldReconnect else { return false }
            needsReconnect = true
            return true
        }
    }
    
    // MARK: - Performing Operations
    
    /// Executes a closure within the context of a managed database connection.
    ///
    /// Runs the operation on the service’s internal queue and ensures that the connection is valid
    /// before use. If the connection is unavailable or fails during execution, this method throws
    /// an error.
    ///
    /// - Parameter closure: The operation to perform using the connection.
    /// - Returns: The result produced by the closure.
    /// - Throws: An error thrown by the closure or the connection.
    public func perform<T>(_ closure: Perform<T>) throws -> T {
        switch DispatchQueue.getSpecific(key: queueKey) {
        case .none: try queue.sync { try closure(connection) }
        case .some: try closure(connection)
        }
    }
    
    // MARK: - Internal Methods
    
    func connect() throws -> ConnectionProtocol {
        let connection = try provider()
        try applyKey(to: connection)
        try config?(connection)
        return connection
    }
    
    func applyKey(to connection: ConnectionProtocol) throws {
        guard let keyProvider = keyProvider else { return }
        do {
            let key = try keyProvider.connectionService(keyFor: self)
            let sql = "SELECT count(*) FROM sqlite_master"
            try connection.apply(key, name: nil)
            try connection.execute(sql: sql)
        } catch {
            keyProvider.connectionService(self, didReceive: error)
            throw error
        }
    }
}
