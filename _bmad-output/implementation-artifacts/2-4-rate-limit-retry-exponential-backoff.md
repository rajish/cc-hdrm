# Story 2.4: Rate Limit Retry & Exponential Backoff

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want the app to handle 429 rate limit responses intelligently and back off on consecutive failures,
so that polling recovers automatically without hammering a rate-limited or degraded API.

## Acceptance Criteria

1. **Given** the API returns HTTP 429 (rate limit), **When** the PollingEngine receives the error, **Then** it is classified as `AppError.rateLimited(retryAfter:)` with the parsed `Retry-After` header value (seconds) **And** it is NOT treated as an API outage (no outage notification, no outage record in DB) **And** `connectionStatus` is set to `.disconnected` **And** the status message shows "Rate limited" / "Will retry in Xs".

2. **Given** the API returns a `Retry-After` header with a 429 response, **When** the APIClient parses the response, **Then** the integer seconds value is extracted and included in the `AppError.rateLimited(retryAfter:)` error **And** if the header is missing or unparseable, `retryAfter` is nil.

3. **Given** 2+ consecutive poll cycles fail (any error type except 401 and credential errors), **When** the PollingEngine calculates the next sleep interval, **Then** the interval increases with exponential backoff: base interval -> 2x -> 4x, capped at 1 hour (3600s) **And** for 429 errors, the backoff floor is the `Retry-After` value if it exceeds the computed backoff **And** the backoff resets to the base interval on the next successful poll. *(Note: cap raised from original 5-minute spec to 1 hour because the default poll interval is 300s — a 300s cap would equal the base interval with no effective backoff.)*

4. **Given** the PollingEngine is in exponential backoff, **When** the popover displays the disconnected status, **Then** it shows the actual last poll attempt time (not last successful fetch) **And** optionally shows the next retry countdown (e.g., "Retrying in 45s").

5. **Given** the system is in Low Power Mode (`ProcessInfo.processInfo.isLowPowerModeEnabled`), **When** the PollingEngine calculates the next interval, **Then** the base interval is doubled (300s -> 600s) before applying backoff multiplier **And** the 1-hour cap still applies to the final interval.

6. **Given** a successful poll occurs after a backoff period, **When** `connectionStatus` returns to `.connected`, **Then** the consecutive failure counter resets to zero **And** the polling interval returns to the base interval (respecting Low Power Mode if active).

## Tasks / Subtasks

- [x] Task 1: Add `AppError.rateLimited` case (AC: 1, 2)
  - [x] 1.1 In `cc-hdrm/Models/AppError.swift`: add `case rateLimited(retryAfter: Int?)` to `AppError` enum
  - [x] 1.2 Update `Equatable` conformance — `rateLimited` uses associated value comparison (same pattern as `apiError`)
  - [x] 1.3 In `cc-hdrmTests/Services/APIClientTests.swift`: add test for 429 response mapping to `.rateLimited` with `Retry-After` header, and test for 429 without header

- [x] Task 2: Parse `Retry-After` header in APIClient (AC: 2)
  - [x] 2.1 In `cc-hdrm/Services/APIClient.swift` `fetch` method: before the `guard httpResponse.statusCode == 200` check, add a 429-specific branch that extracts `Retry-After` header via `httpResponse.value(forHTTPHeaderField: "Retry-After")`, parses as `Int`, and throws `AppError.rateLimited(retryAfter:)`
  - [x] 2.2 If `Retry-After` header is missing or not a valid integer (including HTTP-date format), throw `AppError.rateLimited(retryAfter: nil)`
  - [x] 2.3 Filter non-positive values: `Retry-After` of 0 or negative → `nil` (treated as absent — "retry now" is not a meaningful delay)
  - [x] 2.4 Log the rate limit event: `Self.logger.warning("Rate limited by API — Retry-After: \(retryAfter ?? "not specified")")`

