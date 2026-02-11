# Story 14.5: Analytics View Integration with Conditional Display

Status: done

## Story

As a developer using Claude Code,
I want the subscription value bar and context-aware summary integrated into the analytics view with time-range-aware behavior,
So that the value section adapts meaningfully as I explore different time ranges.

## Acceptance Criteria

1. **Given** the analytics window is open
   **When** AnalyticsView renders
   **Then** the subscription value bar and context-aware summary appear below the UsageChart
   **And** the value bar recalculates when the time range changes via HistoricalDataService
   *Note: Already implemented by Story 14.4 — verify no regressions.*

2. **Given** the selected time range changes
   **When** the value section re-renders
   **Then** the summary insight updates to match the new time range (per Story 14.4 rules)
   **And** the value bar recalculates aggregate breakdown for the new range
   *Note: Already implemented by Story 14.4 — verify no regressions.*

3. **Given** the selected time range has fewer than 6 hours of data
   **When** the value bar renders
   **Then** it shows a qualifier: "X hours of data in this view"
   **And** does not display dollar amounts (insufficient data for meaningful proration)

4. **Given** no reset events exist in the selected range
   **When** the value section renders
   **Then** the bar is hidden entirely (no 80px container with fallback text)
   **And** the summary shows: "No reset events in this period"

5. **Given** the value section has nothing notable to display (ValueInsight.isQuiet == true)
   **When** conditional visibility evaluates
   **Then** the section collapses to minimal height (single line summary only, no bar)
   **And** expands again when the user selects a range with meaningful data

## Tasks / Subtasks

- [x] Task 1: Add `dataQualifier` parameter to HeadroomBreakdownBar (AC: 3)
  - [x] 1.1 Add `var dataQualifier: String? = nil` parameter to `cc-hdrm/Views/HeadroomBreakdownBar.swift`
  - [x] 1.2 Extract bar+legend from `percentageOnlyBreakdown` into shared `percentageOnlyBarAndLegend(utilizationPercent:)` (no padding); refactor `percentageOnlyBreakdown` to call it. Add `qualifierContent` view builder: qualifier text + `percentageOnlyBarAndLegend` (no dollar amounts), own padding
  - [x] 1.3 Modify `content` view builder: insert `dataQualifier != nil` check after `resetEvents.isEmpty` check, before `breakdownContent`
  - [x] 1.4 Add `.accessibilityLabel()` to qualifier content including both qualifier text and percentage breakdown
  - [x] 1.5 Verify existing call sites still work (default parameter `nil` = no behavior change)

- [x] Task 2: Add conditional value section to AnalyticsView (AC: 3, 4, 5)
  - [x] 2.1 Add `computeDataSpanHours()` static method to `cc-hdrm/Views/AnalyticsView.swift`: computes `Double(lastEvent.timestamp - firstEvent.timestamp) / 3_600_000.0` from `resetEvents`; returns 0 when events are empty
  - [x] 2.2 Add `isQuietValueInsight` private computed property: calls `ValueInsightEngine.computeInsight()` and returns `insight.isQuiet` (pure computation, acceptable duplication with ContextAwareValueSummary)
  - [x] 2.3 Extract `valueSection` computed view builder in AnalyticsView body with priority-ordered conditions:
    1. `resetEvents.isEmpty` → show `ContextAwareValueSummary` only (AC 4)
    2. `dataSpanHours < 6` → show `HeadroomBreakdownBar(dataQualifier: qualifierText)` + `ContextAwareValueSummary` (AC 3)
    3. `isQuietValueInsight` → show `ContextAwareValueSummary` only (AC 5)
    4. Default → show `HeadroomBreakdownBar` + `ContextAwareValueSummary` (AC 1, 2)
  - [x] 2.4 Qualifier text format: `let n = max(1, Int(floor(dataSpanHours))); return "\(n) \(n == 1 ? "hour" : "hours") of data in this view"` — floor for conservative accuracy, min 1, singular/plural
  - [x] 2.5 Replace inline `HeadroomBreakdownBar(...)` + `ContextAwareValueSummary(...)` in `body` VStack with `valueSection`

