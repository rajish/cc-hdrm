# Story 2.2: Background Polling Engine

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want the app to poll for usage data automatically in the background,
so that my headroom display is always current without any manual action.

## Acceptance Criteria

1. **Given** the app has successfully launched and credentials are available, **When** the polling engine starts, **Then** it executes a fetch cycle every 30 seconds using `Task.sleep` in structured concurrency.
2. **And** each cycle: reads fresh credentials from Keychain (NFR7) → checks token expiry → fetches usage → updates AppState.
3. **And** `AppState.lastUpdated` is set on each successful fetch.
4. **And** the menu bar display updates automatically within 2 seconds of new data (NFR1).
5. **Given** a poll cycle fails (network error, API error, token expired), **When** the PollingEngine catches the error, **Then** it maps the error to `AppState.connectionStatus` (disconnected, tokenExpired, etc.).
6. **And** the menu bar shows "✳ —" in grey (FR20).
7. **And** the expanded panel shows an explanation of the failure (FR21).
8. **And** polling continues — the next cycle attempts recovery automatically.
9. **Given** connectivity returns after a disconnected period, **When** the next poll cycle succeeds, **Then** `AppState.connectionStatus` returns to normal.
10. **And** the menu bar and panel resume showing live headroom data (FR22).
11. **And** recovery happens within one polling cycle (NFR13).

## Tasks / Subtasks

