import Foundation
import SQLite3

/// Protocol for database management and SQLite operations.
/// DatabaseManager is the ONLY component that manages the SQLite database.
protocol DatabaseManagerProtocol: AnyObject, Sendable {
    /// Returns the current database connection, opening it if necessary.
    /// - Returns: An OpaquePointer to the SQLite database connection
    /// - Throws: `AppError.databaseOpenFailed` if the database cannot be opened
    func getConnection() throws -> OpaquePointer

    /// Ensures all required tables and indexes exist.
    /// Creates schema on first launch, no-op on subsequent launches.
    /// - Throws: `AppError.databaseSchemaFailed` if schema creation fails
    func ensureSchema() throws

    /// Runs any pending database migrations based on schema version.
    /// - Throws: `AppError.databaseSchemaFailed` if migrations fail
    func runMigrations() throws

    /// Returns the path to the database file.
    /// - Returns: URL to the database file at `~/Library/Application Support/cc-hdrm/usage.db`
    func getDatabasePath() -> URL

    /// Indicates whether the database is available and operational.
    /// When `false`, historical features are disabled but app continues functioning.
    var isAvailable: Bool { get }

    /// Returns the current schema version from `PRAGMA user_version`.
    /// - Returns: The schema version number, or 0 if not set
    func getSchemaVersion() throws -> Int

    /// Closes the database connection.
    /// Primarily used in tests for cleanup before deleting test database files.
    func closeConnection()
}