- [x] Task 3: Tests for HeadroomBreakdownBar qualifier mode (AC: 3)
  - [x] 3.1 Test: `dataQualifier nil` renders normal dollar breakdown (no regression)
  - [x] 3.2 Test: `dataQualifier` set renders percentage-only mode (suppresses dollars)
  - [x] 3.3 Test: `dataQualifier` set calls `aggregateBreakdown` (percentage-only path)
  - [x] 3.4 Test: `dataQualifier` with nil creditLimits still shows "unavailable" message (creditLimits nil takes priority)
  - [x] 3.5 Test: `dataQualifier` with empty events still shows "no events" message (empty events takes priority)

- [x] Task 4: Tests for AnalyticsView conditional display (AC: 3, 4, 5)
  - [x] 4.1 Test: `computeDataSpanHours` returns 0 for empty events
  - [x] 4.2 Test: `computeDataSpanHours` returns correct hours for events spanning 3 hours
  - [x] 4.3 Test: `computeDataSpanHours` returns 0 for single event (span between first and last = 0)
  - [x] 4.4 Test: `fetchData` call counts unchanged (no regression from conditional display)
  - [x] 4.5 Test: AnalyticsView renders without crashing with empty events (AC 4 path)
  - [x] 4.6 Test: AnalyticsView renders without crashing with events spanning < 6 hours (AC 3 path)
  - [x] 4.7 Test: AnalyticsView renders without crashing with quiet insight data (AC 5 path)
  - [x] 4.8 Test: AnalyticsView renders without crashing with notable insight data (normal path)

- [x] Task 5: Build verification (AC: all)
  - [x] 5.1 Run `xcodegen generate`
  - [x] 5.2 Run `xcodebuild -scheme cc-hdrm -destination 'platform=macOS' build`
  - [x] 5.3 Run full test suite — all existing + new tests pass (874 tests in 76 suites)
  - [x] 5.4 Verify no regressions in existing analytics view, breakdown bar, or value summary tests

## Dev Notes

### Scope Clarification

ACs 1-2 are **already implemented** by Story 14.4. That story added `ContextAwareValueSummary` below `HeadroomBreakdownBar` in AnalyticsView.body and wired up time-range-reactive data loading. Story 14.5's new work is exclusively ACs 3-5: data span qualifier, conditional bar visibility, and quiet-mode collapse.

### Design: Conditional Value Section

The core change is extracting a `valueSection` computed view builder in AnalyticsView with priority-ordered display logic:

```swift
@ViewBuilder
private var valueSection: some View {
    let dataSpanHours = computeDataSpanHours()

    if resetEvents.isEmpty {
        // AC 4: bar hidden, summary shows "No reset events in this period"
        ContextAwareValueSummary(...)
    } else if dataSpanHours < 6 {
        // AC 3: bar shows qualifier + percentage-only, summary shows insight
        HeadroomBreakdownBar(..., dataQualifier: qualifierText(hours: dataSpanHours))
        ContextAwareValueSummary(...)
    } else if isQuietValueInsight {
        // AC 5: bar hidden, summary-only collapsed section
        ContextAwareValueSummary(...)
    } else {
        // Normal: full bar + summary
        HeadroomBreakdownBar(...)
        ContextAwareValueSummary(...)
    }
}
```

**Priority rationale:**
1. Empty events is the strongest signal — nothing to show at all
2. Insufficient data (< 6h) is an important qualifier even if insight would be quiet
3. Quiet insight only applies when data is sufficient but unremarkable
4. Default is full display

### Design: HeadroomBreakdownBar `dataQualifier` Parameter

A single new optional parameter replaces dollar breakdown with percentage-only mode plus qualifier text:

```swift
struct HeadroomBreakdownBar: View {
    let resetEvents: [ResetEvent]
    let creditLimits: CreditLimits?
    let headroomAnalysisService: any HeadroomAnalysisServiceProtocol
    let selectedTimeRange: TimeRange
    var dataQualifier: String? = nil  // NEW

    @ViewBuilder
    private var content: some View {
        if creditLimits == nil {
            // unchanged — "Subscription breakdown unavailable..."
        } else if resetEvents.isEmpty {
            // unchanged — "No reset events in this period"
        } else if dataQualifier != nil {
            qualifierContent  // NEW — qualifier text + percentage-only bar
        } else {
            breakdownContent  // unchanged — dollar or percentage breakdown
        }
    }
}
```

