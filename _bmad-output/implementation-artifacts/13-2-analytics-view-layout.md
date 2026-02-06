# Story 13.2: Analytics View Layout

Status: done

## Story

As a developer using Claude Code,
I want a clear analytics view layout with time controls, chart, and breakdown,
So that I can explore my usage patterns effectively.

## Acceptance Criteria

1. **Given** the analytics window is open
   **When** AnalyticsView renders
   **Then** it displays (top to bottom):
   - Title bar: "Usage Analytics" with close button
   - Time range selector: [24h] [7d] [30d] [All] buttons
   - Series toggles: 5h (filled circle) | 7d (empty circle) toggle buttons
   - Main chart area (UsageChart component)
   - Headroom breakdown section (HeadroomBreakdownBar + stats)
   **And** vertical spacing follows macOS design guidelines

2. **Given** the window is resized
   **When** AnalyticsView re-renders
   **Then** the chart area expands/contracts to fill available space
   **And** controls and breakdown maintain their natural sizes

## Tasks / Subtasks

- [x] Task 1: Wire AnalyticsView to AppState and HistoricalDataService (AC: 1)
  - [x] 1.1 Add `@Environment(AppState.self)` or pass `AppState` to AnalyticsView so it can observe live data
  - [x] 1.2 Inject `HistoricalDataServiceProtocol` into AnalyticsView (via environment or init parameter) for data queries
  - [x] 1.3 Add `@State private var chartData: [UsagePoll] = []` and `@State private var rollupData: [UsageRollup] = []` for chart content
  - [x] 1.4 Add `@State private var resetEvents: [ResetEvent] = []` for breakdown section
  - [x] 1.5 Add `@State private var isLoading: Bool = false` for loading indicator
  - [x] 1.6 Implement `loadData()` async method that calls `ensureRollupsUpToDate()` then queries data for selected time range
  - [x] 1.7 Call `loadData()` via `.task {}` modifier on appear and `.onChange(of: selectedTimeRange)` on time range change

- [x] Task 2: Replace chart placeholder with UsageChart stub (AC: 1, 2)
  - [x] 2.1 Create `cc-hdrm/Views/UsageChart.swift` as a stub view that accepts `data`, `timeRange`, `fiveHourVisible`, `sevenDayVisible`
  - [x] 2.2 UsageChart stub renders a bordered area with the loaded data point count (e.g., "148 data points") and time range label
  - [x] 2.3 UsageChart shows "Select a series to display" when both series toggled off
  - [x] 2.4 UsageChart shows loading indicator when `isLoading` is true
  - [x] 2.5 UsageChart maintains `frame(maxWidth: .infinity, maxHeight: .infinity)` for flexible resizing (AC: 2)
  - [x] 2.6 Replace `chartPlaceholder` in AnalyticsView with `UsageChart(...)` passing state

- [x] Task 3: Replace breakdown placeholder with HeadroomBreakdownBar stub (AC: 1)
  - [x] 3.1 Create `cc-hdrm/Views/HeadroomBreakdownBar.swift` as a stub view that accepts `resetEvents` and `creditLimits`
  - [x] 3.2 Stub renders: "Headroom breakdown: N reset events in period" or "No reset events in this period"
  - [x] 3.3 Stub renders "Headroom breakdown unavailable -- unknown subscription tier" when credit limits are nil
  - [x] 3.4 Maintains fixed ~80px height, `frame(maxWidth: .infinity)` (AC: 2)
  - [x] 3.5 Replace `breakdownPlaceholder` in AnalyticsView with `HeadroomBreakdownBar(...)` passing state

- [x] Task 4: Wire series toggles to chart visibility (AC: 1)
  - [x] 4.1 Pass `fiveHourVisible` and `sevenDayVisible` state from AnalyticsView to UsageChart
  - [x] 4.2 Verify toggle state works (toggling off 7d should be reflected in UsageChart)
  - [x] 4.3 Verify both-off state shows "Select a series to display" message

- [x] Task 5: Wire time range selector to data loading (AC: 1)
  - [x] 5.1 On `selectedTimeRange` change, call `loadData()` which queries HistoricalDataService with the new range
  - [x] 5.2 Show loading state while data loads
  - [x] 5.3 For `.day` range: call `getRecentPolls(hours: 24)` -> populate `chartData`
  - [x] 5.4 For `.week`/`.month`/`.all`: call `getRolledUpData(range:)` -> populate `rollupData`
  - [x] 5.5 For all ranges: call `getResetEvents(range:)` -> populate `resetEvents`

