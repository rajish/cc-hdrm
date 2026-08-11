---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Anthropic API - Full Surface Area Survey'
research_goals: 'Broad survey of all available Anthropic API endpoints and data beyond core chat/completion, to identify what additional information can be gathered for cc-hdrm'
user_name: 'Boss'
date: '2026-02-24'
web_research_enabled: true
source_verification: true
---

# Anthropic API Surface Area: What cc-hdrm Can Tap Into

**Date:** 2026-02-24
**Author:** Boss
**Research Type:** Technical — Anthropic API Full Surface Survey

---

## Executive Summary

The Anthropic API exposes **45+ endpoints across 12 categories**, far more than cc-hdrm currently uses. Today cc-hdrm consumes just 4 undocumented OAuth endpoints for personal usage/profile data. The remaining surface area — Admin API (org-wide usage/cost/analytics), rate limit headers, models catalog — is untapped.

**The biggest insight:** Two completely separate authentication worlds exist. OAuth (what cc-hdrm uses) gives personal subscription data. The Admin API (`sk-ant-admin...` key) gives org-wide operational data. These don't overlap — they complement each other.

**Key findings:**

1. **Free win available now:** Every API response already includes 12+ rate limit headers that cc-hdrm ignores. Parsing them gives real-time RPM/ITPM/OTPM visibility with zero extra API calls.
2. **Admin API is Team/Enterprise only** — confirmed unavailable for individual accounts. Any Admin API features in cc-hdrm would serve a subset of users.
3. **Richest new data sources:** Usage Report (token-level, 7 grouping dimensions, 1-min granularity), Cost Report (actual USD), and Claude Code Analytics (per-user productivity metrics).
4. **New endpoints discovered during research:** Enterprise Analytics API (Claude Remote usage), data residency controls (`inference_geo`), fast mode tracking (`speed` dimension), automatic caching metrics, web search request counts.

**Top recommendations:**
1. **Phase 0 (all users):** Parse rate limit headers — zero effort, immediate value
2. **Phase 2-4 (Team/Enterprise):** Admin key entry → org metadata → usage report — highest value chain
3. **Phase 6 (Team/Enterprise):** Claude Code Analytics — unique productivity data available nowhere else

---

## Table of Contents

