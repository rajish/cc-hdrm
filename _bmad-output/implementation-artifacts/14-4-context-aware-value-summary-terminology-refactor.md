# Story 14.4: Context-Aware Value Summary & Terminology Refactor

Status: complete

## Story

As a developer using Claude Code,
I want a context-aware summary below the subscription value bar that adapts to the selected time range,
So that I see the single most relevant insight for the data I'm looking at.

## Acceptance Criteria

1. **Given** the analytics view shows a time range with reset events
   **When** the summary section renders
   **Then** it selects and displays the most relevant insight for the time range:
   - **24h:** Simple capacity gauge -- "Used $X of $Y today" or utilization percentage if no pricing
   - **7d:** Usage vs. personal average -- "X% above/below your typical week"
   - **30d:** Dollar summary -- "Used $X of $Y this month" with utilization percentage
   - **All:** Long-term trend -- "Avg monthly utilization: X%" with trend direction

2. **Given** zero reset events exist in the selected range
   **When** the summary section renders
   **Then** it displays: "No reset events in this period"

3. **Given** nothing notable is detected (utilization between 20-80%, no trend change)
   **When** the summary section renders
   **Then** the summary collapses to a single quiet line (e.g., "Normal usage")
   **And** does not demand visual attention

4. **Given** credit limits are unknown
   **When** the summary section renders
   **Then** it shows percentages only (no dollar values)

5. **Terminology refactor (technical task):**
   - Rename `HeadroomBreakdown.wastePercent` -> `unusedPercent`
   - Rename `HeadroomBreakdown.wasteCredits` -> `unusedCredits`
   - Rename `PeriodSummary.wastePercent` -> `unusedPercent`
   - Rename `PeriodSummary.wasteCredits` -> `unusedCredits`
   - Rename `SubscriptionValue.wastedDollars` -> `unusedDollars`
   - Rename `ResetEvent.wasteCredits` -> `unusedCredits`
   - Rename `UsageRollup.wasteCredits` -> `unusedCredits`
   - Update all call sites, tests, and VoiceOver labels to use neutral terminology
   - Bar legend: "Wasted" -> "Unused"

## Tasks / Subtasks

- [x] Task 1: Terminology refactor -- Model layer (AC: 5)
  - [x] 1.1 `cc-hdrm/Models/HeadroomBreakdown.swift`: Rename `HeadroomBreakdown.wastePercent` -> `unusedPercent`, `wasteCredits` -> `unusedCredits`; rename `PeriodSummary.wastePercent` -> `unusedPercent`, `wasteCredits` -> `unusedCredits`; update doc comments
  - [x] 1.2 `cc-hdrm/Models/ResetEvent.swift`: Rename `wasteCredits` -> `unusedCredits`
  - [x] 1.3 `cc-hdrm/Models/UsageRollup.swift`: Rename `wasteCredits` -> `unusedCredits`

- [x] Task 2: Terminology refactor -- Service layer (AC: 5)
  - [x] 2.1 `cc-hdrm/Services/HeadroomAnalysisService.swift`: Rename local variable `trueWasteCredits` -> `trueUnusedCredits`, `totalWaste` -> `totalUnused`, and all `wastePercent`/`wasteCredits` references in struct initializations (~7 lines)
  - [x] 2.2 `cc-hdrm/Services/SubscriptionValueCalculator.swift`: Rename `wastedDollars` -> `unusedDollars` in `SubscriptionValue` struct and in `calculate()` computation (~3 lines)
  - [x] 2.3 `cc-hdrm/Services/HistoricalDataService.swift`: Update Swift-side property access from `.wasteCredits` -> `.unusedCredits` across all read/write sites (~16 lines). **CRITICAL: Keep SQL column name `waste_credits` unchanged** -- no database migration needed, only Swift property mapping changes