- [x] Task 6: Pass AnalyticsView dependencies from AnalyticsWindow (AC: 1)
  - [x] 6.1 Modify `cc-hdrm/Views/AnalyticsWindow.swift` `createPanel()` to inject AppState and HistoricalDataService into AnalyticsView's hosting environment
  - [x] 6.2 Ensure the service dependency chain is satisfied (AnalyticsWindow already has `appState` reference)
  - [x] 6.3 Wire HistoricalDataService from AppDelegate's service graph into AnalyticsWindow

- [x] Task 7: Write/update tests (AC: all)
  - [x] 7.1 Update `cc-hdrmTests/Views/AnalyticsViewTests.swift` to verify data loading integration (mock HistoricalDataService)
  - [x] 7.2 Create `cc-hdrmTests/Views/UsageChartTests.swift` for stub component (verify data point count display, series visibility, empty states)
  - [x] 7.3 Create `cc-hdrmTests/Views/HeadroomBreakdownBarTests.swift` for stub component (verify reset event count, nil credit limits message)
  - [x] 7.4 Test time range change triggers data reload
  - [x] 7.5 Test series toggle state passed to chart

- [x] Task 8: Build verification
  - [x] 8.1 Run `xcodegen generate` to update project file
  - [x] 8.2 Run `xcodebuild -scheme cc-hdrm -destination 'platform=macOS' build`
  - [x] 8.3 Run full test suite
  - [ ] 8.4 Manual: Open analytics window, verify layout with real data (not placeholder text)
  - [ ] 8.5 Manual: Switch time ranges, verify data reloads (loading state visible briefly)
  - [ ] 8.6 Manual: Toggle series off/on, verify chart responds
  - [ ] 8.7 Manual: Resize window, verify chart expands while controls/breakdown stay fixed

> **Note:** Tasks 8.4-8.7 require human manual verification. Cannot be automated.

## Dev Notes

### CRITICAL: Layout Shell Already Exists (Story 13.1)

Story 13.1 built the full analytics layout shell including:
- Title bar with close button
- TimeRangeSelector component (`cc-hdrm/Views/TimeRangeSelector.swift`)
- Series toggles (inline in AnalyticsView as `@State` properties)
- Chart placeholder (bordered area with icon)
- Breakdown placeholder (bordered area, 80px fixed height)
- Resize behavior (chart fills available space via `maxWidth/maxHeight: .infinity`)

**Story 13.2's role is to transform this static shell into a live, data-driven layout.** The structural layout (AC 1-2) is already satisfied. This story's real work is:

1. **Wire data flow:** Connect AnalyticsView to `HistoricalDataService` for time-range-appropriate data queries
2. **Replace placeholders with real stub components:** Create `UsageChart` and `HeadroomBreakdownBar` as typed stub views (not placeholders) that accept real data and display summary info. Full chart rendering is Stories 13.5-13.7; full breakdown is Stories 14.3-14.5
3. **Wire controls to data:** Time range selector triggers data reload; series toggles pass visibility state to chart

### AnalyticsView Current Interface

```swift
// cc-hdrm/Views/AnalyticsView.swift (143 lines)
struct AnalyticsView: View {
    var onClose: () -> Void
    @State private var selectedTimeRange: TimeRange = .week
    @State private var fiveHourVisible: Bool = true
    @State private var sevenDayVisible: Bool = true
    // ... title bar, controls row, chart placeholder, breakdown placeholder
}
```

Keep the `onClose` callback pattern. Add state for loaded data and dependencies.

### Dependency Injection Pattern

AnalyticsView needs access to `HistoricalDataService` for data queries. Follow the existing pattern used in the codebase:

```swift
// Option A: Init parameter (preferred for testability)
struct AnalyticsView: View {
    var onClose: () -> Void
    let historicalDataService: HistoricalDataServiceProtocol
    // ...
}

// Wire in AnalyticsWindow.createPanel():
let view = AnalyticsView(
    onClose: { AnalyticsWindow.shared.close() },
    historicalDataService: self.historicalDataService
)
```

Check how other views receive service dependencies in this codebase before choosing approach. The `AnalyticsWindow` singleton already has `appState: AppState?` — add `historicalDataService` similarly.

### Data Loading Pattern

