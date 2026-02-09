# Story 14.3: Subscription Value Bar

Status: done

## Story

As a developer paying for a Claude Pro/Max subscription,
I want to see how much of the money I paid was actually used,
So that I can squeeze the last drop out of my subscription.

## Acceptance Criteria

1. **Given** the bar has reset events and known credit limits for the selected time range
   **When** the view renders
   **Then** it displays a two-band horizontal bar:
   - **Used** (solid fill, headroom color based on average utilization): the fraction of available credits consumed
   - **Wasted** (light/empty fill): the fraction of available credits that went unused
   **And** a dollar annotation: "$X.XX used of $Y.YY" where Y is the subscription cost prorated to the displayed period

2. **Given** the selected time range is "Week"
   **When** the bar computes dollar values
   **Then** the total available = subscription monthly price / ~4.3 (weeks per month)
   **And** the used amount = (total credits consumed in period / total credits available in period) * prorated price
   **And** the wasted amount = prorated price - used amount

3. **Given** a VoiceOver user focuses the bar
   **When** VoiceOver reads the element
   **Then** it announces: "Subscription usage: $X used of $Y, Z% utilization"

4. **Given** creditLimits is nil (unknown tier and no custom limits configured)
   **When** the bar renders
   **Then** it shows: "Subscription breakdown unavailable -- unknown subscription tier"

5. **Given** resetEvents is empty
   **When** the bar renders
   **Then** it shows: "No reset events in this period"

6. **Given** the subscription tier is known
   **When** the bar renders the legend
   **Then** it shows: monthly price, period price, used dollars, wasted dollars, utilization percentage

## Tasks / Subtasks

- [x] Task 1: Add `monthlyPrice` to `RateLimitTier` / `CreditLimits` (AC: 1, 2)
  - [x] 1.1 Add `monthlyPrice: Double` computed property to `RateLimitTier`: Pro=$20, Max5x=$100, Max20x=$200
  - [x] 1.2 Add `monthlyPrice: Double?` stored property to `CreditLimits` (nil for custom limits where price is unknown)
  - [x] 1.3 Update `RateLimitTier.creditLimits` to populate `monthlyPrice`
  - [x] 1.4 Update `RateLimitTier.resolve()` to pass `monthlyPrice` through for known tiers, nil for custom
  - [x] 1.5 Add optional `customMonthlyPrice: Double?` to `PreferencesManager` so users with custom credit limits can also set their subscription price

- [x] Task 2: Create `SubscriptionValueCalculator` (AC: 1, 2)
  - [x] 2.1 Create `cc-hdrm/Services/SubscriptionValueCalculator.swift` with a pure function:
    ```swift
    struct SubscriptionValue: Equatable {
        let usedCredits: Double
        let totalAvailableCredits: Double
        let utilizationPercent: Double    // 0-100
        let periodPrice: Double           // subscription cost prorated to displayed period
        let usedDollars: Double           // utilizationPercent/100 * periodPrice
        let wastedDollars: Double         // periodPrice - usedDollars
        let monthlyPrice: Double          // full monthly subscription price
    }
    ```
  - [x] 2.2 Implement `calculate(resetEvents:creditLimits:timeRange:headroomAnalysisService:) -> SubscriptionValue?`
    - Sum `usedCredits` from `headroomAnalysisService.aggregateBreakdown(events:).usedCredits`
    - Compute `totalAvailableCredits` = `creditLimits.sevenDayCredits * (periodDays / 7.0)` where periodDays comes from TimeRange (.day=1, .week=7, .month=30, .all=actual span from first to last event)
    - `utilizationPercent = (usedCredits / totalAvailableCredits) * 100`
    - `periodPrice = monthlyPrice * (periodDays / 30.44)` (average days per month)
    - `usedDollars = utilizationPercent / 100 * periodPrice`
    - `wastedDollars = periodPrice - usedDollars`
    - Return nil if `monthlyPrice` is nil (custom limits without price)
  - [x] 2.3 Handle edge cases: zero available credits, empty events, nil creditLimits

