---
stepsCompleted: [step-01-validate-prerequisites, step-02-design-epics, step-03-create-stories, step-04-final-validation]
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/architecture.md
  - _bmad-output/planning-artifacts/ux-design-specification.md
---

# cc-hdrm - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for cc-hdrm, decomposing the requirements from the PRD, UX Design, and Architecture requirements into implementable stories.

## Requirements Inventory

### Functional Requirements

FR1: App can retrieve OAuth credentials from the macOS Keychain without user interaction
FR2: App can detect the user's subscription type and rate limit tier from stored credentials
FR3: App can fetch current usage data from the Claude usage API
FR4: App can handle API request failures with standard HTTP error handling (retry, timeout, graceful degradation)
FR5: App can detect when OAuth credentials have expired and display an actionable status message
FR6: User can see current 5-hour usage percentage in the menu bar at all times
FR7: User can see a color-coded indicator that reflects usage severity (green/yellow/orange/red)
FR8: User can click the menu bar icon to expand a detailed usage panel
FR9: User can see 5-hour usage bar with percentage in the expanded panel
FR10: User can see 7-day usage bar with percentage in the expanded panel
FR11: User can see time remaining until 5-hour window resets
FR12: User can see time remaining until 7-day window resets
FR13: User can see their subscription tier in the expanded panel
FR14: App can poll the usage API at regular intervals without user action
FR15: App can update the menu bar display automatically when new data arrives
FR16: App can continue running in the background with no visible main window
FR17: User can receive a macOS notification when 5-hour usage crosses 80% (headroom drops below 20%)
FR18: User can receive a macOS notification when 5-hour usage crosses 95% (headroom drops below 5%)
FR19: App can include the reset countdown time in notification messages
FR20: User can see a disconnected state indicator when the API is unreachable
FR21: User can see an explanation of the connection failure in the expanded panel
FR22: App can automatically resume normal display when connectivity returns
FR23: App can launch and display usage data without any manual configuration
FR24: User can quit the app from the menu bar

### NonFunctional Requirements

NFR1: Menu bar indicator updates within 2 seconds of receiving new API data
NFR2: Click-to-expand popover opens within 200ms of user click
NFR3: App memory usage remains under 50 MB during continuous operation
NFR4: CPU usage remains below 1% between polling intervals
NFR5: API polling completes within 10 seconds per request (including fallback attempts)
NFR6: OAuth credentials are read from Keychain at runtime and never persisted to disk, logs, or user defaults
NFR7: OAuth tokens are read fresh from Keychain each poll cycle and not cached in application state between cycles
NFR8: No credentials or usage data are transmitted to any endpoint other than api.anthropic.com (usage data) and platform.claude.com (token refresh)
NFR9: API requests use HTTPS exclusively
NFR10: App functions correctly when Claude Code credentials exist in the macOS Keychain
NFR11: App degrades gracefully when Keychain credentials are missing, expired, or malformed
NFR12: App handles Claude API response format changes without crashing (defensive parsing)
NFR13: App resumes normal operation within one polling cycle after network connectivity returns

### Additional Requirements

**From Architecture:**
- Starter template: Xcode macOS App template (File → New → Project → macOS → App). Project initialization is first implementation step.
- Manual configuration after template: LSUIElement=true in Info.plist, Keychain access entitlement, NSStatusItem setup, remove default ContentView/window scene
- App architecture: MVVM with service layer, protocol-based interfaces for testability
- Minimum platform: macOS 14.0 (Sonoma) — required for @Observable macro (updates PRD from macOS 13+)
- Concurrency: async/await with structured concurrency, no GCD/DispatchQueue
- State management: Single @Observable AppState on @MainActor, services write via methods not direct property mutation
- API endpoint: GET https://api.anthropic.com/api/oauth/usage with Bearer token + anthropic-beta header
- Token refresh endpoint: POST https://platform.claude.com/v1/oauth/token — try refresh, fall back to "run Claude Code" message
- Keychain service name: "Claude Code-credentials", JSON with claudeAiOauth object
- Polling: Task.sleep loop, 30-second default interval
- Error handling: Single AppError enum, async throws on services, PollingEngine catches and maps to connectionStatus
- Logging: os.Logger with subsystem com.cc-hdrm.app, categories per service (keychain, api, polling, notification, token)
- Testing: Swift Testing framework, protocol-based service interfaces for mocking
- Zero external dependencies for MVP
- Project structure: layer-based (App/Models/Services/State/Views/Extensions/Resources)

