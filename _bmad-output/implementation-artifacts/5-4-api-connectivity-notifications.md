# Story 5.4: API Connectivity Notifications

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to be notified when the Claude API becomes unreachable and when it recovers,
so that I know about Anthropic service disruptions even when I'm not looking at the menu bar.

## Acceptance Criteria

1. **Given** the app is connected and polling successfully, **When** 2+ consecutive poll cycles fail with API-unreachable errors (network failure, HTTP 5xx, parse error — NOT credential errors or 401/token expiry), **Then** a macOS notification fires with title "Claude API unreachable" and body "Monitoring continues — you'll be notified when it recovers" **And** the notification fires once per outage (not repeated during ongoing outage).

2. **Given** the app is in outage state (2+ consecutive API failures, outage notification already sent), **When** a poll cycle succeeds, **Then** a macOS notification fires with title "Claude API is back" and body "Service restored — usage data is current" **And** the outage state resets (consecutive failure count returns to zero, notification re-armed).

3. **Given** the user has denied notification permissions, **When** a connectivity transition occurs (outage or recovery), **Then** no notification is attempted (visual fallback via menu bar disconnected state).

4. **Given** notifications are enabled, **When** the user opens settings, **Then** an "API status alerts" toggle is available (default: on) **And** when toggled off, connectivity notifications are suppressed but failure tracking continues silently **And** when toggled back on, fire-once semantics still apply (no retroactive notification for ongoing outage).

## Tasks / Subtasks

- [x] Task 1: Add `apiStatusAlertsEnabled` preference (AC: 4)
  - [x] 1.1 In `cc-hdrm/Services/PreferencesManagerProtocol.swift`: add `var apiStatusAlertsEnabled: Bool { get set }` to protocol, add `static let apiStatusAlertsEnabled: Bool = true` to `PreferencesDefaults`
  - [x] 1.2 In `cc-hdrm/Services/PreferencesManager.swift`: add key `"com.cc-hdrm.apiStatusAlertsEnabled"`, implement getter with nil-coalescing default pattern (same as `extraUsageAlertsEnabled`), add `defaults.removeObject` in `resetToDefaults()`
  - [x] 1.3 In `cc-hdrmTests/Mocks/MockPreferencesManager.swift`: add `var apiStatusAlertsEnabled: Bool = PreferencesDefaults.apiStatusAlertsEnabled`, reset in `resetToDefaults()`

- [x] Task 2: Add `evaluateConnectivity` to NotificationService (AC: 1, 2, 3)
  - [x] 2.1 In `cc-hdrm/Services/NotificationServiceProtocol.swift`: add `func evaluateConnectivity(apiReachable: Bool) async` to protocol
  - [x] 2.2 In `cc-hdrm/Services/NotificationService.swift`: add private state — `private var consecutiveFailureCount: Int = 0` and `private var hasNotifiedOutage: Bool = false`
  - [x] 2.3 Implement `evaluateConnectivity(apiReachable:)` with logic:
    - If `apiReachable == true`: if `hasNotifiedOutage` is true AND `apiStatusAlertsEnabled` → send recovery notification; reset `consecutiveFailureCount = 0` and `hasNotifiedOutage = false`
    - If `apiReachable == false`: increment `consecutiveFailureCount`; if count >= 2 AND `!hasNotifiedOutage` → set `hasNotifiedOutage = true`; if `apiStatusAlertsEnabled` → send outage notification
  - [x] 2.4 Create private `sendConnectivityNotification(title:body:identifier:)` method using `notificationCenter.add(request)` — checks `isAuthorized` guard, uses `os.Logger` for delivery logging. Notification identifiers: `"api-outage"` and `"api-recovered"`

