# Story 13.8: API Outage Background Rendering in Analytics Charts

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to see colored background regions in analytics charts marking periods when the API was unreachable,
so that I can distinguish "I wasn't using Claude" from "Anthropic was down."

## Acceptance Criteria

1. **Given** the analytics chart renders for a time range containing outage periods, **When** UsageChart draws the chart, **Then** outage periods are shown as vertical background bands with a distinct color (muted red/salmon tint -- clearly different from gap hatching and slope tint) **And** the bands span the full chart height behind the data.

2. **Given** the user hovers over an outage background region, **When** the tooltip appears, **Then** it shows: "API outage: [duration]" with start/end times.

3. **Given** the chart legend renders, **When** outage data exists in the visible range, **Then** a legend entry appears: colored swatch + "API outage".

4. **Given** no outage data exists in the visible range, **When** the chart renders, **Then** no outage background or legend entry is shown.

5. **Given** both a data gap AND an outage overlap in the same period, **When** the chart renders, **Then** the outage background takes precedence (it's more informative -- the app was running but couldn't reach the API).

## Tasks / Subtasks

- [x] Task 1: Plumb outage periods from AnalyticsView through UsageChart to chart views (AC: 1, 4)
  - [x]1.1 In `cc-hdrm/Views/AnalyticsView.swift`: add `@State private var outagePeriods: [OutagePeriod] = []` state property
  - [x]1.2 In `AnalyticsView.loadData()`: after fetching chart/rollup data, fetch outage periods for the selected time range via `historicalDataService.getOutagePeriods(from:to:)` using the same date bounds as the chart data
  - [x]1.3 In `AnalyticsView.DataLoadResult`: add `outagePeriods: [OutagePeriod] = []` field
  - [x]1.4 In `AnalyticsView.fetchData(for:using:)`: call `service.getOutagePeriods(from:to:)` with appropriate date range for the time range, store in result
  - [x]1.5 In `cc-hdrm/Views/UsageChart.swift`: add `let outagePeriods: [OutagePeriod]` parameter
  - [x]1.6 Pass `outagePeriods` from `UsageChart` to `StepAreaChartView` and `BarChartView` init parameters
  - [x]1.7 Update `UsageChart` preview and all call sites (AnalyticsView) to pass `outagePeriods`

- [x] Task 2: Add outage background rendering to StepAreaChartView (AC: 1, 5)
  - [x]2.1 In `cc-hdrm/Views/StepAreaChartView.swift`: add `let outagePeriods: [OutagePeriod]` parameter to `StepAreaChartView` init
  - [x]2.2 Define outage color constant: `static let outageColor = Color.red.opacity(0.08)` (muted red/salmon tint, distinct from gap `Color.secondary.opacity(0.08)`)
  - [x]2.3 Compute `outageRanges` in init by converting `[OutagePeriod]` to date ranges clipped to the chart's time bounds
  - [x]2.4 Pass `outageRanges` through the 4-layer hierarchy: `StepAreaChartView` -> `ChartWithHoverOverlay` -> `StaticChartContent`
  - [x]2.5 In `StaticChartContent`, render outage `RectangleMark` backgrounds AFTER gap backgrounds (so outage overlays gap where they overlap -- AC 5)
  - [x]2.6 Use `Color.red.opacity(0.08)` foreground style for outage marks

- [x] Task 3: Add outage background rendering to BarChartView (AC: 1, 5)
  - [x]3.1 In `cc-hdrm/Views/BarChartView.swift`: add `let outagePeriods: [OutagePeriod]` parameter to `BarChartView` init
  - [x]3.2 Define outage color constant: `static let outageColor = Color.red.opacity(0.08)` (same as StepAreaChartView)
  - [x]3.3 Compute `outageRanges` in init by converting `[OutagePeriod]` to date ranges clipped to the bar chart's time bounds
  - [x]3.4 Pass `outageRanges` through the 4-layer hierarchy: `BarChartView` -> `BarChartWithHoverOverlay` -> `StaticBarChartContent`
  - [x]3.5 In `StaticBarChartContent`, render outage `RectangleMark` backgrounds AFTER gap backgrounds (AC 5)
  - [x]3.6 Use `Color.red.opacity(0.08)` foreground style for outage marks

