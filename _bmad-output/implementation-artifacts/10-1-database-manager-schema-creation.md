# Story 10.1: Database Manager & Schema Creation

Status: done

## Story

As a developer using Claude Code,
I want cc-hdrm to create and manage a SQLite database for historical data,
So that poll snapshots can be persisted reliably across app restarts.

## Acceptance Criteria

1. **Given** the app launches for the first time after Phase 3 upgrade
   **When** DatabaseManager initializes
   **Then** it creates a SQLite database at `~/Library/Application Support/cc-hdrm/usage.db`
   **And** the database contains table `usage_polls` with columns: id (INTEGER PRIMARY KEY), timestamp (INTEGER), five_hour_util (REAL), five_hour_resets_at (INTEGER nullable), seven_day_util (REAL), seven_day_resets_at (INTEGER nullable)
   **And** the database contains table `usage_rollups` with columns: id, period_start, period_end, resolution (TEXT), five_hour_avg, five_hour_peak, five_hour_min, seven_day_avg, seven_day_peak, seven_day_min, reset_count, waste_credits
   **And** the database contains table `reset_events` with columns: id, timestamp, five_hour_peak, seven_day_util, tier, used_credits, constrained_credits, waste_credits
   **And** indexes exist on: usage_polls(timestamp), usage_rollups(resolution, period_start), reset_events(timestamp)
   **And** DatabaseManager conforms to DatabaseManagerProtocol for testability

2. **Given** the app launches on subsequent runs
   **When** DatabaseManager initializes
   **Then** it opens the existing database without recreating tables
   **And** schema version is tracked for future migrations

3. **Given** the database file is corrupted or inaccessible
   **When** DatabaseManager attempts to open
   **Then** the error is logged via os.Logger (database category)
   **And** the app continues functioning without historical features (graceful degradation)
   **And** real-time usage display continues working normally

## Tasks / Subtasks