- [x] Task 3: Wire `evaluateConnectivity` in PollingEngine (AC: 1, 2)
  - [x] 3.1 In `cc-hdrm/Services/PollingEngine.swift` `fetchUsageData` success path: add `await notificationService?.evaluateConnectivity(apiReachable: true)` after `appState.updateConnectionStatus(.connected)`
  - [x] 3.2 In `handleAPIError` for `.networkUnreachable`, non-401 `.apiError`, `.parseError`, and `default` cases: add `await notificationService?.evaluateConnectivity(apiReachable: false)` after updating connection status
  - [x] 3.3 In `handleAPIError` for `.apiError(statusCode: 401, _)`: do NOT call `evaluateConnectivity` — 401 means the API IS reachable, it's an auth issue handled by token refresh
  - [x] 3.4 In `handleCredentialError`: do NOT call `evaluateConnectivity` — no API call was made, this is a credential issue
  - [x] 3.5 In the unexpected non-AppError catch block at line 288: add `await notificationService?.evaluateConnectivity(apiReachable: false)`

- [x] Task 4: Update MockNotificationService (AC: 1, 2)
  - [x] 4.1 In `cc-hdrmTests/Mocks/MockNotificationService.swift`: add `var evaluateConnectivityCalls: [Bool] = []` and implement `func evaluateConnectivity(apiReachable: Bool) async` appending to the array

- [x] Task 5: Add "API status alerts" toggle to SettingsView (AC: 4)
  - [x] 5.1 In `cc-hdrm/Views/SettingsView.swift`: add `@State private var apiStatusAlertsEnabled: Bool` property, initialize from `preferencesManager.apiStatusAlertsEnabled` in `init`
  - [x] 5.2 Add toggle after critical threshold stepper, before Extra Usage Alerts section:
    ```swift
    Toggle("API status alerts", isOn: $apiStatusAlertsEnabled)
        .onChange(of: apiStatusAlertsEnabled) { _, newValue in
            preferencesManager.apiStatusAlertsEnabled = newValue
        }
        .accessibilityLabel("API status alerts, \(apiStatusAlertsEnabled ? "on" : "off")")
    ```
  - [x] 5.3 In Reset to Defaults handler: add `apiStatusAlertsEnabled = preferencesManager.apiStatusAlertsEnabled`

- [x] Task 6: Write comprehensive tests (AC: 1-4)
  - [x] 6.1 Create `cc-hdrmTests/Services/ConnectivityNotificationTests.swift` — new test file for connectivity notification logic
  - [x] 6.2 Test: 1 failure → no notification (threshold is 2)
  - [x] 6.3 Test: 2 consecutive failures → outage notification sent with correct title/body/identifier
  - [x] 6.4 Test: 3+ failures → no additional notification (fire-once)
  - [x] 6.5 Test: 2 failures then success → recovery notification sent with correct title/body/identifier
  - [x] 6.6 Test: Success without prior outage → no recovery notification
  - [x] 6.7 Test: `isAuthorized = false` → no notification on outage or recovery
  - [x] 6.8 Test: `apiStatusAlertsEnabled = false` → no notification on outage or recovery, but state still tracks (counter increments, hasNotifiedOutage set)
  - [x] 6.9 Test: Toggle `apiStatusAlertsEnabled` from false to true mid-outage → no retroactive notification sent (hasNotifiedOutage already true)
  - [x] 6.10 Test: After recovery, new outage → outage notification fires again (re-armed)
  - [x] 6.11 Test: Outage notification identifier is `"api-outage"`, recovery is `"api-recovered"`
  - [x] 6.12 Test: Interleaved success/failure (success, fail, success, fail) → never reaches threshold 2
  - [x] 6.13 Test: Connectivity notifications don't interfere with headroom threshold notifications (both can fire independently)
  - [x] 6.14 Test: PollingEngine calls `evaluateConnectivity(apiReachable: true)` on successful fetch
  - [x] 6.15 Test: PollingEngine calls `evaluateConnectivity(apiReachable: false)` on network error
  - [x] 6.16 Test: PollingEngine does NOT call `evaluateConnectivity` on 401 (handled by token refresh)
  - [x] 6.17 Test: PollingEngine does NOT call `evaluateConnectivity` on credential error (no API call made)
  - [x] 6.18 Run `xcodegen generate` after creating new test file

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. NotificationService is MODIFIED (not replaced). Connectivity state machine lives inside NotificationService per architecture boundary — `NotificationService` is the ONLY component that imports `UserNotifications`. [Source: `_bmad-output/planning-artifacts/architecture.md` line 488]
- **Boundary:** PollingEngine reports success/failure via `evaluateConnectivity(apiReachable:)`. NotificationService decides when to notify. PollingEngine never imports UserNotifications.
- **State flow:** PollingEngine → `evaluateConnectivity` → NotificationService (internal state machine) → macOS notification. Same one-way flow as threshold notifications.
- **Concurrency:** `@MainActor` consistent with all services. `async` for notification delivery.
- **Logging:** `os.Logger`, subsystem `com.cc-hdrm.app`, category `notification`. Log `.info` on outage detection and notification delivery. Log `.debug` on failure count increments.

