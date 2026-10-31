---
stepsCompleted: [step-01-init, step-02-discovery, step-03-success, step-04-journeys, step-05-domain, step-06-innovation, step-07-project-type, step-08-scoping, step-09-functional, step-10-nonfunctional, step-11-polish, step-e-01-discovery, step-e-02-review, step-e-03-edit]
lastEdited: '2026-10-31'
editHistory:
  - date: '2026-10-31'
    changes: 'Anthropic retired the Claude 5-hour limit (API returns five_hour: null). Weekly window made primary: revised FR6, FR10, FR17, FR18, FR33, FR35, FR40-FR45; retired FR9, FR11, FR39; slope replaced by weekly pace; headroom analysis reduced to used/unused per weekly cycle. Sprint change proposal 2026-10-31 (Epic 26)'
  - date: '2026-08-12'
    changes: 'Added Phase 7 Codex Usage Tracking (FR49-FR60), amended NFR8 endpoint allowlist with chatgpt.com, added NFR14-NFR15 (Codex credential handling, provider failure isolation) per sprint change proposal 2026-08-12 (Codex)'
  - date: '2026-02-10'
    changes: 'Replaced waste terminology with neutral unused capacity framing (FR40, headroom categories), moved extra usage from Phase 4 to Phase 3, added FR46-FR48 for subscription intelligence (pattern detection, total cost comparison, analytics display)'
  - date: '2026-02-03'
    changes: 'Updated Phase 3 with brainstorming results (historical tracking, headroom analysis, slope indicator), added FR33-FR45, deferred unexplored items to new Phase 4'
classification:
  projectType: desktop_app
  domain: general
  complexity: low
  projectContext: greenfield
inputDocuments:
  - _bmad-output/planning-artifacts/product-brief-cc-usage-2026-01-30.md
  - _bmad-output/planning-artifacts/brainstorming-phase3-expansion-2026-02-03.md
workflowType: 'prd'
projectName: cc-hdrm
documentCounts:
  briefs: 1
  research: 0
  brainstorming: 1
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

> **2026-10-31:** Anthropic retired the 5-hour limit. Since 08:03 UTC that day `five_hour` is `null`. The weekly (`seven_day`) window is the only plan-wide window. The sample below is from 2026-08 and still shows the retired `five_hour` / `session` entries.

```json
{
  "five_hour": {
    "utilization": 15.0,
    "resets_at": "2026-08-12T03:40:00.059198+00:00"
  },
  "seven_day": {
    "utilization": 67.0,
    "resets_at": "2026-08-12T22:00:01.059220+00:00"
  },
  "extra_usage": {
    "is_enabled": false,
    "monthly_limit": null,
    "used_credits": null,
    "utilization": null
  },
  "limits": [
    { "kind": "session", "group": "session", "percent": 15, "severity": "normal",
      "resets_at": "2026-08-12T03:40:00.059198+00:00", "scope": null, "is_active": false },
    { "kind": "weekly_all", "group": "weekly", "percent": 67, "severity": "normal",
      "resets_at": "2026-08-12T22:00:01.059220+00:00", "scope": null, "is_active": true },
    { "kind": "weekly_scoped", "group": "weekly", "percent": 63, "severity": "normal",
      "resets_at": "2026-08-12T22:00:00.059415+00:00",
      "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
      "is_active": false }
  ]
}
```