```swift
// In AnalyticsView:
@State private var chartData: [UsagePoll] = []      // For 24h step-area
@State private var rollupData: [UsageRollup] = []   // For 7d/30d/all bars
@State private var resetEvents: [ResetEvent] = []   // For breakdown
@State private var isLoading: Bool = false

private func loadData() async {
    isLoading = true
    defer { isLoading = false }
    
    do {
        try await historicalDataService.ensureRollupsUpToDate()
        
        switch selectedTimeRange {
        case .day:
            chartData = try await historicalDataService.getRecentPolls(hours: 24)
            rollupData = []
        case .week, .month, .all:
            rollupData = try await historicalDataService.getRolledUpData(range: selectedTimeRange)
            chartData = []
        }
        
        resetEvents = try await historicalDataService.getResetEvents(range: selectedTimeRange)
    } catch {
        // Log error, keep previous data visible
    }
}
```

Trigger via `.task { await loadData() }` and `.onChange(of: selectedTimeRange) { _, _ in Task { await loadData() } }`.

### UsageChart Stub Component

Create `cc-hdrm/Views/UsageChart.swift`. This is a **typed stub** — it accepts the real data types and interface that Stories 13.5-13.7 will flesh out, but renders summary info instead of actual charts.

```swift
struct UsageChart: View {
    let pollData: [UsagePoll]       // Raw polls for 24h view
    let rollupData: [UsageRollup]   // Rolled data for 7d+ views
    let timeRange: TimeRange
    let fiveHourVisible: Bool
    let sevenDayVisible: Bool
    let isLoading: Bool
    
    var body: some View {
        // Bordered area showing data summary
        // Stories 13.5-13.7 will replace this body with real chart rendering
    }
}
```

### HeadroomBreakdownBar Stub Component

Create `cc-hdrm/Views/HeadroomBreakdownBar.swift`. This is a **typed stub** — Stories 14.3-14.5 will implement the three-band visualization.

```swift
struct HeadroomBreakdownBar: View {
    let resetEvents: [ResetEvent]
    let creditLimits: CreditLimits?  // From AppState
    
    var body: some View {
        // Summary display of reset events
        // Stories 14.3-14.5 will replace with actual three-band bar + stats
    }
}
```

### HistoricalDataService Query API Reference

Available methods from `HistoricalDataServiceProtocol` (cc-hdrm/Services/HistoricalDataServiceProtocol.swift):

| Method | Returns | Use |
|--------|---------|-----|
| `ensureRollupsUpToDate()` | Void | Call FIRST before any queries. Runs tiered rollup engine |
| `getRecentPolls(hours: Int)` | `[UsagePoll]` | Raw polls for 24h chart (ascending timestamp) |
| `getRolledUpData(range: TimeRange)` | `[UsageRollup]` | Auto-stitched rolled data for 7d/30d/all |
| `getResetEvents(range: TimeRange)` | `[ResetEvent]` | Reset events for breakdown calculation |

Resolution stitching in `getRolledUpData`:
- `.day` -> raw polls only
- `.week` -> raw (<24h) + 5min rollups (1-7d)
- `.month` -> raw + 5min + hourly rollups (7-30d)
- `.all` -> raw + 5min + hourly + daily (full history)

### AnalyticsWindow Wiring

Current `AnalyticsWindow` (`cc-hdrm/Views/AnalyticsWindow.swift`) creates the panel and hosts AnalyticsView:

```swift
// In createPanel():
let analyticsView = AnalyticsView(onClose: { AnalyticsWindow.shared.close() })
// ... hosted in NSHostingView
```

Must be updated to pass the `historicalDataService` dependency. Check how `AnalyticsWindow` is configured in `cc-hdrm/App/AppDelegate.swift` (line ~57-59) — `configure(appState:)` is called there. Extend with `configure(appState:historicalDataService:)` or similar.

### AppState Properties Consumed

From `cc-hdrm/State/AppState.swift`:
- `creditLimits: CreditLimits?` — needed by HeadroomBreakdownBar to determine if breakdown is available
- `isAnalyticsWindowOpen: Bool` — already wired, no changes needed

### Project Structure Notes

**New Files:**
```
cc-hdrm/Views/UsageChart.swift             # Typed stub for chart component
cc-hdrm/Views/HeadroomBreakdownBar.swift   # Typed stub for breakdown component
```

**Modified Files:**
```
cc-hdrm/Views/AnalyticsView.swift          # Wire data loading, replace placeholders with real components
cc-hdrm/Views/AnalyticsWindow.swift        # Add HistoricalDataService dependency injection
cc-hdrm/App/AppDelegate.swift              # Pass HistoricalDataService to AnalyticsWindow.configure()
```

