# Story 17.3: Analytics Extra Usage Crossover Visualization

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want the analytics window to show when and how much I went over 100% plan utilization into extra usage,
so that I can identify patterns in my overflow spending over time.

## Acceptance Criteria

1. **Given** the analytics window is open and extra usage data exists in the selected time range
   **When** the main UsageChart renders
   **Then** a 100% reference line is drawn as a subtle horizontal dashed line across the chart
   **And** periods where utilization was at 100% AND extra usage was active are annotated with a distinct fill or marker above the 100% line

2. **Given** the CycleOverCycleBar (Story 16.6) renders for a billing cycle where extra usage occurred
   **When** extra usage data is available for that cycle
   **Then** an additional segment appears on top of the regular utilization bar:
   - Visually distinct (different color/pattern) from the plan utilization segment
   - Height proportional to extra usage spend relative to base subscription cost
   - Tooltip shows: "Extra: $X.XX" alongside the regular cycle tooltip

3. **Given** the 30d or All time range is selected and extra usage data spans multiple cycles
   **When** the analytics value section renders
   **Then** a summary of extra usage across cycles is available as an insight candidate:
   - Total extra spend across visible cycles
   - Number of cycles with overflow
   - Average extra spend per overflow cycle

4. **Given** no extra usage data exists in the selected time range
   **When** the chart renders
   **Then** the 100% reference line is still shown (for context) but no extra usage annotations appear

5. **Given** the 24h or 7d time range is selected
   **When** the chart renders
   **Then** the 100% reference line is shown
   **And** if current poll shows extra usage active, a subtle indicator appears at the current data point

6. **Given** VoiceOver focuses an extra usage annotation on the chart
   **When** VoiceOver reads the element
   **Then** it announces: "Extra usage active: [amount] spent this period"

## Tasks / Subtasks

- [x] Task 1: Add 100% reference line to StepAreaChartView (AC: 1, 4, 5)
  - [x] 1.1 In `cc-hdrm/Views/StepAreaChartView.swift`, add a `RuleMark(y: .value("Threshold", 100))` to `StaticChartContent.body` (inside the `Chart { ... }` block, after the gap regions at line 453 but before the 5h series at line 466). Use `.foregroundStyle(Color.secondary.opacity(0.35))` and `.lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 3]))`. This renders a subtle horizontal dashed line at y=100 on the step-area chart.
  - [x] 1.2 The Y-axis domain is already `0...100` (`cc-hdrm/Views/StepAreaChartView.swift:511`), so the line sits at the top of the chart area. No domain change needed.
  - [x] 1.3 Add `.accessibilityHidden(true)` on the RuleMark -- the line is decorative context, not interactive data.

- [x] Task 2: Add 100% reference line to BarChartView (AC: 1, 4)
  - [x] 2.1 In `cc-hdrm/Views/BarChartView.swift`, add a `RuleMark(y: .value("Threshold", 100))` to `StaticBarChartContent.body` (inside the `Chart { ... }` block, after gap regions at line 346 but before the 5h bars at line 357). Same style as Task 1: `.foregroundStyle(Color.secondary.opacity(0.35))`, `.lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 3]))`.
  - [x] 2.2 The Y-axis domain is already `0...100` (`cc-hdrm/Views/BarChartView.swift:400`), so the line sits at the top edge.
  - [x] 2.3 Add `.accessibilityHidden(true)` on the RuleMark.

- [x] Task 3: Add extra usage annotations to StepAreaChartView (AC: 1, 5)
  - [x] 3.1 The `StepAreaChartView.ChartPoint` struct (`cc-hdrm/Views/StepAreaChartView.swift:158-165`) does NOT currently include extra usage fields. Add optional fields: `extraUsageActive: Bool?` and `extraUsageUsedCredits: Double?` to the struct.
  - [x] 3.2 In `StepAreaChartView.makeChartPoints(from:)` (`cc-hdrm/Views/StepAreaChartView.swift:176-200`), populate the new fields from `UsagePoll.extraUsageEnabled` and `UsagePoll.extraUsageUsedCredits`. Set `extraUsageActive = (poll.extraUsageEnabled == true && poll.fiveHourUtil != nil && poll.fiveHourUtil! >= 99.5)` -- this captures periods at 100% utilization with extra usage enabled.
  - [x] 3.3 In `StaticChartContent.body` (`cc-hdrm/Views/StepAreaChartView.swift:451-532`), after the 7d series block (line 502) and before the reset boundaries (line 504), add a new annotation layer: `ForEach(fiveHourPoints.filter { $0.extraUsageActive == true })` rendering `PointMark` at `(x: date, y: 100)` with `.symbolSize(30)` and `.foregroundStyle(Color.extraUsageCool.opacity(0.8))`. This places small colored dots at the top of the chart where extra usage is active.
  - [x] 3.4 Pass `fiveHourPoints` to `StaticChartContent` (it already receives this prop at line 345).
  - [x] 3.5 For the 24h/7d current-point indicator (AC 5): the annotation from 3.3 already handles this -- if the latest poll has `extraUsageActive == true`, the marker appears at the current data point.