- `utilization` -- percentage (0-100)
- `resets_at` -- ISO 8601 timestamp or null
- `limits` (added 2026-08) -- array of limit entries: `kind` (`session`, `weekly_all`, `weekly_scoped`), `percent`, `severity`, `resets_at`, `is_active`, and `scope.model.display_name` for model-scoped caps (e.g. Fable's 50%-of-weekly cap). Source of truth for per-model tracking (Epic 21).
- Legacy per-model windows `seven_day_sonnet`, `seven_day_opus` now return `null` -- superseded by `weekly_scoped` entries in `limits`.
- Additional fields (all nullable, unparsed): `seven_day_oauth_apps`, `seven_day_cowork`, `spend` (usage-credits object), extended `extra_usage` fields (`daily`, `weekly`, `currency`), plus obfuscated experiment fields (`iguana_necktie`, `nimbus_quill`, ...)
- Window objects also carry `limit_dollars` / `used_dollars` / `remaining_dollars` (null on subscription plans)

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

1. **Menu bar indicator** -- 5-hour usage percentage (weekly headroom since 2026-10-31) with color coding (green < 60%, yellow 60-80%, orange 80-95%, red > 95%)
2. **Click-to-expand panel** -- 5h and 7d usage bars (weekly gauge only since 2026-10-31) with reset countdowns, subscription tier display
3. **Automatic authentication** -- reads OAuth credentials from macOS Keychain, zero manual config
4. **Background polling** -- every 30-60 seconds, entirely outside Claude conversations
5. **Threshold notifications** -- macOS native notifications at 80% and 95% (hardcoded)
6. **Disconnected state** -- clear indicator when API is unreachable
7. **Subscription tier display** -- Pro/Max shown in expanded panel

**Core User Journeys Supported:** All three (onboarding, daily flow, edge case)

### Phase 2: Growth

- Configurable notification thresholds
- Configurable poll interval
- Homebrew tap distribution (`brew install cc-hdrm`)
- Launch at login preference
- **Semantic versioning** (SemVer) with git tags
- **CHANGELOG.md** maintained in repo, included in GitHub Release notes
- **GitHub Releases pipeline** -- scripted build → ZIP packaging → GitHub Release with changelog
- **In-app update check** -- app checks GitHub Releases API on launch, displays a dismissable badge in the expanded panel when a newer version is available with direct download link. Once dismissed, badge does not reappear until a *newer* version is released.
- **Homebrew tap update path** -- `brew upgrade cc-hdrm` for Homebrew users, paired with the GitHub Releases pipeline

### Phase 3: Expansion

#### Historical Usage Tracking

Persist each poll snapshot to a local SQLite database, building a client-agnostic time-series independent of any single Claude client's local stats.

**Storage:** SQLite (bundled with macOS). Year-scale retention at poll frequency generates ~525K records/year (~15-20 MB raw).

**Tiered Rollup Strategy:**

| Data Age   | Resolution        | Purpose                             |
| ---------- | ----------------- | ----------------------------------- |
| < 24 hours | Per-poll (~60s)   | Real-time detail, recent debugging  |
| 1-7 days   | 5-minute averages | Short-term pattern visibility       |
| 7-30 days  | Hourly averages   | Weekly pattern analysis             |
| 30+ days   | Daily summary     | Long-term trends, seasonal patterns |

Daily summary includes: average utilization, peak utilization, minimum utilization, and calculated unused headroom percentage.

**Retention:** Configurable via settings, default 1 year.

**Gap Handling:** Render missing periods as visually distinct (hatched/grey). Never interpolate. Infer reset boundaries from shifts in `resets_at` timestamp between polls.

**Visualization:** Sparkline of the current weekly cycle with an even-pace line in popover, below the gauges (was: last 24 hours of 5h data; revised 2026-10-31) + full analytics view in a separate window (zoomable, multi-overlay, all retention periods).

**Data per poll:** `{ timestamp, 7d_utilization, 7d_resets_at, scoped weekly caps, extra usage }`. The `5h_utilization` / `5h_resets_at` columns are kept nullable as historical data (no new values since 2026-10-31).

**Research dependency:** Investigate whether Anthropic exposes a historical usage API endpoint to backfill gaps from periods when cc-hdrm was not running.

#### Subscription Value & Headroom Analysis

> **Revised 2026-10-31.** The original model nested the 5-hour and 7-day limits (effective headroom = min of both; three bands: 5h unused, 7d-constrained, true unused). The 5-hour limit was retired, so that model no longer applies.

The weekly allowance is the single plan-wide limit. Each weekly reset closes one cycle.

**Two capacity categories per weekly cycle:**

| Category   | Definition                                         | User Insight                          |
| ---------- | -------------------------------------------------- | ------------------------------------- |
| **Used**   | Peak weekly utilization before the reset           | "This is what you used this week"     |
| **Unused** | 100% minus the peak, at the weekly reset           | "You left this capacity on the table" |

**Visualization:** Two-band stacked chart in analytics view -- used (solid), unused (empty/light). Cycles recorded under the old 5-hour model keep their original breakdown and are not recomputed.

#### Weekly Pace Indicator

> **Revised 2026-10-31.** Replaces the Usage Slope Indicator. The 4-level slope (↘ → ↗ ⬆) was tuned to the 5-hour window. On weekly data, which moves in 1% steps, it flipped between flat and rising.

Pace answers **"at this rate, will my weekly allowance last until the reset?"**

**Calculation:**

- `weekStart = resets_at − 7 days`; `elapsed = clamp((now − weekStart) / 7 days, 0…1)`
- `paceDelta = utilization − elapsed × 100` (positive = ahead of even spending)
- Projected run-out: `rate = utilization / (now − weekStart)`; `runOut = now + (100 − utilization) / rate`. Shown only when `runOut < resets_at` and at least ~4 hours of the week have passed.

**Display:** Menu bar appends an arrow (`72% ↗`) only when run-out is projected before the weekly reset. Popover shows "On pace" or "Ahead of pace -- runs out ~Thu 14:00".

**Known limit:** the average-since-reset rate is pessimistic after a heavy first day. Upgrade path: blend with a recent-window rate.

### Phase 4: Future

- ~~Sonnet-specific usage breakdown~~ -- Superseded by Epic 21 model-scoped limit tracking (API moved per-model windows to the `limits` array; `seven_day_sonnet` now null). Sprint change proposal 2026-08-12.
- Linux tray support
- ~~Extra usage / spending tracking~~ -- Moved to Phase 3 / Epic 16 (data already available and persisted via PR 43)
- Codex Token Efficiency Ratio, unused-capacity breakdown, tier recommendation (deferred from Phase 7)

### Phase 7: Codex Usage Tracking

Extend cc-hdrm to monitor OpenAI Codex subscription limits alongside Claude, with full feature parity for core tracking: dedicated menu bar item, popover panel, threshold notifications, historical persistence, and analytics integration. (Sprint change proposal 2026-08-12, Codex.)

**Kill Condition:** If the Codex usage endpoint cannot be reached from a standalone macOS process using `~/.codex/auth.json` credentials, Phase 7 is killed (spike story 22.1).

**Data source (to be validated by spike):**

- Credentials: `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`), JWT claims carry plan type
- Usage: `GET https://chatgpt.com/backend-api/wham/usage` -- `rate_limit.primary_window` (5h session), `rate_limit.secondary_window` (weekly), `additional_rate_limits[]`, credits (balance / hasCredits / unlimited)
- Credits inventory: `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`
- Token refresh: mechanism TBD in spike