**From UX Design:**
- HeadroomState enum with states: .normal (>40%), .caution (20-40%), .warning (5-20%), .critical (<5%), .exhausted (0%), .disconnected
- Menu bar: Claude sparkle icon (✳) prefix + percentage or countdown, color + weight escalation per state
- Context-adaptive display: percentage when capacity exists, countdown (↻ Xm) when exhausted
- Tighter constraint promotion: menu bar shows whichever window (5h/7d) is tighter when in warning/critical
- Popover: stacked vertical layout — 5h gauge (96px ring) primary, 7d gauge (56px ring) secondary
- Each gauge shows: percentage inside ring, relative countdown below, absolute time below that
- Notification content: "Claude [window] headroom at [X]% — resets in [relative] (at [absolute])"
- Notification thresholds: 20% headroom (warning), 5% headroom (critical) — fire once per crossing, re-arm on recovery
- Both 5h and 7d windows tracked independently for notifications
- Gauge animations: smooth fill transition, respect accessibilityReduceMotion
- Data freshness: <60s normal, 60s-5m stale warning in popover, >5m StatusMessageView
- Font weight escalation: Normal=Regular, Caution=Medium, Warning=Semibold, Critical/Exhausted=Bold, Disconnected=Regular
- All custom views require VoiceOver labels (.accessibilityLabel, .accessibilityValue)
- Color tokens: .headroomNormal, .headroomCaution, .headroomWarning, .headroomCritical, .headroomExhausted, .disconnected
- Semantic colors defined in Asset Catalog with light/dark variants
- Popover footer: subscription tier (left), "updated Xs ago" (center), gear menu with Quit (right)
- StatusMessageView for error states: disconnected, token expired, no credentials, stale data
- Countdown formatting: <1h "resets in 47m", 1-24h "resets in 2h 13m", >24h "resets in 2d 1h"
- Absolute time: same day "at 4:52 PM", different day "at Mon 7:05 PM"
- Countdown updates every 60 seconds (not every second)

### FR Coverage Map

FR1: Epic 1 - Keychain credential retrieval
FR2: Epic 1 - Subscription type/tier detection
FR3: Epic 2 - Fetch usage data from API
FR4: Epic 2 - API error handling (retry, timeout, degradation)
FR5: Epic 1 - Token expiry detection + actionable message
FR6: Epic 3 - Menu bar 5h percentage display
FR7: Epic 3 - Color-coded usage indicator
FR8: Epic 4 - Click-to-expand panel
FR9: Epic 4 - 5h usage bar in popover
FR10: Epic 4 - 7d usage bar in popover
FR11: Epic 4 - 5h reset countdown
FR12: Epic 4 - 7d reset countdown
FR13: Epic 4 - Subscription tier in popover
FR14: Epic 2 - Background polling at regular intervals
FR15: Epic 2 - Auto-update menu bar on new data
FR16: Epic 1 - Background running, no main window
FR17: Epic 5 - Notification at 80% usage (20% headroom)
FR18: Epic 5 - Notification at 95% usage (5% headroom)
FR19: Epic 5 - Reset countdown in notifications
FR20: Epic 2 - Disconnected state indicator
FR21: Epic 2 - Connection failure explanation in panel
FR22: Epic 2 - Auto-resume on connectivity return
FR23: Epic 1 - Zero-config launch
FR24: Epic 4 - Quit from menu bar

## Epic List

### Epic 1: Zero-Config Launch & Credential Discovery
Alex launches the app and it silently finds his Claude credentials — or shows him exactly what's wrong. App runs as menu bar utility (no dock icon, no main window), reads OAuth credentials from macOS Keychain, detects subscription tier, and handles token expiry with clear actionable messaging.
**FRs covered:** FR1, FR2, FR5, FR16, FR23

