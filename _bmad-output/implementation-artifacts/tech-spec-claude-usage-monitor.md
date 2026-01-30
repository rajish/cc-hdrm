---
title: 'Claude Usage Monitor'
slug: 'claude-usage-monitor'
created: '2026-01-30'
status: 'ready-for-dev'
stepsCompleted: [1, 2, 3, 4]
tech_stack: ['TypeScript', 'MCP SDK (@modelcontextprotocol/sdk)', 'Node.js']
files_to_modify: ['package.json', 'tsconfig.json', 'src/index.ts', 'src/auth.ts', 'src/usage-api.ts', 'src/session-parser.ts', 'src/tools/get-usage.ts', 'src/tools/get-session-tokens.ts', 'src/tools/get-cache-status.ts', 'src/types.ts', 'src/constants.ts', 'src/formatting.ts', 'tests/auth.test.ts', 'tests/usage-api.test.ts', 'tests/session-parser.test.ts', 'tests/formatting.test.ts']
code_patterns: ['MCP stdio server', 'macOS Keychain access via security CLI', 'JSONL session file parsing']
test_patterns: ['vitest', 'Unit tests for token aggregation', 'Mock keychain responses via child_process', 'Integration test against local session files']
---

# Tech-Spec: Claude Usage Monitor

**Created:** 2026-01-30

## Overview

### Problem Statement

There is no way to see token counts, cache timers, or session/weekly usage bars when using Claude through coding agents (Claude Code CLI, OpenCode TUI, OpenCode Desktop App). The claude-counter browser extension only works on claude.ai in a browser — developers using terminal/desktop coding agents are blind to their subscription usage limits.

### Solution

Build an MCP server that exposes usage tracking tools and resources. Since Claude Code, OpenCode TUI, and OpenCode Desktop all support MCP servers, a single MCP server covers all three interfaces with one codebase. The server will provide on-demand token counts, cache timers, session usage bars (5-hour window), and weekly usage bars (7-day window) with reset countdowns — mirroring the features of the claude-counter browser extension.

### Scope

**In Scope:**

- Approximate token count for current conversation (vs 200k context limit)
- Cache timer (how long conversation remains cached)
- Session usage bar (5-hour window) with reset countdown
- Weekly usage bar (7-day window) with reset countdown
- Works across: Claude Code CLI, OpenCode TUI, OpenCode Desktop App
- Research phase to determine how each platform exposes usage data (API interception, local files, endpoints)

**Out of Scope:**

- Browser extension (claude-counter already covers that)
- Modifying Claude Code or OpenCode source code
- Paid API usage tracking (focus is on subscription models: Pro/Max)

## Context for Development

### Codebase Patterns

Greenfield project. MCP stdio server pattern using `@modelcontextprotocol/sdk`.

**Data Sources Identified:**

1. **Subscription usage (5h/7d windows):** `GET https://claude.ai/api/oauth/usage` authenticated with OAuth token from macOS Keychain. Returns:
   - `five_hour.utilization` (0-100%), `five_hour.resets_at` (ISO timestamp)
   - `seven_day.utilization` (0-100%), `seven_day.resets_at` (ISO timestamp)
   - `seven_day_sonnet.utilization`, `seven_day_sonnet.resets_at`
   - `extra_usage` (for Pro/Max plans)

2. **Per-message token counts:** Session JSONL files at `~/.claude/projects/{project}/{session}.jsonl`. Each assistant message contains:
   - `usage.input_tokens`, `usage.output_tokens`
   - `usage.cache_creation_input_tokens`, `usage.cache_read_input_tokens`
   - `usage.cache_creation.ephemeral_5m_input_tokens`, `usage.cache_creation.ephemeral_1h_input_tokens`
   - `usage.service_tier`

3. **Auth credentials:** macOS Keychain entry `"Claude Code-credentials"` (account = system username) stores JSON:
   - `claudeAiOauth.accessToken` (OAuth bearer token: `sk-ant-oat01-...`)
   - `claudeAiOauth.refreshToken`
   - `claudeAiOauth.expiresAt` (epoch ms)
   - `claudeAiOauth.subscriptionType` (e.g. `"max"`, `"pro"`)
   - `claudeAiOauth.rateLimitTier` (e.g. `"default_claude_max_5x"`)

