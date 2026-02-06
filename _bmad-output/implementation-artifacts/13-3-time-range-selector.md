# Story 13.3: Time Range Selector

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to select different time ranges to analyze my usage patterns,
So that I can see both recent detail and long-term trends.

## Acceptance Criteria

1. **Given** the analytics view is visible
   **When** TimeRangeSelector renders
   **Then** it shows four buttons: "24h", "7d", "30d", "All"
   **And** one button is visually selected (filled/highlighted)
   **And** default selection is "7d" (design override: 24h too narrow for first impression; deliberate choice from Story 13.1)

2. **Given** Alex clicks a time range button
   **When** the selection changes
   **Then** the chart and breakdown update to show data for that range
   **And** data is loaded via HistoricalDataService with appropriate resolution:
   - `.day` -> `getRecentPolls(hours: 24)` for raw poll data
   - `.week` / `.month` / `.all` -> `getRolledUpData(range:)` for rollup data
   **And** `ensureRollupsUpToDate()` is called before querying (best-effort; failure does not block data display)
   **And** `getResetEvents(range:)` is called for the HeadroomBreakdownBar

3. **Given** Alex selects "All"
   **When** the data loads
   **Then** it includes daily summaries from the full retention period
   **And** if retention is 1 year, "All" shows up to 365 data points

## Tasks / Subtasks

- [x] Task 1: Verify TimeRangeSelector AC compliance (AC: 1)
  - [x] 1.1 Confirm `cc-hdrm/Views/TimeRangeSelector.swift` renders all 4 buttons with correct labels ("24h", "7d", "30d", "All")
  - [x] 1.2 Confirm selected button has filled/highlighted styling (accent color background, white text)
  - [x] 1.3 Confirm unselected buttons have outline styling (clear background, secondary text, subtle border)
  - [x] 1.4 Confirm default `selectedTimeRange` in `cc-hdrm/Views/AnalyticsView.swift` is `.week`
  - [x] 1.5 Confirm each button has `.accessibilityLabel` ("Last 24 hours", "Last 7 days", "Last 30 days", "All time")
  - [x] 1.6 Confirm selected button has `.accessibilityAddTraits(.isSelected)`

- [x] Task 2: Verify data loading on range change (AC: 2)
  - [x] 2.1 Confirm `.task(id: selectedTimeRange)` triggers `loadData()` on range change in `cc-hdrm/Views/AnalyticsView.swift`
  - [x] 2.2 Confirm `.day` case calls `getRecentPolls(hours: 24)` and clears `rollupData`
  - [x] 2.3 Confirm `.week` / `.month` / `.all` cases call `getRolledUpData(range:)` and clear `chartData`
  - [x] 2.4 Confirm `ensureRollupsUpToDate()` is called first, with failure handled gracefully (warning logged, data query proceeds)
  - [x] 2.5 Confirm `getResetEvents(range:)` is called for all ranges
  - [x] 2.6 Confirm `Task.checkCancellation()` is called between queries to handle rapid range switching
  - [x] 2.7 Confirm `isLoading` state is set to `true` during load and `false` after

- [x] Task 3: Add targeted test coverage for time-range-change data loading (AC: 2, 3)
  - [x] 3.1 Add test: switching time range triggers data reload (verify `MockHistoricalDataService` call counts increment)
  - [x] 3.2 Add test: `.day` range calls `getRecentPolls`, not `getRolledUpData`
  - [x] 3.3 Add test: `.week` range calls `getRolledUpData`, not `getRecentPolls`
  - [x] 3.4 Add test: `.all` range calls `getRolledUpData` with `.all` parameter
  - [x] 3.5 Add test: `ensureRollupsUpToDate` is called before data queries
  - [x] 3.6 Add test: `getResetEvents` is called for each range
  - [x] 3.7 Add test: rollup failure does not prevent data loading (mock throws on `ensureRollupsUpToDate`, verify data still loads)

- [x] Task 4: Build verification (AC: all)
  - [x] 4.1 Run `xcodegen generate` to ensure project file is current
  - [x] 4.2 Run `xcodebuild -scheme cc-hdrm -destination 'platform=macOS' build`
  - [x] 4.3 Run full test suite
  - [ ] 4.4 Manual: Open analytics window, click each time range button, verify data reloads
  - [ ] 4.5 Manual: Verify loading indicator appears briefly during range switch
  - [ ] 4.6 Manual: Verify selected button styling changes on click

> **Note:** Tasks 4.4-4.6 require human manual verification. Cannot be automated.

## Dev Notes