### Epic 2: Live Usage Data Pipeline
Alex's usage data flows automatically — the app fetches from the Claude API in the background and keeps itself current, handling errors gracefully with auto-recovery.
**FRs covered:** FR3, FR4, FR14, FR15, FR20, FR21, FR22

### Epic 3: Always-Visible Menu Bar Headroom
Alex glances at his menu bar and instantly knows how much headroom he has — color-coded, weight-escalated percentage that registers in peripheral vision in under one second.
**FRs covered:** FR6, FR7

### Epic 4: Detailed Usage Panel
Alex clicks to expand and sees the full picture — both usage windows with ring gauges, countdowns with relative and absolute times, subscription tier, data freshness, and app controls.
**FRs covered:** FR8, FR9, FR10, FR11, FR12, FR13, FR24

### Epic 5: Threshold Notifications
Alex gets notified before he hits the wall — macOS notifications fire at 20% and 5% headroom for both windows independently, with full context including reset countdowns and absolute times. Never misses a warning, even when AFK.
**FRs covered:** FR17, FR18, FR19

## Epic 1: Zero-Config Launch & Credential Discovery

Alex launches the app and it silently finds his Claude credentials — or shows him exactly what's wrong. App runs as menu bar utility (no dock icon, no main window), reads OAuth credentials from macOS Keychain, detects subscription tier, and handles token expiry with clear actionable messaging.

### Story 1.1: Xcode Project Initialization & Menu Bar Shell

As a developer,
I want a properly configured Xcode project with a menu bar presence,
So that I have the foundation for all subsequent features.

**Acceptance Criteria:**

**Given** a fresh clone of the repository
**When** the developer opens and builds the project in Xcode
**Then** the app compiles and launches as a menu bar-only utility (no dock icon, no main window)
**And** an NSStatusItem appears in the menu bar showing a placeholder "✳ --"
**And** Info.plist has LSUIElement=true
**And** the project targets macOS 14.0+ (Sonoma)
**And** Keychain access entitlement is configured
**And** the project structure follows the Architecture's layer-based layout (App/, Models/, Services/, State/, Views/, Extensions/, Resources/)
**And** HeadroomState enum is defined with states: .normal, .caution, .warning, .critical, .exhausted, .disconnected
**And** AppError enum is defined with all error cases from Architecture
**And** AppState is created as @Observable @MainActor with placeholder properties

### Story 1.2: Keychain Credential Discovery

As a developer using Claude Code,
I want the app to automatically find my OAuth credentials in the macOS Keychain,
So that I never need to configure anything manually.

**Acceptance Criteria:**

**Given** Claude Code credentials exist in the Keychain (service: "Claude Code-credentials")
**When** the app launches
**Then** the app reads and parses the claudeAiOauth JSON object from the Keychain
**And** the app extracts accessToken, refreshToken, expiresAt, subscriptionType, and rateLimitTier
**And** the subscription tier is stored in AppState
**And** credentials are never persisted to disk, logs, or UserDefaults (NFR6)
**And** all Keychain access goes through KeychainServiceProtocol

**Given** no Claude Code credentials exist in the Keychain
**When** the app launches
**Then** the menu bar shows "✳ —" in grey
**And** a StatusMessageView-compatible status is set: "No Claude credentials found" / "Run Claude Code to create them"
**And** the app polls the Keychain every 30 seconds for new credentials
**And** when credentials appear, the app transitions to normal operation silently

**Given** the Keychain contains malformed JSON
**When** the app reads credentials
**Then** the app logs the parse error via os.Logger (keychain category)
**And** treats it as "no credentials" state
**And** does not crash (NFR11)

### Story 1.3: Token Expiry Detection & Refresh

As a developer using Claude Code,
I want the app to detect expired tokens and attempt refresh automatically,
So that I maintain continuous usage visibility without manual intervention.

**Acceptance Criteria:**

**Given** credentials exist with an expiresAt timestamp in the past
**When** the app reads credentials during a poll cycle
**Then** the app attempts token refresh via POST to platform.claude.com/v1/oauth/token
**And** if refresh succeeds, the new access token is written back to the Keychain
**And** normal operation resumes — Alex never knows it happened

