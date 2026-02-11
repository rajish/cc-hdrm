# Epic 3: Always-Visible Menu Bar Headroom

Alex glances at his menu bar and instantly knows how much headroom he has — color-coded, weight-escalated percentage that registers in peripheral vision in under one second.

## Story 3.1: Menu Bar Headroom Display with Color & Weight

As a developer using Claude Code,
I want to see my current headroom percentage in the menu bar with color-coded severity,
So that I know my remaining capacity at a glance without any interaction.

**Acceptance Criteria:**

**Given** AppState contains valid 5-hour usage data
**When** the menu bar renders
**Then** it shows Claude sparkle icon (✳) + headroom percentage (e.g., "✳ 83%")
**And** text color matches the HeadroomState color token:

- \> 40% headroom → `.headroomNormal` (muted green), Regular weight
- 20-40% → `.headroomCaution` (yellow), Medium weight
- 5-20% → `.headroomWarning` (orange), Semibold weight
- < 5% → `.headroomCritical` (red), Bold weight
- 0% → `.headroomExhausted` (red), Bold weight
- Disconnected → `.disconnected` (grey), Regular weight, shows "✳ —"
  **And** the sparkle icon color matches the text color (shifts with state)
  **And** the display updates within 2 seconds of AppState changes (NFR1)

**Given** AppState indicates disconnected, token expired, or no credentials
**When** the menu bar renders
**Then** it shows "✳ —" in grey with Regular weight

**Given** a VoiceOver user focuses the menu bar item
**When** VoiceOver reads the element
**Then** it announces "cc-hdrm: Claude headroom [X] percent, [state]"
**And** state changes trigger NSAccessibility.Notification.valueChanged

## Story 3.2: Context-Adaptive Display & Tighter Constraint Promotion

> **Note:** The 7-day promotion logic in this story (percentage-comparison rule) has been superseded by Story 3.3's credit-math-based promotion rule (`quotas_remaining < 1.0`). The countdown display and percentage formatting logic below remain valid. On unknown tiers without custom limits, Story 3.3 falls back to this story's percentage-comparison rule.

As a developer using Claude Code,
I want the menu bar to automatically switch between percentage and countdown and show whichever limit is tighter,
So that I always see the most relevant information without any manual action.

**Acceptance Criteria:**

**Given** 5-hour headroom is at 0% (exhausted) with a known reset time
**When** the menu bar renders
**Then** it shows "✳ ↻ Xm" (countdown to reset) in red, Bold weight
**And** countdown follows formatting rules: <1h "↻ 47m", 1-24h "↻ 2h 13m", >24h "↻ 2d 1h"
**And** the countdown updates every 60 seconds (not every second)

**Given** 5-hour headroom recovers above 0% (window resets)
**When** the next poll cycle updates AppState
**Then** the menu bar switches back from countdown to percentage display
**And** color transitions to the appropriate HeadroomState

**Given** 7-day headroom is lower than 5-hour headroom AND 7-day is in warning or critical state
**When** the menu bar renders
**Then** it promotes the 7-day value to the menu bar display instead of 5-hour
**And** color and weight reflect the 7-day HeadroomState

**Given** 7-day headroom recovers above the 5-hour headroom or exits warning/critical
**When** the next poll cycle updates AppState
**Then** the menu bar reverts to showing 5-hour headroom

**Given** a VoiceOver user focuses the menu bar during exhausted state
**When** VoiceOver reads the element
**Then** it announces "cc-hdrm: Claude headroom exhausted, resets in [X] minutes"

## Story 3.3: Refined 7d Promotion Rule, Credit-Math Slope Normalization & Popover Quotas Display (Course Correction)

As a developer using Claude Code,
I want the 7d headroom to promote to the menu bar only when the remaining 7d budget can't sustain one more full 5h cycle, a colored dot on the gauge icon when 7d is in caution or worse, the slope calculation normalized to credit terms so 7d slope is meaningful, and a "quotas remaining" display in the popover 7d section,
So that I always see 5h limit and slope (my primary working context), get ambient 7d awareness without losing 5h info, and can see at a glance how many 5h cycles I have left in my weekly budget.

**Course correction:** Replaces Story 3.2's promotion logic (which fired too aggressively, hiding 5h info). Also enhances Epic 11 slope calculation and absorbs Story 14.1 (RateLimitTier credit limits) as a prerequisite.

**Acceptance Criteria:**

**Given** the RateLimitTier enum is defined
**When** referenced across the codebase
**Then** it includes cases `.pro`, `.max5x`, `.max20x` with `fiveHourCredits` and `sevenDayCredits` properties (Pro: 550K/5M, Max 5x: 3.3M/41.67M, Max 20x: 11M/83.33M)
**And** maps from Keychain `rateLimitTier` strings to enum cases
**And** falls back to PreferencesManager custom limits, then nil on unknown tiers

**Given** valid credit limits are available and both 5h and 7d usage data are present
**When** `AppState.displayedWindow` is evaluated
**Then** it calculates `quotas_remaining = remaining_7d_credits / 5h_credit_limit`
**And** if `quotas_remaining < 1.0`, the 7d window is promoted to the menu bar
**And** if `quotas_remaining >= 1.0`, the 5h window is displayed
**And** on unknown tiers without override, falls back to the original Story 3.2 percentage-comparison rule

**Given** 7d is NOT promoted AND 7d headroom state is caution, warning, or critical
**When** the GaugeIcon renders
**Then** a small colored dot in the 7d HeadroomState color appears in a corner of the gauge icon

**Given** 7d IS promoted (quotas < 1)
**When** the GaugeIcon renders
**Then** a small "7d" text label appears in the corner position (replacing the dot)

**Given** valid credit limits are available
**When** `SlopeCalculationService.calculateSlope(for: .sevenDay)` is called
**Then** it normalizes: `rate = raw_7d_rate × (7d_credit_limit / 5h_credit_limit)` and maps using existing thresholds
**And** 5h slope calculation is unchanged
**And** on unknown tiers, falls back to raw percentage-based calculation

**Given** valid credit limits and the popover is open with 7d data
**When** SevenDayGaugeSection renders
**Then** it displays "X full 5h quotas left" below the countdown (always visible, verbose format)
**And** hidden when credit limits are unavailable

**Given** a VoiceOver user focuses the 7d gauge
**When** VoiceOver reads the element
**Then** it announces quotas remaining as part of the reading

_Full acceptance criteria with implementation details: see `_bmad-output/implementation-artifacts/3-3-refined-7d-promotion-credit-math-slope-normalization.md`_
