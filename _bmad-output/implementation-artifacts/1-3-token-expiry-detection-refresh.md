# Story 1.3: Token Expiry Detection & Refresh

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want the app to detect expired tokens and attempt refresh automatically,
so that I maintain continuous usage visibility without manual intervention.

## Acceptance Criteria

1. **Given** credentials exist with an `expiresAt` timestamp in the past, **When** the app reads credentials during a poll cycle, **Then** the app attempts token refresh via POST to `https://platform.claude.com/v1/oauth/token`.
2. **And** if refresh succeeds, the new access token is written back to the Keychain.
3. **And** normal operation resumes — the user never knows it happened.
4. **Given** token refresh fails (network error, invalid refresh token, etc.), **When** the refresh attempt completes, **Then** the menu bar shows "✳ —" in grey.
5. **And** a status is set: "Token expired" / "Run any Claude Code command to refresh".
6. **And** the error is logged via `os.Logger` (token category).
7. **And** the app continues polling the Keychain every 30 seconds for externally refreshed credentials.
8. **Given** credentials exist with `expiresAt` approaching (within 5 minutes), **When** the app reads credentials during a poll cycle, **Then** the app pre-emptively attempts token refresh before expiry.

## Tasks / Subtasks

- [x] Task 1: Create `TokenRefreshServiceProtocol` and `TokenRefreshService` (AC: #1, #2, #3)
  - [x] Create `Services/TokenRefreshServiceProtocol.swift`
  - [x] Define protocol with `func refreshToken(using refreshToken: String) async throws -> KeychainCredentials`
  - [x] Create `Services/TokenRefreshService.swift`
  - [x] Implement POST to `https://platform.claude.com/v1/oauth/token` with `grant_type=refresh_token` and `refresh_token=<token>`
  - [x] Parse response as JSON — extract new `accessToken`, `expiresAt`, and optionally new `refreshToken`
  - [x] Return updated `KeychainCredentials` on success
  - [x] Throw `AppError.tokenRefreshFailed(underlying:)` on any failure
  - [x] Log refresh attempts and outcomes via `os.Logger` (category: `token`)
  - [x] NEVER log token values, even at `.debug` level
- [x] Task 2: Add Keychain write capability to `KeychainService` (AC: #2)
  - [x] Add `func writeCredentials(_ credentials: KeychainCredentials) async throws` to `KeychainServiceProtocol`
  - [x] Implement in `KeychainService`: read existing Keychain item → update `claudeAiOauth` JSON → write back via `SecItemUpdate`
  - [x] If no existing item, use `SecItemAdd` to create it
  - [x] Log write success/failure via `os.Logger` (category: `keychain`)
  - [x] NEVER log credential values
- [x] Task 3: Add token expiry checking logic (AC: #1, #8)
  - [x] Create `Services/TokenExpiryChecker.swift` (or add to existing service)
  - [x] Define `func tokenStatus(for credentials: KeychainCredentials) -> TokenStatus`
  - [x] `TokenStatus` enum: `.valid`, `.expiringSoon` (within 5 minutes), `.expired`
  - [x] `expiresAt` is Unix milliseconds — divide by 1000 for `Date(timeIntervalSince1970:)`
  - [x] If `expiresAt` is nil, treat as `.valid` (unknown expiry = optimistically try API)
- [x] Task 4: Integrate token refresh into AppDelegate polling loop (AC: #1, #3, #4, #5, #6, #7, #8)
  - [x] Modify `AppDelegate.performCredentialRead()` to check token status after reading credentials
  - [x] If `.expired` or `.expiringSoon`: attempt `TokenRefreshService.refreshToken()`
  - [x] On refresh success: write new credentials to Keychain via `KeychainService.writeCredentials()`, update `AppState` to `.connected`, clear status message
  - [x] On refresh failure: set `AppState.connectionStatus` to `.tokenExpired`, set status message ("Token expired" / "Run any Claude Code command to refresh"), log error
  - [x] On `.tokenExpired` status: continue polling Keychain every 30s (existing loop handles this)
  - [x] Ensure `refreshToken` from credentials is available; if nil, skip refresh and go straight to expired status message
- [x] Task 5: Write tests (AC: all)
  - [x] Create `cc-hdrmTests/Services/TokenRefreshServiceTests.swift`
  - [x] Test: successful refresh returns updated credentials
  - [x] Test: network failure throws `AppError.tokenRefreshFailed`
  - [x] Test: invalid response body throws `AppError.tokenRefreshFailed`
  - [x] Create `cc-hdrmTests/Services/TokenExpiryCheckerTests.swift`
  - [x] Test: future `expiresAt` → `.valid`
  - [x] Test: `expiresAt` within 5 minutes → `.expiringSoon`
  - [x] Test: past `expiresAt` → `.expired`
  - [x] Test: nil `expiresAt` → `.valid`
  - [x] Test: `expiresAt` at Unix milliseconds precision (large numbers)
  - [x] Add Keychain write tests to existing `KeychainServiceTests.swift`
  - [x] Test: write credentials updates existing Keychain item
  - [x] Add integration flow tests to `AppStateTests.swift` or new `AppDelegateTests.swift`
  - [x] Test: expired token → refresh succeeds → connectionStatus is `.connected`
  - [x] Test: expired token → refresh fails → connectionStatus is `.tokenExpired`, statusMessage set

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. This story adds `TokenRefreshService` behind a protocol interface, and extends `KeychainService` with write capability.
- **Concurrency:** `TokenRefreshService` uses `async throws` with `URLSession.data(for:)`. No GCD/DispatchQueue.
- **State management:** On refresh outcome, update `AppState` via methods (`updateConnectionStatus()`, `updateStatusMessage()`). Never mutate properties directly from services.
- **Security (NFR6):** Refreshed credentials written back to Keychain only — never to disk, logs, or UserDefaults.
- **Security (NFR7):** Each poll cycle reads fresh credentials from Keychain, checks expiry, refreshes if needed. No token caching between cycles.
- **Security (NFR8):** Token refresh POST goes only to `platform.claude.com`. No other endpoint receives credentials.
- **Security (NFR9):** HTTPS exclusively for the refresh request.
- **Logging:** `os.Logger` with subsystem `com.cc-hdrm.app`, category `token`. Log refresh attempts, success/failure, but NEVER log token values.
- **Testing:** Swift Testing framework. Protocol-based `TokenRefreshServiceProtocol` enables mocking.

### Token Refresh Endpoint Details

**Endpoint:** `POST https://platform.claude.com/v1/oauth/token`

**Request format:** Standard OAuth2 `refresh_token` grant:
```
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token&refresh_token=<refresh_token_value>
```

**Expected response (success):**
```json
{
  "access_token": "new-oauth-token-string",
  "refresh_token": "new-or-same-refresh-token",
  "expires_in": 3600,
  "token_type": "Bearer"
}
```

**Note:** The exact request/response format for Claude's OAuth token refresh has not been verified against live documentation. The implementation should:
1. Start with standard OAuth2 `refresh_token` grant format above
2. If the endpoint returns an error indicating missing fields (e.g., `client_id`), add them based on the error response
3. Log the full error response (minus token values) to aid debugging
4. On any unrecoverable failure, fall back to the "Run any Claude Code command to refresh" message

**Mapping refreshed tokens back to Keychain:**
- The response `access_token` maps to `KeychainCredentials.accessToken`
- The response `refresh_token` (if present) replaces `KeychainCredentials.refreshToken`
- The response `expires_in` (seconds) should be converted: `Date().timeIntervalSince1970 + expires_in` then `* 1000` to store as Unix milliseconds in `expiresAt`
- Other fields (`subscriptionType`, `rateLimitTier`, `scopes`) are preserved from the existing Keychain entry

### Token Expiry Logic

**`expiresAt` format:** Unix timestamp in **milliseconds** (not seconds). Convert: `Date(timeIntervalSince1970: expiresAt / 1000.0)`

**Decision tree per poll cycle:**
```
Read credentials from Keychain
  → Success:
      Check expiresAt:
        → nil: treat as valid, proceed to API fetch (Story 2.x)
        → future (>5 min): valid, proceed
        → future (≤5 min): expiringSoon → attempt pre-emptive refresh
        → past: expired → attempt refresh
      
      If refresh needed:
        → refreshToken available:
            Attempt POST to platform.claude.com
              → Success: write new creds to Keychain, proceed as connected
              → Failure: set .tokenExpired status, show message, continue polling
        → refreshToken nil:
            Set .tokenExpired status, show message, continue polling
  
  → Failure (keychainNotFound, etc.):
      Existing error handling (Story 1.2)
```

### Keychain Write Details

**Updating existing Keychain item:**
```swift
// 1. Read existing Keychain data to preserve outer JSON structure
// 2. Update claudeAiOauth fields with refreshed values
// 3. Write back via SecItemUpdate

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "Claude Code-credentials"
]

let updatedJSON = // serialize updated outer JSON with new claudeAiOauth
let attributes: [String: Any] = [
    kSecValueData as String: updatedJSON
]

let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
```

**Important:** Preserve the full outer JSON structure. Only update fields inside `claudeAiOauth` that changed from the refresh response. Keep `subscriptionType`, `rateLimitTier`, `scopes` from the original entry.

### Previous Story Intelligence (1.2)

**What was built:**
- `KeychainCredentials` Codable+Sendable struct with `accessToken` (required), `refreshToken`, `expiresAt` (Double?), `subscriptionType`, `rateLimitTier`, `scopes` (all optional)
- `KeychainServiceProtocol` with `readCredentials() async throws -> KeychainCredentials`
- `KeychainService` with `SecItemCopyMatching`, JSON parsing of outer `claudeAiOauth` wrapper, testable via `dataProvider` injection
- `AppDelegate` polling loop: reads credentials every 30s, updates AppState
- `AppState.statusMessage` with `StatusMessage(title:detail:)` struct
- `ConnectionStatus` enum: `.connected`, `.disconnected`, `.tokenExpired`, `.noCredentials`
- 43 tests passing

**Code review fixes from 1.2:**
- H1: Entitlements restored with keychain-access-groups
- H2: `dataProvider` changed to `KeychainResult` enum for OSStatus differentiation
- M1: `statusMessage` converted to `Equatable` struct
- Tests use `@MainActor` for anything touching `AppState`

**Patterns established:**
- `os.Logger` with subsystem `com.cc-hdrm.app` and per-component category
- `private(set)` with public mutation methods on AppState
- Swift Testing with `@Suite`, `@Test`, `#expect`
- `KeychainService` uses `@unchecked Sendable` since `dataProvider` closure is immutable after init
- XcodeGen (`project.yml`) with directory-based source discovery — new files in correct folders are automatically included

### Git Intelligence

**Last 2 commits:**
- `5b46e49` Add story 1.2: Keychain credential discovery with code review fixes
- `c2a74e4` Add story 1.1 implementation: Xcode project initialization & menu bar shell

**Key files to modify:**
- `cc-hdrm/App/AppDelegate.swift` — integrate token expiry check + refresh into polling loop
- `cc-hdrm/Services/KeychainServiceProtocol.swift` — add `writeCredentials` method
- `cc-hdrm/Services/KeychainService.swift` — implement `writeCredentials`

**Key files to create:**
- `cc-hdrm/Services/TokenRefreshServiceProtocol.swift`
- `cc-hdrm/Services/TokenRefreshService.swift`
- `cc-hdrm/Services/TokenExpiryChecker.swift`
- `cc-hdrmTests/Services/TokenRefreshServiceTests.swift`
- `cc-hdrmTests/Services/TokenExpiryCheckerTests.swift`

### File Structure Requirements

New files to create:
```
cc-hdrm/Services/TokenRefreshServiceProtocol.swift
cc-hdrm/Services/TokenRefreshService.swift
cc-hdrm/Services/TokenExpiryChecker.swift
cc-hdrmTests/Services/TokenRefreshServiceTests.swift
cc-hdrmTests/Services/TokenExpiryCheckerTests.swift
```

Files to modify:
```
cc-hdrm/App/AppDelegate.swift               # Add token expiry check + refresh to polling
cc-hdrm/Services/KeychainServiceProtocol.swift  # Add writeCredentials method
cc-hdrm/Services/KeychainService.swift          # Implement writeCredentials
cc-hdrmTests/Services/KeychainServiceTests.swift # Add write tests
cc-hdrmTests/State/AppStateTests.swift           # Add tokenExpired status tests
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **Mocking strategy:**
  - Create `MockTokenRefreshService` conforming to `TokenRefreshServiceProtocol` for testing AppDelegate integration
  - Extend existing `MockKeychainService` (or create one) with `writeCredentials` support
  - `TokenRefreshService` itself should be testable via injected `URLSession` or `URLProtocol` mock
- **`@MainActor`:** Required on any test that touches `AppState`
- **Edge cases to test:**
  - `expiresAt` is nil (treat as valid)
  - `refreshToken` is nil (skip refresh, go to expired message)
  - `expiresAt` exactly 5 minutes in the future (boundary)
  - `expiresAt` at 0 (epoch — clearly expired)
  - Refresh returns new `refreshToken` vs. omits it (keep old)

### Anti-Patterns to Avoid

- DO NOT cache tokens between poll cycles — read fresh from Keychain each time (NFR7)
- DO NOT log access tokens, refresh tokens, or any credential data — even at `.debug` level
- DO NOT use `DispatchQueue` — use `async/await` with structured concurrency
- DO NOT send credentials to any endpoint other than `platform.claude.com` (NFR8)
- DO NOT skip the refresh attempt and go straight to error — always try if `refreshToken` is available
- DO NOT modify `KeychainCredentials` to be mutable — create a new instance with updated values
- DO NOT block the polling loop waiting for user interaction — refresh is fully automatic
- DO NOT hard-code the 5-minute pre-emptive window — define as a constant (`let preEmptiveRefreshThreshold: TimeInterval = 300`)

### Project Structure Notes

- Alignment with architecture: New files go in `Services/` per layer-based structure
- `project.yml` uses directory-based source discovery — files in correct folders are auto-included by XcodeGen
- Test files mirror source: `Services/TokenRefreshServiceTests.swift`, `Services/TokenExpiryCheckerTests.swift`
- `TokenExpiryChecker` is a pure function / value type — can be a struct with a static method or an enum with no cases

### References

- [Source: architecture.md#API Integration] — Token refresh endpoint, refresh strategy
- [Source: architecture.md#Keychain Integration] — Service name, read/write access pattern
- [Source: architecture.md#Error Handling Patterns] — AppError.tokenRefreshFailed, connectionStatus mapping
- [Source: architecture.md#Logging Patterns] — os.Logger token category, never log sensitive data
- [Source: architecture.md#Data Flow] — Poll cycle step 2: check expiresAt, TokenRefreshService.refresh()
- [Source: epics.md#Story 1.3] — Full acceptance criteria and BDD scenarios
- [Source: 1-2-keychain-credential-discovery.md] — Previous story patterns, KeychainService implementation, test patterns

## Dev Agent Record

### Agent Model Used

Claude Opus 4.5 (anthropic/claude-opus-4-5)

### Debug Log References

No debug issues encountered.

### Completion Notes List

- Task 1: Created `TokenRefreshServiceProtocol` and `TokenRefreshService` with injectable `dataLoader` for testability. POST to `platform.claude.com/v1/oauth/token` with standard OAuth2 refresh_token grant. Parses `access_token`, `refresh_token`, `expires_in` from response. Logs via `os.Logger` (category: token), never logs token values.
- Task 2: Extended `KeychainServiceProtocol` with `writeCredentials()`. Added `writeProvider` injection to `KeychainService` alongside existing `dataProvider`. Writes preserve outer JSON structure, merging updated `claudeAiOauth` fields. Falls back to `SecItemAdd` if no existing item.
- Task 3: Created `TokenExpiryChecker` as a no-case enum with static `tokenStatus(for:now:)`. Returns `.valid`, `.expiringSoon` (within 300s), or `.expired`. Handles nil `expiresAt` as `.valid`. Uses injectable `now` parameter for deterministic testing.
- Task 4: Integrated token expiry checking into `AppDelegate.performCredentialRead()`. On expired/expiringSoon: attempts refresh via `TokenRefreshService`, writes merged credentials back to Keychain preserving `subscriptionType`/`rateLimitTier`/`scopes`. On failure or nil `refreshToken`: sets `.tokenExpired` status with "Token expired" / "Run any Claude Code command to refresh" message. Polling continues every 30s regardless.
- Task 5: 67 total tests (24 new), all passing. TokenRefreshServiceTests (7 tests), TokenExpiryCheckerTests (7 tests), KeychainService write tests (4 tests), AppDelegate integration tests (4 tests) covering refresh success, refresh failure, nil refreshToken, and valid token scenarios.
- Additional: Added `Equatable` conformance to `AppError` to support `#expect(throws:)` in Swift Testing.

### Change Log

- 2026-01-31: Implemented Story 1.3 — Token Expiry Detection & Refresh. All 5 tasks completed, 67 tests passing (24 new).
- 2026-01-31: Code review fixes — H1: Restored keychain-access-groups entitlements (regression). H2: URL-encode refresh token in POST body. H3: Pass original error to tokenRefreshFailed instead of hardcoded URLError. M1: Removed dead writtenCredentials property. M2: Removed dead NSNull check in writeCredentials merge. M3: Added call counter to MockTokenRefreshService + assertion that refresh is not called when refreshToken is nil. 67 tests passing.

### File List

New files:
- cc-hdrm/Services/TokenRefreshServiceProtocol.swift
- cc-hdrm/Services/TokenRefreshService.swift
- cc-hdrm/Services/TokenExpiryChecker.swift
- cc-hdrmTests/Services/TokenRefreshServiceTests.swift
- cc-hdrmTests/Services/TokenExpiryCheckerTests.swift
- cc-hdrmTests/App/AppDelegateTests.swift

Modified files:
- cc-hdrm/App/AppDelegate.swift
- cc-hdrm/Services/KeychainServiceProtocol.swift
- cc-hdrm/Services/KeychainService.swift
- cc-hdrm/Services/TokenRefreshService.swift
- cc-hdrm/Models/AppError.swift
- cc-hdrm/cc_hdrm.entitlements
- cc-hdrmTests/Services/KeychainServiceTests.swift
