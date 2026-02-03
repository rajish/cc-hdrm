# Story 10.5: Data Query APIs

Status: done

## Story

As a developer using Claude Code,
I want to query historical data at the appropriate resolution for different time ranges,
So that analytics views can display relevant data efficiently.

## Acceptance Criteria

1. **Given** a request for the last 24 hours of data
   **When** HistoricalDataService.getRecentPolls(hours: 24) is called
   **Then** it returns raw poll data from usage_polls ordered by timestamp
   **And** the result includes all fields needed for sparkline and chart rendering

2. **Given** a request for 7-day data
   **When** HistoricalDataService.getRolledUpData(range: .week) is called
   **Then** it returns 5-minute rollups for the 1-7 day range combined with raw data for <24h
   **And** data is seamlessly stitched (no visible boundary between raw and rolled data)

3. **Given** a request for 30-day or all-time data
   **When** getRolledUpData() is called with the appropriate range
   **Then** it returns the correctly tiered data (daily for 30+ days, hourly for 7-30 days, etc.)

4. **Given** a request for reset events in a time range
   **When** HistoricalDataService.getResetEvents(range:) is called
   **Then** it returns all reset_events rows within the specified range
   **And** results are ordered by timestamp ascending

## Tasks / Subtasks

- [x] Task 1: Add TimeRange-based getResetEvents method (AC: 4)
  - [x] 1.1 Add `getResetEvents(range: TimeRange) async throws -> [ResetEvent]` to HistoricalDataServiceProtocol
  - [x] 1.2 Implement in HistoricalDataService, converting TimeRange to timestamp bounds
  - [x] 1.3 Delegate to existing `getResetEvents(fromTimestamp:toTimestamp:)` implementation

- [x] Task 2: Verify existing getRecentPolls API (AC: 1)
  - [x] 2.1 Confirm getRecentPolls(hours:) returns all required fields for sparkline rendering
  - [x] 2.2 Verify results are ordered by timestamp ascending
  - [x] 2.3 Add documentation comments clarifying sparkline/chart usage

- [x] Task 3: Verify getRolledUpData seamless stitching (AC: 2, 3)
  - [x] 3.1 Review .week implementation for raw <24h + 5min rollups stitching
  - [x] 3.2 Review .month implementation for raw + 5min + hourly stitching
  - [x] 3.3 Review .all implementation for raw + 5min + hourly + daily stitching
  - [x] 3.4 Verify all results sorted by period_start ascending

- [x] Task 4: Write unit tests (AC: 1, 2, 3, 4)
  - [x] 4.1 Add test for `getResetEvents(range: .day)` returns events in last 24h
  - [x] 4.2 Add test for `getResetEvents(range: .week)` returns events in last 7 days
  - [x] 4.3 Add test for `getResetEvents(range: .month)` returns events in last 30 days
  - [x] 4.4 Add test for `getResetEvents(range: .all)` returns all events
  - [x] 4.5 Add test verifying reset events ordered by timestamp ascending
  - [x] 4.6 Update PEMockHistoricalDataService to include new method

- [x] Task 5: Documentation and cleanup (AC: 1, 2, 3, 4)
  - [x] 5.1 Add comprehensive doc comments to all Data Query API methods
  - [x] 5.2 Document TimeRange enum usage patterns
  - [x] 5.3 Verify protocol and implementation documentation alignment

## Dev Notes

### Architecture Context

This story finalizes the Data Query API layer for Phase 3 historical analytics. Most functionality was implemented in Stories 10.1-10.4:

| Story | Implemented APIs |
| ----- | ---------------- |
| 10.1  | DatabaseManager, schema creation |
| 10.2  | persistPoll(), getRecentPolls(), getLastPoll(), getDatabaseSize() |
| 10.3  | getResetEvents(fromTimestamp:toTimestamp:), reset detection logic |
| 10.4  | ensureRollupsUpToDate(), getRolledUpData(range:), pruneOldData() |
| 10.5  | getResetEvents(range:) convenience wrapper, API finalization |

The primary new work is adding a `TimeRange`-based convenience method for reset events to match the API pattern established by `getRolledUpData(range:)`.

### TimeRange Enum (Already Defined)