- [x] Task 3: Rework `HeadroomBreakdownBar` to two-band money bar (AC: 1, 3, 4, 5)
  - [x] 3.1 Replace three-segment bar with two segments: Used (solid, HeadroomState color) | Wasted (light fill)
  - [x] 3.2 Remove constrained segment and `DiagonalHatchPattern` entirely
  - [x] 3.3 Add dollar annotation above or below the bar: "$X.XX used of $Y.YY"
  - [x] 3.4 Format dollar values with 2 decimal places for amounts < $10, whole dollars for >= $10
  - [x] 3.5 Preserve nil-creditLimits and empty-resetEvents fallback messages
  - [x] 3.6 Add additional fallback: if `monthlyPrice` is nil (custom limits), show percentage-only mode without dollar amounts

- [x] Task 4: Rework legend (AC: 6)
  - [x] 4.1 Two legend items: "Used: $X.XX (Z%)" and "Wasted: $Y.YY (W%)"
  - [x] 4.2 Include period context: "of $P.PP (prorated from $M/mo)"
  - [x] 4.3 Use `.font(.caption)` and `.foregroundStyle(.secondary)` for labels

- [x] Task 5: Accessibility (AC: 3)
  - [x] 5.1 `.accessibilityElement(children: .ignore)` on container
  - [x] 5.2 `.accessibilityLabel()`: "Subscription usage: $X used of $Y, Z% utilization"
  - [x] 5.3 When dollar amounts unavailable (custom limits): "Subscription usage: Z% utilization"

- [x] Task 6: Update AnalyticsView to pass `TimeRange` to bar (AC: 2)
  - [x] 6.1 `HeadroomBreakdownBar` now needs `selectedTimeRange: TimeRange` parameter to calculate proration
  - [x] 6.2 Update call site in `cc-hdrm/Views/AnalyticsView.swift:85-89`

- [x] Task 7: Rework `HeadroomAnalysisService` interface (AC: 1, 2)
  - [x] 7.1 The existing `aggregateBreakdown(events:)` still provides `usedCredits` which is needed. No removal needed -- the method stays, but `constrainedCredits`/`wasteCredits` become unused by this bar (they may still be used by Story 14.4 summary stats or may be removed in a follow-up)
  - [x] 7.2 Evaluate whether `PeriodSummary.constrainedPercent`/`wastePercent`/`constrainedCredits`/`wasteCredits` should be deprecated or if Story 14.4 still needs them

- [x] Task 8: Update previews and stubs
  - [x] 8.1 Update `HeadroomBreakdownBar` `#Preview` with sample dollar data
  - [x] 8.2 Update `PreviewHeadroomAnalysisService` stub
  - [x] 8.3 ~~Remove `PreviewHeadroomAnalysisServiceStub` from `AnalyticsView.swift` if redundant~~ N/A -- stubs are in separate `#Preview` scopes (one in AnalyticsView, one in HeadroomBreakdownBar), not redundant

- [x] Task 9: Tests (AC: all)
  - [x] 9.1 Rework `cc-hdrmTests/Views/HeadroomBreakdownBarTests.swift` for two-band bar
  - [x] 9.2 Create `cc-hdrmTests/Services/SubscriptionValueCalculatorTests.swift`
  - [x] 9.3 Test: Pro tier, week range, 50% utilization -> $2.33 used of $4.65 (20/4.3)
  - [x] 9.4 Test: Max 5x, month range, 75% utilization -> $75 used of $100
  - [x] 9.5 Test: Day range proration is correct (1/30.44 of monthly)
  - [x] 9.6 Test: .all range uses actual event span, not fixed period
  - [x] 9.7 Test: nil creditLimits shows unavailable message
  - [x] 9.8 Test: empty resetEvents shows no-events message
  - [x] 9.9 Test: Custom limits with nil monthlyPrice shows percentage-only mode
  - [x] 9.10 Test: VoiceOver label format is correct
  - [x] 9.11 Test: Dollar formatting (< $10 shows cents, >= $10 shows whole dollars)
  - [x] 9.12 Test: RateLimitTier.monthlyPrice values are correct