### CRITICAL: This Story Is Mostly Pre-Built

Stories 13.1 and 13.2 already implemented the vast majority of Story 13.3's requirements:

- **Story 13.1** created `TimeRangeSelector` component (`cc-hdrm/Views/TimeRangeSelector.swift`, 56 lines) with all 4 buttons, selected/unselected styling, accessibility labels, and `@Binding var selected: TimeRange`
- **Story 13.1** created the `TimeRange` enum (`cc-hdrm/Models/TimeRange.swift`, 62 lines) with `.day`, `.week`, `.month`, `.all` cases, `displayLabel`, `accessibilityDescription`, and `startTimestamp` properties
- **Story 13.2** wired `AnalyticsView` to `HistoricalDataService`, including:
  - `.task(id: selectedTimeRange)` triggering `loadData()` on range change
  - Resolution-appropriate queries (raw polls for `.day`, rollups for `.week`/`.month`/`.all`)
  - `ensureRollupsUpToDate()` called before queries (with graceful failure handling)
  - `getResetEvents(range:)` for HeadroomBreakdownBar
  - `Task.checkCancellation()` for rapid range switching
  - Loading state management

**This story's primary job is verification and targeted test additions**, not new implementation. The dev agent should audit existing code against ACs, fill any test gaps for time-range-change behavior, and confirm build + test pass.

### Default Time Range: `.week` (Not `.day`)

The epic says default is "24h" but Story 13.1 deliberately chose `.week` with documented rationale:
> "24h is too narrow for first impression; 30d/All require rollup data that may be sparse early on."

This is preserved. The default is `.week` in `cc-hdrm/Views/AnalyticsView.swift:18`.

### Existing Test Coverage

Tests already exist in:
- `cc-hdrmTests/Views/TimeRangeSelectorTests.swift` (75 lines) — 5 tests covering rendering, binding, accessibility
- `cc-hdrmTests/Models/TimeRangeTests.swift` (79 lines) — display labels, accessibility descriptions, ordering
- `cc-hdrmTests/Views/AnalyticsViewTests.swift` (151 lines) — 11 tests including `defaultTimeRange`, `allTimeRangesAvailable`, `createdWithThrowingMock`

**Gap:** No tests explicitly verify that switching from `.day` to `.week` triggers the correct `HistoricalDataService` method (`getRecentPolls` vs `getRolledUpData`). Task 3 fills this gap.

### Data Resolution Mapping (Reference)

| TimeRange | Data Source | Method | Resolution |
|-----------|------------|--------|------------|
| `.day` | `usage_polls` | `getRecentPolls(hours: 24)` | Per-poll (~30s) |
| `.week` | `usage_polls` + `usage_rollups` | `getRolledUpData(range: .week)` | Raw (<24h) + 5min (1-7d) |
| `.month` | `usage_rollups` | `getRolledUpData(range: .month)` | Raw + 5min + hourly (7-30d) |
| `.all` | `usage_rollups` | `getRolledUpData(range: .all)` | Raw + 5min + hourly + daily (30d+) |

Resolution stitching is handled inside `HistoricalDataService.getRolledUpData()` — the view doesn't need to know about tiers.

### AnalyticsView Data Loading Flow (Reference)

```swift
// cc-hdrm/Views/AnalyticsView.swift:62-101
private func loadData() async {
    let range = selectedTimeRange
    isLoading = true
    defer { isLoading = false }

    // Best-effort rollup update
    do {
        try await historicalDataService.ensureRollupsUpToDate()
    } catch {
        Self.logger.warning("Rollup update failed...")
    }

    do {
        try Task.checkCancellation()
        switch range {
        case .day:
            chartData = try await historicalDataService.getRecentPolls(hours: 24)
            rollupData = []
        case .week, .month, .all:
            rollupData = try await historicalDataService.getRolledUpData(range: range)
            chartData = []
        }
        try Task.checkCancellation()
        resetEvents = try await historicalDataService.getResetEvents(range: range)
        // Track fresh-install empty state
        if !hasAnyHistoricalData && (chartData.count + rollupData.count) > 0 {
            hasAnyHistoricalData = true
        }
    } catch is CancellationError {
        // Rapid range switching — discard silently
    } catch {
        Self.logger.error("Analytics data load failed: \(error.localizedDescription)")
    }
}
```

### MockHistoricalDataService (Reference)