- [x] Task 3: Terminology refactor -- View layer (AC: 5)
  - [x] 3.1 `cc-hdrm/Views/HeadroomBreakdownBar.swift`: Change "Wasted" -> "Unused" in dollar legend (line ~173) and percentage legend (line ~196); update `value.wastedDollars` -> `value.unusedDollars`; update preview stub `PeriodSummary` and `HeadroomBreakdown` initializations to use new property names
  - [x] 3.2 `cc-hdrm/Views/AnalyticsView.swift`: Update preview stub `PreviewAnalyticsHeadroomService` -- `wastePercent` -> `unusedPercent`, `wasteCredits` -> `unusedCredits` in mock `HeadroomBreakdown` and `PeriodSummary` initializations (lines ~277-284)

- [x] Task 4: Terminology refactor -- Tests and mocks (AC: 5)
  - [x] 4.1 Update `cc-hdrmTests/Models/HeadroomBreakdownTests.swift` (~18 occurrences)
  - [x] 4.2 Update `cc-hdrmTests/Models/ResetEventTests.swift` (~8 occurrences)
  - [x] 4.3 Update `cc-hdrmTests/Models/UsageRollupTests.swift` (~10 occurrences)
  - [x] 4.4 Update `cc-hdrmTests/Services/HeadroomAnalysisServiceTests.swift` (~12 occurrences)
  - [x] 4.5 Update `cc-hdrmTests/Services/SubscriptionValueCalculatorTests.swift` (~9 occurrences)
  - [x] 4.6 Update `cc-hdrmTests/Services/HistoricalDataServiceTests.swift` (~4 occurrences)
  - [x] 4.7 Update `cc-hdrmTests/Services/DatabaseManagerTests.swift` (~2 occurrences)
  - [x] 4.8 Update `cc-hdrmTests/Views/HeadroomBreakdownBarTests.swift` (~10 occurrences)
  - [x] 4.9 Update `cc-hdrmTests/Views/AnalyticsViewTests.swift` (~3 occurrences)
  - [x] 4.10 Update `cc-hdrmTests/Views/UsageChartTests.swift` (~13 occurrences)
  - [x] 4.11 Update `cc-hdrmTests/Mocks/MockHeadroomAnalysisService.swift` -- rename mock property values

- [x] Task 5: Build verification -- terminology refactor (AC: 5)
  - [x] 5.1 Run `xcodegen generate`
  - [x] 5.2 Run `xcodebuild -scheme cc-hdrm -destination 'platform=macOS' build`
  - [x] 5.3 Run full test suite -- all existing tests must pass with new property names
  - [x] 5.4 Verify no remaining occurrences of `wastePercent`, `wasteCredits`, or `wastedDollars` in Swift source or test files (grep check)

- [x] Task 6: Create ValueInsightEngine (AC: 1, 2, 3, 4)
  - [x] 6.1 Create `cc-hdrm/Services/ValueInsightEngine.swift`
  - [x] 6.2 Define `ValueInsight` struct:
    ```swift
    struct ValueInsight: Sendable, Equatable {
        let text: String
        let isQuiet: Bool  // true = muted styling, single quiet line
    }
    ```
  - [x] 6.3 Implement `static func computeInsight(timeRange:subscriptionValue:resetEvents:allTimeResetEvents:creditLimits:headroomAnalysisService:) -> ValueInsight`
  - [x] 6.4 Implement 24h insight: "Used $X of $Y today" (dollar mode) or "Z% utilization today" (percentage-only mode when creditLimits has no monthlyPrice)
  - [x] 6.5 Implement 7d insight: Compare current week utilization against all-time average utilization. Display "X% above your typical week" / "X% below your typical week". If difference < 5%, return quiet "Normal usage". If insufficient history (all-time span < 14 days), fall back to "Used $X of $Y this week" / "Z% utilization this week"
  - [x] 6.6 Implement 30d insight: "Used $X of $Y this month (Z%)" (dollar mode) or "Z% utilization this month" (percentage-only)
  - [x] 6.7 Implement All insight: Compute average monthly utilization across all data. Determine trend by comparing last 3 months: "trending up" if each > previous by > 5%, "trending down" if each < previous by > 5%, omit trend text otherwise. Display "Avg monthly utilization: X%" or "Avg monthly utilization: X%, trending up/down". If < 2 months of data, show average only, no trend. If within 20-80% and no trend change, return quiet.
  - [x] 6.8 Handle zero events: return `ValueInsight(text: "No reset events in this period", isQuiet: true)`
  - [x] 6.9 Handle "nothing notable" (20-80% utilization, no significant deviation): return quiet insight
  - [x] 6.10 Use `SubscriptionValueCalculator.formatDollars()` for all dollar formatting (reuse existing)
  - [x] 6.11 Use `SubscriptionValueCalculator.calculate()` internally when computing all-time values for 7d comparison and monthly groupings for All trend