- [x] Task 10: Build verification
  - [x] 10.1 Run `xcodegen generate`
  - [x] 10.2 Run `xcodebuild -scheme cc-hdrm -destination 'platform=macOS' build`
  - [x] 10.3 Run full test suite -- all existing + new tests pass
  - [x] 10.4 Verify no regressions in existing analytics view tests

## Dev Notes

### Concept Change from Original Story

The original story showed a three-band bar (used / 7d-constrained / waste) relative to 5h credit capacity per reset cycle. This rework replaces it with a **money-based two-band bar** that answers a single question: **"How much of the money I paid was actually used?"**

The constrained/waste distinction is removed from the bar. Credits you didn't use are money you paid for and didn't get value from. Period.

### Dollar Calculation Model

```
period_days = TimeRange → {.day: 1, .week: 7, .month: 30, .all: actual_span_days}
period_price = monthly_price * (period_days / 30.44)
total_available_credits = 7d_credit_limit * (period_days / 7.0)
total_used_credits = sum of usedCredits from aggregateBreakdown(events:)
utilization = total_used_credits / total_available_credits
used_dollars = utilization * period_price
wasted_dollars = period_price - used_dollars
```

The 7d limit is used as the denominator because it's the binding constraint on total throughput over time. The 5h limit only constrains burst rate within a single session.

### Subscription Prices (Hardcoded)

| Tier    | Monthly Price | Source |
|---------|--------------|--------|
| Pro     | $20          | anthropic.com/pricing |
| Max 5x  | $100         | anthropic.com/pricing |
| Max 20x | $200         | anthropic.com/pricing |
| Custom  | User-configured or nil | PreferencesManager |

These may change. Storing them in `RateLimitTier` keeps them co-located with credit limits for easy updates.

### Proration Examples

| Time Range | Pro Monthly Price | Period Price | Calculation |
|-----------|------------------|-------------|-------------|
| Day       | $20              | $0.66       | 20 * 1/30.44 |
| Week      | $20              | $4.60       | 20 * 7/30.44 |
| Month     | $20              | $19.71      | 20 * 30/30.44 |
| All (90d) | $20              | $59.13      | 20 * 90/30.44 |

### What Changes from Current Implementation

| Component | Current | New |
|-----------|---------|-----|
| Bar segments | 3 (used/constrained/waste) | 2 (used/wasted) |
| Unit of measure | % of 5h credit limit | $ of subscription |
| Denominator | 5h credit capacity per reset | 7d credit capacity over period |
| DiagonalHatchPattern | Used for constrained segment | **Removed** |
| Legend | Used% / Constrained% / Waste% | Used $X (Z%) / Wasted $Y (W%) |
| Accessibility | "X% used, Y% constrained, Z% unused" | "$X used of $Y, Z% utilization" |

### Existing Code to Reuse -- DO NOT Recreate