- [x] Task 4: Add extra usage indicator to BarChartView tooltip (AC: 1)
  - [x] 4.1 The `BarChartView.BarPoint` struct (`cc-hdrm/Views/BarChartView.swift:31-44`) does not include extra usage data. Add an optional field: `extraUsageSpend: Double?`.
  - [x] 4.2 In `BarChartView.makeBarPoints(from:timeRange:)` (`cc-hdrm/Views/BarChartView.swift:76-143`), the method receives `[UsageRollup]` which does NOT contain extra usage data (rollups lose extra usage columns during aggregation). For now, set `extraUsageSpend = nil` -- the extra usage spend will be surfaced via the CycleOverCycleBar (Task 5) for 30d/All, not the bar chart bars. This is consistent with the epic's intent: the bar chart shows plan utilization, while extra usage appears as a stacked segment on the cycle-over-cycle bar.
  - [x] 4.3 In `BarHoverOverlayContent.tooltipView(for:)` (`cc-hdrm/Views/BarChartView.swift:515-560`), add a conditional block after the reset indicator (line 556): if `point.extraUsageSpend` is non-nil and > 0, show `Text(String(format: "Extra: $%.2f", spend))` with `.font(.caption2)` and `.foregroundStyle(Color.extraUsageCool)`. This is a no-op for now since `extraUsageSpend` is nil, but provides the integration point for future enrichment.

- [x] Task 5: Add extra usage segment to CycleOverCycleBar (AC: 2)
  - [x] 5.1 Add an `extraUsageSpend: Double?` field to `CycleUtilization` struct in `cc-hdrm/Models/CycleUtilization.swift:6-21`. Default to nil. This represents the extra usage dollar amount for the cycle.
  - [x] 5.2 In `CycleUtilizationCalculator.computeCycles()` (`cc-hdrm/Services/CycleUtilizationCalculator.swift:22-80`), after computing utilization and dollarValue per cycle group, add extra usage spend computation. This requires querying extra usage data from polls in the cycle's time range. Since `CycleUtilizationCalculator` is pure and doesn't access the database, add an optional parameter `extraUsagePerCycle: [String: Double]?` (keyed by cycle id, e.g., "2026-Jan") that maps cycle keys to total extra usage spend. When non-nil, set `extraUsageSpend` on each `CycleUtilization` from the lookup.
  - [x] 5.3 In `AnalyticsView.loadData()` (`cc-hdrm/Views/AnalyticsView.swift:242-274`), after the existing `cycleUtilizations` computation at line 262, query extra usage data from `HistoricalDataService` for the all-time reset event range. Add a new `@State private var extraUsagePerCycle: [String: Double] = [:]` to `AnalyticsView`. Compute total extra usage spend per billing cycle by querying `getRecentPolls` or a new helper method. Pass to `CycleUtilizationCalculator.computeCycles()`.
  - [x] 5.4 In `CycleOverCycleBar` (`cc-hdrm/Views/CycleOverCycleBar.swift`), modify the `chartContent` to use `Chart(cycles)` with a `ForEach` that renders TWO bar marks per cycle when `extraUsageSpend` is present: the existing utilization `BarMark` (unchanged), plus a stacked extra usage `BarMark` on top. The extra usage bar height is proportional to `extraUsageSpend / baseSubscriptionCost * 100` (converting dollars to a percentage of plan cost). Use `Color.extraUsageCool` for the extra segment. If `extraUsageSpend` is nil or 0, only the regular bar renders.
  - [x] 5.5 Update the tooltip (`cc-hdrm/Views/CycleOverCycleBar.swift:78-101`) to show "Extra: $X.XX" when `hoveredCycle?.extraUsageSpend` is non-nil and > 0.
  - [x] 5.6 Update the accessibility label helper (`cc-hdrm/Views/CycleOverCycleBar.swift:128-137`) to include extra usage text when present: "Extra usage: [amount] dollars".

