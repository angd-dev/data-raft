import Foundation

extension Notification {
    /// A strongly typed key used to access values in a notification’s user info dictionary.
    ///
    /// ## Overview
    ///
    /// `UserInfoKey` provides type safety when working with `Notification.userInfo`, replacing raw
    /// string literals with well-defined constants. This helps prevent typos and improves
    /// discoverability in database- or system-related notifications.
    ///
    /// ## Topics
    ///
    /// ### Keys
    ///
    /// - ``action``
    public struct UserInfoKey: RawRepresentable, Hashable, Sendable {
        /// The raw string value of the key.
        public let rawValue: String
        
        /// The key used to store the action associated with a notification.
        public static let action = Self(rawValue: "action")
        
        /// Creates a user info key from the provided raw string value.
        ///
        /// Returns `nil` if the raw value is invalid.
        ///
        /// - Parameter rawValue: The raw string value of the key.
        public init?(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}
