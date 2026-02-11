# Sprint Change Proposal

**Date:** 2026-02-10
**Revised:** 2026-02-10 (extra usage addendum)
**Triggered by:** Brainstorming session (2026-02-09) during Epic 14 implementation
**Scope classification:** Moderate
**Recommended approach:** Direct Adjustment

---

## Section 1: Issue Summary

A brainstorming session conducted on 2026-02-09 during Epic 14 implementation produced 5 prioritized themes that contradict the "waste" framing embedded in the remaining stories (14.4, 14.5) and identify significant new capabilities not captured in the current plan.

The session was triggered by the observation that the subscription value bar answered a question nobody was asking while failing to answer questions users actually care about. Through 93 questions (Question Storming), 16 reversal insights, and 4 first-principles insights, the session concluded:

1. **Unused capacity is not inherently "waste"** — it can represent available headroom, system constraint, or genuine underutilization depending on context
2. **100% utilization is a failure state** (rate-limited), not a success state
3. **One well-chosen insight beats ten metrics** — context-aware display over fixed statistics
4. **Conditional visibility** — quiet when nothing notable, present when there's real signal
5. **Five themes of new capability** were identified, only one of which (denominator fix) was in the existing plan

**Evidence:** The brainstorming session document (`_bmad-output/brainstorming/brainstorming-session-2026-02-09.md`), which includes the user's own shift in perspective: "I was pretty set on 'waste,' but now I see there can be an opposite point of view."

**Revision (2026-02-10):** The brainstorming document was updated post-session with an "Addendum: Extra Usage Feature" documenting Anthropic's pay-as-you-go overflow pricing. The cost model is no longer flat-rate: users can now exceed plan limits and pay API rates for overflow usage. The API already returns `extra_usage` data (`is_enabled`, `monthly_limit`, `used_credits`, `utilization`) and PR 43 already persists this to SQLite. This impacts Epic 16 stories for pattern detection, tier recommendation, and the insight engine.

---

## Section 2: Impact Analysis

### Epic Impact

| Epic                      | Impact                         | Detail                                                                                                                                                              |
| ------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Epic 14** (in-progress) | **Rename + rewrite 2 stories** | Rename from "Headroom Analysis & Waste Breakdown" to "Subscription Value & Usage Insights". Rewrite 14.4 and 14.5 — both are in backlog, no implementation to undo. |
| **Epic 15** (planned)     | **No change**                  | Story 15.2 (Custom Credit Limit Override) remains valid.                                                                                                            |
| **Epic 16** (new)         | **Create + enrich**            | "Subscription Intelligence" — 6 stories covering brainstorming Themes 2-5. Theme 1 (denominator fix) acknowledged as pre-completed in Story 14.3. Stories 16.1, 16.3, 16.4, 16.5 enriched with extra usage awareness per brainstorming addendum. |

### Artifact Conflicts

| Artifact          | Sections affected                                                                         | Change needed                                                                                                                                         |
| ----------------- | ----------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| **PRD**           | FR40                                                                                      | Replace "waste" classification terminology with neutral terms                                                                                         |
| **PRD**           | New FRs needed                                                                            | Pattern detection, tier recommendation, contextual insights, self-benchmarking                                                                        |
| **PRD**           | Phase 4 scope                                                                             | Move "Extra usage / spending tracking" from Phase 4 to Phase 3 (Epic 16) -- data already available via API and persisted (PR 43)                      |
| **PRD**           | New FRs (extra usage)                                                                     | FR46-FR48: extra usage pattern detection, total cost comparison, extra usage display                                                                  |
| **Architecture**  | HeadroomAnalysisService description                                                       | Update terminology; add SubscriptionPatternDetector and TierRecommendationService component descriptions                                              |
| **Architecture**  | RateLimitTier enum                                                                        | Add `monthlyPrice` property (Pro: $20, Max 5x: $100, Max 20x: $200) for total cost calculations                                                      |
| **Architecture**  | SubscriptionPatternDetector, TierRecommendationService                                    | Both services need access to extra usage history data for overflow pattern detection and total cost comparison                                         |
| **UX Phase 3**    | Feature 4 title + body                                                                    | Rename from "Underutilised Headroom Analysis", update visualization spec, replace summary statistics with context-aware display, update user journeys |
| **Epics**         | Epic 14 header + stories 14.4, 14.5                                                       | Rename epic, rewrite both stories                                                                                                                     |
| **Epics**         | New section                                                                               | Add Epic 16 with 6 stories                                                                                                                            |
| **Code**          | Struct fields                                                                             | Rename `wastePercent`/`wasteCredits`/`wastedDollars` to `unusedPercent`/`unusedCredits`/`unusedDollars`                                               |
| **Tests**         | SubscriptionValueCalculatorTests, HeadroomBreakdownBarTests, HeadroomAnalysisServiceTests | Update for renamed fields                                                                                                                             |
| **Sprint status** | Epic 14, new Epic 16                                                                      | Rename Epic 14, add Epic 16 entries                                                                                                                   |