- [x] Task 1: Create `PollingEngineProtocol` and `PollingEngine` (AC: #1, #2, #8)
  - [x] Create `cc-hdrm/Services/PollingEngineProtocol.swift`
  - [x] Define `protocol PollingEngineProtocol: Sendable` with `func start() async` and `func stop()`
  - [x] Create `cc-hdrm/Services/PollingEngine.swift`
  - [x] Inject dependencies: `keychainService: any KeychainServiceProtocol`, `tokenRefreshService: any TokenRefreshServiceProtocol`, `apiClient: any APIClientProtocol`, `appState: AppState`
  - [x] Implement `start()`: `while !Task.isCancelled` loop with `Task.sleep(for: .seconds(30))`
  - [x] Each cycle calls `performPollCycle()` which: reads fresh credentials → checks token expiry via `TokenExpiryChecker` → fetches usage via `APIClient` → updates `AppState`
  - [x] On success: convert `UsageResponse` to `WindowState`, call `appState.updateWindows()`, set `connectionStatus` to `.connected`, clear `statusMessage`
  - [x] On error: map to `AppState.connectionStatus` and `statusMessage` (same error handling logic currently in `AppDelegate`)
  - [x] Implement `stop()`: cancel the internal `Task`
  - [x] Log poll cycle lifecycle via `os.Logger` (category: `polling`)
- [x] Task 2: Migrate polling logic from `AppDelegate` to `PollingEngine` (AC: #1, #2, #3, #8)
  - [x] Remove `performCredentialRead()`, `attemptTokenRefresh()`, `fetchUsageData()`, `handleCredentialError()`, `startPolling()` from `AppDelegate`
  - [x] Remove `tokenRefreshService`, `apiClient` dependencies from `AppDelegate` (PollingEngine owns them now)
  - [x] Keep `keychainService` in `AppDelegate` only if needed for initial setup; otherwise remove
  - [x] In `applicationDidFinishLaunching`: create `PollingEngine` with all service dependencies, call `pollingEngine.start()`
  - [x] In `applicationWillTerminate`: call `pollingEngine.stop()`
  - [x] Remove `pollingTask` from `AppDelegate` — PollingEngine manages its own Task internally
  - [x] Remove `apiLogger`, `tokenLogger` from `AppDelegate` — PollingEngine has its own loggers
  - [x] Keep `AppDelegate.logger` for app lifecycle logging only
- [x] Task 3: Handle 401 → token refresh within PollingEngine (AC: #5, #8)
  - [x] When `APIClient` throws `AppError.apiError(statusCode: 401, _)`, call `attemptTokenRefresh()` internally
  - [x] Reuse the exact same refresh logic from current `AppDelegate.attemptTokenRefresh()`: merge credentials preserving subscriptionType/rateLimitTier/scopes, write back to Keychain
  - [x] Do NOT retry the API call in the same cycle after refresh — let next poll cycle use the new token
  - [x] On refresh success: set `connectionStatus` to `.connected`, clear `statusMessage`
  - [x] On refresh failure: set `connectionStatus` to `.tokenExpired`, set appropriate `statusMessage`
- [x] Task 4: Write PollingEngine tests (AC: all)
  - [x] Create `cc-hdrmTests/Services/PollingEngineTests.swift`
  - [x] Test: successful poll cycle populates `AppState` with usage data and sets `.connected`
  - [x] Test: network error sets `connectionStatus` to `.disconnected` with appropriate `statusMessage`
  - [x] Test: API 401 triggers token refresh (verify `refreshCallCount`)
  - [x] Test: token expired (no refresh token) sets `.tokenExpired` status
  - [x] Test: keychain not found sets `.noCredentials` status
  - [x] Test: recovery after error — second successful cycle restores `.connected`
  - [x] Test: `stop()` cancels the polling task (verify no further cycles execute)
  - [x] Test: each cycle reads fresh credentials (verify `readCredentials` called each cycle, NFR7)
  - [x] Test: `AppState.lastUpdated` is set after successful fetch
- [x] Task 5: Update existing `AppDelegateTests` (AC: #1)
  - [x] Refactor `AppDelegateTests` — remove tests for logic that moved to `PollingEngine`
  - [x] Keep/add tests verifying `AppDelegate` creates `PollingEngine` with correct dependencies
  - [x] Verify `applicationWillTerminate` stops the polling engine
  - [x] Move mock services to a shared test helpers file if reuse is needed, OR duplicate in PollingEngineTests (keep it simple)

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. `PollingEngine` sits behind `PollingEngineProtocol` — same injection pattern as `KeychainService`, `APIClient`, `TokenRefreshService`.
- **Concurrency:** `PollingEngine.start()` is `async`. Uses `Task.sleep(for:)` in structured concurrency. No GCD/DispatchQueue.
- **State management:** PollingEngine calls `appState.updateWindows()`, `appState.updateConnectionStatus()`, `appState.updateStatusMessage()`, `appState.updateSubscriptionTier()` — never sets properties directly.
- **Error handling:** All errors map to `AppError` enum cases. PollingEngine catches all errors and maps to `AppState.connectionStatus` — errors never propagate to views.
- **Security (NFR6, NFR7):** Token is read fresh from Keychain each poll cycle and passed to `fetchUsage()`. Never cached between cycles.
- **Security (NFR8):** API requests go only to `api.anthropic.com`. Token refresh goes only to `platform.claude.com`.
- **Logging:** `os.Logger` with subsystem `com.cc-hdrm.app`, category `polling`. Log cycle start/end, state transitions, errors. NEVER log token values.

### PollingEngine Design

The PollingEngine is the orchestrator described in the architecture data flow diagram. It owns the poll-parse-update pipeline:

```swift
// Conceptual structure — NOT copy-paste code
final class PollingEngine: PollingEngineProtocol, @unchecked Sendable {
    private let keychainService: any KeychainServiceProtocol
    private let tokenRefreshService: any TokenRefreshServiceProtocol
    private let apiClient: any APIClientProtocol
    private let appState: AppState
    private var pollingTask: Task<Void, Never>?

    func start() async {
        // Perform initial fetch immediately
        await performPollCycle()
        // Then loop
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await self?.performPollCycle()
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
    }
}
```

**Key design points:**
- `@unchecked Sendable` because the class holds references to Sendable protocols and `@MainActor AppState` (same pattern as existing services)
- `start()` performs an initial fetch immediately, then enters the 30s loop — matches current `AppDelegate` behavior where `performCredentialRead()` is called before `startPolling()`
- `stop()` cancels the Task — structured concurrency handles cleanup
- `performPollCycle()` is the single method that runs each cycle: keychain read → token check → API fetch → state update

### Migration Strategy: AppDelegate → PollingEngine

**What moves OUT of AppDelegate:**
- `performCredentialRead()` → becomes `PollingEngine.performPollCycle()`
- `attemptTokenRefresh()` → becomes `PollingEngine.attemptTokenRefresh()`
- `fetchUsageData()` → becomes `PollingEngine.fetchUsageData()`
- `handleCredentialError()` → becomes `PollingEngine.handleCredentialError()`
- `startPolling()` → replaced by `PollingEngine.start()` loop
- `tokenRefreshService` dependency → moves to PollingEngine
- `apiClient` dependency → moves to PollingEngine
- `pollingTask` property → moves to PollingEngine
- `tokenLogger`, `apiLogger` → PollingEngine creates its own loggers

**What STAYS in AppDelegate:**
- `statusItem` setup and menu bar configuration
- `appState` creation
- `keychainService` creation (passed to PollingEngine)
- `applicationDidFinishLaunching` — creates PollingEngine, calls `start()`
- `applicationWillTerminate` — calls `stop()`
- `AppDelegate.logger` for lifecycle logging only

**AppDelegate after migration (conceptual):**
```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    internal var appState: AppState?
    private var pollingEngine: (any PollingEngineProtocol)?

    private static let logger = Logger(subsystem: "com.cc-hdrm.app", category: "AppDelegate")

    // Production init
    override init() {
        super.init()
    }

    // Test init — inject a mock polling engine
    init(pollingEngine: any PollingEngineProtocol) {
        self.pollingEngine = pollingEngine // pre-set for testing
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState()
        self.appState = state
        // ... statusItem setup ...

        if pollingEngine == nil {
            pollingEngine = PollingEngine(
                keychainService: KeychainService(),
                tokenRefreshService: TokenRefreshService(),
                apiClient: APIClient(),
                appState: state
            )
        }

        Task {
            await pollingEngine?.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingEngine?.stop()
    }
}
```

### PollingEngine Poll Cycle Logic

Each `performPollCycle()` follows this exact sequence (migrated from current `AppDelegate.performCredentialRead()`):

1. **Read credentials:** `keychainService.readCredentials()` — fresh each cycle (NFR7)
2. **Update subscription tier:** `appState.updateSubscriptionTier(credentials.subscriptionType)`
3. **Check token expiry:** `TokenExpiryChecker.tokenStatus(for: credentials)`
   - `.valid` → proceed to fetch
   - `.expired` / `.expiringSoon` → attempt token refresh, then stop (next cycle retries with new token)
4. **Fetch usage:** `apiClient.fetchUsage(token: credentials.accessToken)`
5. **Convert response:** `UsageResponse` → `WindowState` (same conversion as Story 2.1)
6. **Update state:** `appState.updateWindows()`, `appState.updateConnectionStatus(.connected)`, `appState.updateStatusMessage(nil)`

**Error mapping (identical to current AppDelegate):**
- `AppError.apiError(statusCode: 401, _)` → trigger token refresh
- `AppError.networkUnreachable` → `.disconnected`, "Unable to reach Claude API" / "Will retry automatically"
- `AppError.apiError(code, body)` → `.disconnected`, "API error (code)" / body
- `AppError.parseError` → `.disconnected`, "Unexpected API response format" / "Will retry automatically"
- `AppError.keychainNotFound` → `.noCredentials`, "No Claude credentials found" / "Run Claude Code to create them"
- `AppError.keychainAccessDenied` → `.noCredentials`, same message
- `AppError.keychainInvalidFormat` → `.noCredentials`, same message

### UsageResponse to WindowState Conversion

Reuse exact same logic from Story 2.1 (currently in `AppDelegate.fetchUsageData`):
```swift
let fiveHourState = response.fiveHour.map { window in
    WindowState(
        utilization: window.utilization ?? 0.0,
        resetsAt: window.resetsAt.flatMap { Date.fromISO8601($0) }
    )
}
let sevenDayState = response.sevenDay.map { window in
    WindowState(
        utilization: window.utilization ?? 0.0,
        resetsAt: window.resetsAt.flatMap { Date.fromISO8601($0) }
    )
}
```

**Important:** `HeadroomState(from:)` derives headroom from utilization. Do NOT invert the value.

### Previous Story Intelligence (2.1)

**What was built:**
- `APIClient` with injectable `dataLoader`, GET to `api.anthropic.com/api/oauth/usage`, correct headers, 10s timeout
- `UsageResponse`, `WindowUsage`, `ExtraUsage` — all Codable, Sendable, Equatable with CodingKeys
- `Date+Formatting.swift` with `fromISO8601()` supporting fractional seconds
- `AppDelegate` polling loop with full error handling (401→refresh, network→disconnected, parse→disconnected)
- 91 tests passing

**Patterns to reuse:**
- Injectable closure pattern (`DataLoader`) for URLSession testability
- `@unchecked Sendable` on service structs/classes with immutable closures
- `os.Logger` with per-component category
- `appState.updateConnectionStatus()` / `appState.updateStatusMessage()` / `appState.updateWindows()` for state changes
- Swift Testing: `@Suite`, `@Test`, `#expect`, `#expect(throws:)`
- Tests use `@MainActor` for anything touching `AppState`
- Mock services use `@unchecked Sendable` class wrappers for call tracking (e.g., `CallTracker`, `APICallTracker`, `WriteTracker`)

**Code review lessons from previous stories:**
- Pass original error to `AppError` wrappers, not hardcoded errors
- Remove dead code / unused properties before committing
- Add call counters to mocks for verifying interaction patterns
- URL-encode dynamic values in request bodies

### Project Structure Notes

- XcodeGen (`project.yml`) uses directory-based source discovery — new files in correct folders are auto-included
- All new files go in the architecture-specified locations per layer-based structure
- Test files mirror source structure

### File Structure Requirements

New files to create:
```
cc-hdrm/Services/PollingEngineProtocol.swift
cc-hdrm/Services/PollingEngine.swift
cc-hdrmTests/Services/PollingEngineTests.swift
```

Files to modify:
```
cc-hdrm/App/AppDelegate.swift              # Strip polling/fetch logic, wire PollingEngine
cc-hdrmTests/App/AppDelegateTests.swift      # Refactor for new AppDelegate shape
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **Mocking:** Create `MockPollingEngine` conforming to `PollingEngineProtocol` for AppDelegate tests. Reuse existing `MockKeychainService`, `MockTokenRefreshService`, `MockAPIClient` for PollingEngine tests.
- **`@MainActor`:** Required on any test touching `AppState`
- **Testing poll cycles:** Use mock services with configurable responses. Call `performPollCycle()` directly (expose as `internal` or via test-only method) rather than testing the full `start()` loop with sleep timing.
- **Edge cases:**
  - Credentials missing → `.noCredentials` status
  - Credentials malformed → `.noCredentials` status
  - Token expired, refresh succeeds → `.connected` on next cycle
  - Token expired, no refresh token → `.tokenExpired` status
  - API 401 → refresh triggered
  - Network unreachable → `.disconnected`
  - Parse error → `.disconnected`
  - Multiple consecutive failures → state stays `.disconnected`
  - Recovery after failure → `.connected` restored

### Anti-Patterns to Avoid

- DO NOT cache tokens or API responses between poll cycles (NFR7)
- DO NOT log access tokens — even at `.debug` level
- DO NOT use `DispatchQueue` — use `async/await` with `Task.sleep`
- DO NOT retry the API call within the same poll cycle on 401 — let token refresh happen and retry next cycle
- DO NOT leave the old polling logic in `AppDelegate` — it must be fully migrated
- DO NOT create a separate `startPolling()` method that duplicates `start()` — one entry point only
- DO NOT make PollingEngine depend on AppDelegate — PollingEngine is independent, AppDelegate just creates and starts/stops it
- DO NOT add adaptive intervals or backoff logic — keep it simple at 30s fixed (future enhancement)
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file

### References

- [Source: architecture.md#Polling Engine] — Task.sleep loop, 30-second default interval, lifecycle
- [Source: architecture.md#Data Flow] — PollingEngine orchestrator role, poll cycle sequence
- [Source: architecture.md#Core Architectural Decisions] — MVVM with service layer, protocol-based interfaces
- [Source: architecture.md#Error Handling Patterns] — AppError enum, PollingEngine catches and maps to connectionStatus
- [Source: architecture.md#Logging Patterns] — os.Logger polling category
- [Source: architecture.md#State Management Patterns] — Services write via methods, not direct property mutation
- [Source: epics.md#Story 2.2] — Full acceptance criteria
- [Source: 2-1-api-client-usage-data-fetch.md] — Previous story patterns, mock patterns, UsageResponse→WindowState conversion
- [Source: AppDelegate.swift:80-236] — Current polling + fetch + error handling logic to migrate

## Dev Agent Record

### Agent Model Used

claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

None — clean implementation, all 96 tests pass on first run.

### Completion Notes List

- Created `PollingEngineProtocol` (Sendable protocol with `start() async` and `stop()`)
- Created `PollingEngine` implementing the full poll-parse-update pipeline: reads fresh credentials each cycle (NFR7), checks token expiry, fetches usage via APIClient, updates AppState
- 401 handling triggers token refresh internally with credential merging (preserves subscriptionType/rateLimitTier/scopes)
- All errors caught and mapped to `AppState.connectionStatus` — errors never propagate to views
- Migrated all polling/fetch/refresh logic out of AppDelegate — AppDelegate now only manages lifecycle (create PollingEngine on launch, stop on terminate)
- Removed `keychainService`, `tokenRefreshService`, `apiClient`, `pollingTask`, `tokenLogger`, `apiLogger`, `performCredentialRead()`, `attemptTokenRefresh()`, `fetchUsageData()`, `handleCredentialError()`, `startPolling()`, `performCredentialReadForTesting()` from AppDelegate
- Added test-only `init(pollingEngine:)` to AppDelegate for injecting MockPollingEngine
- Created 10 PollingEngine tests covering: success, network error, 401→refresh, token expired (no refresh token), keychain not found, recovery after error, stop cancels polling, fresh credentials each cycle, lastUpdated set, parse error
- Refactored AppDelegateTests to 3 lifecycle tests: init with injected engine, launch starts engine + creates AppState, terminate stops engine
- Total: 96 tests passing (was 91 before, net +5 new tests after removing old AppDelegate polling tests)

### Change Log

- 2026-01-31: Implemented Story 2.2 — Background Polling Engine. Created PollingEngine service, migrated polling logic from AppDelegate, wrote comprehensive tests.
- 2026-01-31: Code review fixes — Made PollingEngine and PollingEngineProtocol @MainActor (eliminated data race on pollingTask), simplified MockPollingEngine, strengthened stop() test to exercise actual start() loop, added credential merge assertions to 401 test, added sprint-status.yaml to File List.

### File List

New files:
- cc-hdrm/Services/PollingEngineProtocol.swift
- cc-hdrm/Services/PollingEngine.swift
- cc-hdrmTests/Services/PollingEngineTests.swift

Modified files:
- cc-hdrm/App/AppDelegate.swift (stripped polling/fetch logic, now delegates to PollingEngine)
- cc-hdrmTests/App/AppDelegateTests.swift (refactored to test lifecycle only with MockPollingEngine)
- _bmad-output/implementation-artifacts/sprint-status.yaml (story status updated)
