# Epic 13: Full Analytics Window (Phase 3)

Alex clicks the sparkline and a floating analytics panel appears — zoomable charts across all retention periods, time range selectors, series toggles, and honest gap rendering for periods when cc-hdrm wasn't running.

## Story 13.1: Analytics Window Shell (NSPanel)

As a developer using Claude Code,
I want an analytics window that behaves as a floating utility panel,
So that it's accessible without disrupting my main workflow or polluting the dock.

**Acceptance Criteria:**

**Given** the sparkline is clicked
**When** AnalyticsWindowController.toggle() is called
**Then** an NSPanel opens with the following characteristics:

- styleMask includes .nonactivatingPanel (doesn't steal focus)
- collectionBehavior does NOT include .canJoinAllSpaces (stays on current desktop)
- hidesOnDeactivate is false (stays visible when app loses focus)
- level is .floating (above normal windows, below fullscreen)
- No dock icon appears (app remains LSUIElement)
- No Cmd+Tab entry is added
  **And** default size is ~600×500px
  **And** the window is resizable with reasonable minimum size (~400×350px)

**Given** the analytics window is open
**When** Alex presses Escape or clicks the close button
**Then** the window closes
**And** AppState.isAnalyticsWindowOpen is set to false

**Given** the analytics window is closed and reopened
**When** the window appears
**Then** it restores its previous position and size (persisted to UserDefaults)

**Given** AnalyticsWindowController
**When** toggle() is called multiple times
**Then** it opens the window if closed, brings to front if open (no duplicates)
**And** the controller is a singleton

## Story 13.2: Analytics View Layout

As a developer using Claude Code,
I want a clear analytics view layout with time controls, chart, and breakdown,
So that I can explore my usage patterns effectively.

**Acceptance Criteria:**

**Given** the analytics window is open
**When** AnalyticsView renders
**Then** it displays (top to bottom):

- Title bar: "Usage Analytics" with close button
- Time range selector: [24h] [7d] [30d] [All] buttons
- Series toggles: 5h (filled circle) | 7d (empty circle) toggle buttons
- Main chart area (UsageChart component)
- Headroom breakdown section (HeadroomBreakdownBar + stats)
  **And** vertical spacing follows macOS design guidelines

**Given** the window is resized
**When** AnalyticsView re-renders
**Then** the chart area expands/contracts to fill available space
**And** controls and breakdown maintain their natural sizes

## Story 13.3: Time Range Selector

As a developer using Claude Code,
I want to select different time ranges to analyze my usage patterns,
So that I can see both recent detail and long-term trends.

**Acceptance Criteria:**

**Given** the analytics view is visible
**When** TimeRangeSelector renders
**Then** it shows four buttons: "24h", "7d", "30d", "All"
**And** one button is visually selected (filled/highlighted)
**And** default selection is "24h"

**Given** Alex clicks a time range button
**When** the selection changes
**Then** the chart and breakdown update to show data for that range
**And** data is loaded via HistoricalDataService with appropriate resolution
**And** ensureRollupsUpToDate() is called before querying

**Given** Alex selects "All"
**When** the data loads
**Then** it includes daily summaries from the full retention period
**And** if retention is 1 year, "All" shows up to 365 data points

## Story 13.4: Series Toggle Controls

As a developer using Claude Code,
I want to toggle 5h and 7d series visibility,
So that I can focus on the window that matters for my analysis.

**Acceptance Criteria:**

**Given** the series toggle controls are visible
**When** they render
**Then** "5h" and "7d" appear as toggle buttons with distinct visual states
**And** both are selected by default

**Given** Alex toggles off "7d"
**When** the chart re-renders
**Then** only the 5h series is visible
**And** the 7d toggle shows as unselected (outline only)

**Given** both series are toggled off
**When** the chart re-renders
**Then** the chart shows empty state with message: "Select a series to display"

**Given** a time range is selected
**When** the series toggle state is remembered
**Then** toggle state persists per time range within the session
**And** switching from 24h to 7d and back preserves the 24h toggle state

## Story 13.5: Usage Chart Component (Step-Area Mode)

As a developer using Claude Code,
I want a step-area chart for the 24h view that honors the sawtooth pattern,
So that I see an accurate representation of how utilization actually behaves.

**Acceptance Criteria:**

**Given** time range is "24h"
**When** UsageChart renders
**Then** it displays a step-area chart where:

- Steps only go UP within each window (monotonically increasing)
- Vertical drops mark reset boundaries (dashed vertical lines)
- X-axis shows time labels: "8am", "12pm", "4pm", "8pm", "12am", "4am", "now"
- Y-axis shows 0% to 100%
  **And** both 5h and 7d series can be overlaid (5h primary color, 7d secondary color)

**Given** slope was steep during a period
**When** the chart renders
**Then** background color bands (subtle warm tint) appear behind steep periods
**And** flat periods have no background tint

**Given** the user hovers over a data point
**When** the hover tooltip appears
**Then** it shows: timestamp (absolute), exact utilization %, slope level at that moment

## Story 13.6: Usage Chart Component (Bar Mode)

As a developer using Claude Code,
I want a bar chart for 7d+ views showing peak utilization per period,
So that long-term patterns are visible without visual clutter.

**Acceptance Criteria:**

**Given** time range is "7d"
**When** UsageChart renders
**Then** it displays a bar chart where:

- Each bar represents one hour
- Bar height = peak utilization during that hour (not average)
- Reset events are marked with subtle indicators below affected bars
- X-axis shows day/time labels appropriate to the range

**Given** time range is "30d"
**When** UsageChart renders
**Then** each bar represents one day
**And** bar height = peak utilization for that day

**Given** time range is "All"
**When** UsageChart renders
**Then** each bar represents one day (daily summaries)
**And** X-axis shows date labels with appropriate spacing

**Given** the user hovers over a bar
**When** the hover tooltip appears
**Then** it shows: period range, min/avg/peak utilization for that period

## Story 13.7: Gap Rendering in Charts

As a developer using Claude Code,
I want gaps in historical data rendered honestly,
So that I trust the visualization isn't fabricating data.

**Acceptance Criteria:**

**Given** a gap exists in the 24h data (cc-hdrm wasn't running)
**When** UsageChart (step-area mode) renders
**Then** the gap is rendered as a missing segment — no path drawn
**And** the gap region has a subtle hatched/grey background

**Given** a gap exists in 7d+ data
**When** UsageChart (bar mode) renders
**Then** missing periods have no bar displayed
**And** hovering over the empty space shows: "No data — cc-hdrm not running"

**Given** a gap spans multiple periods
**When** the chart renders
**Then** the gap is visually continuous (not segmented per period)
**And** gap boundaries are clear
