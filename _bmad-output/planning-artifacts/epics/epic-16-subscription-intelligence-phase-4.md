# Epic 16: Subscription Intelligence (Phase 4)

Alex doesn't just see what happened — cc-hdrm tells him what it means. Slow-burn patterns surface as macOS notifications before they become costly surprises. Tier recommendations answer "am I on the right plan?" with concrete numbers. Over time, the analytics view learns to present the single most relevant conclusion from multiple valid lenses, anchored against Alex's own usage history.

## Brainstorming Origin

This epic implements Themes 2–5 from the brainstorming session (2026-02-09):

- Theme 1 (Denominator Fix): Completed in Story 14.3 (PR 41)
- Theme 2 (Slow-Burn Pattern Detection): Stories 16.1–16.2
- Theme 3 (API Pricing & Tier Recommendation): Stories 16.3–16.4
- Theme 4 (Multiple Conclusions from Same Data): Story 16.5
- Theme 5 (Self-Benchmarking & Visual Trends): Story 16.6

**Extra Usage Addendum (2026-02-10):** Stories 16.1, 16.3, 16.4, 16.5 enriched with extra usage awareness per revised sprint change proposal. Anthropic's pay-as-you-go overflow pricing means the cost model is no longer flat-rate. The API already returns `extra_usage` data and PR 43 already persists it to SQLite.

## Story 16.1: Slow-Burn Pattern Detection Service

As a developer using Claude Code,
I want cc-hdrm to detect slow-burn subscription patterns from my usage history,
So that costly patterns are caught before they become expensive surprises.

**Acceptance Criteria:**

**Given** SubscriptionPatternDetector is initialized with access to ResetEvent history and extra usage history
**When** analyzePatterns() is called (triggered after each reset event detection)
**Then** it evaluates the following pattern rules against historical data:

**Pattern: Forgotten Subscription**
**Given** utilization is below 5% for 2+ consecutive weeks (14+ days)
**When** the pattern is detected
**Then** it returns a .forgottenSubscription finding with:

- Duration of low usage (in weeks)
- Average utilization during the period
- Monthly cost being incurred

**Pattern: Chronic Overpaying**
**Given** total cost (base subscription + extra usage charges) fits within a cheaper tier for 3+ consecutive months
**When** the pattern is detected
**Then** it returns a .chronicOverpaying finding with:

- Current tier and monthly cost (base + extra usage)
- Recommended tier and monthly cost
- Potential monthly savings

**Pattern: Chronic Underpowering**
**Given** the user has been rate-limited (hit 100% on either window) more than N times per billing cycle for 2+ consecutive cycles
**When** the pattern is detected
**Then** it returns a .chronicUnderpowering finding with:

