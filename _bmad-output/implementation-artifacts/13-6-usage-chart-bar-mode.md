# Story 13.6: Usage Chart Component (Bar Mode)

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want a bar chart for 7d+ views showing peak utilization per period,
So that long-term patterns are visible without visual clutter.

## Acceptance Criteria

1. **Given** time range is "7d"
   **When** UsageChart renders
   **Then** it displays a bar chart where:
   - Each bar represents one hour
   - Bar height = peak utilization during that hour (not average)
   - Reset events are marked with subtle indicators below affected bars
   - X-axis shows day/time labels appropriate to the range

2. **Given** time range is "30d"
   **When** UsageChart renders
   **Then** each bar represents one day
   **And** bar height = peak utilization for that day

3. **Given** time range is "All"
   **When** UsageChart renders
   **Then** each bar represents one day (daily summaries)
   **And** X-axis shows date labels with appropriate spacing

4. **Given** the user hovers over a bar
   **When** the hover tooltip appears
   **Then** it shows: period range, min/avg/peak utilization for that period

## Tasks / Subtasks

- [x] Task 1: Create BarChartView component (AC: 1, 2, 3)
  - [x] 1.1 Create `cc-hdrm/Views/BarChartView.swift` with `import Charts`
  - [x] 1.2 Accept `[UsageRollup]`, `fiveHourVisible: Bool`, `sevenDayVisible: Bool`, `timeRange: TimeRange` as inputs
  - [x] 1.3 Map each `UsageRollup` to a `BarPoint` struct: `(id, periodStart: Date, periodEnd: Date, fiveHourPeak: Double?, sevenDayPeak: Double?, fiveHourAvg: Double?, sevenDayAvg: Double?, fiveHourMin: Double?, sevenDayMin: Double?, resetCount: Int)`
  - [x] 1.4 Pre-compute bar points in `init` (same pattern as `StepAreaChartView`) to avoid recomputation on hover

- [x] Task 2: Render bar marks for peak utilization (AC: 1, 2, 3)
  - [x] 2.1 Render 5h series as `BarMark(x: .value("Period", midpointDate), y: .value("Peak", fiveHourPeak))` using `Color.headroomNormal` fill
  - [x] 2.2 Render 7d series as `BarMark` using `StepAreaChartView.sevenDayColor` (blue) -- reuse the same color constant
  - [x] 2.3 When both series visible, use `.position(by: .value("Series", seriesName))` to group bars side-by-side (not stacked)
  - [x] 2.4 Conditional rendering based on `fiveHourVisible` / `sevenDayVisible` flags

- [x] Task 3: Configure axes per time range (AC: 1, 2, 3)
  - [x] 3.1 Y-axis: `.chartYScale(domain: 0...100)` with `AxisMarks` at 0, 25, 50, 75, 100 showing "0%"..."100%" (same as StepAreaChartView)
  - [x] 3.2 X-axis for `.week`: time-based `AxisMarks` showing day-of-week + hour (e.g., "Mon 8AM"), ~6-8 labels
  - [x] 3.3 X-axis for `.month`: date-based labels (e.g., "Jan 15"), ~6-8 labels
  - [x] 3.4 X-axis for `.all`: date-based labels with appropriate spacing for potentially 365+ bars
  - [x] 3.5 Use `.chartLegend(.hidden)` -- legend is handled by AnalyticsView toggle buttons (Story 13.5 pattern)

- [x] Task 4: Render reset event indicators (AC: 1)
  - [x] 4.1 For each `BarPoint` where `resetCount > 0`, render a small `PointMark` or `RuleMark` below the bar at y=0 to indicate a reset occurred in that period
  - [x] 4.2 Use a subtle orange indicator (matching `StepAreaChartView` reset line color: `Color.orange.opacity(0.5)`)
  - [x] 4.3 Reset indicators should be unobtrusive -- small triangles or dots at the baseline