Located at `cc-hdrmTests/Mocks/MockHistoricalDataService.swift` (104 lines). Shared mock with:
- Call count tracking: `getRecentPollsCallCount`, `getRolledUpDataCallCount`, `ensureRollupsUpToDateCallCount`, `getResetEventsCallCount`
- Configurable returns: `recentPollsToReturn`, `rolledUpDataToReturn`, `mockResetEvents`
- Error simulation: `shouldThrowOnEnsureRollupsUpToDate`, `shouldThrowOnGetRecentPolls`, `shouldThrowOnGetRolledUpData`
- `lastQueriedTimeRange` for verifying which range was passed

This mock is sufficient for all Task 3 tests — no new mock infrastructure needed.

### Project Structure Notes

**No new files expected.** This story is verification + test additions.

**Potentially modified test files:**
```text
cc-hdrmTests/Views/AnalyticsViewTests.swift  # Add time-range-change data loading tests
```

**After any file changes, run:**
```bash
xcodegen generate
```

### Alignment with Existing Code Conventions

- **Protocol-based testing:** Use `MockHistoricalDataService` for all new tests
- **@MainActor tests:** AnalyticsViewTests suite is `@MainActor` — new tests must be too
- **Async testing:** Use `await` for async view operations if testing data loading directly
- **Test naming:** Follow existing pattern: `testNameDescribingBehavior` (e.g., `dayRangeCallsGetRecentPolls`)
- **Logging:** `os.Logger(subsystem: "com.cc-hdrm.app", category: "analytics")` — already configured
- **Accessibility:** Already verified in existing TimeRangeSelectorTests — no additions needed

### Previous Story Intelligence

**From Story 13.2 (analytics-view-layout):**
- `loadData()` errors are logged and silently tolerated — previous data stays visible
- `ensureRollupsUpToDate()` failure was originally blocking all data; fixed to be best-effort in a post-code-review bugfix
- `@State private var loadTask: Task<Void, Never>?` was considered but `.task(id:)` modifier handles cancellation natively
- 719 tests pass at Story 13.2 completion (post code review + bugfix)

**From Story 13.1 (analytics-window-shell):**
- TimeRangeSelector uses `HStack` of `Button` views with `RoundedRectangle(cornerRadius: 6)` clip shape
- TimeRange enum already existed from Story 10.4 — Story 13.1 added `displayLabel` and `accessibilityDescription`
- Default time range `.week` was a deliberate design choice, documented in code comment
- 691 tests pass at Story 13.1 completion

### Git Intelligence

Last 3 relevant commits:
- `d93aaa8` — Revert "chore: bump version to 1.1.5"
- `cc9a6c0` — fix: decouple rollup update from data query so analytics chart loads data even if rollups fail
- `65047c1` — feat: wire analytics view to data services with UsageChart and HeadroomBreakdownBar stubs (Story 13.2)

Codebase is stable. The rollup decoupling fix (cc9a6c0) is particularly relevant — it ensures `ensureRollupsUpToDate()` failure doesn't block data display, which is AC 2 behavior.

### Edge Cases

| No. | Condition | Expected Behavior |
|-----|-----------|-------------------|
| 1 | Rapid range switching (click 24h then immediately 7d) | Previous load cancelled via `Task.checkCancellation()`, only latest range completes |
| 2 | Range selected with zero data | UsageChart shows "No data for this time range" (if `hasAnyHistoricalData`) or "No data yet" (fresh install) |
| 3 | `ensureRollupsUpToDate()` throws | Warning logged, data query proceeds, chart still populates |
| 4 | Data query throws | Error logged, previous data stays visible, no crash |
| 5 | "All" selected on fresh install | Empty chart with "No data yet" message |
| 6 | "All" selected after 1 year of data | Up to ~365 daily rollup data points |

### References