- [x] Task 6: Add extra usage insight candidates to ValueInsightEngine (AC: 3)
  - [x] 6.1 In `cc-hdrm/Services/ValueInsightEngine.swift`, add a new static method `computeExtraUsageInsights(cycles: [CycleUtilization]) -> [ValueInsight]` that computes summary insights from cycle-level extra usage data.
  - [x] 6.2 Inside the method, filter cycles where `extraUsageSpend != nil && extraUsageSpend! > 0`. If none, return empty array.
  - [x] 6.3 Compute: (a) total extra spend across overflow cycles, (b) number of cycles with overflow, (c) average extra spend per overflow cycle. Format as `ValueInsight` with `priority: .usageDeviation`, `isQuiet: false`, text like: "Extra usage: $X.XX across N months (avg $Y.YY/month)". Include preciseDetail with exact amounts.
  - [x] 6.4 In `AnalyticsView.computeUsageInsight()` and the `valueSection` computed property (`cc-hdrm/Views/AnalyticsView.swift:106-144`), integrate the extra usage insights. After the existing `benchmarkAnchors` computation at line 110, add `let extraUsageInsights = ValueInsightEngine.computeExtraUsageInsights(cycles: cycleUtilizations)`. Include these in the `InsightStack` insights array (line 143).
  - [x] 6.5 Only show extra usage insights for `.month` and `.all` time ranges (where cycle data is meaningful). For `.day` and `.week`, skip the extra usage insight computation.

- [x] Task 7: Add HistoricalDataService helper for extra usage per cycle (AC: 2, 3)
  - [x] 7.1 Add a method to `HistoricalDataServiceProtocol` (`cc-hdrm/Services/HistoricalDataServiceProtocol.swift`): `func getExtraUsagePerCycle(billingCycleDay: Int?) async throws -> [String: Double]`. Returns a dictionary mapping cycle keys (e.g., "2026-Jan") to total extra usage spend.
  - [x] 7.2 Implement in `HistoricalDataService`: query `usage_polls` table for rows where `extra_usage_enabled = 1 AND extra_usage_used_credits IS NOT NULL`. Group by billing cycle (using the same logic as `CycleUtilizationCalculator.groupByBillingCycle`/`groupByCalendarMonth`). For each group, take the MAX `extra_usage_used_credits` as the cycle's total spend (since usedCredits is cumulative within a billing period, the max represents the total at period end).
  - [x] 7.3 Add the method to `MockHistoricalDataService` in `cc-hdrmTests/Mocks/MockHistoricalDataService.swift` with a `var mockExtraUsagePerCycle: [String: Double] = [:]` property.

- [x] Task 8: Add VoiceOver accessibility for extra usage annotations (AC: 6)
  - [x] 8.1 In `StepAreaChartView`, add `.accessibilityLabel()` on the extra usage `PointMark` annotations: "Extra usage active: [amount] dollars spent this period". Use the `extraUsageUsedCredits` value from the `ChartPoint`.
  - [x] 8.2 In `CycleOverCycleBar`, the accessibility label is already updated in Task 5.6.
  - [x] 8.3 In the `InsightStack`, the extra usage insight from Task 6 already includes `preciseDetail` for VoiceOver via the existing `accessibilityLabel(for:)` helper at `cc-hdrm/Views/InsightStack.swift:40-45`.

- [x] Task 9: Write unit tests for 100% reference line rendering (AC: 1, 4)
  - [x] 9.1 Add tests in `cc-hdrmTests/Views/UsageChartTests.swift` verifying that `UsageChart` renders without crash for all time ranges (existing test pattern).
  - [x] 9.2 Add tests in `cc-hdrmTests/Views/StepAreaChartTests.swift` (or extend existing) verifying `StepAreaChartView.makeChartPoints` populates `extraUsageActive` from poll data.
  - [x] 9.3 Test that `extraUsageActive` is `true` when `extraUsageEnabled == true` AND `fiveHourUtil >= 99.5`.
  - [x] 9.4 Test that `extraUsageActive` is `false` when `extraUsageEnabled == false` even if utilization is 100%.
  - [x] 9.5 Test that `extraUsageActive` is `false` when utilization is below 99.5% even if extra usage is enabled.

