# Story 1.2: Keychain Credential Discovery

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want the app to automatically find my OAuth credentials in the macOS Keychain,
so that I never need to configure anything manually.

## Acceptance Criteria

1. **Given** Claude Code credentials exist in the Keychain (service: "Claude Code-credentials"), **When** the app launches, **Then** the app reads and parses the `claudeAiOauth` JSON object from the Keychain.
2. **And** the app extracts `accessToken`, `refreshToken`, `expiresAt`, `subscriptionType`, and `rateLimitTier`.
3. **And** the subscription tier is stored in AppState.
4. **And** credentials are never persisted to disk, logs, or UserDefaults (NFR6).
5. **And** all Keychain access goes through `KeychainServiceProtocol`.
6. **Given** no Claude Code credentials exist in the Keychain, **When** the app launches, **Then** the menu bar shows "✳ —" in grey.
7. **And** a StatusMessageView-compatible status is set: "No Claude credentials found" / "Run Claude Code to create them".
8. **And** the app polls the Keychain every 30 seconds for new credentials.
9. **And** when credentials appear, the app transitions to normal operation silently.
10. **Given** the Keychain contains malformed JSON, **When** the app reads credentials, **Then** the app logs the parse error via `os.Logger` (keychain category).
11. **And** treats it as "no credentials" state.
12. **And** does not crash (NFR11).

## Tasks / Subtasks

