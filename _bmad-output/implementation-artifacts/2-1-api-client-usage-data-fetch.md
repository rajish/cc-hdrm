# Story 2.1: API Client & Usage Data Fetch

Status: done

## Story

As a developer using Claude Code,
I want the app to fetch my current usage data from the Claude API,
so that I have real headroom data to display.

## Acceptance Criteria

1. **Given** valid OAuth credentials are available from KeychainService, **When** the APIClient fetches usage data, **Then** it sends GET to `https://api.anthropic.com/api/oauth/usage` with headers: `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-code/<version>`, using HTTPS exclusively (NFR9).
2. **And** the response is parsed into `UsageResponse` using `Codable` with `CodingKeys` (snake_case → camelCase).
3. **And** all response fields are optional — missing windows result in `nil`, not crashes (NFR12).
4. **And** unknown JSON keys are silently ignored.
5. **Given** the API returns a non-200 status code, **When** the response is received, **Then** the error is mapped to `AppError.apiError(statusCode:body:)`.
6. **And** a 401 specifically triggers the token refresh flow from Story 1.3.
7. **Given** the network is unreachable or the request times out, **When** the fetch attempt fails, **Then** the error is mapped to `AppError.networkUnreachable`.
8. **And** the request completes within 10 seconds (NFR5).

## Tasks / Subtasks