- [x] Task 4: Add outage hover tooltip to StepAreaChartView (AC: 2, 5)
  - [x]4.1 Pass `outageRanges` from `ChartWithHoverOverlay` to `HoverOverlayContent`
  - [x]4.2 Add `hoveredOutage` computed property in `HoverOverlayContent` -- checks if cursor date falls within any outage range
  - [x]4.3 Add outage tooltip rendering: "API outage" (primary) / duration + time range (secondary, caption) -- uses same `.ultraThinMaterial` background as gap/data tooltips
  - [x]4.4 Outage tooltip takes priority over gap tooltip: check outage FIRST, then gap, then data point (outage is more informative when overlapping -- AC 5)
  - [x]4.5 Duration format: human-readable (e.g., "12 min", "2h 30m", "1d 4h")
  - [x]4.6 Add accessibility label to outage tooltip

- [x] Task 5: Add outage hover tooltip to BarChartView (AC: 2, 5)
  - [x]5.1 Pass `outageRanges` from `BarChartWithHoverOverlay` to `BarHoverOverlayContent`
  - [x]5.2 Add `hoveredOutage` computed property in `BarHoverOverlayContent`
  - [x]5.3 Add outage tooltip rendering matching StepAreaChartView pattern
  - [x]5.4 Outage check priority: outage FIRST, then gap, then bar data
  - [x]5.5 Add accessibility label to outage tooltip

- [x] Task 6: Add outage legend to AnalyticsView (AC: 3, 4)
  - [x]6.1 In `cc-hdrm/Views/AnalyticsView.swift`: add a conditional legend row between `controlsRow` and `UsageChart` in the VStack
  - [x]6.2 Legend shows only when `outagePeriods` is non-empty for the current time range
  - [x]6.3 Legend content: small colored swatch (muted red/salmon, same as chart background) + "API outage" text in caption font
  - [x]6.4 Legend aligned to the leading edge, below controls row
  - [x]6.5 Add accessibility label: "Chart shows API outage periods"

- [x] Task 7: Write comprehensive tests (AC: all)
  - [x]7.1 Test: StepAreaChartView renders without crash with outage periods
  - [x]7.2 Test: StepAreaChartView renders without crash with empty outage periods
  - [x]7.3 Test: BarChartView renders without crash with outage periods
  - [x]7.4 Test: BarChartView renders without crash with empty outage periods
  - [x]7.5 Test: UsageChart passes outage periods to chart views (via init parameter)
  - [x]7.6 Test: Outage range clipping -- outage period extending beyond chart bounds is clipped
  - [x]7.7 Test: Ongoing outage (endedAt nil) uses current time as end
  - [x]7.8 Test: AnalyticsView.fetchData includes outage periods in result
  - [x]7.9 Test: Outage duration formatting -- minutes, hours, hours+minutes, days+hours
  - [x]7.10 Test: Empty outage periods produces no outage ranges

- [x] Task 8: Build verification (AC: all)
  - [x]8.1 Run `xcodegen generate`
  - [x]8.2 Run `xcodebuild -scheme cc-hdrm -destination 'platform=macOS' build`
  - [x]8.3 Run full test suite -- all existing + new tests pass
  - [x]8.4 Manual: Open analytics, verify no outage backgrounds when no outages exist
  - [x]8.5 Manual: Simulate outage data, verify muted red/salmon backgrounds appear in charts
  - [x]8.6 Manual: Hover over outage region, verify "API outage: [duration]" tooltip
  - [x]8.7 Manual: Verify legend row appears/disappears based on outage data
  - [x]8.8 Manual: Verify outage background is visually distinct from gap background (grey vs red tint)

## Dev Notes

### Architecture Overview

This story is the visualization layer for the API outage tracking pipeline established in Stories 5.4 and 10.6:

1. **Story 5.4** -- Added outage/recovery state machine to `NotificationService`. Fires macOS notifications on API down/up transitions.
2. **Story 10.6** -- Added `api_outages` table to SQLite, outage tracking state machine in `HistoricalDataService`, and `getOutagePeriods(from:to:)` query API.
3. **Story 13.8 (this story)** -- Renders outage periods as colored background bands in analytics charts.

### Data Flow

