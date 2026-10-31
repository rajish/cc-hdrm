---
phase: 3
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/ux-design-specification.md
  - _bmad-output/planning-artifacts/brainstorming-phase3-expansion-2026-02-03.md
projectName: cc-hdrm
date: 2026-02-03
author: Boss
---

# UX Design Specification: Phase 3 Expansion

**Author:** Boss
**Date:** 2026-02-03

> **Revised 2026-10-31:** Claude's 5-hour limit was retired; the weekly window is primary. See `sprint-change-proposal-2026-10-31.md` (Epic 26).

---

## Executive Summary

Phase 3 extends cc-hdrm from a real-time fuel gauge into a historical analytics platform. Three interconnected features give Alex visibility not just into *where he stands now*, but *how he got here* and *how fast he's moving*:

1. **Historical Usage Tracking** — Persistent storage of poll data, current-weekly-cycle sparkline in popover, full analytics window
2. **Subscription Value & Headroom Analysis** — Two-band breakdown showing used and unused weekly capacity per weekly cycle
3. **Weekly Pace** (replaces the Usage Slope Indicator) — Pace versus the elapsed share of the week, with a run-out projection in the popover and an arrow in the menu bar

These features preserve cc-hdrm's core identity as invisible infrastructure while adding depth for users who want to understand their usage patterns.

### Design Principles Carried Forward

From the Phase 1 UX spec, these principles remain sacred:

- **Peripheral first** — The menu bar glance is still the primary interface
- **Silent until relevant** — New features escalate only when they add value
- **Invisible infrastructure** — The analytics window is a tool you summon, not a presence you manage
- **Never lose a warning** — Historical data ensures patterns are never silently lost

### New Principle for Phase 3

- **Honest data, no predictions** — Show truthful historical data and current pace. Never pretend to predict the future. Revised 2026-10-31: the one exception is the weekly run-out projection — a straight-line average since the weekly reset, shown only when it falls before the reset.

---

## Feature 1: Weekly Pace (replaces Usage Slope Indicator)

### Problem

Alex knows *where* he stands (58% weekly utilization) but not whether that is fast or slow for this point in the week. Will the allowance last until the weekly reset?

### Solution

Revised 2026-10-31: weekly pace replaces the 4-level slope indicator. Pace compares usage with the share of the week elapsed. The popover always shows a pace line. The menu bar shows an arrow only when run-out is projected before the weekly reset.

### Slope Levels

Retired 2026-10-31 — replaced by the two pace states below ("On pace" / "Ahead of pace").

### Calculation

Uses only `seven_day.utilization` and `seven_day.resets_at`:

- `weekStart = resetsAt − 7 days`
- `elapsed = clamp((now − weekStart) / 7 days, 0…1)`
- `paceDelta = utilization − elapsed × 100` (positive = ahead of even spending)
- Projected run-out: `rate = utilization / (now − weekStart)`; `runOut = now + (100 − utilization) / rate`
- Run-out is shown only when `runOut < resetsAt` **and** at least ~4 hours of the week have passed

**Known ceiling:** average-since-reset projection is pessimistic after a heavy first day. Upgrade path: blend with a recent-window rate.

### Menu Bar Display: Escalation-Only

**Design decision:** The existing actionable arrow appears in the menu bar **only** when run-out is projected before the weekly reset. Otherwise it's hidden.

**Rationale:** This preserves the compact footprint principle from Phase 1. During the 80% of time when things are calm, the menu bar stays minimal. The arrow earns its pixels only when pace is actionable information.

| State                                | Menu Bar Display | Width     |
| ------------------------------------ | ---------------- | --------- |
| Normal, no run-out before reset      | `✳ 83%`          | ~5 chars  |
| Normal, run-out before reset         | `✳ 58% ↗`        | ~7 chars  |
| Warning, run-out before reset        | `✳ 17% ↗`        | ~7 chars  |
| Exhausted                            | `✳ ↻ 3d 4h`      | ~8 chars  |
| Disconnected                         | `✳ —`            | ~3 chars  |

### Popover Display: Always Visible

The weekly gauge (large, primary) always shows a pace line below its countdown. The Fable section sits below the weekly gauge:

