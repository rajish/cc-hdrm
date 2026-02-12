# Epic 17: Extra Usage Visibility & Alerts (Phase 5)

Alex doesn't just hit the wall anymore — when his 5h or 7d plan quota runs out, Anthropic's pay-as-you-go overflow kicks in and cc-hdrm shows him exactly what it's costing. The menu bar glows amber when extra credits are burning, the popover shows a live spend bar with balance and reset date, and the analytics window reveals which cycles crossed the 100% line and by how much. Configurable alerts fire when extra spend crosses thresholds, so Alex never wakes up to a surprise bill.

## Origin

Party mode brainstorming session (2026-02-12). The data pipeline already exists — `ExtraUsage` struct (`cc-hdrm/Models/UsageResponse.swift:30-43`) with `isEnabled`, `monthlyLimit`, `usedCredits`, `utilization` is fetched from the API, persisted to SQLite (`cc-hdrm/Services/DatabaseManager.swift:240-243`), and consumed by `SubscriptionPatternDetector` and `TierRecommendationService`. What's missing is real-time visibility across all three UI layers and proactive alerting.

### Current Extra Usage Data Flow

```
Claude API /api/oauth/usage → UsageResponse.extraUsage
    → HistoricalDataService.persistPoll() → SQLite (4 columns)
    → SubscriptionPatternDetector → PatternFinding (.extraUsageOverflow, .persistentExtraUsage)
    → TierRecommendationService → cost comparisons with extra usage factored in
    → ValueInsightEngine → insight candidates (extra usage conclusion types)
```

### What's Missing

1. **AppState does not surface extra usage** to the view layer for real-time display
2. **Menu bar has no "burning extra" state** — HeadroomState only covers normal→exhausted
3. **Popover has no extra usage card** — spend bar, balance, reset date are invisible
4. **Analytics lacks crossover visualization** — no visual boundary at 100% showing when/how much the user went over
5. **Extra usage pattern notifications are disabled** — `PatternNotificationService.isNotifiableType()` returns `false` for `.extraUsageOverflow` and `.persistentExtraUsage` (`cc-hdrm/Services/PatternNotificationService.swift:60`)
6. **No threshold-based alerts** for extra usage spend levels (50%, 75%, 90% of monthly limit)

### Dependencies

- Story 16.4 introduced the billing cycle day preference — extra usage reset date derives from this
- Story 16.5 insight engine already handles extra usage conclusion candidates
- Story 16.6 CycleOverCycleBar can be extended with extra usage cost overlay

---

## Story 17.1: Extra Usage State Propagation & Menu Bar Indicator

As a developer using Claude Code,
I want the menu bar to visually distinguish "over plan quota and burning extra credits" from "exhausted and waiting for reset,"
So that I know at a glance when I'm spending real money beyond my subscription.

**Acceptance Criteria:**

**Given** `UsageResponse.extraUsage` is returned by the API
**When** `AppState` processes the poll response
**Then** the following extra usage fields are surfaced as observable properties:

- `extraUsageEnabled: Bool`
- `extraUsageMonthlyLimit: Double?`
- `extraUsageUsedCredits: Double?`
- `extraUsageUtilization: Double?`

**Given** `extraUsage.isEnabled == true` AND either the 5h or 7d plan utilization is at 100% (`.exhausted` state)
**When** the menu bar renders
**Then** the gauge icon switches to "extra usage mode":

- The gauge **repurposes** to show prepaid extra usage balance draining
- The text label shows a **currency amount** (e.g., "$27.39") representing the remaining balance, instead of a headroom percentage
- The needle direction **reverses** compared to headroom: the arc is **full on the left** and **empty on the right** — the needle sweeps left-to-right as the prepaid balance drains (opposite of headroom where full is on the right)
- This reversed direction + currency symbol makes it unmistakable that the gauge is showing prepaid balance, not plan headroom
- The arc color follows a calm→warm→hot progression as the balance drains toward zero, using colors distinct from the headroom state palette (e.g., a dedicated "extra usage" color ramp that avoids confusion with the green→yellow→orange→red headroom states)

