---
title: 'Keychain Access & Token Refresh Fixes'
slug: 'keychain-token-refresh-fix'
created: '2026-02-03'
status: 'final-review'
stepsCompleted: [1, 2, 3, 4]
tech_stack: [Swift, Security.framework, URLSession, UserNotifications]
files_to_modify:
  - cc-hdrm/cc_hdrm.entitlements
  - cc-hdrm/Services/TokenRefreshService.swift
  - cc-hdrmTests/Services/TokenRefreshServiceTests.swift
code_patterns:
  - Protocol-based services for testability
  - Injectable dataLoader closures for network mocking
  - os.Logger with category-specific loggers
  - AppError enum for unified error handling
test_patterns:
  - Swift Testing framework (@Suite, @Test)
  - Mock services via protocol conformance
  - Injectable closures for network layer
---

# Tech-Spec: Keychain Access & Token Refresh Fixes

**Created:** 2026-02-03

## Overview

### Problem Statement

cc-hdrm has two interconnected bugs preventing autonomous operation:

1. **Token refresh fails with HTTP 400** — The `TokenRefreshService` sends a request to `platform.claude.com/v1/oauth/token` that the server rejects as "Invalid request format". Users must manually run Claude Code in a terminal to refresh tokens.

2. **Keychain password prompts despite "Always Allow"** — After any credential change (e.g., token refresh by Claude Code), macOS prompts for the keychain password. The entitlements file (`cc_hdrm.entitlements`) is empty, causing the app to have no stable code signing identity for ACL persistence. Multiple cc-hdrm.app entries appear in Keychain Access because each rebuild is treated as a different app.

**Error observed:**
```
Token refresh failed with status 400: {"type":"error","error":{"type":"invalid_request_error","message":"Invalid request format"}}
```

### Solution

1. **Fix token refresh request format** — Investigate the correct OAuth2 request format expected by `platform.claude.com/v1/oauth/token` and update `TokenRefreshService` accordingly. May require adding `client_id`, different encoding, or matching Claude Code's exact request format.

2. **Restore proper entitlements** — Add keychain-access-groups entitlement and any other required entitlements to establish a stable app identity for Keychain ACL persistence.

### Scope

**In Scope:**
- Fix `TokenRefreshService` request format to get 200 responses from the token endpoint
- Restore `cc_hdrm.entitlements` with proper keychain access configuration
- Verify keychain reads/writes work without password prompts after entitlements fix
- Update tests if request format changes

**Out of Scope:**
- Sharing keychain access groups with Claude Code (requires their cooperation)
- Automatic ACL injection into keychain items
- Changes to how Claude Code stores credentials

## Context for Development

### Codebase Patterns

- Services use protocol-based design (`TokenRefreshServiceProtocol`, `KeychainServiceProtocol`) for testability
- Network requests use `URLSession` with injectable `dataLoader` closure — allows mock injection in tests
- Keychain access uses Security.framework directly (`SecItemCopyMatching`, `SecItemUpdate`, `SecItemAdd`)
- Logging via `os.Logger` with category-specific loggers (keychain, api, polling, notification, token)
- Error handling via single `AppError` enum with cases for all error types
- MVVM with service layer — services write to `@Observable` `AppState`, views read-only
- **Protected file warning:** `cc_hdrm.entitlements` is listed in AGENTS.md as protected, but user confirmed it was accidentally emptied and needs restoration

### Files to Reference

| File | Purpose |
| ---- | ------- |
| `cc-hdrm/Services/TokenRefreshService.swift:29-41` | Token refresh request construction — **broken**, returns 400 |
| `cc-hdrm/Services/KeychainService.swift:62-90` | Keychain write logic — uses `SecItemUpdate` then falls back to `SecItemAdd` |
| `cc-hdrm/Services/PollingEngine.swift:86-122` | Token refresh orchestration — calls TokenRefreshService, writes merged credentials |
| `cc-hdrm/cc_hdrm.entitlements` | Currently `<dict/>` (empty) — needs keychain entitlements |
| `cc-hdrm/Info.plist` | Has `LSUIElement=true`, no keychain config needed here |
| `cc-hdrmTests/Services/TokenRefreshServiceTests.swift` | Existing tests assume current format — need update if format changes |
| `cc-hdrmTests/Services/KeychainServiceTests.swift` | Tests keychain read/write with mock providers |

