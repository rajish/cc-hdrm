---
stepsCompleted: [step-01-validate-prerequisites, step-02-design-epics, step-03-create-stories, step-04-final-validation, phase-2-epics-added, phase-3-epics-added]
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/architecture.md
  - _bmad-output/planning-artifacts/ux-design-specification.md
  - _bmad-output/planning-artifacts/ux-design-specification-phase3.md
lastUpdated: '2026-02-03'
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
FR25: User can see when a newer version is available via a dismissable badge in the expanded panel; once dismissed, the badge does not reappear until a newer version is released (Phase 2)
FR26: User can access a direct download link for the latest version from within the expanded panel (Phase 2)
FR27: User can configure notification headroom thresholds, replacing the hardcoded 20% and 5% defaults (Phase 2)
FR28: User can configure the polling interval, replacing the hardcoded 30-second default (Phase 2)
FR29: User can enable launch at login so the app starts automatically on macOS boot (Phase 2)
FR30: User can access a settings view from the gear menu to configure preferences (Phase 2)
FR31: Maintainer can trigger a semver release by including [patch], [minor], or [major] in a PR title merged to master (Phase 2)
FR32: Release changelog is auto-generated from merged PR titles since last tag, with optional maintainer preamble (Phase 2)
FR33: App persists each poll snapshot (timestamp, 5h utilization, 5h resets_at, 7d utilization, 7d resets_at) to a local SQLite database (Phase 3)
FR34: App rolls up historical data at decreasing resolution as data ages, balancing storage efficiency with analytical granularity (Phase 3)
FR35: User can view a compact 24-hour usage trend of 5h utilization in the popover below existing gauges (Phase 3)
FR36: User can open a full analytics view in a separate window with zoomable historical charts across all retention periods (Phase 3)
FR37: App renders data gaps as a visually distinct state with no interpolation of missing data (Phase 3)
FR38: User can configure data retention period in settings (default 1 year) (Phase 3)
FR39: App calculates effective headroom as min(5h remaining capacity, 7d remaining capacity) (Phase 3)
FR40: App detects 5h window resets and classifies unused capacity into three categories: 5h waste, 7d-constrained (not waste), and true waste (Phase 3)
FR41: User can view a breakdown of used capacity, 7d-constrained capacity, and true available capacity in the analytics view (Phase 3)
FR42: App computes usage rate of change from recent poll history (Phase 3)
FR43: App maps rate of change to a discrete 4-level slope indicator (Cooling ↘, Flat →, Rising ↗, Steep ⬆) (Phase 3)
FR44: User can see the slope indicator inline next to the utilization percentage in the menu bar (Phase 3)
FR45: User can see per-window slope indicators in the popover for both 5h and 7d gauges (Phase 3)

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
FR25: Epic 8 - Dismissable update badge in popover
FR26: Epic 8 - Direct download link in popover
FR27: Epic 6 - Configurable notification thresholds
FR28: Epic 6 - Configurable poll interval
FR29: Epic 6 - Launch at login
FR30: Epic 6 - Settings view in gear menu
FR31: Epic 7 - Keyword-driven semver release
FR32: Epic 7 - Auto-generated changelog
FR33: Epic 10 - Persist poll snapshots to SQLite
FR34: Epic 10 - Tiered data rollup strategy
FR35: Epic 12 - 24h sparkline in popover
FR36: Epic 13 - Full analytics window with zoomable charts
FR37: Epic 12, 13 - Gap rendering in sparkline and charts
FR38: Epic 15 - Configurable data retention
FR39: Epic 14 - Effective headroom calculation
FR40: Epic 14 - Reset detection and waste classification
FR41: Epic 14 - Three-band headroom breakdown visualization
FR42: Epic 11 - Usage rate of change computation
FR43: Epic 11 - Discrete 4-level slope indicator mapping
FR44: Epic 11 - Slope indicator in menu bar
FR45: Epic 11 - Per-window slope indicators in popover

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

### Epic 6: User Preferences & Settings (Phase 2)
Alex tweaks cc-hdrm to fit his workflow — adjustable notification thresholds, custom poll interval, launch at login. All accessible from a settings view in the gear menu, all taking effect immediately.
**FRs covered:** FR27, FR28, FR29, FR30

### Epic 7: Release Infrastructure & CI/CD (Phase 2)
The maintainer merges a PR with `[minor]` in the title and walks away. GitHub Actions bumps the version, tags the release, builds the binary, generates a changelog from merged PRs, and publishes to GitHub Releases — no manual steps.
**FRs covered:** FR31, FR32

### Epic 8: In-App Update Awareness (Phase 2)
Alex sees a subtle badge in the popover when a new version is available — one click to download, one click to dismiss. No nag, no interruption, just awareness.
**FRs covered:** FR25, FR26

