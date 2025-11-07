import Foundation

public extension NotificationCenter {
    /// The notification center dedicated to database events.
    ///
    /// Use this instance to post and observe notifications related to database lifecycle and
    /// operations instead of using the shared `NotificationCenter.default`.
    static let database = NotificationCenter()
}