### Technical Decisions

- App is development-signed with Personal Team (Bundle ID: `com.cc-hdrm.app`)
- Signing Certificate: Development
- Keychain item service name: `"Claude Code-credentials"` (same as Claude Code)
- **Current (broken) token refresh:**
  - Endpoint: `https://platform.claude.com/v1/oauth/token`
  - Body: `grant_type=refresh_token&refresh_token=<token>`
  - Result: HTTP 400 "Invalid request format"
- **Correct token refresh format (discovered from OpenCode PR #9122):**
  - Endpoint: `https://console.anthropic.com/v1/oauth/token`
  - Body: `grant_type=refresh_token&refresh_token=<token>&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e`
  - Content-Type: `application/x-www-form-urlencoded`
- **Critical:** Claude Code deletes/recreates the keychain item on token refresh, resetting ACL (per GitHub #22144)
- **Important:** Refresh tokens have limited lifetime — after extended inactivity, the token itself expires and cannot be refreshed (returns 400). User must re-authenticate via Claude Code.

### Design Decision: Should cc-hdrm Attempt Token Refresh?

**Option A: Keep Token Refresh (current behavior)**
- Pro: Autonomous operation without user intervention
- Con: Writes to keychain → complicates ACL management
- Con: Need to reverse-engineer correct request format
- Con: If format changes upstream, cc-hdrm breaks

**Option B: Remove Token Refresh (read-only keychain)**
- Pro: Simpler, no write conflicts with Claude Code
- Pro: Avoids ACL complications from multiple writers
- Pro: Always uses Claude Code's known-good refresh
- Con: User must run Claude Code when token expires

**Recommendation:** Option B is safer long-term, but Option A is more user-friendly if we can fix the format. Decision deferred to implementation.

## Implementation Plan

### Tasks

#### Phase 1: Entitlements Restoration & Read-Only Mode (Recommended First)

- [ ] **Task 1: Restore Keychain Entitlements**
  - File: `cc-hdrm/cc_hdrm.entitlements`
  - Action: Replace empty `<dict/>` with proper keychain access entitlement
  - Content:
    ```xml
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>keychain-access-groups</key>
        <array>
            <string>$(AppIdentifierPrefix)com.cc-hdrm.app</string>
        </array>
    </dict>
    </plist>
    ```
  - Notes: This establishes stable app identity for ACL persistence. User must grant access once after this change.

- [ ] **Task 2: Remove Keychain Write from Token Refresh Flow**
  - File: `cc-hdrm/Services/PollingEngine.swift:86-122`
  - Action: Modify `attemptTokenRefresh()` to NOT write credentials back to keychain
  - Change: Remove the `keychainService.writeCredentials(mergedCredentials)` call
  - Rationale: Avoids ACL conflicts with Claude Code. Let Claude Code handle all keychain writes.
  - Notes: Keep the token refresh network call for now — if it succeeds, just update in-memory state; if it fails, show "Run Claude Code to refresh"

- [ ] **Task 3: Update Token Refresh to Memory-Only**
  - File: `cc-hdrm/Services/PollingEngine.swift:86-122`
  - Action: On successful token refresh, update AppState with new token but don't persist
  - Change: After `tokenRefreshService.refreshToken()` succeeds, use the new token for subsequent API calls in the current session only
  - Notes: Token will be re-read from keychain on next app launch or poll cycle

- [ ] **Task 4: Clean Up Old Keychain ACL Entries (Manual Step)**
  - File: N/A (user action)
  - Action: Document manual cleanup step for user
  - Instructions:
    1. Open Keychain Access.app
    2. Find "Claude Code-credentials"
    3. Remove duplicate cc-hdrm.app entries
    4. Rebuild and launch cc-hdrm
    5. Grant access once — should persist now

#### Phase 2: Fix Token Refresh Format (Research Complete — Ready for Implementation)

- [x] **Task 5: Investigate Claude Code Token Refresh Format** ✅ COMPLETED
  - File: N/A (research)
  - **Findings from OpenCode GitHub Issues #9111, #9121, PR #9122:**
    - **Correct Endpoint:** `https://console.anthropic.com/v1/oauth/token` (NOT `platform.claude.com`)
    - **Required Fields:** `grant_type=refresh_token&refresh_token=<token>&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e`
    - **Content-Type:** `application/x-www-form-urlencoded` (cc-hdrm already does this correctly)
    - **Important:** Refresh tokens have a limited lifetime. After extended inactivity, the refresh token itself becomes invalid (returns 400). This is expected behavior, not a format error.
    - **Polling `/api/oauth/usage` does NOT extend token lifetime** — it only returns stats.

- [ ] **Task 6: Update TokenRefreshService Request Format**
  - File: `cc-hdrm/Services/TokenRefreshService.swift:29-41`
  - Action: Modify request to use correct endpoint and include `client_id`
  - **Current (broken):**
    - Endpoint: `https://platform.claude.com/v1/oauth/token`
    - Body: `grant_type=refresh_token&refresh_token=<token>`
  - **Correct format:**
    - Endpoint: `https://console.anthropic.com/v1/oauth/token`
    - Body: `grant_type=refresh_token&refresh_token=<token>&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e`
  - Notes: The `client_id` is Anthropic's public OAuth client ID used by Claude Code and OpenCode

- [ ] **Task 7: Update TokenRefreshService Tests**
  - File: `cc-hdrmTests/Services/TokenRefreshServiceTests.swift`
  - Action: Update mock expectations to verify:
    1. Request URL is `https://console.anthropic.com/v1/oauth/token`
    2. Request body includes `client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e`
  - Notes: Add test for expired refresh token scenario (400 response with specific error message)

- [ ] **Task 8: Re-enable Keychain Write (if refresh works)**
  - File: `cc-hdrm/Services/PollingEngine.swift`
  - Action: Restore `keychainService.writeCredentials()` call after successful refresh
  - Notes: Only do this if Phase 2 succeeds AND user accepts ACL prompt trade-off

### Acceptance Criteria

#### Entitlements & Identity (Phase 1)

- [ ] **AC1:** Given cc-hdrm is rebuilt with restored entitlements, when the user grants keychain access and clicks "Always Allow", then subsequent app rebuilds do NOT trigger new keychain password prompts
- [ ] **AC2:** Given cc-hdrm is rebuilt with restored entitlements, when viewing Keychain Access Control for "Claude Code-credentials", then only ONE cc-hdrm.app entry appears (not multiple duplicates)
- [ ] **AC3:** Given keychain access is granted, when cc-hdrm reads credentials during a poll cycle, then no password prompt appears

#### Read-Only Keychain Mode (Phase 1)

- [ ] **AC4:** Given token is expired, when cc-hdrm detects expiry, then it displays "Token expired — Run any Claude Code command to refresh" status message
- [ ] **AC5:** Given token is expired, when cc-hdrm attempts refresh, then it does NOT write to the keychain (no ACL complications)
- [ ] **AC6:** Given Claude Code refreshes the token externally, when cc-hdrm's next poll cycle reads the keychain, then cc-hdrm uses the new token without prompts

#### Token Refresh Format (Phase 2)

- [ ] **AC7:** Given valid refresh token, when TokenRefreshService sends refresh request to `https://console.anthropic.com/v1/oauth/token`, then the server returns HTTP 200 (not 400)
- [ ] **AC8:** Given successful token refresh, when credentials are written to keychain, then subsequent reads succeed without password prompts
- [ ] **AC9:** Given token refresh request, when inspecting the HTTP body, then it includes: `grant_type=refresh_token`, `refresh_token=<token>`, and `client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e`
- [ ] **AC10:** Given expired refresh token (user inactive too long), when TokenRefreshService sends refresh request, then cc-hdrm displays "Session expired — Run `claude` to re-authenticate" (not a generic error)

## Additional Context

### Dependencies

- None (zero external dependencies policy)

### Testing Strategy

**Framework:** Swift Testing (`@Suite`, `@Test`, `#expect`)

**Token Refresh Tests (`TokenRefreshServiceTests.swift`):**
- Existing tests mock the network layer via injectable `dataLoader` closure
- Tests verify: successful refresh, missing refresh token handling, network failure, non-200 status, invalid response body, missing access_token
- If request format changes, update the mock expectations to verify correct body format

**Keychain Tests (`KeychainServiceTests.swift`):**
- Tests use injectable `dataProvider` and `writeProvider` closures
- Tests verify: valid JSON parsing, missing credentials, access denied, malformed JSON, write operations
- No changes expected unless we modify keychain access approach

**Integration Testing:**
- Manual testing required for real keychain/network interactions
- Test entitlements fix by rebuilding app, granting keychain access once, verifying no re-prompt after subsequent rebuilds

### Notes

**High-Risk Items:**
- Keychain ACL behavior may vary across macOS versions — test on user's actual system (macOS 15.x Sequoia)
- Claude Code's delete/recreate behavior means ACL resets will still occur when Claude Code refreshes tokens — this is upstream and unfixable from cc-hdrm
- Token refresh format is reverse-engineered — may break if Claude/Anthropic changes their OAuth implementation

**Known Limitations:**
- Phase 1 solution requires user to run Claude Code when tokens expire (not fully autonomous)
- Even with fixed entitlements, keychain prompts may recur when Claude Code refreshes tokens (upstream issue)
- User sees two cc-hdrm.app entries in Keychain Access Control — indicates identity instability from empty entitlements; needs manual cleanup

**Future Considerations (Out of Scope):**
- Monitor GitHub #22144 for upstream solutions (usage cache file, token export command)
- If Claude Code exposes `~/.claude/usage-cache.json`, cc-hdrm could read that instead of keychain
- The QUIC parse error in logs (`quic_conn_process_inbound... unable to parse packet`) is likely unrelated network noise

### Critical Research Findings (GitHub Issues)

**Issue #22144** — [Reduce keychain prompt friction for third-party tools](https://github.com/anthropics/claude-code/issues/22144)

This is the EXACT problem cc-hdrm faces. Key insight:

> When Claude Code refreshes tokens, it **deletes and recreates the keychain item**, which **resets the ACL**. Third-party apps lose access and get prompted again.

This means:
1. Fixing entitlements helps with stable app identity, but won't fully solve ACL resets
2. cc-hdrm writing to keychain (during token refresh) further complicates ACL management
3. The community is requesting Claude Code expose a usage cache file or token export command

**Proposed upstream solutions (from #22144):**
- Option A: Usage data cache file (`~/.claude/usage-cache.json`) — third-party tools read cache instead of needing credentials
- Option B: Token export command (`claude auth token`) — CLI outputs token, apps invoke CLI
- Option C: Credentials file on macOS (like Linux) — `~/.claude/.credentials.json`

**Issue #19456** — [OAuth token refresh fails due to Keychain permission errors](https://github.com/anthropics/claude-code/issues/19456)

Documents that even Claude Code itself has keychain permission issues during token refresh after updates.

**Implications for cc-hdrm:**
1. **Token refresh 400 error** — ✅ **SOLVED:** Missing `client_id` AND wrong endpoint URL. Correct format discovered from OpenCode PR #9122.
2. **Keychain prompts** — Fundamentally caused by Claude Code's delete/recreate behavior, not just cc-hdrm's entitlements. But entitlements still need fixing for stable identity.
3. **Design consideration** — cc-hdrm can now attempt token refresh autonomously with the correct format. Falls back to "Run Claude Code to re-authenticate" only when the refresh token itself has expired.

### Token Refresh Format (Discovered)

**Source:** OpenCode GitHub Issues #9111, #9121, PR #9122

| Field | Current (Broken) | Correct |
|-------|------------------|---------|
| Endpoint | `https://platform.claude.com/v1/oauth/token` | `https://console.anthropic.com/v1/oauth/token` |
| grant_type | `refresh_token` | `refresh_token` |
| refresh_token | `<token>` | `<token>` |
| client_id | **MISSING** | `9d1c250a-e61b-44d9-88ed-5944d1962f5e` |
| Content-Type | `application/x-www-form-urlencoded` | `application/x-www-form-urlencoded` ✅ |

**Note:** The `client_id` is Anthropic's public OAuth client identifier, used by both Claude Code and OpenCode. It is not a secret.
