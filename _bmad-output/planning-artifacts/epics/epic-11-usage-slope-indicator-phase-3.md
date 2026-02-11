# Epic 11: Usage Slope Indicator (Phase 3)

Alex sees not just where he stands, but how fast he's burning. A 4-level slope indicator (↘→↗⬆) appears in the menu bar when burn rate is actionable, and always in the popover for both windows.

## Story 11.1: Slope Calculation Service & Ring Buffer

As a developer using Claude Code,
I want cc-hdrm to track recent poll data and calculate usage slope,
So that burn rate can be displayed alongside utilization.

**Acceptance Criteria:**

**Given** the app launches
**When** SlopeCalculationService initializes
**Then** it maintains an in-memory ring buffer for the last 15 minutes of poll data (~30 data points at 30s intervals)
**And** SlopeCalculationService conforms to SlopeCalculationServiceProtocol for testability
**And** it calls HistoricalDataService.getRecentPolls(hours: 1) to bootstrap the buffer from SQLite

**Given** a new poll cycle completes
**When** SlopeCalculationService.addPoll() is called with the UsageResponse
**Then** the new data point is added to the ring buffer
**And** older data points beyond 15 minutes are evicted
**And** slope is recalculated for both 5h and 7d windows

**Given** the ring buffer contains less than 10 minutes of data
**When** calculateSlope() is called
**Then** it returns .flat (insufficient data to determine slope)

## Story 11.2: Slope Level Calculation & Mapping

As a developer using Claude Code,
I want burn rate mapped to discrete slope levels,
So that the display is simple and actionable rather than noisy continuous values.

**Acceptance Criteria:**

**Given** the ring buffer contains 10+ minutes of poll data for a window
**When** calculateSlope(for: .fiveHour) is called
**Then** it computes the average rate of change (% per minute) across the buffer
**And** maps the rate to SlopeLevel:

- Rate < 0.3% per min → .flat (→)
- Rate 0.3 to 1.5% per min → .rising (↗)
- Rate > 1.5% per min → .steep (⬆)

> **Note:** No `.cooling` level exists. Within a usage window, utilization is monotonically increasing — it can only reset (jump down), not decrease gradually. A 3-level indicator is sufficient.

**Given** slope is calculated for both windows
**When** the calculation completes
**Then** AppState.fiveHourSlope and AppState.sevenDaySlope are updated
**And** updates happen on @MainActor to ensure UI consistency

**Given** the SlopeLevel enum is defined
**When** referenced across the codebase
**Then** it includes properties: arrow (String), color (Color), accessibilityLabel (String)
**And** .flat uses secondary color; .rising and .steep use headroom color

## Story 11.3: Menu Bar Slope Display (Escalation-Only)

As a developer using Claude Code,
I want to see a slope arrow in the menu bar only when burn rate is actionable,
So that the compact footprint is preserved during calm periods.

**Acceptance Criteria:**

**Given** AppState.fiveHourSlope is .rising or .steep
**And** connection status is normal (not disconnected/expired)
**And** headroom is not exhausted
**When** MenuBarTextRenderer renders
**Then** it displays "✳ XX% ↗" or "✳ XX% ⬆" (slope arrow appended)
**And** the arrow uses the same color as the percentage

**Given** AppState.fiveHourSlope is .flat
**When** MenuBarTextRenderer renders
**Then** it displays "✳ XX%" (no arrow) — same as Phase 1

**Given** headroom is exhausted (showing countdown)
**When** MenuBarTextRenderer renders
**Then** it displays "✳ ↻ Xm" (no slope arrow) — countdown takes precedence

**Given** 7d headroom is promoted to menu bar (tighter constraint)
**When** MenuBarTextRenderer renders with slope
**Then** it uses AppState.sevenDaySlope instead of fiveHourSlope for the arrow

**Given** a VoiceOver user focuses the menu bar with slope visible
**When** VoiceOver reads the element
**Then** it announces "cc-hdrm: Claude headroom [X] percent, [state], [slope]" (e.g., "rising")

## Story 11.4: Popover Slope Display (Always Visible)

As a developer using Claude Code,
I want to see slope indicators on both gauges in the popover,
So that I have full visibility into burn rate for both windows.

**Acceptance Criteria:**

**Given** the popover is open
**When** HeadroomRingGauge renders for 5h window
**Then** a SlopeIndicator appears below the percentage inside/below the ring
**And** the slope level matches AppState.fiveHourSlope
**And** all four levels are visible in the popover (↘ → ↗ ⬆)

**Given** the popover is open
**When** HeadroomRingGauge renders for 7d window
**Then** a SlopeIndicator appears with AppState.sevenDaySlope
**And** display is consistent with the 5h gauge

**Given** slope data is insufficient (< 10 minutes of history)
**When** the popover renders
**Then** slope displays as → (flat) as the default

**Given** a VoiceOver user focuses a gauge
**When** VoiceOver reads the element
**Then** it announces slope as part of the gauge reading: "[window] headroom: [X] percent, [slope level]"

## Story 11.5: SlopeIndicator Component

As a developer using Claude Code,
I want a reusable SlopeIndicator component,
So that slope display is consistent across menu bar and popover.

**Acceptance Criteria:**

**Given** SlopeIndicator is instantiated with a SlopeLevel and size
**When** the view renders
**Then** it displays the appropriate arrow character (↘ → ↗ ⬆)
**And** color matches the level: secondary for flat, headroom color for rising/steep
**And** font size matches the size parameter

**Given** any SlopeIndicator instance
**When** accessibility is evaluated
**Then** it has .accessibilityLabel set to the slope level name ("flat", "rising", "steep")