### Epic 9: Homebrew Tap Distribution (Phase 2)
A developer finds cc-hdrm, runs `brew install cc-hdrm`, and it works. Upgrades flow through `brew upgrade` automatically when new releases are published.
**FRs covered:** (supports FR25/FR26 Homebrew update path)

### Epic 10: Data Persistence & Historical Storage (Phase 3)
Alex's usage data is no longer ephemeral — every poll snapshot is persisted to SQLite, rolled up at decreasing resolution as it ages, creating a permanent record of usage patterns.
**FRs covered:** FR33, FR34

### Epic 11: Usage Slope Indicator (Phase 3)
Alex sees not just where he stands, but how fast he's burning. A 4-level slope indicator (↘→↗⬆) appears in the menu bar when burn rate is actionable, and always in the popover for both windows.
**FRs covered:** FR42, FR43, FR44, FR45

### Epic 12: 24h Sparkline & Analytics Launcher (Phase 3)
Alex glances at the popover and sees a compact 24-hour usage trend — a step-area sparkline showing the sawtooth pattern of his recent sessions. Clicking it opens the analytics window.
**FRs covered:** FR35, FR37 (sparkline gaps)

### Epic 13: Full Analytics Window (Phase 3)
Alex clicks the sparkline and a floating analytics panel appears — zoomable charts across all retention periods, time range selectors, series toggles, and honest gap rendering for periods when cc-hdrm wasn't running.
**FRs covered:** FR36, FR37 (chart gaps)

### Epic 14: Headroom Analysis & Waste Breakdown (Phase 3)
Alex sees the real story behind his usage — a three-band breakdown showing what he actually used, what was blocked by the weekly limit (not waste!), and what he genuinely left on the table.
**FRs covered:** FR39, FR40, FR41

### Epic 15: Phase 3 Settings & Data Retention (Phase 3)
Alex configures how long cc-hdrm keeps historical data and optionally overrides credit limits for unknown subscription tiers.
**FRs covered:** FR38

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

## Epic 6: User Preferences & Settings (Phase 2)

Alex tweaks cc-hdrm to fit his workflow — adjustable notification thresholds, custom poll interval, launch at login. All accessible from a settings view in the gear menu, all taking effect immediately.

### Story 6.1: Preferences Manager & UserDefaults Persistence

As a developer using Claude Code,
I want my preference changes to persist across app restarts,
So that I configure cc-hdrm once and it remembers my choices.

**Acceptance Criteria:**

**Given** the app launches for the first time (no UserDefaults entries exist)
**When** PreferencesManager initializes
**Then** it provides default values: warning threshold 20%, critical threshold 5%, poll interval 30s, launch at login false, dismissedVersion nil
**And** PreferencesManager conforms to PreferencesManagerProtocol for testability

**Given** the user changes a preference via the settings view
**When** the value is written to UserDefaults
**Then** it persists across app restarts
**And** the new value takes effect immediately without requiring restart

**Given** the user sets warning threshold to 15% and critical threshold to 3%
**When** the next poll cycle evaluates thresholds
**Then** NotificationService uses 15% and 3% instead of the defaults
**And** threshold state machines re-arm based on new thresholds

**Given** the user sets poll interval to 60 seconds
**When** the current poll cycle completes
**Then** PollingEngine waits 60 seconds before the next cycle (hot-reconfigurable)

**Given** UserDefaults contains an invalid value (e.g. poll interval of 5 seconds)
**When** PreferencesManager reads the value
**Then** it clamps to the valid range (min 10s, max 300s) and uses the clamped value
**And** warning threshold must be > critical threshold — if violated, defaults are restored

### Story 6.2: Settings View UI

As a developer using Claude Code,
I want to access a settings view from the gear menu,
So that I can configure cc-hdrm's behavior without editing files.

**Acceptance Criteria:**

**Given** the popover is open and Alex clicks the gear icon
**When** the gear menu appears
**Then** it shows "Settings..." as a menu item above "Quit cc-hdrm" (FR30)

**Given** Alex selects "Settings..."
**When** the settings view opens
**Then** it displays:
**And** Warning threshold: stepper or slider (range 6-50%, default 20%)
**And** Critical threshold: stepper or slider (range 1-49%, must be < warning threshold)
**And** Poll interval: picker with options 10s, 15s, 30s, 60s, 120s, 300s (default 30s)
**And** Launch at login: toggle switch (default off)
**And** "Reset to Defaults" button

**Given** Alex changes any preference value
**When** the value changes
**Then** it takes effect immediately (no save button required)
**And** the value is persisted to UserDefaults via @AppStorage bindings

**Given** Alex clicks "Reset to Defaults"
**When** the reset executes
**Then** all preferences return to default values (20%, 5%, 30s, off)
**And** changes take effect immediately

