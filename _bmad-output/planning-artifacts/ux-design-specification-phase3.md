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

---

## Executive Summary

Phase 3 extends cc-hdrm from a real-time fuel gauge into a historical analytics platform. Three interconnected features give Alex visibility not just into *where he stands now*, but *how he got here* and *how fast he's moving*:

1. **Historical Usage Tracking** — Persistent storage of poll data, 24h sparkline in popover, full analytics window
2. **Underutilised Headroom Analysis** — Three-band breakdown showing used capacity, 7d-constrained capacity, and true waste
3. **Usage Slope Indicator** — Discrete burn rate arrows in menu bar and popover

These features preserve cc-hdrm's core identity as invisible infrastructure while adding depth for users who want to understand their usage patterns.

### Design Principles Carried Forward

From the Phase 1 UX spec, these principles remain sacred:

- **Peripheral first** — The menu bar glance is still the primary interface
- **Silent until relevant** — New features escalate only when they add value
- **Invisible infrastructure** — The analytics window is a tool you summon, not a presence you manage
- **Never lose a warning** — Historical data ensures patterns are never silently lost

### New Principle for Phase 3

- **Honest data, no predictions** — Show truthful historical data and current burn rate. Never pretend to predict the future.

---

## Feature 1: Usage Slope Indicator

### Problem

Alex knows *where* he stands (78% utilization) but not *how fast* he's burning capacity. Is this a steady cruise or a steep climb toward the wall?

### Solution

A discrete 4-level slope indicator showing burn rate, displayed contextually in the menu bar and always in the popover.

### Slope Levels

| Level       | Arrow | Meaning                  | Typical Scenario                          |
| ----------- | ----- | ------------------------ | ----------------------------------------- |
| **Cooling** | ↘     | Utilization decreasing   | Rolling window moving past older usage    |
| **Flat**    | →     | No meaningful change     | Idle, between sessions                    |
| **Rising**  | ↗     | Moderate consumption     | One active session, normal pace           |
| **Steep**   | ⬆     | Heavy consumption        | Multiple sessions or intense conversation |

### Calculation

- Sample last 10-15 minutes of poll data
- Compute average rate of change (% per minute)
- Map to discrete levels:

| Rate (% / min) | Level   |
| -------------- | ------- |
| < -0.5         | Cooling |
| -0.5 to 0.3    | Flat    |
| 0.3 to 1.5     | Rising  |
| > 1.5          | Steep   |

Threshold values will require tuning with real usage data.

### Menu Bar Display: Escalation-Only

**Design decision:** The slope arrow appears in the menu bar **only** at Rising (↗) and Steep (⬆). At Flat and Cooling, it's hidden.

**Rationale:** This preserves the compact footprint principle from Phase 1. During the 80% of time when things are calm, the menu bar stays minimal. The arrow earns its pixels only when the burn rate is actionable information.

| State                    | Menu Bar Display | Width     |
| ------------------------ | ---------------- | --------- |
| Normal, Flat/Cooling     | `✳ 83%`          | ~5 chars  |
| Normal, Rising           | `✳ 78% ↗`        | ~7 chars  |
| Normal, Steep            | `✳ 65% ⬆`        | ~7 chars  |
| Warning, Rising          | `✳ 17% ↗`        | ~7 chars  |
| Exhausted, any slope     | `✳ ↻ 12m`        | ~6 chars  |
| Disconnected             | `✳ —`            | ~3 chars  |

### Popover Display: Always Visible

Both gauges in the popover always show their slope indicator, regardless of level:

```
┌──────────────────┐
│    ◯ 5h gauge    │
│     78% ↗        │  ← slope always visible
│  resets in 1h 12m│
│  at 5:17 PM      │
├──────────────────┤
│    ◯ 7d gauge    │
│     42% →        │  ← even flat is shown
│  resets in 2d 1h │
│  at Mon 7:05 PM  │
└──────────────────┘
```

### Accessibility

- VoiceOver announces slope as part of gauge reading: "5-hour headroom: 78 percent, rising"
- Slope is never color-only — the arrow shape conveys meaning independently

---

## Feature 2: Historical Usage Tracking

### Problem

cc-hdrm currently discards poll data after display. Alex has no visibility into usage patterns over time.

### Solution

Persist each poll snapshot to SQLite, display a 24h sparkline in the popover, and provide a full analytics window for deep exploration.

### Data Storage

**Per-poll record:**
```
{ timestamp, 5h_utilization, 5h_resets_at, 7d_utilization, 7d_resets_at }
```

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
         5h window        reset