- [x] Task 5: Implement hover tooltip (AC: 4)
  - [x] 5.1 Follow the same `.chartOverlay` + `GeometryReader` + `onContinuousHover` pattern from `StepAreaChartView`
  - [x] 5.2 Separate static chart content from hover overlay (same architecture as `ChartWithHoverOverlay` / `StaticChartContent` / `HoverOverlayContent` in `StepAreaChartView.swift`) to prevent chart re-evaluation on hover
  - [x] 5.3 Find nearest bar by X-coordinate, display tooltip showing: period range (e.g., "Mon 2PM - 3PM"), min/avg/peak utilization for both visible series
  - [x] 5.4 Show vertical hover line at bar position
  - [x] 5.5 Tooltip follows cursor horizontally, flips side near edge (same `tooltipXPosition` logic as StepAreaChartView)
  - [x] 5.6 Tooltip uses `.ultraThinMaterial` background with rounded rectangle (same style as StepAreaChartView tooltip)

- [x] Task 6: Wire into UsageChart (AC: all)
  - [x] 6.1 In `UsageChart.swift`, replace the `dataSummary` stub in the `else` branch (line 56) with `BarChartView` for non-`.day` ranges
  - [x] 6.2 Pass `rollupData`, `fiveHourVisible`, `sevenDayVisible`, `timeRange` to `BarChartView`
  - [x] 6.3 Preserve all existing states: loading, no-series, empty-data (both variants)
  - [x] 6.4 Verify series toggle changes work without data reload (visual-only, not `.task(id:)` trigger)

- [x] Task 7: Add tests (AC: all)
  - [x] 7.1 Test: `.week` time range with rollup data renders bar chart (body evaluates without crash)
  - [x] 7.2 Test: `.month` time range with rollup data renders bar chart
  - [x] 7.3 Test: `.all` time range with rollup data renders bar chart
  - [x] 7.4 Test: bar point creation from rollup data -- verify peak values, date conversion, reset count
  - [x] 7.5 Test: 5h-only visibility hides 7d bars
  - [x] 7.6 Test: 7d-only visibility hides 5h bars
  - [x] 7.7 Test: empty rollup data with non-.day range shows empty state
  - [x] 7.8 Test: rollup data with reset events flags correct bars
  - [x] 7.9 Update `UsageChartTests` to verify the stub replacement -- non-.day range with data no longer shows `dataSummary`

- [x] Task 8: Build verification (AC: all)
  - [x] 8.1 Run `xcodegen generate`
  - [x] 8.2 Run `xcodebuild -scheme cc-hdrm -destination 'platform=macOS' build`
  - [x] 8.3 Run full test suite -- all existing + new tests pass
  - [x] 8.4 Manual: Open analytics on 7d view with real data -- verify bar chart with hourly bars
  - [x] 8.5 Manual: Switch to 30d -- verify daily bars
  - [x] 8.6 Manual: Hover over bar -- verify tooltip shows period range, min/avg/peak
  - [x] 8.7 Manual: Toggle 5h off -- verify only 7d bars; toggle 7d off -- verify empty state
  - [x] 8.8 Manual: Verify reset indicators appear below bars where resets occurred

> **Note:** Tasks 8.4-8.8 require human manual verification.

## Dev Notes

### CRITICAL: Replace dataSummary Stub with Bar Chart

`cc-hdrm/Views/UsageChart.swift:90-102` contains a `dataSummary` stub view created by Story 13.2 that just shows a data point count. This story replaces it with a real bar chart for `.week`, `.month`, and `.all` time ranges. The step-area chart (`.day`) was implemented by Story 13.5 and remains unchanged.

### Framework: Swift Charts BarMark

Use Apple's **Swift Charts** `BarMark` -- the same framework already imported in `StepAreaChartView.swift`. Key APIs:

```swift
BarMark(
    x: .value("Period", midpointDate),
    y: .value("Peak", peak),
    width: .ratio(0.8)  // 80% of available width per bar
)
.foregroundStyle(Color.headroomNormal)
.position(by: .value("Series", "5h"))  // For grouped bars when both series visible
```