**Given** a VoiceOver user navigates the settings view
**When** VoiceOver reads each control
**Then** each has a descriptive accessibility label (e.g., "Warning notification threshold, 20 percent")

### Story 6.3: Configurable Notification Thresholds

As a developer using Claude Code,
I want to set my own notification thresholds,
So that I get alerted at the headroom levels that matter for my workflow.

**Acceptance Criteria:**

**Given** the user has set warning threshold to 30% and critical threshold to 10%
**When** 5-hour headroom drops below 30%
**Then** a warning notification fires with the same format as Story 5.2 (FR27)
**And** the 20% default is no longer used

**Given** the user has set critical threshold to 10%
**When** headroom drops below 10% (after warning has fired)
**Then** a critical notification fires with the same format as Story 5.3 (FR27)

**Given** the user changes thresholds while headroom is already below the old threshold
**When** the new threshold is set
**Then** the threshold state machine re-evaluates immediately against current headroom
**And** if headroom is above the new threshold, state resets to ABOVE_WARNING (re-armed)
**And** if headroom is below the new threshold and no notification fired for it yet, notification fires

### Story 6.4: Launch at Login

As a developer using Claude Code,
I want cc-hdrm to start automatically when I log in,
So that usage monitoring is always running without me remembering to launch it.

**Acceptance Criteria:**

**Given** the user enables "Launch at login" in settings
**When** the toggle is switched on
**Then** the app registers as a login item via SMAppService.mainApp.register() (FR29)
**And** on next macOS login, cc-hdrm launches automatically

**Given** the user disables "Launch at login" in settings
**When** the toggle is switched off
**Then** the app unregisters via SMAppService.mainApp.unregister()
**And** cc-hdrm no longer launches on login

**Given** the app launches
**When** PreferencesManager reads the launchAtLogin preference
**Then** the toggle in settings reflects the actual SMAppService.mainApp.status (not just the stored preference)
**And** if there's a mismatch (user changed it in System Settings), the UI reflects reality

## Epic 7: Release Infrastructure & CI/CD (Phase 2)

The maintainer merges a PR with `[minor]` in the title and walks away. GitHub Actions bumps the version, tags the release, builds the binary, generates a changelog from merged PRs, and publishes to GitHub Releases — no manual steps.

### Story 7.1: Semantic Versioning Scheme & CHANGELOG

As a project maintainer,
I want a consistent versioning scheme and changelog format,
So that users and contributors can track what changed between releases.

**Acceptance Criteria:**

**Given** the project repository
**When** a developer inspects versioning
**Then** the version lives in Info.plist (`CFBundleShortVersionString`) as the single source of truth
**And** git tags follow the format `v{major}.{minor}.{patch}` (e.g., `v1.0.0`, `v1.1.0`)
**And** CHANGELOG.md exists in the repo root

**Given** a new release is published
**When** the changelog is generated
**Then** the CHANGELOG.md contains a section `## [version] - YYYY-MM-DD`
**And** the section includes an auto-generated list of merged PR titles since the last tag
**And** if the release PR body contained content between `<!-- release-notes-start -->` and `<!-- release-notes-end -->` markers, that content appears as a preamble above the PR list

### Story 7.2: Pre-Merge Version Bump Workflow

As a project maintainer,
I want the version to be bumped automatically when I include a release keyword in a PR title,
So that I don't have to manually edit Info.plist or remember version numbers.

**Acceptance Criteria:**

**Given** a maintainer opens a PR with `[patch]` in the title
**When** the `release-prepare.yml` GitHub Actions workflow runs
**Then** it reads the current version from Info.plist
**And** bumps the patch component (e.g., `1.0.0` → `1.0.1`)
**And** commits the updated Info.plist back to the PR branch
**And** the commit message is: `chore: bump version to {new_version}`

**Given** a maintainer opens a PR with `[minor]` in the title
**When** the workflow runs
**Then** it bumps the minor component and resets patch (e.g., `1.0.1` → `1.1.0`)

**Given** a maintainer opens a PR with `[major]` in the title
**When** the workflow runs
**Then** it bumps the major component and resets minor + patch (e.g., `1.1.0` → `2.0.0`)

**Given** a PR title contains no release keyword
**When** the workflow evaluates the PR
**Then** no version bump occurs, no commit is made, the workflow exits cleanly

**Given** a non-maintainer opens a PR with a release keyword
**When** the workflow evaluates permissions
**Then** the version bump is skipped (only maintainers can trigger releases)
**And** a comment or annotation indicates the keyword was ignored due to permissions

### Story 7.3: Post-Merge Release Publish Workflow

As a project maintainer,
I want merging a release PR to automatically build, package, and publish,
So that the entire release process requires zero manual steps after merge.

