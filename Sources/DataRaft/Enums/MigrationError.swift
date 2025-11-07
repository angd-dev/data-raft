import Foundation
import DataLiteCore

/// Errors that can occur during database migration registration or execution.
///
/// ## Overview
///
/// These errors indicate problems such as duplicate migrations, failed execution, or empty
/// migration scripts.
///
/// ## Topics
///
/// ### Error Cases
/// - ``duplicateMigration(_:)``
/// - ``emptyMigrationScript(_:)``
/// - ``migrationFailed(_:_:)``
public enum MigrationError<Version: VersionRepresentable>: Error {
    /// Indicates that a migration with the same version or script URL has already been registered.
    ///
    /// - Parameter migration: The duplicate migration instance.
    case duplicateMigration(Migration<Version>)
    
    /// Indicates that the migration script is empty.
    ///
    /// - Parameter migration: The migration whose script is empty.
    case emptyMigrationScript(Migration<Version>)
    
    /// Indicates that migration execution failed.
    ///
    /// - Parameters:
    ///   - migration: The migration that failed, if available.
    ///   - error: The underlying error that caused the failure.
    case migrationFailed(Migration<Version>?, Error)
}
