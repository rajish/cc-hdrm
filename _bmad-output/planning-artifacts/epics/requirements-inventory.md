# Requirements Inventory

## Functional Requirements

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

## NonFunctional Requirements

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

## Additional Requirements

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

## FR Coverage Map

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
