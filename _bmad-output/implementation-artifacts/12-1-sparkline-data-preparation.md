# Story 12.1: Sparkline Data Preparation

Status: done

## Story

As a developer using Claude Code,
I want the popover to have sparkline data ready instantly,
So that opening the popover never feels slow.

## Acceptance Criteria

1. **Given** a successful poll cycle completes
   **When** PollingEngine updates AppState
   **Then** it also updates AppState.sparklineData by calling HistoricalDataService.getRecentPolls(hours: 24)
   **And** sparklineData is refreshed on every poll cycle (kept current)

2. **Given** the app just launched and historical data exists
   **When** the first poll cycle completes
   **Then** sparklineData is populated from SQLite (bootstrap from history)

3. **Given** no historical data exists (fresh Phase 3 install)
   **When** the first poll cycle completes
   **Then** sparklineData is an empty array
   **And** hasSparklineData returns false until at least 2 data points are collected (~60 seconds at default poll interval)

4. **Given** the connection status changes to disconnected/tokenExpired/noCredentials
   **When** the error state is entered
   **Then** sparklineData is NOT cleared (preserved for display continuity)
   **And** the UI layer (Story 12.2) handles stale data presentation

## Tasks / Subtasks

- [x] Task 1: Add sparklineData property to AppState (AC: 1, 2, 3, 4)
  - [x] 1.1 Add `private(set) var sparklineData: [UsagePoll] = []` property to AppState
  - [x] 1.2 Add `func updateSparklineData(_ data: [UsagePoll])` method to AppState
  - [x] 1.3 Ensure property is observable (triggers view updates when changed)

- [x] Task 2: Update PollingEngine to refresh sparklineData (AC: 1, 2)
  - [x] 2.1 After successful usage fetch in `fetchUsageData()`, call `historicalDataService?.getRecentPolls(hours: 24)`
  - [x] 2.2 Update AppState.sparklineData with the returned data
  - [x] 2.3 Handle errors gracefully - log and continue without crashing
  - [x] 2.4 Execute sparkline data refresh asynchronously (does not block main poll cycle completion)
  - [x] 2.5 Use cancellation token pattern to prevent overlapping refresh operations (see Dev Notes)

- [x] Task 3: Add computed property for sparkline availability (AC: 3)
  - [x] 3.1 Add `var hasSparklineData: Bool` computed property to AppState
  - [x] 3.2 Returns true if sparklineData contains at least 2 data points (minimum for line rendering)
  - [x] 3.3 Add `static let sparklineMinDataPoints = 2` constant to AppState for consistency

- [x] Task 4: Write unit tests for AppState sparkline properties
  - [x] 4.1 Create tests in `cc-hdrmTests/State/AppStateTests.swift` for sparklineData updates
  - [x] 4.2 Test that sparklineData starts empty
  - [x] 4.3 Test that updateSparklineData() correctly sets the data
  - [x] 4.4 Test hasSparklineData computed property returns false when empty
  - [x] 4.5 Test hasSparklineData returns false with 1 data point
  - [x] 4.6 Test hasSparklineData returns true with 2+ data points
  - [x] 4.7 Test that data is ordered by timestamp ascending after update

- [x] Task 5: Write integration tests for PollingEngine sparkline refresh
  - [x] 5.1 Add tests in `cc-hdrmTests/Services/PollingEngineTests.swift`
  - [x] 5.2 Test that successful poll cycle updates AppState.sparklineData
  - [x] 5.3 Test that sparkline refresh failure does not prevent poll cycle completion
  - [x] 5.4 Test that data ordering (timestamp ascending) is preserved
  - [x] 5.5 Use mock HistoricalDataService returning test UsagePoll data
  - [x] 5.6 Use XCTestExpectation for async completion (NOT Task.sleep)

- [x] Task 6: Build verification and regression check
  - [x] 6.1 Run `xcodegen generate` to update project file
  - [x] 6.2 Run `xcodebuild -scheme cc-hdrm -destination 'platform=macOS' build`
  - [x] 6.3 Run full test suite (expect 548+ tests to pass)
  - [x] 6.4 Manually verify app launches and PollingEngine logs sparkline data updates

## Dev Notes