- [x] Task 10: Write unit tests for CycleOverCycleBar extra usage segment (AC: 2)
  - [x] 10.1 Create or extend tests in `cc-hdrmTests/Views/CycleOverCycleBarTests.swift`.
  - [x] 10.2 Test that `CycleOverCycleBar` renders without crash when cycles have non-nil `extraUsageSpend`.
  - [x] 10.3 Test that `CycleOverCycleBar` renders without crash when all cycles have nil `extraUsageSpend`.
  - [x] 10.4 Test accessibility label includes extra usage text when `extraUsageSpend > 0`.
  - [x] 10.5 Test accessibility label omits extra usage text when `extraUsageSpend` is nil.

- [x] Task 11: Write unit tests for ValueInsightEngine extra usage insights (AC: 3)
  - [x] 11.1 Add tests in `cc-hdrmTests/Services/ValueInsightEngineTests.swift`.
  - [x] 11.2 Test `computeExtraUsageInsights` returns empty when no cycles have extra usage spend.
  - [x] 11.3 Test `computeExtraUsageInsights` returns insight with correct total, count, and average when 3 of 5 cycles have extra usage.
  - [x] 11.4 Test insight text format includes dollar amounts and cycle count.
  - [x] 11.5 Test insight priority is `.usageDeviation`.

- [x] Task 12: Write unit tests for HistoricalDataService extra usage query (AC: 2, 3)
  - [x] 12.1 Add tests in `cc-hdrmTests/Services/HistoricalDataServiceTests.swift`.
  - [x] 12.2 Test `getExtraUsagePerCycle` returns empty dictionary when no extra usage data exists.
  - [x] 12.3 Test `getExtraUsagePerCycle` returns correct per-cycle totals when polls span multiple months.
  - [x] 12.4 Test billing cycle grouping with `billingCycleDay` parameter.

- [x] Task 13: Run `xcodegen generate` and verify compilation + all tests pass

## Dev Notes

### Architecture Context

This story adds the third UI surface for extra usage data: the analytics window. Stories 17.1 (menu bar) and 17.2 (popover) established the extra usage state propagation and card component patterns. Story 17.3 enhances three existing analytics components:

1. **UsageChart** (step-area + bar modes) -- adds a 100% reference line and extra usage point annotations
2. **CycleOverCycleBar** (Story 16.6) -- adds stacked extra usage segment per billing cycle
3. **ValueInsightEngine** (Story 16.5) -- adds extra usage summary insight candidates

**Key design decisions:**
- The 100% reference line is always shown (even without extra usage data) as it provides useful plan-limit context for all users.
- Extra usage annotations on the step-area chart are simple point markers (not filled regions above 100%) because the Y-axis domain is `0...100` and extending it would distort the scale. The markers sit at y=100 with a distinct color to indicate overflow periods.
- The CycleOverCycleBar gets stacked bars rather than separate bars because the extra usage spend is conceptually "on top of" the plan utilization -- it shows the total cost beyond the base subscription.
- Extra usage insights only appear for 30d/All time ranges where cycle-level data is meaningful. For 24h/7d, the point annotations on the chart serve the role instead.

### Chart Rendering Pipeline

**StepAreaChartView** (24h mode):
- `cc-hdrm/Views/StepAreaChartView.swift` -- main view
- Data flows: `[UsagePoll]` -> `makeChartPoints()` -> `[ChartPoint]` -> `StaticChartContent` -> Swift Charts
- Performance split: `StaticChartContent` (marks, never re-evaluates on hover) vs `HoverOverlayContent` (tooltip, redraws on hover)
- Chart marks are layered: gap regions (bottom) -> 5h area + line -> 7d line -> reset boundaries (top)
- The 100% reference line and extra usage annotations insert into this layer stack
- Y-axis domain: `0...100` (fixed, `cc-hdrm/Views/StepAreaChartView.swift:511`)
- `ChartPoint` carries: `id`, `date`, `fiveHourUtil`, `sevenDayUtil`, `slopeLevel`, `segment`

