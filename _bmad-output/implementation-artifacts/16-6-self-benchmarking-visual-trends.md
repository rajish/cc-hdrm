# Story 16.6: Self-Benchmarking & Visual Trends

Status: ready-for-dev

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want my usage anchored against my own history with visual cycle-over-cycle trends,
so that raw numbers have personal context and I can spot long-term patterns at a glance.

## Acceptance Criteria

1. **Given** the analytics view is open with 30d or All time range selected
   **When** sufficient history exists (3+ billing cycles or 3+ calendar months)
   **Then** a compact cycle-over-cycle mini-bar appears showing utilization per cycle:
   - Each bar represents one billing cycle (or calendar month if billing day unset)
   - Current partial cycle is visually distinguished (lighter fill)
   - Trend direction is immediately visible without reading numbers

2. **Given** the cycle-over-cycle visualization is rendered
   **When** the user hovers over a cycle bar
   **Then** a tooltip shows: month label, utilization percentage, dollar value (if pricing known)

3. **Given** a notable personal benchmark is detected
   **When** the insight engine (Story 16.5) evaluates available insights
   **Then** self-benchmarking anchors are available as candidates:
   - "Your highest usage week since [month]"
   - "3rd consecutive month above 80% utilization"
   - "Usage down 40% from your peak in [month]"

4. **Given** fewer than 3 cycles of history exist
   **When** the cycle-over-cycle section would render
   **Then** it is hidden (insufficient data for meaningful comparison)

5. **Given** the 24h or 7d time range is selected
   **When** the analytics view renders
   **Then** the cycle-over-cycle visualization is hidden (not relevant at short ranges)

6. **Given** a VoiceOver user focuses the cycle-over-cycle visualization
   **When** VoiceOver reads the element
   **Then** it announces: "Usage trend over [N] months. [Trend summary]. Double-tap for details."

## Tasks / Subtasks

- [ ] Task 1: Create CycleUtilization model (AC: 1, 2, 4)
  - [ ] 1.1 Create `cc-hdrm/Models/CycleUtilization.swift`
  - [ ] 1.2 Define struct with: `label: String` (e.g., "Jan"), `year: Int`, `utilizationPercent: Double`, `dollarValue: Double?`, `isPartial: Bool` (current incomplete cycle), `resetCount: Int`
  - [ ] 1.3 Make `Identifiable` (id = "\(year)-\(label)") and `Sendable`

- [ ] Task 2: Create CycleUtilizationCalculator service (AC: 1, 4)
  - [ ] 2.1 Create `cc-hdrm/Services/CycleUtilizationCalculator.swift` as pure enum (same pattern as `ValueInsightEngine`)
  - [ ] 2.2 Implement `computeCycles(resetEvents:creditLimits:billingCycleDay:headroomAnalysisService:) -> [CycleUtilization]`
  - [ ] 2.3 Group reset events by billing cycle (if `billingCycleDay` set) or calendar month (if nil)
  - [ ] 2.4 For each group: compute utilization via `SubscriptionValueCalculator.calculate()`, mark last group as `isPartial: true` if within current calendar month/billing cycle
  - [ ] 2.5 Return chronologically sorted array; return empty if fewer than 3 complete cycles
  - [ ] 2.6 Reuse grouping pattern from `ValueInsightEngine.computeMonthlyUtilizations()` (lines 211-246)

- [ ] Task 3: Create CycleOverCycleBar view component (AC: 1, 2, 5)
  - [ ] 3.1 Create `cc-hdrm/Views/CycleOverCycleBar.swift`
  - [ ] 3.2 Accept `cycles: [CycleUtilization]`, `timeRange: TimeRange`
  - [ ] 3.3 Render only when `timeRange` is `.month` or `.all` AND `cycles.count >= 3`
  - [ ] 3.4 Use Swift Charts `BarMark` with one bar per cycle
  - [ ] 3.5 Color: `.headroomNormal` for complete cycles, `.headroomNormal.opacity(0.4)` for partial (current) cycle
  - [ ] 3.6 Height: fixed 60px to keep compact
  - [ ] 3.7 X-axis: month abbreviation labels (e.g., "Jan", "Feb"); hide for >12 cycles (too crowded)
  - [ ] 3.8 Y-axis: hidden (trend is enough — no need for explicit percent axis)