### CRITICAL: Sparkline Data Refresh is Async Fire-and-Forget

The sparkline data refresh MUST NOT block the main poll cycle. Use cancellation to prevent race conditions from overlapping refreshes:

```swift
// Add to PollingEngine class properties
private var sparklineRefreshTask: Task<Void, Never>?

// In fetchUsageData(), after slope calculation block:

// Cancel any in-flight sparkline refresh to prevent races
sparklineRefreshTask?.cancel()

// Refresh sparkline data for popover (async, non-blocking)
sparklineRefreshTask = Task { [weak self] in
    guard let self, !Task.isCancelled else { return }
    do {
        if let data = try await historicalDataService?.getRecentPolls(hours: 24) {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                appState.updateSparklineData(data)
            }
            Self.logger.debug("Sparkline data refreshed: \(data.count) points")
        }
    } catch {
        guard !Task.isCancelled else { return }
        Self.logger.error("Failed to refresh sparkline data: \(error.localizedDescription)")
    }
}
```

### CRITICAL: MainActor for AppState Updates

AppState is `@MainActor`, so all updates must occur on the main thread. The async Task must use `await MainActor.run {}` to update sparklineData. The cancellation check BEFORE the MainActor.run prevents updating state after a newer refresh has started.

### CRITICAL: Do NOT Clear Data on Disconnect

When connection status becomes disconnected/tokenExpired/noCredentials, sparklineData is **preserved**. Rationale:
- Historical data remains valid even if current polling fails
- UI can show stale sparkline with a visual indicator (handled by Story 12.2)
- Clearing would cause jarring UX on temporary network blips

### Memory Impact Analysis

At default 30-second poll interval over 24 hours:
- Data points: 24 * 60 * 2 = **2,880 UsagePoll objects**
- UsagePoll size: ~56 bytes (Int64 id, Int64 timestamp, 4 optional Doubles/Int64s)
- Total: ~161 KB

At minimum 10-second poll interval (configurable):
- Data points: 24 * 60 * 6 = **8,640 UsagePoll objects**
- Total: ~484 KB

Both are well within acceptable memory budget (app target < 50 MB).

### AppState Additions

```swift
// cc-hdrm/State/AppState.swift - Add to existing class

/// Minimum data points required for sparkline rendering.
static let sparklineMinDataPoints = 2

/// Poll data for the 24h sparkline visualization. Updated on each successful poll cycle.
/// Data is ordered by timestamp ascending. Preserved across connection state changes.
private(set) var sparklineData: [UsagePoll] = []

/// Whether enough sparkline data exists for rendering (minimum 2 data points for a line).
var hasSparklineData: Bool {
    sparklineData.count >= Self.sparklineMinDataPoints
}

/// Updates the sparkline data from recent polls.
/// - Parameter data: Poll data ordered by timestamp ascending from HistoricalDataService
func updateSparklineData(_ data: [UsagePoll]) {
    self.sparklineData = data
}
```

### Data Validation Note

`getRecentPolls(hours:)` may return UsagePoll objects where `fiveHourUtil` is nil (the field is optional per the model). This is **acceptable** for sparkline data:
- The Sparkline component (Story 12.2) will handle nil values during rendering
- Filtering here would create data gaps that misrepresent the actual poll history
- Nil values indicate API returned partial data, which is valid historical information

### Project Structure Notes

**Files to modify:**
```text
cc-hdrm/State/AppState.swift          # Add sparklineData, hasSparklineData, updateSparklineData(), sparklineMinDataPoints
cc-hdrm/Services/PollingEngine.swift  # Add sparklineRefreshTask property, add refresh after slope calculation
```

**Test files to modify:**
```text
cc-hdrmTests/State/AppStateTests.swift           # Add sparklineData tests
cc-hdrmTests/Services/PollingEngineTests.swift   # Add sparkline refresh tests
```

**No new files required** - this story adds to existing files only.

### Scope Clarification: isAnalyticsWindowOpen

The architecture.md mentions `isAnalyticsWindowOpen: Bool` as a Phase 3 AppState addition. This property is **NOT part of Story 12.1** — it will be added in Story 13.1 (Analytics Window Shell) when the analytics window is implemented. This story focuses solely on data preparation.