### Technical Impact

- **No schema changes** — all new analysis is computable from existing `reset_events` and `usage_polls` tables. Extra usage data already persisted to SQLite (PR 43).
- **No rollback needed** — Stories 14.1-14.3 are compatible with the new direction. The two-band money bar (14.3) and denominator fix already anticipated the brainstorming conclusions.
- **New services:** SubscriptionPatternDetector, TierRecommendationService, context-aware insight engine
- **New preference:** Billing cycle day (Int, 1-28)
- **New enum property:** `RateLimitTier.monthlyPrice` — required for total cost comparison (base + extra usage). Hardcoded like credit limits, with user override fallback.
- **Extra usage data path:** API returns `extra_usage` object -> already parsed by `UsageResponse.extraUsage` -> already persisted by `HistoricalDataService` (PR 43) -> available for pattern detection and tier recommendation

---

## Section 3: Recommended Approach

**Selected:** Direct Adjustment (Option 1)

### Rationale

1. **No completed work is invalidated** — Stories 14.1-14.3 are done and useful. The two-band money bar and denominator fix from 14.3 actually anticipated the brainstorming direction.
2. **Minimal disruption** — Only 2 stories need rewriting, and both are still in backlog.
3. **Clean expansion path** — A new Epic 16 captures all brainstorming themes as proper stories without cramming them into Epic 14.
4. **Terminology refactor is contained** — Renaming struct fields fits naturally into rewritten 14.4 since it touches the same components.
5. **Extra usage integration is free** — The data layer already exists (PR 43). Weaving extra usage awareness into Epic 16 stories requires acceptance criteria additions, not new infrastructure.

### Alternatives considered

- **Rollback 14.2/14.3:** Not viable — HeadroomAnalysisService and the money bar are still needed. The only issue is field names, which is a rename not a rollback.
- **MVP scope reduction:** Not needed — the brainstorming themes are extensions beyond current MVP, not contradictions of it.
- **Split Themes 4+5 into Epic 17:** Possible but unnecessary — 6 stories in one epic is manageable. Can revisit during sprint planning.
- **Separate Epic for extra usage:** Not needed — extra usage capabilities integrate naturally into existing 16.x story acceptance criteria. Creating a separate epic would fragment related functionality.

### Effort and risk

- **Effort:** Medium — rewriting 2 stories is small; planning and implementing 6 new stories is the main work. Extra usage adds AC depth but no new stories.
- **Risk:** Low — no completed work reverted, new stories are additive, all data sources already exist (including extra usage via PR 43)
- **Timeline impact:** Epic 14 completion unchanged (2 stories remain). Epic 16 adds new work after Epic 15.

---

## Section 4: Detailed Change Proposals

### 4.1 Epic 14 Changes

#### Rename Epic 14

**OLD:**

```
## Epic 14: Headroom Analysis & Waste Breakdown (Phase 3)

Alex sees the real story behind his usage — a three-band breakdown showing what he
actually used, what was blocked by the weekly limit (not waste!), and what he genuinely
left on the table.
```

**NEW:**

```
## Epic 14: Subscription Value & Usage Insights (Phase 3)

Alex sees the real story behind his subscription — a money-based value bar showing what
he used in dollar terms, with context-aware summary insights that adapt to the selected
time range.
```

#### Rewrite Story 14.4: Context-Aware Value Summary & Terminology Refactor

**OLD:** Fixed summary stats (Avg peak, Total waste, 7d-constrained) always visible below breakdown bar.

**NEW:**

As a developer using Claude Code,
I want a context-aware summary below the subscription value bar that adapts to the selected time range,
So that I see the single most relevant insight for the data I'm looking at.