**Given** token refresh fails (network error, invalid refresh token, etc.)
**When** the refresh attempt completes
**Then** the menu bar shows "✳ —" in grey
**And** a status is set: "Token expired" / "Run any Claude Code command to refresh"
**And** the error is logged via os.Logger (token category)
**And** the app continues polling the Keychain every 30 seconds for externally refreshed credentials

**Given** credentials exist with expiresAt approaching (within 5 minutes)
**When** the app reads credentials during a poll cycle
**Then** the app pre-emptively attempts token refresh before expiry

## Epic 2: Live Usage Data Pipeline

Alex's usage data flows automatically — the app fetches from the Claude API in the background and keeps itself current, handling errors gracefully with auto-recovery.

### Story 2.1: API Client & Usage Data Fetch

As a developer using Claude Code,
I want the app to fetch my current usage data from the Claude API,
So that I have real headroom data to display.

**Acceptance Criteria:**

**Given** valid OAuth credentials are available from KeychainService
**When** the APIClient fetches usage data
**Then** it sends GET to `https://api.anthropic.com/api/oauth/usage`
**And** includes headers: `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-code/<version>`
**And** uses HTTPS exclusively (NFR9)
**And** the response is parsed into UsageResponse using Codable with CodingKeys (snake_case → camelCase)
**And** all response fields are optional — missing windows result in nil, not crashes (NFR12)
**And** unknown JSON keys are silently ignored

**Given** the API returns a non-200 status code
**When** the response is received
**Then** the error is mapped to AppError (.apiError with status code and body)
**And** a 401 specifically triggers the token refresh flow from Story 1.3

**Given** the network is unreachable or the request times out
**When** the fetch attempt fails
**Then** the error is mapped to AppError (.networkUnreachable)
**And** the request completes within 10 seconds (NFR5)

### Story 2.2: Background Polling Engine

As a developer using Claude Code,
I want the app to poll for usage data automatically in the background,
So that my headroom display is always current without any manual action.

**Acceptance Criteria:**

**Given** the app has successfully launched and credentials are available
**When** the polling engine starts
**Then** it executes a fetch cycle every 30 seconds using Task.sleep in structured concurrency
**And** each cycle: reads fresh credentials from Keychain (NFR7) → checks token expiry → fetches usage → updates AppState
**And** AppState.lastUpdated is set on each successful fetch
**And** the menu bar display updates automatically within 2 seconds of new data (NFR1)

**Given** a poll cycle fails (network error, API error, token expired)
**When** the PollingEngine catches the error
**Then** it maps the error to AppState.connectionStatus (disconnected, tokenExpired, etc.)
**And** the menu bar shows "✳ —" in grey (FR20)
**And** the expanded panel shows an explanation of the failure (FR21)
**And** polling continues — the next cycle attempts recovery automatically

**Given** connectivity returns after a disconnected period
**When** the next poll cycle succeeds
**Then** AppState.connectionStatus returns to normal
**And** the menu bar and panel resume showing live headroom data (FR22)
**And** recovery happens within one polling cycle (NFR13)

### Story 2.3: Data Freshness Tracking

As a developer using Claude Code,
I want the app to track and communicate data freshness,
So that I never see a number I can't trust as current.

**Acceptance Criteria:**

**Given** usage data was fetched successfully
**When** less than 60 seconds have elapsed since the last fetch
**Then** AppState reflects normal freshness (no warning)

**Given** usage data was fetched successfully
**When** 60 seconds to 5 minutes have elapsed since the last fetch
**Then** AppState reflects stale data state
**And** the popover timestamp shows "Updated Xm ago" in amber/warning color

**Given** usage data was fetched successfully
**When** more than 5 minutes have elapsed since the last fetch
**Then** AppState reflects very stale data state
**And** a StatusMessageView-compatible status is set: "Data may be outdated" / "Last updated: Xm ago"

**Given** the app has never successfully fetched data
**When** the display renders
**Then** the menu bar shows "✳ —" in grey (full disconnected state)
**And** no stale number is ever displayed

## Epic 3: Always-Visible Menu Bar Headroom

Alex glances at his menu bar and instantly knows how much headroom he has — color-coded, weight-escalated percentage that registers in peripheral vision in under one second.