- [x] Task 1: Create DatabaseManagerProtocol (AC: #1)
  - [x] 1.1 Create `cc-hdrm/Services/DatabaseManagerProtocol.swift`
  - [x] 1.2 Define protocol with: `getConnection() throws -> Connection`, `ensureSchema() throws`, `runMigrations() throws`, `getDatabasePath() -> URL`
  - [x] 1.3 Define `DatabaseError` cases in `AppError.swift` or dedicated enum

- [x] Task 2: Create DatabaseManager implementation (AC: #1, #2)
  - [x] 2.1 Create `cc-hdrm/Services/DatabaseManager.swift`
  - [x] 2.2 Implement singleton pattern with lazy initialization
  - [x] 2.3 Implement `getOrCreateDatabaseDirectory()` for `~/Library/Application Support/cc-hdrm/`
  - [x] 2.4 Implement SQLite connection opening with `sqlite3_open_v2`
  - [x] 2.5 Implement `ensureSchema()` for first-launch table creation
  - [x] 2.6 Implement schema version tracking via `PRAGMA user_version`
  - [x] 2.7 Add `os.Logger` with category `"database"`

- [x] Task 3: Implement usage_polls table (AC: #1)
  - [x] 3.1 CREATE TABLE statement with proper types
  - [x] 3.2 CREATE INDEX on timestamp column
  - [x] 3.3 Verify schema with test insert/select

- [x] Task 4: Implement usage_rollups table (AC: #1)
  - [x] 4.1 CREATE TABLE statement with all columns
  - [x] 4.2 CREATE INDEX on (resolution, period_start)
  - [x] 4.3 Verify schema with test insert/select

- [x] Task 5: Implement reset_events table (AC: #1)
  - [x] 5.1 CREATE TABLE statement with all columns
  - [x] 5.2 CREATE INDEX on timestamp
  - [x] 5.3 Verify schema with test insert/select

- [x] Task 6: Implement graceful degradation (AC: #3)
  - [x] 6.1 Wrap all database operations in do-catch
  - [x] 6.2 Log errors at `.error` level
  - [x] 6.3 Return nil/empty results on failure without crashing
  - [x] 6.4 Ensure AppState/polling continues without database

- [x] Task 7: Write unit tests (AC: #1, #2, #3)
  - [x] 7.1 Create `cc-hdrmTests/Services/DatabaseManagerTests.swift`
  - [x] 7.2 Test schema creation on fresh database
  - [x] 7.3 Test idempotent schema (re-run doesn't recreate)
  - [x] 7.4 Test graceful degradation with invalid path
  - [x] 7.5 Test migration path (schema version increments)

## Dev Notes

### Architecture Context

This is the **first persistent storage** in cc-hdrm. Phase 1-2 were entirely in-memory. This story introduces SQLite for historical data that persists across app restarts.

**Database Location:** `~/Library/Application Support/cc-hdrm/usage.db`
- Standard macOS convention for application data
- Survives app updates, separate from app bundle
- Directory may not exist on first launch — create it

### SQLite Implementation Approach

**Use raw SQLite C API via Swift** (no external dependencies):
```swift
import SQLite3

var db: OpaquePointer?
let result = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
```

**Why not GRDB/SQLite.swift?** Zero external dependencies is a project constraint (NFR). The C API is sufficient for our simple schema.

### Schema Definition

```sql
-- Table: usage_polls (raw poll data, < 24h retention at full resolution)
CREATE TABLE IF NOT EXISTS usage_polls (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    five_hour_util REAL,
    five_hour_resets_at INTEGER,
    seven_day_util REAL,
    seven_day_resets_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_usage_polls_timestamp ON usage_polls(timestamp);

-- Table: usage_rollups (aggregated data at decreasing resolution)
CREATE TABLE IF NOT EXISTS usage_rollups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    period_start INTEGER NOT NULL,
    period_end INTEGER NOT NULL,
    resolution TEXT NOT NULL,  -- '5min' | 'hourly' | 'daily'
    five_hour_avg REAL,
    five_hour_peak REAL,
    five_hour_min REAL,
    seven_day_avg REAL,
    seven_day_peak REAL,
    seven_day_min REAL,
    reset_count INTEGER DEFAULT 0,
    waste_credits REAL
);
CREATE INDEX IF NOT EXISTS idx_usage_rollups_resolution_period 
    ON usage_rollups(resolution, period_start);

-- Table: reset_events (captures each 5h window reset)
CREATE TABLE IF NOT EXISTS reset_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    five_hour_peak REAL,
    seven_day_util REAL,
    tier TEXT,
    used_credits REAL,
    constrained_credits REAL,
    waste_credits REAL
);
CREATE INDEX IF NOT EXISTS idx_reset_events_timestamp ON reset_events(timestamp);

-- Schema version tracking
PRAGMA user_version = 1;
```

### Schema Version Strategy

Use SQLite's `PRAGMA user_version` for migration tracking:
```swift
func getSchemaVersion() throws -> Int {
    var statement: OpaquePointer?
    sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil)
    sqlite3_step(statement)
    let version = sqlite3_column_int(statement, 0)
    sqlite3_finalize(statement)
    return Int(version)
}

func setSchemaVersion(_ version: Int) throws {
    sqlite3_exec(db, "PRAGMA user_version = \(version)", nil, nil, nil)
}
```

### Error Handling Pattern

Add database errors to `AppError.swift`:
```swift
enum AppError: Error, Sendable, Equatable {
    // ... existing cases ...
    case databaseOpenFailed(path: String)
    case databaseSchemaFailed(underlying: any Error & Sendable)
    case databaseQueryFailed(underlying: any Error & Sendable)
}
```

### Logging Pattern

Follow existing codebase pattern:
```swift
private static let logger = Logger(
    subsystem: "com.cc-hdrm.app",
    category: "database"
)

// Usage:
Self.logger.info("Database opened at \(path, privacy: .public)")
Self.logger.error("Failed to create schema: \(error.localizedDescription)")
```

### Graceful Degradation Approach

**Critical:** Database failures must NEVER crash the app or disrupt real-time usage display.

```swift
final class DatabaseManager: DatabaseManagerProtocol {
    private var db: OpaquePointer?
    private(set) var isAvailable: Bool = false
    
    func initialize() {
        do {
            try ensureDirectory()
            try openDatabase()
            try ensureSchema()
            isAvailable = true
            Self.logger.info("Database initialized successfully")
        } catch {
            isAvailable = false
            Self.logger.error("Database initialization failed: \(error.localizedDescription) — historical features disabled")
            // App continues without historical features
        }
    }
}
```

### Service Integration (Future Story)

This story creates the foundation. Story 10.2 (HistoricalDataService) will:
1. Depend on DatabaseManager
2. Be wired into AppDelegate alongside other services
3. Be called from PollingEngine after each successful poll

**Do NOT wire DatabaseManager into AppDelegate in this story** — that happens in Story 10.2 when HistoricalDataService is created.

### Testing Strategy

Use a temporary database path for tests:
```swift
func testSchemaCreation() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: testPath) }
    
    let manager = DatabaseManager(databasePath: testPath)
    try manager.ensureSchema()
    
    // Verify tables exist
    XCTAssertTrue(manager.tableExists("usage_polls"))
    XCTAssertTrue(manager.tableExists("usage_rollups"))
    XCTAssertTrue(manager.tableExists("reset_events"))
}
```

### Project Structure Notes

**New files to create:**
```
cc-hdrm/Services/
├── DatabaseManagerProtocol.swift    # NEW
└── DatabaseManager.swift            # NEW

cc-hdrmTests/Services/
└── DatabaseManagerTests.swift       # NEW
```

**Alignment with architecture.md:**
- Layer-based organization: Services/ folder (confirmed)
- Protocol-based interfaces for testability (confirmed)
- Single `os.Logger` per service with specific category (confirmed)

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Data Layer Architecture] — SQLite schema, rollup strategy
- [Source: _bmad-output/planning-artifacts/architecture.md#Database Location] — `~/Library/Application Support/cc-hdrm/usage.db`
- [Source: _bmad-output/planning-artifacts/architecture.md#DatabaseManager] — Protocol definition, responsibility
- [Source: _bmad-output/planning-artifacts/epics.md#Story 10.1] — Acceptance criteria
- [Source: cc-hdrm/Services/PreferencesManager.swift] — Service pattern example
- [Source: cc-hdrm/Models/AppError.swift] — Error handling pattern

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

None required - all tests passing, no debugging needed.

### Completion Notes List

- Implemented DatabaseManagerProtocol with getConnection(), ensureSchema(), runMigrations(), getDatabasePath(), getSchemaVersion(), isAvailable
- Implemented DatabaseManager with singleton pattern, SQLite C API (no external dependencies)
- Database location: `~/Library/Application Support/cc-hdrm/usage.db`
- Created three tables: usage_polls, usage_rollups, reset_events with proper indexes
- Schema version tracking via PRAGMA user_version (version 1)
- Graceful degradation: isAvailable flag allows app to continue without historical features if DB fails
- Added tableExists() and indexExists() helper methods for test verification
- Comprehensive unit tests: 18 new tests covering schema creation, idempotency, graceful degradation, migrations, and CRUD operations
- All 384 tests passing (18 new + 366 existing)

### File List

**New Files:**
- cc-hdrm/Services/DatabaseManagerProtocol.swift
- cc-hdrm/Services/DatabaseManager.swift
- cc-hdrmTests/Services/DatabaseManagerTests.swift

**Modified Files:**
- cc-hdrm/Models/AppError.swift (added database error cases)

**Note:** `cc-hdrm.xcodeproj/project.pbxproj` is modified but excluded from git (in .gitignore).

### Code Review Fixes (2026-02-03)

**Issues Fixed:**
1. **SQLITE_TRANSIENT** - Fixed memory safety bug in `sqlite3_bind_text` calls that used SQLITE_STATIC with temporary `withCString` buffers
2. **Thread safety** - Made `@unchecked Sendable` safe by protecting all mutable state (`db`, `_isAvailable`) with the internal lock
3. **Test cleanup** - Added `closeConnection()` method and updated all tests to close connections before deleting database files (eliminates SQLite warnings)
4. **Migration test** - Added test verifying migration path preserves data