**Do NOT use Canvas.** Swift Charts handles axes, grouping, and tooltips natively.
**Do NOT add any external dependency.** Swift Charts ships with Xcode/macOS 14+.

### Data Source: UsageRollup

For non-`.day` ranges, `AnalyticsView.swift:165-167` loads rollup data via `service.getRolledUpData(range:)` and clears `chartData`. The `UsageChart` receives `rollupData: [UsageRollup]`.

```swift
// cc-hdrm/Models/UsageRollup.swift
struct UsageRollup: Sendable, Equatable {
    let id: Int64
    let periodStart: Int64          // Unix ms (inclusive)
    let periodEnd: Int64            // Unix ms (exclusive)
    let resolution: Resolution      // .fiveMin, .hourly, .daily
    let fiveHourAvg: Double?        // 0-100
    let fiveHourPeak: Double?       // 0-100 -- THIS is what bar height uses
    let fiveHourMin: Double?        // 0-100
    let sevenDayAvg: Double?
    let sevenDayPeak: Double?
    let sevenDayMin: Double?
    let resetCount: Int             // Number of resets in this period
    let wasteCredits: Double?       // Daily resolution only
}
```

Convert `periodStart` (Int64 ms) to `Date`: `Date(timeIntervalSince1970: Double(periodStart) / 1000.0)`.

For bar X-position, use the midpoint of the period: `(periodStart + periodEnd) / 2` converted to Date.

### Resolution Mapping by Time Range

| TimeRange | Resolution in rollupData | Bar represents |
|-----------|-------------------------|----------------|
| `.week`   | `.fiveMin` (raw<24h) + `.fiveMin` (1-7d) | 1 hour |
| `.month`  | `.fiveMin` + `.hourly` (7-30d) | 1 day |
| `.all`    | `.fiveMin` + `.hourly` + `.daily` (30d+) | 1 day |

**IMPORTANT:** The rollup data comes pre-stitched from `HistoricalDataService.getRolledUpData(range:)`. For `.week`, individual 5-minute rollups need to be aggregated into hourly bars. For `.month`, hourly rollups may need to be aggregated into daily bars if the query returns mixed resolutions.

**Aggregation approach:** Group rollups by the target period (hour for `.week`, day for `.month`/`.all`), then take `max(fiveHourPeak)` for bar height, `min(fiveHourMin)` for min, `average(fiveHourAvg)` weighted by period duration for avg, and `sum(resetCount)` for reset indicators.

### Performance Architecture: Separate Static and Hover Views

Follow the exact same pattern from `StepAreaChartView.swift:339-622`:

1. **`BarChartView`** -- outer view, pre-computes `barPoints` in `init`
2. **`BarChartWithHoverOverlay`** (private) -- manages `@State hoveredIndex`, renders static chart + overlay
3. **`StaticBarChartContent`** (private) -- the actual `Chart { }` with `BarMark`s, does NOT depend on hover state
4. **`BarHoverOverlayContent`** (private) -- the tooltip/hover line, only this redraws on hover

This prevents the 100% CPU issue that was fixed in Story 13.5 (see completion note: "Resolved 100% CPU on hover").

### Series Colors

Reuse existing constants:
- **5h series**: `Color.headroomNormal` (green, from Asset Catalog)
- **7d series**: `StepAreaChartView.sevenDayColor` (blue) -- defined at `StepAreaChartView.swift:25`

### Y-Axis and Grid Styling

Match `StepAreaChartView`'s axis styling exactly (lines 504-524):
- `.chartYScale(domain: 0...100)`
- `AxisMarks` at 0, 25, 50, 75, 100
- Grid line: `StrokeStyle(lineWidth: 0.5)`, `.secondary.opacity(0.3)`
- `.chartLegend(.hidden)`

### Existing States to Preserve in UsageChart

These branches in `UsageChart.swift:41-57` MUST continue working:
1. `isLoading == true` -> `ProgressView()`
2. `!anySeriesVisible` -> "Select a series to display"
3. `dataPointCount == 0 && !hasAnyHistoricalData` -> "No data yet"
4. `dataPointCount == 0 && hasAnyHistoricalData` -> "No data for this time range"
5. `timeRange == .day` -> `StepAreaChartView` (Story 13.5, unchanged)