**BarChartView** (7d/30d/All modes):
- `cc-hdrm/Views/BarChartView.swift` -- main view
- Data flows: `[UsageRollup]` -> `makeBarPoints()` -> `[BarPoint]` -> `StaticBarChartContent` -> Swift Charts
- Same performance split as StepAreaChartView
- Y-axis domain: `0...100` (fixed, `cc-hdrm/Views/BarChartView.swift:400`)
- Bars use `RectangleMark` with explicit temporal boundaries (not `BarMark`)

**UsageChart** (container):
- `cc-hdrm/Views/UsageChart.swift` -- delegates to StepAreaChartView for `.day`, BarChartView for `.week`/`.month`/`.all`
- No direct chart rendering -- pure routing

### CycleOverCycleBar Architecture (Story 16.6)

- `cc-hdrm/Views/CycleOverCycleBar.swift` -- compact 60px bar chart using Swift Charts `BarMark`
- Only renders for `.month` and `.all` time ranges with 3+ cycles
- Uses `CycleUtilization` model (`cc-hdrm/Models/CycleUtilization.swift`)
- Data computed by `CycleUtilizationCalculator` (`cc-hdrm/Services/CycleUtilizationCalculator.swift`)
- Tooltip shows month, utilization%, and optional dollar value
- Current implementation: single `BarMark` per cycle, color varies by partial flag
- For extra usage: needs a second stacked `BarMark` per cycle with height proportional to extra usage spend. Swift Charts supports stacking via the `stacking:` modifier or separate BarMarks with the same x-axis key.

### Extra Usage Data Flow

Extra usage data is already persisted to SQLite by `HistoricalDataService.persistPoll()` (`cc-hdrm/Services/HistoricalDataService.swift:51-188`). The `usage_polls` table has these columns (schema v3, `cc-hdrm/Services/DatabaseManager.swift:240-243`):
- `extra_usage_enabled INTEGER` -- 0/1 flag
- `extra_usage_monthly_limit REAL` -- dollar limit
- `extra_usage_used_credits REAL` -- dollars used (cumulative within billing period)
- `extra_usage_utilization REAL` -- 0-1 fraction

**Key query patterns:**
- `getRecentPolls(hours:)` already returns extra usage fields via `readPollRow()` (`cc-hdrm/Services/HistoricalDataService.swift:390-422`)
- `UsagePoll` struct already has `extraUsageEnabled`, `extraUsageMonthlyLimit`, `extraUsageUsedCredits`, `extraUsageUtilization` fields (`cc-hdrm/Models/UsagePoll.swift:17-24`)
- For per-cycle extra usage: query MAX(extra_usage_used_credits) per billing cycle from usage_polls (cumulative, so max = total for the period)

### ValueInsightEngine Architecture (Story 16.5)

- `cc-hdrm/Services/ValueInsightEngine.swift` -- pure computation, no side effects
- Returns `ValueInsight` with `text`, `isQuiet`, `priority`, `preciseDetail`
- Priority levels: `.patternFinding` (3) > `.tierRecommendation` (2) > `.usageDeviation` (1) > `.summary` (0)
- Existing multi-insight API: `computeInsights()` aggregates pattern findings, tier recommendations, usage insights, and benchmark anchors
- For extra usage: add `computeExtraUsageInsights(cycles:)` at `.usageDeviation` priority
- `InsightStack` (`cc-hdrm/Views/InsightStack.swift`) displays up to 2 prioritized insights with primary/secondary styling

### Previous Story Intelligence

Key learnings from Stories 17.1 and 17.2:
- **Extra usage color tokens** are defined in `cc-hdrm/Extensions/Color+Headroom.swift`: `Color.extraUsageCool`, `.extraUsageWarm`, `.extraUsageHot`, `.extraUsageCritical`. Use `Color.extraUsageCool` (blue-teal) for the extra usage chart annotations and bar segments -- it's the "calm" color that contrasts well with the green headroom and blue 7d series.
- **Currency formatting**: `String(format: "$%.2f", amount)` per Story 17.1 convention. `SubscriptionValueCalculator.formatDollars()` is the existing helper used by CycleOverCycleBar tooltip.
- **AppState extra usage properties** (`cc-hdrm/State/AppState.swift:52-56`): `extraUsageEnabled`, `extraUsageMonthlyLimit`, `extraUsageUsedCredits`, `extraUsageUtilization`.
- **Test patterns**: View tests use `@MainActor`, `NSHostingController`, `_ = controller.view` for layout. Service tests use `MockHistoricalDataService`, `MockHeadroomAnalysisService`.