**Acceptance Criteria:**

**Given** a PR with a version bump commit is merged to `master`
**When** the `release-publish.yml` GitHub Actions workflow runs
**Then** it detects the version from the bumped Info.plist
**And** tags `master` with `v{version}`
**And** auto-generates a changelog entry from merged PR titles since the previous tag
**And** if the merged PR body contained release notes between `<!-- release-notes-start -->` and `<!-- release-notes-end -->`, prepends that preamble
**And** updates CHANGELOG.md with the new entry and commits to `master`
**And** builds a universal binary (arm64 + x86_64) via `xcodebuild`
**And** creates a ZIP: `cc-hdrm-{version}-macos.zip`
**And** creates a GitHub Release with the changelog entry as body and the ZIP as an asset

**Given** a PR without a version bump commit is merged to `master`
**When** the workflow evaluates the merge
**Then** no release is triggered, the workflow exits cleanly

**Given** the build fails during the release workflow
**When** `xcodebuild` returns a non-zero exit code
**Then** the workflow fails, no GitHub Release is created, no tag is pushed
**And** the maintainer is notified via GitHub Actions failure notification

## Epic 8: In-App Update Awareness (Phase 2)

Alex sees a subtle badge in the popover when a new version is available — one click to download, one click to dismiss. No nag, no interruption, just awareness.

### Story 8.1: Update Check Service

As a developer using Claude Code,
I want the app to check for updates on launch,
So that I know when a newer version is available without leaving the app.

**Acceptance Criteria:**

**Given** the app launches
**When** UpdateCheckService runs
**Then** it fetches `https://api.github.com/repos/{owner}/{repo}/releases/latest`
**And** includes headers: `Accept: application/vnd.github.v3+json`, `User-Agent: cc-hdrm/<version>`
**And** compares the response `tag_name` (stripped of `v` prefix) against `Bundle.main.infoDictionary["CFBundleShortVersionString"]`
**And** UpdateCheckService conforms to UpdateCheckServiceProtocol for testability

**Given** the latest release version is newer than the running version
**When** the comparison completes
**Then** AppState.availableUpdate is set with the version string and download URL (browser_download_url of the ZIP asset, falling back to html_url)

**Given** the latest release version is equal to or older than the running version
**When** the comparison completes
**Then** AppState.availableUpdate remains nil, no badge is shown

**Given** the GitHub API request fails (network error, rate limit, etc.)
**When** the fetch fails
**Then** the failure is silent — no error state, no UI impact, no log noise beyond `.debug` level
**And** the app functions normally without update awareness

### Story 8.2: Dismissable Update Badge & Download Link

As a developer using Claude Code,
I want to see and dismiss an update badge in the popover,
So that I'm aware of updates without being nagged.

**Acceptance Criteria:**

**Given** AppState.availableUpdate is set (newer version available)
**And** PreferencesManager.dismissedVersion != the available version
**When** the popover renders
**Then** a subtle badge appears in the popover (e.g., above the footer or below the gauges): "v{version} available" with a download icon/link (FR25)
**And** the download link opens the release URL in the default browser (FR26)
**And** a dismiss button (X or "Dismiss") is visible next to the badge

**Given** Alex clicks the dismiss button
**When** the badge is dismissed
**Then** PreferencesManager.dismissedVersion is set to the available version
**And** the badge disappears immediately
**And** the badge does not reappear on subsequent launches or popover opens

**Given** a *newer* version is released after Alex dismissed a previous update
**When** UpdateCheckService detects a version newer than dismissedVersion
**Then** the badge reappears for the new version
**And** the cycle repeats (dismiss stores the new version)

**Given** Alex installed via Homebrew
**When** the update badge is shown
**Then** the badge also shows "or `brew upgrade cc-hdrm`" as alternative update path

**Given** a VoiceOver user focuses the update badge
**When** VoiceOver reads the element
**Then** it announces "Update available: version {version}. Activate to download. Double tap to dismiss."

## Epic 9: Homebrew Tap Distribution (Phase 2)

A developer finds cc-hdrm, runs `brew install cc-hdrm`, and it works. Upgrades flow through `brew upgrade` automatically when new releases are published.

### Story 9.1: Homebrew Tap Repository Setup

As a project maintainer,
I want a Homebrew tap repository with a working formula,
So that users can install cc-hdrm via `brew install`.

**Acceptance Criteria:**

**Given** the maintainer creates a separate repository `{owner}/homebrew-tap`
**When** the repository is configured
**Then** it contains `Formula/cc-hdrm.rb` with a valid Homebrew formula
**And** the formula downloads the ZIP asset from the latest GitHub Release
**And** the formula includes the correct SHA256 checksum of the ZIP
**And** the formula installs the cc-hdrm.app bundle to the appropriate location