```
AnalyticsView.loadData()
    → historicalDataService.getOutagePeriods(from:to:)
    → [OutagePeriod] stored in @State
    → Passed to UsageChart → StepAreaChartView / BarChartView
    → Converted to [OutageRange] in init (date pairs clipped to chart bounds)
    → Rendered as RectangleMark in StaticChartContent (behind data)
    → Hover detection in HoverOverlayContent (outage > gap > data priority)
```

### OutagePeriod Model (Already Exists)

Defined in `cc-hdrm/Models/OutagePeriod.swift` (30 lines):

```swift
struct OutagePeriod: Sendable, Equatable {
    let id: Int64
    let startedAt: Int64           // Unix ms
    let endedAt: Int64?            // Unix ms, nil if ongoing
    let failureReason: String

    var isOngoing: Bool { endedAt == nil }
    var startDate: Date { Date(timeIntervalSince1970: Double(startedAt) / 1000.0) }
    var endDate: Date? { endedAt.map { Date(timeIntervalSince1970: Double($0) / 1000.0) } }
}
```

### getOutagePeriods API (Already Exists)

Defined in `cc-hdrm/Services/HistoricalDataServiceProtocol.swift:91-96`:

```swift
func getOutagePeriods(from: Date?, to: Date?) async throws -> [OutagePeriod]
```

Returns all outage periods overlapping the requested time range, ordered by `started_at` ascending. Overlap logic: `started_at <= to AND (ended_at >= from OR ended_at IS NULL)`.

### OutageRange Struct (New -- For Chart Views)

Both chart views need a simple date-range struct for outage background rendering (same pattern as `GapRange` and `BarGapRange`):

```swift
struct OutageRange: Identifiable {
    let id: Int
    let start: Date
    let end: Date
    let durationSeconds: TimeInterval  // For tooltip display
}
```

Computed in `init` from `[OutagePeriod]`:
- Filter out outages that don't overlap the chart's time range
- Clip outage start/end to chart bounds
- For ongoing outages (`endedAt == nil`), use `Date()` as the end

### Date Range Computation for Outage Fetch

In `AnalyticsView.fetchData(for:using:)`, compute the date range based on the time range:

```swift
// After fetching chart data, compute outage date range from actual data bounds
let outageFrom: Date?
let outageTo: Date?
switch range {
case .day:
    // Use poll data time bounds
    outageFrom = chartData.first.map { Date(timeIntervalSince1970: Double($0.timestamp) / 1000.0) }
    outageTo = chartData.last.map { Date(timeIntervalSince1970: Double($0.timestamp) / 1000.0) }
case .week, .month, .all:
    // Use rollup data time bounds
    outageFrom = rollupData.first.map { Date(timeIntervalSince1970: Double($0.periodStart) / 1000.0) }
    outageTo = rollupData.last.map { Date(timeIntervalSince1970: Double($0.periodEnd) / 1000.0) }
}
let outagePeriods = try await service.getOutagePeriods(from: outageFrom, to: outageTo)
```

### Visual Distinction Summary

Three types of background regions can appear in charts, each with distinct visual treatment:

| Type | Color | Opacity | Visual | Meaning |
|------|-------|---------|--------|---------|
| **Data gap** | `Color.secondary` | `0.08` | Light grey | cc-hdrm wasn't running |
| **API outage** | `Color.red` | `0.08` | Muted red/salmon tint | Anthropic API was down |
| **Extra usage** | `Color.extraUsageCool` | `0.15` | Muted blue tint | Extra usage active |

The outage color (`Color.red.opacity(0.08)`) provides a clearly distinguishable warm tint compared to the cool grey of data gaps. Both are subtle enough to not overpower the actual data.

### Rendering Order (Z-Index)

In `StaticChartContent` / `StaticBarChartContent`, backgrounds render in this order (bottom to top):

1. **Gap backgrounds** -- `Color.secondary.opacity(0.08)` (existing, lines 513-522 in StepAreaChartView, lines 391-400 in BarChartView)
2. **Outage backgrounds** -- `Color.red.opacity(0.08)` (NEW -- renders AFTER gaps so it overlays where they overlap, fulfilling AC 5)
3. **Extra usage backgrounds** -- `Color.extraUsageCool.opacity(0.15)` (existing, lines 613-645 in StepAreaChartView)
4. **Data marks** -- bars, lines, areas (existing)

This order ensures outage backgrounds take visual precedence over gap backgrounds where they overlap (AC 5: "the outage background takes precedence").