### Potential Pitfalls

1. **Y-axis domain 0...100 vs extra usage above 100%**: The charts fix Y-axis at 0-100. Extra usage annotations must NOT extend the Y-axis beyond 100 -- this would compress all existing data into a smaller region. Instead, use point markers AT y=100 to indicate overflow, not bars/areas above 100. The CycleOverCycleBar is the only component that visually shows extra usage magnitude (as a stacked segment), and it uses its own Y-axis.

2. **CycleOverCycleBar stacking**: Swift Charts `BarMark` supports stacking with `.position(by:)`, but `CycleOverCycleBar` currently uses plain `BarMark(x:y:)` without stacking. Adding a second BarMark for extra usage requires either: (a) switching to stacked BarMark with a series discriminator, or (b) using two separate ForEach loops with explicit y-offsets. Option (b) is simpler: render the utilization bar first, then overlay extra usage bars with `yStart` at the utilization value and `yEnd` at utilization + extra percentage. The Y-axis may need to grow beyond 100 for CycleOverCycleBar -- this is acceptable since it's a separate 60px trend chart, not the main chart.

3. **Extra usage usedCredits is cumulative**: Within a billing period, `extra_usage_used_credits` grows monotonically. To get total spend per cycle, take `MAX(extra_usage_used_credits)` within the cycle's date range, NOT `SUM`. If the billing period resets (usedCredits drops to 0), the cycle boundary already handles this.

4. **Missing extra usage data in older polls**: Polls before schema v3 migration have NULL extra usage columns. All queries must handle NULL gracefully -- treat NULL `extraUsageEnabled` as `false`, NULL `extraUsageUsedCredits` as 0.

5. **RuleMark at y=100 rendering**: `RuleMark(y:)` draws a horizontal line across the full chart width. Verify it renders correctly with the `chartYScale(domain: 0...100)` -- it should sit exactly at the top of the chart area. If it's clipped by the chart bounds, use `chartYScale(domain: 0...101)` with a 1% buffer, but this should be a last resort.

6. **Thread safety for extra usage per-cycle query**: The `getExtraUsagePerCycle` method runs on a background thread (async). Ensure the result is assigned to `@State` on the main actor (which SwiftUI does automatically via `.task`).

7. **CycleOverCycleBar Y-axis scaling**: The existing chart uses `chartYAxis(.hidden)` and lets Swift Charts auto-scale. When adding extra usage bars on top of utilization bars, the combined height may exceed 100. This is fine -- the auto-scaling accommodates it. But ensure the partial-cycle opacity logic (`cycle.isPartial ? .opacity(0.4) : full`) also applies to the extra usage segment.

### Key Integration Points

**Files consumed (read-only):**
- `cc-hdrm/State/AppState.swift:52-56` -- Extra usage state properties
- `cc-hdrm/Models/UsagePoll.swift:17-24` -- Extra usage fields on poll model
- `cc-hdrm/Models/CycleUtilization.swift` -- Cycle model (to extend)
- `cc-hdrm/Extensions/Color+Headroom.swift:119-131` -- `Color.extraUsageCool` and `Color.extraUsageColor(for:)` SwiftUI helpers
- `cc-hdrm/Services/DatabaseManager.swift:240-243` -- Schema v3 extra usage columns
- `cc-hdrm/Services/HistoricalDataService.swift:390-422` -- `readPollRow()` extra usage extraction
- `cc-hdrm/Services/CycleUtilizationCalculator.swift` -- Pure cycle computation
- `cc-hdrm/Views/InsightStack.swift` -- Insight display component