4. **Cloudflare challenge:** Direct HTTP calls to `claude.ai` are blocked by Cloudflare. Claude Code's binary uses custom headers (`User-Agent`, `x-app: cli`, `anthropic-client-platform`) and internal auth helpers to bypass. The MCP server will need to replicate these headers or find an alternative approach (e.g. use `api.anthropic.com` endpoints if available, or shell out to the claude binary).

### Files to Reference

| File | Purpose |
| ---- | ------- |
| claude-counter `src/injected/bridge.js` | Shows how usage data is intercepted from SSE streams and `/usage` API |
| claude-counter `src/content/main.js` | Shows usage parsing logic for `five_hour`/`seven_day` windows |
| claude-counter `src/content/constants.js` | Constants: 5min cache window, 200k context limit |
| `~/.claude/projects/{project}/{session}.jsonl` | Per-message token usage data |
| macOS Keychain `"Claude Code-credentials"` | OAuth token and subscription info |
| Claude Code binary strings | Reveals `/api/oauth/usage`, `/api/oauth/organizations/` endpoints |

### Technical Decisions

- **MCP server** as the delivery mechanism (shared across all target platforms)
- **TypeScript + Node.js** for the MCP server (aligns with MCP SDK ecosystem)
- **macOS Keychain** for credential retrieval (via `security` CLI command)
- **Subscription model focus** (Pro/Max), not API key billing
- **Cloudflare bypass strategy:** Replicate Claude Code's exact request headers (`User-Agent`, `x-app: cli`, `anthropic-client-platform: claude-code`) with the OAuth bearer token. If Cloudflare still blocks, fall back to shelling out to `claude` CLI with a usage query, or parsing the built-in `/usage` command output.

## Implementation Plan

### Tasks

- [ ] Task 1: Project scaffolding
  - File: `package.json`
  - Action: Initialize Node.js project with dependencies: `@modelcontextprotocol/sdk`, `typescript`, `vitest` (dev). Set `"type": "module"`, add build/dev/test scripts. Entry point: `dist/index.js`.
  - File: `tsconfig.json`
  - Action: Configure TypeScript with `"target": "ES2022"`, `"module": "Node16"`, `"moduleResolution": "Node16"`, `"outDir": "dist"`, strict mode enabled.
  - Notes: Use Node.js native `fetch` (available in Node 18+) — no external HTTP dependency needed.

- [ ] Task 2: Type definitions and constants
  - File: `src/types.ts`
  - Action: Define TypeScript interfaces:
    - `OAuthCredentials` — `{ accessToken, refreshToken, expiresAt, subscriptionType, rateLimitTier }`
    - `KeychainPayload` — `{ claudeAiOauth: OAuthCredentials }`
    - `UsageWindow` — `{ utilization: number, resets_at: string | null }`
    - `UsageResponse` — `{ five_hour: UsageWindow | null, seven_day: UsageWindow | null, seven_day_sonnet: UsageWindow | null, extra_usage?: ExtraUsage }`
    - `ExtraUsage` — `{ is_enabled: boolean, used_credits: number | null, monthly_limit: number | null, utilization: number | null }`
    - `SessionMessage` — `{ type, message?: { usage?: TokenUsage }, timestamp }`
    - `TokenUsage` — `{ input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens, cache_creation?: { ephemeral_5m_input_tokens, ephemeral_1h_input_tokens } }`
    - `SessionTokenSummary` — `{ totalInputTokens, totalOutputTokens, totalCacheCreationTokens, totalCacheReadTokens, messageCount, lastMessageTimestamp, cacheExpiresAt: string | null }`
  - File: `src/constants.ts`
  - Action: Define constants:
    - `CONTEXT_LIMIT_TOKENS = 200_000`
    - `CACHE_5M_WINDOW_MS = 5 * 60 * 1000`
    - `CACHE_1H_WINDOW_MS = 60 * 60 * 1000`
    - `KEYCHAIN_SERVICE = "Claude Code-credentials"`
    - `CLAUDE_PROJECTS_DIR` = `~/.claude/projects`
    - `USAGE_API_URL = "https://claude.ai/api/oauth/usage"`
    - `USER_AGENT` string matching Claude Code's format

