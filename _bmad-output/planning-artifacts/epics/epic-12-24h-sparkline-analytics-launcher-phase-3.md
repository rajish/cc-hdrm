# Epic 12: 24h Sparkline & Analytics Launcher (Phase 3)

Alex glances at the popover and sees a compact 24-hour usage trend — a step-area sparkline showing the sawtooth pattern of his recent sessions. Clicking it opens the analytics window.

## Story 12.1: Sparkline Data Preparation

As a developer using Claude Code,
I want the popover to have sparkline data ready instantly,
So that opening the popover never feels slow.

**Acceptance Criteria:**

**Given** a successful poll cycle completes
**When** PollingEngine updates AppState
**Then** it also updates AppState.sparklineData by calling HistoricalDataService.getRecentPolls(hours: 24)
**And** sparklineData is refreshed on every poll cycle (kept current)

**Given** the app just launched and historical data exists
**When** the first poll cycle completes
**Then** sparklineData is populated from SQLite (bootstrap from history)

**Given** no historical data exists (fresh Phase 3 install)
**When** the popover opens before any data is collected
**Then** the sparkline area shows a placeholder: "Building history..." in secondary text
**And** after ~30 minutes of polling, enough data exists to render a meaningful sparkline

## Story 12.2: Sparkline Component

As a developer using Claude Code,
I want a compact sparkline showing the 24h usage sawtooth pattern,
So that I can see recent trends at a glance without opening analytics.

**Acceptance Criteria:**

**Given** AppState.sparklineData contains 24h of poll data
**When** Sparkline component renders
**Then** it displays a step-area chart (not line chart) honoring the monotonically increasing nature of utilization
**And** only 5h utilization is shown (7d is too slow-moving for 24h sparkline)
**And** reset boundaries are visible as vertical drops to the baseline
**And** the sparkline fits in approximately 200×40px in the popover

**Given** gaps exist in the sparkline data (cc-hdrm wasn't running)
**When** Sparkline renders
**Then** gaps are rendered as breaks in the path — no interpolation, no fake data
**And** gap regions are subtly distinct (slight grey tint or dashed baseline)

**Given** the sparkline data is empty or insufficient
**When** Sparkline renders
**Then** it shows placeholder text instead of an empty chart

**Given** a VoiceOver user focuses the sparkline
**When** VoiceOver reads the element
**Then** it announces "24-hour usage chart. Double-tap to open analytics."

## Story 12.3: Sparkline as Analytics Toggle

As a developer using Claude Code,
I want to click the sparkline to open the analytics window,
So that deeper analysis is one click away from the popover.

**Acceptance Criteria:**

**Given** the sparkline is visible in the popover
**When** Alex clicks/taps the sparkline
**Then** the analytics window opens (or comes to front if already open)
**And** the popover remains open (does not auto-close)

**Given** the analytics window is already open
**When** Alex clicks the sparkline
**Then** the analytics window comes to front (orderFront)
**And** no duplicate window is created

**Given** the analytics window is open
**When** the popover renders the sparkline
**Then** a subtle indicator dot appears on the sparkline to show the window is open

**Given** the sparkline has hover/press states
**When** Alex hovers over the sparkline
**Then** a subtle background highlight indicates it's clickable
**And** cursor changes to pointer (hand) on hover

## Story 12.4: PopoverView Integration

As a developer using Claude Code,
I want the sparkline integrated into the existing popover layout,
So that the Phase 3 feature enhances without disrupting the Phase 1 design.

**Acceptance Criteria:**

**Given** the popover is open
**When** PopoverView renders
**Then** the layout is: 5h gauge → 7d gauge → sparkline section → footer
**And** a hairline divider separates the sparkline from the gauges above
**And** a hairline divider separates the sparkline from the footer below

**Given** AppState.isAnalyticsWindowOpen is true
**When** the popover renders
**Then** the sparkline shows the indicator dot (visual link between popover and analytics)