**Files to modify:**
- `cc-hdrm/Views/StepAreaChartView.swift` -- Add 100% reference line + extra usage point annotations + extend ChartPoint struct
- `cc-hdrm/Views/BarChartView.swift` -- Add 100% reference line + extend BarPoint struct + tooltip
- `cc-hdrm/Views/CycleOverCycleBar.swift` -- Add stacked extra usage segment + tooltip + accessibility
- `cc-hdrm/Models/CycleUtilization.swift` -- Add `extraUsageSpend: Double?` field
- `cc-hdrm/Services/CycleUtilizationCalculator.swift` -- Accept and propagate extra usage per cycle
- `cc-hdrm/Services/ValueInsightEngine.swift` -- Add `computeExtraUsageInsights(cycles:)` method
- `cc-hdrm/Views/AnalyticsView.swift` -- Wire extra usage data loading + insight integration
- `cc-hdrm/Services/HistoricalDataServiceProtocol.swift` -- Add `getExtraUsagePerCycle` method
- `cc-hdrm/Services/HistoricalDataService.swift` -- Implement `getExtraUsagePerCycle` query

**Files to create:**
- `cc-hdrmTests/Views/CycleOverCycleBarTests.swift` -- Tests for extra usage segment (if not existing)

**Test files to modify:**
- `cc-hdrmTests/Views/UsageChartTests.swift` -- Add 100% reference line tests
- `cc-hdrmTests/Services/ValueInsightEngineTests.swift` -- Add extra usage insight tests
- `cc-hdrmTests/Services/HistoricalDataServiceTests.swift` -- Add extra usage per-cycle query tests
- `cc-hdrmTests/Mocks/MockHistoricalDataService.swift` -- Add mock method

After adding any new Swift files, run `xcodegen generate` to regenerate the Xcode project.

### References

- [Source: _bmad-output/planning-artifacts/epics/epic-17-extra-usage-visibility-alerts-phase-5.md:139-179] -- Story 17.3 acceptance criteria
- [Source: cc-hdrm/Views/StepAreaChartView.swift:158-165] -- ChartPoint struct (to extend with extra usage)
- [Source: cc-hdrm/Views/StepAreaChartView.swift:451-532] -- StaticChartContent.body (insertion point for 100% line and annotations)
- [Source: cc-hdrm/Views/StepAreaChartView.swift:176-200] -- makeChartPoints() data transformation
- [Source: cc-hdrm/Views/StepAreaChartView.swift:511] -- Y-axis domain (0...100)
- [Source: cc-hdrm/Views/BarChartView.swift:299-438] -- StaticBarChartContent.body (insertion point for 100% line)
- [Source: cc-hdrm/Views/BarChartView.swift:31-44] -- BarPoint struct (to extend)
- [Source: cc-hdrm/Views/BarChartView.swift:400] -- Y-axis domain (0...100)
- [Source: cc-hdrm/Views/BarChartView.swift:515-560] -- BarHoverOverlayContent.tooltipView (tooltip extension)
- [Source: cc-hdrm/Views/CycleOverCycleBar.swift:1-151] -- CycleOverCycleBar component
- [Source: cc-hdrm/Views/CycleOverCycleBar.swift:30-74] -- chartContent with BarMark
- [Source: cc-hdrm/Views/CycleOverCycleBar.swift:78-101] -- tooltipView
- [Source: cc-hdrm/Views/CycleOverCycleBar.swift:128-137] -- accessibilityLabel helper
- [Source: cc-hdrm/Models/CycleUtilization.swift:6-21] -- CycleUtilization struct
- [Source: cc-hdrm/Services/CycleUtilizationCalculator.swift:22-80] -- computeCycles()
- [Source: cc-hdrm/Services/ValueInsightEngine.swift:41-75] -- computeInsight() main method
- [Source: cc-hdrm/Services/ValueInsightEngine.swift:460-531] -- computeBenchmarkAnchors() pattern for multi-insight
- [Source: cc-hdrm/Views/AnalyticsView.swift:106-144] -- valueSection computed property
- [Source: cc-hdrm/Views/AnalyticsView.swift:242-274] -- loadData() where cycle utilizations are computed
- [Source: cc-hdrm/Views/InsightStack.swift:1-46] -- InsightStack display component
- [Source: cc-hdrm/Models/UsagePoll.swift:17-24] -- Extra usage fields on poll model
- [Source: cc-hdrm/Services/HistoricalDataService.swift:51-188] -- persistPoll() with extra usage columns
- [Source: cc-hdrm/Services/HistoricalDataService.swift:190-232] -- getRecentPolls() returning extra usage data
- [Source: cc-hdrm/Services/HistoricalDataService.swift:390-422] -- readPollRow() with extra usage extraction
- [Source: cc-hdrm/Services/DatabaseManager.swift:231-252] -- usage_polls CREATE TABLE with extra usage columns
- [Source: cc-hdrm/State/AppState.swift:52-56] -- Extra usage state properties
- [Source: cc-hdrm/Extensions/Color+Headroom.swift:119-131] -- SwiftUI Color extra usage statics and Color.extraUsageColor(for:)