- [ ] Task 4: Add hover tooltip to CycleOverCycleBar (AC: 2)
  - [ ] 4.1 Add `@State private var hoveredCycle: CycleUtilization?` state
  - [ ] 4.2 Use `chartOverlay` or `AnnotationMark` for tooltip positioning
  - [ ] 4.3 Tooltip content: "Nov 2025\n72% utilization\n$14 of $20" (month + year, percentage, dollar value if available)
  - [ ] 4.4 Dollar value shows only when `dollarValue != nil`

- [ ] Task 5: Add VoiceOver accessibility to CycleOverCycleBar (AC: 6)
  - [ ] 5.1 Compute trend summary string: "rising", "falling", "stable" based on last 3 complete cycles
  - [ ] 5.2 Set `.accessibilityLabel("Usage trend over \(cycles.count) months. \(trendSummary).")`
  - [ ] 5.3 Add `.accessibilityHint("Double-tap for details")`
  - [ ] 5.4 Each bar as accessibility child element: "November 2025, 72 percent utilization, 14 dollars of 20"

- [ ] Task 6: Add self-benchmarking anchor computation (AC: 3)
  - [ ] 6.1 Add `static func computeBenchmarkAnchors(...)` to `cc-hdrm/Services/ValueInsightEngine.swift` (or `CycleUtilizationCalculator`)
  - [ ] 6.2 Detect "highest usage week since [month]": find peak week utilization and compare against historical peak
  - [ ] 6.3 Detect "N consecutive months above X% utilization": scan cycle array for runs above 80%
  - [ ] 6.4 Detect "Usage down N% from peak in [month]": compare current cycle to historical max
  - [ ] 6.5 Return as `[ValueInsight]` with `.usageDeviation` priority (integrates with Story 16.5's InsightStack)
  - [ ] 6.6 Use `NaturalLanguageFormatter` from Story 16.5 for text generation

- [ ] Task 7: Integrate CycleOverCycleBar into AnalyticsView (AC: 1, 5)
  - [ ] 7.1 Add `@State private var cycleUtilizations: [CycleUtilization] = []` to `cc-hdrm/Views/AnalyticsView.swift`
  - [ ] 7.2 Load cycles in `loadData()` after reset events are fetched
  - [ ] 7.3 Insert `CycleOverCycleBar` in the value section between `HeadroomBreakdownBar` and card/insight area
  - [ ] 7.4 Only render for `.month` and `.all` time ranges (per AC 5)
  - [ ] 7.5 Pass `preferencesManager?.billingCycleDay` to calculator for billing cycle alignment

- [ ] Task 8: Write unit tests for CycleUtilizationCalculator (AC: 1, 4)
  - [ ] 8.1 Create `cc-hdrmTests/Services/CycleUtilizationCalculatorTests.swift`
  - [ ] 8.2 Test grouping by calendar month produces correct cycle labels
  - [ ] 8.3 Test grouping with `billingCycleDay` set aligns to billing boundaries
  - [ ] 8.4 Test fewer than 3 complete cycles returns empty array
  - [ ] 8.5 Test current partial cycle has `isPartial: true`
  - [ ] 8.6 Test utilization percentages match expected values
  - [ ] 8.7 Test dollar values are populated when `creditLimits` has `monthlyPrice`

- [ ] Task 9: Write unit tests for self-benchmarking anchors (AC: 3)
  - [ ] 9.1 Add tests in same file or `cc-hdrmTests/Services/ValueInsightEngineTests.swift`
  - [ ] 9.2 Test peak detection returns "highest usage week since [month]" when current exceeds historical peak
  - [ ] 9.3 Test consecutive months detection when 3+ months above 80%
  - [ ] 9.4 Test decline detection when current is significantly below peak
  - [ ] 9.5 Test no anchors returned when insufficient history

- [ ] Task 10: Run `xcodegen generate` and verify compilation + all tests pass

## Dev Notes

### Architecture Context

This story adds a compact cycle-over-cycle visualization to the analytics value section and provides self-benchmarking anchor insights for Story 16.5's InsightStack. It builds on the existing monthly utilization computation in `ValueInsightEngine.computeMonthlyUtilizations()`.

**Key design decisions:**
- The cycle-over-cycle bar is a separate, compact component -- NOT part of the main UsageChart. It sits in the value section between HeadroomBreakdownBar and the cards/insights area.
- Uses Swift Charts `BarMark` for rendering (consistent with `BarChartView` pattern).
- Billing cycle alignment reuses `preferencesManager.billingCycleDay` from Story 16.3.
- Self-benchmarking anchors integrate with Story 16.5's `ValueInsight` and priority system. If 16.5 is not yet implemented, the anchors can be surfaced through the existing `ContextAwareValueSummary`.
- The component is intentionally compact (60px height) — it's a trend indicator, not a full chart.

### Key Integration Points

**Files consumed (read-only):**
- `cc-hdrm/Services/ValueInsightEngine.swift:211-246` -- `computeMonthlyUtilizations()` pattern for grouping events by month
- `cc-hdrm/Services/SubscriptionValueCalculator.swift:35-88` -- `calculate()` and `periodDays()` for per-cycle utilization
- `cc-hdrm/Services/HeadroomAnalysisServiceProtocol.swift` -- `aggregateBreakdown(events:)` for percentage-only fallback
- `cc-hdrm/Models/TimeRange.swift` -- `.month` and `.all` are the only ranges where the bar appears
- `cc-hdrm/Views/BarChartView.swift:76-143` -- `makeBarPoints()` grouping pattern reference
- `cc-hdrm/Services/PreferencesManagerProtocol.swift` -- `billingCycleDay: Int?` for billing cycle alignment

**Files to create:**
- `cc-hdrm/Models/CycleUtilization.swift` -- NEW, per-cycle utilization data model
- `cc-hdrm/Services/CycleUtilizationCalculator.swift` -- NEW, cycle grouping + utilization computation
- `cc-hdrm/Views/CycleOverCycleBar.swift` -- NEW, compact bar chart visualization
- `cc-hdrmTests/Services/CycleUtilizationCalculatorTests.swift` -- NEW, calculator tests

**Files to modify:**
- `cc-hdrm/Views/AnalyticsView.swift` -- add `cycleUtilizations` state, load in `loadData()`, render CycleOverCycleBar
- `cc-hdrm/Services/ValueInsightEngine.swift` -- add `computeBenchmarkAnchors()` for self-benchmarking insights

**Dependency on Story 16.5:**
- Self-benchmarking anchors (Task 6) produce `ValueInsight` entries. If Story 16.5 is implemented first, these flow into `InsightStack`. If not, they can be surfaced through existing `ContextAwareValueSummary` by extending `computeInsight()`.

### CycleOverCycleBar Design

```
Value section layout:
┌─────────────────────────────────────────────────────┐
│ HeadroomBreakdownBar                                │
│ ┌─────────────────────────────────────────────────┐ │
│ │ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ ░░░░░░░░░░░░░░░ │ │
│ └─────────────────────────────────────────────────┘ │
│                                                     │
│ CycleOverCycleBar (NEW — 60px height)               │
│ ┌─────────────────────────────────────────────────┐ │
│ │  ▓▓  ▓▓▓  ▓▓▓▓  ▓▓  ▓▓▓  ░░                   │ │
│ │  Nov  Dec  Jan   Feb  Mar  Apr                  │ │
│ └─────────────────────────────────────────────────┘ │
│                                                     │
│ PatternFindingCards / TierRecommendationCard         │
│ InsightStack (or ContextAwareValueSummary)           │
└─────────────────────────────────────────────────────┘
```

- **Bar height** encodes utilization percentage (0-100% of cycle max)
- **Bar color**: `.headroomNormal` for complete cycles; `.headroomNormal.opacity(0.4)` for current partial cycle
- **X-axis labels**: 3-letter month abbreviations; omitted for >12 cycles
- **Y-axis**: hidden (implied from bar height)
- **Hover tooltip**: positioned above hovered bar via `chartOverlay`

### Billing Cycle Alignment

When `billingCycleDay` is set (e.g., day 15):
- Cycle "Jan 2026" = Jan 15 to Feb 14
- Events are grouped by billing boundaries, not calendar months
- The current incomplete billing cycle gets `isPartial: true`

When `billingCycleDay` is nil:
- Fall back to calendar months (Jan 1-31, Feb 1-28, etc.)
- Same behavior as existing `computeMonthlyUtilizations()`

### Self-Benchmarking Anchors

Three anchor types, each producing a `ValueInsight`:

1. **Peak detection**: Compare current week's utilization against the highest historical week. If current exceeds previous peak: "Your heaviest week since [peak month]"

2. **Consecutive high months**: Scan completed cycles for runs of utilization above 80%. If 3+ consecutive: "3rd consecutive month above 80% utilization"

3. **Decline from peak**: Compare current cycle to historical maximum. If down by >30%: "Usage down [natural language amount] from your peak in [month]"

These insights integrate with Story 16.5's priority system at the `.usageDeviation` level (medium priority, above default summary but below pattern findings and tier recommendations).

### Potential Pitfalls

1. **Swift Charts import:** The main app uses Swift Charts in `StepAreaChartView` and `BarChartView`. CycleOverCycleBar should `import Charts` and use `BarMark` directly. Verify Charts framework is linked in `project.yml`.

2. **Billing cycle boundary edge cases:** When `billingCycleDay` is 29-31, some months don't have that day. The calculator should clamp to the last day of the month (use `Calendar.dateComponents` with `.day` capped).
   **Important:** The story AC specifies 1-28 range for billing day picker (Story 16.4), so days 29-31 are not possible. No clamping needed.

3. **Partial cycle detection:** The current cycle is partial if the cycle hasn't ended yet. Use `Date()` to check whether the last cycle in the array is still in progress. Don't use the last event timestamp — the cycle may have days remaining with no events yet.

4. **Minimum 3 complete cycles:** The threshold is 3 *complete* cycles, not 3 total. Exclude the partial current cycle from the count. If only 2 complete + 1 partial exist, hide the visualization.

5. **Performance with large datasets:** `computeMonthlyUtilizations()` iterates all events to group them. For "All" time range with 2+ years of data, this could be thousands of events. The grouping itself is O(n) with Dictionary and should be fine, but avoid calling it on every render — cache the result in `@State`.

6. **Coordinate with Story 16.5 dependency:** If 16.5 (InsightStack) isn't implemented yet, the benchmark anchors can temporarily augment the existing `allInsight()` text. The anchors should be designed to work with or without InsightStack.

7. **CycleOverCycleBar visibility in value section:** The bar should only appear between HeadroomBreakdownBar and the cards area. It must NOT appear when `selectedTimeRange` is `.day` or `.week`. Use a simple conditional check.

8. **VoiceOver trend summary computation:** Reuse the same trend detection logic from `ValueInsightEngine.allInsight()` (lines 189-201): compare last 3 complete cycles for rising/falling/stable pattern.

### Previous Story Intelligence

Key learnings from Stories 16.4 and earlier:
- **Calendar grouping pattern:** `ValueInsightEngine.computeMonthlyUtilizations()` groups by `DateComponents([.year, .month])`. Extend this for billing cycle alignment by computing custom start/end dates.
- **BarChartView grouping:** `makeBarPoints()` groups rollups by day using `calendar.startOfDay(for:)`. Same pattern scales to monthly grouping.
- **Swift Charts convention:** Both chart views (`StepAreaChartView`, `BarChartView`) use static content separated from hover overlay for performance.
- **Compact component precedent:** `SparklineView` is a compact 24h visualization (approx 30px height). CycleOverCycleBar at 60px follows the same "compact trend indicator" philosophy.
- **Optional parameter pattern:** AnalyticsView already accepts optional `patternDetector`, `tierRecommendationService`, `preferencesManager`. CycleOverCycleBar data flows through existing state rather than adding new parameters.

### Git Intelligence

Recent commits:
- `36e060f` (Story 16.4): TierRecommendationCard, billing cycle picker, fingerprint dismissal
- `def04b8` (Story 16.2): PatternFindingCard, notification delivery, cooldown persistence
- `b3d9d79` (PR 53): Fixed negative savings in tier cost comparison
- `5bfec97` (Story 16.1): SubscriptionPatternDetector with 6 pattern types
- `a4d1bf4` (Story 16.3): TierRecommendationService, billingCycleDay preference

### Project Structure Notes

New files to create:
```
cc-hdrm/Models/CycleUtilization.swift                      # NEW - Per-cycle utilization data model
cc-hdrm/Services/CycleUtilizationCalculator.swift           # NEW - Cycle grouping + computation
cc-hdrm/Views/CycleOverCycleBar.swift                       # NEW - Compact bar chart visualization
cc-hdrmTests/Services/CycleUtilizationCalculatorTests.swift  # NEW - Calculator tests
```

Files to modify:
```
cc-hdrm/Views/AnalyticsView.swift                           # ADD cycleUtilizations state + CycleOverCycleBar
cc-hdrm/Services/ValueInsightEngine.swift                    # ADD computeBenchmarkAnchors()
```

After adding files, run `xcodegen generate` to regenerate the Xcode project.

### References

- [Source: _bmad-output/planning-artifacts/epics/epic-16-subscription-intelligence-phase-4.md:292-331] - Story 16.6 acceptance criteria
- [Source: cc-hdrm/Services/ValueInsightEngine.swift:144-204] - allInsight() trend detection logic
- [Source: cc-hdrm/Services/ValueInsightEngine.swift:211-246] - computeMonthlyUtilizations() grouping pattern
- [Source: cc-hdrm/Views/BarChartView.swift:76-143] - makeBarPoints() calendar-based grouping
- [Source: cc-hdrm/Views/BarChartView.swift:153-198] - findGapRanges() for missing period detection
- [Source: cc-hdrm/Views/StepAreaChartView.swift:343-438] - Static content vs. hover overlay performance pattern
- [Source: cc-hdrm/Views/Sparkline.swift:323-450] - Compact visualization reference
- [Source: cc-hdrm/Services/SubscriptionValueCalculator.swift:35-88] - calculate() and periodDays() for utilization
- [Source: cc-hdrm/Models/TimeRange.swift:1-62] - TimeRange enum (only .month/.all show the bar)
- [Source: cc-hdrm/Models/ResetEvent.swift:1-24] - ResetEvent with timestamp, fiveHourPeak, sevenDayUtil
- [Source: cc-hdrm/Models/UsageRollup.swift:1-41] - UsageRollup with resolution tiers
- [Source: cc-hdrm/Views/AnalyticsView.swift:103-145] - Value section rendering order (insertion point for bar)
- [Source: cc-hdrm/Services/PreferencesManagerProtocol.swift] - billingCycleDay property
- [Source: cc-hdrm/Views/HeadroomBreakdownBar.swift:1-320] - Breakdown bar (appears above CycleOverCycleBar)
- [Source: _bmad-output/implementation-artifacts/16-5-context-aware-insight-engine.md] - Story 16.5 (InsightStack dependency for benchmark anchors)

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