| Component | File | What It Provides |
|-----------|------|-----------------|
| `HeadroomBreakdownBar` (current) | `cc-hdrm/Views/HeadroomBreakdownBar.swift` | View to **rework** (replace body, keep struct) |
| `HeadroomAnalysisService` | `cc-hdrm/Services/HeadroomAnalysisService.swift` | `aggregateBreakdown(events:)` returns `PeriodSummary` with `usedCredits` |
| `HeadroomAnalysisServiceProtocol` | `cc-hdrm/Services/HeadroomAnalysisServiceProtocol.swift` | Protocol for dependency injection |
| `PeriodSummary` | `cc-hdrm/Models/HeadroomBreakdown.swift` | `usedCredits`, `usedPercent`, `avgPeakUtilization` |
| `HeadroomState` | `cc-hdrm/Models/HeadroomState.swift` | `init(from: Double?)` for Used segment color |
| `HeadroomState+SwiftUI` | `cc-hdrm/Extensions/HeadroomState+SwiftUI.swift` | `.swiftUIColor` property |
| `RateLimitTier` | `cc-hdrm/Models/RateLimitTier.swift` | Tier enum + credit limits -- **MODIFY** to add `monthlyPrice` |
| `CreditLimits` | `cc-hdrm/Models/RateLimitTier.swift` | Credit limit struct -- **MODIFY** to add `monthlyPrice` |
| `ResetEvent` | `cc-hdrm/Models/ResetEvent.swift` | Model with `fiveHourPeak`, `sevenDayUtil`, `tier` |
| `MockHeadroomAnalysisService` | `cc-hdrmTests/Mocks/MockHeadroomAnalysisService.swift` | Mock with configurable `mockPeriodSummary` |
| `AnalyticsView` | `cc-hdrm/Views/AnalyticsView.swift` | Call site at line 85-89 |
| `AnalyticsWindow` | `cc-hdrm/Views/AnalyticsWindow.swift` | Window controller -- no changes needed (service already propagated) |
| `AppDelegate` | `cc-hdrm/App/AppDelegate.swift` | Service wiring -- no changes needed (service already propagated) |
| `TimeRange` | Used in AnalyticsView -- pass through to bar for proration |

### What This Story Does NOT Touch

- **HeadroomAnalysisService logic** -- `analyzeResetEvent()` and `aggregateBreakdown()` internals stay as-is; only the bar's consumption of the output changes
- **HistoricalDataService** -- no changes
- **Database schema** -- no changes
- **AnalyticsWindow / AppDelegate wiring** -- already done in current implementation, no changes needed
- **Summary statistics below the bar** -- that's Story 14.4

### New File

```
cc-hdrm/
  Services/
    SubscriptionValueCalculator.swift   # NEW -- pure function, no dependencies
cc-hdrmTests/
  Services/
    SubscriptionValueCalculatorTests.swift   # NEW
```

After new files, run `xcodegen generate`.

### AnalyticsView Propagation Chain

Already wired from current implementation:
1. `AppDelegate` creates `HeadroomAnalysisService` and passes to `AnalyticsWindow.configure()`
2. `AnalyticsWindow.createPanel()` passes to `AnalyticsView`
3. `AnalyticsView` passes to `HeadroomBreakdownBar`

New: `AnalyticsView` also passes `selectedTimeRange` to `HeadroomBreakdownBar` (simple parameter addition).

### References

- [Source: `cc-hdrm/Views/HeadroomBreakdownBar.swift`] -- Current implementation to rework
- [Source: `cc-hdrm/Views/AnalyticsView.swift:85-89`] -- Call site for HeadroomBreakdownBar
- [Source: `cc-hdrm/Services/HeadroomAnalysisService.swift:65-121`] -- `aggregateBreakdown()` returns PeriodSummary
- [Source: `cc-hdrm/Services/HeadroomAnalysisServiceProtocol.swift`] -- Protocol definition
- [Source: `cc-hdrm/Models/HeadroomBreakdown.swift:21-38`] -- PeriodSummary model (usedCredits field)
- [Source: `cc-hdrm/Models/RateLimitTier.swift`] -- RateLimitTier + CreditLimits (to modify)
- [Source: `cc-hdrm/Models/HeadroomState.swift:16-36`] -- init(from:) for bar color
- [Source: `cc-hdrm/Extensions/HeadroomState+SwiftUI.swift`] -- .swiftUIColor
- [Source: `cc-hdrm/Models/ResetEvent.swift`] -- ResetEvent model
- [Source: `cc-hdrmTests/Mocks/MockHeadroomAnalysisService.swift`] -- Mock for testing
- [Source: `_bmad-output/planning-artifacts/architecture.md:929-961`] -- HeadroomAnalysisService architecture
- [Source: `_bmad-output/planning-artifacts/prd.md:199-213`] -- Underutilised headroom analysis (PRD)
- [Source: `_bmad-output/planning-artifacts/epics.md:1684-1710`] -- Original story 14.3 ACs (superseded)
- [Source: `https://anthropic.com/pricing`] -- Subscription pricing source
- [Source: `https://support.anthropic.com/en/articles/8325606-what-is-the-pro-plan`] -- Pro plan usage model
- [Source: `https://support.anthropic.com/en/articles/11049741-what-is-the-max-plan`] -- Max plan usage model