```
┌──────────────────────────────┐
│    ◯ 7d gauge                │
│     42%                      │
│  resets in 2d 1h             │
│  at Thu 9:00 AM              │
│  On pace                     │  ← pace line (always visible)
├──────────────────────────────┤
│    ◯ Fable gauge             │
│  resets in 2d 1h             │
└──────────────────────────────┘
```

**Pace line copy:**
- "On pace" — no run-out projected before the weekly reset
- "Ahead of pace — runs out ~Thu 14:00" — run-out projected before the weekly reset

**Quotas remaining display:** Retired 2026-10-31 — "N full 5h quotas left" referred to a limit that no longer exists.

### Accessibility

- VoiceOver announces pace as part of the weekly gauge reading: "Weekly headroom: 42 percent, on pace". When run-out is projected before the reset: "…, ahead of pace, runs out around Thursday 14:00"
- Pace is never color-only — the line text and the arrow shape convey meaning independently

---

## Feature 2: Historical Usage Tracking

### Problem

cc-hdrm currently discards poll data after display. Alex has no visibility into usage patterns over time.

### Solution

Persist each poll snapshot to SQLite, display a current-weekly-cycle sparkline in the popover, and provide a full analytics window for deep exploration.

### Data Storage

**Per-poll record (revised 2026-10-31):**
```
{ timestamp, 7d_utilization, 7d_resets_at, scoped caps, extra usage }
```

Historical 5h columns are retained and nullable. New polls store NULL there; nothing is deleted.

**Tiered rollup strategy:**

| Data Age   | Resolution        | Purpose                             |
| ---------- | ----------------- | ----------------------------------- |
| < 24 hours | Per-poll (~60s)   | Real-time detail, recent debugging  |
| 1-7 days   | 5-minute averages | Short-term pattern visibility       |
| 7-30 days  | Hourly averages   | Weekly pattern analysis             |
| 30+ days   | Daily summary     | Long-term trends, seasonal patterns |

Daily summary includes: average utilization, peak utilization, minimum utilization, and calculated waste percentage.

**Retention:** Configurable via settings, default 1 year.

### The Sawtooth Data Shape

Utilization data has a distinctive pattern that the visualization must honor:

- **Monotonically increasing** within each window — utilization only goes up as Alex uses Claude
- **Drops to 0%** at reset boundaries — the window clears completely
- **Never decreases mid-window** — you can't un-use tokens

This creates a sawtooth pattern:

```
100%│
    │                    │
    │               ▄▄▄▄▄│
    │          ▄▄▄▄▀     │    ▄▄
    │     ▄▄▄▀▀          │▄▄▄▀
    │▄▄▄▀▀               │
  0%│────────────────────┴────────
       weekly cycle       reset
```

### Popover Sparkline

Revised 2026-10-31: a compact sparkline appears below the gauges, showing the current weekly cycle (since the last weekly reset) against an even-pace diagonal.

```
┌──────────────────┐
│    ◯ 7d gauge    │
│     42%          │
│  resets in 2d 1h │
│  at Thu 9:00 AM  │
│  On pace         │
├──────────────────┤
│    ◯ Fable gauge │
├──────────────────┤
│  wk ▁▂▃▅▇  ╱     │  ← sparkline (weekly cycle + even-pace line)
├──────────────────┤
│ Pro │ 12s ago │ ⚙ │
└──────────────────┘
```

**Sparkline design:**
- Shows weekly utilization for the current weekly cycle, from the last weekly reset to now
- Even-pace diagonal from 0% at the cycle start to 100% at the weekly reset — usage above the line is ahead of pace
- Step-area style honoring the sawtooth shape
- Gaps (cc-hdrm not running) rendered as breaks in the line — never interpolated
- No axis labels — the shape is the story

**Sparkline as analytics launcher:**
- The sparkline is a button
- Click to open the analytics window
- If analytics window is already open, click brings it to front
- Subtle hover state indicates clickability

---

## Feature 3: The Analytics Window

### Identity & Behavior

The analytics window is cc-hdrm's first real window. This is a significant expansion, handled carefully to preserve the app's identity as invisible infrastructure.

**Mental model:** The analytics window is a detachable instrument panel. The menu bar is the fuel gauge you glance at while driving. The popover is the dashboard at a red light. The analytics window is the mechanic's diagnostic screen — deliberate, occasional, deep.

**Window type:** NSPanel (utility panel)
- No dock icon appears
- No Cmd+Tab entry
- Floats above regular windows, below full-screen apps
- Closes via close button or Escape key