- [Source: _bmad-output/planning-artifacts/epics.md:1485-1509] - Story 13.3 requirements
- [Source: _bmad-output/planning-artifacts/architecture.md:1253-1267] - TimeRangeSelector architecture spec
- [Source: _bmad-output/planning-artifacts/architecture.md:1190-1216] - AnalyticsView architecture spec
- [Source: _bmad-output/planning-artifacts/architecture.md:870-885] - HistoricalDataService protocol
- [Source: _bmad-output/planning-artifacts/ux-design-specification-phase3.md:270-290] - Time range selector UX spec
- [Source: cc-hdrm/Views/TimeRangeSelector.swift:1-56] - TimeRangeSelector component (built in 13.1)
- [Source: cc-hdrm/Models/TimeRange.swift:1-62] - TimeRange enum (built in 10.4, extended in 13.1)
- [Source: cc-hdrm/Views/AnalyticsView.swift:1-200] - AnalyticsView with data loading (built in 13.1-13.2)
- [Source: cc-hdrm/Services/HistoricalDataServiceProtocol.swift:1-69] - Data service protocol
- [Source: cc-hdrmTests/Views/TimeRangeSelectorTests.swift:1-75] - Existing TimeRangeSelector tests
- [Source: cc-hdrmTests/Models/TimeRangeTests.swift:1-79] - Existing TimeRange tests
- [Source: cc-hdrmTests/Views/AnalyticsViewTests.swift:1-151] - Existing AnalyticsView tests
- [Source: cc-hdrmTests/Mocks/MockHistoricalDataService.swift:1-104] - Shared mock for testing
- [Source: _bmad-output/implementation-artifacts/13-2-analytics-view-layout.md] - Previous story (data wiring)
- [Source: _bmad-output/implementation-artifacts/13-1-analytics-window-shell.md] - Previous story (layout shell)

## Dev Agent Record

### Agent Model Used

claude-opus-4-6 (anthropic/claude-opus-4-6)

### Debug Log References

None required — verification story with minimal code changes.

### Completion Notes List

- **Task 1:** Audited `TimeRangeSelector.swift` against AC-1. All 6 subtasks verified: 4 buttons with correct labels, selected/unselected styling (accent fill vs outline), default `.week`, accessibility labels, `.isSelected` trait. No changes needed.
- **Task 2:** Audited `AnalyticsView.swift:55-101` against AC-2. All 7 subtasks verified: `.task(id: selectedTimeRange)` triggers `loadData()`, `.day` calls `getRecentPolls(hours: 24)`, `.week/.month/.all` call `getRolledUpData(range:)`, `ensureRollupsUpToDate()` is best-effort, `getResetEvents(range:)` called for all ranges, `Task.checkCancellation()` guards rapid switching, `isLoading` state managed via `defer`. No changes needed.
- **Task 3:** Added 11 new tests in `AnalyticsViewDataLoadingTests` suite. To make `loadData()` testable, extracted data-fetching logic into `AnalyticsView.fetchData(for:using:)` static method returning `DataLoadResult` struct. Tests verify: range switching triggers reloads, `.day` calls `getRecentPolls` (not `getRolledUpData`), `.week`/`.month`/`.all` call `getRolledUpData` (not `getRecentPolls`), `.all` passes correct parameter, `ensureRollupsUpToDate` called before queries, `getResetEvents` called for every range, rollup failure doesn't block data loading.
- **Task 4:** `xcodegen generate` succeeded, build succeeded, 730 tests pass (up from 719 post-13.2). Tasks 4.4-4.6 require human manual verification.

### Implementation Plan

Extracted `AnalyticsView.loadData()` internals into `static func fetchData(for:using:) -> DataLoadResult` for testability. The private `loadData()` now delegates to `fetchData`, applies results to `@State`, and handles `CancellationError`. This is the only production code change — all other work was audit + test additions.

### Change Log

- 2026-02-06: Story 13.3 implementation — Verified AC compliance for TimeRangeSelector (Task 1) and data loading (Task 2). Extracted `fetchData(for:using:)` from `AnalyticsView.loadData()` for testability. Added 11 tests covering time-range-change data loading contract (Task 3). Build and 730 tests pass (Task 4).
- 2026-02-06: Code review fixes — (M1) Added doc comments to `DataLoadResult` clarifying internal visibility contract and zero-init semantics. (M2) Added explicit `rollupData = []` / `chartData = []` clearing in `fetchData` switch cases to match original `loadData()` intent. (M3) Added `callOrder` tracking to `MockHistoricalDataService` and updated test 3.5 to verify `ensureRollupsUpToDate` is called before data queries (not just counted). (L1/L2) Removed redundant `monthRangeCallsGetRolledUpData` test, correcting test count to 11. Build and 729 tests pass.

### File List

- `cc-hdrm/Views/AnalyticsView.swift` — Extracted `fetchData(for:using:)` static method and `DataLoadResult` struct from private `loadData()` for testability; added explicit data clearing in switch cases and doc comments on `DataLoadResult` zero-init contract
- `cc-hdrmTests/Views/AnalyticsViewTests.swift` — Added `AnalyticsViewDataLoadingTests` suite with 11 tests for time-range-change data loading; test 3.5 verifies call ordering via `callOrder`
- `cc-hdrmTests/Mocks/MockHistoricalDataService.swift` — Added `callOrder: [String]` array tracking method invocation order for ordering verification in tests
