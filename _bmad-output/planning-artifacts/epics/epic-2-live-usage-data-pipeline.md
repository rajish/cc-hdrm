# Epic 2: Live Usage Data Pipeline

Alex's usage data flows automatically — the app fetches from the Claude API in the background and keeps itself current, handling errors gracefully with auto-recovery.

## Story 2.1: API Client & Usage Data Fetch

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

## Story 2.2: Background Polling Engine

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

## Story 2.3: Data Freshness Tracking

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