**Recall mechanism:**
- Sparkline in popover acts as toggle: click to open, click to bring to front
- When analytics window is open, sparkline shows subtle indicator (dot or highlight)
- Window remembers size and position between sessions

**Default size:** ~600×500px, resizable

### Layout Structure

```
┌─────────────────────────────────────────────────────────┐
│  Usage Analytics                                    ✕   │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  [24h]  [7d]  [30d]  [All]     7d ● │ Fable ● │ 5h ○    │
│                                                         │
│  100%│          │                                       │
│      │     ▄▄▄▄▄│                                       │
│      │▄▄▄▄▀    ││    ▄▄▄                               │
│      │▀        ││▄▄▄▀                                   │
│    0%│─────────┴┴────────                               │
│      8am   12pm   4pm   8pm   12am  4am   now          │
│                                                         │
├─────────────────────────────────────────────────────────┤
│  Headroom Breakdown (selected period)                   │
│  ┌─────────────────────────────────────────────────┐    │
│  │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                        │    │
│  └─────────────────────────────────────────────────┘    │
│  ▓ Used: 52%   □ Unused: 48%                            │
│                                                         │
│  Context-aware summary (adapts to time range)           │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Time Range Selector

Four preset buttons: `24h`, `7d`, `30d`, `All`

These map directly to the tiered rollup strategy:
- **24h:** Per-poll data, step-area chart
- **7d:** 5-minute rolled data, bar chart (one bar per hour)
- **30d:** Hourly rolled data, bar chart (one bar per day)
- **All:** Daily summaries, bar chart

No custom date picker for MVP — presets cover the primary user stories.

### Series Toggles

`7d`, `Fable` and `5h` as toggleable overlays on the main chart (revised 2026-10-31).

- Default series: weekly (`7d`) and Fable
- `5h` is historical only: off by default, and hidden when the selected range has no 5h data
- Toggle state persists per time range

### Main Chart: Hybrid Visualization

**24h view — Step Area Chart:**
- Honors the sawtooth shape: steps only go UP within windows
- Weekly reset boundaries rendered as distinct vertical lines (dashed, subtle color)
- Gaps rendered as missing segments (no interpolation)
- Slope background bands: retired 2026-10-31 — no per-point slope colouring

**7d+ views — Bar Chart:**
- Each bar represents one period (hour for 7d, day for 30d/All)
- Bar height = **peak utilization** for that period (not average)
- Rationale: "How close did I get to the wall?" is the question that matters
- Weekly reset events marked with subtle indicator below affected bars

**Interaction:**
- Hover tooltip: timestamp, exact utilization %
- For bars: period range, min/avg/peak for that period
- Scroll to zoom, drag to pan (24h view)

### Legend & Information

- Legend in top-right showing series colors (7d, Fable; 5h only when shown)
- Hover info provides detailed data points
- Gap periods labeled on hover: "No data (cc-hdrm not running)"

---

## Feature 4: Subscription Value & Headroom Analysis

> **Renamed** from "Underutilised Headroom Analysis" per sprint change proposal (2026-02-10). The "waste" framing is replaced with neutral terminology. Unused capacity is one of many valid conclusions, not the only lens.

### The Math

Revised 2026-10-31: the analysis runs per weekly cycle. With a single plan-wide window there is no second limit to constrain the first, so no credit comparison is needed for the breakdown.

**Weekly credit limits by tier** (used for value $ and tier advice; the 5h credit column was dropped):

| Tier    | Credits/7d   |
| ------- | ------------ |
| Pro     | 5,000,000    |
| Max 5×  | 41,666,700   |
| Max 20× | 83,333,300   |

**Calculation at each weekly reset** (uses the stored `sevenDayUtil` peak for the cycle):

```
used_% = 7d_peak%
unused_% = 100% - 7d_peak%
```

**Example:** the weekly window peaked at 72% before reset → Used 72%, Unused 28%.

Older reset events computed from 5h data are still displayed for their period; they are not recomputed.

### Three-Band Visualization

Revised 2026-10-31 to two bands; the "7d-constrained" band is retired. The headroom breakdown appears in the analytics window below the main chart.

```
100% ┌────────────────────────────────────────┐
     │              □ Unused                  │ ← unused weekly capacity
     │      (left in the week at reset)       │
     ├────────────────────────────────────────┤
     │               ▓ Used                   │ ← actual consumption
     │        (peak weekly utilization)       │
  0% └────────────────────────────────────────┘