**Given** `extraUsage.monthlyLimit` is known
**When** the gauge renders in extra usage mode
**Then** the needle position reflects remaining balance: `(monthlyLimit - usedCredits) / monthlyLimit` — full balance = needle on the left (full arc), depleted = needle on the right (empty arc)

**Given** `extraUsage.monthlyLimit` is nil (no limit set)
**When** the gauge renders in extra usage mode
**Then** the text shows the spent amount only (e.g., "$15.61 spent") and the needle position is not meaningful — use a fixed position or hide the needle

**Given** `extraUsage.isEnabled == false` AND plan utilization is at 100%
**When** the menu bar renders
**Then** it shows the existing `.exhausted` state unchanged

**Given** `extraUsage.isEnabled == true` but plan utilization is below 100%
**When** the menu bar renders
**Then** no extra usage indicator is shown — normal headroom display applies

**Given** `extraUsage` is nil (API did not return it)
**When** `AppState` processes the response
**Then** extra usage fields default to disabled/nil and no extra usage UI appears

**Given** VoiceOver is active and the menu bar is in "burning extra" state
**When** VoiceOver reads the status item
**Then** it announces: "Claude usage: extra usage active, [amount] spent of [limit]"

**Currency note:** The `ExtraUsage` API model (`cc-hdrm/Models/UsageResponse.swift:30-43`) returns `usedCredits` and `monthlyLimit` as raw `Double` values with no currency indicator. Investigation is needed during implementation to determine whether the API returns amounts in USD or the user's account currency. If the API does not include a currency field, default to `$` (USD) display. If a currency field is discovered, parse and use it.

## Story 17.2: Popover Extra Usage Card

As a developer using Claude Code,
I want the popover to show my current extra usage spend, limit, and utilization with color-coded urgency,
So that one click gives me the full picture of what I'm spending beyond my plan.

**Acceptance Criteria:**

**Given** `extraUsage.isEnabled == true` AND `extraUsage.usedCredits > 0`
**When** the popover renders
**Then** an "Extra Usage" card appears below the 7d gauge section (before the sparkline):

- A horizontal progress bar showing `usedCredits / monthlyLimit`
- Text: amount spent and monthly limit in currency (e.g., "$15.61 / $43.00") — currency determined per Story 17.1 currency note
- Utilization percentage (e.g., "37%")
- Reset context: derived from billing cycle day preference (Story 16.4), e.g., "Resets Mar 1"
- If billing cycle day is not configured: show "Set billing day in Settings for reset date"

**Given** extra usage utilization is below 50%
**When** the card renders
**Then** the progress bar fill is the standard accent color (calm)

**Given** extra usage utilization is between 50% and 75%
**When** the card renders
**Then** the progress bar fill shifts to amber

**Given** extra usage utilization is between 75% and 90%
**When** the card renders
**Then** the progress bar fill shifts to orange

**Given** extra usage utilization is above 90%
**When** the card renders
**Then** the progress bar fill shifts to red

**Given** `extraUsage.isEnabled == true` AND `extraUsage.usedCredits == 0` or is nil
**When** the popover renders
**Then** the extra usage card shows in a minimal collapsed state: "Extra usage: enabled, no spend this period"

**Given** `extraUsage.isEnabled == false` or `extraUsage` is nil
**When** the popover renders
**Then** no extra usage card is shown

**Given** `extraUsage.monthlyLimit` is nil (no limit set)
**When** the card renders
**Then** show spend amount without the progress bar and without percentage (no denominator)

**Given** VoiceOver focuses the extra usage card
**When** VoiceOver reads the element
**Then** it announces: "Extra usage: [amount] spent of [limit] monthly limit, [percentage] used, resets [date]"

## Story 17.3: Analytics Extra Usage Crossover Visualization

As a developer using Claude Code,
I want the analytics window to show when and how much I went over 100% plan utilization into extra usage,
So that I can identify patterns in my overflow spending over time.

**Acceptance Criteria:**