```swift
// Source: cc-hdrm/Models/TimeRange.swift
enum TimeRange: CaseIterable {
    case day    // Last 24 hours - raw polls only
    case week   // Last 7 days - raw + 5min rollups
    case month  // Last 30 days - raw + 5min + hourly
    case all    // Full retention - includes daily rollups
    
    var startTimestamp: Int64 {
        let now = Date().timeIntervalSince1970 * 1000
        switch self {
        case .day:   return Int64(now) - (24 * 60 * 60 * 1000)
        case .week:  return Int64(now) - (7 * 24 * 60 * 60 * 1000)
        case .month: return Int64(now) - (30 * 24 * 60 * 60 * 1000)
        case .all:   return 0  // All available data
        }
    }
}
```

### New Protocol Method

Add to `HistoricalDataServiceProtocol.swift`:

```swift
/// Retrieves reset events within a time range.
/// Convenience wrapper using TimeRange enum for consistency with getRolledUpData().
/// - Parameter range: Time range to query (.day, .week, .month, .all)
/// - Returns: Array of reset events ordered by timestamp ascending
func getResetEvents(range: TimeRange) async throws -> [ResetEvent]
```

### Implementation

Add to `HistoricalDataService.swift`:

```swift
func getResetEvents(range: TimeRange) async throws -> [ResetEvent] {
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    let fromTimestamp: Int64?
    
    switch range {
    case .day:
        fromTimestamp = nowMs - (24 * 60 * 60 * 1000)
    case .week:
        fromTimestamp = nowMs - (7 * 24 * 60 * 60 * 1000)
    case .month:
        fromTimestamp = nowMs - (30 * 24 * 60 * 60 * 1000)
    case .all:
        fromTimestamp = nil  // No lower bound
    }
    
    return try await getResetEvents(fromTimestamp: fromTimestamp, toTimestamp: nowMs)
}
```

### Data Stitching Verification

The `getRolledUpData(range:)` method already implements seamless stitching:

```text
.day:   Raw polls (last 24h)
.week:  Raw polls (last 24h) + 5min rollups (1-7d)
.month: Raw polls (last 24h) + 5min rollups (1-7d) + hourly rollups (7-30d)
.all:   Raw polls (last 24h) + 5min rollups (1-7d) + hourly rollups (7-30d) + daily rollups (30d+)
```

All results are sorted by `period_start` ascending (line 1315 in HistoricalDataService.swift).

### Existing getRecentPolls Fields

The `getRecentPolls(hours:)` method returns `[UsagePoll]` with all fields needed for sparkline rendering:

```swift
struct UsagePoll: Sendable, Equatable {
    let id: Int64
    let timestamp: Int64           // Unix ms - X-axis for charts
    let fiveHourUtil: Double?      // Y-axis primary series
    let fiveHourResetsAt: Int64?   // Reset boundary markers
    let sevenDayUtil: Double?      // Y-axis secondary series
    let sevenDayResetsAt: Int64?   // Reset boundary markers
}
```

### Thread Safety

Follows established patterns from Stories 10.1-10.4:
- HistoricalDataService is `@unchecked Sendable` with protected state
- All database operations use the same connection from DatabaseManager
- Query results are immutable value types (structs)

### Testing Strategy

Unit tests with in-memory SQLite database:

```swift
func testGetResetEventsWithDayRange() async throws {
    let service = createTestService()
    
    // Insert reset events at various times
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    let twelveHoursAgo = nowMs - (12 * 60 * 60 * 1000)
    let thirtySixHoursAgo = nowMs - (36 * 60 * 60 * 1000)
    
    try await insertTestResetEvent(timestamp: twelveHoursAgo)  // Within range
    try await insertTestResetEvent(timestamp: thirtySixHoursAgo)  // Outside range
    
    let events = try await service.getResetEvents(range: .day)
    
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0].timestamp, twelveHoursAgo)
}

func testGetResetEventsOrderedByTimestamp() async throws {
    let service = createTestService()
    
    // Insert in non-chronological order
    try await insertTestResetEvent(timestamp: 3000)
    try await insertTestResetEvent(timestamp: 1000)
    try await insertTestResetEvent(timestamp: 2000)
    
    let events = try await service.getResetEvents(range: .all)
    
    XCTAssertEqual(events.count, 3)
    XCTAssertEqual(events[0].timestamp, 1000)
    XCTAssertEqual(events[1].timestamp, 2000)
    XCTAssertEqual(events[2].timestamp, 3000)
}
```

### Project Structure Notes