**Given** a user runs `brew tap {owner}/tap && brew install cc-hdrm`
**When** Homebrew processes the formula
**Then** cc-hdrm is downloaded, extracted, and installed
**And** the user can launch cc-hdrm from the installed location

**Given** a user runs `brew upgrade cc-hdrm` after a new release
**When** the formula has been updated with the new version and SHA256
**Then** the new version is downloaded and installed, replacing the old version

### Story 9.2: Automated Homebrew Formula Update

As a project maintainer,
I want the Homebrew formula to be updated automatically when a release is published,
So that Homebrew users get new versions without manual formula maintenance.

**Acceptance Criteria:**

**Given** the `release-publish.yml` workflow has created a GitHub Release with a ZIP asset
**When** the Homebrew update step runs
**Then** it computes the SHA256 of the uploaded ZIP asset
**And** updates `Formula/cc-hdrm.rb` in the `{owner}/homebrew-tap` repository with the new version URL and SHA256
**And** commits and pushes the formula update

**Given** the Homebrew formula update fails (e.g., push permission denied)
**When** the step fails
**Then** the GitHub Release is still published (formula update is non-blocking)
**And** the maintainer is notified of the formula update failure

## Epic 10: Data Persistence & Historical Storage (Phase 3)

Alex's usage data is no longer ephemeral — every poll snapshot is persisted to SQLite, rolled up at decreasing resolution as it ages, creating a permanent record of usage patterns.

### Story 10.1: Database Manager & Schema Creation

As a developer using Claude Code,
I want cc-hdrm to create and manage a SQLite database for historical data,
So that poll snapshots can be persisted reliably across app restarts.

**Acceptance Criteria:**

**Given** the app launches for the first time after Phase 3 upgrade
**When** DatabaseManager initializes
**Then** it creates a SQLite database at `~/Library/Application Support/cc-hdrm/usage.db`
**And** the database contains table `usage_polls` with columns: id (INTEGER PRIMARY KEY), timestamp (INTEGER), five_hour_util (REAL), five_hour_resets_at (INTEGER nullable), seven_day_util (REAL), seven_day_resets_at (INTEGER nullable)
**And** the database contains table `usage_rollups` with columns: id, period_start, period_end, resolution (TEXT), five_hour_avg, five_hour_peak, five_hour_min, seven_day_avg, seven_day_peak, seven_day_min, reset_count, waste_credits
**And** the database contains table `reset_events` with columns: id, timestamp, five_hour_peak, seven_day_util, tier, used_credits, constrained_credits, waste_credits
**And** indexes exist on: usage_polls(timestamp), usage_rollups(resolution, period_start), reset_events(timestamp)
**And** DatabaseManager conforms to DatabaseManagerProtocol for testability

**Given** the app launches on subsequent runs
**When** DatabaseManager initializes
**Then** it opens the existing database without recreating tables
**And** schema version is tracked for future migrations

**Given** the database file is corrupted or inaccessible
**When** DatabaseManager attempts to open
**Then** the error is logged via os.Logger (database category)
**And** the app continues functioning without historical features (graceful degradation)
**And** real-time usage display continues working normally

### Story 10.2: Historical Data Service & Poll Persistence

As a developer using Claude Code,
I want each poll snapshot to be automatically persisted,
So that I build a historical record without any manual action.

**Acceptance Criteria:**

**Given** a successful poll cycle completes with valid usage data
**When** PollingEngine receives the UsageResponse
**Then** HistoricalDataService.persistPoll() is called with the response data
**And** a new row is inserted into usage_polls with current timestamp and utilization values
**And** persistence happens asynchronously (does not block UI updates)
**And** HistoricalDataService conforms to HistoricalDataServiceProtocol for testability

**Given** the database write fails
**When** persistPoll() encounters an error
**Then** the error is logged via os.Logger
**And** the poll cycle is not retried (data for this cycle is lost)
**And** the app continues functioning — subsequent polls attempt persistence normally

**Given** the app has been running for 24+ hours
**When** the database is inspected
**Then** it contains one row per successful poll (~1440 rows for 30-second intervals over 24h)
**And** no duplicate timestamps exist

### Story 10.3: Reset Event Detection

As a developer using Claude Code,
I want cc-hdrm to detect when a 5h window resets,
So that headroom analysis can be performed at each reset boundary.

**Acceptance Criteria:**

**Given** two consecutive polls where the second poll's `five_hour_resets_at` differs from the first
**When** HistoricalDataService detects this shift
**Then** a new row is inserted into reset_events with the pre-reset peak utilization and current 7d utilization
**And** the tier from KeychainCredentials is recorded