### UsagePoll Model Reference (from cc-hdrm/Models/UsagePoll.swift)

```swift
struct UsagePoll: Sendable, Equatable, Identifiable {
    let id: Int64
    let timestamp: Int64        // Unix ms - X-axis for sparkline
    let fiveHourUtil: Double?   // Y-axis value (percentage 0-100), may be nil
    let fiveHourResetsAt: Int64?
    let sevenDayUtil: Double?
    let sevenDayResetsAt: Int64?
}
```

Sparkline will use `timestamp` and `fiveHourUtil` for rendering. Only 5h utilization is shown (7d moves too slowly for 24h view to be meaningful per UX spec).

### Edge Cases to Handle

| # | Condition | Expected Behavior |
|---|-----------|-------------------|
| 1 | App just launched, no history | sparklineData is empty, hasSparklineData returns false |
| 2 | First poll completes | sparklineData populated from DB (may have prior data) |
| 3 | DB query fails | Log error, sparklineData unchanged, poll cycle continues |
| 4 | HistoricalDataService is nil | sparklineData stays empty (acceptable for tests) |
| 5 | < 24h of history exists | sparklineData contains whatever exists (partial data OK) |
| 6 | Connection drops mid-session | sparklineData preserved (NOT cleared) |
| 7 | Rapid poll cycles overlap | Previous refresh cancelled, latest wins |
| 8 | Some UsagePoll.fiveHourUtil is nil | Data kept as-is, UI layer handles nil |

### Previous Story Intelligence

**From Story 10.2:**
- `HistoricalDataService.persistPoll()` pattern for async fire-and-forget DB operations
- Error logging pattern: `Self.logger.error("Failed to persist poll data: \(error.localizedDescription)")`

**From Story 10.5:**
- `getRecentPolls(hours:)` API returns `[UsagePoll]` ordered by timestamp ascending
- Result includes all fields needed for sparkline rendering

**From Story 11.1-11.4:**
- Slope calculation pattern in PollingEngine (synchronous update to AppState)
- The sparkline refresh follows the same location but uses async pattern with cancellation

### Testing Strategy

```swift
// cc-hdrmTests/State/AppStateTests.swift

@Suite("AppState Sparkline Tests")
@MainActor
struct AppStateSparklineTests {
    
    @Test("sparklineData starts empty")
    func sparklineDataInitiallyEmpty() {
        let appState = AppState()
        #expect(appState.sparklineData.isEmpty)
    }
    
    @Test("hasSparklineData returns false when empty")
    func hasSparklineDataFalseWhenEmpty() {
        let appState = AppState()
        #expect(appState.hasSparklineData == false)
    }
    
    @Test("hasSparklineData returns false with 1 data point")
    func hasSparklineDataFalseWithOne() {
        let appState = AppState()
        let poll = UsagePoll(
            id: 1,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            fiveHourUtil: 50.0,
            fiveHourResetsAt: nil,
            sevenDayUtil: 30.0,
            sevenDayResetsAt: nil
        )
        appState.updateSparklineData([poll])
        #expect(appState.hasSparklineData == false)
    }
    
    @Test("hasSparklineData returns true with 2+ data points")
    func hasSparklineDataTrueWithTwo() {
        let appState = AppState()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let polls = [
            UsagePoll(id: 1, timestamp: now - 60000, fiveHourUtil: 50.0, fiveHourResetsAt: nil, sevenDayUtil: 30.0, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: now, fiveHourUtil: 52.0, fiveHourResetsAt: nil, sevenDayUtil: 31.0, sevenDayResetsAt: nil)
        ]
        appState.updateSparklineData(polls)
        #expect(appState.hasSparklineData == true)
    }
    
    @Test("updateSparklineData replaces existing data")
    func updateSparklineDataReplaces() {
        let appState = AppState()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        
        let initialPolls = [
            UsagePoll(id: 1, timestamp: now - 60000, fiveHourUtil: 50.0, fiveHourResetsAt: nil, sevenDayUtil: 30.0, sevenDayResetsAt: nil)
        ]
        appState.updateSparklineData(initialPolls)
        #expect(appState.sparklineData.count == 1)
        
        let newPolls = [
            UsagePoll(id: 2, timestamp: now - 30000, fiveHourUtil: 55.0, fiveHourResetsAt: nil, sevenDayUtil: 32.0, sevenDayResetsAt: nil),
            UsagePoll(id: 3, timestamp: now, fiveHourUtil: 60.0, fiveHourResetsAt: nil, sevenDayUtil: 35.0, sevenDayResetsAt: nil)
        ]
        appState.updateSparklineData(newPolls)
        #expect(appState.sparklineData.count == 2)
        #expect(appState.sparklineData[0].id == 2)
    }
    
    @Test("sparklineData preserves timestamp ordering")
    func sparklineDataPreservesOrdering() {
        let appState = AppState()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let polls = [
            UsagePoll(id: 1, timestamp: now - 120000, fiveHourUtil: 50.0, fiveHourResetsAt: nil, sevenDayUtil: 30.0, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: now - 60000, fiveHourUtil: 55.0, fiveHourResetsAt: nil, sevenDayUtil: 32.0, sevenDayResetsAt: nil),
            UsagePoll(id: 3, timestamp: now, fiveHourUtil: 60.0, fiveHourResetsAt: nil, sevenDayUtil: 35.0, sevenDayResetsAt: nil)
        ]
        appState.updateSparklineData(polls)
        
        // Verify ascending order
        for i in 1..<appState.sparklineData.count {
            #expect(appState.sparklineData[i].timestamp > appState.sparklineData[i-1].timestamp)
        }
    }
    
    @Test("sparklineMinDataPoints constant is 2")
    func sparklineMinDataPointsConstant() {
        #expect(AppState.sparklineMinDataPoints == 2)
    }
}
```