**Modified files:**
```text
cc-hdrm/Services/HistoricalDataServiceProtocol.swift  # Add getResetEvents(range:)
cc-hdrm/Services/HistoricalDataService.swift          # Implement getResetEvents(range:)
cc-hdrmTests/Services/HistoricalDataServiceTests.swift # Add TimeRange reset event tests
cc-hdrmTests/Services/PollingEngineTests.swift        # Update mock to conform
```

No new files required - this is an API refinement story.

### Previous Story Learnings (10.1-10.4)

From Stories 10.1-10.4 completion notes:

1. **SQLITE_TRANSIENT** - Required for `sqlite3_bind_text` with temporary Swift strings
2. **Thread safety** - Protected state with NSLock, use `@unchecked Sendable`
3. **Test cleanup** - Close database connections before deleting test files
4. **Graceful degradation** - `isAvailable` flag pattern works well
5. **Fire-and-forget async** - Use `Task { }` in PollingEngine for non-blocking persistence
6. **NULL handling** - Use `sqlite3_column_type() == SQLITE_NULL` check before reading values
7. **Pre-reset values** - When recording reset events, capture pre-reset state from previous poll
8. **Data stitching** - Convert raw polls to pseudo-rollups for consistent query results

### References

- [Source: cc-hdrm/Services/HistoricalDataServiceProtocol.swift] - Protocol with existing methods
- [Source: cc-hdrm/Services/HistoricalDataService.swift:272-346] - Existing getResetEvents implementation
- [Source: cc-hdrm/Services/HistoricalDataService.swift:637-645] - getRolledUpData entry point
- [Source: cc-hdrm/Services/HistoricalDataService.swift:1242-1316] - Data stitching implementation
- [Source: cc-hdrm/Models/TimeRange.swift] - TimeRange enum definition
- [Source: cc-hdrm/Models/UsagePoll.swift] - Poll model with sparkline fields
- [Source: cc-hdrm/Models/ResetEvent.swift] - Reset event model
- [Source: _bmad-output/planning-artifacts/architecture.md:856-869] - Data tiering strategy
- [Source: _bmad-output/planning-artifacts/epics.md:1120-1145] - Story 10.5 acceptance criteria
- [Source: _bmad-output/implementation-artifacts/10-4-tiered-rollup-engine.md] - Previous story patterns

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

N/A - No debugging required. Clean implementation.

### Completion Notes List

- **Task 1**: Added `getResetEvents(range: TimeRange)` to protocol and implementation. Delegates to existing `getResetEvents(fromTimestamp:toTimestamp:)` for consistency. Uses switch statement to convert TimeRange cases to millisecond bounds.

- **Task 2**: Verified `getRecentPolls(hours:)` returns `[UsagePoll]` with all sparkline fields (timestamp, fiveHourUtil, sevenDayUtil, resetsAt values), ordered by timestamp ASC. Enhanced doc comments.

- **Task 3**: Verified `getRolledUpData(range:)` implementation at HistoricalDataService.swift:1260-1334:
  - `.day`: Raw polls only (last 24h)
  - `.week`: Raw + 5min rollups (1-7d)
  - `.month`: Raw + 5min + hourly rollups
  - `.all`: Raw + 5min + hourly + daily rollups
  - All results sorted by period_start ascending (line 1333)

- **Task 4**: Added 6 new tests for `getResetEvents(range:)` covering all TimeRange cases plus ordering verification. Updated `PEMockHistoricalDataService` to implement new protocol method. All 451 tests pass.

- **Task 5**: Enhanced documentation for `getRecentPolls(hours:)` with sparkline field usage details. Enhanced `TimeRange` enum docs with tier resolution mapping and usage examples.

### Change Log

- 2026-02-03: Story 10.5 implementation complete. Added getResetEvents(range:) convenience API, verified existing Data Query APIs, added comprehensive tests.
- 2026-02-03: Code review complete. Fixed 3 documentation issues: TimeRange.all doc clarified retention vs query scope, protocol doc improved API consistency wording, story line number reference corrected.

### File List

- cc-hdrm/Services/HistoricalDataServiceProtocol.swift (modified: added getResetEvents(range:), enhanced getRecentPolls docs)
- cc-hdrm/Services/HistoricalDataService.swift (modified: implemented getResetEvents(range:))
- cc-hdrm/Models/TimeRange.swift (modified: enhanced documentation)
- cc-hdrmTests/Services/HistoricalDataServiceTests.swift (modified: added 6 tests for getResetEvents(range:))
- cc-hdrmTests/Services/PollingEngineTests.swift (modified: updated PEMockHistoricalDataService)