- [x] Task 7: Create ContextAwareValueSummary view (AC: 1, 2, 3, 4)
  - [x] 7.1 Create `cc-hdrm/Views/ContextAwareValueSummary.swift`
  - [x] 7.2 Accept inputs: `timeRange: TimeRange`, `resetEvents: [ResetEvent]`, `allTimeResetEvents: [ResetEvent]`, `creditLimits: CreditLimits?`, `headroomAnalysisService: any HeadroomAnalysisServiceProtocol`
  - [x] 7.3 Compute `ValueInsight` internally via `ValueInsightEngine.computeInsight()`
  - [x] 7.4 Render insight text: `.font(.caption)` baseline; `.foregroundStyle(.primary)` for notable insights; `.foregroundStyle(.tertiary)` for quiet mode
  - [x] 7.5 `.accessibilityLabel()` with the insight text
  - [x] 7.6 Add `#Preview` with sample data showing each time range insight

- [x] Task 8: Integrate into AnalyticsView (AC: 1)
  - [x] 8.1 Add `@State private var allTimeResetEvents: [ResetEvent] = []` to AnalyticsView
  - [x] 8.2 Update `DataLoadResult` struct to include `allTimeResetEvents: [ResetEvent] = []`
  - [x] 8.3 In `fetchData()`, add `let allTime = try await service.getResetEvents(range: .all)` and include in return value
  - [x] 8.4 In `loadData()`, apply `allTimeResetEvents = result.allTimeResetEvents`
  - [x] 8.5 Add `ContextAwareValueSummary` below `HeadroomBreakdownBar` in body VStack, passing `selectedTimeRange`, `resetEvents`, `allTimeResetEvents`, `appState.creditLimits`, `headroomAnalysisService`

- [x] Task 9: Tests for new components (AC: 1, 2, 3, 4)
  - [x] 9.1 Create `cc-hdrmTests/Services/ValueInsightEngineTests.swift`
  - [x] 9.2 Test 24h insight with dollar value: "Used $X of $Y today"
  - [x] 9.3 Test 24h insight percentage-only (nil monthlyPrice): "Z% utilization today"
  - [x] 9.4 Test 7d insight above average: "X% above your typical week"
  - [x] 9.5 Test 7d insight below average: "X% below your typical week"
  - [x] 9.6 Test 7d insight near average (< 5% diff): quiet "Normal usage"
  - [x] 9.7 Test 7d insight insufficient history (< 14 days): falls back to dollar/percentage summary
  - [x] 9.8 Test 30d insight with dollar value and utilization percentage
  - [x] 9.9 Test 30d insight percentage-only
  - [x] 9.10 Test All insight with trending up
  - [x] 9.11 Test All insight with trending down
  - [x] 9.12 Test All insight stable (no significant trend): quiet mode
  - [x] 9.13 Test All insight insufficient history (< 2 months): average only, no trend
  - [x] 9.14 Test zero events: "No reset events in this period"
  - [x] 9.15 Test nil creditLimits: percentages only, no dollar values
  - [x] 9.16 Test "nothing notable" quiet mode (20-80% utilization, no deviation)

