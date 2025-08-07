import Foundation
import DataLiteCore

/// Errors that may occur during migration registration or execution.
public enum MigrationError<Version: VersionRepresentable>: Error {
    /// A migration with the same version or script URL was already registered.
    case duplicateMigration(Migration<Version>)
    
    /// Migration execution failed, with optional reference to the failed migration.
    case migrationFailed(Migration<Version>?, Error)
    
    /// The migration script is empty.
    case emptyMigrationScript(Migration<Version>)
}
