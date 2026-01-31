---
stepsCompleted: [step-01-init, step-02-discovery, step-03-success, step-04-journeys, step-05-domain, step-06-innovation, step-07-project-type, step-08-scoping, step-09-functional, step-10-nonfunctional, step-11-polish]
classification:
  projectType: desktop_app
  domain: general
  complexity: low
  projectContext: greenfield
inputDocuments:
  - _bmad-output/planning-artifacts/product-brief-cc-usage-2026-01-30.md
workflowType: 'prd'
projectName: cc-hdrm
documentCounts:
  briefs: 1
  research: 0
  brainstorming: 0
  projectDocs: 0
---

# Product Requirements Document - cc-hdrm

**Author:** Boss
**Date:** 2026-01-30

## Executive Summary

cc-hdrm is a native macOS menu bar utility that gives Claude Pro/Max subscribers always-visible, glanceable usage data. Developers using Claude through coding agents (CLI, TUI, Desktop) have no passive way to monitor subscription limits, leading to unexpected mid-task cutoffs and persistent anxiety about remaining capacity. cc-hdrm polls the Claude usage API in the background and displays live usage bars, reset countdowns, and color-coded warnings directly in the menu bar -- zero tokens spent, zero workflow interruption.

**Target User:** Solo power developer running Claude Code 24/7 across multiple projects simultaneously.

**Tech Stack:** Swift/SwiftUI, native macOS menu bar app.

**Distribution:** Open source, build from source (Homebrew tap in growth phase).

**Kill Condition:** ~~If the Claude usage API cannot be reached from a standalone macOS process (all Cloudflare fallbacks fail), the project is killed.~~ **PASSED** -- see API Spike Results below.

## API Spike Results (2026-01-31)

**Kill gate validated. Project is a GO.**

### Endpoint Discovery

The usage API lives at `https://api.anthropic.com/api/oauth/usage` -- NOT `claude.ai`. The `api.anthropic.com` domain is a clean API endpoint with no Cloudflare browser challenge. The entire Cloudflare bypass concern from the original tech spec is moot.

### Authentication