### Story 3.1: Menu Bar Headroom Display with Color & Weight

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

### Story 3.2: Context-Adaptive Display & Tighter Constraint Promotion

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

## Epic 4: Detailed Usage Panel

Alex clicks to expand and sees the full picture — both usage windows with ring gauges, countdowns with relative and absolute times, subscription tier, data freshness, and app controls.

### Story 4.1: Popover Shell & Click-to-Expand

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

### Story 4.2: 5-Hour Headroom Ring Gauge with Countdown

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

### Story 4.3: 7-Day Headroom Ring Gauge with Countdown

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

### Story 4.4: Panel Footer — Tier, Freshness & Quit

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

### Story 4.5: Status Messages for Error States

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

## Epic 5: Threshold Notifications

Alex gets notified before he hits the wall — macOS notifications fire at 20% and 5% headroom for both windows independently, with full context including reset countdowns and absolute times. Never misses a warning, even when AFK.

### Story 5.1: Notification Permission & Service Setup

As a developer using Claude Code,
I want the app to set up macOS notification capabilities,
So that threshold alerts can be delivered when headroom drops.

**Acceptance Criteria:**

**Given** the app launches for the first time
**When** the NotificationService initializes
**Then** it requests notification authorization via UserNotifications framework
**And** authorization status is tracked in AppState or NotificationService internal state
**And** if the user denies permission, the app continues functioning without notifications (no crash, no nag)

**Given** the app launches on subsequent runs
**When** the NotificationService initializes
**Then** it checks existing authorization status without re-prompting

### Story 5.2: Threshold State Machine & Warning Notifications

As a developer using Claude Code,
I want to receive a macOS notification when my headroom drops below 20%,
So that I can make informed decisions about which Claude sessions to prioritize.

**Acceptance Criteria:**

**Given** 5-hour headroom is above 20%
**When** a poll cycle reports 5-hour headroom below 20%
**Then** a macOS notification fires: "Claude headroom at [X]% — resets in [relative] (at [absolute])" (FR17, FR19)
**And** the notification is standard (not persistent)
**And** the threshold state transitions from ABOVE_20 to WARNED_20

**Given** the 5-hour threshold state is WARNED_20
**When** subsequent poll cycles report headroom still below 20% but above 5%
**Then** no additional notification fires (fire once per crossing)

**Given** 7-day headroom drops below 20% independently of 5-hour
**When** a poll cycle reports the crossing
**Then** a separate notification fires: "Claude 7-day headroom at [X]% — resets in [relative] (at [absolute])"
**And** 5h and 7d threshold states are tracked independently

**Given** headroom recovers above 20% (window reset)
**When** a poll cycle reports the recovery
**Then** the threshold state resets to ABOVE_20 (re-armed)
**And** if headroom drops below 20% again, a new notification fires

### Story 5.3: Critical Threshold & Persistent Notifications

As a developer using Claude Code,
I want to receive a persistent notification when my headroom drops below 5%,
So that I have maximum warning to wrap up before hitting the limit.

**Acceptance Criteria:**

**Given** the threshold state is WARNED_20 (already received 20% warning)
**When** a poll cycle reports headroom below 5%
**Then** a persistent macOS notification fires with sound: "Claude headroom at [X]% — resets in [relative] (at [absolute])" (FR18, FR19)
**And** the notification remains in Notification Center
**And** the threshold state transitions from WARNED_20 to WARNED_5

**Given** headroom drops directly from above 20% to below 5% in a single poll
**When** the crossing is detected
**Then** only the critical (5%) notification fires (skip the 20% notification — go straight to the more urgent alert)
**And** the threshold state transitions to WARNED_5

**Given** the threshold state is WARNED_5
**When** subsequent poll cycles report headroom still below 5%
**Then** no additional notification fires

**Given** headroom recovers above 20% after being in WARNED_5
**When** a poll cycle reports the recovery
**Then** both thresholds re-arm (state returns to ABOVE_20)

**Given** notification permission was denied by the user
**When** a threshold crossing occurs
**Then** no notification is attempted, no error is shown
**And** the menu bar color/weight changes still reflect the state (visual fallback)