```swift
// cc-hdrmTests/Services/PollingEngineTests.swift - Add to existing test suite

@Suite("PollingEngine Sparkline Tests")
@MainActor
struct PollingEngineSparklineTests {
    
    @Test("poll cycle updates sparkline data on success")
    func pollCycleUpdatesSparklineData() async throws {
        let appState = AppState()
        let mockHistoricalService = MockHistoricalDataService()
        let testPolls = [
            UsagePoll(id: 1, timestamp: 1000, fiveHourUtil: 50.0, fiveHourResetsAt: nil, sevenDayUtil: 30.0, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 2000, fiveHourUtil: 52.0, fiveHourResetsAt: nil, sevenDayUtil: 31.0, sevenDayResetsAt: nil)
        ]
        mockHistoricalService.recentPollsToReturn = testPolls
        
        let engine = PollingEngine(
            keychainService: MockKeychainService(credentialsToReturn: .validCredentials),
            tokenRefreshService: MockTokenRefreshService(),
            apiClient: MockAPIClient(responseToReturn: .validResponse),
            appState: appState,
            historicalDataService: mockHistoricalService
        )
        
        await engine.performPollCycle()
        
        // Use expectation pattern instead of arbitrary sleep
        let expectation = XCTestExpectation(description: "Sparkline data updated")
        Task {
            while appState.sparklineData.isEmpty {
                try? await Task.sleep(for: .milliseconds(10))
            }
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
        
        #expect(appState.sparklineData.count == 2)
        #expect(appState.sparklineData[0].timestamp < appState.sparklineData[1].timestamp)
    }
    
    @Test("sparkline refresh failure does not prevent poll cycle completion")
    func sparklineRefreshFailureDoesNotBlockPoll() async throws {
        let appState = AppState()
        let mockHistoricalService = MockHistoricalDataService()
        mockHistoricalService.shouldThrowOnGetRecentPolls = true // Simulate DB failure
        
        let engine = PollingEngine(
            keychainService: MockKeychainService(credentialsToReturn: .validCredentials),
            tokenRefreshService: MockTokenRefreshService(),
            apiClient: MockAPIClient(responseToReturn: .validResponse),
            appState: appState,
            historicalDataService: mockHistoricalService
        )
        
        // Poll should complete successfully despite sparkline failure
        await engine.performPollCycle()
        
        // Main state should be updated
        #expect(appState.connectionStatus == .connected)
        #expect(appState.fiveHour != nil)
        
        // Sparkline data should remain empty (refresh failed)
        // Wait briefly to ensure async task had time to run
        try await Task.sleep(for: .milliseconds(50))
        #expect(appState.sparklineData.isEmpty)
    }
}
```