**Deferred beyond Phase 7:** Codex TPP, Codex unused-capacity breakdown, Codex tier recommendation.

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

He launches the app. No login screen, no setup wizard, no config file. A small `72%` appears in his menu bar within seconds. He clicks it -- a panel drops down showing his weekly allowance at 28% used, "On pace", with a reset in 3d 4h.

He exhales. For the first time, he knows exactly where he stands.

**Capabilities revealed:** Keychain auto-discovery, zero-config onboarding, immediate data display, menu bar rendering, expand panel UI.

### Journey 2: Daily Flow -- "Informed pacing"

It's Tuesday, 3pm. Alex has three Claude Code sessions open -- a feature build, a code review, and a docs rewrite. The menu bar reads `58% ↗`. He clicks to expand: "Ahead of pace -- runs out ~Thu 14:00", weekly reset Sat 09:00.

He decides: the docs rewrite can wait until after the reset. He focuses the week on the feature build and the code review.

On Thursday the indicator turns **orange**. A macOS notification: "Weekly allowance at 17% headroom -- resets Sat 09:00." He is already pacing for it.

No panic. No surprise. Just a calm, informed decision.

**Capabilities revealed:** Color-coded thresholds, reset countdown display, macOS notifications, background polling, always-visible indicator.

### Journey 3: Edge Case -- "The wall"