The `qualifierContent` view builder:
- Shows `dataQualifier!` text at top (`.font(.caption)`, `.foregroundStyle(.secondary)`, `.frame(maxWidth: .infinity, alignment: .leading)`)
- Renders the percentage-only bar + legend inline (same content as `percentageOnlyBreakdown`, but NOT by calling that method — it has its own `.padding` that would nest)
- Recommended approach: extract the bar+legend from `percentageOnlyBreakdown` into a shared inner builder (e.g. `percentageOnlyBarAndLegend(limits:)`) with no padding, called by both `percentageOnlyBreakdown` and `qualifierContent`. Each caller applies its own padding.
- Wrapped in VStack(spacing: 4) with `.padding(.horizontal, 12).padding(.vertical, 8)` within the existing 80px frame

The nil creditLimits and empty events checks remain ABOVE the qualifier check — those states take priority. Existing call sites pass `dataQualifier: nil` (default) and see no behavior change.

### Design: Data Span Computation

```swift
private func computeDataSpanHours() -> Double {
    guard let first = resetEvents.first, let last = resetEvents.last else { return 0 }
    return Double(last.timestamp - first.timestamp) / 3_600_000.0
}
```

- Empty events → 0 (handled by AC 4 path before reaching AC 3 check)
- Single event → 0 (first == last, span = 0). Since 0 < 6, qualifier shows "1 hour of data" (min 1)
- Multiple events spanning 3.7 hours → 3.7. Qualifier shows "3 hours of data" (floor)

**Qualifier text format:** `let n = max(1, Int(floor(hours))); "\(n) \(n == 1 ? "hour" : "hours") of data in this view"`
- floor(3.7) = 3 → "3 hours of data in this view" (conservative)
- floor(0.5) = 0, max(1, 0) = 1 → "1 hour of data in this view" (singular)
- floor(5.9) = 5 → "5 hours of data in this view"

Note: `SubscriptionValueCalculator.periodDays()` uses `max(1.0, actualDays)` which clamps to minimum 1 day = 24 hours. The data span qualifier uses the RAW span, not the clamped value, because it needs to detect sub-day spans.

### Design: Quiet Insight Detection

Note: `appState` and `headroomAnalysisService` are `let` init parameters on AnalyticsView (not `@State`). The `@State` properties used by conditional logic are `resetEvents`, `allTimeResetEvents`, and `selectedTimeRange`.

```swift
private var isQuietValueInsight: Bool {
    let subscriptionValue: SubscriptionValue?
    if selectedTimeRange != .all, let limits = appState.creditLimits {
        subscriptionValue = SubscriptionValueCalculator.calculate(
            resetEvents: resetEvents,
            creditLimits: limits,
            timeRange: selectedTimeRange,
            headroomAnalysisService: headroomAnalysisService
        )
    } else {
        subscriptionValue = nil
    }

    let insight = ValueInsightEngine.computeInsight(
        timeRange: selectedTimeRange,
        subscriptionValue: subscriptionValue,
        resetEvents: resetEvents,
        allTimeResetEvents: allTimeResetEvents,
        creditLimits: appState.creditLimits,
        headroomAnalysisService: headroomAnalysisService
    )
    return insight.isQuiet
}
```

This duplicates computation that `ContextAwareValueSummary` performs internally. Acceptable because:
- `ValueInsightEngine.computeInsight()` is a pure static function with no side effects
- The computation is trivial (a few comparisons and optional chaining)
- The view re-renders only when `@State` properties change (not on every frame)
- Avoids coupling AnalyticsView to ContextAwareValueSummary's internal state

### Quiet Mode Definition (from ValueInsightEngine)

`ValueInsight.isQuiet == true` when:
- Utilization is between 20-80% (normal range)
- No significant deviation from average (7d insight)
- No significant trend (All insight)
- Zero events (always quiet)

When `isQuiet` is true and data span >= 6h, the bar adds no value — the user's usage is unremarkable. Collapsing to summary-only (AC 5) reduces visual noise.

### What This Story Does NOT Create

- No new files — all changes are to existing AnalyticsView and HeadroomBreakdownBar
- No new services or models
- No database changes
- No new dependencies

### Existing Code to Reuse — DO NOT Recreate