- [ ] Task 3: Keychain authentication module
  - File: `src/auth.ts`
  - Action: Implement `getOAuthCredentials(): Promise<OAuthCredentials>` that:
    1. Runs `security find-generic-password -s "Claude Code-credentials" -w` via `child_process.execSync`
    2. Parses the JSON output
    3. Extracts `claudeAiOauth` object
    4. Validates `expiresAt` — if token is expired, throw a clear error advising the user to run `claude` to refresh
    5. Returns the `OAuthCredentials` object
  - Action: Implement `getSystemUsername(): string` using `os.userInfo().username` for the keychain account parameter
  - Notes: macOS only for initial implementation. Guard with platform check and throw descriptive error on Linux/Windows.

- [ ] Task 4: Usage API client
  - File: `src/usage-api.ts`
  - Action: Implement `fetchUsage(credentials: OAuthCredentials): Promise<UsageResponse>` that:
    1. Calls `GET https://claude.ai/api/oauth/usage` with headers:
       - `Authorization: Bearer {accessToken}`
       - `User-Agent: {claude-code-style user agent}`
       - `x-app: cli`
       - `anthropic-client-platform: claude-code`
       - `Content-Type: application/json`
    2. Parses JSON response
    3. Normalizes the response into `UsageResponse` type
    4. Handles errors: 401 (expired token), 403 (Cloudflare/forbidden), network errors
  - Notes: If Cloudflare blocks this, implement fallback: parse output of `claude --usage` or equivalent CLI command. Document this as a known limitation that may require iteration.

- [ ] Task 5: Session JSONL parser
  - File: `src/session-parser.ts`
  - Action: Implement `findLatestSession(projectDir?: string): Promise<string | null>` that:
    1. Reads `~/.claude/projects/` directory
    2. If `projectDir` provided, maps it to the encoded project key format (e.g. `/Users/foo/proj` → `-Users-foo-proj`)
    3. Finds the most recently modified `.jsonl` file in the project directory
    4. Returns the full path, or `null` if none found
  - Action: Implement `parseSessionTokens(sessionPath: string): Promise<SessionTokenSummary>` that:
    1. Reads the JSONL file line by line
    2. Filters for `type: "assistant"` messages with `message.usage`
    3. Aggregates: `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`
    4. Counts total messages
    5. Computes `cacheExpiresAt` from the last message with ephemeral cache tokens:
       - If `ephemeral_5m_input_tokens > 0`: cache expires at `lastMessageTimestamp + 5min`
       - If `ephemeral_1h_input_tokens > 0`: cache expires at `lastMessageTimestamp + 1h`
       - If both present, use the later expiry
    6. Returns `SessionTokenSummary`
  - Notes: Files can be large (megabytes). Use streaming line reader, not `readFileSync`.

- [ ] Task 6: Text formatting utilities
  - File: `src/formatting.ts`
  - Action: Implement helper functions for rendering usage data as text (MCP tools return text, not UI):
    - `formatUsageBar(label: string, utilization: number, width: number): string` — ASCII progress bar e.g. `Session: [████████░░░░░░░░] 52% used`
    - `formatTimeUntilReset(resetsAt: string | null): string` — e.g. `Resets in 2h 34m`
    - `formatCacheTimer(expiresAt: string | null): string` — e.g. `Cache: 3m 12s remaining` or `Cache: expired`
    - `formatTokenCount(tokens: number, limit: number): string` — e.g. `Token count: 45.2k / 200k (22.6%)`
    - `formatFullUsageReport(usage: UsageResponse, session: SessionTokenSummary | null): string` — combines all of the above into a single formatted report