### Key Implementation Details

**What counts as "API unreachable" vs. "auth issue":**

The "2+ consecutive poll cycles fail" threshold should only count failures where the API itself is unreachable or broken, NOT authentication/credential issues:

| Error | Counts as failure? | Reason |
|-------|-------------------|--------|
| `networkUnreachable` | YES | Can't reach API |
| `apiError(5xx)` | YES | Server error |
| `apiError(non-401)` | YES | API error |
| `parseError` | YES | API returned unparseable response |
| `apiError(401)` | NO | API IS reachable, auth issue → handled by token refresh |
| Credential errors (`keychainNotFound`, etc.) | NO | No API call was made |

This mapping is implemented by WHERE `evaluateConnectivity` is called in PollingEngine — see Task 3 subtasks.

**Connectivity state machine in NotificationService:**

```swift
// State (private to NotificationService):
private var consecutiveFailureCount: Int = 0
private var hasNotifiedOutage: Bool = false

// State transitions:
func evaluateConnectivity(apiReachable: Bool) async {
    if apiReachable {
        if hasNotifiedOutage {
            // Recovery: send "API is back" notification (if authorized + enabled)
            await sendConnectivityNotification(
                title: "Claude API is back",
                body: "Service restored — usage data is current",
                identifier: "api-recovered"
            )
        }
        consecutiveFailureCount = 0
        hasNotifiedOutage = false
    } else {
        consecutiveFailureCount += 1
        if consecutiveFailureCount >= 2 && !hasNotifiedOutage {
            hasNotifiedOutage = true
            // Outage: send "API unreachable" notification (if authorized + enabled)
            await sendConnectivityNotification(
                title: "Claude API unreachable",
                body: "Monitoring continues — you'll be notified when it recovers",
                identifier: "api-outage"
            )
        }
    }
}
```

**Notification delivery method:**

```swift
private func sendConnectivityNotification(title: String, body: String, identifier: String) async {
    guard isAuthorized else {
        Self.logger.info("Skipping connectivity notification — not authorized")
        return
    }
    guard preferencesManager.apiStatusAlertsEnabled else {
        Self.logger.info("Skipping connectivity notification — API status alerts disabled")
        return
    }

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    // No sound for connectivity notifications — informational, not urgent

    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

    do {
        try await notificationCenter.add(request)
        Self.logger.info("Connectivity notification delivered: \(identifier, privacy: .public)")
    } catch {
        Self.logger.error("Failed to deliver connectivity notification: \(error.localizedDescription)")
    }
}
```

**PollingEngine wiring points:**

In `fetchUsageData`, success path (after line 217 `appState.updateConnectionStatus(.connected)`):
```swift
await notificationService?.evaluateConnectivity(apiReachable: true)
```

In `handleAPIError`, for each non-401 case (after `appState.updateConnectionStatus(.disconnected)`):
```swift
await notificationService?.evaluateConnectivity(apiReachable: false)
```

In the catch block for unexpected non-AppError (after line 289):
```swift
await notificationService?.evaluateConnectivity(apiReachable: false)
```

**NOT wired in:**
- `handleAPIError` case `.apiError(statusCode: 401, _)` — routes to `attemptTokenRefresh`, API was reachable
- `handleCredentialError` — no API call was made

**Notification identifiers rationale:**

- `"api-outage"` — reuses same identifier for each outage notification. If a previous outage notification is still in Notification Center, it gets replaced (not stacked). This is correct because only one outage can be active at a time.
- `"api-recovered"` — reuses same identifier for recovery. Replaces any previous recovery notification.
- These are completely distinct from headroom identifiers (`"headroom-warning-*"`, `"headroom-critical-*"`), so connectivity and headroom notifications never interfere.

**Settings toggle placement:**