**New Test Files:**
```
cc-hdrmTests/Views/UsageChartTests.swift
cc-hdrmTests/Views/HeadroomBreakdownBarTests.swift
```

**Modified Test Files:**
```
cc-hdrmTests/Views/AnalyticsViewTests.swift  # Add data loading tests
```

**After adding new files, run:**
```bash
xcodegen generate
```

### Alignment with Existing Code Conventions

- **Layer-based organization:** Views in `cc-hdrm/Views/`, Models in `cc-hdrm/Models/`
- **One type per file:** `UsageChart.swift`, `HeadroomBreakdownBar.swift`
- **Protocol-based testing:** Use `HistoricalDataServiceProtocol` for mock injection in tests
- **Accessibility:** Every new interactive element needs `.accessibilityLabel()`. Chart stub needs "Usage chart" label. Breakdown stub needs "Headroom breakdown" label
- **No external deps:** Use SwiftUI only. No Swift Charts framework (chart rendering deferred to Stories 13.5-13.7)
- **@MainActor:** Data loading state (`@State`) is view-local, automatically MainActor. The `loadData()` async method should update `@State` on the main actor
- **Logging:** Add `os.Logger(subsystem: "com.cc-hdrm.app", category: "analytics")` for data loading errors
- **Error handling:** Data load failures should be logged and silently tolerated — display previous data or empty state, never crash

### Previous Story Intelligence

**From Story 13.1 (analytics-window-shell):**
- AnalyticsView has `onClose` callback pattern — preserve it
- TimeRangeSelector is a standalone component in `cc-hdrm/Views/TimeRangeSelector.swift`
- Series toggles are `@State` inline in AnalyticsView, both default to `true`
- Chart placeholder uses `frame(maxWidth: .infinity, maxHeight: .infinity)` — maintain this on UsageChart
- Breakdown placeholder is 80px fixed height — maintain on HeadroomBreakdownBar
- AnalyticsPanel subclass handles Escape key — no changes needed
- 691 tests pass at Story 13.1 completion (post code review)
- `TimeRange` enum already existed from Story 10.4 — Story 13.1 added `displayLabel` and `accessibilityDescription` properties
- Default time range is `.week` (not `.day`) — chosen because 24h is too narrow for first impression

**From Story 12.3 (sparkline-as-analytics-toggle):**
- AnalyticsWindow is a singleton: `AnalyticsWindow.shared`
- `configure(appState:)` called from AppDelegate
- Window uses `orderFront(nil)` not `makeKeyAndOrderFront` to avoid stealing focus

### Git Intelligence

Last two commits:
- `fac1fef` — fix: macOS accessibility hint and test count in story doc
- `9ce756b` — feat: analytics window shell with layout, TimeRangeSelector, series toggles, Escape key (Story 13.1)

Codebase is stable. No breaking changes since Story 13.1 completion.

### Edge Cases

| No. | Condition | Expected Behavior |
|-----|-----------|-------------------|
| 1 | No historical data exists (fresh install) | UsageChart shows "No data yet — usage history builds over time" |
| 2 | Data loading fails (SQLite error) | Log error, show previous data or empty state, do not crash |
| 3 | Time range has zero data points | UsageChart shows "No data for this time range" |
| 4 | Time range has zero reset events | HeadroomBreakdownBar shows "No reset events in this period" |
| 5 | Credit limits unknown (unknown tier) | HeadroomBreakdownBar shows "Headroom breakdown unavailable -- unknown subscription tier" |
| 6 | Both series toggled off | UsageChart shows "Select a series to display" |
| 7 | Rapid time range switching | Each switch cancels the previous load task, only latest completes |
| 8 | Window resized to minimum (400x350) | Chart area compresses, controls remain visible, breakdown stays 80px |
| 9 | Analytics window opened with large dataset (365 days) | Loading indicator shown briefly, data renders after rollup completes |

### References