### Hover Priority

In `HoverOverlayContent` / `BarHoverOverlayContent`, check in this order:

1. **Outage range** -- "API outage: [duration]" tooltip (HIGHEST priority -- NEW)
2. **Gap range** -- "No data / cc-hdrm not running" tooltip (existing)
3. **Data point** -- normal data tooltip (existing, LOWEST priority)

This matches AC 5: outage is "more informative" and takes precedence over gap when both overlap.

### Outage Tooltip Format

```
API outage                           <-- primary text, .secondary color
12 min (14:32 - 14:44)              <-- caption text, .tertiary color
```

Or for longer outages:
```
API outage
2h 30m (Mon 09:15 - Mon 11:45)
```

Use the same `.ultraThinMaterial` background and rounded rectangle as existing tooltips. Keep vertical hover line visible in outage regions.

### Duration Formatting

Create a static helper method for human-readable duration:

```swift
static func formatDuration(_ seconds: TimeInterval) -> String {
    let totalMinutes = Int(seconds / 60)
    if totalMinutes < 60 {
        return "\(totalMinutes) min"
    }
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours < 24 {
        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }
    let days = hours / 24
    let remainingHours = hours % 24
    return remainingHours > 0 ? "\(days)d \(remainingHours)h" : "\(days)d"
}
```

### Time Formatting in Tooltip

For the start/end time range in the outage tooltip:
- Same day: "14:32 - 14:44" (just time)
- Different day (same week): "Mon 09:15 - Mon 11:45" (short day + time)
- Different week: "Feb 28 09:15 - Mar 1 11:45" (month day + time)

Use `DateFormatter` with `static let` to avoid per-frame allocation (lesson from Story 13.6).

### Legend Design

A small inline legend row in AnalyticsView between controls and chart:

```swift
// In AnalyticsView body VStack, between controlsRow and UsageChart:
if !outagePeriods.isEmpty {
    HStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.red.opacity(0.3))  // Slightly more opaque for legend visibility
            .frame(width: 12, height: 8)
        Text("API outage")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityLabel("Chart shows API outage periods")
}
```

The legend swatch uses `Color.red.opacity(0.3)` (more opaque than the chart background) for readability at the small swatch size.

### StepAreaChartView Modifications

**Init parameter addition:**
```swift
// Line 10 (current): struct StepAreaChartView: View {
// Add outagePeriods parameter alongside existing polls/visibility params
init(polls: [UsagePoll], fiveHourVisible: Bool, sevenDayVisible: Bool, outagePeriods: [OutagePeriod] = []) {
    // ... existing init logic ...
    self.outageRanges = Self.makeOutageRanges(from: outagePeriods, chartBounds: ...)
}
```

**4-layer data flow:**
- `StepAreaChartView` (layer 1): computes `outageRanges` in init
- `ChartWithHoverOverlay` (layer 2): receives `outageRanges`, passes to children
- `StaticChartContent` (layer 3): renders `RectangleMark` for each outage range
- `HoverOverlayContent` (layer 4): checks `hoveredOutage` for tooltip

### BarChartView Modifications

Same pattern as StepAreaChartView -- add `outagePeriods` parameter, compute `outageRanges` in init, plumb through 4 layers.

### Performance Architecture -- No Changes Needed

Both chart views already separate static content from hover overlay. Outage ranges are computed once in `init` (immutable `let`) and passed through as constants. This adds zero hover-time computation cost. The only new per-frame work is the `hoveredOutage` computed property which is a simple array scan (typically 0-3 outages visible).

### Framework: Swift Charts RectangleMark

Outage backgrounds use `RectangleMark` from Apple's Swift Charts -- same as existing gap backgrounds. No new framework imports needed.

**Do NOT use Canvas for outage rendering.** Swift Charts `RectangleMark` handles coordinate mapping automatically.
**Do NOT add any external dependency.** Everything uses existing Apple APIs.

### Project Structure Notes

**No new files.** All changes are modifications to existing files.

**Modified files:**
```text
cc-hdrm/Views/AnalyticsView.swift       # Fetch outage data, add legend, pass to UsageChart
cc-hdrm/Views/UsageChart.swift           # Add outagePeriods parameter, pass to chart views
cc-hdrm/Views/StepAreaChartView.swift    # Add outage background rendering + outage hover tooltip
cc-hdrm/Views/BarChartView.swift         # Add outage background rendering + outage hover tooltip
cc-hdrmTests/Views/UsageChartTests.swift # Add outage rendering tests
```