## Dev Agent Record

### Implementation Summary

All 13 tasks implemented across 14 production files and 5 test files. The implementation adds extra usage crossover visualization to the analytics window through three surfaces:

1. **100% reference line** on both StepAreaChartView and BarChartView (dashed line at y=100)
2. **Extra usage point annotations** on StepAreaChartView (colored dots at y=100 where extra usage is active)
3. **Stacked extra usage segment** on CycleOverCycleBar (proportional to spend vs base cost)
4. **Extra usage insights** in ValueInsightEngine (total spend, overflow count, average per cycle)
5. **HistoricalDataService helper** for querying MAX(extra_usage_used_credits) per billing cycle

### Test Results

1128 tests across 95 suites -- all passing.

### File List

**Modified production files:**
- `cc-hdrm/Models/CycleUtilization.swift` -- Added `extraUsageSpend: Double?` field
- `cc-hdrm/Services/CycleUtilizationCalculator.swift` -- Added `extraUsagePerCycle` parameter to `computeCycles()`
- `cc-hdrm/Services/HistoricalDataServiceProtocol.swift` -- Added `getExtraUsagePerCycle` method
- `cc-hdrm/Services/HistoricalDataService.swift` -- Implemented `getExtraUsagePerCycle` query
- `cc-hdrm/Services/ValueInsightEngine.swift` -- Added `computeExtraUsageInsights(cycles:)` method
- `cc-hdrm/Views/StepAreaChartView.swift` -- 100% RuleMark, ChartPoint extra usage fields, PointMark annotations
- `cc-hdrm/Views/BarChartView.swift` -- 100% RuleMark, BarPoint extra usage field, tooltip line
- `cc-hdrm/Views/CycleOverCycleBar.swift` -- Stacked extra usage BarMark, tooltip, accessibility label
- `cc-hdrm/Views/AnalyticsView.swift` -- Extra usage data loading, insight integration, preview stub

**Created test files:**
- `cc-hdrmTests/Views/CycleOverCycleBarTests.swift` -- 6 tests for extra usage segment rendering

**Modified test files:**
- `cc-hdrmTests/Mocks/MockHistoricalDataService.swift` -- Added `mockExtraUsagePerCycle` and stub method
- `cc-hdrmTests/Services/PollingEngineTests.swift` -- Added protocol conformance stub to `PEMockHistoricalDataService`
- `cc-hdrmTests/Views/UsageChartTests.swift` -- 5 new tests for extra usage annotations
- `cc-hdrmTests/Services/ValueInsightEngineTests.swift` -- 6 new tests for extra usage insights
- `cc-hdrmTests/Services/HistoricalDataServiceTests.swift` -- 4 new tests for `getExtraUsagePerCycle`

### Change Log

- Tasks 1-2: Added 100% reference RuleMark to StepAreaChartView and BarChartView
- Task 3: Extended ChartPoint with extra usage fields, populated from poll data, added PointMark annotations with VoiceOver labels, preserved fields in enforceMonotonicWithinSegments
- Task 4: Extended BarPoint with extraUsageSpend field, added conditional tooltip line
- Task 5: Extended CycleUtilization with extraUsageSpend, added extraUsagePerCycle parameter to calculator, wired data loading in AnalyticsView, added stacked BarMark segment with tooltip and accessibility
- Task 6: Added computeExtraUsageInsights method to ValueInsightEngine, integrated into AnalyticsView valueSection for .month/.all ranges
- Task 7: Added getExtraUsagePerCycle to protocol, implementation (MAX per billing cycle), mock, and preview stub
- Task 8: VoiceOver covered by PointMark accessibilityLabel (Task 3) and CycleOverCycleBar accessibilityLabel (Task 5)
- Tasks 9-12: Comprehensive unit tests (21 new tests total)
- Task 13: XcodeGen regenerated, build succeeded, all 1128 tests pass
