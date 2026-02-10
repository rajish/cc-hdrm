# Epic 4: Detailed Usage Panel

Alex clicks to expand and sees the full picture — both usage windows with ring gauges, countdowns with relative and absolute times, subscription tier, data freshness, and app controls.

## Story 4.1: Popover Shell & Click-to-Expand

As a developer using Claude Code,
I want to click the menu bar icon to open a detailed usage panel,
So that I can see the full picture when I need more context than the glance provides.

**Acceptance Criteria:**

**Given** the menu bar item is visible
**When** Alex clicks the menu bar item
**Then** a SwiftUI popover opens below the status item with an arrow pointing to it
**And** the popover opens within 200ms (NFR2)
**And** the popover has a stacked vertical layout with proper macOS native styling

**Given** the popover is open
**When** Alex clicks the menu bar item again, clicks outside the popover, or presses Escape
**Then** the popover closes

**Given** the popover is open
**When** new data arrives from a poll cycle
**Then** the popover content updates live without closing

## Story 4.2: 5-Hour Headroom Ring Gauge with Countdown

As a developer using Claude Code,
I want to see a detailed 5-hour headroom gauge with countdown in the expanded panel,
So that I know exactly how much session capacity remains and when it resets.

**Acceptance Criteria:**

**Given** AppState contains valid 5-hour usage data
**When** the popover renders
**Then** it shows a circular ring gauge (96px diameter, 7px stroke) as the primary element
**And** the ring depletes clockwise from 12 o'clock as headroom decreases
**And** ring fill color matches the HeadroomState color token
**And** ring track (unfilled) uses system tertiary color
**And** percentage is displayed centered inside the ring, bold, headroom-colored
**And** "5h" label appears above the gauge in caption size, secondary color
**And** relative countdown appears below: "resets in 47m" (secondary text)
**And** absolute time appears below that: "at 4:52 PM" (tertiary text)

**Given** 5-hour headroom is at 0% (exhausted)
**When** the popover renders
**Then** the ring is empty (no fill), center shows "0%" in red
**And** countdown shows "resets in Xm" in headroom color (red) for emphasis

**Given** 5-hour data is unavailable (disconnected/no credentials)
**When** the popover renders
**Then** the ring is empty with grey track, center shows "—" in grey
**And** no countdown is displayed

**Given** gauge fill changes between poll cycles
**When** new data arrives
**Then** the ring animates smoothly to the new fill level (.animation(.easeInOut(duration: 0.5)))
**And** if accessibilityReduceMotion is enabled, the gauge snaps instantly

**Given** a VoiceOver user focuses the 5h gauge
**When** VoiceOver reads the element
**Then** it announces "5-hour headroom: [X] percent, resets in [relative], at [absolute]"

## Story 4.3: 7-Day Headroom Ring Gauge with Countdown

As a developer using Claude Code,
I want to see a detailed 7-day headroom gauge with countdown in the expanded panel,
So that I can track my weekly limit alongside the session limit.

**Acceptance Criteria:**

**Given** AppState contains valid 7-day usage data
**When** the popover renders
**Then** it shows a circular ring gauge (56px diameter, 4px stroke) below a hairline divider after the 5h gauge
**And** ring behavior matches Story 4.2 (depletes clockwise, color tokens, percentage centered, countdown below)
**And** "7d" label appears above the gauge
**And** relative countdown: "resets in 2d 1h"
**And** absolute time: "at Mon 7:05 PM"

**Given** 7-day data is unavailable or null in the API response
**When** the popover renders
**Then** the 7d gauge section is hidden entirely (not shown as grey/empty)

**Given** a VoiceOver user focuses the 7d gauge
**When** VoiceOver reads the element
**Then** it announces "7-day headroom: [X] percent, resets in [relative], at [absolute]"

## Story 4.4: Panel Footer — Tier, Freshness & Quit

As a developer using Claude Code,
I want to see my subscription tier, data freshness, and a quit option in the panel,
So that I have full context about my account and can control the app.

**Acceptance Criteria:**

**Given** AppState contains subscription tier data
**When** the popover renders the footer
**Then** subscription tier (e.g., "Max") appears left-aligned in caption size, tertiary color
**And** "Updated Xs ago" timestamp appears center-aligned in mini size, tertiary color
**And** a gear icon (SF Symbol) appears right-aligned

**Given** the timestamp is in the stale range (60s-5m)
**When** the footer renders
**Then** the "Updated Xm ago" text shows in amber/warning color

**Given** Alex clicks the gear icon
**When** the menu opens
**Then** it shows "Quit cc-hdrm" as a menu item
**And** selecting Quit terminates the application (FR24)
**And** the gear menu opens as a standard SwiftUI Menu dropdown
**And** selecting Quit closes the popover and terminates the app

## Story 4.5: Status Messages for Error States

As a developer using Claude Code,
I want to see clear error messages in the panel when the app is in a degraded state,
So that I understand what's happening and what (if anything) I need to do.

**Acceptance Criteria:**

**Given** AppState.connectionStatus indicates API unreachable
**When** the popover renders
**Then** a StatusMessageView appears between the gauges and footer
**And** it shows: "Unable to reach Claude API" (body, secondary color, centered)
**And** detail: "Last attempt: 30s ago" (caption, tertiary color, centered)

**Given** AppState.connectionStatus indicates token expired
**When** the popover renders
**Then** StatusMessageView shows: "Token expired" / "Run any Claude Code command to refresh"

**Given** AppState.connectionStatus indicates no credentials
**When** the popover renders
**Then** StatusMessageView shows: "No Claude credentials found" / "Run Claude Code to create them"

**Given** AppState indicates very stale data (> 5 minutes)
**When** the popover renders
**Then** StatusMessageView shows: "Data may be outdated" / "Last updated: Xm ago"

**Given** no error state exists
**When** the popover renders
**Then** StatusMessageView is not shown

**Given** a VoiceOver user focuses the StatusMessageView
**When** VoiceOver reads the element
**Then** it reads the full message and detail text