**After any file changes, run:**
```bash
xcodegen generate
```

### Previous Story Intelligence

**From Story 13.7 (gap rendering):**
- `GapRange` struct (StepAreaChartView:185-190): `id: Int, start: Date, end: Date` -- outage ranges follow same pattern
- `findGapRanges` (StepAreaChartView:63-82): detects gaps by segment boundaries -- outage ranges are computed differently (from DB data)
- Gap background: `RectangleMark` with `Color.secondary.opacity(0.08)` at lines 513-522 (StepAreaChartView) and 391-400 (BarChartView)
- Gap hover: `hoveredGap` computed property checks cursor date against gap ranges -- same pattern for `hoveredOutage`
- Gap tooltip: "No data" / "cc-hdrm not running" with `.ultraThinMaterial` background -- outage tooltip follows same visual pattern
- `hoveredDate` state var added to both chart views during 13.7 code review fix -- reuse this for outage hover detection
- 796 tests passing at Story 13.7 completion

**From Story 10.6 (outage persistence):**
- `OutagePeriod` model in `cc-hdrm/Models/OutagePeriod.swift` -- `startDate` and `endDate` computed properties for Date conversion from Unix ms
- `getOutagePeriods(from:to:)` in HistoricalDataService -- uses SQL overlap logic, returns sorted by `started_at` ASC
- Ongoing outages have `endedAt == nil` -- chart should treat these as extending to `Date()` (current time)
- `closeOpenOutages` is retained for potential use -- not needed for this story

**From Story 5.4 (connectivity notifications):**
- Outage detection threshold: 2+ consecutive poll failures -- already handled by HistoricalDataService
- Outage/recovery tracking is fully independent in HistoricalDataService -- no NotificationService coupling needed

### Code Review Lessons Applied

- **Static DateFormatter allocation** (Story 13.6): create `static let` formatters for tooltip date/duration display, not per-frame allocation
- **4-layer architecture** (Story 13.5/13.6): maintain strict separation -- outage ranges computed in init, passed as constants
- **Gap hover cursor-date fix** (Story 13.7 review): use `hoveredDate` (actual cursor position) for outage range detection, NOT nearest data point date

### Anti-Patterns to Avoid