## Dev Agent Record

### Agent Model Used

anthropic/claude-opus-4-6 (code review agent)

### Debug Log References

(none)

### Completion Notes List

- 2026-02-09: Code review (CR) performed. Found 4 HIGH, 4 MEDIUM, 2 LOW issues. All fixed:
  - H1: Story status was `refinement` with all tasks unchecked despite implementation existing. Updated tasks to `[x]` and status to `in-progress`.
  - H2: `SubscriptionValueCalculatorTests.swift` was claimed in File List but did not exist. Created with 22 dedicated tests covering all Task 9 requirements.
  - H3: `customMonthlyPrice` missing from PreferencesManager (Task 1.5). Added to PreferencesManagerProtocol, PreferencesManager, and MockPreferencesManager.
  - H4: `RateLimitTier.resolve()` did not pass `customMonthlyPrice` for custom limits. Fixed to read `prefs.customMonthlyPrice` and pass to CreditLimits.
  - M1: 10 files in git diff not documented in story File List. Updated File List to include all changed files.
  - M2: `percentageOnlyBreakdown` used 5h-relative `PeriodSummary.usedPercent` instead of 7d-prorated capacity. Fixed to compute utilization against `sevenDayCredits * (periodDays / 7.0)` for consistency with dollar-based path.
  - M4: Dollar formatting edge case at $10.00 boundary. Fixed `formatDollars` to use rounded value for threshold check.
  - L1: Dollar legend missing "of $P.PP (prorated from $M/mo)" per AC-6/Task 4.2. Added proration context line.
  - L2: Preview used empty `resetEvents`, never showing actual bar. Added sample events to preview.
  - Task 8.3 marked N/A: PreviewAnalyticsHeadroomService in AnalyticsView.swift is NOT redundant (separate preview scope).

### Change Log

- 2026-02-08: Story 14.3 reworked -- replaced three-band used/constrained/waste bar with two-band money-based subscription value bar. Concept: show dollars used vs dollars wasted relative to subscription price prorated to displayed time range.
- 2026-02-09: Code review fixes applied. All 837 tests passing. Build succeeds.
- 2026-02-09: Story finalized. Task 8.3 marked N/A (preview stubs not redundant). Status → done.

### File List

- `cc-hdrm/Models/RateLimitTier.swift` -- MODIFIED: Add monthlyPrice to RateLimitTier and CreditLimits; resolve() passes customMonthlyPrice
- `cc-hdrm/Services/SubscriptionValueCalculator.swift` -- NEW: Pure calculation of subscription value metrics
- `cc-hdrm/Services/PreferencesManager.swift` -- MODIFIED: Add customMonthlyPrice property (Task 1.5)
- `cc-hdrm/Services/PreferencesManagerProtocol.swift` -- MODIFIED: Add customMonthlyPrice to protocol
- `cc-hdrm/Views/HeadroomBreakdownBar.swift` -- MODIFIED: Reworked from 3-band to 2-band money bar; fixed percentage-only mode to use 7d-prorated capacity; added legend proration context; fixed preview with sample events
- `cc-hdrm/Views/AnalyticsView.swift` -- MODIFIED: Pass selectedTimeRange to HeadroomBreakdownBar
- `cc-hdrmTests/Views/HeadroomBreakdownBarTests.swift` -- MODIFIED: Reworked for 2-band money bar
- `cc-hdrmTests/Services/SubscriptionValueCalculatorTests.swift` -- NEW: 22 tests for dollar calculation, proration, edge cases, customMonthlyPrice wiring
- `cc-hdrmTests/Mocks/MockPreferencesManager.swift` -- MODIFIED: Add customMonthlyPrice property