The "API status alerts" toggle goes in `SettingsView` after the critical threshold stepper and before the Extra Usage Alerts section. It's a simple on/off toggle, no sub-toggles. This groups it with other notification-related settings.

### Previous Story Intelligence (5.3)

**What was built:**
- `ThresholdState` enum: `aboveWarning`, `warned20`, `warned5` — defined in `cc-hdrm/Services/NotificationServiceProtocol.swift`
- Full state machine in `evaluateWindow` (internal visibility for testing)
- `deliverNotification` shared method for both warning and critical notifications
- `evaluateThresholds(fiveHour:sevenDay:)` wired into PollingEngine via `notificationService?.evaluateThresholds(...)`
- `NotificationCenterProtocol` + `SpyNotificationCenter` for testable notification delivery
- Configurable thresholds via `PreferencesManager.warningThreshold`/`criticalThreshold`
- `reevaluateThresholds()` for instant feedback on threshold changes

**Code review lessons from story 5.3:**
- Refactored duplicate `sendNotification`/`sendCriticalNotification` into shared `deliverNotification` — follow this pattern for the new connectivity notification method
- `evaluateWindow` is `internal` (not private) for direct unit-test access — consider making `evaluateConnectivity` also `internal` for direct testing
- Tests use `SpyNotificationCenter` to verify notification delivery — reuse same pattern

**Patterns to follow:**
- `SpyNotificationCenter` captures `addedRequests: [UNNotificationRequest]` for verification
- Test assertions check `spy.addedRequests.count`, `.first?.content.title`, `.first?.content.body`, `.first?.identifier`
- MockNotificationService in `cc-hdrmTests/Mocks/MockNotificationService.swift` needs `evaluateConnectivity` method added

### Git Intelligence

Recent commits:
- `fc21a55` feat: clickable ring gauges as analytics launchers (Story 4.6)
- `28d1248` feat: first-run onboarding popup, README rewrite, app icon (Story 18.3)
- `3569a3a` [patch] fix: changelog generation uses wrong git log range
- `39ce3fc` [patch] feat: OAuth profile fetch for tier resolution (Story 18.2)

**Patterns:**
- PRs use squash merge with descriptive titles
- Story numbering in commit messages
- XcodeGen auto-discovers new files — run `xcodegen generate` after adding files

### Project Structure Notes

- `cc-hdrm/Services/NotificationService.swift` (253 lines) — will be MODIFIED: add `consecutiveFailureCount`, `hasNotifiedOutage`, `evaluateConnectivity`, `sendConnectivityNotification`
- `cc-hdrm/Services/NotificationServiceProtocol.swift` (34 lines) — will be MODIFIED: add `evaluateConnectivity(apiReachable:)` to protocol
- `cc-hdrm/Services/PollingEngine.swift` (395 lines) — will be MODIFIED: add `evaluateConnectivity` calls in success and failure paths
- `cc-hdrm/Services/PreferencesManagerProtocol.swift` (79 lines) — will be MODIFIED: add `apiStatusAlertsEnabled` to protocol and defaults
- `cc-hdrm/Services/PreferencesManager.swift` (366 lines) — will be MODIFIED: add key, getter/setter, resetToDefaults entry
- `cc-hdrm/Views/SettingsView.swift` (498 lines) — will be MODIFIED: add @State property, toggle, reset handler
- `cc-hdrmTests/Mocks/MockNotificationService.swift` (23 lines) — will be MODIFIED: add `evaluateConnectivity` tracking
- `cc-hdrmTests/Mocks/MockPreferencesManager.swift` (55 lines) — will be MODIFIED: add `apiStatusAlertsEnabled` property + reset
- `cc-hdrmTests/Services/ConnectivityNotificationTests.swift` — NEW FILE: connectivity notification tests

### File Structure Requirements