Add the bar chart as the new `else` branch replacing `dataSummary`:
```swift
} else if timeRange == .day {
    StepAreaChartView(...)
} else {
    BarChartView(
        rollups: rollupData,
        timeRange: timeRange,
        fiveHourVisible: fiveHourVisible,
        sevenDayVisible: sevenDayVisible
    )
}
```

### Tooltip Content for Bars

Unlike the step-area tooltip (single point: timestamp + utilization + slope), bar tooltips show period aggregates:

```
Mon 2:00 PM - 3:00 PM          <-- period range
  5h: Peak 67.2% | Avg 42.1%   <-- if 5h visible
  7d: Peak 31.5% | Avg 28.0%   <-- if 7d visible
  Min: 12.3%                    <-- lowest point in period
  1 reset                       <-- if resetCount > 0
```

Date formatting for period range:
- `.week` (hourly bars): "Mon 2 PM - 3 PM"
- `.month` / `.all` (daily bars): "Jan 15" or "Mon, Jan 15"

### Gap Rendering is Story 13.7

This story does NOT implement explicit gap rendering for bars. If a period has no data, there will simply be no bar for that period (natural gap). Story 13.7 adds explicit "No data" hover labels and visual gap indicators. For now, missing bars are sufficient.

### Project Structure Notes

**New file:**
```text
cc-hdrm/Views/BarChartView.swift       # Bar chart for 7d/30d/All time ranges
```

**Modified files:**
```text
cc-hdrm/Views/UsageChart.swift          # Replace dataSummary stub with BarChartView
cc-hdrmTests/Views/UsageChartTests.swift # Add bar chart tests
```

**After any file changes, run:**
```bash
xcodegen generate
```

### Previous Story Intelligence

**From Story 13.5 (step-area-mode):**
- Created `StepAreaChartView` with performance-critical architecture: static chart + hover overlay separation to prevent 100% CPU on hover. **REPLICATE THIS PATTERN.**
- `StepAreaChartView.sevenDayColor = Color.blue` -- reuse this for 7d bar color
- Tooltip uses `.ultraThinMaterial` background, follows cursor with flip logic at edges
- `ChartPoint` pre-computed in `init` -- do the same for `BarPoint`
- 764 tests pass at Story 13.5 completion (71 suites)
- Post-review fixes: removed slope bands (readability), changed 7d color from `.secondary` to blue (dark mode visibility), moved computed properties to `init` (CPU fix)

**From Story 13.4 (series-toggle-controls):**
- `SeriesVisibility` struct stores per-time-range toggle state in `AnalyticsView`
- Toggle changes do NOT trigger `.task(id:)` data reload -- visual only
- Panel is nil'd on `windowWillClose` to reset `@State` on next open

**From Story 13.2 (analytics-view-layout):**
- `UsageChart` interface: `pollData`, `rollupData`, `timeRange`, `fiveHourVisible`, `sevenDayVisible`, `isLoading`, `hasAnyHistoricalData`
- `dataSummary` is the stub this story replaces

### Git Intelligence

Last 5 commits:
- `37c2ee3` -- merge branch 'master'
- `1dc8a35` -- feat: step-area chart for 24h analytics view (Story 13.5)
- `cf58f0a` -- merge branch 'master'
- `19a1535` -- feat: per-time-range series toggle persistence (Story 13.4)
- `42ecb1d` -- resolve merge conflict: keep 13.3 done status

### Edge Cases

