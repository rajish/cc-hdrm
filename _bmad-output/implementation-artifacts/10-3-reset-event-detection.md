# Story 10.3: Reset Event Detection

Status: done

## Story

As a developer using Claude Code,
I want cc-hdrm to detect when a 5h window resets,
So that headroom analysis can be performed at each reset boundary.

## Acceptance Criteria

1. **Given** two consecutive polls where the second poll's `five_hour_resets_at` differs from the first
   **When** HistoricalDataService detects this shift
   **Then** a new row is inserted into reset_events with the pre-reset peak utilization and current 7d utilization
   **And** the tier from KeychainCredentials is recorded

2. **Given** `five_hour_resets_at` is null or missing in the API response
   **When** HistoricalDataService detects a large utilization drop (e.g., 80% -> 2%)
   **Then** it infers a reset event occurred (fallback detection)
   **And** logs the inferred reset via os.Logger (info level)

3. **Given** a reset event is detected
   **When** the event is recorded
   **Then** used_credits, constrained_credits, and waste_credits are calculated per the headroom analysis math (deferred to Epic 14 for full calculation)
   **And** if credit limits are unknown for the tier, the credit fields are set to null

## Tasks / Subtasks

- [x] Task 1: Create ResetEvent model (AC: #1, #3)
  - [x] 1.1 Create `cc-hdrm/Models/ResetEvent.swift` with struct matching reset_events schema
  - [x] 1.2 Include all fields: id, timestamp, fiveHourPeak, sevenDayUtil, tier, usedCredits, constrainedCredits, wasteCredits
  - [x] 1.3 Mark struct as Sendable and Equatable

- [x] Task 2: Extend HistoricalDataServiceProtocol (AC: #1, #2)
  - [x] 2.1 Add `detectAndRecordResetEvent(currentPoll: UsagePoll, previousPoll: UsagePoll?, tier: String?) async throws` method
  - [x] 2.2 Add `getResetEvents(fromTimestamp: Int64?, toTimestamp: Int64?) async throws -> [ResetEvent]` method
  - [x] 2.3 Add `getLastPoll() async throws -> UsagePoll?` helper method for retrieving the most recent poll

- [x] Task 3: Implement reset detection logic in HistoricalDataService (AC: #1, #2)
  - [x] 3.1 Add private property `lastPollResetsAt: Int64?` to track previous poll's resets_at
  - [x] 3.2 Implement primary detection: compare current poll's `five_hour_resets_at` with previous poll's value
  - [x] 3.3 Implement fallback detection: detect large utilization drop (threshold: >= 50% drop, e.g., 80% -> 30%)
  - [x] 3.4 Log detected resets at `.info` level with appropriate context

- [x] Task 4: Implement reset event recording in HistoricalDataService (AC: #1, #3)
  - [x] 4.1 Implement INSERT statement for reset_events table
  - [x] 4.2 Calculate peak utilization from recent polls before reset (within last 5 hours)
  - [x] 4.3 Set credit fields (used_credits, constrained_credits, waste_credits) to NULL for now (Epic 14 will implement)
  - [x] 4.4 Bind tier string using SQLITE_TRANSIENT pattern

- [x] Task 5: Implement getLastPoll() query (AC: #1)
  - [x] 5.1 Query usage_polls table with ORDER BY timestamp DESC LIMIT 1
  - [x] 5.2 Return nil if no polls exist

- [x] Task 6: Implement getResetEvents() query (AC: #3)
  - [x] 6.1 Query reset_events table with optional timestamp range filters
  - [x] 6.2 Order results by timestamp ascending
  - [x] 6.3 Map SQLite rows to ResetEvent structs

- [x] Task 7: Integrate reset detection into persistPoll flow (AC: #1, #2)
  - [x] 7.1 Modify `persistPoll()` to call reset detection after inserting poll
  - [x] 7.2 Fetch previous poll before inserting new poll for comparison
  - [x] 7.3 Accept optional tier parameter in persistPoll or add separate method

- [x] Task 8: Update PollingEngine integration (AC: #1)
  - [x] 8.1 Pass tier from credentials to historical data service for reset recording
  - [x] 8.2 Ensure tier is available in the persistence call path

- [x] Task 9: Write unit tests (AC: #1, #2, #3)
  - [x] 9.1 Create `cc-hdrmTests/Models/ResetEventTests.swift`
  - [x] 9.2 Create or extend `cc-hdrmTests/Services/HistoricalDataServiceTests.swift` with reset detection tests
  - [x] 9.3 Test primary detection: resets_at shift triggers event
  - [x] 9.4 Test fallback detection: large utilization drop triggers event
  - [x] 9.5 Test no false positives: small utilization drops don't trigger events
  - [x] 9.6 Test getResetEvents returns correct data
  - [x] 9.7 Test credit fields are NULL when tier unknown
  - [x] 9.8 Test graceful degradation when database unavailable

## Dev Notes

### Architecture Context

This story extends the Phase 3 data persistence layer to detect and record 5-hour window reset events. Reset detection is crucial for Epic 14's headroom waste analysis - each reset represents a boundary where unused capacity either becomes "waste" or was "7d-constrained".

**Data Flow:**
```
PollingEngine -> APIClient.fetchUsage() -> UsageResponse
                                              |
                                              v
                            HistoricalDataService.persistPoll()
                                              |
                              +---------------+---------------+
                              |                               |
                              v                               v
                    INSERT into usage_polls      detectAndRecordResetEvent()
                                                              |
                                              +---------------+---------------+
                                              |                               |
                                              v                               v
                                    Primary Detection           Fallback Detection
                                   (resets_at shift)          (utilization drop)
                                              |                               |
                                              +---------------+---------------+
                                                              |
                                                              v
                                                  INSERT into reset_events
```

### ResetEvent Model

```swift
/// Represents a 5-hour window reset event for headroom analysis.
struct ResetEvent: Sendable, Equatable {
    /// Database row ID
    let id: Int64
    /// Unix milliseconds when the reset was detected
    let timestamp: Int64
    /// Peak 5h utilization before reset (percentage 0-100)
    let fiveHourPeak: Double?
    /// 7d utilization at reset time (percentage 0-100)
    let sevenDayUtil: Double?
    /// Rate limit tier string from credentials (e.g., "default_claude_max_5x")
    let tier: String?
    /// Credits actually used (NULL until Epic 14)
    let usedCredits: Double?
    /// Credits blocked by 7d limit - NOT waste (NULL until Epic 14)
    let constrainedCredits: Double?
    /// True wasted credits (NULL until Epic 14)
    let wasteCredits: Double?
}
```

### Reset Detection Logic

**Primary Detection (AC #1):**
Compare consecutive polls' `five_hour_resets_at` values. If they differ (and both are non-null), a reset occurred.

```swift
func detectReset(current: UsagePoll, previous: UsagePoll) -> Bool {
    guard let currentResetsAt = current.fiveHourResetsAt,
          let previousResetsAt = previous.fiveHourResetsAt else {
        // Fall through to fallback detection
        return false
    }
    return currentResetsAt != previousResetsAt
}
```

**Fallback Detection (AC #2):**
When `resets_at` is missing, infer reset from large utilization drop. The 5h window is monotonically increasing within a window, so a significant drop indicates a reset.

```swift
// Threshold: 50% absolute drop (e.g., 80% -> 30% is a 50-point drop)
private let utilizationDropThreshold: Double = 50.0

func detectResetFallback(current: UsagePoll, previous: UsagePoll) -> Bool {
    guard let currentUtil = current.fiveHourUtil,
          let previousUtil = previous.fiveHourUtil else {
        return false
    }
    let drop = previousUtil - currentUtil
    return drop >= utilizationDropThreshold
}
```

### Peak Utilization Calculation

The reset event should record the **peak** utilization reached before the reset, not just the last poll's value. Query recent polls (last 5 hours) and find the maximum `five_hour_util`:

```swift
func getRecentPeakUtilization(beforeTimestamp: Int64) async throws -> Double? {
    // Query polls from last 5 hours, find max five_hour_util
    let fiveHoursMs: Int64 = 5 * 60 * 60 * 1000
    let cutoff = beforeTimestamp - fiveHoursMs
    // SELECT MAX(five_hour_util) FROM usage_polls WHERE timestamp >= ? AND timestamp < ?
}
```

### SQL Statements

**Insert Reset Event:**
```sql
INSERT INTO reset_events (
    timestamp,
    five_hour_peak,
    seven_day_util,
    tier,
    used_credits,
    constrained_credits,
    waste_credits
) VALUES (?, ?, ?, ?, ?, ?, ?)
```

**Get Last Poll:**
```sql
SELECT id, timestamp, five_hour_util, five_hour_resets_at, seven_day_util, seven_day_resets_at
FROM usage_polls
ORDER BY timestamp DESC
LIMIT 1
```

**Get Reset Events:**
```sql
SELECT id, timestamp, five_hour_peak, seven_day_util, tier, used_credits, constrained_credits, waste_credits
FROM reset_events
WHERE timestamp >= COALESCE(?, 0)
  AND timestamp <= COALESCE(?, 9223372036854775807)
ORDER BY timestamp ASC
```

**Get Peak Utilization:**
```sql
SELECT MAX(five_hour_util) FROM usage_polls
WHERE timestamp >= ? AND timestamp < ?
```

### HistoricalDataServiceProtocol Extensions

```swift
protocol HistoricalDataServiceProtocol: Sendable {
    // Existing methods...
    func persistPoll(_ response: UsageResponse) async throws
    func getRecentPolls(hours: Int) async throws -> [UsagePoll]
    func getDatabaseSize() async throws -> Int64
    
    // NEW: Story 10.3 additions
    
    /// Persists a poll snapshot and detects/records any reset events.
    /// - Parameters:
    ///   - response: The usage response from the API
    ///   - tier: The rate limit tier string from credentials (for reset event recording)
    func persistPoll(_ response: UsageResponse, tier: String?) async throws
    
    /// Retrieves reset events within an optional time range.
    /// - Parameters:
    ///   - fromTimestamp: Optional start timestamp (Unix ms), inclusive
    ///   - toTimestamp: Optional end timestamp (Unix ms), inclusive
    /// - Returns: Array of reset events ordered by timestamp ascending
    func getResetEvents(fromTimestamp: Int64?, toTimestamp: Int64?) async throws -> [ResetEvent]
    
    /// Retrieves the most recent poll from the database.
    /// - Returns: The last poll, or nil if no polls exist
    func getLastPoll() async throws -> UsagePoll?
}
```

**Note:** Add a new `persistPoll(_:tier:)` overload to accept tier. The existing `persistPoll(_:)` can call the new method with `tier: nil` for backward compatibility.

### PollingEngine Integration

Modify the persistence call in `fetchUsageData()` to include tier:

```swift
// In PollingEngine.fetchUsageData():
Task {
    do {
        try await historicalDataService?.persistPoll(response, tier: credentials.rateLimitTier)
    } catch {
        Self.logger.error("Failed to persist poll data: \(error.localizedDescription)")
    }
}
```

### Thread Safety Considerations

- HistoricalDataService already uses `@unchecked Sendable` pattern
- Reset detection state (tracking previous poll's resets_at) should be stored in database, not in-memory, to survive app restarts
- Alternative: Query last poll from database on each call rather than caching in memory

### Graceful Degradation

Follow existing pattern - if database unavailable, reset detection is skipped:

```swift
func detectAndRecordResetEvent(...) async throws {
    guard databaseManager.isAvailable else {
        Self.logger.debug("Database unavailable - skipping reset detection")
        return
    }
    // ... detection logic ...
}
```

### Logging Guidelines

- **Reset detected (primary):** `.info` level - "Reset detected: resets_at shifted from X to Y"
- **Reset detected (fallback):** `.info` level - "Reset inferred: utilization dropped from X% to Y%"
- **Reset recorded:** `.info` level - "Reset event recorded: peak=X%, 7d=Y%, tier=Z"
- **No reset:** `.debug` level - implicit (no log needed)
- **Database errors:** `.error` level - follow existing patterns

### Testing Strategy

**Unit tests with temp database:**

```swift
func testResetDetectedWhenResetsAtChanges() async throws {
    let service = createTestService()
    
    // Insert first poll with resets_at = T1
    let poll1 = createTestPoll(fiveHourResetsAt: 1000000)
    try await service.persistPoll(poll1, tier: "test_tier")
    
    // Insert second poll with resets_at = T2 (different)
    let poll2 = createTestPoll(fiveHourResetsAt: 2000000)
    try await service.persistPoll(poll2, tier: "test_tier")
    
    // Verify reset event was recorded
    let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
    XCTAssertEqual(events.count, 1)
}

func testFallbackDetectionOnLargeUtilizationDrop() async throws {
    let service = createTestService()
    
    // Insert poll at 80% utilization (no resets_at)
    let poll1 = createTestPoll(fiveHourUtil: 80.0, fiveHourResetsAt: nil)
    try await service.persistPoll(poll1, tier: nil)
    
    // Insert poll at 5% utilization (large drop, no resets_at)
    let poll2 = createTestPoll(fiveHourUtil: 5.0, fiveHourResetsAt: nil)
    try await service.persistPoll(poll2, tier: nil)
    
    // Verify reset event was inferred
    let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
    XCTAssertEqual(events.count, 1)
}

func testNoFalsePositiveOnSmallUtilizationChange() async throws {
    let service = createTestService()
    
    // Insert polls with small changes (shouldn't trigger reset)
    let poll1 = createTestPoll(fiveHourUtil: 50.0, fiveHourResetsAt: 1000000)
    try await service.persistPoll(poll1, tier: nil)
    
    let poll2 = createTestPoll(fiveHourUtil: 52.0, fiveHourResetsAt: 1000000) // same resets_at
    try await service.persistPoll(poll2, tier: nil)
    
    let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
    XCTAssertEqual(events.count, 0)
}

func testCreditFieldsNullWhenTierUnknown() async throws {
    let service = createTestService()
    
    // Trigger reset with nil tier
    let poll1 = createTestPoll(fiveHourResetsAt: 1000000)
    try await service.persistPoll(poll1, tier: nil)
    
    let poll2 = createTestPoll(fiveHourResetsAt: 2000000)
    try await service.persistPoll(poll2, tier: nil)
    
    let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
    XCTAssertEqual(events.count, 1)
    XCTAssertNil(events[0].tier)
    XCTAssertNil(events[0].usedCredits)
    XCTAssertNil(events[0].constrainedCredits)
    XCTAssertNil(events[0].wasteCredits)
}
```

### Project Structure Notes

**New files to create:**
```
cc-hdrm/Models/
└── ResetEvent.swift                        # NEW

cc-hdrmTests/Models/
└── ResetEventTests.swift                   # NEW
```

**Modified files:**
```
cc-hdrm/Services/HistoricalDataServiceProtocol.swift  # Add new methods
cc-hdrm/Services/HistoricalDataService.swift          # Implement reset detection
cc-hdrm/Services/PollingEngine.swift                  # Pass tier to persistPoll
cc-hdrmTests/Services/HistoricalDataServiceTests.swift # Add reset detection tests
```

### Previous Story Learnings (10.1 & 10.2)

From Stories 10.1 and 10.2 completion notes:

1. **SQLITE_TRANSIENT** - Required for `sqlite3_bind_text` with temporary Swift strings (use for tier binding)
2. **Thread safety** - Protected state with NSLock, use `@unchecked Sendable` 
3. **Test cleanup** - Close database connections before deleting test files
4. **Graceful degradation** - `isAvailable` flag pattern works well
5. **Fire-and-forget async** - Use `Task { }` in PollingEngine for non-blocking persistence
6. **NULL handling** - Use `sqlite3_column_type() == SQLITE_NULL` check before reading values

### References

- [Source: cc-hdrm/Services/DatabaseManager.swift:268-287] - reset_events table schema
- [Source: cc-hdrm/Services/HistoricalDataService.swift] - Existing persistence implementation
- [Source: cc-hdrm/Services/HistoricalDataServiceProtocol.swift] - Current protocol definition
- [Source: cc-hdrm/Services/PollingEngine.swift:128-171] - Integration point in fetchUsageData()
- [Source: cc-hdrm/Models/UsagePoll.swift] - Poll model structure
- [Source: _bmad-output/planning-artifacts/architecture.md:876-889] - HistoricalDataService specification
- [Source: _bmad-output/planning-artifacts/architecture.md:829-845] - reset_events schema
- [Source: _bmad-output/planning-artifacts/epics.md:1065-1087] - Story 10.3 acceptance criteria
- [Source: _bmad-output/implementation-artifacts/10-2-historical-data-service-poll-persistence.md] - Previous story patterns

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

N/A - No debug issues encountered

### Completion Notes List

- Created ResetEvent model with all schema fields (id, timestamp, fiveHourPeak, sevenDayUtil, tier, credit fields)
- Extended HistoricalDataServiceProtocol with new methods: `persistPoll(_:tier:)`, `getLastPoll()`, `getResetEvents(fromTimestamp:toTimestamp:)`
- Implemented primary reset detection: detects when `five_hour_resets_at` shifts between consecutive polls
- Implemented fallback reset detection: detects >= 50% utilization drop when resets_at is nil
- Reset events record peak 5h utilization from last 5 hours, current 7d util, and tier
- Credit fields (used_credits, constrained_credits, waste_credits) set to NULL - deferred to Epic 14
- PollingEngine passes tier from credentials to persistPoll for reset event recording
- Added comprehensive tests: 14 new tests for reset detection, 4 tests for ResetEvent model
- All 419 tests pass with no regressions

### Code Review Fixes (2026-02-03)

- **H1 Fixed**: Changed sevenDayUtil to capture pre-reset value from previousPoll instead of post-reset from currentPoll
- **L1 Fixed**: Added full doc comment to `getRecentPeakUtilization` private method
- **L2 Fixed**: Enhanced `PEMockHistoricalDataService` with configurable `mockLastPoll` and `mockResetEvents`
- **Test Added**: New test `resetEventCapturesPreReset7dUtil` verifies pre-reset 7d utilization is captured
- All 420 tests pass after review fixes

### File List

**New files:**
- cc-hdrm/Models/ResetEvent.swift
- cc-hdrmTests/Models/ResetEventTests.swift

**Modified files:**
- cc-hdrm/Services/HistoricalDataServiceProtocol.swift
- cc-hdrm/Services/HistoricalDataService.swift
- cc-hdrm/Services/PollingEngine.swift
- cc-hdrmTests/Services/HistoricalDataServiceTests.swift
- cc-hdrmTests/Services/PollingEngineTests.swift (mock updated)

## Change Log

- 2026-02-03: Story 10.3 implemented - Reset event detection with primary (resets_at shift) and fallback (utilization drop) detection methods. Tests added and passing.
- 2026-02-03: Code review fixes applied - sevenDayUtil now captures pre-reset value, doc comments added, test mock improved, new test added. 420 tests pass.
