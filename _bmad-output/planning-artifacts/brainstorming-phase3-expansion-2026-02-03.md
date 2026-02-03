# Brainstorming Session: Phase 3 Expansion Features

**Date:** 2026-02-03
**Participants:** Boss, Mary (Business Analyst)
**Project:** cc-hdrm
**Focus:** Phase 3 features — historical usage tracking, underutilised headroom analysis, and usage slope indicator

---

## Context

cc-hdrm Phases 1 and 2 are fully implemented. The PRD defines Phase 3 as: Sonnet-specific usage breakdown, usage graphs, limit prediction, Linux tray support, and extra usage/spending tracking. This session explored three of those features in depth, refining the original "limit prediction" concept into a simpler slope indicator based on design analysis.

### Key Discovery: Data Sources

Investigation of Claude Code's `/stats` feature revealed:

- **Claude Code stores stats locally** in `~/.claude/stats-cache.json` — daily activity, tokens per model, session data, hour-of-day heatmap data
- This data is **client-specific** — it only tracks Claude Code sessions, not OpenCode or other clients
- Therefore, cc-hdrm **cannot rely on Claude Code's local stats** for users of alternative clients
- The Anthropic usage API (`api.anthropic.com/api/oauth/usage`) is **client-agnostic** — it reports account-level utilization regardless of which client consumed the tokens
- **cc-hdrm must build its own time-series** by persisting poll results

### Research Task Identified