- [Source: _bmad-output/planning-artifacts/epics.md:1462-1483] - Story 13.2 requirements
- [Source: _bmad-output/planning-artifacts/architecture.md:1190-1267] - AnalyticsView, UsageChart, TimeRangeSelector specs
- [Source: _bmad-output/planning-artifacts/architecture.md:1014-1075] - Analytics Window Architecture
- [Source: _bmad-output/planning-artifacts/architecture.md:870-885] - HistoricalDataService protocol
- [Source: _bmad-output/planning-artifacts/ux-design-specification-phase3.md:220-300] - Analytics window layout and behavior
- [Source: cc-hdrm/Views/AnalyticsView.swift:1-143] - Current layout shell (replace placeholders)
- [Source: cc-hdrm/Views/AnalyticsWindow.swift:1-108] - Singleton controller (add service injection)
- [Source: cc-hdrm/Views/TimeRangeSelector.swift:1-56] - Already built, no changes needed
- [Source: cc-hdrm/Services/HistoricalDataServiceProtocol.swift] - Data query API
- [Source: cc-hdrm/Services/HistoricalDataService.swift] - Implementation (1392 lines)
- [Source: cc-hdrm/State/AppState.swift:54,230] - isAnalyticsWindowOpen, creditLimits
- [Source: cc-hdrm/App/AppDelegate.swift:57-59] - AnalyticsWindow configuration
- [Source: _bmad-output/implementation-artifacts/13-1-analytics-window-shell.md] - Previous story (layout shell, learnings)
- [Source: _bmad-output/implementation-artifacts/12-3-sparkline-as-analytics-toggle.md] - AnalyticsWindow creation story

## Dev Agent Record

### Agent Model Used

claude-opus-4-6

### Debug Log References

None — clean implementation, no debug issues encountered.

### Completion Notes List

- Chose init-parameter injection over @Environment for HistoricalDataService (testability, matches codebase pattern)
- AppState passed as init parameter to AnalyticsView for creditLimits access by HeadroomBreakdownBar
- AnalyticsWindow.configure() signature changed from `configure(appState:)` to `configure(appState:historicalDataService:)` — all 7 existing call sites in tests updated
- Created shared MockHistoricalDataService in cc-hdrmTests/Mocks/ (replaces per-file private mocks for analytics tests)
- Added `@State private var loadTask: Task<Void, Never>?` for rapid time-range switching cancellation (edge case 7)
- loadData() errors are logged via os.Logger and silently tolerated per edge case 2 spec
- UsageChart stub shows 5 states: loading, no-series-selected, fresh-install-empty, range-empty, and data-summary
- HeadroomBreakdownBar stub shows 3 states: nil-credit-limits, no-reset-events, and event-count
- AppDelegate defers AnalyticsWindow.configure() until after HistoricalDataService is created (moved from line 59 to after polling engine block)
- Preview stub (PreviewHistoricalDataService) is #if DEBUG only inside AnalyticsView.swift
- 719 tests pass (28 new tests added: 11 AnalyticsView, 15 UsageChart, 10 HeadroomBreakdownBar, minus 8 removed old AnalyticsView tests replaced by new ones)
- Tasks 8.4-8.7 require manual verification by user

### Change Log

- 2026-02-06: Story 13.2 implementation complete — wired AnalyticsView to HistoricalDataService, replaced placeholders with UsageChart and HeadroomBreakdownBar typed stubs, wired time range selector to data loading, wired series toggles to chart visibility, injected dependencies from AppDelegate through AnalyticsWindow
- 2026-02-06: Code review fixes (5 issues) — removed force unwraps in AnalyticsWindow.createPanel() (H1), added fresh-install "No data yet" empty state with hasAnyHistoricalData flag (H2), added Task.checkCancellation() to loadData() to prevent stale data overwrites on rapid range switching (M1), fixed singular/plural grammar in HeadroomBreakdownBar (M3), added sprint-status.yaml to File List (M2). 719 tests pass.
- 2026-02-06: Bugfix — ensureRollupsUpToDate() failure was blocking the entire data fetch in loadData(). Separated rollup update into its own try/catch so data queries proceed even if rollups fail. This was causing the analytics chart to show "No data yet" despite sparkline having data.

### File List

**New Files:**
- cc-hdrm/Views/UsageChart.swift
- cc-hdrm/Views/HeadroomBreakdownBar.swift
- cc-hdrmTests/Views/UsageChartTests.swift
- cc-hdrmTests/Views/HeadroomBreakdownBarTests.swift
- cc-hdrmTests/Mocks/MockHistoricalDataService.swift

**Modified Files:**
- cc-hdrm/Views/AnalyticsView.swift
- cc-hdrm/Views/AnalyticsWindow.swift
- cc-hdrm/App/AppDelegate.swift
- cc-hdrmTests/Views/AnalyticsViewTests.swift
- cc-hdrmTests/Views/AnalyticsWindowTests.swift
- cc-hdrmTests/Views/PopoverViewSparklineTests.swift
- _bmad-output/implementation-artifacts/sprint-status.yaml