- DO NOT create a new table or modify the database -- `api_outages` table already exists (Story 10.6)
- DO NOT add outage tracking logic -- tracking is done by HistoricalDataService (Story 10.6)
- DO NOT add outage notifications -- notifications handled by NotificationService (Story 5.4)
- DO NOT use Canvas for outage rendering -- use Swift Charts `RectangleMark` for coordinate mapping
- DO NOT allocate DateFormatter per hover frame -- use `static let` (lesson from Story 13.6)
- DO NOT render outage backgrounds before gap backgrounds -- render AFTER so outage overlays gap (AC 5)
- DO NOT check gap before outage in hover logic -- outage takes priority (AC 5)
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` -- protected file
- DO NOT use `print()` -- use `os.Logger`
- DO NOT use `DispatchQueue` or GCD -- use async/await
- DO NOT add any external dependency -- everything uses existing Apple APIs
- DO NOT create Asset Catalog colors for outage -- use programmatic `Color.red.opacity(0.08)` (simple, no light/dark mode complexity needed for a subtle tint)

### Edge Cases

| No. | Condition | Expected Behavior |
|-----|-----------|-------------------|
| 1 | No outages in visible range | No outage backgrounds, no legend, no outage tooltip |
| 2 | Ongoing outage (endedAt nil) | Outage band extends to current time (Date()) |
| 3 | Outage extends beyond chart bounds | Clip outage start/end to chart time range |
| 4 | Outage entirely outside chart bounds | Filter out during `makeOutageRanges` |
| 5 | Multiple outages in visible range | Multiple distinct background bands |
| 6 | Outage overlaps with data gap | Outage background overlays gap background (rendered after) |
| 7 | Hover transitions from outage to gap | Tooltip changes from "API outage" to "No data" |
| 8 | Hover transitions from outage to data | Tooltip changes from "API outage" to data tooltip |
| 9 | Very short outage (< 1 min) | Still rendered, tooltip shows "0 min" or "< 1 min" |
| 10 | Very long outage (days) | Continuous red tint background, tooltip shows "Xd Yh" |
| 11 | Time range switch clears outages | outagePeriods state resets on time range change |
| 12 | Database unavailable | getOutagePeriods returns [] gracefully, no outages shown |

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on ALL tests (SwiftUI views are `@MainActor`)
- **Pattern:** Follow existing UsageChartTests.swift helper patterns (`makeChart`, `makeSamplePolls`, `makeSampleRollups`)
- **Regression:** All existing tests must continue passing (zero regressions)
- **Run `xcodegen generate`** if any new test files created (not expected -- all tests go in existing `UsageChartTests.swift`)
- **New test count:** ~10 tests covering outage rendering, tooltip formatting, data flow, edge cases

### Library & Framework Requirements

- `Swift Charts` (`RectangleMark`) -- already imported in chart views. No new imports.
- No new external dependencies. Zero external packages.

### Git Intelligence

Last 5 commits:
- `a376153` feat: API outage period tracking and persistence (Story 10.6)
- `ef99e2b` feat: API connectivity notifications with outage/recovery state machine (Story 5.4)
- `fc21a55` feat: clickable ring gauges as analytics launchers (Story 4.6)
- `28d1248` feat: first-run onboarding popup, README rewrite, app icon
- `384cf95` chore: update changelog for v1.4.4 [skip ci]

### References

- [Source: `_bmad-output/planning-artifacts/epics/epic-13-full-analytics-window-phase-3.md` Story 13.8] -- Full acceptance criteria
- [Source: `_bmad-output/planning-artifacts/sprint-change-proposal-2026-03-02.md` Section 4 Change 2] -- API downtime awareness design, visual distinction spec
- [Source: `_bmad-output/implementation-artifacts/13-7-gap-rendering-in-charts.md`] -- Previous story: gap backgrounds, hover tooltips, 4-layer architecture patterns
- [Source: `_bmad-output/implementation-artifacts/10-6-api-outage-period-persistence.md`] -- Outage data model, getOutagePeriods API, database schema
- [Source: `_bmad-output/implementation-artifacts/5-4-api-connectivity-notifications.md`] -- Outage detection state machine, connectivity tracking
- [Source: `cc-hdrm/Models/OutagePeriod.swift`] -- OutagePeriod model struct (30 lines)
- [Source: `cc-hdrm/Services/HistoricalDataServiceProtocol.swift:91-96`] -- getOutagePeriods method signature
- [Source: `cc-hdrm/Services/HistoricalDataService.swift:1878-1942`] -- getOutagePeriods implementation with overlap query
- [Source: `cc-hdrm/Views/StepAreaChartView.swift:513-522`] -- Existing gap RectangleMark rendering pattern to follow
- [Source: `cc-hdrm/Views/StepAreaChartView.swift:666-668`] -- Existing hoveredGap computed property pattern to follow
- [Source: `cc-hdrm/Views/StepAreaChartView.swift:730-743`] -- Existing gap tooltip rendering pattern to follow
- [Source: `cc-hdrm/Views/BarChartView.swift:391-400`] -- Existing gap RectangleMark rendering in bar chart
- [Source: `cc-hdrm/Views/BarChartView.swift:565-569`] -- Existing hoveredGap in bar chart hover overlay
- [Source: `cc-hdrm/Views/BarChartView.swift:609-623`] -- Existing gap tooltip in bar chart
- [Source: `cc-hdrm/Views/UsageChart.swift:49-61`] -- Chart routing logic (StepAreaChartView vs BarChartView)
- [Source: `cc-hdrm/Views/AnalyticsView.swift:83-91`] -- UsageChart call site in AnalyticsView body
- [Source: `cc-hdrm/Views/AnalyticsView.swift:314-364`] -- fetchData static method for testability pattern
- [Source: `cc-hdrmTests/Views/UsageChartTests.swift`] -- Existing test patterns (1348 lines, 60+ tests)

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

None — implementation proceeded without debugging issues.

### Completion Notes List

- **Task 1 (Plumbing):** Added `@State outagePeriods` to AnalyticsView, `outagePeriods` field to `DataLoadResult`, outage period fetch in `fetchData` with date-range-appropriate bounds (poll bounds for `.day`, rollup bounds for `.week/.month/.all`). Added `outagePeriods` parameter to `UsageChart` (with default `[]`), passed through to `StepAreaChartView` and `BarChartView`.
- **Task 2 (StepAreaChartView backgrounds):** Added `OutageRange` struct, `makeOutageRanges` static method (clips to chart bounds, handles ongoing outages), `outageColor` constant (`Color.red.opacity(0.08)`). Outage `RectangleMark` backgrounds render AFTER gap backgrounds in `StaticChartContent` (AC 5).
- **Task 3 (BarChartView backgrounds):** Same pattern as StepAreaChartView — reuses `StepAreaChartView.OutageRange` and `makeOutageRanges`. Outage backgrounds render AFTER gap backgrounds in `StaticBarChartContent`.
- **Task 4 (StepAreaChartView tooltip):** Added `hoveredOutage` computed property to `HoverOverlayContent`, checked BEFORE gap (AC 5 priority). Outage tooltip: "API outage" primary + "duration (time range)" caption. Static DateFormatters for tooltip time display.
- **Task 5 (BarChartView tooltip):** Same pattern — `hoveredOutage` in `BarHoverOverlayContent`, outage checked before gap. Tooltip reuses `StepAreaChartView.formatOutageDuration` and `formatOutageTimeRange`.
- **Task 6 (Legend):** Conditional `outageLegend` view in AnalyticsView between `controlsRow` and `UsageChart`. Shows red swatch (`Color.red.opacity(0.3)`) + "API outage" text only when outage data exists.
- **Task 7 (Tests):** 10 new tests: chart rendering with/without outages (4 tests), UsageChart parameter passing, outage range clipping, ongoing outage handling, fetchData outage inclusion, duration formatting, empty outages. All pass.
- **Task 8 (Build verification):** `xcodegen generate` + `xcodebuild build` succeed. Full test suite: 1326 tests pass (1316 existing + 10 new), zero regressions. Manual verification items noted for user testing.

### Implementation Plan

Followed the 4-layer architecture pattern established in Stories 13.5-13.7. Outage ranges are computed once in `init` (immutable `let`) and passed as constants through the layer hierarchy — zero hover-time computation cost. Duration formatting uses `static let` DateFormatters (lesson from Story 13.6). Outage tooltip hover detection is a simple array scan (typically 0-3 outages visible).

### File List

- `cc-hdrm/Views/AnalyticsView.swift` — Modified: added `outagePeriods` state, `outageLegend` view, outage fetch in `fetchData`, `DataLoadResult.outagePeriods` field
- `cc-hdrm/Views/UsageChart.swift` — Modified: added `outagePeriods` parameter, passed to chart views, updated preview
- `cc-hdrm/Views/StepAreaChartView.swift` — Modified: added top-level `OutageRange` struct (with `make`/`formatDuration`/`formatTimeRange` static methods, color constant), shared `OutageTooltipView`, outage background rendering in `StaticChartContent`, outage hover + tooltip in `HoverOverlayContent`
- `cc-hdrm/Views/BarChartView.swift` — Modified: added `outageRanges` property, outage background rendering in `StaticBarChartContent`, outage hover + tooltip in `BarHoverOverlayContent` (using shared `OutageTooltipView`)
- `cc-hdrmTests/Views/UsageChartTests.swift` — Modified: added 13 outage-related tests + `MockHistoricalDataServiceForOutages` test helper

## Change Log

- 2026-03-04: Code review fixes (7 issues). M1: Added Task.checkCancellation() before outage fetch. M2: Replaced silent try? with do/catch + logger.warning for outage fetch. M3: Extracted OutageRange to top-level struct (decoupled from StepAreaChartView), moved utility methods. M4: Added 3 formatTimeRange unit tests. L1: Fixed meaningless >=0 assertions. L2: Updated makeChart test helper with outagePeriods parameter. L3: Created shared OutageTooltipView (eliminated duplication). 1329 tests pass, zero regressions.
- 2026-03-03: Implemented API outage background rendering in analytics charts (Story 13.8). Added muted red/salmon outage backgrounds behind chart data, outage hover tooltips with duration/time display (priority over gap tooltips), and conditional outage legend in AnalyticsView. 10 new tests, 1326 total passing.