- **Method:** `Authorization: Bearer <oauth_access_token>`
- **Required header:** `anthropic-beta: oauth-2025-04-20`
- **User-Agent:** `claude-code/<version>` (mirrors Claude Code's own agent string)

### Keychain Credentials

- **Service name:** `Claude Code-credentials`
- **Format:** JSON containing `claudeAiOauth` object
- **Fields available at rest (no API call needed):**
  - `accessToken` -- OAuth bearer token
  - `refreshToken` -- for token renewal
  - `expiresAt` -- Unix timestamp (ms) of token expiry
  - `subscriptionType` -- e.g. `"max"`
  - `rateLimitTier` -- e.g. `"default_claude_max_5x"`
  - `scopes` -- array of granted scopes

### API Response Format

```json
{
  "five_hour": {
    "utilization": 18.0,
    "resets_at": "2026-01-31T01:59:59.782798+00:00"
  },
  "seven_day": {
    "utilization": 6.0,
    "resets_at": "2026-02-06T08:59:59.782818+00:00"
  },
  "seven_day_sonnet": {
    "utilization": 0.0,
    "resets_at": null
  },
  "extra_usage": {
    "is_enabled": false,
    "monthly_limit": null,
    "used_credits": null,
    "utilization": null
  }
}
```

- `utilization` -- percentage (0-100)
- `resets_at` -- ISO 8601 timestamp or null
- Additional fields: `seven_day_oauth_apps`, `seven_day_opus`, `seven_day_cowork`, `iguana_necktie` (all nullable)

### Token Refresh

OAuth tokens expire (observed `expiresAt` ~6h from issue). The Keychain includes a `refreshToken`. Token refresh endpoint: `https://platform.claude.com/v1/oauth/token` (from binary analysis). cc-hdrm must handle token refresh or display a clear "token expired, run Claude Code to refresh" message.

### Risk Update

| Risk                             | Original | Updated  | Notes                                        |
| -------------------------------- | -------- | -------- | -------------------------------------------- |
| Cloudflare blocks all approaches | Medium   | **Eliminated** | API is on `api.anthropic.com`, no Cloudflare |
| OAuth token expiry mid-session   | High     | High     | Must implement refresh or show clear status  |

## Success Criteria

### User Success

- **Informed resource allocation** -- when running multiple Claude sessions in parallel, user sees remaining headroom and decides which session to prioritize, pausing less important ones to ensure the critical task completes within the limit.
- **Zero surprise cutoffs** -- every threshold crossing triggers a notification before Claude stops responding.
- **Zero workflow interruption** -- user never types `/usage`, opens claude.ai, or takes any action to check usage status.

### Business Success

- GitHub stars: 100+ in first 6 months
- Adoption signal: issue reports and feature requests from other developers

### Technical Success

- Stable for 8+ continuous hours without crash or memory leak
- Memory under 50 MB
- Usage data no more than 60s stale
- API errors handled silently -- user sees usage data or a clear status, never a raw error
- Zero false negatives on threshold notifications

### Measurable Outcomes

| Outcome             | Measure                                   | Target       |
| ------------------- | ----------------------------------------- | ------------ |
| No surprise cutoffs | Notifications fire before every limit hit | 100%         |
| Always-visible data | Usage displayed in menu bar continuously  | 99%+ uptime  |
| Fresh data          | Time since last successful poll           | < 60 seconds |
| Lightweight         | Memory in Activity Monitor                | < 50 MB      |
| Quick setup         | Time from clone to working menu bar       | < 2 minutes  |

## Product Scope & Phased Development

### MVP Strategy

**Approach:** Problem-solving MVP -- the smallest thing that eliminates usage anxiety for a solo developer.

**Resource Requirements:** Single developer. No backend, no infrastructure, no team.

### Phase 1: MVP

1. **Menu bar indicator** -- 5-hour usage percentage with color coding (green < 60%, yellow 60-80%, orange 80-95%, red > 95%)
2. **Click-to-expand panel** -- 5h and 7d usage bars with reset countdowns, subscription tier display
3. **Automatic authentication** -- reads OAuth credentials from macOS Keychain, zero manual config
4. **Background polling** -- every 30-60 seconds, entirely outside Claude conversations
5. **Threshold notifications** -- macOS native notifications at 80% and 95% (hardcoded)
6. **Disconnected state** -- clear indicator when API is unreachable
8. **Subscription tier display** -- Pro/Max shown in expanded panel

**Core User Journeys Supported:** All three (onboarding, daily flow, edge case)

### Phase 2: Growth

- Configurable notification thresholds
- Configurable poll interval
- Homebrew tap distribution (`brew install cc-hdrm`)
- Launch at login preference
- Sonnet-specific usage breakdown

### Phase 3: Expansion

- Usage graphs -- historical patterns over hours/days/weeks
- Limit prediction based on usage slope
- Linux tray support
- Extra usage / spending tracking

### Risk Mitigation

| Risk                             | Likelihood | Impact | Mitigation                                               |
| -------------------------------- | ---------- | ------ | -------------------------------------------------------- |
| ~~Cloudflare blocks all approaches~~ | ~~Medium~~ | ~~Fatal~~ | **Eliminated** -- API is on `api.anthropic.com`, no Cloudflare. See API Spike Results. |
| OAuth token expiry mid-session   | High       | Low    | Show clear "token expired, run claude to refresh" status |
| Keychain access denied           | Low        | Medium | Clear error message with instructions                    |
| Anthropic changes API format     | Low        | Medium | Defensive parsing, graceful degradation                  |

**Market Risks:** Minimal -- personal tool first. If it works for the creator, it works.

**Resource Risks:** Single developer, no external dependencies beyond macOS SDK and the Claude API. Risk is only time investment, mitigated by the early kill gate.

## User Journeys

### Journey 1: First Launch -- "Where has this been all my life?"

**Alex** has been using Claude Code for months. Last week he got cut off twice mid-refactor -- once during a critical production fix. He finds cc-hdrm on GitHub, clones the repo, runs the build.

He launches the app. No login screen, no setup wizard, no config file. A small `42%` appears in his menu bar within seconds. He clicks it -- a panel drops down showing his 5-hour window at 42% with a reset in 2h 13m, and his 7-day at 28%.

He exhales. For the first time, he knows exactly where he stands.

**Capabilities revealed:** Keychain auto-discovery, zero-config onboarding, immediate data display, menu bar rendering, expand panel UI.

### Journey 2: Daily Flow -- "Informed pacing"

It's 3pm. Alex has three Claude Code sessions open -- a feature build, a code review, and a docs rewrite. The indicator has turned **orange** -- 83%. He clicks to expand: 5-hour window resets in 47 minutes.

A macOS notification: "Claude usage at 83% -- resets in 47 min."

He decides: the docs rewrite can wait. He focuses the feature build on wrapping up cleanly. When the reset hits, he'll have full headroom for the code review.

No panic. No surprise. Just a calm, informed decision.

**Capabilities revealed:** Color-coded thresholds, reset countdown display, macOS notifications, background polling, always-visible indicator.

### Journey 3: Edge Case -- "The wall"

Alex is deep in a complex refactor. The menu bar is **red** -- 96%. A notification fires: "Claude usage at 95% -- resets in 8 min."

He finishes his current prompt and waits. Eight minutes later, the indicator drops to **green** -- 0%. He picks up exactly where he left off with full capacity.

Without cc-hdrm, he'd have kept going, gotten cut off mid-response, lost context, and had to restart the conversation.

**Capabilities revealed:** High-threshold notification (95%), real-time reset tracking, color transition feedback, polling continues through limit boundary.

### Journey Requirements Summary

| Capability                  | Journey 1 | Journey 2 | Journey 3 |
| --------------------------- | --------- | --------- | --------- |
| Keychain auto-auth          | x         |           |           |
| Zero-config onboarding      | x         |           |           |
| Menu bar percentage display | x         | x         | x         |
| Color-coded indicator       |           | x         | x         |
| Click-to-expand panel       | x         | x         |           |
| 5h + 7d usage bars          | x         | x         |           |
| Reset countdown             | x         | x         | x         |
| Background polling          |           | x         | x         |
| Threshold notifications     |           | x         | x         |
| Real-time color transitions |           |           | x         |

## Desktop App Requirements

### Architecture

- **Language/Framework:** Swift 5.9+, SwiftUI, targeting macOS 14+ (Sonoma) — required for `@Observable` macro
- **App type:** Menu bar-only (LSUIElement = true, no dock icon, no main window)
- **Distribution:** Build from source (Xcode), manual update
- **Signing:** Unsigned for initial release, users allow in System Preferences

### Platform Support

| Platform | Status       | Notes                                |
| -------- | ------------ | ------------------------------------ |
| macOS    | MVP          | 14+ (Sonoma), Apple Silicon + Intel  |
| Linux    | Future       | Community-contributed tray support   |
| Windows  | Out of scope | No current plans                     |

### System Integration

- **macOS Keychain** -- reads Claude Code OAuth credentials via `Security` framework. Read + write (write required for token refresh).
- **macOS Notifications** -- `UserNotifications` framework for threshold alerts (80%, 95%)
- **Menu bar** -- `NSStatusItem` with SwiftUI popover for expanded view

### Disconnected Behavior

- Show disconnected state in menu bar (e.g. `--` or grey icon) when API unreachable
- Do not cache or display stale data
- Resume automatically when connectivity returns
- Expanded panel shows "Unable to reach Claude API" with timestamp of last failed attempt

### Constraints

- No main window -- entire UI lives in the menu bar popover
- Minimal permissions -- Keychain read/write access (write for token refresh) and outbound HTTPS
- Background execution via `NSApplication` with no termination on last window close
- Under 50 MB memory, no persistent storage beyond in-memory state

## Functional Requirements

### Usage Data Retrieval

- FR1: App can retrieve OAuth credentials from the macOS Keychain without user interaction
- FR2: App can detect the user's subscription type and rate limit tier from stored credentials
- FR3: App can fetch current usage data from the Claude usage API
- FR4: App can handle API request failures with standard HTTP error handling (retry, timeout, graceful degradation)
- FR5: App can detect when OAuth credentials have expired and display an actionable status message

### Usage Display

- FR6: User can see current 5-hour usage percentage in the menu bar at all times
- FR7: User can see a color-coded indicator that reflects usage severity (green/yellow/orange/red)
- FR8: User can click the menu bar icon to expand a detailed usage panel
- FR9: User can see 5-hour usage bar with percentage in the expanded panel
- FR10: User can see 7-day usage bar with percentage in the expanded panel
- FR11: User can see time remaining until 5-hour window resets
- FR12: User can see time remaining until 7-day window resets
- FR13: User can see their subscription tier in the expanded panel

### Background Monitoring

- FR14: App can poll the usage API at regular intervals without user action
- FR15: App can update the menu bar display automatically when new data arrives
- FR16: App can continue running in the background with no visible main window

### Notifications

- FR17: User can receive a macOS notification when 5-hour usage crosses 80%
- FR18: User can receive a macOS notification when 5-hour usage crosses 95%
- FR19: App can include the reset countdown time in notification messages

### Connection State

- FR20: User can see a disconnected state indicator when the API is unreachable
- FR21: User can see an explanation of the connection failure in the expanded panel
- FR22: App can automatically resume normal display when connectivity returns

### App Lifecycle

- FR23: App can launch and display usage data without any manual configuration
- FR24: User can quit the app from the menu bar

## Non-Functional Requirements

### Performance

- NFR1: Menu bar indicator updates within 2 seconds of receiving new API data
- NFR2: Click-to-expand popover opens within 200ms of user click
- NFR3: App memory usage remains under 50 MB during continuous operation
- NFR4: CPU usage remains below 1% between polling intervals
- NFR5: API polling completes within 10 seconds per request (including fallback attempts)

### Security

- NFR6: OAuth credentials are read from Keychain at runtime and never persisted to disk, logs, or user defaults
- NFR7: OAuth tokens are read fresh from Keychain each poll cycle and not cached in application state between cycles
- NFR8: No credentials or usage data are transmitted to any endpoint other than `api.anthropic.com` (usage data) and `platform.claude.com` (token refresh)
- NFR9: API requests use HTTPS exclusively

### Integration

- NFR10: App functions correctly when Claude Code credentials exist in the macOS Keychain
- NFR11: App degrades gracefully when Keychain credentials are missing, expired, or malformed
- NFR12: App handles Claude API response format changes without crashing (defensive parsing)
- NFR13: App resumes normal operation within one polling cycle after network connectivity returns