**Given** the analytics window is open and extra usage data exists in the selected time range
**When** the main UsageChart renders
**Then** a 100% reference line is drawn as a subtle horizontal dashed line across the chart
**And** periods where utilization was at 100% AND extra usage was active are annotated with a distinct fill or marker above the 100% line

**Given** the CycleOverCycleBar (Story 16.6) renders for a billing cycle where extra usage occurred
**When** extra usage data is available for that cycle
**Then** an additional segment appears on top of the regular utilization bar:

- Visually distinct (different color/pattern) from the plan utilization segment
- Height proportional to extra usage spend relative to base subscription cost
- Tooltip shows: "Extra: €X.XX" alongside the regular cycle tooltip

**Given** the 30d or All time range is selected and extra usage data spans multiple cycles
**When** the analytics value section renders
**Then** a summary of extra usage across cycles is available as an insight candidate:

- Total extra spend across visible cycles
- Number of cycles with overflow
- Average extra spend per overflow cycle

**Given** no extra usage data exists in the selected time range
**When** the chart renders
**Then** the 100% reference line is still shown (for context) but no extra usage annotations appear

**Given** the 24h or 7d time range is selected
**When** the chart renders
**Then** the 100% reference line is shown
**And** if current poll shows extra usage active, a subtle indicator appears at the current data point

**Given** VoiceOver focuses an extra usage annotation on the chart
**When** VoiceOver reads the element
**Then** it announces: "Extra usage active: [amount] spent this period"

## Story 17.4: Extra Usage Alerts & Configuration

As a developer using Claude Code,
I want configurable alerts when my extra usage crosses spend thresholds,
So that I'm proactively warned about overflow costs without having to check the app.

**Acceptance Criteria:**

**AC: Enable existing pattern notifications**

**Given** `PatternNotificationService.isNotifiableType()` currently returns `false` for `.extraUsageOverflow` and `.persistentExtraUsage`
**When** Story 17.4 is implemented
**Then** both pattern types return `true` (notifications enabled)
**And** notification content follows the existing `notificationTitle()` and `notificationBody()` patterns
**And** 30-day cooldown applies (consistent with other pattern notifications)

**AC: Extra usage threshold alerts**

**Given** extra usage is enabled and the user has configured alert thresholds
**When** extra usage utilization crosses a threshold (default: 50%, 75%, 90%)
**Then** a macOS notification is delivered:

- At 50%: Title "Extra usage update" / Body "You've used half your extra usage budget ([amount] of [limit])"
- At 75%: Title "Extra usage warning" / Body "Extra usage at 75% — [amount] of [limit] spent this period"
- At 90%: Title "Extra usage alert" / Body "Extra usage at 90% — [remaining] left before hitting your monthly limit"

**Given** extra usage utilization crosses from below 100% to at/above 100% (entered extra usage zone)
**When** the threshold is crossed for the first time in this billing cycle
**Then** a macOS notification is delivered:

- Title: "Extra usage started"
- Body: "Your plan quota is exhausted — extra usage is now active"
- This fires once per billing cycle (re-arms on billing cycle reset)

**Given** a threshold notification has already been sent for a given level in the current billing period
**When** utilization remains at or above that level
**Then** no duplicate notification is sent
**And** the threshold re-arms when a new billing period begins (detected via reset date or utilization dropping to 0)

**AC: Settings UI**

**Given** the settings view is open
**When** the notification section renders
**Then** an "Extra Usage Alerts" subsection appears below the existing headroom threshold settings:

- Toggle: "Extra usage alerts" (default: on if extra usage is enabled)
- Three threshold steppers: 50%, 75%, 90% (each individually toggleable)
- "Entered extra usage" alert toggle (default: on)
- Help text: "Get notified when your extra usage spending crosses these thresholds"

**Given** the user disables all extra usage alert toggles
**When** extra usage thresholds are crossed
**Then** no notifications are delivered for extra usage (pattern notifications from AC 1 still respect their own toggle)

**Given** extra usage is not enabled on the user's account
**When** the settings view renders
**Then** the "Extra Usage Alerts" subsection is hidden or shows: "Extra usage is not enabled on your Anthropic account"