- [x] Task 10: Build verification -- complete (AC: all)
  - [x] 10.1 Run `xcodegen generate`
  - [x] 10.2 Run `xcodebuild -scheme cc-hdrm -destination 'platform=macOS' build`
  - [x] 10.3 Run full test suite -- all tests pass (857 tests, 75 suites)
  - [x] 10.4 Verify no regressions in existing analytics view, breakdown bar, or subscription value tests

## Dev Notes

### Two-Part Story

This story has two distinct parts that should be done **sequentially**:

1. **Terminology refactor** (Tasks 1-5): Mechanical rename of "waste" -> "unused" across the codebase
2. **Context-aware value summary** (Tasks 6-10): New feature using the renamed types

Complete the refactor first and verify the build before starting the new feature. All new code should use the new terminology from the start.

### Terminology Refactor -- Database Column Strategy

**CRITICAL:** The SQLite column `waste_credits` in `reset_events` and rollup tables does **NOT** get renamed. Only the Swift-side property names change. This avoids database migrations entirely.

The HistoricalDataService reads `waste_credits` from SQL results and maps to the Swift `unusedCredits` property. When writing, it maps `unusedCredits` back to the `waste_credits` column. The SQL strings referencing `waste_credits` stay as-is.

### Terminology Refactor -- Complete File Manifest

**Source files (8 files):**

| File | Changes | Approx. Occurrences |
|------|---------|---------------------|
| `cc-hdrm/Models/HeadroomBreakdown.swift` | Properties + doc comments | 4 |
| `cc-hdrm/Models/ResetEvent.swift` | Property | 1 |
| `cc-hdrm/Models/UsageRollup.swift` | Property | 1 |
| `cc-hdrm/Services/HeadroomAnalysisService.swift` | Local vars + struct inits | 7 |
| `cc-hdrm/Services/SubscriptionValueCalculator.swift` | Property + var + init | 3 |
| `cc-hdrm/Services/HistoricalDataService.swift` | Swift property access only (SQL stays) | 16 |
| `cc-hdrm/Views/HeadroomBreakdownBar.swift` | UI labels + preview data | 6 |
| `cc-hdrm/Views/AnalyticsView.swift` | Preview data only | 4 |

**Test files (10 files):**

| File | Approx. Occurrences |
|------|---------------------|
| `cc-hdrmTests/Models/HeadroomBreakdownTests.swift` | 18 |
| `cc-hdrmTests/Models/ResetEventTests.swift` | 8 |
| `cc-hdrmTests/Models/UsageRollupTests.swift` | 10 |
| `cc-hdrmTests/Services/HeadroomAnalysisServiceTests.swift` | 12 |
| `cc-hdrmTests/Services/SubscriptionValueCalculatorTests.swift` | 9 |
| `cc-hdrmTests/Services/HistoricalDataServiceTests.swift` | 4 |
| `cc-hdrmTests/Services/DatabaseManagerTests.swift` | 2 |
| `cc-hdrmTests/Views/HeadroomBreakdownBarTests.swift` | 10 |
| `cc-hdrmTests/Views/AnalyticsViewTests.swift` | 3 |
| `cc-hdrmTests/Views/UsageChartTests.swift` | 13 |

**Mock file (1 file):**

| File | Changes |
|------|---------|
| `cc-hdrmTests/Mocks/MockHeadroomAnalysisService.swift` | Mock property values |

**Total: ~119 occurrences across 19 files.** Verify with grep after completion -- zero occurrences of `wastePercent`, `wasteCredits`, or `wastedDollars` should remain in any `.swift` file.

### Value Summary -- Design

**ValueInsightEngine** (`cc-hdrm/Services/ValueInsightEngine.swift`):
- Pure `enum` with static methods (same pattern as `SubscriptionValueCalculator`)
- Takes data in, returns `ValueInsight` out
- Calls `SubscriptionValueCalculator.calculate()` and `.formatDollars()` internally for dollar values
- Calls `HeadroomAnalysisServiceProtocol.aggregateBreakdown()` for credit aggregation when computing all-time comparison values
- No database access, no side effects