1. [Complete API Surface Area](#complete-api-surface-area) — All 45+ endpoints cataloged
2. [Response Headers & Metadata](#response-headers--metadata-from-every-messages-api-call) — Rate limit headers, request IDs
3. [Usage Tier System](#usage-tier-system) — Tier requirements and limits
4. [Beta Features Available](#beta-features-available-via-anthropic-beta-header) — 16+ beta capabilities
5. [Enterprise / Compliance](#enterprise--compliance-separate-from-api) — SSO, audit, ZDR
6. [Integration Patterns Analysis](#integration-patterns-analysis) — Two auth worlds, patterns A-E
7. [Architectural Patterns](#architectural-patterns-for-cc-hdrm-integration) — Options A/B/C, data model, security
8. [Implementation Roadmap](#implementation-roadmap) — Phases 0-6 with effort/value/risk
9. [Sources](#sources) — All verified references

---

## Research Overview

Broad survey of every Anthropic API endpoint and the data each returns, organized by API category. Goal: identify what cc-hdrm could consume beyond what it already uses.

---

## Complete API Surface Area

### Category 1: Core APIs (GA — standard API key)

| #   | Endpoint                 | Method | Path                         | What It Returns                                                          |
| --- | ------------------------ | ------ | ---------------------------- | ------------------------------------------------------------------------ |
| 1   | **Messages**             | POST   | `/v1/messages`               | Model response, usage (input/output/cache tokens), stop reason, model ID |
| 2   | **Messages (streaming)** | POST   | `/v1/messages` (stream=true) | Same as above, streamed via SSE                                          |
| 3   | **Token Counting**       | POST   | `/v1/messages/count_tokens`  | Token count for a message payload before sending                         |
| 4   | **List Models**          | GET    | `/v1/models`                 | Available model IDs, display names, created dates                        |
| 5   | **Get Model**            | GET    | `/v1/models/{model_id}`      | Single model details                                                     |

### Category 2: Batch APIs (GA — standard API key)

| #   | Endpoint              | Method | Path                                      | What It Returns                                |
| --- | --------------------- | ------ | ----------------------------------------- | ---------------------------------------------- |
| 6   | **Create Batch**      | POST   | `/v1/messages/batches`                    | Batch ID, status, request counts               |
| 7   | **List Batches**      | GET    | `/v1/messages/batches`                    | All batches with status, creation time, counts |
| 8   | **Get Batch**         | GET    | `/v1/messages/batches/{batch_id}`         | Single batch details + status                  |
| 9   | **Get Batch Results** | GET    | `/v1/messages/batches/{batch_id}/results` | JSONL results for completed batch              |
| 10  | **Cancel Batch**      | POST   | `/v1/messages/batches/{batch_id}/cancel`  | Updated batch status                           |

### Category 3: Files API (Beta — `files-api-2025-04-14`)

| #   | Endpoint          | Method | Path                          | What It Returns                                  |
| --- | ----------------- | ------ | ----------------------------- | ------------------------------------------------ |
| 11  | **Upload File**   | POST   | `/v1/files`                   | File ID, filename, size, MIME type               |
| 12  | **List Files**    | GET    | `/v1/files`                   | All uploaded files with metadata                 |
| 13  | **Get File**      | GET    | `/v1/files/{file_id}`         | Single file metadata                             |
| 14  | **Download File** | GET    | `/v1/files/{file_id}/content` | File content (only skill/code-execution outputs) |
| 15  | **Delete File**   | DELETE | `/v1/files/{file_id}`         | Deletion confirmation                            |

### Category 4: Skills API (Beta — `skills-2025-10-02`)

| #   | Endpoint         | Method | Path                    | What It Returns             |
| --- | ---------------- | ------ | ----------------------- | --------------------------- |
| 16  | **Create Skill** | POST   | `/v1/skills`            | Skill ID, name, description |
| 17  | **List Skills**  | GET    | `/v1/skills`            | All skills with metadata    |
| 18  | **Get Skill**    | GET    | `/v1/skills/{skill_id}` | Single skill details        |
| 19  | **Update Skill** | PATCH  | `/v1/skills/{skill_id}` | Updated skill               |
| 20  | **Delete Skill** | DELETE | `/v1/skills/{skill_id}` | Deletion confirmation       |

### Category 5: Admin API — Organization (Admin key: `sk-ant-admin...`)

| #   | Endpoint               | Method | Path                                | What It Returns                                                                      |
| --- | ---------------------- | ------ | ----------------------------------- | ------------------------------------------------------------------------------------ |
| 21  | **Get Organization**   | GET    | `/v1/organizations/me`              | Org ID, name, type                                                                   |
| 22  | **List Members**       | GET    | `/v1/organizations/users`           | Member list: user IDs, emails, roles (user/claude_code_user/developer/billing/admin) |
| 23  | **Get Member**         | GET    | `/v1/organizations/users/{user_id}` | Single member details                                                                |
| 24  | **Update Member Role** | POST   | `/v1/organizations/users/{user_id}` | Updated role                                                                         |
| 25  | **Remove Member**      | DELETE | `/v1/organizations/users/{user_id}` | Removal confirmation                                                                 |

### Category 6: Admin API — Invites

| #   | Endpoint          | Method | Path                                    | What It Returns                        |
| --- | ----------------- | ------ | --------------------------------------- | -------------------------------------- |
| 26  | **Create Invite** | POST   | `/v1/organizations/invites`             | Invite ID, email, role, status         |
| 27  | **List Invites**  | GET    | `/v1/organizations/invites`             | Pending invites (expire after 21 days) |
| 28  | **Get Invite**    | GET    | `/v1/organizations/invites/{invite_id}` | Single invite details                  |
| 29  | **Delete Invite** | DELETE | `/v1/organizations/invites/{invite_id}` | Deletion confirmation                  |

### Category 7: Admin API — Workspaces

| #   | Endpoint              | Method | Path                                                  | What It Returns          |
| --- | --------------------- | ------ | ----------------------------------------------------- | ------------------------ |
| 30  | **Create Workspace**  | POST   | `/v1/organizations/workspaces`                        | Workspace ID, name       |
| 31  | **List Workspaces**   | GET    | `/v1/organizations/workspaces`                        | All workspaces           |
| 32  | **Get Workspace**     | GET    | `/v1/organizations/workspaces/{workspace_id}`         | Single workspace details |
| 33  | **Update Workspace**  | POST   | `/v1/organizations/workspaces/{workspace_id}`         | Updated workspace        |
| 34  | **Archive Workspace** | POST   | `/v1/organizations/workspaces/{workspace_id}/archive` | Archive confirmation     |

### Category 8: Admin API — Workspace Members

| #   | Endpoint               | Method | Path                                                     | What It Returns                  |
| --- | ---------------------- | ------ | -------------------------------------------------------- | -------------------------------- |
| 35  | **Add Member**         | POST   | `/v1/organizations/workspaces/{workspace_id}/members`    | Member + workspace role          |
| 36  | **List Members**       | GET    | `/v1/organizations/workspaces/{workspace_id}/members`    | Workspace member list with roles |
| 37  | **Get Member**         | GET    | `/v1/organizations/workspaces/{ws_id}/members/{user_id}` | Single member details            |
| 38  | **Update Member Role** | POST   | `/v1/organizations/workspaces/{ws_id}/members/{user_id}` | Updated workspace role           |
| 39  | **Remove Member**      | DELETE | `/v1/organizations/workspaces/{ws_id}/members/{user_id}` | Removal confirmation             |

### Category 9: Admin API — API Keys

| #   | Endpoint           | Method | Path                                      | What It Returns                                                                                      |
| --- | ------------------ | ------ | ----------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| 40  | **List API Keys**  | GET    | `/v1/organizations/api_keys`              | Key IDs, names, status (active/inactive), workspace, created dates. Filterable by status & workspace |
| 41  | **Get API Key**    | GET    | `/v1/organizations/api_keys/{api_key_id}` | Single key details                                                                                   |
| 42  | **Update API Key** | POST   | `/v1/organizations/api_keys/{api_key_id}` | Updated key (name, status). Cannot create new keys via API                                           |

### Category 10: Admin API — Usage Report

| #   | Endpoint         | Method | Path                                      | What It Returns                                        |
| --- | ---------------- | ------ | ----------------------------------------- | ------------------------------------------------------ |
| 43  | **Usage Report** | GET    | `/v1/organizations/usage_report/messages` | Token consumption aggregated by time bucket (1m/1h/1d) |

**Query parameters:**
- `starting_at`, `ending_at` — time range (RFC 3339)
- `bucket_width` — `1m` (max 1440), `1h` (max 168), `1d` (max 31)
- `group_by[]` — `model`, `workspace_id`, `api_key_id`, `service_tier`, `context_window`, `inference_geo`, `speed`
- Filter arrays: `models[]`, `workspace_ids[]`, `api_key_ids[]`, `service_tiers[]`, `context_window[]`, `inference_geos[]`, `speeds[]`
- Pagination: `limit`, `page`

**Response fields per bucket:**
- `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`
- Grouped dimensions echoed back
- `has_more`, `next_page` for pagination

### Category 11: Admin API — Cost Report

| #   | Endpoint        | Method | Path                            | What It Returns                               |
| --- | --------------- | ------ | ------------------------------- | --------------------------------------------- |
| 44  | **Cost Report** | GET    | `/v1/organizations/cost_report` | Cost in USD cents by time bucket (daily only) |

**Query parameters:**
- `starting_at`, `ending_at` — time range
- `bucket_width` — `1d` only
- `group_by[]` — `workspace_id`, `description`
- When grouped by `description`: parsed fields include `model`, `inference_geo`
- Includes token usage costs, web search costs, code execution costs
- **Note:** Priority Tier costs are NOT included (track via usage endpoint instead)

### Category 12: Admin API — Claude Code Analytics

| #   | Endpoint                  | Method | Path                                         | What It Returns                               |
| --- | ------------------------- | ------ | -------------------------------------------- | --------------------------------------------- |
| 45  | **Claude Code Analytics** | GET    | `/v1/organizations/usage_report/claude_code` | Daily aggregated per-user Claude Code metrics |

**Query parameters:**
- `starting_at` — single day (YYYY-MM-DD format, UTC)
- `limit`, `page` — cursor-based pagination

**Response fields per user-day:**
- **Dimensions:** `date`, `actor` (email or API key name), `organization_id`, `customer_type` (api/subscription), `terminal_type` (vscode, iTerm.app, tmux, etc.)
- **Core metrics:** `num_sessions`, `lines_of_code.added`, `lines_of_code.removed`, `commits_by_claude_code`, `pull_requests_by_claude_code`
- **Tool actions:** `edit_tool.accepted/rejected`, `multi_edit_tool.accepted/rejected`, `write_tool.accepted/rejected`, `notebook_edit_tool.accepted/rejected`
- **Model breakdown:** per-model `tokens.input/output/cache_read/cache_creation`, `estimated_cost.amount` (USD cents), `estimated_cost.currency`
- Data freshness: ~1 hour delay
- Free to use

---

## Response Headers & Metadata (from every Messages API call)

### Standard Response Headers

| Header                      | What It Tells You                    |
| --------------------------- | ------------------------------------ |
| `request-id`                | Globally unique request identifier   |
| `anthropic-organization-id` | Organization ID for the API key used |

### Rate Limit Headers (every response)

| Header                                        | What It Tells You                        |
| --------------------------------------------- | ---------------------------------------- |
| `anthropic-ratelimit-requests-limit`          | Max RPM                                  |
| `anthropic-ratelimit-requests-remaining`      | Remaining RPM                            |
| `anthropic-ratelimit-requests-reset`          | RPM reset time (RFC 3339)                |
| `anthropic-ratelimit-input-tokens-limit`      | Max ITPM                                 |
| `anthropic-ratelimit-input-tokens-remaining`  | Remaining ITPM (rounded to nearest 1000) |
| `anthropic-ratelimit-input-tokens-reset`      | ITPM reset time                          |
| `anthropic-ratelimit-output-tokens-limit`     | Max OTPM                                 |
| `anthropic-ratelimit-output-tokens-remaining` | Remaining OTPM (rounded to nearest 1000) |
| `anthropic-ratelimit-output-tokens-reset`     | OTPM reset time                          |
| `anthropic-ratelimit-tokens-limit`            | Most restrictive combined token limit    |
| `anthropic-ratelimit-tokens-remaining`        | Remaining under most restrictive limit   |
| `anthropic-ratelimit-tokens-reset`            | Reset time for most restrictive limit    |
| `retry-after`                                 | Seconds to wait (only on 429 errors)     |

### Priority Tier Headers (if applicable)

| Header                                       | What It Tells You        |
| -------------------------------------------- | ------------------------ |
| `anthropic-priority-input-tokens-limit`      | Priority ITPM limit      |
| `anthropic-priority-input-tokens-remaining`  | Priority ITPM remaining  |
| `anthropic-priority-input-tokens-reset`      | Priority ITPM reset time |
| `anthropic-priority-output-tokens-limit`     | Priority OTPM limit      |
| `anthropic-priority-output-tokens-remaining` | Priority OTPM remaining  |
| `anthropic-priority-output-tokens-reset`     | Priority OTPM reset time |

### Fast Mode Headers (Opus 4.6 with speed="fast")

Separate `anthropic-fast-*` headers for fast mode rate limits.

---

## Usage Tier System

| Tier              | Credit Purchase Required | Max Single Purchase | Monthly Spend Limit |
| ----------------- | ------------------------ | ------------------- | ------------------- |
| Tier 1            | $5                       | $100                | Tier-specific       |
| Tier 2            | $40                      | $500                | Tier-specific       |
| Tier 3            | $200                     | $1,000              | Tier-specific       |
| Tier 4            | $400                     | $5,000              | Tier-specific       |
| Monthly Invoicing | N/A                      | N/A                 | Custom              |

Tiers auto-advance when deposit thresholds are met. Rate limits scale significantly per tier (e.g., Tier 1: 50 RPM → Tier 4: 4,000 RPM for Opus).

---

## Beta Features Available (via `anthropic-beta` header)

| Beta Header                        | Feature                    |
| ---------------------------------- | -------------------------- |
| `prompt-caching-2024-07-31`        | Prompt caching             |
| `computer-use-2025-01-24`          | Computer use               |
| `pdfs-2024-09-25`                  | PDF processing             |
| `token-counting-2024-11-01`        | Token counting             |
| `token-efficient-tools-2025-02-19` | Token-efficient tools      |
| `output-128k-2025-02-19`           | 128K output tokens         |
| `files-api-2025-04-14`             | Files API                  |
| `mcp-client-2025-11-20`            | MCP client                 |
| `dev-full-thinking-2025-05-14`     | Full thinking output       |
| `interleaved-thinking-2025-05-14`  | Interleaved thinking       |
| `code-execution-2025-05-22`        | Server-side code execution |
| `extended-cache-ttl-2025-04-11`    | Extended cache TTL         |
| `context-1m-2025-08-07`            | 1M token context window    |
| `context-management-2025-06-27`    | Context management         |
| `skills-2025-10-02`                | Agent Skills               |
| `fast-mode-2026-02-01`             | Fast mode (Opus 4.6)       |

---

## Enterprise / Compliance (separate from API)

- **Compliance API**: Real-time programmatic access to Claude usage data for compliance teams. Enables continuous monitoring and automated policy enforcement.
- **Audit trails**: User sign-ins, session starts, API token usage all logged.
- **SSO**: SAML 2.0 and OIDC-based SSO for centralized authentication.
- **Zero-data-retention**: Optional ZDR for API requests.
- **SOC 2-aligned**: Audit capabilities.

---

## Integration Patterns Analysis

### What cc-hdrm Currently Uses (4 endpoints)

| Endpoint                                            | Auth                                   | Purpose                     |
| --------------------------------------------------- | -------------------------------------- | --------------------------- |
| `GET https://claude.ai/oauth/authorize`             | Browser redirect                       | OAuth authorization         |
| `POST https://console.anthropic.com/v1/oauth/token` | Client credentials                     | Token exchange & refresh    |
| `GET https://api.anthropic.com/api/oauth/usage`     | Bearer token + `oauth-2025-04-20` beta | 5h/7d usage, extra usage    |
| `GET https://api.anthropic.com/api/oauth/profile`   | Bearer token + `oauth-2025-04-20` beta | Subscription tier, org type |

**Authentication model:** OAuth 2.0 with PKCE. No admin API keys used. All data comes through OAuth-scoped endpoints.

### Two Authentication Worlds

There are **two completely separate API authentication systems** that expose different data:

#### World 1: OAuth Bearer Token (what cc-hdrm uses now)
- Scoped to individual user's subscription
- Endpoints under `/api/oauth/*` — undocumented/internal
- Returns: personal usage utilization, subscription tier, extra usage credits
- No admin privileges needed — any authenticated user can access their own data
- Requires `oauth-2025-04-20` beta header

#### World 2: Admin API Key (`sk-ant-admin...`)
- Scoped to entire organization
- Endpoints under `/v1/organizations/*` — publicly documented
- Returns: org-wide usage reports, cost reports, member lists, workspace management, API key management, Claude Code analytics
- Requires admin role in the organization
- Only available for Team/Enterprise plans (NOT individual accounts)

**Key implication for cc-hdrm:** The Admin API endpoints are powerful but require a fundamentally different authentication approach. cc-hdrm's current OAuth flow cannot access them. Adding Admin API support would mean:
1. A separate credential entry (admin API key pasted/stored in Keychain)
2. A separate API client path
3. Only useful for Team/Enterprise users

### Integration Patterns by Data Source

#### Pattern A: OAuth Endpoints (current — no code changes needed to access more)

Currently cc-hdrm hits `/api/oauth/usage` and `/api/oauth/profile`. These are undocumented internal endpoints. There may be additional OAuth-scoped endpoints, but they're not publicly documented. The data available through OAuth is limited to:
- Usage utilization (5h, 7d windows)
- Subscription tier info
- Extra usage credits

**Polling strategy:** cc-hdrm already polls these on a timer. Data freshness is near-real-time.

#### Pattern B: Rate Limit Response Headers (free metadata from existing calls)

Every API response already includes 12+ rate limit headers. cc-hdrm currently does NOT parse these from its OAuth calls. This is the **lowest-effort integration** — just read headers from responses already being made:

- Current RPM/ITPM/OTPM limits and remaining capacity
- Reset times for each limit type
- Priority Tier headers (if applicable)
- `request-id` and `anthropic-organization-id`

**Effort:** Minimal — add header parsing to existing `APIClient` response handling.
**Value:** Real-time rate limit visibility without extra API calls.

#### Pattern C: Admin API — Usage & Cost Reports (requires admin key)

**Usage Report** (`/v1/organizations/usage_report/messages`):
- Token-level granularity: input, output, cache_read, cache_creation
- Time buckets: 1-minute, 1-hour, 1-day
- Group by: model, workspace, API key, service tier, context window, inference geo, speed
- Filter by any dimension
- Data freshness: ~5 minutes
- Polling: supports 1/minute sustained

**Cost Report** (`/v1/organizations/cost_report`):
- USD cents by day
- Group by workspace and/or description (includes model, inference_geo)
- Includes: token costs, web search costs, code execution costs
- Priority Tier costs NOT included (tracked separately)

**Integration approach:**
- Separate `AdminAPIClient` with admin key auth
- Cursor-based pagination for large orgs
- 5-minute polling interval matches data freshness
- Could coexist alongside OAuth-based personal usage tracking

#### Pattern D: Admin API — Claude Code Analytics (requires admin key)

**Claude Code Analytics** (`/v1/organizations/usage_report/claude_code`):
- Per-user per-day metrics
- Dimensions: email, terminal type, customer type
- Metrics: sessions, LOC added/removed, commits, PRs, tool acceptance rates
- Model breakdown with estimated costs
- Data freshness: ~1 hour
- Free to use

**Integration approach:** Daily poll (data is daily aggregated). Rich productivity dashboard potential.

#### Pattern E: Admin API — Org Management (requires admin key)

- Members, workspaces, API keys, invites
- Useful for labeling/enriching usage data with human-readable names
- Low-frequency polling (on-demand or hourly) — this data rarely changes

### Swift-Specific Integration Notes

**Third-party Swift SDKs available:**
- [SwiftAnthropic](https://github.com/jamesrochabrun/SwiftAnthropic) — Messages API focused
- [AnthropicSwiftSDK](https://github.com/fumito-ito/AnthropicSwiftSDK) — Includes admin API support (`AnthropicAdmin`)

**cc-hdrm's current approach:** Custom `APIClient` using native `URLSession`. Given the simplicity of the Admin API (standard REST with JSON), continuing with native `URLSession` is likely better than adding a dependency.

**Admin key storage:** Would use the same Keychain approach cc-hdrm already uses for OAuth tokens.

### Authentication Security Considerations

- Admin API keys start with `sk-ant-admin...` — they're permanent secrets (no expiry/rotation via API)
- Cannot create new admin keys via API — must be provisioned in Console
- Recommended rotation: every 90 days via Console
- cc-hdrm should store admin keys in Keychain (not UserDefaults)
- Admin keys cannot be used for Messages API calls (separate auth domain)

### Data Freshness & Polling Strategy Summary

| Data Source            | Freshness      | Recommended Poll Interval  | Auth         |
| ---------------------- | -------------- | -------------------------- | ------------ |
| OAuth usage/profile    | Real-time      | 30s–5min (current)         | OAuth        |
| Rate limit headers     | Real-time      | Per-request (free)         | OAuth        |
| Usage Report           | ~5 min         | 5 min                      | Admin key    |
| Cost Report            | ~5 min         | 1 hour (daily granularity) | Admin key    |
| Claude Code Analytics  | ~1 hour        | 1 hour or daily            | Admin key    |
| Org/Members/Workspaces | Rarely changes | On-demand or hourly        | Admin key    |
| Models list            | Rarely changes | Daily or on-demand         | Standard key |

---

## Architectural Patterns for cc-hdrm Integration

### Current Architecture (baseline)

cc-hdrm is a macOS menu bar app (SwiftUI + `MenuBarExtra`) with:
- `OAuthService` — PKCE OAuth flow via `claude.ai`
- `TokenRefreshService` — automatic token refresh via `console.anthropic.com`
- `APIClient` — fetches `/api/oauth/usage` and `/api/oauth/profile` with Bearer tokens
- Keychain storage for OAuth credentials
- Polling timer for periodic data refresh
- `@Observable` / `ObservableObject` state management driving SwiftUI views

### Architecture Option A: Header Parsing (Zero New Endpoints)

**Pattern:** Enrich existing data by parsing response headers from calls already being made.

```
APIClient.fetchUsage() → HTTPURLResponse
  ├── Body → UsageData (existing)
  └── Headers → RateLimitSnapshot (NEW)
        ├── requests: limit/remaining/reset
        ├── inputTokens: limit/remaining/reset
        └── outputTokens: limit/remaining/reset
```

**Design:**
- Add `RateLimitSnapshot` struct parsed from `HTTPURLResponse.allHeaderFields`
- Return as secondary output from existing API calls (tuple or combined model)
- No new network calls, no new auth, no new polling
- `@Observable` `RateLimitStore` updated on every existing poll cycle

**Complexity:** Very low. Pure data parsing.

### Architecture Option B: Admin API as Optional Add-On

**Pattern:** Dual-credential architecture — OAuth for personal data, Admin key for org data.

```
┌─────────────────────────────────────────────┐
│                  cc-hdrm                     │
│                                              │
│  ┌──────────────┐    ┌───────────────────┐  │
│  │ OAuthClient   │    │ AdminAPIClient     │  │
│  │ (Bearer token)│    │ (sk-ant-admin key) │  │
│  │               │    │                    │  │
│  │ /oauth/usage  │    │ /v1/orgs/usage_rpt │  │
│  │ /oauth/profile│    │ /v1/orgs/cost_rpt  │  │
│  │               │    │ /v1/orgs/cc_analytics│ │
│  │               │    │ /v1/orgs/users     │  │
│  │               │    │ /v1/orgs/workspaces│  │
│  │               │    │ /v1/models         │  │
│  └──────┬───────┘    └──────┬────────────┘  │
│         │                    │                │
│         └────────┬───────────┘                │
│                  ▼                            │
│         DataAggregator                        │
│         (merges both sources)                 │
│                  │                            │
│                  ▼                            │
│         @Observable ViewModels                │
│                  │                            │
│                  ▼                            │
│         SwiftUI Views                         │
│         (menu bar + popover)                  │
└─────────────────────────────────────────────┘
```

**Design decisions:**

1. **Credential storage:** Separate Keychain entries (`kSecAttrService` = `com.cc-hdrm.oauth` vs `com.cc-hdrm.admin-api`). Admin key stored as `kSecClassGenericPassword`. No iCloud sync for admin key.

2. **Feature gating:** Admin API features shown only when admin key is configured. Graceful degradation — app works fully without it (current behavior). Settings panel with "Add Admin API Key" option.

3. **Polling orchestration:** Independent timers per data source:
   - OAuth usage/profile: 30s–5min (existing)
   - Admin usage report: 5 min
   - Admin cost report: 1 hour
   - Claude Code analytics: 1 hour or daily
   - Org metadata (members/workspaces): on-demand or hourly

4. **Data aggregation:** `DataAggregator` merges OAuth personal data with Admin org data. Resolves workspace IDs → names, API key IDs → labels. Enriches usage data with cost data for complete picture.

5. **Error isolation:** Admin API failures don't affect OAuth data flow. Separate error states per client. Admin key invalid → show warning, continue with OAuth-only mode.

### Architecture Option C: Admin-Only Mode (Alternative)

**Pattern:** For Team/Enterprise users who prefer admin key over OAuth.

Some users may want to skip OAuth entirely and use only admin key + usage/cost APIs. This is a simpler auth flow (paste key → done) but loses personal usage utilization data (5h/7d windows) which is OAuth-only.

**Trade-off:** Simpler setup, less data. Could be a "lite mode" for org admins who care about team-wide metrics, not personal utilization.

### Data Model Architecture

```
PersonalUsage (from OAuth)          OrgUsage (from Admin API)
├── fiveHour: Utilization           ├── tokenBuckets: [TimeBucket]
├── sevenDay: Utilization           │   ├── inputTokens
├── sevenDaySonnet: Utilization?    │   ├── outputTokens
├── extraUsage: ExtraUsage?         │   ├── cacheReadTokens
└── tier: SubscriptionTier          │   └── cacheCreationTokens
                                    ├── costBuckets: [CostBucket]
RateLimits (from headers)           │   └── amountCentsUSD
├── requests: Limit                 ├── ccAnalytics: [UserDay]
├── inputTokens: Limit              │   ├── sessions, loc, commits, prs
├── outputTokens: Limit             │   └── toolActions, modelBreakdown
└── priorityTokens: Limit?         ├── members: [Member]
                                    ├── workspaces: [Workspace]
                                    └── apiKeys: [APIKey]
```

### Security Architecture

- **Admin key never leaves Keychain** — loaded into memory only for request signing
- **No admin key in UserDefaults, plists, or logs**
- **Entitlements:** Existing `cc-hdrm.entitlements` already grants Keychain access and network permissions — no changes needed
- **Admin key validation:** Test with `GET /v1/organizations/me` on entry — fast, free, confirms key works
- **Key rotation reminder:** Optional notification when key age > 90 days (store creation date in Keychain metadata)

### UI Architecture Considerations

Menu bar space is limited. New data sources could manifest as:
- **Expanded popover sections** — toggle between Personal/Organization views
- **Tabbed popover** — tabs for Usage, Cost, Claude Code Analytics
- **Status bar indicators** — rate limit utilization as secondary icon/color
- **Separate window** — full dashboard for admin data (triggered from popover)

_Sources: [Apple MenuBarExtra docs](https://developer.apple.com/documentation/SwiftUI/Building-and-customizing-the-menu-bar-with-SwiftUI), [Keychain Services](https://developer.apple.com/documentation/security/storing-keys-in-the-keychain), [Swift by Sundell - Combine pipelines](https://www.swiftbysundell.com/articles/connecting-and-merging-combine-publishers-in-swift/)_

---

## Implementation Roadmap

### Phase 0: Rate Limit Header Parsing (no new endpoints)

**Effort:** Small (1-2 story points)
**Value:** Real-time rate limit visibility from data already being received
**Audience:** All users (OAuth-only, no admin key needed)

**What to build:**
- `RateLimitSnapshot` struct with `limit`, `remaining`, `reset` for requests/inputTokens/outputTokens
- Parse from `HTTPURLResponse.allHeaderFields` in existing `APIClient` response handling
- `@Observable` `RateLimitStore` updated on every existing poll cycle
- UI: small rate limit indicator in menu bar popover (utilization bars or percentages)

**Risk:** Low. Pure read-only header parsing on existing responses.

### Phase 1: Models List (standard API key)

**Effort:** Tiny (0.5 story points)
**Value:** Dynamic model discovery — populate dropdowns, validate model names, show available models
**Audience:** All users

**What to build:**
- `GET /v1/models` with standard API key (or even Bearer token — needs verification)
- Cache locally, refresh daily or on-demand
- Simple model catalog display

**Risk:** Very low. Public, documented, stable endpoint.

### Phase 2: Admin API Key Entry + Validation

**Effort:** Medium (3-5 story points)
**Value:** Prerequisite for all Admin API features (Phases 3-6)
**Audience:** Team/Enterprise users only

**What to build:**
- Settings panel with `SecureField` for admin API key input
- Keychain storage under separate service identifier (`com.cc-hdrm.admin-api`)
- Validation call: `GET /v1/organizations/me` — confirms key works, retrieves org name
- Feature gate: Admin API sections in UI appear only when key is configured and validated
- Error handling: invalid key, expired key, network failure — with clear user messaging
- "Remove Admin Key" option to clear credential

**Important constraints:**
- Admin API is **unavailable for individual accounts** — only Team/Enterprise orgs
- Admin keys can only be created in Console (not via API)
- Admin keys start with `sk-ant-admin...` — validate prefix on entry
- Recommended rotation: every 90 days (optional reminder)

**Risk:** Medium. New credential flow, but straightforward Keychain pattern already exists in codebase.

### Phase 3: Organization Metadata

**Effort:** Small (2 story points)
**Value:** Human-readable labels for workspaces, members, API keys — enriches all subsequent data
**Audience:** Team/Enterprise users with admin key

**What to build:**
- Fetch and cache: `GET /v1/organizations/workspaces`, `/users`, `/api_keys`
- Refresh: hourly or on-demand (this data rarely changes)
- Local lookup maps: `workspaceId → name`, `apiKeyId → name`, `userId → email`
- Used by Phases 4-6 to display human-readable labels instead of raw UUIDs

**Risk:** Low. Simple REST GETs with pagination.

### Phase 4: Usage Report Integration

**Effort:** Medium-Large (5-8 story points)
**Value:** Token-level granularity (input/output/cached/uncached), groupable by model/workspace/key/tier/geo/speed
**Audience:** Team/Enterprise users with admin key

**What to build:**
- `AdminAPIClient.fetchUsageReport()` calling `GET /v1/organizations/usage_report/messages`
- Polling: every 5 minutes (matches data freshness)
- Cursor-based pagination for large result sets
- Configurable grouping: model, workspace, API key, service tier, context window, inference geo, speed

**Response schema (verified from API reference):**
```
data[].starting_at / ending_at — time bucket bounds
data[].results[]:
  ├── uncached_input_tokens: number
  ├── output_tokens: number
  ├── cache_read_input_tokens: number
  ├── cache_creation.ephemeral_5m_input_tokens: number
  ├── cache_creation.ephemeral_1h_input_tokens: number
  ├── server_tool_use.web_search_requests: number
  ├── model: string (if grouped)
  ├── workspace_id: string (if grouped)
  ├── api_key_id: string (if grouped)
  ├── service_tier: standard|batch|priority|priority_on_demand|flex|flex_discount
  ├── context_window: "0-200k"|"200k-1M" (if grouped)
  ├── inference_geo: string (if grouped)
  └── speed: "standard"|"fast" (if grouped, requires fast-mode beta header)
```

**UI options:** Charts (token consumption over time), breakdowns by model/workspace, cache efficiency metrics.

**Risk:** Medium. Most complex endpoint with many grouping/filter dimensions. Need robust pagination handling.

### Phase 5: Cost Report Integration

**Effort:** Medium (3-5 story points)
**Value:** Actual USD costs per day — replaces estimated calculations with real billing data
**Audience:** Team/Enterprise users with admin key

**What to build:**
- `AdminAPIClient.fetchCostReport()` calling `GET /v1/organizations/cost_report`
- Polling: hourly (daily granularity only, so more frequent polling wastes resources)
- Group by workspace and/or description (parsed fields include model, inference_geo)
- Includes: token costs, web search costs, code execution costs

**Caveats:**
- Daily granularity only (`1d` bucket width)
- Priority Tier costs NOT included — track via usage endpoint with `service_tier` filter instead
- Costs reported in USD cents as decimal strings

**Risk:** Low-Medium. Simpler than usage report, but cost data requires careful display (currency formatting, aggregation).

### Phase 6: Claude Code Analytics

**Effort:** Medium (3-5 story points)
**Value:** Per-user developer productivity metrics — sessions, LOC, commits, PRs, tool acceptance rates
**Audience:** Team/Enterprise users with admin key

**What to build:**
- `AdminAPIClient.fetchClaudeCodeAnalytics()` calling `GET /v1/organizations/usage_report/claude_code`
- Polling: daily (data is daily aggregated, ~1 hour freshness)
- Per-user metrics with model breakdown and estimated costs

**Unique data not available elsewhere:**
- `lines_of_code.added / removed` by Claude Code
- `commits_by_claude_code`, `pull_requests_by_claude_code`
- Tool acceptance rates: edit_tool, multi_edit_tool, write_tool, notebook_edit_tool
- `terminal_type`: vscode, iTerm.app, tmux, etc.
- `customer_type`: api vs subscription

**Risk:** Low. Simple daily query, well-documented response schema, free to use.

### Implementation Priority Matrix

| Phase                 | Effort      | Value                 | Auth Required   | User Base       |
| --------------------- | ----------- | --------------------- | --------------- | --------------- |
| 0: Rate limit headers | Very Low    | Medium                | None (existing) | All users       |
| 1: Models list        | Very Low    | Low                   | Standard key    | All users       |
| 2: Admin key entry    | Medium      | Prerequisite          | New credential  | Team/Enterprise |
| 3: Org metadata       | Low         | Medium (enriches all) | Admin key       | Team/Enterprise |
| 4: Usage report       | Medium-High | High                  | Admin key       | Team/Enterprise |
| 5: Cost report        | Medium      | High                  | Admin key       | Team/Enterprise |
| 6: CC Analytics       | Medium      | Medium-High           | Admin key       | Team/Enterprise |

**Recommended order:** 0 → 1 → 2 → 3 → 4 → 5 → 6

Phases 0-1 ship to ALL users with zero new auth. Phases 2-6 are Team/Enterprise gated behind admin key.

### Risk Assessment

| Risk                                         | Impact                               | Likelihood          | Mitigation                                            |
| -------------------------------------------- | ------------------------------------ | ------------------- | ----------------------------------------------------- |
| Admin API not available for individual users | Phases 2-6 useless for Pro/Max users | Certain (confirmed) | Clear messaging; Phases 0-1 still add value for all   |
| Undocumented OAuth endpoints change          | Breaks existing usage/profile fetch  | Medium              | Monitor for API changes; degrade gracefully           |
| Admin API rate limits                        | Too many polling calls throttled     | Low                 | Admin API has generous limits; respect `retry-after`  |
| Admin key rotation forgotten                 | Key expires, admin features stop     | Low                 | Optional age reminder; graceful degradation           |
| Large org pagination                         | Slow/incomplete data for big orgs    | Low-Medium          | Implement proper cursor-based pagination from day one |
| Cache read token field changes               | Ephemeral TTL fields evolving        | Low                 | Defensive parsing; handle missing fields gracefully   |

_Sources: [Admin API Overview](https://platform.claude.com/docs/en/api/administration-api), [Usage Report API Reference](https://platform.claude.com/docs/en/api/admin-api/usage-cost/get-messages-usage-report), [Apple SecureField](https://developer.apple.com/documentation/swiftui/securefield), [API Key Best Practices](https://support.claude.com/en/articles/9767949-api-key-best-practices-keeping-your-keys-safe-and-secure)_

---

## Additional Endpoints Discovered (Late-Breaking)

During final verification, these additional API features were confirmed:

| Feature                              | Status         | Notes                                                                                                        |
| ------------------------------------ | -------------- | ------------------------------------------------------------------------------------------------------------ |
| **Enterprise Analytics API**         | Available      | Programmatic access to Claude & Claude Code Remote engagement data. Separate from Claude Code Analytics API. |
| **Web Fetch Tool**                   | Beta           | Claude can retrieve full web page/PDF content. Server-side tool tracked in usage report (`server_tool_use`). |
| **Automatic Caching**                | GA             | Single `cache_control` field; system auto-caches last cacheable block. Simplifies cache strategy.            |
| **Data Residency (`inference_geo`)** | GA (Feb 2026+) | US-only inference at 1.1x pricing. Trackable via usage report `inference_geo` dimension.                     |
| **Fine-Grained Tool Streaming**      | GA             | No beta header needed. All models/platforms.                                                                 |
| **Web Search Dynamic Filtering**     | GA             | Reduces token cost for web search tool use.                                                                  |

_Source: [Anthropic API Release Notes](https://docs.anthropic.com/en/release-notes/api), [Releasebot - Anthropic](https://releasebot.io/updates/anthropic)_

---

## Conclusion

cc-hdrm currently uses 4 of 45+ available endpoints. The lowest-hanging fruit (rate limit header parsing) requires zero new API calls. The highest-value additions (Admin API usage/cost reports) require a second credential flow but unlock org-wide operational visibility that no other tool provides in a macOS menu bar format.

**The recommended path forward:**
1. Ship Phase 0 (headers) and Phase 1 (models) to all users immediately
2. Build the Admin key credential flow (Phase 2) as the gateway to Phases 3-6
3. Prioritize Usage Report (Phase 4) as the single highest-value Admin API integration
4. Claude Code Analytics (Phase 6) is unique data — no other tool surfaces per-user LOC/commit/PR metrics from a menu bar

The Admin API's Team/Enterprise-only restriction means cc-hdrm should always work fully without it. Treat Admin API features as a "pro tier" overlay on top of the existing OAuth-based personal usage tracking.

---

**Technical Research Completed:** 2026-02-24
**Source Verification:** All claims verified against current Anthropic documentation
**Confidence Level:** High — primary sources are official API docs and reference pages

---

## Sources

- [API Overview](https://platform.claude.com/docs/en/api/overview)
- [Admin API Overview](https://platform.claude.com/docs/en/api/administration-api)
- [Usage and Cost API](https://platform.claude.com/docs/en/build-with-claude/usage-cost-api)
- [Usage Report API Reference](https://platform.claude.com/docs/en/api/admin-api/usage-cost/get-messages-usage-report)
- [Claude Code Analytics API](https://platform.claude.com/docs/en/api/claude-code-analytics-api)
- [Rate Limits](https://platform.claude.com/docs/en/api/rate-limits)
- [Service Tiers](https://platform.claude.com/docs/en/api/service-tiers)
- [Files API](https://platform.claude.com/docs/en/build-with-claude/files)
- [Skills API](https://platform.claude.com/docs/en/api/beta/skills)
- [API Key Best Practices](https://support.claude.com/en/articles/9767949-api-key-best-practices-keeping-your-keys-safe-and-secure)
- [Anthropic Compliance API (Token Security)](https://www.token.security/blog/why-anthropics-new-compliance-api-is-a-game-changer-for-secure-agentic-ai-access)
- [Anthropic API Release Notes](https://docs.anthropic.com/en/release-notes/api)
- [SwiftAnthropic SDK](https://github.com/jamesrochabrun/SwiftAnthropic)
- [AnthropicSwiftSDK](https://github.com/fumito-ito/AnthropicSwiftSDK)
- [Apple SecureField](https://developer.apple.com/documentation/swiftui/securefield)
- [Apple Keychain Services](https://developer.apple.com/documentation/security/storing-keys-in-the-keychain)
- [Apple MenuBarExtra](https://developer.apple.com/documentation/SwiftUI/Building-and-customizing-the-menu-bar-with-SwiftUI)
