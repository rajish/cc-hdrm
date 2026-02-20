# Story 18.2: OAuth Profile Fetch for Tier Resolution

Status: done

## Story

As a cc-hdrm user who authenticates via the independent OAuth flow,
I want the app to fetch my subscription tier from the Anthropic profile API,
so that the "X full 5h quotas left" display, credit-math 7d promotion, slope normalization, and tier-dependent analytics all work correctly without requiring manual custom credit limit configuration.

## Acceptance Criteria

1. **Given** the user completes OAuth sign-in, **when** tokens are obtained, **then** the app immediately calls `GET https://api.anthropic.com/api/oauth/profile` with the new access token, extracts `organization.rate_limit_tier` and `organization.organization_type`, and stores them as `rateLimitTier` and `subscriptionType` in the Keychain credentials before the first poll cycle begins.

2. **Given** a token refresh succeeds, **when** rotated tokens are persisted, **then** the app also re-fetches the profile to capture any subscription tier changes (e.g., Pro → Max upgrade) and updates the stored credentials accordingly.

3. **Given** an existing user who authenticated before this story (credentials in Keychain with `rateLimitTier: nil`), **when** the first poll cycle runs, **then** the app detects the missing tier, fetches the profile to backfill it, and updates the Keychain credentials — no re-authentication required.

4. **Given** the profile API is unreachable or returns an error, **when** tier resolution fails, **then** the app continues operating normally (profile fetch failure is non-fatal) — credit limits fall back to user-configured custom limits or nil (existing graceful degradation), and the profile fetch is retried on the next token refresh or poll cycle where tier is still nil.

5. **Given** the profile response contains `organization.rate_limit_tier` with a value like `"default_claude_pro"`, **when** stored in Keychain credentials, **then** the existing `RateLimitTier.resolve()` pipeline resolves credit limits correctly, enabling the "X full 5h quotas left" display, credit-math 7d promotion, slope normalization, and all tier-dependent features.

6. **Given** the profile fetch succeeds, **when** `subscriptionType` is extracted from `organization.organization_type`, **then** it is mapped to a display-friendly value (`"claude_pro"` → `"pro"`, `"claude_max"` → `"max"`) and stored in the credentials, making it available for `AppState.subscriptionTier` and analytics display.

## Tasks / Subtasks

- [x] **Task 1: ProfileResponse Model** (AC: 1, 5, 6)
  - [x] Create `cc-hdrm/Models/ProfileResponse.swift`
  - [x] Define `ProfileResponse` with nested `Organization` struct
  - [x] Parse `organization.rate_limit_tier` (String?) and `organization.organization_type` (String?)
  - [x] Use `CodingKeys` for `snake_case` → `camelCase` mapping (consistent with `UsageResponse` pattern)
  - [x] Add `subscriptionTypeDisplay` computed property to map `organization_type` values: `"claude_pro"` → `"pro"`, `"claude_max"` → `"max"`, `"claude_enterprise"` → `"enterprise"`, `"claude_team"` → `"team"`, anything else → nil
  - [x] All fields optional — defensive parsing per project conventions