**ContextAwareValueSummary** (`cc-hdrm/Views/ContextAwareValueSummary.swift`):
- Thin view wrapper around ValueInsightEngine output
- Takes same inputs as HeadroomBreakdownBar plus `allTimeResetEvents: [ResetEvent]`
- Computes `ValueInsight` internally and renders as styled text
- Single line height -- just text, no bar or complex visuals

### Value Summary -- Insight Logic by Time Range

**24h (`.day`):**
- Dollar mode: "Used $X of $Y today"
- Percentage mode (no monthlyPrice): "Z% utilization today"
- Quiet if 20-80% utilization

**7d (`.week`):**
- Compute all-time utilization: `SubscriptionValueCalculator.calculate(resetEvents: allTimeResetEvents, creditLimits:, timeRange: .all, headroomAnalysisService:)?.utilizationPercent`
- Compare current week's `utilizationPercent` against all-time `utilizationPercent`
- |diff| >= 5%: "X% above/below your typical week" (not quiet)
- |diff| < 5%: "Normal usage" (quiet)
- Insufficient history (all-time span < 14 days based on first/last event timestamps): fall back to 30d-style summary -- "Used $X of $Y this week" or "Z% utilization this week"

**30d (`.month`):**
- Dollar mode: "Used $X of $Y this month (Z%)"
- Percentage mode: "Z% utilization this month"
- Quiet if 20-80% utilization

**All (`.all`):**
- Group events by calendar month using `Calendar.current.dateComponents([.year, .month], from: Date(timeIntervalSince1970: Double(event.timestamp) / 1000.0))`
- For each month with events: compute utilization using `SubscriptionValueCalculator.calculate()` with that month's events and `.month` time range
- Average monthly utilization = arithmetic mean of per-month utilizations
- **Trend detection:** Compare last 3 completed months sequentially. If each month's utilization exceeds the previous by > 5pp, "trending up". If each is below the previous by > 5pp, "trending down". Otherwise no trend annotation.
- Display: "Avg monthly utilization: X%" or "Avg monthly utilization: X%, trending up/down"
- If < 2 months of data: show average only, no trend
- Quiet if 20-80% average and no significant trend

### Value Summary -- "Nothing Notable" Quiet Mode

Per AC-3, when utilization is between 20-80% and there's no significant deviation or trend, the summary should be visually quiet:
- `ValueInsight.isQuiet = true` drives styling
- Text examples: "Normal usage" (7d near-average), or range-specific text rendered with muted styling
- View styling: `.font(.caption)` + `.foregroundStyle(.tertiary)` -- minimal visual weight
- Single line, no bold, no attention-grabbing colors

### AnalyticsView Integration -- Data Flow

Current flow (after Story 14.3):
```
AnalyticsView.body VStack:
  titleBar
  controlsRow (TimeRangeSelector + seriesToggles)
  UsageChart(pollData, rollupData, timeRange, ...)
  HeadroomBreakdownBar(resetEvents, creditLimits, headroomAnalysisService, selectedTimeRange)
```

After this story:
```
AnalyticsView.body VStack:
  titleBar
  controlsRow (TimeRangeSelector + seriesToggles)
  UsageChart(pollData, rollupData, timeRange, ...)
  HeadroomBreakdownBar(resetEvents, creditLimits, headroomAnalysisService, selectedTimeRange)
  ContextAwareValueSummary(timeRange, resetEvents, allTimeResetEvents, creditLimits, headroomAnalysisService)
```

New `@State` property:
```swift
@State private var allTimeResetEvents: [ResetEvent] = []
```

Add to `DataLoadResult` struct:
```swift
var allTimeResetEvents: [ResetEvent] = []
```

Add to `fetchData()` static method (after the existing reset events fetch):
```swift
let allTimeResetEvents = try await service.getResetEvents(range: .all)
// return in DataLoadResult
```