| Component | File | What It Provides |
|-----------|------|-----------------|
| `ValueInsightEngine` | `cc-hdrm/Services/ValueInsightEngine.swift` | `computeInsight()` for quiet detection, `isQuiet` flag |
| `SubscriptionValueCalculator` | `cc-hdrm/Services/SubscriptionValueCalculator.swift` | `calculate()` for subscription value, `periodDays()` for span math |
| `HeadroomBreakdownBar.percentageOnlyBreakdown()` | `cc-hdrm/Views/HeadroomBreakdownBar.swift` | Existing percentage-only rendering — extract bar+legend into shared inner builder for reuse by qualifier mode |
| `ContextAwareValueSummary` | `cc-hdrm/Views/ContextAwareValueSummary.swift` | Summary view — NO changes needed, works correctly in all conditions |
| `MockHeadroomAnalysisService` | `cc-hdrmTests/Mocks/MockHeadroomAnalysisService.swift` | Mock for testing — already has `aggregateBreakdownHandler` from 14.4 |
| `MockHistoricalDataService` | `cc-hdrmTests/Mocks/MockHistoricalDataService.swift` | Mock for AnalyticsView data loading tests |

### Project Structure Notes

- No new files — modifications only to `cc-hdrm/Views/AnalyticsView.swift` and `cc-hdrm/Views/HeadroomBreakdownBar.swift`
- Test additions to existing `cc-hdrmTests/Views/AnalyticsViewTests.swift` and `cc-hdrmTests/Views/HeadroomBreakdownBarTests.swift`
- No changes to entitlements, Info.plist, or project configuration
- Run `xcodegen generate` not needed (no new files), but good practice to verify

### Previous Story (14.4) Learnings

- `ValueInsightEngine` is a pure `enum` with static methods (same as `SubscriptionValueCalculator`) — safe to call from computed properties
- `ContextAwareValueSummary` computes `ValueInsight` internally — no external insight state needed
- AnalyticsView's `.task(id: selectedTimeRange)` already handles all data reloading — conditional display just reads the loaded `@State` arrays
- `allTimeResetEvents` caching (Story 14.4 code review [M2]) prevents redundant DB queries on range switch — this story benefits from that optimization
- `percentageOnlyBreakdown` in HeadroomBreakdownBar is already factored out as a separate view builder — reusable for qualifier mode
- Story 14.4 had 857 tests in 75 suites passing — baseline for regression check
- The `aggregateBreakdownHandler` added to MockHeadroomAnalysisService during 14.4 code review [H1] enables deterministic testing of percentage-only mode

### Git Intelligence (Recent Commits)

```
33558bd docs: address CodeRabbit review feedback across planning artifacts
9fad73d docs: shard epics into individual files and update planning artifacts
a94df74 feat: context-aware value summary with terminology refactor (Story 14.4)
2743534 feat: persist extra usage data to SQLite database
0a4f091 feat: subscription value bar with dollar-based utilization tracking (Story 14.3)
```

Story 14.4 (a94df74) is the immediate predecessor. This story builds directly on the AnalyticsView integration and HeadroomBreakdownBar established in 14.3-14.4.

### References

- [Source: `_bmad-output/planning-artifacts/epics/epic-14-subscription-value-usage-insights-phase-3.md:141-172`] — Story 14.5 acceptance criteria
- [Source: `_bmad-output/planning-artifacts/sprint-change-proposal-2026-02-10.md:139+`] — Rewrite rationale for Story 14.5
- [Source: `_bmad-output/implementation-artifacts/14-4-context-aware-value-summary-terminology-refactor.md`] — Previous story with dev notes and file list
- [Source: `cc-hdrm/Views/AnalyticsView.swift:73-104`] — Current body VStack with HeadroomBreakdownBar + ContextAwareValueSummary integration
- [Source: `cc-hdrm/Views/HeadroomBreakdownBar.swift:25-39`] — Current `content` view builder with nil/empty checks
- [Source: `cc-hdrm/Views/HeadroomBreakdownBar.swift:117-157`] — `percentageOnlyBreakdown` method (reused for qualifier)
- [Source: `cc-hdrm/Views/ContextAwareValueSummary.swift:12-18`] — View body computing insight and rendering text
- [Source: `cc-hdrm/Services/ValueInsightEngine.swift:25-47`] — `computeInsight()` static method, `isQuiet` flag
- [Source: `cc-hdrm/Services/ValueInsightEngine.swift:275-277`] — `isQuietUtilization()` helper (20-80% range)
- [Source: `cc-hdrm/Services/SubscriptionValueCalculator.swift:74-88`] — `periodDays()` with `max(1.0, ...)` clamp (not used for data span qualifier)
- [Source: `cc-hdrm/Models/TimeRange.swift`] — TimeRange enum (.day, .week, .month, .all)
- [Source: `cc-hdrmTests/Views/AnalyticsViewTests.swift`] — Existing test suite (525 lines)
- [Source: `cc-hdrmTests/Views/HeadroomBreakdownBarTests.swift`] — Existing test suite (291 lines)
- [Source: `_bmad-output/planning-artifacts/architecture.md:1077-1084`] — Analytics window architecture
- [Source: `_bmad-output/planning-artifacts/project-context.md`] — Tech stack, naming conventions, project structure

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (claude-opus-4-6)

