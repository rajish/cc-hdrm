# Story 11.1: Slope Calculation Service & Ring Buffer

Status: review

## Story

As a developer using Claude Code,
I want cc-hdrm to track recent poll data and calculate usage slope,
So that burn rate can be displayed alongside utilization.

## Acceptance Criteria

1. **Given** the app launches
   **When** SlopeCalculationService initializes
   **Then** it maintains an in-memory ring buffer for the last 15 minutes of poll data (~30 data points at 30s intervals)
   **And** SlopeCalculationService conforms to SlopeCalculationServiceProtocol for testability
   **And** it calls HistoricalDataService.getRecentPolls(hours: 1) to bootstrap the buffer from SQLite

2. **Given** a new poll cycle completes
   **When** SlopeCalculationService.addPoll() is called with the UsageResponse
   **Then** the new data point is added to the ring buffer
   **And** older data points beyond 15 minutes are evicted
   **And** slope is recalculated for both 5h and 7d windows

3. **Given** the ring buffer contains less than 10 minutes of data
   **When** calculateSlope() is called
   **Then** it returns .flat (insufficient data to determine slope)

## Tasks / Subtasks

- [x] Task 1: Create SlopeLevel enum (AC: #2, #3)
  - [x] 1.1 Create `cc-hdrm/Models/SlopeLevel.swift`
  - [x] 1.2 Define enum cases: `.flat`, `.rising`, `.steep` (NO cooling - utilization cannot decrease)
  - [x] 1.3 Add `arrow: String` computed property (→, ↗, ⬆)
  - [x] 1.4 Add `accessibilityLabel: String` computed property ("flat", "rising", "steep")
  - [x] 1.5 Mark enum as `Sendable` and `Equatable`

- [x] Task 2: Create UsageWindow enum (AC: #2)
  - [x] 2.1 Create `cc-hdrm/Models/UsageWindow.swift` (if not exists)
  - [x] 2.2 Define cases: `.fiveHour`, `.sevenDay`
  - [x] 2.3 Mark enum as `Sendable` and `Equatable`

- [x] Task 3: Create SlopeCalculationServiceProtocol (AC: #1, #2)
  - [x] 3.1 Create `cc-hdrm/Services/SlopeCalculationServiceProtocol.swift`
  - [x] 3.2 Define protocol methods:
    - `func addPoll(_ poll: UsagePoll)`
    - `func calculateSlope(for window: UsageWindow) -> SlopeLevel`
    - `func bootstrapFromHistory(_ polls: [UsagePoll])`
  - [x] 3.3 Protocol must be `Sendable` for actor isolation compatibility

- [x] Task 4: Implement RingBuffer data structure (AC: #1, #2)
  - [x] 4.1 Create private `RingBuffer<T>` struct or use array with fixed capacity
  - [x] 4.2 Store `(timestamp: Int64, fiveHourUtil: Double?, sevenDayUtil: Double?)` tuples
  - [x] 4.3 Implement automatic eviction of entries older than 15 minutes
  - [x] 4.4 Capacity: ~30 entries (15 min / 30s interval)

- [x] Task 5: Create SlopeCalculationService implementation (AC: #1, #2, #3)
  - [x] 5.1 Create `cc-hdrm/Services/SlopeCalculationService.swift`
  - [x] 5.2 Implement `addPoll()` - convert UsagePoll to buffer entry, add to buffer, evict stale
  - [x] 5.3 Implement `calculateSlope(for:)` with rate-of-change calculation
  - [x] 5.4 Implement `bootstrapFromHistory()` - populate buffer from SQLite polls
  - [x] 5.5 Add `os.Logger` with category `"slope"`
  - [x] 5.6 Mark as `@unchecked Sendable` with proper thread safety (NSLock pattern from Epic 10)

- [x] Task 6: Implement slope calculation math (AC: #2, #3)
  - [x] 6.1 Filter buffer entries with non-nil utilization for target window
  - [x] 6.2 Require minimum 10 minutes of data (~20 entries) for valid calculation
  - [x] 6.3 Compute average rate of change: `(latest_util - oldest_util) / time_span_minutes`
  - [x] 6.4 Map rate to SlopeLevel using thresholds (NO cooling level - utilization is monotonically increasing):
    - Rate < 0.3% per min → `.flat` (includes any negative rate from reset edge case)
    - Rate 0.3 to 1.5% per min → `.rising`
    - Rate > 1.5% per min → `.steep`
  - [x] 6.5 Return `.flat` if insufficient data

- [x] Task 7: Extend AppState with slope properties (AC: #2)
  - [x] 7.1 Add `private(set) var fiveHourSlope: SlopeLevel = .flat` to AppState
  - [x] 7.2 Add `private(set) var sevenDaySlope: SlopeLevel = .flat` to AppState
  - [x] 7.3 Add `func updateSlopes(fiveHour: SlopeLevel, sevenDay: SlopeLevel)` method

- [x] Task 8: Integrate with PollingEngine (AC: #2)
  - [x] 8.1 Add `slopeCalculationService: (any SlopeCalculationServiceProtocol)?` parameter to PollingEngine init
  - [x] 8.2 In `fetchUsageData()`, after successful response and persistence, call `slopeCalculationService?.addPoll()`
  - [x] 8.3 After addPoll, calculate slopes and update AppState:
    ```swift
    let fiveHourSlope = slopeCalculationService.calculateSlope(for: .fiveHour)
    let sevenDaySlope = slopeCalculationService.calculateSlope(for: .sevenDay)
    appState.updateSlopes(fiveHour: fiveHourSlope, sevenDay: sevenDaySlope)
    ```

- [x] Task 9: Wire service in AppDelegate (AC: #1)
  - [x] 9.1 Create SlopeCalculationService instance in AppDelegate
  - [x] 9.2 Bootstrap from history on app startup:
    ```swift
    Task {
        if let polls = try? await historicalDataService.getRecentPolls(hours: 1) {
            slopeCalculationService.bootstrapFromHistory(polls)
        }
    }
    ```
  - [x] 9.3 Pass SlopeCalculationService to PollingEngine

- [x] Task 10: Write unit tests (AC: #1, #2, #3)
  - [x] 10.1 Create `cc-hdrmTests/Models/SlopeLevelTests.swift`
  - [x] 10.2 Create `cc-hdrmTests/Services/SlopeCalculationServiceTests.swift`
  - [x] 10.3 Test addPoll adds entry to buffer
  - [x] 10.4 Test buffer evicts entries older than 15 minutes
  - [x] 10.5 Test calculateSlope returns .flat with insufficient data (<10 min)
  - [x] 10.6 Test calculateSlope returns correct level for various rates:
    - Test flat (stable/idle utilization, rate < 0.3%/min)
    - Test rising (moderate increase, rate 0.3-1.5%/min)
    - Test steep (rapid increase, rate > 1.5%/min)
    - Test edge case: negative rate (reset in buffer) returns .flat
  - [x] 10.7 Test bootstrapFromHistory populates buffer correctly
  - [x] 10.8 Test 5h and 7d windows calculated independently
  - [x] 10.9 Test protocol conformance

## Dev Notes

### CRITICAL: Utilization is Monotonically Increasing

**THIS IS THE MOST IMPORTANT CONSTRAINT TO UNDERSTAND:**

Within any rate limit window (5h or 7d), utilization **ONLY GOES UP**. You consume tokens, you cannot un-consume them. The utilization percentage can only:
1. **Increase** — as you use Claude
2. **Stay flat** — when idle
3. **Jump to ~0% at reset** — discontinuous, not a gradual decrease

**There is NO gradual decrease.** The rolling window does NOT cause utilization to "cool off" over time. The window defines when the reset happens, not a continuous decay.

**Implication for slope calculation:** A negative slope is **impossible** during normal operation. The only way to see decreasing utilization is at the instant of a reset boundary, which is a discontinuous jump — not a trend.

**Therefore: There is no "Cooling" slope level.** Only three levels exist: Flat, Rising, Steep.

---

### Architecture Context

This is the **first story of Epic 11 (Usage Slope Indicator)**. It establishes the calculation engine that will power slope display in the menu bar (Story 11.3) and popover (Story 11.4).

**Data Flow:**
```
PollingEngine -> fetchUsageData() -> UsageResponse
                                        |
                    +-------------------+-------------------+
                    |                                       |
                    v                                       v
          HistoricalDataService.persistPoll()    SlopeCalculationService.addPoll()
                                                            |
                                                            v
                                                  Ring Buffer (15 min)
                                                            |
                                                            v
                                              calculateSlope(for: .fiveHour/.sevenDay)
                                                            |
                                                            v
                                              AppState.updateSlopes()
```

### SlopeLevel Enum (3 Levels Only)

**No "Cooling" level exists** — see critical constraint above. Utilization cannot decrease gradually.

```swift
enum SlopeLevel: String, Sendable, Equatable, CaseIterable {
    case flat     // → no meaningful change (idle, or usage matches natural pace)
    case rising   // ↗ moderate consumption
    case steep    // ⬆ heavy consumption, burning fast
    
    var arrow: String {
        switch self {
        case .flat: return "→"
        case .rising: return "↗"
        case .steep: return "⬆"
        }
    }
    
    var accessibilityLabel: String {
        rawValue  // "flat", "rising", "steep"
    }
}
```

### SlopeCalculationServiceProtocol

```swift
// Source: _bmad-output/planning-artifacts/architecture.md:895-899
protocol SlopeCalculationServiceProtocol: Sendable {
    /// Add a poll data point to the ring buffer.
    func addPoll(_ poll: UsagePoll)
    
    /// Calculate current slope for specified window.
    /// Returns .flat if insufficient data (<10 minutes).
    func calculateSlope(for window: UsageWindow) -> SlopeLevel
    
    /// Bootstrap buffer from historical data on app launch.
    func bootstrapFromHistory(_ polls: [UsagePoll])
}
```

### Ring Buffer Implementation Strategy

**Option A: Fixed-size array with circular index** (preferred for performance)
```swift
private struct BufferEntry: Sendable {
    let timestamp: Int64  // Unix milliseconds
    let fiveHourUtil: Double?
    let sevenDayUtil: Double?
}

private var buffer: [BufferEntry] = []
private let maxAge: Int64 = 15 * 60 * 1000  // 15 minutes in ms
```

**Eviction strategy:** On each `addPoll()`, remove entries where `timestamp < (now - maxAge)`.

**Why not a true circular buffer?** Time-based eviction is simpler and handles gaps (app not running) naturally.

### Slope Calculation Math

**Remember:** Rate will always be >= 0 during normal operation (utilization only increases).

```swift
func calculateSlope(for window: UsageWindow) -> SlopeLevel {
    let entries = buffer.compactMap { entry -> (Int64, Double)? in
        let util = window == .fiveHour ? entry.fiveHourUtil : entry.sevenDayUtil
        guard let util = util else { return nil }
        return (entry.timestamp, util)
    }
    
    guard entries.count >= 20 else { return .flat }  // Need ~10 minutes of data
    
    let oldest = entries.first!
    let newest = entries.last!
    let timeSpanMinutes = Double(newest.0 - oldest.0) / (60 * 1000)
    
    guard timeSpanMinutes >= 10 else { return .flat }
    
    let ratePerMinute = (newest.1 - oldest.1) / timeSpanMinutes
    
    // Note: ratePerMinute should always be >= 0 (utilization only increases)
    // Negative rates can only occur if buffer spans a reset boundary - treat as flat
    switch ratePerMinute {
    case ..<0.3: return .flat      // Idle or very light use
    case 0.3..<1.5: return .rising // Moderate consumption
    default: return .steep         // Heavy consumption
    }
}
```

**Rate thresholds (% per minute):**
| Rate      | Level   | Meaning                              |
| --------- | ------- | ------------------------------------ |
| < 0.3     | Flat    | Idle or light use                    |
| 0.3 - 1.5 | Rising  | Moderate consumption                 |
| > 1.5     | Steep   | Heavy consumption, burning fast      |

**Edge case:** If a reset occurs within the buffer window, the calculated rate may be negative. Treat this as `.flat` — the reset event itself is the meaningful signal, not the artificial negative slope.

### Thread Safety Pattern

Follow the pattern established in Epic 10 (DatabaseManager, HistoricalDataService):

```swift
final class SlopeCalculationService: SlopeCalculationServiceProtocol, @unchecked Sendable {
    private var buffer: [BufferEntry] = []
    private let lock = NSLock()
    
    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "slope"
    )
    
    func addPoll(_ poll: UsagePoll) {
        lock.withLock {
            // Add new entry
            let entry = BufferEntry(
                timestamp: poll.timestamp,
                fiveHourUtil: poll.fiveHourUtil,
                sevenDayUtil: poll.sevenDayUtil
            )
            buffer.append(entry)
            
            // Evict stale entries
            let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - maxAge
            buffer.removeAll { $0.timestamp < cutoff }
        }
    }
}
```

### PollingEngine Integration Point

Integrate in `PollingEngine.fetchUsageData()` after the historicalDataService persistence call:

```swift
// cc-hdrm/Services/PollingEngine.swift:165-175 (approximate)
// After: try await historicalDataService?.persistPoll(response, tier: credentials.rateLimitTier)

// NEW: Update slope calculation
if let slopeService = slopeCalculationService {
    // Convert UsageResponse to UsagePoll for slope service
    let poll = UsagePoll(
        id: 0,  // Not from DB, ID doesn't matter
        timestamp: Int64(Date().timeIntervalSince1970 * 1000),
        fiveHourUtil: response.fiveHour?.utilization,
        fiveHourResetsAt: nil,  // Not needed for slope
        sevenDayUtil: response.sevenDay?.utilization,
        sevenDayResetsAt: nil
    )
    slopeService.addPoll(poll)
    
    let fiveHourSlope = slopeService.calculateSlope(for: .fiveHour)
    let sevenDaySlope = slopeService.calculateSlope(for: .sevenDay)
    appState.updateSlopes(fiveHour: fiveHourSlope, sevenDay: sevenDaySlope)
}
```

### AppState Extension

Add to `cc-hdrm/State/AppState.swift`:

```swift
// After line 47 (availableUpdate property)
private(set) var fiveHourSlope: SlopeLevel = .flat
private(set) var sevenDaySlope: SlopeLevel = .flat

// Add method after updateWindows():
func updateSlopes(fiveHour: SlopeLevel, sevenDay: SlopeLevel) {
    self.fiveHourSlope = fiveHour
    self.sevenDaySlope = sevenDay
}
```

### Bootstrap on App Launch

In `AppDelegate.swift`, after DatabaseManager initialization and HistoricalDataService creation:

```swift
// Bootstrap slope buffer from history
Task {
    do {
        let recentPolls = try await historicalDataService.getRecentPolls(hours: 1)
        slopeCalculationService.bootstrapFromHistory(recentPolls)
        Self.logger.info("Slope buffer bootstrapped with \(recentPolls.count) historical polls")
    } catch {
        Self.logger.warning("Failed to bootstrap slope buffer: \(error.localizedDescription)")
        // Continue without historical data - buffer will fill naturally
    }
}
```

### Project Structure Notes

**New files to create:**
```
cc-hdrm/Models/
├── SlopeLevel.swift                         # NEW
└── UsageWindow.swift                        # NEW (if not exists)

cc-hdrm/Services/
├── SlopeCalculationServiceProtocol.swift    # NEW
└── SlopeCalculationService.swift            # NEW

cc-hdrmTests/Models/
└── SlopeLevelTests.swift                    # NEW

cc-hdrmTests/Services/
└── SlopeCalculationServiceTests.swift       # NEW
```

**Modified files:**
```
cc-hdrm/State/AppState.swift                 # Add slope properties
cc-hdrm/Services/PollingEngine.swift         # Add slopeCalculationService parameter
cc-hdrm/App/AppDelegate.swift                # Wire up service, bootstrap
```

### Previous Epic Learnings (Epic 10)

From Stories 10.1-10.5 completion notes:

1. **Thread safety** - Use `@unchecked Sendable` with NSLock for mutable state
2. **Protocol-first** - Define protocol before implementation for testability
3. **Graceful degradation** - Service should work even if historical data unavailable
4. **Logger pattern** - `private static let logger = Logger(subsystem:category:)`
5. **Fire-and-forget async** - Bootstrap can happen asynchronously without blocking startup
6. **Test cleanup** - Create fresh service instances per test

### Testing Strategy

**Unit tests with isolated service:**
```swift
func testAddPollAddsEntryToBuffer() {
    let service = SlopeCalculationService()
    let poll = createTestPoll(fiveHourUtil: 50.0, sevenDayUtil: 30.0)
    
    service.addPoll(poll)
    
    // Verify by calculating slope (should return .flat due to insufficient data)
    XCTAssertEqual(service.calculateSlope(for: .fiveHour), .flat)
}

func testCalculateSlopeReturnsRisingForIncreasingUtilization() {
    let service = SlopeCalculationService()
    
    // Add 20 polls over 10 minutes with increasing utilization
    let baseTime = Int64(Date().timeIntervalSince1970 * 1000) - (10 * 60 * 1000)
    for i in 0..<20 {
        let poll = UsagePoll(
            id: Int64(i),
            timestamp: baseTime + Int64(i * 30 * 1000),  // 30s intervals
            fiveHourUtil: 50.0 + Double(i),  // +1% per poll = +2%/min
            fiveHourResetsAt: nil,
            sevenDayUtil: 30.0,
            sevenDayResetsAt: nil
        )
        service.addPoll(poll)
    }
    
    XCTAssertEqual(service.calculateSlope(for: .fiveHour), .steep)  // >1.5%/min
    XCTAssertEqual(service.calculateSlope(for: .sevenDay), .flat)   // No change
}
```

### References

- [Source: _bmad-output/planning-artifacts/architecture.md:890-923] - SlopeCalculationService specification
- [Source: _bmad-output/planning-artifacts/architecture.md:901-906] - SlopeLevel enum definition
- [Source: _bmad-output/planning-artifacts/ux-design-specification-phase3.md:52-76] - Slope level thresholds and UX
- [Source: _bmad-output/planning-artifacts/epics.md:1151-1173] - Story 11.1 acceptance criteria
- [Source: cc-hdrm/Services/PollingEngine.swift:1-50] - Integration point for addPoll
- [Source: cc-hdrm/Models/UsagePoll.swift] - Poll data structure
- [Source: cc-hdrm/State/AppState.swift:40-50] - State properties pattern
- [Source: cc-hdrm/Services/HistoricalDataService.swift] - Bootstrap data source

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

N/A

### Completion Notes List

- Implemented SlopeLevel enum with flat/rising/steep cases (no cooling level per architecture spec)
- Implemented UsageWindow enum for 5h/7d window identification
- Created SlopeCalculationServiceProtocol for testability via dependency injection
- Implemented SlopeCalculationService with NSLock thread safety pattern from Epic 10
- Ring buffer implementation uses time-based eviction (15 min max age) with ~30 entry capacity
- Slope calculation uses rate-of-change thresholds: <0.3%/min=flat, 0.3-1.5%/min=rising, >1.5%/min=steep
- Negative rates (reset edge case) treated as flat per spec
- Extended AppState with fiveHourSlope/sevenDaySlope properties and updateSlopes() method
- Integrated with PollingEngine to calculate slopes after each successful poll
- Wired AppDelegate to create service, bootstrap from history, and pass to PollingEngine
- All 479 tests pass including 28 new slope-related tests

### File List

**New Files:**
- cc-hdrm/Models/SlopeLevel.swift
- cc-hdrm/Models/UsageWindow.swift
- cc-hdrm/Services/SlopeCalculationServiceProtocol.swift
- cc-hdrm/Services/SlopeCalculationService.swift
- cc-hdrmTests/Models/SlopeLevelTests.swift
- cc-hdrmTests/Services/SlopeCalculationServiceTests.swift

**Modified Files:**
- cc-hdrm/State/AppState.swift (added slope properties)
- cc-hdrm/Services/PollingEngine.swift (added slopeCalculationService integration)
- cc-hdrm/App/AppDelegate.swift (wired service, bootstrap)
- cc-hdrm.xcodeproj/project.pbxproj (added new files)

## Change Log

- 2026-02-03: Implemented Story 11.1 - Slope Calculation Service & Ring Buffer (all 10 tasks complete)