Add to `loadData()`:
```swift
allTimeResetEvents = result.allTimeResetEvents
```

### What This Story Does NOT Touch

- **Conditional bar visibility** (bar hidden when no events) -- that's Story 14.5
- **Data-span qualifier** ("X hours of data in this view") -- that's Story 14.5
- **Section collapse** (entire value section collapses to minimal height) -- that's Story 14.5
- **HeadroomAnalysisService logic** -- internals stay the same, only property names change
- **Database schema** -- no migrations, SQL column names unchanged
- **HistoricalDataService query logic** -- same SQL queries, only Swift property mapping changes
- **AnalyticsWindow / AppDelegate wiring** -- already done, no changes needed

### Existing Code to Reuse -- DO NOT Recreate

| Component | File | What It Provides |
|-----------|------|-----------------|
| `SubscriptionValueCalculator` | `cc-hdrm/Services/SubscriptionValueCalculator.swift` | `calculate()` for dollar values, `formatDollars()` for display, `periodDays()` for time range math |
| `HeadroomAnalysisServiceProtocol` | `cc-hdrm/Services/HeadroomAnalysisServiceProtocol.swift` | Protocol for DI -- pass through to ValueInsightEngine |
| `HeadroomBreakdownBar` | `cc-hdrm/Views/HeadroomBreakdownBar.swift` | Reference for integration pattern -- new summary sits below this |
| `TimeRange` | `cc-hdrm/Models/TimeRange.swift` | `.day`, `.week`, `.month`, `.all` enum with labels and timestamps |
| `AnalyticsView` | `cc-hdrm/Views/AnalyticsView.swift` | Integration target -- add summary below bar |
| `MockHeadroomAnalysisService` | `cc-hdrmTests/Mocks/MockHeadroomAnalysisService.swift` | Mock for testing ValueInsightEngine |
| `HistoricalDataServiceProtocol` | `cc-hdrm/Services/HistoricalDataServiceProtocol.swift` | `getResetEvents(range:)` for fetching all-time data |

### New Files

```
cc-hdrm/
  Services/
    ValueInsightEngine.swift              # NEW -- pure computation of context-aware insights
  Views/
    ContextAwareValueSummary.swift        # NEW -- summary view below value bar
cc-hdrmTests/
  Services/
    ValueInsightEngineTests.swift         # NEW
```

After adding new files, run `xcodegen generate`.

### Project Structure Notes

- All files follow the existing by-layer structure (Services/, Views/, Models/)
- New files follow naming convention: `TypeName.swift`, one primary type per file
- No new dependencies or frameworks required
- No changes to entitlements or Info.plist

### Git Intelligence (Recent Commits)

```
0a4f091 feat: subscription value bar with dollar-based utilization tracking (Story 14.3)
b244346 feat: headroom analysis service with code review fixes (Story 14.2)
228c307 chore: update changelog for v1.2.0 [skip ci]
fe44d63 [minor] docs: rewrite README with full feature coverage for v1.2 release
ceef79c feat: gap rendering in charts with hover tooltips (Story 13.7)
```

Story 14.3 established the dollar-based subscription value pattern. This story extends it with contextual insights and cleans up terminology.

### Previous Story (14.3) Learnings

- `SubscriptionValueCalculator` is a pure `enum` with static methods (no instance state) -- follow this same pattern for `ValueInsightEngine`
- Dollar formatting has a $10 boundary: < $10 shows cents (e.g., "$4.60"), >= $10 shows whole dollars (e.g., "$75") -- reuse `formatDollars()`
- `periodDays()` caps at actual data span for fixed ranges (prevents inflated denominators when data is sparse)
- Preview stubs for `HeadroomAnalysisServiceProtocol` exist in **both** `HeadroomBreakdownBar.swift` and `AnalyticsView.swift` (separate `#Preview` scopes, not redundant -- both need updating for rename)
- `PreferencesManager.customMonthlyPrice` was added for users with custom credit limits
- Code review found that percentage-only mode was incorrectly using 5h-relative percentages instead of 7d-prorated capacity -- the fix is already applied