Alex is deep in a complex refactor. It's Friday evening. The menu bar is **red** -- 4% headroom. A notification fires: "Weekly allowance at 5% headroom -- resets in 14h."

He finishes his current prompt and stops for the night. Saturday morning the indicator returns to **green** -- 100% headroom. He picks up exactly where he left off with full capacity.

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
| Weekly usage gauge + pace   | x         | x         |           |
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
- Under 50 MB memory, no persistent storage beyond in-memory state (Phase 1; Phase 3 introduces SQLite for historical data)

## Functional Requirements

### Usage Data Retrieval

- FR1: App can retrieve OAuth credentials from the macOS Keychain without user interaction
- FR2: App can detect the user's subscription type and rate limit tier from stored credentials
- FR3: App can fetch current usage data from the Claude usage API
- FR4: App can handle API request failures with standard HTTP error handling (retry, timeout, graceful degradation)
- FR5: App can detect when OAuth credentials have expired and display an actionable status message

### Usage Display

- FR6: User can see current weekly allowance headroom in the menu bar at all times (revised 2026-10-31)
- FR7: User can see a color-coded indicator that reflects usage severity (green/yellow/orange/red)
- FR8: User can click the menu bar icon to expand a detailed usage panel
- ~~FR9: User can see 5-hour usage bar with percentage in the expanded panel~~ -- Retired 2026-10-31: Anthropic removed the 5-hour limit
- FR10: User can see the weekly usage gauge as the primary gauge in the expanded panel (revised 2026-10-31)
- ~~FR11: User can see time remaining until 5-hour window resets~~ -- Retired 2026-10-31
- FR12: User can see time remaining until 7-day window resets
- FR13: User can see their subscription tier in the expanded panel

### Background Monitoring

- FR14: App can poll the usage API at regular intervals without user action
- FR15: App can update the menu bar display automatically when new data arrives
- FR16: App can continue running in the background with no visible main window

### Notifications

- FR17: User can receive a macOS notification when weekly usage crosses the warning threshold (revised 2026-10-31)
- FR18: User can receive a macOS notification when weekly usage crosses the critical threshold (revised 2026-10-31)
- FR19: App can include the reset countdown time in notification messages

### Connection State

- FR20: User can see a disconnected state indicator when the API is unreachable
- FR21: User can see an explanation of the connection failure in the expanded panel
- FR22: App can automatically resume normal display when connectivity returns

### App Lifecycle

- FR23: App can launch and display usage data without any manual configuration
- FR24: User can quit the app from the menu bar
- FR25: User can see when a newer version is available via a dismissable badge in the expanded panel; once dismissed, the badge does not reappear until a newer version is released (Phase 2)
- FR26: User can access a direct download link for the latest version from within the expanded panel (Phase 2)
- FR27: User can configure notification headroom thresholds, replacing the hardcoded 20% and 5% defaults (Phase 2)
- FR28: User can configure the polling interval, replacing the hardcoded 30-second default (Phase 2)
- FR29: User can enable launch at login so the app starts automatically on macOS boot (Phase 2)
- FR30: User can access a settings view from the gear menu to configure preferences (Phase 2)
- FR31: Maintainer can trigger a semver release by including `[patch]`, `[minor]`, or `[major]` in a PR title merged to `master` (Phase 2)
- FR32: Release changelog is auto-generated from merged PR titles since last tag, with optional maintainer preamble (Phase 2)

### Historical Usage Tracking (Phase 3)