- [x] **Task 2: APIClient.fetchProfile** (AC: 1, 4)
  - [x] Add `fetchProfile(token: String) async throws -> ProfileResponse` to `cc-hdrm/Services/APIClient.swift`
  - [x] Endpoint: `GET https://api.anthropic.com/api/oauth/profile`
  - [x] Headers: same as `fetchUsage` — `Authorization: Bearer {token}`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: cc-hdrm/{version}`
  - [x] Add `static let profileEndpoint` alongside existing `usageEndpoint`
  - [x] Log at info level: "Fetching profile data", "Profile API responded with status {code}", "Profile data parsed successfully"
  - [x] Error handling: throw `AppError.apiError` on non-200, `AppError.parseError` on decode failure (reuse existing error cases)

- [x] **Task 3: APIClientProtocol Update** (AC: 1)
  - [x] Add `func fetchProfile(token: String) async throws -> ProfileResponse` to `cc-hdrm/Services/APIClientProtocol.swift`

- [x] **Task 4: AppDelegate Sign-In Integration** (AC: 1)
  - [x] In `cc-hdrm/App/AppDelegate.swift` `performSignIn()`: after `oauthService.authorize()` returns credentials, call `apiClient.fetchProfile(token: credentials.accessToken)`
  - [x] On success: create enriched credentials with `rateLimitTier` and `subscriptionType` from profile before storing to Keychain
  - [x] On failure: log warning, store credentials without tier (non-fatal — profile will be retried on next refresh or poll)
  - [x] Inject `APIClient` (or `APIClientProtocol`) into AppDelegate scope (it already has `pollingEngine` which owns `apiClient` — either expose it or create a shared instance)

- [x] **Task 5: PollingEngine Token Refresh Integration** (AC: 2)
  - [x] In `cc-hdrm/Services/PollingEngine.swift` `attemptTokenRefresh()`: after successful refresh and credential merge, fetch profile with the new access token
  - [x] On success: update `rateLimitTier` and `subscriptionType` in the merged credentials before writing to Keychain
  - [x] On failure: log warning, proceed with existing tier from original credentials (non-fatal)
  - [x] This catches subscription tier changes within ~1 hour (token refresh interval)

- [x] **Task 6: Migration Backfill for Existing Users** (AC: 3)
  - [x] In `cc-hdrm/Services/PollingEngine.swift` `performPollCycle()` or `fetchUsageData()`: after reading credentials from Keychain, if `credentials.rateLimitTier` is nil AND custom credit limits are not configured, fetch profile once to backfill
  - [x] On success: update Keychain credentials with tier, use fetched tier for credit limit resolution in this cycle
  - [x] On failure: continue with nil tier (existing graceful degradation — quotas hidden)
  - [x] Guard against repeated fetch attempts on every cycle: once backfilled, the tier persists in Keychain; if profile fetch fails, don't retry until next token refresh

- [x] **Task 7: Remove Debug Logging** (AC: N/A — cleanup)
  - [x] Remove the temporary raw JSON debug log added to `cc-hdrm/Services/APIClient.swift` during investigation (the `Self.logger.debug("Raw usage response: ...")` line) — already absent from current source

- [x] **Task 8: Tests** (AC: 1-6)
  - [x] Unit tests for `ProfileResponse` parsing: full response, missing organization, missing fields, unknown organization_type
  - [x] Unit tests for `subscriptionTypeDisplay` mapping: claude_pro → pro, claude_max → max, claude_enterprise → enterprise, claude_team → team, unknown → nil
  - [x] Unit tests for `APIClient.fetchProfile`: success, non-200 status, parse error, network error
  - [x] Update `MockAPIClient` (or equivalent test double) to include `fetchProfile` stub
  - [x] Unit tests for PollingEngine: verify profile is fetched after token refresh, verify tier backfill on nil rateLimitTier
  - [x] Unit tests for AppDelegate: profile fetch integration verified via PollingEngine tests (AppDelegate delegates to enrichCredentialsWithProfile which follows same pattern)
  - [x] Update existing `PollingEngineTests` that inject mock credentials — PEMockAPIClient updated with fetchProfile support

## Dev Notes

### The Problem

Story 18.1 introduced independent OAuth authentication, replacing the passive read of Claude Code's Keychain credentials. Claude Code's credentials included `rateLimitTier` (e.g., `"default_claude_pro"`) because Claude Code calls the profile API after auth and stores the result. The independent OAuth flow doesn't fetch the profile, so `rateLimitTier` is always `nil` in cc-hdrm's credentials. This causes `RateLimitTier.resolve()` to return nil, `creditLimits` to be nil, and `quotasRemaining` to be nil — hiding the "X full 5h quotas left" display and breaking credit-math features.

### The Fix

Mirror Claude Code's behavior: call `GET /api/oauth/profile` after token exchange and after each token refresh. The profile response includes `organization.rate_limit_tier` which maps directly to the existing `RateLimitTier` enum raw values (`"default_claude_pro"`, `"default_claude_max_5x"`, `"default_claude_max_20x"`).

### Profile API Response Structure

Based on research of Claude Code's source (anthropics/claude-code on GitHub):

```json
{
  "account": {
    "uuid": "...",
    "email_address": "...",
    "display_name": "..."
  },
  "organization": {
    "uuid": "...",
    "organization_type": "claude_max",
    "rate_limit_tier": "default_claude_max_20x",
    "has_extra_usage_enabled": true,
    "billing_type": "...",
    "subscription_created_at": "..."
  }
}
```

Only `organization.rate_limit_tier` and `organization.organization_type` are needed. All other fields should be parsed defensively (optional) but can be ignored.

### Profile Fetch Timing

| Event | Profile Fetched? | Rationale |
|-------|-----------------|-----------|
| Initial OAuth sign-in | Yes | Tier available immediately for first poll |
| Token refresh (~hourly) | Yes | Catches subscription upgrades |
| Poll cycle (tier is nil) | Yes (once) | Migration backfill for existing users |
| Normal poll cycle (tier present) | No | Tier already in Keychain, no extra API call |

### Architectural Boundary

The profile endpoint is at `api.anthropic.com`, so `fetchProfile` belongs in `APIClient` per the architectural boundary table in `project-context.md` ("APIClient — only component that calls api.anthropic.com").

### Required Headers

Same as the usage endpoint (already set in `APIClient`):
- `Authorization: Bearer {access_token}`
- `anthropic-beta: oauth-2025-04-20`
- `User-Agent: cc-hdrm/{version}`

### OAuth Scope

The `user:profile` scope is already requested in the OAuth authorization URL (`OAuthService.swift:17`: `"org:create_api_key user:profile user:inference"`). No scope changes needed.

### Non-Fatal Design

Profile fetch failure must NEVER block polling or break the app. The entire profile fetch is optional enrichment — if it fails:
- Credit limits fall back to user-configured custom limits (existing `PreferencesManager` path in `RateLimitTier.resolve()`)
- If no custom limits, `creditLimits` is nil and quota display is hidden (existing graceful degradation)
- Retry happens naturally on next token refresh or next poll cycle with nil tier

### Existing Code Reuse

- `cc-hdrm/Services/APIClient.swift` — add `fetchProfile` alongside `fetchUsage` (same headers, same error handling pattern)
- `cc-hdrm/Services/APIClientProtocol.swift` — add protocol method
- `cc-hdrm/Models/RateLimitTier.swift` — `resolve()` already handles the tier string → credit limits mapping. No changes needed.
- `cc-hdrm/State/AppState.swift` — `updateCreditLimits()` and `updateSubscriptionTier()` already exist. No changes needed.
- `cc-hdrm/Views/SevenDayGaugeSection.swift` — quota display already works when `quotasRemaining` is non-nil. No changes needed.

### Files That Need Changes

| File | Change |
|------|--------|
| `cc-hdrm/Models/ProfileResponse.swift` | **New** — profile API response model |
| `cc-hdrm/Services/APIClient.swift` | Add `fetchProfile()`, remove debug log |
| `cc-hdrm/Services/APIClientProtocol.swift` | Add `fetchProfile` to protocol |
| `cc-hdrm/Services/PollingEngine.swift` | Fetch profile after refresh; backfill nil tier |
| `cc-hdrm/App/AppDelegate.swift` | Fetch profile after sign-in |
| `cc-hdrmTests/Models/ProfileResponseTests.swift` | **New** — profile parsing tests |
| `cc-hdrmTests/Services/APIClientTests.swift` | Add fetchProfile tests |
| `cc-hdrmTests/Services/PollingEngineTests.swift` | Update for profile fetch integration |

### What Does NOT Change

- `RateLimitTier.swift` — `resolve()` already handles tier strings correctly
- `KeychainCredentials.swift` — already has `rateLimitTier` and `subscriptionType` fields
- `OAuthService.swift` — auth flow stays focused on token exchange (profile fetch is called by the caller after)
- `TokenRefreshService.swift` — refresh stays focused on token rotation (profile fetch is called by PollingEngine after)
- `SevenDayGaugeSection.swift` — quota display already reactive on `quotasRemaining`
- `AppState.swift` — `quotasRemaining`, `creditLimits`, `subscriptionTier` already wired

### Project Structure Notes

- New `ProfileResponse.swift` goes in `cc-hdrm/Models/` (consistent with `UsageResponse.swift`)
- New test file `ProfileResponseTests.swift` goes in `cc-hdrmTests/Models/`
- Run `xcodegen generate` after adding new Swift files
- All file paths are project-relative

### References

- [Source: cc-hdrm/Services/APIClient.swift:11] Existing usage endpoint and fetch pattern to mirror
- [Source: cc-hdrm/Services/APIClientProtocol.swift:9] Protocol to extend
- [Source: cc-hdrm/Models/UsageResponse.swift] Model pattern to follow for ProfileResponse
- [Source: cc-hdrm/Models/RateLimitTier.swift:5-9] Known tier raw values: `default_claude_pro`, `default_claude_max_5x`, `default_claude_max_20x`
- [Source: cc-hdrm/Models/RateLimitTier.swift:61-82] `resolve()` method — already handles tier string → CreditLimits
- [Source: cc-hdrm/Services/PollingEngine.swift:157-162] Where credit limits are resolved from tier string
- [Source: cc-hdrm/Services/PollingEngine.swift:98-138] Token refresh flow where profile should be fetched
- [Source: cc-hdrm/Services/OAuthService.swift:17] Scope already includes `user:profile`
- [Source: cc-hdrm/Services/OAuthService.swift:229-236] Where credentials are returned with nil tier
- [Source: cc-hdrm/Models/KeychainCredentials.swift:10] `rateLimitTier` field already exists
- [Source: cc-hdrm/State/AppState.swift:105-113] `quotasRemaining` computed property that depends on `creditLimits`
- [Source: cc-hdrm/Views/SevenDayGaugeSection.swift:62-66] Quota display conditional on `quotasRemaining`
- [Source: GitHub anthropics/claude-code] Claude Code's profile fetch flow (reverse-engineered)
- [Source: Previous conversation] Raw usage API response confirming tier is NOT in usage endpoint

## Dev Agent Record

### Agent Model Used
Claude Opus 4.6

### Debug Log References
N/A — no debug logging issues encountered.

### Completion Notes List
- Task 1: Created `ProfileResponse` model with nested `Organization` struct, `CodingKeys` for snake_case mapping, and `subscriptionTypeDisplay` computed property. 11 unit tests (6 parsing + 5 mapping).
- Task 2: Added `fetchProfile(token:)` to `APIClient` alongside `fetchUsage`. Same headers, timeout, error handling pattern. Added `profileEndpoint` static constant.
- Task 3: Extended `APIClientProtocol` with `fetchProfile` method signature.
- Task 4: Added `apiClient` property to `AppDelegate`. Created `enrichCredentialsWithProfile()` helper. Updated `performSignIn()` to enrich credentials with profile data before writing to Keychain. Profile failure is non-fatal.
- Task 5: Updated `attemptTokenRefresh()` to fetch profile after successful refresh, updating tier and subscription type in merged credentials before Keychain write. Catches subscription upgrades within ~1 hour.
- Task 6: Added `backfillTierFromProfile()` to `PollingEngine`. Called from `fetchUsageData()` when `rateLimitTier` is nil and no custom limits configured. Persists backfilled tier to Keychain and updates AppState subscription tier.
- Task 7: Debug log line already absent from current source — no action needed.
- Task 8: Comprehensive tests: ProfileResponse parsing (11 tests), APIClient fetchProfile (5 tests), PollingEngine profile integration (7 tests). Updated `PEMockAPIClient` with `fetchProfile` support.

### File List
**New files:**
- `cc-hdrm/Models/ProfileResponse.swift`
- `cc-hdrmTests/Models/ProfileResponseTests.swift`

**Modified files:**
- `cc-hdrm/Models/KeychainCredentials.swift` — added `applying(_:)` profile merge helper
- `cc-hdrm/Services/APIClient.swift` — added `profileEndpoint`, `fetchProfile()`, extracted generic `fetch<T>()` helper
- `cc-hdrm/Services/APIClientProtocol.swift` — added `fetchProfile` to protocol
- `cc-hdrm/App/AppDelegate.swift` — added `apiClient` property, `enrichCredentialsWithProfile()`, updated `performSignIn()`
- `cc-hdrm/Services/PollingEngine.swift` — profile fetch in `attemptTokenRefresh()`, backfill in `fetchUsageData()`, added `backfillTierFromProfile()`, `hasAttemptedProfileBackfill` guard
- `cc-hdrmTests/Services/APIClientTests.swift` — added `APIClientFetchProfileTests` suite, deduplicated `RequestCapture`
- `cc-hdrmTests/Services/PollingEngineTests.swift` — updated `PEMockAPIClient` with `fetchProfile` token tracking, added `PollingEngineProfileFetchTests` suite (7 tests)

### Change Log
- **Code Review (2026-02-20):** Fixed 5 issues (3 MEDIUM, 2 LOW):
  - M1: Added `hasAttemptedProfileBackfill` guard to prevent repeated API calls when profile has no tier; resets on token refresh
  - M2: Extracted generic `fetch<T>(endpoint:label:token:)` helper in APIClient, eliminating ~30 lines of duplicated boilerplate
  - M3: Added token tracking to `PEMockAPIClient.fetchProfile()` and assertion verifying refreshed token is used
  - L1: Added profile parameters to `PEMockAPIClient(results:)` initializer
  - L2: Noted — AppDelegate.enrichCredentialsWithProfile untested directly (covered by PollingEngine pattern tests; full AppDelegate testability is a larger refactor)
  - 2 new tests added: backfill-not-retried, backfill-guard-resets-after-refresh (1233→1235 total)
- **CodeRabbit Fixes (2026-02-20):** Addressed 3 valid findings (2 false positives dismissed):
  - Moved `hasAttemptedProfileBackfill` flag to after success paths — Keychain write failure no longer suppresses retry
  - Extracted `KeychainCredentials.applying(_:)` helper to eliminate profile-merge triplication across AppDelegate, PollingEngine.attemptTokenRefresh, and PollingEngine.backfillTierFromProfile
  - Deduplicated `RequestCapture` in APIClientTests to single `fileprivate` file-scope type
  - Dismissed: Info.plist version bump (automated by workflow, not manual) and xcodeproj file registration (XcodeGen project, xcodeproj gitignored)