| No. | Condition | Expected Behavior |
|-----|-----------|-------------------|
| 1 | Rollup has nil fiveHourPeak | No 5h bar for that period; 7d bar unaffected |
| 2 | Rollup has nil sevenDayPeak | No 7d bar for that period; 5h bar unaffected |
| 3 | Only 1 rollup in data | Single bar displayed |
| 4 | Mixed resolutions in rollupData | Group by target period, aggregate correctly |
| 5 | Very sparse data (few bars across range) | Bars display at correct positions, gaps are natural |
| 6 | Very dense data (365+ bars for "All") | Chart handles via Swift Charts auto-scaling; bar width adjusts |
| 7 | Both series visible | Bars grouped side-by-side via `.position(by:)` |
| 8 | Switching from 24h (step-area) to 7d (bar) and back | Correct chart type renders from cached data |
| 9 | Window resize | Chart expands/contracts with `.frame(maxWidth: .infinity, maxHeight: .infinity)` |
| 10 | Reset count > 1 in a period | Single indicator with count shown in tooltip |

### References

- [Source: _bmad-output/planning-artifacts/epics.md:1563-1593] -- Story 13.6 acceptance criteria
- [Source: _bmad-output/planning-artifacts/ux-design-specification-phase3.md:291-310] -- Chart hybrid visualization spec (bar mode for 7d+)
- [Source: _bmad-output/planning-artifacts/ux-design-specification-phase3.md:502-519] -- UsageChart component detail
- [Source: cc-hdrm/Views/UsageChart.swift:90-102] -- dataSummary stub to replace
- [Source: cc-hdrm/Views/UsageChart.swift:49-57] -- Branching logic for chart type
- [Source: cc-hdrm/Views/StepAreaChartView.swift:339-622] -- Performance architecture to replicate (static/hover split)
- [Source: cc-hdrm/Views/StepAreaChartView.swift:25] -- sevenDayColor constant to reuse
- [Source: cc-hdrm/Views/AnalyticsView.swift:161-168] -- Data loading by time range (rollupData path)
- [Source: cc-hdrm/Models/UsageRollup.swift] -- Rollup data model with peak/avg/min fields
- [Source: cc-hdrm/Models/TimeRange.swift] -- TimeRange enum
- [Source: cc-hdrmTests/Views/UsageChartTests.swift] -- Existing tests (38 tests)
- [Source: _bmad-output/implementation-artifacts/13-5-usage-chart-step-area-mode.md] -- Previous story (performance lessons, color choices, architecture)

## Dev Agent Record

### Agent Model Used

Claude claude-opus-4-6 (anthropic/claude-opus-4-6)

### Debug Log References

None required — clean build and test run.

### Implementation Plan

- Created `BarChartView.swift` with 4-layer architecture mirroring StepAreaChartView: outer view (pre-computes BarPoints in init), BarChartWithHoverOverlay (manages @State hoveredIndex), StaticBarChartContent (Chart marks, never re-evaluates on hover), BarHoverOverlayContent (tooltip/hover line, lightweight redraw).
- Aggregation logic groups rollups by Calendar hour (.week) or day (.month/.all), computing max for peak, min for min, simple average for avg, sum for resetCount.
- Replaced dataSummary stub in UsageChart.swift with BarChartView for non-.day ranges. Removed unused dataSummary computed property.
- Reset indicators rendered as PointMark at y=0 with orange opacity matching StepAreaChartView reset line color.
- Tooltip shows period range (hourly for .week, daily for .month/.all), per-series peak/avg, min across visible series, and reset count.

### Completion Notes List

- All 8 tasks completed including manual verification (8.4-8.8)
- 779 tests pass across 71 suites (15 new tests added, up from 764)
- New tests cover: bar chart rendering for all 3 non-.day time ranges, bar point creation with aggregation verification, visibility toggling, empty state, reset event flagging, stub replacement validation, nil value handling, single rollup, monthly aggregation
- Performance architecture replicated from StepAreaChartView — static chart content separated from hover overlay to prevent chart re-evaluation on hover
- Series colors reuse existing constants: Color.headroomNormal (5h) and StepAreaChartView.sevenDayColor (7d)
- All existing states preserved: loading, no-series, empty-data (both variants), .day step-area chart

#### Bug: BarMark invisible on temporal Date x-axis (discovered during manual test 8.4)