**Given** `five_hour_resets_at` is null or missing in the API response
**When** HistoricalDataService detects a large utilization drop (e.g., 80% → 2%)
**Then** it infers a reset event occurred (fallback detection)
**And** logs the inferred reset via os.Logger (info level)

**Given** a reset event is detected
**When** the event is recorded
**Then** used_credits, constrained_credits, and waste_credits are calculated per the headroom analysis math (deferred to Epic 14 for full calculation)
**And** if credit limits are unknown for the tier, the credit fields are set to null

### Story 10.4: Tiered Rollup Engine

As a developer using Claude Code,
I want historical data to be rolled up at decreasing resolution as it ages,
So that storage remains efficient while preserving analytical value.

**Acceptance Criteria:**

**Given** usage_polls contains data older than 24 hours
**When** HistoricalDataService.ensureRollupsUpToDate() is called
**Then** raw polls from 24h-7d ago are aggregated into 5-minute rollups
**And** each rollup row contains: period_start, period_end, resolution='5min', avg/peak/min for both windows
**And** original raw polls older than 24h are deleted after rollup
**And** a metadata record tracks last_rollup_timestamp

**Given** usage_rollups contains 5-minute data older than 7 days
**When** ensureRollupsUpToDate() processes that data
**Then** 5-minute rollups from 7-30 days ago are aggregated into hourly rollups
**And** original 5-minute rollups older than 7 days are deleted after aggregation

**Given** usage_rollups contains hourly data older than 30 days
**When** ensureRollupsUpToDate() processes that data
**Then** hourly rollups from 30+ days ago are aggregated into daily summaries
**And** daily summaries include: avg utilization, peak utilization, min utilization, calculated waste %
**And** original hourly rollups older than 30 days are deleted

**Given** the analytics window opens
**When** the view loads
**Then** ensureRollupsUpToDate() is called before querying data
**And** rollup processing completes within 100ms for a typical day's data
**And** rollups are performed on-demand (not on a background timer)

### Story 10.5: Data Query APIs

As a developer using Claude Code,
I want to query historical data at the appropriate resolution for different time ranges,
So that analytics views can display relevant data efficiently.

**Acceptance Criteria:**

**Given** a request for the last 24 hours of data
**When** HistoricalDataService.getRecentPolls(hours: 24) is called
**Then** it returns raw poll data from usage_polls ordered by timestamp
**And** the result includes all fields needed for sparkline and chart rendering

**Given** a request for 7-day data
**When** HistoricalDataService.getRolledUpData(range: .week) is called
**Then** it returns 5-minute rollups for the 1-7 day range combined with raw data for <24h
**And** data is seamlessly stitched (no visible boundary between raw and rolled data)

**Given** a request for 30-day or all-time data
**When** getRolledUpData() is called with the appropriate range
**Then** it returns the correctly tiered data (daily for 30+ days, hourly for 7-30 days, etc.)

**Given** a request for reset events in a time range
**When** HistoricalDataService.getResetEvents(range:) is called
**Then** it returns all reset_events rows within the specified range
**And** results are ordered by timestamp ascending

## Epic 11: Usage Slope Indicator (Phase 3)

Alex sees not just where he stands, but how fast he's burning. A 4-level slope indicator (↘→↗⬆) appears in the menu bar when burn rate is actionable, and always in the popover for both windows.

### Story 11.1: Slope Calculation Service & Ring Buffer

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

### Story 11.2: Slope Level Calculation & Mapping

As a developer using Claude Code,
I want burn rate mapped to discrete slope levels,
So that the display is simple and actionable rather than noisy continuous values.

**Acceptance Criteria:**

**Given** the ring buffer contains 10+ minutes of poll data for a window
**When** calculateSlope(for: .fiveHour) is called
**Then** it computes the average rate of change (% per minute) across the buffer
**And** maps the rate to SlopeLevel:
- Rate < -0.5% per min → .cooling (↘)
- Rate -0.5 to 0.3% per min → .flat (→)
- Rate 0.3 to 1.5% per min → .rising (↗)
- Rate > 1.5% per min → .steep (⬆)

**Given** slope is calculated for both windows
**When** the calculation completes
**Then** AppState.fiveHourSlope and AppState.sevenDaySlope are updated
**And** updates happen on @MainActor to ensure UI consistency

**Given** the SlopeLevel enum is defined
**When** referenced across the codebase
**Then** it includes properties: arrow (String), color (Color), accessibilityLabel (String)
**And** .cooling and .flat use secondary color; .rising and .steep use headroom color

### Story 11.3: Menu Bar Slope Display (Escalation-Only)

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

**Given** AppState.fiveHourSlope is .flat or .cooling
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

### Story 11.4: Popover Slope Display (Always Visible)

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

### Story 11.5: SlopeIndicator Component