```

**Visual encoding:**
- **Used (▓)** — solid fill, headroom color based on peak level
- **Unused (□)** — light/empty, faint fill or outline only. Weekly capacity that went unused.

**Emotional framing:**
- Unused capacity → neutral tone, one of many valid conclusions (not inherently "waste")
- High unused + low utilization → context-aware insight may suggest tier review

### Context-Aware Summary

> **Replaced** fixed summary statistics per sprint change proposal (2026-02-10). Instead of always showing Avg peak / Total waste / 7d-constrained, the summary adapts to the selected time range and shows the single most relevant insight.

Below the two-band bar, a context-aware summary selects the most relevant insight. Revised 2026-10-31: value $, cycle utilisation and insight copy are computed per weekly cycle.

- **24h:** Simple capacity gauge — "Used $X of $Y today" or utilization percentage if no pricing
- **7d:** Usage vs. personal average — "X% above/below your typical week"
- **30d:** Dollar summary — "Used $X of $Y this month" with utilization percentage
- **All:** Long-term trend — "Avg monthly utilization: X%" with trend direction

**Conditional visibility:** Collapses to a quiet single line when nothing notable (utilization 20-80%, no trend change). Expands when there's real signal.

**Zero reset events:** Shows "No reset events in this period" with bar hidden.

### Display Context

- **24h and 7d views:** Usually contain one weekly reset at most, often none. Breakdown shows the visible reset, or "No reset events in this period".
- **30d+ views:** Breakdown aggregates all weekly resets in the selected period. This is where patterns emerge: "I consistently leave 30% of my week unused."

---

## User Journeys: Phase 3

### Journey 1: The Pattern Discovery

**Trigger:** Alex notices he keeps running low on Thursdays. He wants to understand why.

```
1. Alex clicks the sparkline in the popover
2. Analytics window opens, defaults to 24h view
3. Alex clicks [7d] to see the weekly pattern
4. The weekly series reveals: Monday steep climb, Tuesday-Wednesday moderate, Thursday hits the wall
5. Headroom breakdown shows almost no unused weekly capacity, cycle after cycle
6. Insight: "I'm not wasting capacity — I'm running into my weekly limit by Thursday"
7. Alex adjusts his weekly pacing strategy
```

**Emotional outcome:** Understanding, not frustration. The visualization distinguishes "you messed up" from "the system constrained you."

### Journey 2: The Burn Rate Warning

**Trigger:** Alex is heads-down coding. The menu bar shows `✳ 45% ↗` — the arrow appeared because run-out is now projected before the weekly reset.

```
1. Alex notices the ↗ in peripheral vision
2. Glances at menu bar: 45% weekly headroom, ahead of pace
3. Clicks to expand popover: weekly gauge shows
   - 45%, resets in 3d 2h
   - "Ahead of pace — runs out ~Thu 14:00"