### References

- [Source: `_bmad-output/planning-artifacts/epics.md:1747-1783`] -- Story 14.4 acceptance criteria
- [Source: `_bmad-output/planning-artifacts/sprint-change-proposal-2026-02-10.md:110-127`] -- Rewrite rationale and terminology change context
- [Source: `_bmad-output/implementation-artifacts/14-3-headroom-breakdown-bar-component.md`] -- Previous story with full dev notes and file list
- [Source: `cc-hdrm/Models/HeadroomBreakdown.swift`] -- HeadroomBreakdown + PeriodSummary structs (rename targets)
- [Source: `cc-hdrm/Models/ResetEvent.swift:22`] -- ResetEvent.wasteCredits (rename target)
- [Source: `cc-hdrm/Models/UsageRollup.swift:29`] -- UsageRollup.wasteCredits (rename target)
- [Source: `cc-hdrm/Services/HeadroomAnalysisService.swift`] -- Service with ~7 waste references in computation + struct inits
- [Source: `cc-hdrm/Services/SubscriptionValueCalculator.swift`] -- SubscriptionValue.wastedDollars + calculate() computation
- [Source: `cc-hdrm/Services/HistoricalDataService.swift`] -- ~16 Swift-side waste_credits property mappings (SQL column stays)
- [Source: `cc-hdrm/Views/HeadroomBreakdownBar.swift`] -- UI "Wasted" labels + preview data
- [Source: `cc-hdrm/Views/AnalyticsView.swift:85-90`] -- HeadroomBreakdownBar integration point (summary goes below)
- [Source: `cc-hdrm/Views/AnalyticsView.swift:277-284`] -- Preview stubs with waste terminology
- [Source: `cc-hdrm/Models/TimeRange.swift`] -- TimeRange enum (.day, .week, .month, .all)
- [Source: `_bmad-output/planning-artifacts/architecture.md:927-961`] -- HeadroomAnalysisService architecture
- [Source: `_bmad-output/planning-artifacts/prd.md:199-213`] -- Headroom analysis requirements (FR40)
- [Source: `_bmad-output/planning-artifacts/project-context.md`] -- Tech stack, naming conventions, project structure

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

None

### Completion Notes List

- Part 1 (Tasks 1-5): Terminology refactor completed -- 119+ occurrences of "waste" renamed to "unused" across 19 files. SQL column `waste_credits` intentionally unchanged.
- Part 2 (Tasks 6-10): Context-aware value summary feature implemented -- ValueInsightEngine (pure computation), ContextAwareValueSummary view, AnalyticsView integration.
- Build verification: 857 tests in 75 suites pass (19 new tests added).
- Fix applied: `computeUtilization()` falls back to `aggregateBreakdown.usedPercent` when `SubscriptionValueCalculator.calculate()` returns nil (no monthlyPrice).
- Code review fixes applied (see Change Log below).

### Change Log