```

### Popover Sparkline

A compact 24-hour sparkline appears below the gauges, showing the shape of recent 5h utilization.

```
┌──────────────────┐
│    ◯ 5h gauge    │
│     78% ↗        │
│  resets in 1h 12m│
│  at 5:17 PM      │
├──────────────────┤
│    ◯ 7d gauge    │
│     42% →        │
│  resets in 2d 1h │
│  at Mon 7:05 PM  │
├──────────────────┤
│  24h ▁▂▃▅▇│▁▂▄▅  │  ← sparkline (5h only)
├──────────────────┤
│ Pro │ 12s ago │ ⚙ │
└──────────────────┘
```

**Sparkline design:**
- Shows 5h utilization only (7d moves too slowly for a 24h sparkline to be meaningful)
- Step-area style honoring the sawtooth shape
- Reset boundaries visible as vertical drops to baseline
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
│  [24h]  [7d]  [30d]  [All]          5h ● │ 7d ○        │
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
│  │▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░                       │    │
│  └─────────────────────────────────────────────────┘    │
│  ▓ Used: 52%   ░ 7d-constrained: 12%   □ Waste: 36%    │
│                                                         │
│  Avg peak: 64%  │  Total waste: 2.1M credits           │
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

`5h` and `7d` as toggleable overlays on the main chart.

- Both visible by default at 24h
- At 7d+ views, 7d becomes more interesting (slower-moving patterns)
- Toggle state persists per time range

### Main Chart: Hybrid Visualization

**24h view — Step Area Chart:**
- Honors the sawtooth shape: steps only go UP within windows
- Reset boundaries rendered as distinct vertical lines (dashed, subtle color)
- Gaps rendered as missing segments (no interpolation)
- Slope intensity shown via background color bands:
  - Steep periods: subtle warm tint behind the chart
  - Flat periods: no tint
  - This reinforces the slope without adding visual clutter

**7d+ views — Bar Chart:**
- Each bar represents one period (hour for 7d, day for 30d/All)
- Bar height = **peak utilization** for that period (not average)
- Rationale: "How close did I get to the wall?" is the question that matters
- Reset events marked with subtle indicator below affected bars

**Interaction:**
- Hover tooltip: timestamp, exact utilization %, slope at that moment
- For bars: period range, min/avg/peak for that period
- Scroll to zoom, drag to pan (24h view)

### Legend & Information

- Legend in top-right showing series colors (5h, 7d)
- Hover info provides detailed data points
- Gap periods labeled on hover: "No data (cc-hdrm not running)"

---

## Feature 4: Underutilised Headroom Analysis

### The Math

The 5h and 7d limits are both measured in **credits** (the internal unit reverse-engineered from API responses). This makes them directly comparable.

**Credit limits by tier:**

| Tier    | Credits/5h  | Credits/7d   |
| ------- | ----------- | ------------ |
| Pro     | 550,000     | 5,000,000    |
| Max 5×  | 3,300,000   | 41,666,700   |
| Max 20× | 11,000,000  | 83,333,300   |

**Calculation at each 5h reset:**

```
5h_remaining_credits = (100% - 5h_peak%) × 5h_limit
7d_remaining_credits = (100% - 7d_util%) × 7d_limit
effective_headroom_credits = min(5h_remaining_credits, 7d_remaining_credits)