Files to modify:
```
cc-hdrm/Services/NotificationServiceProtocol.swift   # ADD evaluateConnectivity to protocol
cc-hdrm/Services/NotificationService.swift            # ADD connectivity state machine + notification delivery
cc-hdrm/Services/PollingEngine.swift                  # ADD evaluateConnectivity calls at success/failure points
cc-hdrm/Services/PreferencesManagerProtocol.swift     # ADD apiStatusAlertsEnabled to protocol + defaults
cc-hdrm/Services/PreferencesManager.swift             # ADD apiStatusAlertsEnabled key/getter/setter/reset
cc-hdrm/Views/SettingsView.swift                      # ADD API status alerts toggle
cc-hdrmTests/Mocks/MockNotificationService.swift      # ADD evaluateConnectivity tracking
cc-hdrmTests/Mocks/MockPreferencesManager.swift       # ADD apiStatusAlertsEnabled + reset
```

Files to create:
```
cc-hdrmTests/Services/ConnectivityNotificationTests.swift  # NEW — connectivity notification tests
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on ALL tests (NotificationService is `@MainActor`)
- **Mock strategy:** Use existing `SpyNotificationCenter` to verify connectivity notification delivery — check `addedRequests` for content with correct title/body and identifiers `"api-outage"` / `"api-recovered"`
- **Key test scenarios:** See Task 6 subtasks above for complete list
- **Integration:** Use `MockNotificationService` in PollingEngine tests to verify `evaluateConnectivity` is called at the right times with the right arguments
- **Regression:** All ~1377 existing tests must continue passing (zero regressions)
- **Run `xcodegen generate`** after creating the new test file

### Library & Framework Requirements

- `UserNotifications` — already imported in `cc-hdrm/Services/NotificationService.swift`. No new framework imports needed.
- No new external dependencies. Zero external packages.

### Anti-Patterns to Avoid

- DO NOT put connectivity failure tracking in AppState — keep it in NotificationService per architecture boundary (notification logic stays in notification service)
- DO NOT count 401 errors as "API unreachable" — 401 means the API IS reachable, it's an auth issue handled by token refresh
- DO NOT count credential errors as "API unreachable" — no API call was made
- DO NOT fire connectivity notifications repeatedly during ongoing outage — fire once, then wait for recovery
- DO NOT fire retroactive outage notification when user toggles `apiStatusAlertsEnabled` back on during an existing outage
- DO NOT add sound to connectivity notifications — these are informational, not urgent like critical headroom alerts
- DO NOT use headroom notification identifiers (`"headroom-warning-*"`, `"headroom-critical-*"`) — use distinct `"api-outage"` and `"api-recovered"` identifiers
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT use `DispatchQueue` or GCD — use async/await
- DO NOT use `print()` — use `os.Logger`
- DO NOT cache or persist connectivity state across app launches — state resets on launch (counter = 0, hasNotifiedOutage = false)
- DO NOT call `evaluateConnectivity` from `handleCredentialError` in PollingEngine — no API call was made, can't determine API reachability

### References

- [Source: `_bmad-output/planning-artifacts/epics/epic-5-threshold-notifications.md` Story 5.4] — Full acceptance criteria for API connectivity notifications
- [Source: `_bmad-output/planning-artifacts/architecture.md` line 210] — Notification Strategy: UserNotifications, fire once per crossing, re-arm on recovery
- [Source: `_bmad-output/planning-artifacts/architecture.md` line 488] — NotificationService is the ONLY component importing UserNotifications
- [Source: `_bmad-output/planning-artifacts/project-context.md` Architectural Boundaries] — NotificationService boundary
- [Source: `cc-hdrm/Services/NotificationService.swift`] — Current implementation with evaluateWindow, deliverNotification, evaluateThresholds
- [Source: `cc-hdrm/Services/NotificationServiceProtocol.swift`] — ThresholdState enum, protocol with evaluateThresholds, reevaluateThresholds
- [Source: `cc-hdrm/Services/NotificationCenterProtocol.swift`] — Protocol abstraction over UNUserNotificationCenter
- [Source: `cc-hdrm/Services/PollingEngine.swift`] — Poll cycle orchestration, handleAPIError, handleCredentialError
- [Source: `cc-hdrm/Services/PreferencesManager.swift`] — Existing preference pattern (extraUsageAlertsEnabled)
- [Source: `cc-hdrm/Services/PreferencesManagerProtocol.swift`] — Protocol + PreferencesDefaults enum
- [Source: `cc-hdrm/Views/SettingsView.swift`] — Existing toggle pattern (extraUsageAlertsEnabled toggle)
- [Source: `cc-hdrmTests/Mocks/SpyNotificationCenter.swift`] — Spy for notification delivery verification
- [Source: `cc-hdrmTests/Mocks/MockNotificationService.swift`] — Mock for PollingEngine tests
- [Source: `cc-hdrmTests/Mocks/MockPreferencesManager.swift`] — Mock for preferences in tests
- [Source: `cc-hdrmTests/Services/ThresholdStateMachineTests.swift`] — Existing notification test patterns to follow
- [Source: `_bmad-output/planning-artifacts/epics/epic-10-data-persistence-historical-storage-phase-3.md` Story 10.6] — Downstream story: outage period persistence (depends on consecutive failure tracking established here)
- [Source: `_bmad-output/planning-artifacts/epics/epic-13-full-analytics-window-phase-3.md` Story 13.8] — Downstream story: outage background rendering in charts

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (claude-opus-4-6)

### Debug Log References

No issues encountered during implementation.

### Completion Notes List

- Implemented connectivity state machine in NotificationService with `consecutiveFailureCount` and `outageDetected` / `outageNotificationDelivered` private state
- Added `evaluateConnectivity(apiReachable:)` to protocol and implementation with fire-once outage notification at 2+ consecutive failures and recovery notification on success after outage
- Added `sendConnectivityNotification` private method with `isAuthorized` and `apiStatusAlertsEnabled` guards, returns `Bool` for delivery tracking, no sound (informational)
- Recovery notification only fires when outage notification was actually delivered (prevents orphan "API is back" when outage was silently suppressed)
- Wired `evaluateConnectivity` calls in PollingEngine: `apiReachable: true` on success, `apiReachable: false` on networkUnreachable/apiError(non-401)/parseError/default/unexpected errors. NOT wired for 401 (auth issue) or credential errors (no API call made)
- Added `apiStatusAlertsEnabled` preference (default: true) to protocol, PreferencesManager, and MockPreferencesManager with resetToDefaults support
- Added "API status alerts" toggle in SettingsView after critical threshold stepper, before Extra Usage Alerts section, with Reset to Defaults support
- Created 18 comprehensive tests in ConnectivityNotificationTests.swift covering: threshold behavior, fire-once semantics, recovery, authorization guard, preference toggle, re-arming, interleaved patterns, headroom independence, and PollingEngine integration (including parseError and 500 server error paths)
- All 1285 tests pass (18 new + 1267 existing), zero regressions

### Change Log

- 2026-03-03: Implemented Story 5.4 — API connectivity notifications with outage/recovery state machine, PollingEngine wiring, settings toggle, and 16 comprehensive tests
- 2026-03-03: Code review fixes — separated outage detection from notification delivery tracking to prevent orphan recovery notifications, renamed hasNotifiedOutage to outageDetected/outageNotificationDelivered, extended tests 6.8 and 6.9 with state-tracking and orphan-recovery verification, added PollingEngine integration tests for parseError and apiError(500)

### File List

Modified:
- cc-hdrm/Services/PreferencesManagerProtocol.swift — Added `apiStatusAlertsEnabled` to protocol and `PreferencesDefaults`
- cc-hdrm/Services/PreferencesManager.swift — Added key, getter/setter, resetToDefaults for `apiStatusAlertsEnabled`
- cc-hdrm/Services/NotificationServiceProtocol.swift — Added `evaluateConnectivity(apiReachable:)` to protocol
- cc-hdrm/Services/NotificationService.swift — Added connectivity state machine, `evaluateConnectivity`, `sendConnectivityNotification`
- cc-hdrm/Services/PollingEngine.swift — Wired `evaluateConnectivity` calls in success and failure paths
- cc-hdrm/Views/SettingsView.swift — Added `apiStatusAlertsEnabled` @State property, toggle, and reset handler
- cc-hdrmTests/Mocks/MockNotificationService.swift — Added `evaluateConnectivityCalls` tracking
- cc-hdrmTests/Mocks/MockPreferencesManager.swift — Added `apiStatusAlertsEnabled` property and reset

Created:
- cc-hdrmTests/Services/ConnectivityNotificationTests.swift — 18 tests for connectivity notification logic and PollingEngine integration