Investigate whether Anthropic exposes a **historical usage API endpoint**. They clearly have historical data server-side (Claude Code's `/stats` shows tokens per day). If such an endpoint exists, it would fill gaps from periods when cc-hdrm wasn't running.

---

## Feature 1: Historical Usage Tracking

### Problem

cc-hdrm currently polls the usage API every 30-60 seconds but discards the data after display. Users have no visibility into usage patterns over time.

### Proposed Solution

Persist each poll snapshot to build a local time-series database.

### Storage Decision: SQLite

- Year-scale retention at poll frequency generates ~525K records/year (~15-20 MB raw)
- SQLite provides efficient querying for arbitrary time ranges and aggregation
- Minimal dependency for a native macOS app (SQLite is bundled with macOS)

### Tiered Rollup Strategy

| Data Age   | Resolution          | Purpose                            |
| ---------- | ------------------- | ---------------------------------- |
| < 24 hours | Per-poll (~60s)     | Real-time detail, recent debugging |
| 1-7 days   | 5-minute averages   | Short-term pattern visibility      |
| 7-30 days  | Hourly averages     | Weekly pattern analysis            |
| 30+ days   | Daily summary       | Long-term trends, seasonal patterns|

Daily summary record includes: average utilization, peak utilization, minimum utilization, and calculated wasted headroom percentage.

### Retention Period

- **Configurable** via settings, default 1 year
- At daily rollup granularity, a year is just 365 records — trivial storage
- Enables year-scale pattern analysis: "I consistently underutilise on weekends," "February was my heaviest month"

### Gap Handling

**Problem:** cc-hdrm may not be running at all times. Usage can occur from other devices or while the machine is asleep. Gaps in the time-series are inevitable.

**Approach:**
1. **Accept gaps honestly** — render missing periods as a distinct visual state (hatched/grey regions). Never interpolate. The chart says "I don't know what happened here" rather than presenting fabricated data.
2. **Infer reset boundaries** — if between two polls the `resets_at` timestamp shifted forward and utilization dropped, a reset occurred somewhere in the gap. Log this as a detected event for the headroom analysis.
3. **Server-side history** (future/contingent) — if a historical API is discovered, use it to backfill gaps.

### Visualization

**Option C selected: sparkline in popover + full analytics view**

- **Popover sparkline:** last 24 hours of 5h utilization, inline below the existing gauges. Gaps shown as breaks in the line.
- **Analytics view:** separate window accessible from popover. Full history, zoomable, with multiple overlays. Supports all retention periods.

### Data Captured Per Poll

```
{ timestamp, 5h_utilization, 5h_resets_at, 7d_utilization, 7d_resets_at }
```

Both windows captured together — essential for the headroom analysis.

---

## Feature 2: Underutilised Headroom Analysis

### Core Insight

The 5-hour and 7-day limits form a **nested constraint system**. The weekly limit prevents exploitation of the 5h rolling window. Headroom analysis must factor both constraints simultaneously.

### Effective Headroom

Effective headroom is NOT simply `100% - five_hour_utilization`. It must account for the 7-day constraint:

**Effective headroom = min(5h remaining capacity, 7d remaining capacity)**

A user at 10% of their 5h window but 92% of their 7d window has very little real headroom — pushing the 5h window would blow through the weekly limit.

### Three Waste Categories

| Category           | Definition                                                         | User Insight                                                 |
| ------------------ | ------------------------------------------------------------------ | ------------------------------------------------------------ |
| **5h waste**       | 5h window reset with unused capacity; 7d had room                  | "You could have done more in that window"                    |
| **7d-constrained** | 5h had headroom but 7d was the binding constraint                  | "You were pacing correctly — pushing harder would've hit the weekly wall" |
| **True waste**     | Both 5h and 7d had significant remaining capacity at 5h reset      | "You genuinely left capacity unused"                         |

The **7d-constrained** category is explicitly **not waste** — it's smart pacing. The visualization must distinguish this to avoid misleading users into thinking they should push harder when the weekly limit would stop them.

### Visualization: Three-Band Stacked Chart

```
100% |████████████████████████████████████████|
     |         true available                 | <- what you could have used
     |░░░░░░ 7d-constrained ░░░░░░░░░░░░░░░░░| <- couldn't safely use (not waste)
     |▓▓▓▓▓▓ actual usage ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓|
  0% |________________________________________|
      Mon    Tue    Wed    Thu    Fri    Sat
```

Three bands:
- **Used** (solid) — actual utilization
- **7d-constrained** (hatched/muted) — headroom blocked by weekly limit
- **True available** (empty/light) — capacity that was genuinely available but not used

Calculation happens at **render time**, not storage time, since the relationship between the two limits depends on the time horizon being analyzed.

---

## Feature 3: Usage Slope Indicator (replaces Limit Prediction)

### Why Slope Instead of Prediction

The original Phase 3 item was "limit prediction based on usage slope." Through analysis, we determined that explicit time-to-exhaustion predictions have significant trust problems:

- Usage patterns are **bursty**, not linear — predictions would whipsaw ("12 minutes... now 3 hours... now 8 minutes")
- False precision erodes trust and trains users to ignore the feature
- cc-hdrm's design philosophy is **show truthful data, let the user decide**

A discrete slope indicator communicates the essential signal — **how fast am I burning?** — without pretending to know the future.

### Slope Levels

| Indicator    | Visual | Meaning                                    | Typical Scenario                               |
| ------------ | ------ | ------------------------------------------ | ---------------------------------------------- |
| **Cooling**  | ↘      | Utilization decreasing                     | Rolling window moving past older high-usage     |
| **Flat**     | →      | No meaningful change                       | Idle, between sessions                          |
| **Rising**   | ↗      | Moderate consumption rate                  | One active session, normal pace                 |
| **Steep**    | ⬆      | Heavy consumption rate                     | Multiple sessions or intense conversation       |

### Calculation

- Sample last 10-15 minutes of poll data
- Compute average rate of change (% per minute)
- Map to discrete levels:

| Rate (% / min) | Level   |
| --------------- | ------- |
| < -0.5          | Cooling |
| -0.5 to 0.3     | Flat    |
| 0.3 to 1.5      | Rising  |
| > 1.5           | Steep   |

Threshold values will need tuning with real usage data.

### Where It Appears

- **Menu bar:** inline next to utilization number — `78% ↗` — minimal UI change, significant information gain
- **Popover:** both 5h and 7d gauges get their own slope indicator
- **Historical analytics:** slope rendered over time shows periods of steep vs flat usage, overlaid with headroom bands

### Connection to Headroom Analysis

Slope + headroom together tells the full story:
- "Every afternoon you go steep for 2 hours, then flat"
- "You went steep on Monday and it constrained your whole week"
- Steep slope + high 7d utilization = actionable warning signal without needing a countdown timer

---

## Features Not Explored (Remaining Phase 3)

The following Phase 3 items were not discussed in this session and remain for future brainstorming:

- **Sonnet-specific usage breakdown** — the API returns `seven_day_sonnet` data
- **Linux tray support** — cross-platform expansion
- **Extra usage / spending tracking** — the API returns `extra_usage` with spending data

---

## Recommended Next Steps

1. **Technical research spike** — investigate whether Anthropic has a historical usage API endpoint
2. **Update PRD** — add detailed functional requirements for these three features (FR33+)
3. **Update Architecture** — SQLite integration, rollup engine design, analytics view architecture
4. **Update UX Design** — sparkline, three-band chart, slope indicators, analytics window
5. **Create new epics and stories** for Phase 3 implementation

### Suggested Workflow Path

Run in fresh context windows:
- `/bmad-bmm-prd` — update PRD with Phase 3 requirements
- `/bmad-bmm-create-ux-design` — design the new visualizations
- `/bmad-bmm-create-architecture` — address SQLite, rollup engine, analytics view
- `/bmad-bmm-create-epics-and-stories` — break into implementable stories
- `/bmad-bmm-check-implementation-readiness` — verify alignment before development