4. The sparkline shows usage climbing above the even-pace diagonal
5. Decision: "At this rate I run out before the reset. Let me wrap up this task and slow down."
```

**Emotional outcome:** Informed pacing. The pace indicator gave early warning before color escalation.

### Journey 3: The Historical Audit

**Trigger:** End of month, Alex wants to understand his usage patterns.

```
1. Opens analytics window, selects [30d]
2. Bar chart shows daily peaks across the month
3. Pattern emerges: the weekly series climbs on weekdays and stays flat at weekends
4. Headroom breakdown: 35% of weekly capacity unused across the month's cycles
5. Insight: "I'm leaving a third of my capacity unused. I could do more weekend projects."
```

**Emotional outcome:** Awareness of habits, opportunity identification.

### Journey 4: The Gap Explanation

**Trigger:** Alex was on vacation for a week. Comes back, checks analytics.

```
1. Opens analytics window, selects [30d]
2. Sees a visible gap in the chart (hatched/grey region)
3. Hovers over gap: "No data — cc-hdrm not running (7 days)"
4. Usage before and after the gap is visible, but no fabricated data in between
5. Alex appreciates the honesty: "It doesn't pretend to know what happened while I was gone"
```

**Emotional outcome:** Trust in the data. The visualization admits what it doesn't know.

---

## Component Strategy: Phase 3

### New Custom Components

#### SlopeIndicator

Retired 2026-10-31 — replaced by the weekly pace line in the weekly gauge section and the menu bar actionable arrow (see Feature 1).

#### Sparkline

**Purpose:** Compact current-weekly-cycle usage visualization, acts as button to launch analytics.

**Props:**
- `data: [UsageDataPoint]` (polls since the last weekly reset)
- `onTap: () -> Void`
- `isAnalyticsOpen: Bool` (shows indicator dot when true)

**Rendering:**
- Step-area path honoring sawtooth shape
- Even-pace diagonal from cycle start (0%) to weekly reset (100%)
- Gaps as path breaks
- Subtle hover/press state
- Optional indicator dot when analytics window is open

**Accessibility:** "Weekly usage chart. Double-tap to open analytics."

#### UsageChart

**Purpose:** Main chart in analytics window, handles both step-area and bar modes.

**Props:**
- `data: [UsageDataPoint]` or `[RolledUpDataPoint]`
- `timeRange: TimeRange` (determines chart type)
- `visibleSeries: Set<Series>` (7d, Fable toggles; 5h historical, off by default)

**Rendering:**
- 24h: Step-area chart with weekly reset markers
- 7d+: Bar chart with peak values
- No slope bands (retired 2026-10-31)
- Gap regions as hatched/grey
- Hover tooltip with detailed info

**Accessibility:** Chart data available as accessible table for VoiceOver users.

#### HeadroomBreakdownBar

**Purpose:** Two-band stacked horizontal bar showing used / unused weekly capacity (revised 2026-10-31; 7d-constrained band retired).

**Props:**
- `used: Double` (percentage)
- `unused: Double` (percentage)

**Rendering:**
- Used: solid fill, headroom color
- Unused: light/empty fill

**Accessibility:** "Headroom breakdown: 52% used, 48% unused weekly capacity."

#### AnalyticsWindow

**Purpose:** Container for the full analytics view.

**Behavior:**
- NSPanel (utility window)
- No dock icon, no Cmd+Tab
- Remembers size/position
- Closeable via button or Escape

**Layout:** Time range selector, series toggles, UsageChart, HeadroomBreakdownBar, summary stats.

### Modified Components

#### MenuBarTextRenderer (Phase 1 component)

**Modification:** Add optional pace arrow suffix (revised 2026-10-31).

**New logic:**
- If run-out is projected before the weekly reset AND not exhausted/disconnected: append the actionable arrow
- Otherwise: no arrow (same as Phase 1)

#### HeadroomRingGauge (Phase 1 component)

**Modification:** Add pace line below the countdown on the weekly gauge (revised 2026-10-31; replaces the slope indicator).

**New layout:**
```
    ◯ (ring)
     78%
