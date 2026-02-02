# Story 2.3: Data Freshness Tracking

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want the app to track and communicate data freshness,
so that I never see a number I can't trust as current.

## Acceptance Criteria

1. **Given** usage data was fetched successfully, **When** less than 60 seconds have elapsed since the last fetch, **Then** AppState reflects normal freshness (no warning).
2. **Given** usage data was fetched successfully, **When** 60 seconds to 5 minutes have elapsed since the last fetch, **Then** AppState reflects stale data state.
3. **And** the popover timestamp shows "Updated Xm ago" in amber/warning color.
4. **Given** usage data was fetched successfully, **When** more than 5 minutes have elapsed since the last fetch, **Then** AppState reflects very stale data state.
5. **And** a StatusMessageView-compatible status is set: "Data may be outdated" / "Last updated: Xm ago".
6. **Given** the app has never successfully fetched data, **When** the display renders, **Then** the menu bar shows "✳ —" in grey (full disconnected state).
7. **And** no stale number is ever displayed.

## Tasks / Subtasks

- [x] Task 1: Create `DataFreshness` enum (AC: #1, #2, #4)
  - [x] Create `cc-hdrm/Models/DataFreshness.swift`
  - [x] Define `enum DataFreshness: String, CaseIterable, Sendable` with cases: `.fresh`, `.stale`, `.veryStale`, `.unknown`
  - [x] Add `init(lastUpdated: Date?)` that computes freshness from elapsed time:
    - `nil` → `.unknown`
    - < 60s → `.fresh`
    - 60s–300s → `.stale`
    - > 300s → `.veryStale`
  - [x] Add thresholds as static constants: `staleThreshold: TimeInterval = 60`, `veryStaleThreshold: TimeInterval = 300`
- [x] Task 2: Add `dataFreshness` computed property to `AppState` (AC: #1, #2, #4, #6, #7)
  - [x] In `cc-hdrm/State/AppState.swift`, add a computed property `var dataFreshness: DataFreshness` that derives from `lastUpdated`
  - [x] This is a **derived** property (computed, never stored) — same pattern as `WindowState.headroomState`
  - [x] When `connectionStatus` is not `.connected`, return `.unknown` regardless of `lastUpdated`
- [x] Task 3: Add freshness-aware status message logic to `PollingEngine` (AC: #4, #5)
  - [x] In `cc-hdrm/Services/PollingEngine.swift`, after each successful fetch cycle, do NOT set a stale status message — freshness is a time-based concern, not a fetch-cycle concern
  - [x] Instead, create a `FreshnessMonitor` that runs a timer to check staleness periodically
  - [x] Create `cc-hdrm/Services/FreshnessMonitor.swift`
  - [x] `FreshnessMonitor` accepts `AppState`, checks `appState.dataFreshness` every 15 seconds via `Task.sleep`
  - [x] When freshness transitions to `.veryStale` and `connectionStatus` is `.connected`: set `appState.updateStatusMessage(StatusMessage(title: "Data may be outdated", detail: "Last updated: Xm ago"))`
  - [x] When freshness returns to `.fresh` (after a successful poll): clear the status message (PollingEngine already does this on success)
  - [x] When freshness is `.stale`: do NOT set a status message — stale state is communicated only through the popover timestamp color (implemented in Story 4.4)
  - [x] `FreshnessMonitor` conforms to a `FreshnessMonitorProtocol` for testability
  - [x] Create `cc-hdrm/Services/FreshnessMonitorProtocol.swift`
- [x] Task 4: Wire `FreshnessMonitor` into `AppDelegate` (AC: #4, #5)
  - [x] In `cc-hdrm/App/AppDelegate.swift`, create `FreshnessMonitor` alongside `PollingEngine`
  - [x] Start the monitor in `applicationDidFinishLaunching` after starting `PollingEngine`
  - [x] Stop the monitor in `applicationWillTerminate`
- [x] Task 5: Add relative time formatting to `Date+Formatting.swift` (AC: #3, #5)
  - [x] In `cc-hdrm/Extensions/Date+Formatting.swift`, add `func relativeTimeAgo() -> String` extension on `Date`
  - [x] Formatting rules (from UX spec):
    - < 60s: `"just now"` or `"Xs ago"`
    - 60s–3600s: `"Xm ago"`
    - 3600s–86400s: `"Xh Ym ago"`
    - > 86400s: `"Xd Xh ago"`
  - [x] This is the same formatting pattern used by CountdownLabel (Story 4.2) — establish the pattern now
- [x] Task 6: Write `DataFreshness` tests (AC: #1, #2, #4)
  - [x] Create `cc-hdrmTests/Models/DataFreshnessTests.swift`
  - [x] Test: `nil` lastUpdated → `.unknown`
  - [x] Test: 0 seconds ago → `.fresh`
  - [x] Test: 30 seconds ago → `.fresh`
  - [x] Test: 59 seconds ago → `.fresh`
  - [x] Test: 60 seconds ago → `.stale`
  - [x] Test: 180 seconds ago → `.stale`
  - [x] Test: 299 seconds ago → `.stale`
  - [x] Test: 300 seconds ago → `.veryStale`
  - [x] Test: 600 seconds ago → `.veryStale`
- [x] Task 7: Write `AppState.dataFreshness` tests (AC: #1, #2, #4, #6)
  - [x] In `cc-hdrmTests/State/AppStateTests.swift` (create if not exists)
  - [x] Test: `lastUpdated` is nil → `.unknown`
  - [x] Test: `lastUpdated` is recent + connected → `.fresh`
  - [x] Test: `lastUpdated` is recent + disconnected → `.unknown` (connection status overrides)
  - [x] Test: `lastUpdated` is old + connected → `.veryStale`
- [x] Task 8: Write `FreshnessMonitor` tests (AC: #4, #5)
  - [x] Create `cc-hdrmTests/Services/FreshnessMonitorTests.swift`
  - [x] Test: when `dataFreshness` is `.veryStale` and connected, status message is set to "Data may be outdated"
  - [x] Test: when `dataFreshness` is `.fresh`, no status message is set
  - [x] Test: when `dataFreshness` is `.stale`, no status message is set (stale only affects popover timestamp color)
  - [x] Test: when `connectionStatus` is not `.connected`, no stale message is set even if data is old
  - [x] Test: `stop()` cancels the monitor task
- [x] Task 9: Write `Date.relativeTimeAgo()` tests (AC: #3, #5)
  - [x] In `cc-hdrmTests/Extensions/DateFormattingTests.swift` (create or extend existing)
  - [x] Test: 5 seconds ago → `"5s ago"`
  - [x] Test: 45 seconds ago → `"45s ago"`
  - [x] Test: 90 seconds ago → `"1m ago"`
  - [x] Test: 150 seconds ago → `"2m ago"`
  - [x] Test: 3720 seconds ago → `"1h 2m ago"`
  - [x] Test: 90000 seconds ago → `"1d 1h ago"`
- [x] Task 10: Update `AppDelegateTests` for `FreshnessMonitor` wiring (AC: #4)
  - [x] Add test verifying `AppDelegate` creates and starts `FreshnessMonitor`
  - [x] Add test verifying `applicationWillTerminate` stops the `FreshnessMonitor`

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. `FreshnessMonitor` sits behind `FreshnessMonitorProtocol` — same protocol-based injection pattern as all other services.
- **State derivation:** `dataFreshness` is a **computed** property on `AppState`, derived from `lastUpdated` and `connectionStatus`. This follows the same pattern as `WindowState.headroomState` — never stored separately, always derived.
- **Concurrency:** `FreshnessMonitor` uses `Task.sleep` loop, same pattern as `PollingEngine`. No GCD.
- **State management:** `FreshnessMonitor` writes to `AppState` via `updateStatusMessage()` — never sets properties directly.
- **Logging:** `os.Logger` with subsystem `com.cc-hdrm.app`, category `freshness`.

### DataFreshness Enum Design

```swift
// Conceptual structure — NOT copy-paste code
enum DataFreshness: String, CaseIterable, Sendable {
    case fresh       // < 60s since last update — normal, no indicators
    case stale       // 60s–5m — popover timestamp turns amber (Story 4.4)
    case veryStale   // > 5m — StatusMessageView shows "Data may be outdated"
    case unknown     // Never fetched or disconnected — full grey state

    static let staleThreshold: TimeInterval = 60
    static let veryStaleThreshold: TimeInterval = 300

    init(lastUpdated: Date?) {
        guard let lastUpdated else {
            self = .unknown
            return
        }
        let elapsed = Date().timeIntervalSince(lastUpdated)
        switch elapsed {
        case ..<Self.staleThreshold:
            self = .fresh
        case ..<Self.veryStaleThreshold:
            self = .stale
        default:
            self = .veryStale
        }
    }
}
```

### AppState.dataFreshness Design

```swift
// Added to AppState as a computed property
var dataFreshness: DataFreshness {
    guard connectionStatus == .connected else {
        return .unknown
    }
    return DataFreshness(lastUpdated: lastUpdated)
}
```

**Key insight:** When `connectionStatus` is not `.connected`, `dataFreshness` returns `.unknown` regardless of `lastUpdated`. This ensures we never display stale data warnings alongside disconnection messages — disconnection takes precedence.

### FreshnessMonitor Design

```swift
// Conceptual structure — NOT copy-paste code
@MainActor
final class FreshnessMonitor: FreshnessMonitorProtocol {
    private let appState: AppState
    private var monitorTask: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.cc-hdrm.app", category: "freshness")
    private static let checkInterval: TimeInterval = 15

    func start() async {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.checkInterval))
                guard !Task.isCancelled else { break }
                self?.checkFreshness()
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func checkFreshness() {
        let freshness = appState.dataFreshness
        switch freshness {
        case .veryStale:
            let timeAgo = appState.lastUpdated?.relativeTimeAgo() ?? "unknown"
            appState.updateStatusMessage(StatusMessage(
                title: "Data may be outdated",
                detail: "Last updated: \(timeAgo)"
            ))
        case .fresh, .stale:
            // Don't clear status message here — PollingEngine manages it on successful fetch
            // Only clear if the current message is OUR stale message
            if appState.statusMessage?.title == "Data may be outdated" {
                appState.updateStatusMessage(nil)
            }
        case .unknown:
            // Disconnected/no credentials — don't interfere with those status messages
            break
        }
    }
}
```

**Why a separate FreshnessMonitor instead of checking in PollingEngine?**
- PollingEngine runs every 30s. Data becomes stale at 60s. If a poll fails, the next staleness check wouldn't happen for another 30s — potentially 90s before the user sees a stale indicator.
- FreshnessMonitor checks every 15s, ensuring staleness transitions are detected within 15s of the threshold.
- Separation of concerns: PollingEngine fetches data, FreshnessMonitor monitors time-based state.

### Interaction with Existing Components

**PollingEngine (no changes to logic):**
- On successful fetch: already calls `appState.updateStatusMessage(nil)` — this clears any "Data may be outdated" message.
- On error: already sets appropriate error messages — FreshnessMonitor defers to these via the `.unknown` check.

**Views (future stories):**
- Story 3.1/3.2 (Menu Bar): Will read `appState.dataFreshness` — no display when `.unknown` (AC #6, #7).
- Story 4.4 (Panel Footer): Will read `appState.dataFreshness` to color the "Updated Xs ago" text amber when `.stale`.
- Story 4.5 (StatusMessageView): Already reads `appState.statusMessage` — will show "Data may be outdated" when FreshnessMonitor sets it.

### `Date.relativeTimeAgo()` Formatting

This establishes the relative time formatting that will be reused by:
- Popover footer "Updated Xs ago" (Story 4.4)
- StatusMessageView "Last updated: Xm ago" (this story)
- Notification content (Story 5.2, 5.3) — uses the same `Date+Formatting.swift` source of truth

```swift
// Added to Date+Formatting.swift
extension Date {
    func relativeTimeAgo() -> String {
        let elapsed = Date().timeIntervalSince(self)
        switch elapsed {
        case ..<60:
            return "\(Int(elapsed))s ago"
        case ..<3600:
            return "\(Int(elapsed / 60))m ago"
        case ..<86400:
            let hours = Int(elapsed / 3600)
            let minutes = Int((elapsed.truncatingRemainder(dividingBy: 3600)) / 60)
            return minutes > 0 ? "\(hours)h \(minutes)m ago" : "\(hours)h ago"
        default:
            let days = Int(elapsed / 86400)
            let hours = Int((elapsed.truncatingRemainder(dividingBy: 86400)) / 3600)
            return hours > 0 ? "\(days)d \(hours)h ago" : "\(days)d ago"
        }
    }
}
```

### Previous Story Intelligence (2.2)

**What was built:**
- `PollingEngine` with `@MainActor`, injectable services, `Task.sleep` loop at 30s, `performPollCycle()` exposed for testing
- `PollingEngineProtocol` (Sendable)
- `AppDelegate` stripped to lifecycle management — creates PollingEngine on launch, stops on terminate
- 96 tests passing

**Patterns to reuse:**
- `@MainActor` on service classes that touch `AppState`
- `Task.sleep(for: .seconds(N))` loop with `Task.isCancelled` guard
- `stop()` cancels internal `Task` and sets to nil
- Protocol-based injection for testability
- `MockPollingEngine` pattern for AppDelegate tests — reuse for `MockFreshnessMonitor`
- Test `performPollCycle()` / `checkFreshness()` directly (expose as `internal`) rather than testing full loop timing

**Code review lessons from previous stories:**
- Pass original error to `AppError` wrappers, not hardcoded errors
- Remove dead code / unused properties before committing
- Add call counters to mocks for verifying interaction patterns
- Make services `@MainActor` (not `@unchecked Sendable`) when they hold `AppState` reference

### Git Intelligence

Recent commits show:
- Story 2.2 extracted polling from AppDelegate into PollingEngine
- Story 2.1 established APIClient, UsageResponse, Date+Formatting
- project-context.md was added summarizing architecture

**Patterns from recent work:**
- New protocol + implementation files for each service
- Tests mirror source structure
- Sprint status updated on story completion

### Project Structure Notes

- XcodeGen (`project.yml`) uses directory-based source discovery — new files in correct folders are auto-included
- All new files go in the architecture-specified locations per layer-based structure
- Test files mirror source structure

### File Structure Requirements

New files to create:
```
cc-hdrm/Models/DataFreshness.swift
cc-hdrm/Services/FreshnessMonitor.swift
cc-hdrm/Services/FreshnessMonitorProtocol.swift
cc-hdrmTests/Models/DataFreshnessTests.swift
cc-hdrmTests/Services/FreshnessMonitorTests.swift
```

Files to modify:
```
cc-hdrm/State/AppState.swift                   # Add dataFreshness computed property
cc-hdrm/Extensions/Date+Formatting.swift        # Add relativeTimeAgo()
cc-hdrm/App/AppDelegate.swift                   # Wire FreshnessMonitor
cc-hdrmTests/State/AppStateTests.swift           # Add dataFreshness tests (create if needed)
cc-hdrmTests/App/AppDelegateTests.swift          # Add FreshnessMonitor wiring tests
cc-hdrmTests/Extensions/DateFormattingTests.swift # Add relativeTimeAgo tests (create if needed)
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **Mocking:** Create `MockFreshnessMonitor` conforming to `FreshnessMonitorProtocol` for AppDelegate tests.
- **`@MainActor`:** Required on any test touching `AppState`
- **Time manipulation:** For `DataFreshness` tests, create dates using `Date().addingTimeInterval(-N)` to simulate elapsed time.
- **FreshnessMonitor testing:** Call `checkFreshness()` directly (expose as `internal`) rather than testing the full timer loop. Set `appState.lastUpdated` to specific dates before calling.

### Anti-Patterns to Avoid

- DO NOT store `dataFreshness` as a separate property — it must be computed from `lastUpdated` and `connectionStatus`
- DO NOT add freshness checking inside `PollingEngine` — keep separation of concerns
- DO NOT use `Timer` or `DispatchQueue` — use `Task.sleep` for the monitor loop
- DO NOT set stale status messages when disconnected — disconnection messages take precedence
- DO NOT clear non-freshness status messages from `FreshnessMonitor` — only clear messages that `FreshnessMonitor` itself set
- DO NOT log timestamps or dates that could leak usage patterns — keep logs factual and minimal
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file

### References

- [Source: epics.md#Story 2.3] — Full acceptance criteria, data freshness tiers
- [Source: ux-design-specification.md#Data Freshness] — <60s normal, 60s-5m stale warning in popover, >5m StatusMessageView
- [Source: architecture.md#Cross-Cutting Concerns] — Data freshness centrally managed
- [Source: architecture.md#State Management Patterns] — Derived state, services write via methods
- [Source: architecture.md#Logging Patterns] — os.Logger categories
- [Source: prd.md#NFR1] — Menu bar updates within 2s of new data
- [Source: 2-2-background-polling-engine.md] — PollingEngine patterns, @MainActor, mock patterns
- [Source: AppState.swift:37] — `lastUpdated: Date?` already exists, needs consumer

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

No debug issues encountered. Build and tests passed on first attempt after xcodegen regeneration.

### Completion Notes List

- Implemented `DataFreshness` enum with `init(lastUpdated:)` computing freshness from elapsed time, with static threshold constants
- Added `dataFreshness` computed property to `AppState` — derived from `lastUpdated` + `connectionStatus`, returns `.unknown` when disconnected
- Added `setLastUpdated(_:)` internal helper to `AppState` for test-time control of `lastUpdated`
- Created `FreshnessMonitorProtocol` and `FreshnessMonitor` — checks every 15s via `Task.sleep`, sets "Data may be outdated" status on `.veryStale`, clears own message on recovery, defers to other status messages
- Wired `FreshnessMonitor` into `AppDelegate` — created alongside `PollingEngine`, started on launch, stopped on terminate, injectable via init for testing
- Added `Date.relativeTimeAgo()` extension — formats elapsed time as "Xs ago", "Xm ago", "Xh Ym ago", "Xd Xh ago"
- 124 tests passing (28 new tests added across 5 test files), 0 regressions

### Change Log

- 2026-01-31: Implemented Story 2.3 — Data Freshness Tracking (all 10 tasks, 28 new tests)
- 2026-02-01: Code Review fixes — 8 issues resolved (3 HIGH, 3 MEDIUM, 2 LOW), 3 new tests added (127 total)

### File List

New files:
- cc-hdrm/Models/DataFreshness.swift
- cc-hdrm/Services/FreshnessMonitor.swift
- cc-hdrm/Services/FreshnessMonitorProtocol.swift
- cc-hdrmTests/Models/DataFreshnessTests.swift
- cc-hdrmTests/Services/FreshnessMonitorTests.swift

Modified files:
- cc-hdrm/State/AppState.swift
- cc-hdrm/Extensions/Date+Formatting.swift
- cc-hdrm/App/AppDelegate.swift
- cc-hdrmTests/State/AppStateTests.swift
- cc-hdrmTests/App/AppDelegateTests.swift
- cc-hdrmTests/Extensions/DateFormattingTests.swift
- cc-hdrmTests/Models/DataFreshnessTests.swift
- _bmad-output/implementation-artifacts/sprint-status.yaml