- [x] Task 1: Create `KeychainCredentials` model (AC: #1, #2)
  - [x] Create `Models/KeychainCredentials.swift`
  - [x] Define `Codable` struct matching the `claudeAiOauth` JSON shape: `accessToken`, `refreshToken`, `expiresAt` (Double — Unix ms), `subscriptionType`, `rateLimitTier`, `scopes`
  - [x] Use `CodingKeys` for any snake_case → camelCase mapping if the stored JSON uses snake_case
  - [x] Make all fields optional except `accessToken` (the minimum needed for any API call)
  - [x] Add `Sendable` conformance
- [x] Task 2: Define `KeychainServiceProtocol` (AC: #5)
  - [x] Create `Services/KeychainServiceProtocol.swift`
  - [x] Define protocol with `func readCredentials() async throws -> KeychainCredentials`
  - [x] Protocol must be `Sendable` for structured concurrency compatibility
- [x] Task 3: Implement `KeychainService` (AC: #1, #2, #4, #5, #10, #11, #12)
  - [x] Create `Services/KeychainService.swift`
  - [x] Use `SecItemCopyMatching` to query Keychain with service name `"Claude Code-credentials"`
  - [x] Parse returned data as JSON → extract `claudeAiOauth` object → decode to `KeychainCredentials`
  - [x] On no item found: throw `AppError.keychainNotFound`
  - [x] On access denied: throw `AppError.keychainAccessDenied`
  - [x] On malformed JSON: log via `os.Logger` (category: `keychain`), throw `AppError.keychainInvalidFormat`
  - [x] NEVER log token values, even at `.debug` level
  - [x] NEVER persist credentials to disk, UserDefaults, or any cache
- [x] Task 4: Wire `KeychainService` into app lifecycle (AC: #3, #6, #7, #8, #9)
  - [x] In `AppDelegate`, instantiate `KeychainService` and `AppState`
  - [x] On launch: attempt credential read → on success, update `AppState.updateSubscriptionTier()` and `AppState.updateConnectionStatus(.noCredentials → .connected or appropriate)`
  - [x] On failure (keychainNotFound): set `AppState.updateConnectionStatus(.noCredentials)`
  - [x] Menu bar already shows "✳ --" in grey for `.disconnected`/`.noCredentials` — verify this path works
  - [x] Start a background `Task` that polls Keychain every 30 seconds (structured concurrency, `Task.sleep(for: .seconds(30))`)
  - [x] On each poll: read credentials → update AppState accordingly → if credentials newly found, transition to `.connected`
  - [x] NOTE: This is a temporary polling loop — Story 2.2 (PollingEngine) will replace it with the full fetch cycle
- [x] Task 5: Add `AppState` status message support (AC: #7)
  - [x] Add a `statusMessage` property to `AppState`: `private(set) var statusMessage: (title: String, detail: String)?`
  - [x] Add `func updateStatusMessage(_ message: (title: String, detail: String)?)` method
  - [x] When `.noCredentials`: set statusMessage to ("No Claude credentials found", "Run Claude Code to create them")
  - [x] When credentials found: clear statusMessage to nil
- [x] Task 6: Write tests (AC: all)
  - [x] Create `cc-hdrmTests/Services/KeychainServiceTests.swift`
  - [x] Test: valid JSON → returns correct `KeychainCredentials` with all fields populated
  - [x] Test: missing optional fields → returns `KeychainCredentials` with nils for missing fields
  - [x] Test: malformed JSON → throws `AppError.keychainInvalidFormat`
  - [x] Test: no Keychain item → throws `AppError.keychainNotFound`
  - [x] Test: `KeychainCredentials` Codable round-trip with known JSON payloads
  - [x] Create `cc-hdrmTests/Models/KeychainCredentialsTests.swift`
  - [x] Test: decoding from realistic JSON payload matching Claude Code's stored format
  - [x] Test: `expiresAt` is Unix milliseconds (not seconds) — verify the field type handles large numbers

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. This story adds the first real service (`KeychainService`) behind a protocol interface.
- **Concurrency:** `KeychainService` uses `async throws`. Keychain read is synchronous (`SecItemCopyMatching`) but wrapped in async context. No GCD/DispatchQueue.
- **State management:** Services write to `AppState` via methods only. `subscriptionTier` is set via `updateSubscriptionTier()`. `connectionStatus` via `updateConnectionStatus()`.
- **Security (NFR6):** Credentials are read from Keychain into memory, used, and never written to disk/logs/UserDefaults. The `KeychainCredentials` struct lives only in memory.
- **Security (NFR7):** In the polling loop, credentials are read fresh from Keychain each cycle — no caching between cycles.
- **Logging:** `os.Logger` with subsystem `com.cc-hdrm.app`, category `keychain`. Log credential discovery events (found/not-found/malformed) but NEVER log token values.
- **Testing:** Swift Testing framework. Protocol-based `KeychainServiceProtocol` enables mocking in tests — mock the Security framework response, not the Keychain itself.

### Keychain Access Details (from Architecture + PRD API Spike)

**Keychain query parameters:**
```swift
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "Claude Code-credentials",
    kSecReturnData as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne
]
```

**Expected JSON structure in Keychain value:**
```json
{
  "claudeAiOauth": {
    "accessToken": "oauth-token-string",
    "refreshToken": "refresh-token-string",
    "expiresAt": 1738400000000,
    "subscriptionType": "pro",
    "rateLimitTier": "tier_1",
    "scopes": ["user:inference"]
  }
}
```

Note: The Keychain stores a top-level JSON object with `claudeAiOauth` as a key. You must parse the outer object first, then extract the inner `claudeAiOauth` value.

**`expiresAt` format:** Unix timestamp in **milliseconds** (not seconds). Divide by 1000 to get `Date(timeIntervalSince1970:)`.

### Credential Field Mapping

| JSON field         | Swift property       | Type       | Required? | Notes                                    |
|--------------------|----------------------|------------|-----------|------------------------------------------|
| `accessToken`      | `accessToken`        | `String`   | Yes       | Bearer token for API calls               |
| `refreshToken`     | `refreshToken`       | `String?`  | No        | Used by Story 1.3 for token refresh      |
| `expiresAt`        | `expiresAt`          | `Double?`  | No        | Unix ms — convert to Date via /1000      |
| `subscriptionType` | `subscriptionType`   | `String?`  | No        | e.g., "pro", "max"                       |
| `rateLimitTier`    | `rateLimitTier`      | `String?`  | No        | e.g., "tier_1"                           |
| `scopes`           | `scopes`             | `[String]?`| No        | OAuth scopes, informational only for MVP |

### Error Mapping

| Keychain Result          | `OSStatus`               | AppError                      | Behavior                              |
|--------------------------|--------------------------|-------------------------------|---------------------------------------|
| Item found, valid JSON   | `errSecSuccess`          | (no error)                    | Parse and return credentials          |
| No item found            | `errSecItemNotFound`     | `.keychainNotFound`           | Set `.noCredentials` status           |
| Access denied            | `errSecAuthFailed` etc.  | `.keychainAccessDenied`       | Set `.noCredentials` status, log      |
| Item found, bad JSON     | `errSecSuccess`          | `.keychainInvalidFormat`      | Set `.noCredentials` status, log      |

### Previous Story Intelligence (1.1)

**What was built:**
- Xcode project via XcodeGen (`project.yml` as spec, `.xcodeproj` gitignored)
- `AppDelegate` creates `NSStatusItem` with placeholder "✳ --" in grey
- `HeadroomState` enum with all thresholds and color/weight mappings
- `AppError` enum with all cases including `keychainNotFound`, `keychainAccessDenied`, `keychainInvalidFormat`
- `AppState` as `@Observable @MainActor` with `private(set)` + mutation methods
- `WindowState` struct with derived `headroomState`
- `ConnectionStatus` enum: `.connected`, `.disconnected`, `.tokenExpired`, `.noCredentials`
- 27 tests passing (Swift Testing framework)

**Code review fixes applied:**
- H1: Entitlements file had empty Keychain access — fixed, `keychain-access-groups` added
- M3: `AppError` Sendable conformance — fixed, associated `Error` changed to `any Error & Sendable`
- M4: `WindowState` missing `Equatable` — fixed

**Patterns established:**
- `os.Logger` with subsystem `com.cc-hdrm.app` and per-component category
- Monospaced system font for NSStatusItem
- `private(set)` with public mutation methods on AppState
- Swift Testing with `@Suite`, `@Test`, `#expect`
- `@MainActor` required on all `AppState` test functions

### Git Intelligence

**Last commit:** `c2a74e4 Add story 1.1 implementation: Xcode project initialization & menu bar shell`

Files established:
- `project.yml` — XcodeGen spec (add new files here, NOT manually in .xcodeproj)
- `cc-hdrm/App/AppDelegate.swift` — will be modified to wire KeychainService
- `cc-hdrm/App/cc_hdrmApp.swift` — entry point, may need AppState injection
- `cc-hdrm/Models/AppError.swift` — already has keychain error cases
- `cc-hdrm/State/AppState.swift` — needs statusMessage property added

### File Structure Requirements

New files to create:
```
cc-hdrm/Models/KeychainCredentials.swift    # Codable struct
cc-hdrm/Services/KeychainServiceProtocol.swift
cc-hdrm/Services/KeychainService.swift
cc-hdrmTests/Models/KeychainCredentialsTests.swift
cc-hdrmTests/Services/KeychainServiceTests.swift
```

Files to modify:
```
cc-hdrm/App/AppDelegate.swift               # Wire KeychainService, add polling loop
cc-hdrm/State/AppState.swift                 # Add statusMessage property + method
project.yml                                  # Add new source files to XcodeGen spec
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **Mocking strategy:** Create a `MockKeychainService` conforming to `KeychainServiceProtocol` for tests that need controlled credential responses
- **`@MainActor`:** Required on any test that touches `AppState`
- **Security tests:** Verify that `KeychainCredentials` does NOT conform to `CustomStringConvertible` or `CustomDebugStringConvertible` (prevents accidental token logging)

### Anti-Patterns to Avoid

- DO NOT cache credentials between poll cycles — read fresh from Keychain each time (NFR7)
- DO NOT log access tokens, refresh tokens, or any credential data
- DO NOT store credentials in UserDefaults, files, or any persistent storage
- DO NOT use `DispatchQueue` for the polling loop — use `Task.sleep` with structured concurrency
- DO NOT make `KeychainCredentials` conform to `CustomStringConvertible` — prevents accidental logging
- DO NOT call `SecItemCopyMatching` directly from views — only through `KeychainService`
- DO NOT use empty catch blocks — always map errors to `connectionStatus`

### Project Structure Notes

- Alignment with architecture: New files go in `Services/` and `Models/` per layer-based structure
- `project.yml` (XcodeGen) must be updated with new source file paths — the `.xcodeproj` is generated from it
- Test files mirror source: `Services/KeychainServiceTests.swift`, `Models/KeychainCredentialsTests.swift`

### References

- [Source: architecture.md#Keychain Integration] — Service name, JSON format, read/write access pattern
- [Source: architecture.md#Implementation Patterns & Consistency Rules] — Naming, protocol patterns, error handling
- [Source: architecture.md#Error Handling Patterns] — AppError enum, async throws, connectionStatus mapping
- [Source: architecture.md#Logging Patterns] — os.Logger categories, never log sensitive data
- [Source: architecture.md#Project Structure & Boundaries] — Keychain boundary: only KeychainService imports Security
- [Source: epics.md#Story 1.2] — Full acceptance criteria and BDD scenarios
- [Source: prd.md#API Spike Results] — Keychain service name "Claude Code-credentials", JSON structure
- [Source: 1-1-xcode-project-initialization-menu-bar-shell.md] — Previous story file list, patterns, code review findings

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

None — clean implementation, no debugging required.

### Completion Notes List

- Task 1: Created `KeychainCredentials` Codable+Sendable struct with `accessToken` (required) and all optional fields. No CodingKeys needed — JSON keys match Swift property names.
- Task 2: Defined `KeychainServiceProtocol` as Sendable protocol with single `readCredentials() async throws` method.
- Task 3: Implemented `KeychainService` with `SecItemCopyMatching`, JSON parsing of outer `claudeAiOauth` wrapper, `os.Logger` (category: keychain). Testable via `dataProvider` injection — no credentials logged. `@unchecked Sendable` since `dataProvider` closure is immutable after init.
- Task 4: Wired `KeychainService` into `AppDelegate` with `@MainActor` isolation. On launch: reads credentials, updates AppState. Polls every 30s via `Task.sleep(for:)`. Cancels polling on app termination. `AppState` created in `applicationDidFinishLaunching` to satisfy `@MainActor` init requirement.
- Task 5: Added `statusMessage: (title: String, detail: String)?` to `AppState` with `updateStatusMessage()` method. Set on `.noCredentials`, cleared on credential success.
- Task 6: 43 total tests (16 new). KeychainCredentialsTests: full payload, minimal, round-trip, large expiresAt, missing accessToken, Sendable, no CustomStringConvertible/CustomDebugStringConvertible, realistic payload. KeychainServiceTests: valid full JSON, minimal JSON, malformed JSON, missing claudeAiOauth key, no keychain item. AppStateTests: statusMessage default nil, set, clear.

### Change Log

- 2026-01-31: Story 1.2 implementation complete — Keychain credential discovery with 30s polling, status messages, 43 tests passing.
- 2026-01-31: Code review fixes applied (H1, H2, M1-M4). Entitlements restored, dataProvider changed to KeychainResult enum for OSStatus differentiation, statusMessage converted to Equatable struct, test assertions strengthened with specific error cases, keychainAccessDenied test added, File List corrected.

### File List

New files:
- cc-hdrm/Models/KeychainCredentials.swift
- cc-hdrm/Services/KeychainServiceProtocol.swift
- cc-hdrm/Services/KeychainService.swift
- cc-hdrmTests/Models/KeychainCredentialsTests.swift
- cc-hdrmTests/Services/KeychainServiceTests.swift

Modified files:
- cc-hdrm/App/AppDelegate.swift
- cc-hdrm/State/AppState.swift
- cc-hdrm/cc_hdrm.entitlements
- cc-hdrmTests/State/AppStateTests.swift