- Tasks 1-3: Renamed `wastePercent`→`unusedPercent`, `wasteCredits`→`unusedCredits`, `wastedDollars`→`unusedDollars` across models, services, and views (8 source files)
- Task 4: Updated all test files and mocks for new terminology (10 test files)
- Task 5: Build verification -- all 838 tests pass, zero remaining "waste" property references
- Task 6: Created `cc-hdrm/Services/ValueInsightEngine.swift` -- pure enum with time-range-specific insight computation
- Task 7: Created `cc-hdrm/Views/ContextAwareValueSummary.swift` -- thin SwiftUI view wrapper with 5 previews
- Task 8: Modified `cc-hdrm/Views/AnalyticsView.swift` -- added allTimeResetEvents state, second getResetEvents call, ContextAwareValueSummary below HeadroomBreakdownBar
- Task 9: Created `cc-hdrmTests/Services/ValueInsightEngineTests.swift` (19 tests); updated `cc-hdrmTests/Views/AnalyticsViewTests.swift` for new call counts
- Task 10: Final build verification -- 857 tests in 75 suites pass
- Code review [H1]: Rewrote 4 weak ValueInsightEngine tests (weekInsightAboveAverage, weekInsightBelowAverage, allInsightTrendingUp, allInsightTrendingDown) with dynamic mock handler for deterministic assertions. Added `aggregateBreakdownHandler` to MockHeadroomAnalysisService.
- Code review [M1]: Updated 20+ test descriptions, assertion messages, and source doc comments from "waste"/"wasted" to "unused" terminology (HeadroomAnalysisServiceTests, SubscriptionValueCalculatorTests, HeadroomBreakdownBarTests, ResetEvent, HeadroomAnalysisService, HeadroomAnalysisServiceProtocol).
- Code review [M2]: Added `existingAllTimeEvents` parameter to `AnalyticsView.fetchData()` to cache allTimeResetEvents across range switches, skipping redundant DB query.
- Code review [M3]: Skip `SubscriptionValueCalculator.calculate()` in ContextAwareValueSummary when timeRange is `.all` (allInsight computes its own monthly values).
- Code review [L1-L3]: Clarified comments in ValueInsightEngine (visibility, fallback denominator) and HistoricalDataService (SQL column mapping).

### File List

**New files (3):**
- `cc-hdrm/Services/ValueInsightEngine.swift`
- `cc-hdrm/Views/ContextAwareValueSummary.swift`
- `cc-hdrmTests/Services/ValueInsightEngineTests.swift`

**Modified source files (10):**
- `cc-hdrm/Models/HeadroomBreakdown.swift` -- terminology refactor
- `cc-hdrm/Models/ResetEvent.swift` -- terminology refactor + doc comment fix [M1]
- `cc-hdrm/Models/UsageRollup.swift` -- terminology refactor
- `cc-hdrm/Services/HeadroomAnalysisService.swift` -- terminology refactor + doc comment fix [M1]
- `cc-hdrm/Services/HeadroomAnalysisServiceProtocol.swift` -- doc comment fix [M1]
- `cc-hdrm/Services/SubscriptionValueCalculator.swift` -- terminology refactor
- `cc-hdrm/Services/HistoricalDataService.swift` -- terminology refactor (SQL unchanged) + comment fix [L3]
- `cc-hdrm/Services/ValueInsightEngine.swift` -- new (Task 6) + comment fixes [L1, L2]
- `cc-hdrm/Views/HeadroomBreakdownBar.swift` -- terminology refactor
- `cc-hdrm/Views/AnalyticsView.swift` -- terminology refactor + integration + allTimeResetEvents caching [M2]
- `cc-hdrm/Views/ContextAwareValueSummary.swift` -- new (Task 7) + skip compute for .all [M3]

**Modified test/mock files (11):**
- `cc-hdrmTests/Models/HeadroomBreakdownTests.swift`
- `cc-hdrmTests/Models/ResetEventTests.swift`
- `cc-hdrmTests/Models/UsageRollupTests.swift`
- `cc-hdrmTests/Services/HeadroomAnalysisServiceTests.swift` -- terminology in test descriptions [M1]
- `cc-hdrmTests/Services/SubscriptionValueCalculatorTests.swift` -- terminology in test descriptions [M1]
- `cc-hdrmTests/Services/HistoricalDataServiceTests.swift`
- `cc-hdrmTests/Services/DatabaseManagerTests.swift`
- `cc-hdrmTests/Services/ValueInsightEngineTests.swift` -- new (Task 9) + 4 tests rewritten [H1]
- `cc-hdrmTests/Views/HeadroomBreakdownBarTests.swift` -- terminology in test descriptions [M1]
- `cc-hdrmTests/Views/AnalyticsViewTests.swift`
- `cc-hdrmTests/Views/UsageChartTests.swift`
- `cc-hdrmTests/Mocks/MockHeadroomAnalysisService.swift` -- added aggregateBreakdownHandler [H1]