- [ ] Task 7: MCP tool — `get_usage`
  - File: `src/tools/get-usage.ts`
  - Action: Implement MCP tool `get_usage` that:
    1. Calls `getOAuthCredentials()` from auth module
    2. Calls `fetchUsage(credentials)` from usage-api module
    3. Formats results using `formatFullUsageReport()` (without session data)
    4. Returns formatted text showing:
       - Session (5h) usage bar + reset countdown
       - Weekly (7d) usage bar + reset countdown
       - Weekly Sonnet-only bar (if present)
       - Extra usage info (if Pro/Max with extra usage enabled)
       - Subscription type and rate limit tier
  - Input schema: `{}` (no parameters)
  - Notes: This is the primary tool users will call. Keep output concise.

- [ ] Task 8: MCP tool — `get_session_tokens`
  - File: `src/tools/get-session-tokens.ts`
  - Action: Implement MCP tool `get_session_tokens` that:
    1. Accepts optional `project_dir` parameter (defaults to cwd)
    2. Calls `findLatestSession(projectDir)` to locate the active session
    3. Calls `parseSessionTokens(sessionPath)` to aggregate token usage
    4. Formats and returns:
       - Total input/output tokens vs context limit (200k)
       - Cache creation tokens breakdown (5m vs 1h ephemeral)
       - Cache read tokens
       - Total message count
       - Cache timer (time remaining until cache expires)
  - Input schema: `{ project_dir?: string }`

- [ ] Task 9: MCP tool — `get_cache_status`
  - File: `src/tools/get-cache-status.ts`
  - Action: Implement MCP tool `get_cache_status` that:
    1. Accepts optional `project_dir` parameter
    2. Finds the latest session and parses it
    3. Returns focused cache information:
       - Whether conversation is currently cached
       - Time remaining on cache (5m and/or 1h windows)
       - Total cached tokens
  - Input schema: `{ project_dir?: string }`
  - Notes: This is a lightweight subset of `get_session_tokens` for quick cache checks.

- [ ] Task 10: MCP server entry point
  - File: `src/index.ts`
  - Action: Create the MCP server that:
    1. Initializes `Server` from `@modelcontextprotocol/sdk/server/index.js`
    2. Uses `StdioServerTransport` from `@modelcontextprotocol/sdk/server/stdio.js`
    3. Registers all three tools: `get_usage`, `get_session_tokens`, `get_cache_status`
    4. Handles the `tools/list` request (returns tool metadata)
    5. Handles the `tools/call` request (dispatches to the correct tool handler)
    6. Starts the server with `server.connect(transport)`
  - Notes: Follow the MCP SDK patterns for tool registration. Server name: `claude-usage-monitor`.

- [ ] Task 11: Build and integration test
  - File: `package.json` (scripts section)
  - Action: Ensure `npm run build` produces working `dist/index.js`. Verify the MCP server starts and responds to `tools/list` via stdio.
  - Notes: Manual integration test by adding the server to Claude Code's MCP config:
    ```json
    {
      "mcpServers": {
        "usage-monitor": {
          "command": "node",
          "args": ["/absolute/path/to/dist/index.js"]
        }
      }
    }
    ```

- [ ] Task 12: Unit tests
  - File: `tests/auth.test.ts`
  - Action: Test `getOAuthCredentials()` with:
    - Mock `child_process.execSync` returning valid JSON keychain output
    - Mock expired token (expiresAt in the past) — should throw
    - Mock missing keychain entry — should throw with helpful message
  - File: `tests/usage-api.test.ts`
  - Action: Test `fetchUsage()` with:
    - Mock successful response with full usage data
    - Mock 401 response (expired token)
    - Mock 403 response (Cloudflare block)
    - Mock network error
  - File: `tests/session-parser.test.ts`
  - Action: Test `parseSessionTokens()` with:
    - Fixture JSONL file with mixed message types (user, assistant, system, progress)
    - Verify correct token aggregation (only assistant messages with usage)
    - Verify cache expiry calculation from ephemeral tokens
    - Empty file returns zero counts
  - File: `tests/formatting.test.ts`
  - Action: Test formatting functions:
    - Usage bar at 0%, 50%, 100%, >100% (clamped)
    - Time formatting for various durations
    - Full report with all fields populated
    - Full report with null/missing optional fields