- Rate-limit frequency
- Current tier
- Suggested higher tier
- If extra usage is enabled and absorbing overflows: pattern triggers on cost (base + extra usage exceeds higher tier's base price), not rate-limits alone

**Pattern: Usage Decay**
**Given** monthly utilization has declined for 3+ consecutive months
**When** the pattern is detected
**Then** it returns a .usageDecay finding with:

- Trend direction and magnitude
- Current vs. 3-month-ago utilization

**Pattern: Extra Usage Overflow**
**Given** extra_usage.is_enabled == true and extra_usage.used_credits > 0 for 2+ consecutive billing periods
**When** the pattern is detected
**Then** it returns a .extraUsageOverflow finding with:

- Overflow frequency and average extra spend per period
- Higher tier that would have covered usage without overflow
- Estimated savings (higher tier base price vs. current base + extra usage)

**Pattern: Persistent Extra Usage**
**Given** extra_usage spending exceeds 50% of base subscription price for 2+ consecutive months
**When** the pattern is detected
**Then** it returns a .persistentExtraUsage finding with:

- Average monthly extra usage spend
- Base subscription price
- Recommended tier and total cost comparison

**Given** no patterns are detected
**When** analyzePatterns() completes
**Then** it returns an empty findings array

**Given** insufficient history to evaluate a pattern (e.g., less than 2 weeks of data)
**When** that pattern is evaluated
**Then** it is skipped (not reported as negative finding)

**Given** extra usage patterns are evaluated but extra_usage.is_enabled == false or used_credits data is nil
**When** extra usage patterns are checked
**Then** they are skipped (insufficient data)

## Story 16.2: Pattern Notification & Analytics Display

As a developer using Claude Code,
I want slow-burn pattern findings to surface as macOS notifications and appear in the analytics view,
So that I'm alerted to costly patterns even when I'm not looking at the app.

**Acceptance Criteria:**

**Given** SubscriptionPatternDetector returns a .forgottenSubscription finding
**When** the finding is new (not previously notified)
**Then** a macOS notification is delivered:

- Title: "Subscription check-in"
- Body: "You've used less than 5% of your Claude capacity for [N] weeks. Worth reviewing?"
- Action: Opens analytics window

**Given** SubscriptionPatternDetector returns a .chronicOverpaying finding
**When** the finding is new (not previously notified)
**Then** a macOS notification is delivered:

- Title: "Tier recommendation"
- Body: "Your usage fits [recommended tier] — you could save $[amount]/mo"
- Action: Opens analytics window

**Given** SubscriptionPatternDetector returns a .chronicUnderpowering finding
**When** the finding is new (not previously notified)
**Then** a macOS notification is delivered:

- Title: "Tier recommendation"
- Body: "You've been rate-limited [N] times recently. [higher tier] would cover your usage."
- Action: Opens analytics window

**Given** a pattern finding has already been notified
**When** the same pattern is detected again within 30 days
**Then** no duplicate notification is sent
**And** the cooldown period is tracked in UserDefaults

**Given** the analytics window is open and pattern findings exist
**When** the value section renders
**Then** active findings appear as a compact insight card below the subscription value bar
**And** each card shows the finding summary in natural language
**And** cards are dismissable (dismissed state persisted)

**Given** the user has disabled notifications in system preferences
**When** a pattern is detected
**Then** findings still appear in the analytics view
**And** no macOS notification is attempted

## Story 16.3: Tier Recommendation Service

As a developer using Claude Code,
I want cc-hdrm to compare my actual usage against all available tiers,
So that I know whether I'm on the right plan with concrete dollar figures.

**Acceptance Criteria:**

**Given** TierRecommendationService is initialized with access to ResetEvent history, RateLimitTier data, and extra usage history
**When** recommendTier() is called with a time range
**Then** it compares actual usage against each tier using total cost:

- For each tier: would this tier's 5h and 7d limits have covered the user's usage?
- Safety margin: requires 20% headroom above actual peak usage (configurable)
- **Total cost comparison:** for each tier, computes `total = base_price + estimated_extra_usage`. If usage fits within a tier's limits, extra usage = $0. If usage exceeds limits and extra usage is enabled, includes actual or estimated overflow cost at API rates.

**Given** the user's usage fits a cheaper tier with safety margin
**When** the recommendation is computed
**Then** it returns a .downgrade recommendation with:

- Current tier name and monthly total cost (base + extra usage if applicable)
- Recommended tier name and monthly total cost
- Monthly savings
- Confidence note: "Based on [N] weeks of usage data"

**Given** the user has been rate-limited or is paying extra usage overflow, and a higher tier would have been cheaper
**When** the recommendation is computed
**Then** it returns a .upgrade recommendation with:

- Current tier name and monthly total cost (base + extra usage)
- Recommended tier name and monthly price
- Number of rate-limit events that would have been avoided
- Cost comparison: e.g., "On Pro ($20/mo) you paid ~$47 in extra usage ($67 total) — Max 5x ($100/mo) would have covered you and saved $67"

**Given** the user is on the best-fit tier
**When** the recommendation is computed
**Then** it returns a .goodFit recommendation with:

- Current tier name
- Headroom percentage remaining
- Brief confirmation: no action needed

**Given** fewer than 2 weeks of usage data exist
**When** recommendTier() is called
**Then** it returns nil (insufficient data for a meaningful recommendation)

**Given** billing cycle day is configured in preferences
**When** the recommendation is computed
**Then** it aligns analysis to complete billing cycles where possible
**And** flags the current partial cycle as provisional

**Given** extra usage data is unavailable (is_enabled = false or no data)
**When** the recommendation is computed
**Then** it falls back to credit-only comparison (pre-extra-usage behavior)

## Story 16.4: Tier Recommendation Display & Billing Cycle Preference

As a developer using Claude Code,
I want to see tier recommendations in the analytics view and configure my billing cycle day,
So that recommendations are grounded in my actual billing periods and visible when relevant.

**Acceptance Criteria:**

**Given** TierRecommendationService returns a .downgrade or .upgrade recommendation
**When** the analytics view renders
**Then** a recommendation card appears below the subscription value bar (after any pattern findings from 16.2):

- Natural language summary (e.g., "Your usage fits Pro ($20/mo) — you'd save $80/mo")
- When extra usage data exists: card shows total cost breakdown (e.g., "Base: $20 + Extra: $47 = $67 total")
- When recommending tier change with extra usage context: shows comparison (e.g., "Max 5x at $100/mo would have covered this with no extra charges")
- Based-on context: "Based on 12 weeks of usage data"
- Card is dismissable (dismissed state persisted, re-shown if recommendation changes)

**Given** TierRecommendationService returns a .goodFit recommendation
**When** the analytics view renders
**Then** no card is shown (conditional visibility — quiet when nothing actionable)

**Given** the settings view is open
**When** SettingsView renders
**Then** a "Billing" section appears with:

- Billing cycle day: picker with values 1–28
- Help text: "Day of month your Anthropic subscription renews. Enables accurate monthly summaries."
- Default: nil (unset)

**Given** billing cycle day is configured
**When** the subscription value bar renders for 30d or All time ranges
**Then** dollar summaries align to complete billing cycles
**And** the current partial cycle is visually distinguished (e.g., lighter fill or "so far" qualifier)

**Given** billing cycle day is not configured
**When** tier recommendation or subscription value renders
**Then** calculations use calendar months as approximation
**And** settings shows a subtle hint: "Set your billing day for more accurate insights"

## Story 16.5: Context-Aware Insight Engine (Future Iteration)

As a developer using Claude Code,
I want the analytics value section to choose the single most relevant conclusion from multiple valid lenses,
So that the display tells me what matters most right now instead of showing every metric at once.

**Acceptance Criteria:**

**Given** the analytics value section has multiple data sources available (subscription value, pattern findings, tier recommendation, usage trend, extra usage data)
**When** the context-aware insight engine evaluates what to display
**Then** it selects insights by priority:

1. Active pattern findings (forgotten subscription, chronic mismatch, extra usage overflow) — highest priority
2. Tier recommendation (actionable change) — high priority
3. Notable usage deviation from personal baseline — medium priority
4. Subscription value summary — default fallback

**Given** multiple insights compete for display
**When** the value section renders
**Then** the highest-priority insight is shown prominently
**And** a secondary insight may appear as a subdued one-liner below
**And** no more than two insights are shown simultaneously

**Given** the user dismisses an insight card
**When** the value section re-evaluates
**Then** the next-priority insight promotes to the primary position
**And** the dismissed insight does not reappear until conditions change materially

**Given** insights are displayed
**When** the text is generated
**Then** it uses natural language, not raw numbers:

- "About three-quarters" not "76.2%"
- "Your heaviest week since November" not "Peak: 847,291 credits"
- "Roughly double your usual" not "198% of average"
  **And** precise values are available on hover/VoiceOver for users who want them

**Given** the emotional tone of the data varies
**When** insights are composed
**Then** tone matches context:

- High utilization near reset: cautious, not celebratory
- Low utilization with headroom: reassuring, not accusatory
- Chronic pattern detected: matter-of-fact, not alarmist

**Given** extra usage data is available
**When** the insight engine evaluates conclusions
**Then** the following extra usage conclusion types are candidates:

- "You spent $X in extra usage this period — a higher tier would have saved $Y"
- "You never triggered extra usage — your base plan covers your needs"
- "X% of your total spend this month was extra usage"
- "Total this period: $X base + $Y extra usage"

## Story 16.6: Self-Benchmarking & Visual Trends (Future Iteration)

As a developer using Claude Code,
I want my usage anchored against my own history with visual cycle-over-cycle trends,
So that raw numbers have personal context and I can spot long-term patterns at a glance.

**Acceptance Criteria:**

**Given** the analytics view is open with 30d or All time range selected
**When** sufficient history exists (3+ billing cycles or 3+ calendar months)
**Then** a compact cycle-over-cycle mini-bar or sparkline appears showing utilization per cycle:

- Each bar/point represents one billing cycle (or calendar month if billing day unset)
- Current partial cycle is visually distinguished
- Trend direction is immediately visible without reading numbers

**Given** the cycle-over-cycle visualization is rendered
**When** the user hovers over a cycle bar/point
**Then** a tooltip shows: month label, utilization percentage, dollar value (if pricing known)

**Given** a notable personal benchmark is detected
**When** the insight engine (16.5) evaluates available insights
**Then** self-benchmarking anchors are available as candidates:

- "Your highest usage week since [month]"
- "3rd consecutive month above 80% utilization"
- "Usage down 40% from your peak in [month]"

**Given** fewer than 3 cycles of history exist
**When** the cycle-over-cycle section would render
**Then** it is hidden (insufficient data for meaningful comparison)

**Given** the 24h or 7d time range is selected
**When** the analytics view renders
**Then** the cycle-over-cycle visualization is hidden (not relevant at short ranges)

**Given** a VoiceOver user focuses the cycle-over-cycle visualization
**When** VoiceOver reads the element
**Then** it announces: "Usage trend over [N] months. [Trend summary]. Double-tap for details."