`BarMark(x: .value("Period", date), y: .value("Peak", peak), width: .ratio(0.8))` renders zero-width bars on a continuous Date x-axis. Swift Charts cannot determine bin boundaries for temporal data, so `.ratio()` computes no meaningful width. Hover tooltip worked (ChartProxy resolves dates independently of mark rendering), confirming bar points existed but bars were invisible.

**Fix:** Replaced `BarMark` with `RectangleMark(xStart:xEnd:yStart:yEnd:)` for explicit temporal boundaries. Added `barBounds(for:series:)` helper that computes x-axis start/end dates with 5% outer padding. For grouped mode (both series visible), the period is split in half with a 4% inner gap between 5h (left) and 7d (right) bars.

#### Pre-existing bugs fixed during manual testing

**1. AnalyticsPanel double-click to activate buttons (pre-existing from Story 13.1)**

`AnalyticsPanel` uses `.nonactivatingPanel` style mask (so it doesn't steal focus from other apps on open). By default, non-activating panels return `false` for `canBecomeKey`, which means the first click merely focuses the panel — the second click triggers the button action.

**Fix:** `override var canBecomeKey: Bool { true }` in `AnalyticsPanel.swift`. The panel still opens via `orderFront` (not `makeKeyAndOrderFront`), so it won't steal focus from other apps on open — but once the user clicks inside, it becomes key and processes the click immediately.

**2. Series toggle dead area between dot and label (pre-existing from Story 13.4)**

The `seriesToggleButton` in `AnalyticsView` uses an `HStack(spacing: 4)` with a Circle and Text inside a Button with `.buttonStyle(.plain)`. Plain button style only registers clicks on rendered content, not on the 4pt spacing gap between the dot and label.

**Fix:** Added `.contentShape(Rectangle())` to the HStack to expand the hit area across the full button frame.

**3. Focus rings on sparkline, gear button, and close button (pre-existing)**

After clicking the sparkline (now a Button) or gear menu, a focus ring appeared. The focus ring also stole the hand cursor from the sparkline.

**Fix:** Added `.focusEffectDisabled()` to the sparkline button, gear menu, series toggle buttons, and analytics close button.

**4. Sparkline click and hand cursor in NSPopover context (pre-existing from Story 12.1)**

Multiple interrelated issues with the sparkline in an NSPopover:

- **Double-click required:** `.onTapGesture` on a Canvas inside an NSPopover required the popover window to become key first, consuming the first click.
- **Hand cursor disappearing forever:** `NSCursor.push()`/`pop()` cursor stack corrupted when the analytics window opened (key-window change resets the stack). After corruption, subsequent push/pop calls were permanently out of sync.
- **`NSCursor.set()` overridden:** `set()` is immediately overridden by AppKit's cursor rect system on the next mouse move, so the hand cursor would disappear as soon as the mouse moved even slightly.
- **`addCursorRect` requires key window:** Cursor rectangles are only active for the key window (`NSWindow` documentation: "Cursor rectangles are active only for the key window"). The popover window isn't always key.
- **Background NSView tracking areas don't fire:** An `NSTrackingArea` on a background NSView doesn't receive `mouseEnteredAndExited` events when a SwiftUI hosting view is on top.
- **Overlay NSView blocks clicks:** An overlay NSView that wins `hitTest` (required for `addCursorRect`) intercepts mouse events intended for the SwiftUI button underneath. Returning `nil` from `hitTest` fixes clicks but breaks `addCursorRect` (which uses `hitTest` to resolve the owning view).
- **First mouse consumed by window activation:** Even with the overlay handling clicks via `mouseUp`, the first click was consumed by AppKit to make the popover window key.

**Final solution:** Replaced the SwiftUI `Button` entirely with a single AppKit `NSView` overlay (`SparklineInteractionOverlay`) that handles cursor, click, and hover in one unified place:

1. **Cursor (key window):** `addCursorRect(bounds, cursor: .pointingHand)` in `resetCursorRects()` — managed by the window server, works when popover is key.
2. **Cursor (non-key window):** `NSTrackingArea` with `.mouseEnteredAndExited` + `.activeAlways` calls `NSCursor.pointingHand.set()` in `mouseEntered` — works when popover is NOT key because there's no cursor rect system active to override `set()`.
3. **Window activation:** `window?.makeKey()` in `viewDidMoveToWindow()` — makes the popover window key immediately when it opens, so `addCursorRect` works from the first hover.
4. **Click:** `mouseUp(with:)` calls the `onTap` closure directly — no SwiftUI Button, no focus ring, no first-responder issues.
5. **First mouse:** `acceptsFirstMouse(for:)` returns `true` — delivers the click immediately instead of consuming it for window activation.
6. **Hover highlight:** `mouseEntered`/`mouseExited` from the tracking area calls `onHoverChange` for the background color effect.

Key insight: `addCursorRect` and `NSCursor.set()` are complementary — `addCursorRect` works only in key windows, `set()` works only in non-key windows (because the cursor rect system isn't active to override it). Using both together covers all window states.

### Senior Developer Review (AI)

**Reviewer:** Amelia (claude-opus-4-6) | **Date:** 2026-02-07

**Outcome:** Approved with fixes applied

**AC Validation:** All 4 ACs fully implemented and verified against code.

**Task Audit:** All 8 tasks (31 subtasks) marked [x] confirmed implemented. 779 tests pass (71 suites, 15 new).

**Fixes applied during review (7 issues: 0 HIGH, 3 MEDIUM, 4 LOW):**
- M1: `DateFormatter` allocated per hover frame in `BarHoverOverlayContent.periodRangeText()` — moved to `static let` cached formatters
- M2: Stale test comments in `UsageChartTests.swift` still referenced "stub" — updated to "bar chart"
- M3: `sprint-status.yaml` modified but missing from story File List — added
- L1: Unused `logger` in `BarChartView` — removed (along with `import os`)
- L2: Stale docstring in `UsageChart.swift` still mentioned stub — updated
- L3: Extra blank line artifact from `dataSummary` removal — cleaned
- L4: `BarPoint.id` was index-based (fragile on data reload) — changed to `Int(periodStart.timeIntervalSince1970)` for stable identity

**Pre-existing bug fixes (out of scope but well-documented):** 4 fixes to AnalyticsPanel, AnalyticsView, GearMenuView, Sparkline. All appropriately documented in Dev Agent Record with root cause analysis. No concerns — quality improvements.

**Build:** Passes. **Tests:** 779/779 pass (71 suites).

### Change Log

- 2026-02-07: Code review passed — 7 fixes applied (DateFormatter caching, stable BarPoint.id, stale comments/docs, File List)
- 2026-02-07: Story 13.6 implementation complete — bar chart for 7d/30d/All time ranges
- 2026-02-07: Fixed invisible BarMark — replaced with RectangleMark for explicit temporal boundaries
- 2026-02-07: Fixed AnalyticsPanel double-click (canBecomeKey override)
- 2026-02-07: Fixed series toggle dead area (contentShape), focus rings (focusEffectDisabled)
- 2026-02-07: Fixed sparkline click/cursor — replaced SwiftUI Button with AppKit SparklineInteractionOverlay

### File List

**New files:**
- cc-hdrm/Views/BarChartView.swift

**Modified files:**
- cc-hdrm/Views/UsageChart.swift — replaced dataSummary stub with BarChartView
- cc-hdrm/Views/BarChartView.swift — RectangleMark fix for temporal bar rendering
- cc-hdrm/Views/AnalyticsPanel.swift — canBecomeKey override for single-click activation
- cc-hdrm/Views/AnalyticsView.swift — contentShape on toggle buttons, focusEffectDisabled on close button and toggles
- cc-hdrm/Views/Sparkline.swift — SparklineInteractionOverlay replacing SwiftUI Button for reliable cursor and click
- cc-hdrm/Views/GearMenuView.swift — focusEffectDisabled on gear menu
- cc-hdrmTests/Views/UsageChartTests.swift — 15 new bar chart tests
- _bmad-output/implementation-artifacts/sprint-status.yaml — story status updated to review