As a developer using Claude Code,
I want a reusable SlopeIndicator component,
So that slope display is consistent across menu bar and popover.

**Acceptance Criteria:**

**Given** SlopeIndicator is instantiated with a SlopeLevel and size
**When** the view renders
**Then** it displays the appropriate arrow character (↘ → ↗ ⬆)
**And** color matches the level: secondary for cooling/flat, headroom color for rising/steep
**And** font size matches the size parameter

**Given** any SlopeIndicator instance
**When** accessibility is evaluated
**Then** it has .accessibilityLabel set to the slope level name ("cooling", "flat", "rising", "steep")

## Epic 12: 24h Sparkline & Analytics Launcher (Phase 3)

Alex glances at the popover and sees a compact 24-hour usage trend — a step-area sparkline showing the sawtooth pattern of his recent sessions. Clicking it opens the analytics window.

### Story 12.1: Sparkline Data Preparation

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

### Story 12.2: Sparkline Component

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

### Story 12.3: Sparkline as Analytics Toggle

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

### Story 12.4: PopoverView Integration

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

## Epic 13: Full Analytics Window (Phase 3)

Alex clicks the sparkline and a floating analytics panel appears — zoomable charts across all retention periods, time range selectors, series toggles, and honest gap rendering for periods when cc-hdrm wasn't running.

### Story 13.1: Analytics Window Shell (NSPanel)

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

### Story 13.2: Analytics View Layout

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

### Story 13.3: Time Range Selector

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

### Story 13.4: Series Toggle Controls

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

### Story 13.5: Usage Chart Component (Step-Area Mode)

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

### Story 13.6: Usage Chart Component (Bar Mode)

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

### Story 13.7: Gap Rendering in Charts

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

## Epic 14: Headroom Analysis & Waste Breakdown (Phase 3)

Alex sees the real story behind his usage — a three-band breakdown showing what he actually used, what was blocked by the weekly limit (not waste!), and what he genuinely left on the table.

### Story 14.1: Rate Limit Tier & Credit Limits

As a developer using Claude Code,
I want cc-hdrm to know the credit limits for my subscription tier,
So that headroom can be calculated in absolute terms.

**Acceptance Criteria:**

**Given** the RateLimitTier enum is defined
**When** referenced across the codebase
**Then** it includes cases: .pro, .max5x, .max20x
**And** each case provides fiveHourCredits and sevenDayCredits properties:
- Pro: 550,000 / 5,000,000
- Max 5x: 3,300,000 / 41,666,700
- Max 20x: 11,000,000 / 83,333,300

**Given** rateLimitTier is read from KeychainCredentials
**When** the tier string matches a known case (e.g., "default_claude_max_5x")
**Then** it maps to the corresponding RateLimitTier enum case

**Given** rateLimitTier doesn't match any known tier
**When** HeadroomAnalysisService needs credit limits
**Then** it checks PreferencesManager for user-configured custom credit limits
**And** if custom limits exist, uses those
**And** if no custom limits, returns nil (percentage-only analysis)
**And** a warning is logged: "Unknown rate limit tier: [tier]"

### Story 14.2: Headroom Analysis Service

As a developer using Claude Code,
I want headroom analysis calculated at each reset event,
So that waste breakdown is accurate and meaningful.

**Acceptance Criteria:**

**Given** a reset event is detected (from Story 10.3)
**When** HeadroomAnalysisService.analyzeResetEvent() is called
**Then** it calculates:
```
5h_remaining_credits = (100% - 5h_peak%) × 5h_limit
7d_remaining_credits = (100% - 7d_util%) × 7d_limit
effective_headroom_credits = min(5h_remaining, 7d_remaining)

If 5h_remaining ≤ 7d_remaining:
    true_waste_credits = 5h_remaining  
    constrained_credits = 0
Else:
    true_waste_credits = 7d_remaining  
    constrained_credits = 5h_remaining - 7d_remaining
```
**And** returns a HeadroomBreakdown struct with: usedPercent, constrainedPercent, wastePercent, usedCredits, constrainedCredits, wasteCredits

**Given** credit limits are unknown (tier not recognized, no user override)
**When** analyzeResetEvent() is called
**Then** it returns nil (analysis cannot be performed)
**And** the analytics view shows: "Headroom breakdown unavailable — unknown subscription tier"

**Given** multiple reset events in a time range
**When** HeadroomAnalysisService.aggregateBreakdown() is called
**Then** it sums used_credits, constrained_credits, and waste_credits across all events
**And** returns aggregate percentages and totals

### Story 14.3: Headroom Breakdown Bar Component

As a developer using Claude Code,
I want a three-band visualization showing used, constrained, and waste,
So that the emotional framing is clear — constrained is not waste.

**Acceptance Criteria:**