resets in...
On pace     ← pace line added
```

#### PopoverView (Phase 1 component)

**Modification:** Add sparkline section between the Fable section and footer. Revised 2026-10-31: the 5h gauge section is removed; the weekly gauge is first.

---

## Consistency Patterns: Phase 3

### Slope Communication Pattern

Revised 2026-10-31: slope is replaced by weekly pace, communicated consistently across all locations:

| Location        | No run-out before reset | Run-out before reset                  |
| --------------- | ----------------------- | ------------------------------------- |
| Menu bar        | Hidden                  | Actionable arrow (↗)                  |
| Popover weekly  | "On pace"               | "Ahead of pace — runs out ~Thu 14:00" |
| Analytics chart | No pace colouring       | No pace colouring                     |

### Gap Rendering Pattern

Gaps (periods when cc-hdrm wasn't running) are rendered consistently:

- **Sparkline:** Break in the line
- **24h chart:** Missing segment, no path drawn
- **7d+ bars:** Missing bars, subtle "no data" label on hover
- **Headroom breakdown:** Gaps excluded from calculation (only complete windows counted)

**Never interpolated.** The visualization admits what it doesn't know.

### Time Display Pattern

All timestamps follow the Phase 1 pattern (relative + absolute):

- **Chart X-axis:** Time labels appropriate to scale (hours for 24h, days for 30d)
- **Hover tooltip:** "Mon 2:34 PM" (absolute)
- **Reset markers:** "Reset at 4:52 PM"

---

## Accessibility: Phase 3

### New Accessibility Requirements

#### Slope Indicator
Revised 2026-10-31 — now the pace indicator:
- Pace line is text; the menu bar arrow shape conveys meaning (not color-only)
- VoiceOver reads the pace line ("ahead of pace, runs out around Thursday 14:00")
- VoiceOver reading order in the popover starts with the weekly gauge

#### Sparkline
- Accessible as button with label
- Chart data available as alternative text summary

#### Analytics Window
- Full keyboard navigation
- Time range buttons focusable
- Chart data available as accessible table
- Headroom breakdown announces both values

#### Charts
- Not relying on color alone — bars have distinct patterns, lines have distinct styles
- Hover information available via keyboard focus
- Summary statistics provide textual alternative to visual patterns

### Color Independence

All Phase 3 visualizations maintain color independence:

| Element            | Color Signal         | Non-Color Signal            |
| ------------------ | -------------------- | --------------------------- |
| Pace arrow         | Headroom color       | Arrow direction shape       |
| Used band          | Headroom color       | Solid fill pattern          |
| Unused capacity    | Light/transparent    | Empty/outline pattern       |
| Gap regions        | Grey                 | Hatched pattern + label     |

---

## Implementation Notes

### Credit Limit Lookup

cc-hdrm reads `rateLimitTier` from Keychain credentials. Map to weekly credit limits (revised 2026-10-31 — the 5h credit value is dropped; a custom tier needs only the weekly value):

```swift
enum RateLimitTier {
    case pro           // 5M / 7d
    case max5x         // 41.67M / 7d
    case max20x        // 83.33M / 7d
}
```

If tier is unknown or new, fall back to percentage-only display (no credit-based value math).

### Slope Calculation Buffering

Retired 2026-10-31 — replaced by weekly pace, which needs no poll buffer. It uses only the current `seven_day` utilization and `resets_at`. The run-out projection is withheld until ~4 hours of the week have passed.

### Analytics Window State

- Window position/size persisted to UserDefaults
- Time range selection persisted per session (not across launches)
- Series toggle state persisted per time range

### Data Migration

Phase 3 introduces SQLite storage. On first launch after upgrade:
- Create database schema
- Begin collecting data going forward
- No historical backfill (unless Anthropic historical API is discovered)

---

## Summary of Design Decisions

| Decision                          | Choice                                             |
| --------------------------------- | -------------------------------------------------- |
| Slope in menu bar                 | Replaced by pace: arrow only when run-out is projected before the weekly reset (revised 2026-10-31) |
| Sparkline data                    | Current weekly cycle with even-pace diagonal (revised 2026-10-31) |
| Default analytics series          | Weekly + Fable; 5h off, hidden when range has no 5h data (revised 2026-10-31) |
| Sparkline interaction             | Clickable, launches/recalls analytics window       |
| Analytics window type             | NSPanel (utility), no dock icon                    |
| Analytics recall                  | Sparkline as toggle                                |
| 24h chart type                    | Step-area (honors sawtooth shape)                  |
| 7d+ chart type                    | Bar chart (peak per period)                        |
| Slope on historical chart         | Retired — no per-point slope colouring (2026-10-31) |
| Headroom breakdown position       | Below chart, summary for selected period           |
| Headroom math                     | Per weekly cycle, two bands: used / unused (revised 2026-10-31) |
| Gap handling                      | Honest breaks, never interpolated                  |

---

## Open Questions / Future Considerations

1. **Historical API:** If Anthropic exposes a historical usage endpoint, cc-hdrm could backfill gaps. Research spike recommended.

2. **Slope threshold tuning:** Retired 2026-10-31 with the slope indicator. Pace follow-up instead: the average-since-reset projection is pessimistic after a heavy first day; upgrade path is to blend with a recent-window rate.

3. **Export functionality:** Future phase could allow exporting historical data (CSV, JSON) for external analysis.

4. **Notification for pace:** A "will run out before reset" notification is not included (2026-10-31). Add later if wanted.

5. **README acknowledgement:** When Phase 3 ships, add acknowledgement to README for [@she_llac](https://twitter.com/she_llac)'s reverse-engineering of Claude's credit limits ([suspiciously precise floats](https://she-llac.com/claude-limits)). Use Option C: both a dedicated Acknowledgements section AND inline reference in "How It Works" explaining the credit math.
