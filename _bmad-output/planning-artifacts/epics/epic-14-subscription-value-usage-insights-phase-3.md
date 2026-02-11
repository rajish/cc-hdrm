# Epic 14: Subscription Value & Usage Insights (Phase 3)

Alex sees the real story behind his subscription — a money-based value bar showing what he used in dollar terms, with context-aware summary insights that adapt to the selected time range.

## Story 14.1: Rate Limit Tier & Credit Limits (Absorbed into Story 3.3)

**Note:** This story's RateLimitTier enum implementation was absorbed into Story 3.3 (course correction) which required credit limits for the revised promotion rule, slope normalization, and quotas display. The enum created by Story 3.3 satisfies all requirements below and is available for Stories 14.2-14.5.

As a developer using Claude Code,
I want cc-hdrm to know the credit limits for my subscription tier,
So that headroom can be calculated in absolute terms.

**Acceptance Criteria:**

**Given** the RateLimitTier enum is defined
**When** referenced across the codebase
**Then** it includes cases: .pro, .max5x, .max20x
**And** each case provides fiveHourCredits and sevenDayCredits properties:

- Pro: 550,000 / 5,000,000
- Max 5x: 3,300,000 / 41,666,700
- Max 20x: 11,000,000 / 83,333,300

**Given** rateLimitTier is read from KeychainCredentials
**When** the tier string matches a known case (e.g., "default_claude_max_5x")
**Then** it maps to the corresponding RateLimitTier enum case

**Given** rateLimitTier doesn't match any known tier
**When** HeadroomAnalysisService needs credit limits
**Then** it checks PreferencesManager for user-configured custom credit limits
**And** if custom limits exist, uses those
**And** if no custom limits, returns nil (percentage-only analysis)
**And** a warning is logged: "Unknown rate limit tier: [tier]"

## Story 14.2: Headroom Analysis Service

> **Terminology note:** This story and Story 14.3 use pre-refactor terminology (`true_waste_credits`, `wastePercent`, etc.) in formulas and acceptance criteria. Story 14.4 defines the terminology refactor that renames these to "unused" terms. Implementers should use the post-refactor names (`unusedCredits`, `unusedPercent`, etc.) from the start — the old names here describe the _concept_, not the final variable names.

As a developer using Claude Code,
I want headroom analysis calculated at each reset event,
So that unused capacity breakdown is accurate and meaningful.

**Acceptance Criteria:**

**Given** a reset event is detected (from Story 10.3)
**When** HeadroomAnalysisService.analyzeResetEvent() is called
**Then** it calculates:

```text
5h_remaining_credits = (100% - 5h_peak%) × 5h_limit
7d_remaining_credits = (100% - 7d_util%) × 7d_limit
effective_headroom_credits = min(5h_remaining, 7d_remaining)

If 5h_remaining ≤ 7d_remaining:
    true_unused_credits = 5h_remaining
    constrained_credits = 0
Else:
    true_unused_credits = 7d_remaining
    constrained_credits = 5h_remaining - 7d_remaining
```

**And** returns a HeadroomBreakdown struct with: usedPercent, constrainedPercent, unusedPercent, usedCredits, constrainedCredits, unusedCredits

**Given** credit limits are unknown (tier not recognized, no user override)
**When** analyzeResetEvent() is called
**Then** it returns nil (analysis cannot be performed)
**And** the analytics view shows: "Headroom breakdown unavailable — unknown subscription tier"

**Given** multiple reset events in a time range
**When** HeadroomAnalysisService.aggregateBreakdown() is called
**Then** it sums used_credits, constrained_credits, and unused_credits across all events
**And** returns aggregate percentages and totals

## Story 14.3: Headroom Breakdown Bar Component

As a developer using Claude Code,
I want a three-band visualization showing used, constrained, and unused capacity,
So that the emotional framing is clear — constrained is not unused.

**Acceptance Criteria:**

**Given** HeadroomBreakdownBar is instantiated with breakdown data
**When** the view renders
**Then** it displays a horizontal stacked bar with three segments:

- **Used (▓)**: solid fill, headroom color based on the aggregate peak level
- **7d-constrained (░)**: hatched/stippled pattern, muted slate blue
- **True unused (□)**: light/empty fill, faint outline

**Given** breakdown percentages (e.g., 52% used, 12% constrained, 36% unused)
**When** the bar renders
**Then** segment widths are proportional to percentages
**And** segments are stacked left-to-right: Used | Constrained | Unused

**Given** constrained is 0%
**When** the bar renders
**Then** the constrained segment is not visible (only Used and Unused)

**Given** a VoiceOver user focuses the breakdown bar
**When** VoiceOver reads the element
**Then** it announces: "Headroom breakdown: [X]% used, [Y]% constrained by weekly limit, [Z]% unused"

## Story 14.4: Context-Aware Value Summary & Terminology Refactor

As a developer using Claude Code,
I want a context-aware summary below the subscription value bar that adapts to the selected time range,
So that I see the single most relevant insight for the data I'm looking at.

**Acceptance Criteria:**

**Given** the analytics view shows a time range with reset events
**When** the summary section renders
**Then** it selects and displays the most relevant insight for the time range:

- **24h:** Simple capacity gauge — "Used $X of $Y today" or utilization percentage if no pricing
- **7d:** Usage vs. personal average — "X% above/below your typical week"
- **30d:** Dollar summary — "Used $X of $Y this month" with utilization percentage
- **All:** Long-term trend — "Avg monthly utilization: X%" with trend direction

**Given** zero reset events exist in the selected range
**When** the summary section renders
**Then** it displays: "No reset events in this period"

**Given** nothing notable is detected (utilization between 20-80%, no trend change)
**When** the summary section renders
**Then** the summary collapses to a single quiet line (e.g., "Normal usage")
**And** does not demand visual attention

**Given** credit limits are unknown
**When** the summary section renders
**Then** it shows percentages only (no dollar values)

**Terminology refactor (technical task):**

- Rename `HeadroomBreakdown.wastePercent` → `unusedPercent`
- Rename `HeadroomBreakdown.wasteCredits` → `unusedCredits`
- Rename `SubscriptionValue.wastedDollars` → `unusedDollars`
- Update all call sites, tests, and VoiceOver labels to use neutral terminology
- Bar legend: "wasted" → "unused"

## Story 14.5: Analytics View Integration with Conditional Display

As a developer using Claude Code,
I want the subscription value bar and context-aware summary integrated into the analytics view with time-range-aware behavior,
So that the value section adapts meaningfully as I explore different time ranges.

**Acceptance Criteria:**

**Given** the analytics window is open
**When** AnalyticsView renders
**Then** the subscription value bar and context-aware summary appear below the UsageChart
**And** the value bar recalculates when the time range changes via HistoricalDataService

**Given** the selected time range changes
**When** the value section re-renders
**Then** the summary insight updates to match the new time range (per Story 14.4 rules)
**And** the value bar recalculates aggregate breakdown for the new range

**Given** the selected time range has fewer than 6 hours of data
**When** the value bar renders
**Then** it shows a qualifier: "X hours of data in this view"
**And** does not display dollar amounts (insufficient data for meaningful proration)

**Given** no reset events exist in the selected range
**When** the value section renders
**Then** the bar is hidden
**And** the summary shows: "No reset events in this period"

**Given** the value section has nothing notable to display
**When** conditional visibility evaluates
**Then** the section collapses to minimal height (single line summary only, no bar)
**And** expands again when the user selects a range with meaningful data
