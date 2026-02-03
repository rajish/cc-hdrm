# Story 10.2: Historical Data Service & Poll Persistence

Status: done

## Story

As a developer using Claude Code,
I want each poll snapshot to be automatically persisted,
So that I build a historical record without any manual action.

## Acceptance Criteria

1. **Given** a successful poll cycle completes with valid usage data
   **When** PollingEngine receives the UsageResponse
   **Then** HistoricalDataService.persistPoll() is called with the response data
   **And** a new row is inserted into usage_polls with current timestamp and utilization values
   **And** persistence happens asynchronously (does not block UI updates)
   **And** HistoricalDataService conforms to HistoricalDataServiceProtocol for testability

2. **Given** the database write fails
   **When** persistPoll() encounters an error
   **Then** the error is logged via os.Logger
   **And** the poll cycle is not retried (data for this cycle is lost)
   **And** the app continues functioning - subsequent polls attempt persistence normally

3. **Given** the app has been running for 24+ hours
   **When** the database is inspected
   **Then** it contains one row per successful poll (~1440 rows for 30-second intervals over 24h)
   **And** no duplicate timestamps exist

## Tasks / Subtasks

- [x] Task 1: Create HistoricalDataServiceProtocol (AC: #1)
  - [x] 1.1 Create `cc-hdrm/Services/HistoricalDataServiceProtocol.swift`
  - [x] 1.2 Define protocol with methods: `persistPoll(_ response: UsageResponse) async throws`, `getRecentPolls(hours: Int) async throws -> [UsagePoll]`, `getDatabaseSize() async throws -> Int64`
  - [x] 1.3 Define `UsagePoll` model struct in `cc-hdrm/Models/UsagePoll.swift`

- [x] Task 2: Create HistoricalDataService implementation (AC: #1, #2, #3)
  - [x] 2.1 Create `cc-hdrm/Services/HistoricalDataService.swift`
  - [x] 2.2 Implement dependency injection of `DatabaseManagerProtocol`
  - [x] 2.3 Implement `persistPoll()` with INSERT statement
  - [x] 2.4 Implement timestamp as Unix milliseconds (`Int64(Date().timeIntervalSince1970 * 1000)`)
  - [x] 2.5 Convert `resetsAt` ISO8601 string to Unix ms for storage
  - [x] 2.6 Add `os.Logger` with category `"historical"`
  - [x] 2.7 Implement graceful degradation: check `databaseManager.isAvailable` before operations

- [x] Task 3: Integrate with PollingEngine (AC: #1)
  - [x] 3.1 Add `historicalDataService: (any HistoricalDataServiceProtocol)?` parameter to PollingEngine init
  - [x] 3.2 Call `persistPoll()` in `fetchUsageData()` after successful API response
  - [x] 3.3 Use `Task { }` to make persistence async (fire-and-forget, no await blocking UI)
  - [x] 3.4 Catch errors in the Task and log without disrupting poll cycle

- [x] Task 4: Wire service in AppDelegate (AC: #1)
  - [x] 4.1 Create HistoricalDataService instance in AppDelegate
  - [x] 4.2 Initialize DatabaseManager on app startup (call `DatabaseManager.shared.initialize()`)
  - [x] 4.3 Pass HistoricalDataService to PollingEngine

- [x] Task 5: Implement getRecentPolls query (AC: #3)
  - [x] 5.1 Implement SELECT query with timestamp filter
  - [x] 5.2 Order results by timestamp ascending
  - [x] 5.3 Map SQLite rows to UsagePoll structs

- [x] Task 6: Write unit tests (AC: #1, #2, #3)
  - [x] 6.1 Create `cc-hdrmTests/Services/HistoricalDataServiceTests.swift`
  - [x] 6.2 Test persistPoll inserts correct data
  - [x] 6.3 Test getRecentPolls returns correct time range
  - [x] 6.4 Test graceful degradation when database unavailable
  - [x] 6.5 Test no duplicate timestamps on rapid calls
  - [x] 6.6 Create `cc-hdrmTests/Models/UsagePollTests.swift` for model tests

## Dev Notes

### Architecture Context

This story builds on Story 10.1 (DatabaseManager). The HistoricalDataService is the primary consumer of the database, responsible for all poll data persistence and retrieval.

**Data Flow:**
```
PollingEngine -> APIClient.fetchUsage() -> UsageResponse
                                             |
                                             v
                           HistoricalDataService.persistPoll()
                                             |
                                             v
                           DatabaseManager -> SQLite (usage_polls table)
```

### HistoricalDataServiceProtocol Definition

From architecture.md, the full protocol includes methods for future stories. For Story 10.2, implement only what's needed:

```swift
protocol HistoricalDataServiceProtocol: Sendable {
    /// Persists a poll snapshot to the database.
    /// - Parameter response: The usage response from the API
    /// - Throws: Database errors (caller should handle gracefully)
    func persistPoll(_ response: UsageResponse) async throws
    
    /// Retrieves recent poll data.
    /// - Parameter hours: Number of hours to look back
    /// - Returns: Array of poll records ordered by timestamp ascending
    func getRecentPolls(hours: Int) async throws -> [UsagePoll]
    
    /// Returns the current database file size in bytes.
    func getDatabaseSize() async throws -> Int64
}
```

**Note:** Methods for rollups, reset events, and pruning are defined in the protocol but implementation is deferred to Stories 10.3-10.5.

### UsagePoll Model

```swift
/// Represents a single poll snapshot stored in the database.
struct UsagePoll: Sendable, Equatable {
    let id: Int64
    let timestamp: Int64  // Unix milliseconds
    let fiveHourUtil: Double?
    let fiveHourResetsAt: Int64?  // Unix milliseconds
    let sevenDayUtil: Double?
    let sevenDayResetsAt: Int64?  // Unix milliseconds
}
```

### Timestamp Handling

- **Storage format:** Unix milliseconds (Int64) for precise timestamp storage
- **Conversion from API:** `resetsAt` is ISO8601 string -> parse with `Date.fromISO8601()` -> convert to Unix ms
- **Current time:** `Int64(Date().timeIntervalSince1970 * 1000)`

```swift
// In HistoricalDataService.persistPoll()
let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
let fiveHourResetsAt = response.fiveHour?.resetsAt
    .flatMap { Date.fromISO8601($0) }
    .map { Int64($0.timeIntervalSince1970 * 1000) }
```

### SQL Insert Statement

```sql
INSERT INTO usage_polls (
    timestamp, 
    five_hour_util, 
    five_hour_resets_at, 
    seven_day_util, 
    seven_day_resets_at
) VALUES (?, ?, ?, ?, ?)
```

Use `sqlite3_bind_int64` for timestamps and `sqlite3_bind_double` for utilization values. Handle NULL values with `sqlite3_bind_null`.

### PollingEngine Integration Pattern

The key integration point is in `PollingEngine.fetchUsageData()` at line 125-157. After successful response:

```swift
private func fetchUsageData(credentials: KeychainCredentials) async {
    do {
        let response = try await apiClient.fetchUsage(token: credentials.accessToken)
        
        // ... existing WindowState creation ...
        
        appState.updateWindows(fiveHour: fiveHourState, sevenDay: sevenDayState)
        
        // NEW: Persist to database asynchronously (fire-and-forget)
        Task {
            do {
                try await historicalDataService?.persistPoll(response)
            } catch {
                Self.logger.error("Failed to persist poll data: \(error.localizedDescription)")
                // Continue without retrying - data for this cycle is lost
            }
        }
        
        await notificationService?.evaluateThresholds(...)
        // ... rest of existing code ...
    } catch {
        // ... existing error handling ...
    }
}
```

**Critical:** Use `Task { }` without await to make persistence non-blocking. The UI update (`appState.updateWindows`) must not wait for database operations.

### Graceful Degradation Pattern

Follow the pattern established in DatabaseManager:

```swift
final class HistoricalDataService: HistoricalDataServiceProtocol {
    private let databaseManager: any DatabaseManagerProtocol
    
    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "historical"
    )
    
    func persistPoll(_ response: UsageResponse) async throws {
        guard databaseManager.isAvailable else {
            Self.logger.debug("Database unavailable - skipping poll persistence")
            return  // Silent skip, not an error
        }
        
        // ... perform insert ...
    }
}
```

### Thread Safety Considerations

- DatabaseManager already uses `SQLITE_OPEN_FULLMUTEX` for thread safety
- HistoricalDataService methods are `async` and will be called from detached Tasks

### Timestamp Uniqueness

AC #3 requires "no duplicate timestamps exist". This is ensured by design rather than schema constraint:
- Polling interval is 30 seconds minimum (configurable, never sub-second)
- Timestamps are Unix milliseconds - collision requires two polls in same millisecond
- The probability of timestamp collision is effectively zero given polling interval
- No UNIQUE constraint added to avoid migration complexity for a non-issue

### Existing Code Patterns to Follow

**Logger pattern** (from DatabaseManager.swift:23-26):
```swift
private static let logger = Logger(
    subsystem: "com.cc-hdrm.app",
    category: "historical"
)
```

**Error handling pattern** (from DatabaseManager.swift):
- Log errors at `.error` level with privacy-safe interpolation
- Throw `AppError` cases for recoverable errors
- Allow caller to decide how to handle

**Service initialization pattern** (from PollingEngine.swift:22-36):
- Accept dependencies via init parameters
- Use protocol types for testability
- Optional dependencies use `(any ProtocolName)?`

### AppDelegate Wiring

In `cc-hdrm/App/AppDelegate.swift`, add:

```swift
// In applicationDidFinishLaunching or similar:
DatabaseManager.shared.initialize()

let historicalDataService = HistoricalDataService(
    databaseManager: DatabaseManager.shared
)

let pollingEngine = PollingEngine(
    keychainService: keychainService,
    tokenRefreshService: tokenRefreshService,
    apiClient: apiClient,
    appState: appState,
    notificationService: notificationService,
    preferencesManager: preferencesManager,
    historicalDataService: historicalDataService  // NEW
)
```

### Testing Strategy

**Unit tests with in-memory/temp database:**
```swift
func testPersistPollInsertsCorrectData() async throws {
    let tempPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("test_\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: tempPath) }
    
    let dbManager = DatabaseManager(databasePath: tempPath)
    try dbManager.ensureSchema()
    
    let service = HistoricalDataService(databaseManager: dbManager)
    
    let response = UsageResponse(
        fiveHour: WindowUsage(utilization: 45.5, resetsAt: "2026-02-03T15:00:00Z"),
        sevenDay: WindowUsage(utilization: 23.1, resetsAt: "2026-02-10T00:00:00Z"),
        sevenDaySonnet: nil,
        extraUsage: nil
    )
    
    try await service.persistPoll(response)
    
    let polls = try await service.getRecentPolls(hours: 1)
    XCTAssertEqual(polls.count, 1)
    XCTAssertEqual(polls[0].fiveHourUtil, 45.5)
    XCTAssertEqual(polls[0].sevenDayUtil, 23.1)
}
```

**Mock DatabaseManager for graceful degradation tests:**
```swift
final class MockDatabaseManager: DatabaseManagerProtocol {
    var isAvailable: Bool = false
    func getConnection() throws -> OpaquePointer { throw AppError.databaseOpenFailed(path: "mock") }
    // ... other required methods ...
}
```

### Project Structure Notes

**New files to create:**
```
cc-hdrm/Services/
├── HistoricalDataServiceProtocol.swift    # NEW
└── HistoricalDataService.swift            # NEW

cc-hdrm/Models/
└── UsagePoll.swift                        # NEW

cc-hdrmTests/Services/
└── HistoricalDataServiceTests.swift       # NEW

cc-hdrmTests/Models/
└── UsagePollTests.swift                   # NEW
```

**Modified files:**
```
cc-hdrm/Services/PollingEngine.swift       # Add historicalDataService parameter
cc-hdrm/Services/PollingEngineProtocol.swift  # May need protocol update
cc-hdrm/App/AppDelegate.swift              # Wire up service
```

### Previous Story Learnings (10.1)

From the Story 10.1 completion notes:

1. **SQLITE_TRANSIENT** - Required for `sqlite3_bind_text` with temporary Swift strings
2. **Thread safety** - Protected state with NSLock, use `@unchecked Sendable` 
3. **Test cleanup** - Close database connections before deleting test files
4. **Graceful degradation** - `isAvailable` flag pattern works well

### References

- [Source: cc-hdrm/Services/DatabaseManager.swift] - Database connection and schema
- [Source: cc-hdrm/Services/DatabaseManagerProtocol.swift] - Protocol pattern
- [Source: cc-hdrm/Services/PollingEngine.swift:125-157] - Integration point in fetchUsageData()
- [Source: cc-hdrm/Models/UsageResponse.swift] - API response structure
- [Source: _bmad-output/planning-artifacts/architecture.md#HistoricalDataService] - Service specification
- [Source: _bmad-output/planning-artifacts/architecture.md#Data Layer Architecture] - SQLite schema
- [Source: _bmad-output/planning-artifacts/epics.md#Story 10.2] - Acceptance criteria
- [Source: _bmad-output/implementation-artifacts/10-1-database-manager-schema-creation.md] - Previous story patterns

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

None - implementation proceeded without issues.

### Completion Notes List

- **Task 1**: Created `HistoricalDataServiceProtocol` with three async methods: `persistPoll`, `getRecentPolls`, `getDatabaseSize`. Created `UsagePoll` model struct with Sendable and Equatable conformance, storing timestamps as Int64 Unix milliseconds.

- **Task 2**: Implemented `HistoricalDataService` following patterns from `DatabaseManager`. Used `@unchecked Sendable` for thread safety. Implemented graceful degradation - operations silently skip when database unavailable. Used SQLITE_TRANSIENT pattern for string bindings. Proper NULL handling with `sqlite3_bind_null`.

- **Task 3**: Added optional `historicalDataService` parameter to PollingEngine init. Integrated persistence in `fetchUsageData()` using `Task { }` for fire-and-forget async execution (does not block UI). Errors caught and logged without disrupting poll cycle.

- **Task 4**: Wired up in AppDelegate: `DatabaseManager.shared.initialize()` called on app startup, HistoricalDataService created and passed to PollingEngine.

- **Task 5**: Implemented `getRecentPolls` with timestamp filter query (`WHERE timestamp >= ?`), results ordered ascending. Maps SQLite rows to UsagePoll structs with proper NULL checking for optional columns.

- **Task 6**: Comprehensive test coverage with 15+ tests covering: persistPoll data insertion, NULL handling, timestamp generation, time range filtering, ordering, graceful degradation (MockDatabaseManager), rapid call handling, protocol conformance. All 401 tests pass.

### Change Log

- 2026-02-03: Implemented Story 10.2 - Historical Data Service & Poll Persistence
- 2026-02-03: Code Review fixes applied:
  - Added PollingEngine integration tests for historicalDataService (M1)
  - Removed unused SQLITE_TRANSIENT constant from HistoricalDataService (M2)
  - Added closeConnection() to DatabaseManagerProtocol for test cleanup (M3)
  - Updated File List documentation (L1)
  - Documented timestamp uniqueness design decision (L2)

### File List

**New Files:**
- `cc-hdrm/Services/HistoricalDataServiceProtocol.swift`
- `cc-hdrm/Services/HistoricalDataService.swift`
- `cc-hdrm/Models/UsagePoll.swift`
- `cc-hdrmTests/Services/HistoricalDataServiceTests.swift`
- `cc-hdrmTests/Models/UsagePollTests.swift`

**Modified Files:**
- `cc-hdrm/Services/PollingEngine.swift` - Added historicalDataService parameter and persistPoll integration
- `cc-hdrm/App/AppDelegate.swift` - Added DatabaseManager.initialize() and HistoricalDataService wiring
- `cc-hdrm/Services/DatabaseManagerProtocol.swift` - Added closeConnection() to protocol (code review fix)
- `cc-hdrmTests/Services/PollingEngineTests.swift` - Added historicalDataService integration tests (code review fix)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` - Updated story status

**Note:** `cc-hdrm.xcodeproj/project.pbxproj` is auto-generated by XcodeGen from `project.yml` - source folders auto-include new files.