- [x] Task 1: Create `UsageResponse` Codable model (AC: #2, #3, #4)
  - [x] Create `cc-hdrm/cc-hdrm/Models/UsageResponse.swift`
  - [x] Define `UsageResponse` with optional `fiveHour`, `sevenDay`, `sevenDaySonnet`, `extraUsage` fields
  - [x] Define `WindowUsage` with optional `utilization: Double?` and `resetsAt: String?`
  - [x] Define `ExtraUsage` with optional `isEnabled: Bool?`, `monthlyLimit: Double?`, `usedCredits: Double?`, `utilization: Double?`
  - [x] Add `CodingKeys` enums mapping snake_case JSON to camelCase Swift (e.g., `five_hour` → `fiveHour`, `resets_at` → `resetsAt`, `is_enabled` → `isEnabled`)
  - [x] All structs conform to `Codable, Sendable`
- [x] Task 2: Create `APIClientProtocol` and `APIClient` (AC: #1, #5, #7, #8)
  - [x] Create `cc-hdrm/cc-hdrm/Services/APIClientProtocol.swift`
  - [x] Define `protocol APIClientProtocol: Sendable` with `func fetchUsage(token: String) async throws -> UsageResponse`
  - [x] Create `cc-hdrm/cc-hdrm/Services/APIClient.swift`
  - [x] Implement using `URLSession` with injectable `dataLoader` closure for testability (same pattern as `TokenRefreshService`)
  - [x] Build `URLRequest` with GET method, URL `https://api.anthropic.com/api/oauth/usage`
  - [x] Set headers: `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-code/1.0`
  - [x] Set `timeoutInterval = 10` on the request (NFR5)
  - [x] On success (200): decode response as `UsageResponse` via `JSONDecoder`; throw `AppError.parseError` on decode failure
  - [x] On non-200: throw `AppError.apiError(statusCode:body:)` with response body as string
  - [x] On network error (`URLError.notConnectedToInternet`, `.timedOut`, `.networkConnectionLost`, `.cannotFindHost`, `.cannotConnectToHost`): throw `AppError.networkUnreachable`
  - [x] On other `URLError`: throw `AppError.networkUnreachable`
  - [x] Log request/response via `os.Logger` (category: `api`); NEVER log token values
- [x] Task 3: Integrate APIClient into AppDelegate polling loop (AC: #1, #5, #6, #7)
  - [x] Add `apiClient: any APIClientProtocol` dependency to `AppDelegate` (injected via init, defaulting to `APIClient()`)
  - [x] After successful credential read and token validation in `performCredentialRead()`: call `apiClient.fetchUsage(token: credentials.accessToken)`
  - [x] On success: convert `UsageResponse` to `WindowState` values and call `appState.updateWindows(fiveHour:sevenDay:)`, set `connectionStatus` to `.connected`, clear `statusMessage`
  - [x] On `AppError.apiError(statusCode: 401, _)`: trigger token refresh flow (call existing `attemptTokenRefresh`)
  - [x] On `AppError.networkUnreachable`: set `connectionStatus` to `.disconnected`, set `statusMessage` to "Unable to reach Claude API" / "Will retry automatically"
  - [x] On `AppError.apiError` (non-401): set `connectionStatus` to `.disconnected`, set `statusMessage` with error details
  - [x] On `AppError.parseError`: log the error, set `connectionStatus` to `.disconnected`, set `statusMessage` to "Unexpected API response format"
- [x] Task 4: Add `resetsAt` ISO 8601 date parsing helper (AC: #2)
  - [x] Add to `Extensions/Date+Formatting.swift` (or create it): `static func fromISO8601(_ string: String) -> Date?`
  - [x] Use `ISO8601DateFormatter` with `fractionalSeconds` option to handle the microsecond precision in API responses (e.g., `2026-01-31T01:59:59.782798+00:00`)
  - [x] Return `nil` on parse failure — never crash
- [x] Task 5: Write tests (AC: all)
  - [x] Create `cc-hdrmTests/Models/UsageResponseTests.swift`
  - [x] Test: full API response parses all fields correctly
  - [x] Test: response with missing `seven_day` parses without crash
  - [x] Test: response with null `resets_at` parses as nil
  - [x] Test: response with unknown keys (e.g., `iguana_necktie`) parses without crash
  - [x] Test: empty JSON object `{}` parses as all-nil UsageResponse
  - [x] Test: malformed JSON throws decode error
  - [x] Create `cc-hdrmTests/Services/APIClientTests.swift`
  - [x] Test: successful 200 response returns parsed `UsageResponse`
  - [x] Test: 401 response throws `AppError.apiError(statusCode: 401, body:)`
  - [x] Test: 500 response throws `AppError.apiError(statusCode: 500, body:)`
  - [x] Test: network timeout throws `AppError.networkUnreachable`
  - [x] Test: malformed JSON response throws `AppError.parseError`
  - [x] Test: request includes correct headers (Authorization, anthropic-beta, User-Agent)
  - [x] Test: request URL is exactly `https://api.anthropic.com/api/oauth/usage`
  - [x] Add integration tests to `AppDelegateTests.swift`
  - [x] Test: valid credentials + successful fetch → `appState.fiveHour` populated, `connectionStatus` is `.connected`
  - [x] Test: valid credentials + 401 → token refresh triggered
  - [x] Test: valid credentials + network error → `connectionStatus` is `.disconnected`
  - [x] Create `cc-hdrmTests/Extensions/DateFormattingTests.swift`
  - [x] Test: ISO 8601 with fractional seconds parses correctly
  - [x] Test: ISO 8601 with timezone offset parses correctly
  - [x] Test: invalid string returns nil

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. `APIClient` sits behind `APIClientProtocol` — same injection pattern as `KeychainService` and `TokenRefreshService`.
- **Concurrency:** `APIClient.fetchUsage()` is `async throws`. Uses `URLSession.data(for:)`. No GCD/DispatchQueue.
- **State management:** Polling loop calls `appState.updateWindows()` and `appState.updateConnectionStatus()` — never sets properties directly.
- **Error handling:** All errors map to `AppError` enum cases. `PollingEngine` (future story 2.2) will eventually own this, but for now the polling loop in `AppDelegate` handles errors.
- **Security (NFR6, NFR7):** Token is read fresh from Keychain each cycle and passed to `fetchUsage()`. Never cached.
- **Security (NFR8):** API requests go only to `api.anthropic.com`.
- **Security (NFR9):** HTTPS exclusively.
- **Logging:** `os.Logger` with subsystem `com.cc-hdrm.app`, category `api`. Log request outcomes (success/fail/status code). NEVER log token values.

### API Endpoint Details

**Endpoint:** `GET https://api.anthropic.com/api/oauth/usage`

**Required headers:**
```
Authorization: Bearer <oauth_access_token>
anthropic-beta: oauth-2025-04-20
User-Agent: claude-code/1.0
```

**Response format (from API spike):**
```json
{
  "five_hour": { "utilization": 18.0, "resets_at": "2026-01-31T01:59:59.782798+00:00" },
  "seven_day": { "utilization": 6.0, "resets_at": "2026-02-06T08:59:59.782818+00:00" },
  "seven_day_sonnet": { "utilization": 0.0, "resets_at": null },
  "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
}
```

- `utilization` is 0-100 (percentage of capacity used, NOT headroom). Headroom = 100 - utilization.
- `resets_at` is ISO 8601 with fractional seconds and timezone offset, or `null`.
- Additional keys may appear (e.g., `seven_day_opus`, `iguana_necktie`) — silently ignore.

### UsageResponse to WindowState Conversion

When converting API response to `WindowState` for `AppState`:
```swift
// utilization from API is usage percentage (0-100)
// WindowState.utilization stores usage percentage (HeadroomState derives headroom from it)
let fiveHourState = response.fiveHour.map { window in
    WindowState(
        utilization: window.utilization ?? 0.0,
        resetsAt: window.resetsAt.flatMap { Date.fromISO8601($0) }
    )
}
```

**Important:** `HeadroomState(from:)` already exists and derives headroom from utilization. The API's `utilization` value maps directly to `WindowState.utilization`. Do NOT invert the value — `HeadroomState` handles the math.

### Testability Pattern

Follow the same injectable closure pattern used by `TokenRefreshService` and `KeychainService`:

```swift
struct APIClient: APIClientProtocol {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let dataLoader: DataLoader

    init(dataLoader: @escaping DataLoader = { request in
        try await URLSession.shared.data(for: request)
    }) {
        self.dataLoader = dataLoader
    }
}
```

This allows tests to inject mock responses without `URLProtocol` complexity.

### 401 Handling — Integration with Token Refresh

When the API returns 401:
1. `APIClient` throws `AppError.apiError(statusCode: 401, body:)`
2. `AppDelegate.performCredentialRead()` catches this specific error
3. Calls existing `attemptTokenRefresh(credentials:appState:)` from Story 1.3
4. If refresh succeeds, the **next** poll cycle will retry the API call with the new token
5. Do NOT retry immediately in the same cycle — let the polling loop handle recovery naturally

### Previous Story Intelligence (1.3)

**What was built:**
- `TokenRefreshService` with injectable `dataLoader`, POST to `platform.claude.com/v1/oauth/token`
- `TokenExpiryChecker` — static `tokenStatus(for:now:)` returning `.valid`, `.expiringSoon`, `.expired`
- `KeychainService.writeCredentials()` with `SecItemUpdate`/`SecItemAdd`
- `AppDelegate.performCredentialRead()` — reads creds, checks expiry, attempts refresh
- `AppDelegate.attemptTokenRefresh()` — merges refreshed creds, writes to Keychain
- 67 tests passing

**Patterns to reuse:**
- Injectable `dataLoader` closure for `URLSession` testability
- `@unchecked Sendable` on service structs with immutable closures
- `os.Logger` with per-component category
- `appState.updateConnectionStatus()` / `appState.updateStatusMessage()` for state changes
- Swift Testing: `@Suite`, `@Test`, `#expect`, `#expect(throws:)`
- Tests use `@MainActor` for anything touching `AppState`

**Code review fixes to learn from:**
- URL-encode dynamic values in request bodies
- Pass original error to `AppError` wrappers, not hardcoded errors
- Remove dead code / unused properties before committing
- Add call counters to mocks for verifying interaction patterns

### Project Structure Notes

- XcodeGen (`project.yml`) uses directory-based source discovery — new files in correct folders are auto-included
- All new files go in the architecture-specified locations per layer-based structure
- Test files mirror source structure

### File Structure Requirements

New files to create:
```
cc-hdrm/cc-hdrm/Models/UsageResponse.swift
cc-hdrm/cc-hdrm/Services/APIClientProtocol.swift
cc-hdrm/cc-hdrm/Services/APIClient.swift
cc-hdrm/cc-hdrm/Extensions/Date+Formatting.swift
cc-hdrm/cc-hdrmTests/Models/UsageResponseTests.swift
cc-hdrm/cc-hdrmTests/Services/APIClientTests.swift
cc-hdrm/cc-hdrmTests/Extensions/DateFormattingTests.swift
```

Files to modify:
```
cc-hdrm/cc-hdrm/App/AppDelegate.swift               # Add APIClient dependency, integrate fetch into polling
cc-hdrm/cc-hdrmTests/App/AppDelegateTests.swift       # Add API fetch integration tests
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **Mocking:** Create `MockAPIClient` conforming to `APIClientProtocol`. Track call count and last token passed. Return configurable `UsageResponse` or throw configurable errors.
- **`@MainActor`:** Required on any test touching `AppState`
- **Edge cases:**
  - All-nil `UsageResponse` (empty API response `{}`)
  - `utilization` of exactly 0.0, 100.0, and values > 100 (defensive)
  - `resets_at` with various ISO 8601 formats (fractional seconds, Z suffix, offset)
  - `resets_at` as `null`
  - Unknown JSON keys in response
  - Network timeout at exactly 10 seconds

### Anti-Patterns to Avoid

- DO NOT cache tokens or API responses between poll cycles (NFR7)
- DO NOT log access tokens — even at `.debug` level
- DO NOT use `DispatchQueue` — use `async/await`
- DO NOT send requests to any endpoint other than `api.anthropic.com` (NFR8)
- DO NOT force-unwrap any field from the API response — all fields are optional
- DO NOT retry the API call within the same poll cycle on 401 — let token refresh happen and retry next cycle
- DO NOT create a separate `PollingEngine` yet — that's Story 2.2. Keep the fetch call in the existing `AppDelegate` polling loop
- DO NOT invert the `utilization` value — `HeadroomState(from:)` already handles headroom derivation from utilization

### References

- [Source: architecture.md#API Integration] — Endpoint, headers, response parsing strategy
- [Source: architecture.md#Structure Patterns] — Layer-based file organization
- [Source: architecture.md#Format Patterns] — `UsageResponse` Codable example with CodingKeys
- [Source: architecture.md#Error Handling Patterns] — AppError enum, async throws, PollingEngine error mapping
- [Source: architecture.md#Logging Patterns] — os.Logger api category
- [Source: prd.md#API Spike Results] — Exact endpoint, response format, headers
- [Source: epics.md#Story 2.1] — Full acceptance criteria
- [Source: 1-3-token-expiry-detection-refresh.md] — Previous story patterns, AppDelegate structure, testability patterns

## Dev Agent Record

### Agent Model Used

claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

- Swift 6 concurrency: `var capturedRequest` in `@Sendable` closures required `@unchecked Sendable` class wrapper (`RequestCapture`).

### Completion Notes List

- ✅ Task 1: Created `UsageResponse.swift` with `UsageResponse`, `WindowUsage`, `ExtraUsage` structs — all Codable, Sendable, Equatable with CodingKeys for snake_case mapping.
- ✅ Task 2: Created `APIClientProtocol` and `APIClient` with injectable `dataLoader`, GET to `api.anthropic.com/api/oauth/usage`, correct headers, 10s timeout, error mapping to `AppError`.
- ✅ Task 3: Integrated `APIClient` into `AppDelegate` — added `apiClient` dependency, `fetchUsageData()` method with full error handling (401→refresh, network→disconnected, parse→disconnected).
- ✅ Task 4: Created `Date+Formatting.swift` with `fromISO8601()` supporting fractional seconds and fallback without.
- ✅ Task 5: 91 tests passing (25 new). UsageResponseTests (6), APIClientTests (10), DateFormattingTests (4), AppDelegateAPITests (4) + 1 new validTokenNoRefresh test + updated existing tests for new apiClient parameter.

### Change Log

- 2026-01-31: Implemented Story 2.1 — API Client & Usage Data Fetch. All 5 tasks complete, 90 tests passing (23 new).
- 2026-01-31: Code review fixes — restored entitlements, APIClient class→struct, static ISO8601 formatters, pass credentials to avoid double Keychain read, improved parseError test assertion, added parseError integration test, documented intentional sevenDaySonnet/extraUsage omission. 91 tests passing (25 new).

### File List

**New files:**
- `cc-hdrm/cc-hdrm/Models/UsageResponse.swift`
- `cc-hdrm/cc-hdrm/Services/APIClientProtocol.swift`
- `cc-hdrm/cc-hdrm/Services/APIClient.swift`
- `cc-hdrm/cc-hdrm/Extensions/Date+Formatting.swift`
- `cc-hdrm/cc-hdrmTests/Models/UsageResponseTests.swift`
- `cc-hdrm/cc-hdrmTests/Services/APIClientTests.swift`
- `cc-hdrm/cc-hdrmTests/Extensions/DateFormattingTests.swift`

**Modified files:**
- `cc-hdrm/cc-hdrm/App/AppDelegate.swift`
- `cc-hdrm/cc-hdrmTests/App/AppDelegateTests.swift`