### Acceptance Criteria

- [ ] AC 1: Given a valid Claude Pro/Max subscription, when the user invokes the `get_usage` tool, then the tool returns a text report showing session (5h) and weekly (7d) usage percentages with reset countdowns.
- [ ] AC 2: Given an active Claude Code session with messages, when the user invokes `get_session_tokens`, then the tool returns the total input/output token counts, cache token breakdown, and context usage percentage (vs 200k limit).
- [ ] AC 3: Given a conversation with recently cached content, when the user invokes `get_cache_status`, then the tool returns whether the cache is active and how much time remains.
- [ ] AC 4: Given an expired OAuth token in the keychain, when any tool is invoked, then a clear error message is returned advising the user to run `claude` to refresh their session.
- [ ] AC 5: Given the MCP server is registered in Claude Code's config, when the user starts a Claude Code session, then the `get_usage`, `get_session_tokens`, and `get_cache_status` tools appear in the available tools list.
- [ ] AC 6: Given the MCP server is registered in OpenCode's config (`.opencode/config.json` or similar), when the user starts an OpenCode session, then the tools are available and functional.
- [ ] AC 7: Given the Cloudflare challenge blocks the HTTP request to `/api/oauth/usage`, when `get_usage` fails, then a clear error is returned explaining the limitation and suggesting alternatives.
- [ ] AC 8: Given no Claude Code session exists for the current project, when `get_session_tokens` is invoked, then a clear message indicates no session was found.
- [ ] AC 9: Given usage bar data, when formatted, then the ASCII progress bar renders correctly with the utilization percentage (e.g. `[████████░░░░] 67%`).

## Additional Context

### Dependencies

- `@modelcontextprotocol/sdk` (latest) — MCP server framework
- `typescript` (^5.x) — build-time
- `vitest` (^3.x) — test runner (dev dependency)
- Node.js built-ins only for runtime: `node:child_process`, `node:fs`, `node:readline`, `node:os`, `node:path`
- No external HTTP library — use Node.js native `fetch` (Node 18+)

### Testing Strategy

**Unit Tests (vitest):**
- Auth module: mock `child_process.execSync` for keychain access
- Usage API: mock `global.fetch` for HTTP responses
- Session parser: use fixture JSONL files with known token counts
- Formatting: pure function tests with snapshot assertions

**Integration Tests:**
- Start MCP server via stdio, send `tools/list` request, verify all 3 tools listed
- Send `tools/call` for `get_session_tokens` against a real local session file (if available)

**Manual Verification:**
- Register server in Claude Code MCP config, invoke tools from a live session
- Register server in OpenCode MCP config, verify tools work
- Test with expired token to verify error messaging

### Notes

**High-Risk Items:**
- **Cloudflare blocking** the `/api/oauth/usage` endpoint is the biggest risk. The Claude Code binary may have special Cloudflare clearance that a standalone Node.js process cannot replicate. Mitigation: if initial headers don't work, implement a fallback that shells out to the `claude` CLI (e.g. `claude --print-usage` or similar) or parses the `/usage` command output from a headless session.
- **Token expiry:** OAuth tokens expire. The MCP server should not attempt token refresh (that's Claude Code's responsibility). Instead, provide clear error messaging.

**Known Limitations:**
- macOS only for initial release (keychain access via `security` CLI)
- Cache timer is approximate — based on last message timestamp + ephemeral window, not a live server-side value
- Token counts are from the local session log, which may not include all conversation context (system prompts, tool definitions are not logged in the same way)

**Future Considerations (Out of Scope):**
- Linux/Windows keychain support
- MCP resource subscriptions for live-updating usage data
- Browser extension interop (share data between MCP server and claude-counter)
- Sonnet-only usage breakdown as a separate tool
- Extra usage spending tracking and alerts