Acceptance Criteria:

- Time-range-specific insights: 24h (capacity gauge), 7d (vs. personal average), 30d (dollar summary), All (long-term trend)
- Conditional visibility: collapses to quiet single line when nothing notable (utilization 20-80%, no trend change)
- Zero reset events: "No reset events in this period"
- Unknown credit limits: percentages only, no dollar values
- Terminology refactor: rename wastePercent/wasteCredits/wastedDollars to unusedPercent/unusedCredits/unusedDollars across all code, tests, and VoiceOver labels

#### Rewrite Story 14.5: Analytics View Integration with Conditional Display

**OLD:** Always-present breakdown bar and summary stats below UsageChart.

**NEW:**

As a developer using Claude Code,
I want the subscription value bar and context-aware summary integrated into the analytics view with time-range-aware behavior,
So that the value section adapts meaningfully as I explore different time ranges.

Acceptance Criteria:

- Value bar and summary appear below UsageChart, recalculate on time range change
- Data-span qualifier for ranges with fewer than 6 hours of data
- Bar hidden when no reset events (summary-only message)
- Conditional collapse to minimal height when nothing notable to display

### 4.2 New Epic 16: Subscription Intelligence

#### Story 16.1: Slow-Burn Pattern Detection Service

SubscriptionPatternDetector analyzes ResetEvent and extra usage history for 6 patterns:

- Forgotten subscription: <5% utilization for 2+ consecutive weeks
- Chronic overpaying: total cost (base + extra usage) fits cheaper tier for 3+ consecutive months
- Chronic underpowering: rate-limited N+ times per cycle for 2+ cycles (adjusted: if extra usage is enabled and absorbing overflows, the user is paying API rates, not truly blocked -- pattern triggers on cost, not rate-limits alone)
- Usage decay: monthly utilization declining for 3+ consecutive months
- Extra usage overflow: extra_usage.used_credits > 0 for 2+ consecutive billing periods -- signals higher tier may be cheaper than base + overflow
- Persistent extra usage: extra_usage spending exceeds 50% of base subscription price for 2+ months -- strong tier upgrade signal

Returns typed findings array; empty when no patterns detected; skips patterns with insufficient history. Extra usage patterns require extra_usage.is_enabled == true and non-nil used_credits data.

#### Story 16.2: Pattern Notification & Analytics Display

Surfaces pattern findings as macOS notifications and analytics insight cards:

- Notification per finding type with natural language messaging
- 30-day cooldown prevents duplicate notifications
- Analytics cards below value bar, dismissable with persisted state
- Respects system notification preferences

#### Story 16.3: Tier Recommendation Service

TierRecommendationService compares actual usage against all tiers using total cost:

- Returns .downgrade, .upgrade, or .goodFit recommendation
- 20% safety margin above actual peak (configurable)
- **Total cost comparison:** for each tier, computes `total = base_price + estimated_extra_usage`. If usage fits within a tier's limits, extra usage = $0. If usage exceeds limits and extra usage is enabled, includes actual or estimated overflow cost at API rates.
- Includes dollar figures: current total cost, recommended total cost, savings/additional cost
- Requires 2+ weeks of data; aligns to billing cycles when configured
- Bidirectional: recommends downgrades as freely as upgrades
- Example output: "On Pro ($20/mo) you paid ~$47 in extra usage ($67 total) -- Max 5x ($100/mo) would have covered you and saved $67"
- When extra usage data is unavailable (is_enabled = false or no data), falls back to credit-only comparison (pre-extra-usage behavior)

#### Story 16.4: Tier Recommendation Display & Billing Cycle Preference

Display layer for tier recommendations plus billing cycle day setting:

- Recommendation card in analytics (conditional -- hidden for .goodFit)
- When extra usage data exists: card shows total cost breakdown (e.g., "Base: $20 + Extra: $47 = $67 total")
- When recommending tier change: shows comparison (e.g., "Max 5x at $100/mo would have covered this with no extra charges")
- Billing cycle day picker (1-28) in Settings
- Dollar summaries align to billing cycles when configured
- Subtle hint to set billing day when unset

#### Story 16.5: Context-Aware Insight Engine (Future Iteration)

Selects single most relevant conclusion from multiple data sources:

- Priority ranking: pattern findings > tier recommendation > usage deviation > value summary
- Maximum two insights displayed simultaneously
- Natural language output ("about three-quarters" not "76.2%")
- Emotional tone matches context (cautious near limits, reassuring with headroom)
- Precise values available on hover/VoiceOver
- Extra usage conclusion types:
  - "You spent $X in extra usage this period -- a higher tier would have saved $Y"
  - "You never triggered extra usage -- your base plan covers your needs"
  - "X% of your total spend this month was extra usage"
  - "Total this period: $X base + $Y extra usage"

#### Story 16.6: Self-Benchmarking & Visual Trends (Future Iteration)

Personal usage anchoring with cycle-over-cycle visualization:

- Compact mini-bar or sparkline showing utilization per billing cycle (3+ cycles required)
- Current partial cycle visually distinguished
- Hover tooltips with month, utilization, dollar value
- Self-benchmarking anchors feed into insight engine ("Your highest week since November")
- Hidden at 24h/7d ranges; hidden with fewer than 3 cycles of history
- VoiceOver: trend summary announcement

### 4.3 PRD Changes

#### Move Extra Usage from Phase 4 to Phase 3

**OLD (PRD Phase 4: Future):**

```
- Extra usage / spending tracking (API returns `extra_usage` with spending data)
```

**NEW:**

```
- ~~Extra usage / spending tracking~~ -> Moved to Phase 3 / Epic 16 (data already available and persisted)
```

#### Add New Functional Requirements

- FR46: App detects extra usage overflow patterns from persisted extra_usage data and includes them in slow-burn pattern analysis
- FR47: Tier recommendation computes total cost (base subscription + extra usage charges) when comparing tiers
- FR48: Analytics displays total cost breakdown when extra usage data is available

---

## Section 5: Implementation Handoff

### Scope Classification: Moderate

Requires backlog reorganization (rewrite 2 stories, add 1 epic with 6 stories) plus artifact updates. Extra usage integration adds acceptance criteria depth to 4 stories but no new stories or epics.

### Handoff Plan

| Role                       | Responsibility                                                                                                                                                                                |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Scrum Master (Bob)**     | Update epics.md with all approved changes (rename Epic 14, rewrite 14.4/14.5, add Epic 16). Update sprint-status.yaml. Run Create Story workflow for each story when reached in sprint order. |
| **Developer (Amelia)**     | Implement rewritten 14.4, 14.5, then Epic 15, then Epic 16 stories in sequence.                                                                                                               |
| **Product Manager (John)** | Update PRD: fix FR40 terminology, add new FRs for Themes 2-5, move extra usage from Phase 4 to Phase 3, add FR46-FR48 for extra usage analysis. Can be bundled into Create Story workflow.    |
| **UX Designer (Sally)**    | Update UX Phase 3 Feature 4 spec. Recommended before Epic 16 stories begin.                                                                                                                   |
| **Architect (Winston)**    | Update architecture doc: new service descriptions (SubscriptionPatternDetector, TierRecommendationService), add monthlyPrice to RateLimitTier, document extra usage data flow from PR 43 through pattern detection and tier recommendation. Can be done during Create Story. |

### Sequencing

1. **Now:** Update epics.md and sprint-status.yaml with approved changes
2. **Next:** Create Story for rewritten 14.4 -> Dev Story -> Code Review
3. **Then:** Create Story for rewritten 14.5 -> Dev Story -> Code Review
4. **Then:** Epic 14 retrospective (optional)
5. **Then:** Epic 15 (Settings & Data Retention) -- unchanged
6. **Then:** Epic 16 stories in order: 16.1 -> 16.2 -> 16.3 -> 16.4 -> 16.5 -> 16.6

### Success Criteria

- All "waste" terminology removed from code and user-facing surfaces
- Context-aware value summary replaces fixed statistics
- Conditional visibility implemented throughout analytics value section
- Slow-burn patterns detected and surfaced via macOS notifications (including extra usage overflow patterns)
- Tier recommendations computed using total cost (base + extra usage) and displayed when actionable
- Billing cycle preference available in settings
- Extra usage data integrated into pattern detection, tier recommendation, and analytics display
- (Future) Insight engine selects most relevant conclusion, including extra usage conclusions
- (Future) Cycle-over-cycle self-benchmarking visualization