### Debug Log References

- Initial build succeeded before tests — verified source changes compile cleanly
- 2 test failures on first run: (1) `dataQualifierNilRendersNormalBreakdown` expected 0 aggregateBreakdown calls but got 1 — `SubscriptionValueCalculator.calculate()` calls `aggregateBreakdown` internally; (2) `rendersWithQuietInsightData` expected quiet insight but got notable — events spanning 48h with .week range caused `periodDays` to cap at 2 days, inflating utilization to 100%. Both fixed by correcting test expectations.

### Completion Notes List

- **Task 1:** Added `var dataQualifier: String? = nil` to HeadroomBreakdownBar. Extracted `percentageOnlyBarAndLegend(utilizationPercent:)` shared builder (no padding) from `percentageOnlyBreakdown`. Added `qualifierContent` computed property with qualifier text + percentage-only bar in VStack(spacing: 4). Added `percentageOnlyUtilization(limits:)` helper to avoid duplicate `aggregateBreakdown` calls. Accessibility label on qualifier includes both qualifier text and utilization percentage.
- **Task 2:** Added `computeDataSpanHours(resetEvents:)` as a static method for testability (same pattern as `fetchData`). Added `isQuietValueInsight` computed property duplicating `ValueInsightEngine.computeInsight()` call (pure, no side effects). Extracted `valueSection` with 4 priority-ordered branches: empty events (AC 4), short span < 6h (AC 3), quiet insight (AC 5), normal (AC 1-2). Qualifier text uses floor + singular/plural formatting.
- **Task 3:** Added 5 tests to HeadroomBreakdownBarTests: nil qualifier normal path, qualifier set percentage-only mode, aggregateBreakdown call verification, nil creditLimits priority, empty events priority. Updated `makeBar` helper with `dataQualifier` parameter.
- **Task 4:** Added 8 tests in new `AnalyticsViewConditionalDisplayTests` suite: `computeDataSpanHours` edge cases (empty/3h/single), fetchData regression check, and 4 render-without-crashing tests covering AC 4/3/5/normal paths. Tests verify logic via static methods and component composition.
- **Task 5:** xcodegen generate, build, 874 tests in 76 suites all pass. No regressions.

### Change Log

- 2026-02-11: Implemented Story 14.5 — Analytics view conditional display with data span qualifier (AC 3), hidden bar for empty events (AC 4), and quiet-mode collapse (AC 5). 13 new tests added. 874 total tests passing.
- 2026-02-11: Code review fixes — [M1] Clarified test names for 4.6-4.8 to reflect actual coverage scope. [M2] Updated stale layout doc comment on AnalyticsView struct. [M3] Refactored `valueSection` to deduplicate ContextAwareValueSummary (summary always shown, bar conditionally added). [L1] Replaced force-unwraps in `qualifierContent` with `if let`. [L3] Updated HeadroomBreakdownBar struct doc to describe all 3 display modes. 874 tests passing.

### File List

**Modified source files (2):**
- `cc-hdrm/Views/AnalyticsView.swift` — Conditional value section (`valueSection`), `computeDataSpanHours()` static method, `isQuietValueInsight` computed property, replaced inline bar+summary with `valueSection` in body
- `cc-hdrm/Views/HeadroomBreakdownBar.swift` — `var dataQualifier: String? = nil` parameter, `qualifierContent` view builder, `percentageOnlyBarAndLegend(utilizationPercent:)` shared builder, `percentageOnlyUtilization(limits:)` helper, refactored `percentageOnlyBreakdown` to use shared builder

**Modified test files (2):**
- `cc-hdrmTests/Views/AnalyticsViewTests.swift` — Added `AnalyticsViewConditionalDisplayTests` suite with 8 tests (computeDataSpanHours edge cases, fetchData regression, render paths for AC 3/4/5/normal)
- `cc-hdrmTests/Views/HeadroomBreakdownBarTests.swift` — Updated `makeBar` helper with `dataQualifier` parameter, added 5 qualifier mode tests (nil regression, percentage-only, aggregateBreakdown, creditLimits priority, empty events priority)