- [x] Task 3: Add backoff state to PollingEngine (AC: 3, 5, 6)
  - [x] 3.1 In `cc-hdrm/Services/PollingEngine.swift`: add properties:
    ```swift
    private var consecutiveFailureCount: Int = 0
    private var retryAfterOverride: Int? = nil  // From 429 Retry-After header
    private let isLowPowerModeEnabled: () -> Bool  // Injectable for testability
    ```
    Add `isLowPowerModeEnabled` parameter to `init` with default `{ ProcessInfo.processInfo.isLowPowerModeEnabled }`
  - [x] 3.2 Add `internal` method `computeNextInterval() -> TimeInterval` (internal for testability, same pattern as `evaluateWindow` in NotificationService):
    - `baseInterval` = `preferencesManager.pollInterval` (default 300s)
    - If `isLowPowerModeEnabled()` returns true: double `baseInterval`
    - If `consecutiveFailureCount <= 1`: return `baseInterval`
    - Clamp exponent: `let exponent = min(consecutiveFailureCount - 1, 10)` — prevents `pow()` overflow for sustained failures
    - Backoff: `baseInterval * pow(2, Double(exponent))`, capped at 3600s (1 hour)
    - If `retryAfterOverride` exceeds computed value, use `retryAfterOverride` (also capped at 3600s)
    - Log interval change at `.info` level
  - [x] 3.3 On success path (after `appState.updateConnectionStatus(.connected)` at line 217): reset `consecutiveFailureCount = 0` and `retryAfterOverride = nil`
  - [x] 3.4 On failure paths in `handleAPIError` (for `.networkUnreachable`, `.apiError`, `.parseError`, `default`): increment `consecutiveFailureCount += 1` AND clear `retryAfterOverride = nil` (stale Retry-After from a previous 429 must not persist across different error types)
  - [x] 3.5 On `.rateLimited` case: increment `consecutiveFailureCount += 1` and set `retryAfterOverride = retryAfter`
  - [x] 3.6 Update the polling loop in `start()` to use `computeNextInterval()` instead of reading `pollInterval` directly

- [x] Task 4: Handle `.rateLimited` in `handleAPIError` (AC: 1)
  - [x] 4.1 In `cc-hdrm/Services/PollingEngine.swift` `handleAPIError`: add a new case BEFORE the generic `.apiError` case:
    ```swift
    case .rateLimited(let retryAfter):
        Self.logger.warning("Rate limited — retry after: \(retryAfter.map(String.init) ?? "unspecified") seconds")
        appState.updateExtraUsage(enabled: false, monthlyLimit: nil, usedCredits: nil, utilization: nil)
        appState.updateConnectionStatus(.disconnected)
        let detail = retryAfter.map { "Will retry in \($0)s" } ?? "Will retry with backoff"
        appState.updateStatusMessage(StatusMessage(
            title: "Rate limited",
            detail: detail
        ))
        // Do NOT call evaluateConnectivity — 429 is ambiguous (API responded but is
        // rejecting requests). Calling apiReachable:true would reset the outage failure
        // counter, masking real outages in mixed-error scenarios (e.g., 429, timeout, 429, timeout).
        // Calling apiReachable:false is also wrong since the API did respond.
        // Best: leave connectivity state unchanged — let real successes/failures drive it.
    ```
  - [x] 4.2 Do NOT call `evaluateConnectivity` at all for 429 — it's neither "reachable" (would reset outage tracking) nor "unreachable" (it responded). Leave connectivity state unchanged.
  - [x] 4.3 Do NOT call `historicalDataService?.evaluateOutageState(apiReachable: false, ...)` — 429 means the API responded, it's not an outage