### MockHistoricalDataService Extension

Ensure the mock supports sparkline testing:

```swift
// In MockHistoricalDataService (likely in cc-hdrmTests/Mocks/)

var recentPollsToReturn: [UsagePoll] = []
var shouldThrowOnGetRecentPolls = false

func getRecentPolls(hours: Int) async throws -> [UsagePoll] {
    if shouldThrowOnGetRecentPolls {
        throw AppError.databaseError(message: "Mock DB failure")
    }
    return recentPollsToReturn
}
```

### Dependency on Other Stories

**Requires (already complete):**
- Story 10.2: HistoricalDataService.persistPoll() - poll data in DB
- Story 10.5: HistoricalDataService.getRecentPolls(hours:) - query API

**Enables (future stories):**
- Story 12.2: Sparkline Component - will render AppState.sparklineData, handle empty/nil states
- Story 12.3: Sparkline as Analytics Toggle - will check hasSparklineData
- Story 12.4: PopoverView Integration - will use sparklineData
- Story 13.1: Analytics Window Shell - will add isAnalyticsWindowOpen to AppState

### References

- [Source: cc-hdrm/State/AppState.swift] - Current AppState implementation
- [Source: cc-hdrm/Services/PollingEngine.swift:131-193] - fetchUsageData() method
- [Source: cc-hdrm/Services/HistoricalDataServiceProtocol.swift:18-28] - getRecentPolls API
- [Source: cc-hdrm/Models/UsagePoll.swift] - UsagePoll model with sparkline fields
- [Source: _bmad-output/planning-artifacts/epics.md:1285-1306] - Story 12.1 acceptance criteria
- [Source: _bmad-output/planning-artifacts/architecture.md:1280-1285] - Sparkline data architecture
- [Source: _bmad-output/planning-artifacts/ux-design-specification-phase3.md:171-200] - Sparkline UX requirements
- [Source: _bmad-output/implementation-artifacts/11-4-popover-slope-display.md] - Previous story patterns

## Dev Agent Record

### Agent Model Used

claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

None required - implementation followed Dev Notes patterns exactly.

### Completion Notes List

- Task 1: Added `sparklineData: [UsagePoll]` property, `updateSparklineData()` method, and `sparklineMinDataPoints` constant to AppState. Property is observable via `@Observable` class.
- Task 2: Implemented async sparkline refresh in PollingEngine with cancellation token pattern (`sparklineRefreshTask`). Refresh is fire-and-forget, non-blocking, with error logging.
- Task 3: Added `hasSparklineData` computed property returning `sparklineData.count >= sparklineMinDataPoints`.
- Task 4: Added 7 unit tests for sparkline properties covering empty state, single point, 2+ points, data replacement, ordering, and constant verification.
- Task 5: Added 4 integration tests for PollingEngine sparkline refresh covering success, failure graceful handling, ordering preservation, and nil service handling. Extended `PEMockHistoricalDataService` with sparkline testing support.
- Task 6: Build successful, 559 tests pass (11 new sparkline tests added to baseline 548).

### File List

**Modified:**
- cc-hdrm/State/AppState.swift - Added sparklineData, sparklineMinDataPoints, hasSparklineData, updateSparklineData()
- cc-hdrm/Services/PollingEngine.swift - Added sparklineRefreshTask property and async refresh logic after slope calculation
- cc-hdrmTests/State/AppStateTests.swift - Added 7 sparkline unit tests
- cc-hdrmTests/Services/PollingEngineTests.swift - Added PollingEngineSparklineTests suite with 4 integration tests, extended PEMockHistoricalDataService

**No new files created** - all changes to existing files per Dev Notes specification.

## Change Log

- 2026-02-04: Implemented Story 12.1 - Sparkline Data Preparation. Added sparklineData property and refresh mechanism to support 24h sparkline visualization in popover. All 6 tasks completed, 559 tests pass.
- 2026-02-04: Code Review fixes applied: (1) Cancel sparklineRefreshTask in PollingEngine.stop() to prevent orphaned refresh operations, (2) Added clarifying comment for MainActor.run usage in async Task, (3) Added test for nil fiveHourUtil edge case. 560 tests pass.