true_waste_% = effective_headroom_credits / 5h_limit × 100%
7d_constrained_% = (5h_remaining_% - true_waste_%)
used_% = 5h_peak%
```

**Example (Max 5× user):**

5h peaked at 60%, 7d was at 85%:
- 5h remaining: 40% × 3,300,000 = 1,320,000 credits
- 7d remaining: 15% × 41,666,700 = 6,250,005 credits
- Effective headroom: 1,320,000 credits (5h was the constraint)
- True waste: 40% (all unused 5h was genuinely available)
- 7d-constrained: 0%

5h peaked at 60%, 7d was at 97%:
- 5h remaining: 1,320,000 credits
- 7d remaining: 3% × 41,666,700 = 1,250,001 credits
- Effective headroom: 1,250,001 credits (7d was the constraint)
- True waste: 1,250,001 / 3,300,000 = 37.9%
- 7d-constrained: 40% - 37.9% = 2.1%

### Three-Band Visualization

The headroom breakdown appears in the analytics window below the main chart.

```
100% ┌────────────────────────────────────────┐
     │              □ True waste              │ ← genuinely unused
     │         (both windows had room)        │
     ├────────────────────────────────────────┤
     │           ░ 7d-constrained             │ ← blocked by weekly limit
     │   (would've hit weekly wall anyway)    │   (NOT waste)
     ├────────────────────────────────────────┤
     │               ▓ Used                   │ ← actual consumption
     │         (peak 5h utilization)          │
  0% └────────────────────────────────────────┘
```

**Visual encoding:**
- **Used (▓)** — solid fill, headroom color based on peak level
- **7d-constrained (░)** — hatched/stippled pattern, muted slate blue. Visually reads as "blocked by system" not "you messed up"
- **True waste (□)** — light/empty, faint fill or outline only. The "could've been yours" signal

**Emotional framing:**
- True waste → "You left capacity on the table"
- 7d-constrained → "You were right to leave this — pushing harder would've blown your week"

### Summary Statistics

Below the three-band bar:
- **Avg peak:** Average of peak utilization across resets in selected period
- **Total waste:** Sum of true waste in credits (gives absolute sense of scale)
- **7d-constrained:** Percentage of unused capacity that was blocked by weekly limit

### Display Context

- **24h view:** May show only 1-2 resets. Breakdown shows aggregate for visible resets.
- **7d+ views:** Breakdown aggregates all resets in the selected period. This is where patterns emerge: "I consistently leave 30% on the table on weekends."

---

## User Journeys: Phase 3

### Journey 1: The Pattern Discovery

**Trigger:** Alex notices he keeps running low on Thursdays. He wants to understand why.

```
1. Alex clicks the sparkline in the popover
2. Analytics window opens, defaults to 24h view
3. Alex clicks [7d] to see the weekly pattern
4. The sawtooth pattern reveals: Monday steep climb, Tuesday-Wednesday moderate, Thursday hits the wall
5. Headroom breakdown shows: minimal waste Mon-Wed (good), but Thursday's 7d-constrained band is large
6. Insight: "I'm not wasting capacity — I'm running into my weekly limit by Thursday"
7. Alex adjusts his weekly pacing strategy
```

**Emotional outcome:** Understanding, not frustration. The visualization distinguishes "you messed up" from "the system constrained you."

### Journey 2: The Burn Rate Warning

**Trigger:** Alex is heads-down coding. The menu bar shows `✳ 45% ⬆` — the steep arrow appeared.

```
1. Alex notices the ⬆ in peripheral vision
2. Glances at menu bar: 45% with steep burn rate
3. Clicks to expand popover: sees both gauges with slopes
   - 5h: 45% ⬆ (steep)
   - 7d: 78% ↗ (rising)
4. The sparkline shows a sharp recent climb
5. Decision: "I'm burning fast and 7d is getting tight. Let me wrap up this task and pause."
```

**Emotional outcome:** Informed pacing. The slope indicator gave early warning before color escalation.

### Journey 3: The Historical Audit

**Trigger:** End of month, Alex wants to understand his usage patterns.

```
1. Opens analytics window, selects [30d]
2. Bar chart shows daily peaks across the month
3. Pattern emerges: weekdays average 70% peak, weekends 20%
4. Headroom breakdown: 35% true waste (mostly weekends)
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

**Purpose:** Display the discrete slope arrow with appropriate styling.

**Props:**
- `slope: SlopeLevel` (`.cooling`, `.flat`, `.rising`, `.steep`)
- `size: CGFloat` (matches adjacent text size)

**Rendering:**
- Cooling: ↘ (system secondary color)
- Flat: → (system secondary color)
- Rising: ↗ (headroom color)
- Steep: ⬆ (headroom color, slightly bolder)

**Accessibility:** Announces slope level ("rising", "steep", etc.)

#### Sparkline

**Purpose:** Compact 24h usage visualization, acts as button to launch analytics.

**Props:**
- `data: [UsageDataPoint]` (last 24h of polls)
- `onTap: () -> Void`
- `isAnalyticsOpen: Bool` (shows indicator dot when true)

**Rendering:**
- Step-area path honoring sawtooth shape
- Gaps as path breaks
- Subtle hover/press state
- Optional indicator dot when analytics window is open

**Accessibility:** "24-hour usage chart. Double-tap to open analytics."

#### UsageChart

**Purpose:** Main chart in analytics window, handles both step-area and bar modes.

**Props:**
- `data: [UsageDataPoint]` or `[RolledUpDataPoint]`
- `timeRange: TimeRange` (determines chart type)
- `visibleSeries: Set<Series>` (5h, 7d toggles)
- `slopeBands: Bool` (show background color bands)

**Rendering:**
- 24h: Step-area chart with reset markers
- 7d+: Bar chart with peak values
- Slope bands as subtle background shading
- Gap regions as hatched/grey
- Hover tooltip with detailed info

**Accessibility:** Chart data available as accessible table for VoiceOver users.

#### HeadroomBreakdownBar

**Purpose:** Three-band stacked horizontal bar showing used/7d-constrained/waste.

**Props:**
- `used: Double` (percentage)
- `sevenDayConstrained: Double` (percentage)
- `trueWaste: Double` (percentage)

**Rendering:**
- Used: solid fill, headroom color
- 7d-constrained: hatched pattern, muted slate blue
- True waste: light/empty fill

**Accessibility:** "Headroom breakdown: 52% used, 12% constrained by weekly limit, 36% unused."

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

**Modification:** Add optional slope arrow suffix.

**New logic:**
- If slope is Rising or Steep AND not exhausted/disconnected: append arrow
- Otherwise: no arrow (same as Phase 1)

#### HeadroomRingGauge (Phase 1 component)

**Modification:** Add slope indicator below percentage.

**New layout:**
```
    ◯ (ring)
     78%
      ↗     ← slope indicator added
resets in...
```

#### PopoverView (Phase 1 component)

**Modification:** Add sparkline section between 7d gauge and footer.

---

## Consistency Patterns: Phase 3

### Slope Communication Pattern

Slope is communicated consistently across all locations:

| Location        | Flat/Cooling | Rising | Steep |
| --------------- | ------------ | ------ | ----- |
| Menu bar        | Hidden       | ↗      | ⬆     |
| Popover 5h      | →/↘          | ↗      | ⬆     |
| Popover 7d      | →/↘          | ↗      | ⬆     |
| Analytics chart | No tint      | Tint   | Tint  |

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
- Arrow shape conveys meaning (not color-only)
- VoiceOver announces level name ("rising", "steep")

#### Sparkline
- Accessible as button with label
- Chart data available as alternative text summary

#### Analytics Window
- Full keyboard navigation
- Time range buttons focusable
- Chart data available as accessible table
- Headroom breakdown announces all three values

#### Charts
- Not relying on color alone — bars have distinct patterns, lines have distinct styles
- Hover information available via keyboard focus
- Summary statistics provide textual alternative to visual patterns

### Color Independence

All Phase 3 visualizations maintain color independence:

| Element            | Color Signal         | Non-Color Signal            |
| ------------------ | -------------------- | --------------------------- |
| Slope arrow        | Headroom color       | Arrow direction shape       |
| Slope bands        | Warm tint            | Presence/absence of tint    |
| Used band          | Headroom color       | Solid fill pattern          |
| 7d-constrained     | Slate blue           | Hatched pattern             |
| True waste         | Light/transparent    | Empty/outline pattern       |
| Gap regions        | Grey                 | Hatched pattern + label     |

---

## Implementation Notes

### Credit Limit Lookup

cc-hdrm reads `rateLimitTier` from Keychain credentials. Map to credit limits:

```swift
enum RateLimitTier {
    case pro           // 550K / 5h, 5M / 7d
    case max5x         // 3.3M / 5h, 41.67M / 7d
    case max20x        // 11M / 5h, 83.33M / 7d
}
```

If tier is unknown or new, fall back to percentage-only display (no headroom breakdown math).

### Slope Calculation Buffering

Slope calculation requires 10-15 minutes of poll history. On fresh launch:
- First ~10 minutes: slope displays as Flat (insufficient data)
- After buffer fills: slope calculation activates

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
| Slope in menu bar                 | Escalation-only (Rising/Steep visible, Flat/Cooling hidden) |
| Sparkline data                    | 5h only                                            |
| Sparkline interaction             | Clickable, launches/recalls analytics window       |
| Analytics window type             | NSPanel (utility), no dock icon                    |
| Analytics recall                  | Sparkline as toggle                                |
| 24h chart type                    | Step-area (honors sawtooth shape)                  |
| 7d+ chart type                    | Bar chart (peak per period)                        |
| Slope on historical chart         | Background color bands (subtle tint)               |
| Headroom breakdown position       | Below chart, summary for selected period           |
| Headroom math                     | Uses actual credit limits per tier                 |
| Gap handling                      | Honest breaks, never interpolated                  |

---

## Open Questions / Future Considerations

1. **Historical API:** If Anthropic exposes a historical usage endpoint, cc-hdrm could backfill gaps. Research spike recommended.

2. **Slope threshold tuning:** The % per minute thresholds for Rising/Steep need validation with real usage data. May need per-tier adjustment.

3. **Export functionality:** Future phase could allow exporting historical data (CSV, JSON) for external analysis.

4. **Notification for slope:** Should a sustained Steep slope trigger a notification? ("You're burning fast — 15 minutes at this rate will hit the wall.") Deferred to avoid prediction territory.

5. **README acknowledgement:** When Phase 3 ships, add acknowledgement to README for [@she_llac](https://twitter.com/she_llac)'s reverse-engineering of Claude's credit limits ([suspiciously precise floats](https://she-llac.com/claude-limits)). Use Option C: both a dedicated Acknowledgements section AND inline reference in "How It Works" explaining the credit math.