- [x] Task 5: Add `lastAttempted` to AppState (AC: 4)
  - [x] 5.1 In `cc-hdrm/State/AppState.swift`: add `private(set) var lastAttempted: Date?` property
  - [x] 5.2 Add `func updateLastAttempted()` that sets `lastAttempted = Date()`
  - [x] 5.3 In `cc-hdrm/Services/PollingEngine.swift` `performPollCycle()`: call `appState.updateLastAttempted()` AFTER the credential check succeeds but BEFORE `fetchUsageData()` is called. This ensures the timestamp reflects the most recent API attempt, not credential-check-only cycles (if credentials are missing, no API call is made, so "last attempt" shouldn't update)

- [x] Task 6: Fix PopoverView status message display (AC: 1, 4)
  - [x] 6.1 In `cc-hdrm/Views/PopoverView.swift` `resolvedStatusMessage` computed property, `.disconnected` case: if `appState.statusMessage` is already set (e.g., "Rate limited / Will retry in Xs"), use it as-is instead of overriding with "Unable to reach Claude API". Only generate the generic "Unable to reach Claude API / Last attempt: Xs ago" fallback when `appState.statusMessage` is nil.
  - [x] 6.2 In the fallback path: use `appState.lastAttempted ?? appState.lastUpdated` for the "Last attempt: Xs ago" calculation (tracks actual last poll attempt, not last success)
  - [x] 6.3 Keep `appState.lastUpdated` for the `.connected` + `.veryStale` case ("Last updated: Xm ago") — this correctly tracks last successful fetch

- [x] Task 7: Write comprehensive tests (AC: 1-6)
  - [x] 7.1 In `cc-hdrmTests/Services/APIClientTests.swift`:
    - [x] Test: 429 response with `Retry-After: 30` header -> `AppError.rateLimited(retryAfter: 30)`
    - [x] Test: 429 response without `Retry-After` header -> `AppError.rateLimited(retryAfter: nil)`
    - [x] Test: 429 response with non-integer `Retry-After` (e.g., HTTP-date format) -> `AppError.rateLimited(retryAfter: nil)`
    - [x] Test: 429 response with negative `Retry-After: -1` -> `AppError.rateLimited(retryAfter: nil)` (non-positive treated as absent)
  - [x] 7.2 In `cc-hdrmTests/Services/PollingEngineTests.swift`:
    - [x] Test: Single failure -> no backoff (interval stays at base)
    - [x] Test: 2 consecutive failures -> interval doubles
    - [x] Test: 3 consecutive failures -> interval quadruples
    - [x] Test: Backoff caps at 1 hour (3600s) even with many consecutive failures
    - [x] Test: Exponent capped at 10 — 100 consecutive failures doesn't cause pow() overflow
    - [x] Test: Success after backoff -> interval resets to base, consecutiveFailureCount = 0
    - [x] Test: 429 with Retry-After=60 -> interval is at least 60s
    - [x] Test: 429 with Retry-After exceeding cap -> capped at 3600s
    - [x] Test: 429 with negative Retry-After -> treated as nil (non-positive = absent)
    - [x] Test: `evaluateConnectivity` NOT called on 429 (connectivity state unchanged)
    - [x] Test: `evaluateOutageState` NOT called on 429
    - [x] Test: `lastAttempted` is updated before fetchUsageData, not on credential failure
    - [x] Test: Recovery from backoff state restores `consecutiveFailureCount` to 0
    - [x] Test: `retryAfterOverride` cleared when non-429 error follows a 429 (e.g., 429 then networkUnreachable)
    - [x] Test: Mixed errors (429, timeout, 429, timeout) — connectivity counter not reset by 429s
    - [x] Test: Low Power Mode doubles base interval (inject `isLowPowerModeEnabled: { true }`)
    - [x] Test: Low Power Mode + backoff compounds correctly (600s base -> 1200s -> 2400s -> cap 3600s)
    - [x] Test: PopoverView shows "Rate limited" message (not overridden to "Unable to reach Claude API")
    - [x] Test: PopoverView shows "Unable to reach Claude API" with `lastAttempted` timestamp when no specific status message set
  - [x] 7.3 Run `xcodegen generate` after any new test files (likely no new files — tests go in existing files)

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. Backoff state lives in PollingEngine (poll orchestration is its responsibility). AppState only gets the derived `lastAttempted` timestamp and `connectionStatus` — it does NOT track failure counts or intervals.
- **Boundary:** APIClient maps HTTP responses to errors. PollingEngine decides what to do with them. PopoverView displays state. Same one-way flow as all existing features.
- **Concurrency:** `@MainActor` on PollingEngine. Backoff state (`consecutiveFailureCount`, `retryAfterOverride`) is only accessed from the polling loop — no thread safety concern.
- **Logging:** `os.Logger`, subsystem `com.cc-hdrm.app`, category `polling`. Log `.warning` on rate limit, `.info` on backoff interval changes, `.debug` on failure count increments.

### Key Implementation Details

**429 vs. other errors — connectivity/outage classification:**

| Error | evaluateConnectivity | evaluateOutageState | Reason |
|-------|---------------------|---------------------|--------|
| `rateLimited(429)` | NOT called | NOT called | Ambiguous — API responded but is rejecting. Neither reachable nor unreachable. Leave connectivity/outage state unchanged. |
| `networkUnreachable` | `apiReachable: false` | `apiReachable: false` | Can't reach API |
| `apiError(5xx)` | `apiReachable: false` | `apiReachable: false` | Server error |
| `apiError(401)` | NOT called | NOT called | Auth issue, handled by token refresh |
| `parseError` | `apiReachable: false` | `apiReachable: false` | API returned garbage |

**Default poll interval change (30s → 300s):**

The default poll interval was raised from 30s to 300s (5 minutes) to reduce API load and avoid rate limiting in normal operation. With this change:
- `PreferencesDefaults.pollInterval` changed from 30 to 300
- `PreferencesManager.pollInterval` max clamp raised from 300 to 1800 (30 minutes)
- `SettingsView.pollIntervalOptions` extended with 600s, 900s, 1800s picker options
- Backoff cap raised from 300s to 3600s (1 hour) — a 300s cap with a 300s base would provide no effective backoff

**Backoff calculation:**

```swift
func computeNextInterval() -> TimeInterval {  // internal for testability
    var base = preferencesManager.pollInterval  // Default 300s
    if isLowPowerModeEnabled() {
        base *= 2  // 30s -> 60s in Low Power Mode
    }
    guard consecutiveFailureCount > 1 else { return base }

    let exponent = min(consecutiveFailureCount - 1, 10)  // Cap exponent to prevent pow() overflow
    let backoff = base * pow(2.0, Double(exponent))
    let retryFloor = retryAfterOverride.map { TimeInterval(max(0, $0)) } ?? 0
    return min(max(backoff, retryFloor), 3600)  // Cap at 1 hour
}
```

**Polling loop change:**

```swift
// BEFORE (current):
let interval = self?.preferencesManager.pollInterval ?? PreferencesDefaults.pollInterval
try? await Task.sleep(for: .seconds(interval))

// AFTER:
let interval = self?.computeNextInterval() ?? PreferencesDefaults.pollInterval
try? await Task.sleep(for: .seconds(interval))
```

**APIClient 429 detection:**

```swift
// In fetch(), BEFORE the existing guard:
if httpResponse.statusCode == 429 {
    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
    Self.logger.warning("Rate limited — Retry-After: \(retryAfter.map(String.init) ?? "not specified")")
    throw AppError.rateLimited(retryAfter: retryAfter)
}

guard httpResponse.statusCode == 200 else { ... }
```

**PopoverView fix — respect PollingEngine status messages, fix timestamp:**

```swift
case .disconnected:
    // If PollingEngine set a specific status message (e.g., "Rate limited"),
    // use it instead of the generic "Unable to reach Claude API" override.
    if let existingMessage = appState.statusMessage {
        return existingMessage
    }
    // Fallback: generic disconnected message with actual last attempt time
    let detail: String
    if let lastAttempted = appState.lastAttempted ?? appState.lastUpdated {
        let elapsed = Int(max(0, Date().timeIntervalSince(lastAttempted)))
        detail = elapsed < 60 ? "Last attempt: \(elapsed)s ago" : "Last attempt: \(elapsed / 60)m ago"
    } else {
        detail = "Attempting to connect..."
    }
    return StatusMessage(title: "Unable to reach Claude API", detail: detail)
```

### Previous Story Intelligence (2.2, 5.4, 10.6)

**Story 2.2 (Background Polling Engine) — what was deferred:**
- Epic 2 Story 2.2 ACs specified exponential backoff (30s -> 60s -> 120s, capped at 5 min), Low Power Mode doubling, and sleep/wake handling
- Implementation deferred backoff with explicit note: "DO NOT add adaptive intervals or backoff logic — keep it simple at 30s fixed (future enhancement)" [Source: `_bmad-output/implementation-artifacts/2-2-background-polling-engine.md`]
- Sleep/wake handling is out of scope for this story (separate concern)

**Story 5.4 (API Connectivity Notifications):**
- Added `evaluateConnectivity(apiReachable:)` state machine in NotificationService
- 429 should NOT call `evaluateConnectivity` at all — calling `apiReachable: true` would reset the outage failure counter, masking real outages in mixed-error scenarios (429 interspersed with timeouts). Calling `apiReachable: false` is wrong because the API did respond. Best approach: leave connectivity state unchanged, same as 401.
- `consecutiveFailureCount` in NotificationService is independent from the backoff `consecutiveFailureCount` in PollingEngine — different purposes (notification threshold vs interval calculation)

**Story 10.6 (API Outage Period Persistence):**
- Added `evaluateOutageState(apiReachable:failureReason:)` in HistoricalDataService
- Currently maps 429 as `"httpError:429"` and creates outage records — this is WRONG for rate limiting
- 429 should NOT call `evaluateOutageState(apiReachable: false, ...)` — rate limiting is not an outage

### Project Structure Notes

- All changes are to existing files — no new files needed
- `xcodegen generate` only needed if new files are created (unlikely for this story)

### File Structure Requirements

Files to modify:
```text
cc-hdrm/Models/AppError.swift                    # ADD rateLimited(retryAfter:) case + Equatable
cc-hdrm/Services/APIClient.swift                  # ADD 429 detection + Retry-After parsing + clamping
cc-hdrm/Services/PollingEngine.swift              # ADD backoff state, isLowPowerModeEnabled injection, computeNextInterval(), rateLimited handler, lastAttempted call
cc-hdrm/State/AppState.swift                      # ADD lastAttempted property + updateLastAttempted()
cc-hdrm/Views/PopoverView.swift                   # FIX: respect statusMessage for .disconnected, use lastAttempted
cc-hdrmTests/Services/APIClientTests.swift        # ADD 429 tests (with/without Retry-After, negative, non-integer)
cc-hdrmTests/Services/PollingEngineTests.swift    # ADD backoff + 429 + Low Power Mode + PopoverView tests
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on all PollingEngine tests (AppState is `@MainActor`)
- **Mock strategy:** Use existing `PEMockAPIClient` with result sequences to simulate consecutive failures and recovery
- **Backoff verification:** `computeNextInterval()` is `internal` (not private) for direct unit testing — same pattern as `evaluateWindow` in NotificationService
- **Low Power Mode:** Inject `isLowPowerModeEnabled: () -> Bool` in PollingEngine init. Tests pass `{ true }` or `{ false }` to control behavior without system dependency.
- **PopoverView tests:** Verify that `resolvedStatusMessage` respects `appState.statusMessage` for `.disconnected` state (rate limit message passes through, generic fallback only when nil)
- **Key test coverage:** See Task 7 subtasks for complete list
- **Regression:** All existing tests must continue passing (zero regressions). Note: existing PopoverView tests may need updating since `.disconnected` behavior changes (no longer always overrides).

### Library & Framework Requirements

- No new dependencies. Uses Foundation (`ProcessInfo`, `URLResponse` headers), os (`Logger`), existing project infrastructure.

### Anti-Patterns to Avoid

- DO NOT add a separate `.rateLimited` case to `ConnectionStatus` — use `.disconnected` with a descriptive status message (keeps the enum simple)
- DO NOT put backoff state in AppState — it's polling orchestration logic, belongs in PollingEngine
- DO NOT call `evaluateConnectivity` at all for 429 — calling `apiReachable: true` resets outage tracking (masks real outages in mixed-error scenarios), calling `apiReachable: false` is wrong since the API responded. Leave connectivity state unchanged.
- DO NOT call `evaluateOutageState` for 429 — rate limiting is not an outage
- DO NOT let `retryAfterOverride` persist across non-429 errors — clear it when a different error type occurs
- DO NOT use `ProcessInfo.processInfo.isLowPowerModeEnabled` directly — inject via closure for testability
- DO NOT add jitter in this story — keep backoff deterministic for testability (jitter can be added later if needed)
- DO NOT implement sleep/wake handling — separate concern, out of scope
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT use `DispatchQueue` or GCD — use async/await
- DO NOT use `print()` — use `os.Logger`
- DO NOT create a timer or separate Task for backoff — reuse the existing polling loop with dynamic interval

### References

- [Source: `_bmad-output/planning-artifacts/epics/epic-2-live-usage-data-pipeline.md` Story 2.2 lines 54-72] — Original backoff ACs (never implemented)
- [Source: `_bmad-output/planning-artifacts/architecture.md` line 427] — NFR5: API polling completes within 10 seconds per request
- [Source: `_bmad-output/planning-artifacts/architecture.md` line 441] — NFR13: Recovery within one polling cycle
- [Source: `_bmad-output/planning-artifacts/prd.md` lines 346-347] — FR4: Standard HTTP error handling (retry, timeout, graceful degradation)
- [Source: `cc-hdrm/Services/PollingEngine.swift`] — Current polling loop, handleAPIError, all error paths
- [Source: `cc-hdrm/Services/APIClient.swift` line 54] — 10-second request timeout, no 429 handling
- [Source: `cc-hdrm/Models/AppError.swift`] — Current error enum (no rateLimited case)
- [Source: `cc-hdrm/State/AppState.swift` line 251] — lastUpdated set only on success
- [Source: `cc-hdrm/Views/PopoverView.swift` lines 178-186] — resolvedStatusMessage uses lastUpdated (misleading)
- [Source: `cc-hdrm/Services/NotificationService.swift`] — evaluateConnectivity state machine (Story 5.4)
- [Source: `cc-hdrm/Services/HistoricalDataService.swift` lines 1796-1876] — evaluateOutageState (Story 10.6)
- [Source: `cc-hdrmTests/Services/PollingEngineTests.swift`] — Existing mock patterns (PEMockAPIClient, result sequences)
- [Source: `cc-hdrmTests/Services/APIClientTests.swift`] — Existing HTTP error tests (401, 500 patterns)
- [Source: `_bmad-output/planning-artifacts/research/technical-anthropic-api-surface-research-2026-02-24.md`] — Retry-After header documentation

## Dev Agent Record

### Agent Model Used

claude-opus-4-6

### Debug Log References

None

### Completion Notes List

- Added `AppError.rateLimited(retryAfter: Int?)` case with `Equatable` support
- APIClient now detects HTTP 429, parses `Retry-After` header (integer only), filters non-positive values to nil
- PollingEngine gains exponential backoff: `consecutiveFailureCount`, `retryAfterOverride`, injectable `isLowPowerModeEnabled`
- `computeNextInterval()` implements: base * 2^(failures-1), Retry-After floor, 3600s cap, Low Power Mode doubling, exponent capped at 10
- 429 handler: sets `.disconnected` + "Rate limited" message, does NOT call `evaluateConnectivity` or `evaluateOutageState`
- Non-429 errors increment failure count and clear `retryAfterOverride` (stale Retry-After doesn't persist)
- Success path resets `consecutiveFailureCount` and `retryAfterOverride` to zero/nil
- Added `AppState.lastAttempted` — updated before `fetchUsageData()`, not on credential-only failures
- PopoverView `.disconnected` case: passes through `appState.statusMessage` if set (e.g., "Rate limited"), falls back to generic "Unable to reach Claude API" with `lastAttempted` timestamp
- 20 new tests covering all ACs: 4 APIClient 429 tests, 16 PollingEngine backoff/rate-limit/Low-Power-Mode/PopoverView tests
- Default poll interval raised from 30s to 300s; max clamp raised from 300 to 1800; SettingsView picker extended with 600/900/1800 options
- Backoff cap raised from 300s to 3600s (1 hour) — 300s cap equals 300s base with no effective backoff
- All 1353 tests pass, zero regressions
- Code review: fixed evaluateConnectivity test (injected NotificationService mock), rewrote PopoverView tests as integration tests, removed extra usage clearing on 429

### Change Log

- 2026-03-05: Implemented Story 2.4 — Rate limit retry & exponential backoff (all 7 tasks, 6 ACs)
- 2026-03-05: Code review fixes — (1) documented default poll interval change 30s→300s and backoff cap 300s→3600s in story ACs and dev notes, (2) added 4 undocumented files to File List, (3) fixed evaluateConnectivity test to inject NotificationService mock, (4) rewrote PopoverView tests to exercise PollingEngine integration instead of testing appState directly, (5) stopped clearing extra usage state on 429 (rate limiting is transient)

### File List

Modified:
- cc-hdrm/Models/AppError.swift — Added `rateLimited(retryAfter:)` case + Equatable
- cc-hdrm/Services/APIClient.swift — 429 detection, Retry-After parsing, negative clamping
- cc-hdrm/Services/PollingEngine.swift — Backoff state, `computeNextInterval()`, `isLowPowerModeEnabled` injection, `.rateLimited` handler, `lastAttempted` call, dynamic polling interval
- cc-hdrm/Services/PreferencesManagerProtocol.swift — Default `pollInterval` changed from 30s to 300s
- cc-hdrm/Services/PreferencesManager.swift — Poll interval max clamp raised from 300 to 1800
- cc-hdrm/State/AppState.swift — `lastAttempted` property, `updateLastAttempted()`, `setLastAttempted()` (DEBUG)
- cc-hdrm/Views/PopoverView.swift — Respect statusMessage for `.disconnected`, use `lastAttempted`
- cc-hdrm/Views/SettingsView.swift — Added poll interval picker options 600s, 900s, 1800s
- cc-hdrmTests/Services/APIClientTests.swift — 4 new 429 tests (with/without/non-integer/negative Retry-After)
- cc-hdrmTests/Services/PollingEngineTests.swift — 16 new backoff + rate limit tests
- cc-hdrmTests/Services/PreferencesManagerTests.swift — Updated for new default poll interval and max clamp