- FR33: App persists each poll snapshot (timestamp, 7d utilization, 7d resets_at, scoped weekly caps, extra usage) to a local SQLite database; historical 5h columns are retained as nullable (revised 2026-10-31)
- FR34: App rolls up historical data at decreasing resolution as data ages, balancing storage efficiency with analytical granularity
- FR35: User can view the current weekly cycle's usage trend against an even-pace line in the popover (revised 2026-10-31)
- FR36: User can open a full analytics view in a separate window with zoomable historical charts across all retention periods
- FR37: App renders data gaps as a visually distinct state with no interpolation of missing data
- FR38: User can configure data retention period in settings (default 1 year)

### Subscription Value & Headroom Analysis (Phase 3)

- ~~FR39: App calculates effective headroom as min(5h remaining capacity, 7d remaining capacity)~~ -- Retired 2026-10-31: weekly headroom is the effective headroom
- FR40: App detects weekly resets and classifies each cycle's capacity as used or unused (revised 2026-10-31)
- FR41: User can view a breakdown of used and unused weekly capacity per cycle in the analytics view (revised 2026-10-31)

### Weekly Pace Indicator (Phase 3, revised 2026-10-31)

- FR42: App computes weekly pace: usage versus the share of the week elapsed (revised 2026-10-31)
- FR43: App projects the run-out time from average usage since the weekly reset (revised 2026-10-31)
- FR44: User can see an indicator in the menu bar when run-out is projected before the weekly reset (revised 2026-10-31)
- FR45: User can see pace status and projected run-out time in the popover (revised 2026-10-31)

### Subscription Intelligence (Phase 3)

- FR46: App detects extra usage overflow patterns from persisted extra_usage data and includes them in slow-burn pattern analysis
- FR47: Tier recommendation computes total cost (base subscription + extra usage charges) when comparing tiers
- FR48: Analytics displays total cost breakdown when extra usage data is available

### Codex Usage Tracking (Phase 7)

- FR49: App can read Codex OAuth credentials from `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`) without user interaction, read-only
- FR50: App can detect the user's Codex plan type from stored credentials
- FR51: App can fetch current Codex usage data (5h primary window, weekly secondary window, credits) from the ChatGPT backend usage endpoint
- FR52: App can detect expired/invalid Codex credentials and display an actionable status message ("run codex to refresh" or equivalent validated by spike)
- FR53: User can see Codex 5h headroom in a dedicated second menu bar item with the same color/weight coding as Claude
- FR54: User can click the Codex menu bar item to expand a Codex panel with 5h and weekly gauges, reset countdowns, plan type, and credits balance when available
- FR55: User can see per-window slope indicators for Codex (menu bar + popover), reusing the 4-level slope model
- FR56: User can receive threshold notifications for Codex 5h and weekly windows at configurable headroom thresholds
- FR57: User can enable/disable Codex tracking in settings; the Codex menu bar item auto-hides when no credentials are found or tracking is disabled
- FR58: App persists Codex poll snapshots to SQLite with a provider dimension, participating in the existing tiered rollup strategy
- FR59: User can view Codex historical data in the analytics window via provider selection
- FR60: Codex polling failures degrade gracefully and independently -- Claude tracking is never affected by Codex errors, and vice versa

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
- NFR8: No credentials or usage data are transmitted to any endpoint other than `api.anthropic.com` (Claude usage), `platform.claude.com` (Claude token refresh), and `chatgpt.com` (Codex usage). Codex token refresh may only target a fixed HTTPS origin and exact path added to this allowlist by PRD amendment once the Phase 7 spike establishes it; until that amendment lands, the app must not send Codex refresh requests and must surface the token-expired state instead
- NFR14: Codex credentials are read from `auth.json` fresh each poll cycle, never written back, never persisted elsewhere, and never logged
- NFR15: Claude and Codex polling lanes are failure-isolated -- an error in one provider's pipeline must not affect the other's display, notifications, or persistence
- NFR9: API requests use HTTPS exclusively

### Integration

- NFR10: App functions correctly when Claude Code credentials exist in the macOS Keychain
- NFR11: App degrades gracefully when Keychain credentials are missing, expired, or malformed
- NFR12: App handles Claude API response format changes without crashing (defensive parsing)
- NFR13: App resumes normal operation within one polling cycle after network connectivity returns