**Given** HeadroomBreakdownBar is instantiated with breakdown data
**When** the view renders
**Then** it displays a horizontal stacked bar with three segments:
- **Used (▓)**: solid fill, headroom color based on the aggregate peak level
- **7d-constrained (░)**: hatched/stippled pattern, muted slate blue
- **True waste (□)**: light/empty fill, faint outline

**Given** breakdown percentages (e.g., 52% used, 12% constrained, 36% waste)
**When** the bar renders
**Then** segment widths are proportional to percentages
**And** segments are stacked left-to-right: Used | Constrained | Waste

**Given** constrained is 0%
**When** the bar renders
**Then** the constrained segment is not visible (only Used and Waste)

**Given** a VoiceOver user focuses the breakdown bar
**When** VoiceOver reads the element
**Then** it announces: "Headroom breakdown: [X]% used, [Y]% constrained by weekly limit, [Z]% unused"

### Story 14.4: Breakdown Summary Statistics

As a developer using Claude Code,
I want summary stats below the breakdown bar,
So that I understand the scale and patterns of my usage.

**Acceptance Criteria:**

**Given** the analytics view shows a time range with reset events
**When** the breakdown section renders
**Then** it displays below the bar:
- **Avg peak:** Average of peak utilization across resets in the period
- **Total waste:** Sum of waste_credits formatted as "X.XM credits" or "XXXk credits"
- **7d-constrained:** Percentage of unused capacity blocked by weekly limit

**Given** the selected time range is "24h" with 0-2 resets
**When** the breakdown renders
**Then** it shows aggregate for those resets (may be just one)
**And** if zero resets in range, shows: "No reset events in this period"

**Given** credit limits are unknown
**When** the breakdown section renders
**Then** it shows percentages only (no absolute credit values)
**And** "Total waste" shows as percentage, not credits

### Story 14.5: Analytics View Integration

As a developer using Claude Code,
I want the headroom breakdown integrated into the analytics view,
So that I can see breakdown alongside the usage chart.

**Acceptance Criteria:**

**Given** the analytics window is open
**When** AnalyticsView renders
**Then** HeadroomBreakdownBar and summary stats appear below the UsageChart

**Given** the time range changes
**When** the breakdown re-renders
**Then** it recalculates aggregate breakdown for the new range
**And** queries reset_events for that range via HistoricalDataService

**Given** no reset events exist in the selected range
**When** the breakdown section renders
**Then** it displays: "No reset events in this period — usage continues from previous window"

## Epic 15: Phase 3 Settings & Data Retention (Phase 3)

Alex configures how long cc-hdrm keeps historical data and optionally overrides credit limits for unknown subscription tiers.

### Story 15.1: Data Retention Configuration

As a developer using Claude Code,
I want to configure how long cc-hdrm retains historical data,
So that I can balance storage usage with analytical depth.

**Acceptance Criteria:**

**Given** the settings view is open (from Epic 6)
**When** SettingsView renders
**Then** a new "Historical Data" section appears with:
- Data retention: picker with options: 30 days, 90 days, 6 months, 1 year (default), 2 years, 5 years
- Database size: read-only display showing current size (e.g., "14.2 MB")
- "Clear History" button

**Given** Alex changes the retention period
**When** the value is saved to PreferencesManager
**Then** the next rollup cycle prunes data older than the new retention period

**Given** Alex clicks "Clear History"
**When** confirmation dialog appears and Alex confirms
**Then** all tables are truncated (usage_polls, usage_rollups, reset_events)
**And** the database is vacuumed to reclaim space
**And** sparkline and analytics show empty state until new data is collected

**Given** the database exceeds a reasonable size (e.g., 500 MB)
**When** the settings view opens
**Then** the database size is displayed with warning color
**And** a hint suggests reducing retention or clearing history

### Story 15.2: Custom Credit Limit Override

As a developer using Claude Code,
I want to manually set credit limits for unknown tiers,
So that headroom analysis works even if Anthropic introduces new tiers.

**Acceptance Criteria:**

**Given** the settings view is open
**When** SettingsView renders
**Then** an "Advanced" section appears (collapsed by default) with:
- Custom 5h credit limit: optional number field
- Custom 7d credit limit: optional number field
- Hint text: "Override credit limits if your tier isn't recognized"

**Given** Alex enters custom credit limits
**When** the values are saved to PreferencesManager
**Then** HeadroomAnalysisService uses the custom limits instead of tier lookup

**Given** custom limits are set AND tier is recognized
**When** HeadroomAnalysisService needs limits
**Then** tier lookup values take precedence (custom limits are fallback only)

**Given** invalid values are entered (e.g., negative numbers, zero)
**When** validation runs
**Then** the invalid values are rejected with inline error message
**And** previous valid values are retained
