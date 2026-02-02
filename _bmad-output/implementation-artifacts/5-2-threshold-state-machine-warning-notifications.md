# Story 5.2: Threshold State Machine & Warning Notifications

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to receive a macOS notification when my headroom drops below 20%,
so that I can make informed decisions about which Claude sessions to prioritize.

## Acceptance Criteria

1. **Given** 5-hour headroom is above 20%, **When** a poll cycle reports 5-hour headroom below 20%, **Then** a macOS notification fires: "Claude headroom at [X]% — resets in [relative] (at [absolute])" (FR17, FR19) **And** the notification is standard (not persistent, no sound) **And** the threshold state transitions from `ABOVE_20` to `WARNED_20`.

2. **Given** the 5-hour threshold state is `WARNED_20`, **When** subsequent poll cycles report headroom still below 20% but above 5%, **Then** no additional notification fires (fire once per crossing).

3. **Given** 7-day headroom drops below 20% independently of 5-hour, **When** a poll cycle reports the crossing, **Then** a separate notification fires: "Claude 7-day headroom at [X]% — resets in [relative] (at [absolute])" **And** 5h and 7d threshold states are tracked independently.

4. **Given** headroom recovers above 20% (window reset), **When** a poll cycle reports the recovery, **Then** the threshold state resets to `ABOVE_20` (re-armed) **And** if headroom drops below 20% again, a new notification fires.

5. **Given** notification permission was denied by the user, **When** a threshold crossing occurs, **Then** no notification is attempted, no error is shown **And** the menu bar color/weight changes still reflect the state (visual fallback).

## Tasks / Subtasks

- [x] Task 1: Define ThresholdState enum and extend NotificationServiceProtocol (AC: #1-#4)
  - [x] Create `ThresholdState` enum in `cc-hdrm/Services/NotificationServiceProtocol.swift`: `aboveWarning`, `warned20`, `warned5`
  - [x] Extend `NotificationServiceProtocol` with `evaluateThresholds(fiveHour:sevenDay:)` method
  - [x] Add read-only state accessors for testability: `fiveHourThresholdState`, `sevenDayThresholdState`

- [x] Task 2: Implement threshold state machine in NotificationService (AC: #1-#4)
  - [x] Add private properties: `fiveHourThreshold: ThresholdState = .aboveWarning`, `sevenDayThreshold: ThresholdState = .aboveWarning`
  - [x] Implement `evaluateThresholds(fiveHour:sevenDay:)`:
    1. Extract headroom from each `WindowState` (headroom = 100 - utilization)
    2. For each window independently, evaluate state transitions:
       - `aboveWarning` + headroom < 20% → transition to `warned20`, fire notification
       - `warned20` + headroom < 5% → transition to `warned5` (DO NOT fire — that's Story 5.3)
       - `warned20` or `warned5` + headroom >= 20% → transition to `aboveWarning` (re-arm)
       - All other combinations → no action
    3. Skip notification delivery if `!isAuthorized` (AC #5)
  - [x] Use `os.Logger` to log every state transition with window name and headroom value

- [x] Task 3: Implement notification delivery (AC: #1, #3)
  - [x] Create private `sendNotification(window:headroom:resetsAt:)` method
  - [x] Build `UNMutableNotificationContent`:
    - `title`: `"cc-hdrm"`
    - `body`: `"Claude [window] headroom at [X]% — resets in [relative] (at [absolute])"` where:
      - `[window]` = `""` for 5h (implied), `"7-day "` for 7d
      - `[X]` = headroom integer
      - `[relative]` = `resetsAt.countdownString()` (from `cc-hdrm/Extensions/Date+Formatting.swift`)
      - `[absolute]` = `resetsAt.absoluteTimeString()` (from `cc-hdrm/Extensions/Date+Formatting.swift`)
    - `sound`: `nil` (standard notification, no sound — sound is for Story 5.3 critical)
  - [x] Create `UNNotificationRequest` with unique identifier per window (e.g., `"headroom-warning-5h"`, `"headroom-warning-7d"`)
  - [x] Deliver via `notificationCenter.add(request)`
  - [x] Log delivery success/failure

- [x] Task 4: Wire threshold evaluation into PollingEngine (AC: #1-#4)
  - [x] Add `notificationService: (any NotificationServiceProtocol)?` to `PollingEngine` init
  - [x] After each successful poll cycle that updates AppState, call `notificationService?.evaluateThresholds(fiveHour:sevenDay:)` with the current window states
  - [x] Update `PollingEngineProtocol` if needed
  - [x] Update AppDelegate to pass `notificationService` to `PollingEngine`

- [x] Task 5: Write comprehensive tests (AC: #1-#5)
  - [x] Test: Initial state is `aboveWarning` for both windows
  - [x] Test: Headroom drops from 25% to 18% → state becomes `warned20`, notification sent
  - [x] Test: Headroom stays at 15% after warning → no additional notification
  - [x] Test: Headroom recovers to 22% → state resets to `aboveWarning`
  - [x] Test: After re-arm, headroom drops to 19% → new notification fires
  - [x] Test: 5h and 7d tracked independently — 5h warning doesn't affect 7d state
  - [x] Test: 7d crossing produces notification with "7-day" in body text
  - [x] Test: `isAuthorized = false` → no notification attempted on crossing
  - [x] Test: `nil` WindowState → no crash, no state change
  - [x] Test: Notification content format matches spec (title, body with countdown + absolute time)
  - [x] Test: Headroom at exactly 20% does NOT trigger (must be below 20%)

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. NotificationService is extended (not replaced) from Story 5.1. Threshold state machines live inside NotificationService, NOT AppState — per architecture boundary (`_bmad-output/planning-artifacts/architecture.md` line 532).
- **Boundary:** NotificationService remains the ONLY component importing `UserNotifications`.
- **State flow:** PollingEngine calls NotificationService after each successful fetch. NotificationService reads WindowState values passed to it — it does NOT observe AppState directly.
- **Concurrency:** `@MainActor` consistent with all services. `async` for notification delivery.
- **Logging:** `os.Logger`, subsystem `com.cc-hdrm.app`, category `notification`. Log `.info` on threshold crossings and notification delivery.

### Key Implementation Details

**ThresholdState enum:**
```swift
enum ThresholdState: String, Sendable {
    case aboveWarning   // Headroom >= 20%, both thresholds armed
    case warned20       // Warning fired, headroom < 20%, critical armed
    case warned5        // Critical fired (Story 5.3), headroom < 5%
}
```

**Threshold evaluation logic (per window):**
```swift
private func evaluateWindow(
    currentState: ThresholdState,
    headroom: Double,
    windowLabel: String,
    resetsAt: Date?
) -> (ThresholdState, shouldFireWarning: Bool) {
    switch currentState {
    case .aboveWarning:
        if headroom < 20 {
            return (.warned20, shouldFireWarning: true)
        }
        return (.aboveWarning, shouldFireWarning: false)
    case .warned20:
        if headroom >= 20 {
            return (.aboveWarning, shouldFireWarning: false) // re-arm
        }
        if headroom < 5 {
            return (.warned5, shouldFireWarning: false) // critical handled in 5.3
        }
        return (.warned20, shouldFireWarning: false)
    case .warned5:
        if headroom >= 20 {
            return (.aboveWarning, shouldFireWarning: false) // re-arm both
        }
        return (.warned5, shouldFireWarning: false)
    }
}
```

**Notification content construction:**
```swift
private func sendNotification(window: String, headroom: Int, resetsAt: Date?) async {
    guard isAuthorized else { return }
    
    let content = UNMutableNotificationContent()
    content.title = "cc-hdrm"
    
    let windowPrefix = window == "7d" ? "7-day " : ""
    var body = "Claude \(windowPrefix)headroom at \(headroom)%"
    
    if let resetsAt {
        body += " — resets in \(resetsAt.countdownString()) (\(resetsAt.absoluteTimeString()))"
    }
    
    content.body = body
    // No sound for warning threshold (sound is Story 5.3 critical)
    
    let identifier = "headroom-warning-\(window)"
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    
    do {
        try await notificationCenter.add(request)
        Self.logger.info("Notification delivered: \(window, privacy: .public) headroom \(headroom)%")
    } catch {
        Self.logger.error("Failed to deliver notification: \(error.localizedDescription)")
    }
}
```

**PollingEngine integration point:**
After a successful fetch cycle in PollingEngine, add:
```swift
// After appState.updateWindows(fiveHour:sevenDay:)
await notificationService?.evaluateThresholds(
    fiveHour: fiveHourState,
    sevenDay: sevenDayState
)
```

### Extended Protocol

```swift
/// Protocol for the notification service that manages macOS notification authorization
/// and threshold-based notification delivery.
@MainActor
protocol NotificationServiceProtocol: Sendable {
    func requestAuthorization() async
    var isAuthorized: Bool { get }
    
    /// Evaluates headroom thresholds for both windows and fires notifications on crossings.
    func evaluateThresholds(fiveHour: WindowState?, sevenDay: WindowState?) async
    
    /// Current threshold state for 5-hour window (read-only, for testing).
    var fiveHourThresholdState: ThresholdState { get }
    /// Current threshold state for 7-day window (read-only, for testing).
    var sevenDayThresholdState: ThresholdState { get }
}
```

### Previous Story Intelligence (5.1)

**What was built:**
- NotificationServiceProtocol with `requestAuthorization()` and `isAuthorized`
- NotificationService with full authorization flow handling (authorized, denied, notDetermined, ephemeral)
- Injectable `notificationCenter` parameter for testability
- MockNotificationService in `cc-hdrmTests/Mocks/`
- AppDelegate wired: creates NotificationService, calls `requestAuthorization()` in Task block
- 235 tests passing, zero regressions

**Code review lessons from story 5.1:**
- Removed unnecessary `import Foundation` from protocol files — protocol files have zero imports
- Added `///` doc comments to protocol and its members
- Injected MockNotificationService in AppDelegateTests to prevent real UNUserNotificationCenter calls

**Patterns established:**
- NotificationService uses `private static let logger` with category `notification`
- Init takes `notificationCenter: UNUserNotificationCenter = .current()` for testability
- `@MainActor` on service class
- `private(set)` on state properties exposed to protocol

### Git Intelligence

Recent commits follow pattern: "Add story X.Y: [description] and code review fixes"
Last commit: `5b053d8 Add story 5.1: notification permission service setup and code review fixes`
XcodeGen auto-discovers new files — run `xcodegen generate` after adding files.

### Project Structure Notes

- NotificationService.swift EXISTS at `cc-hdrm/Services/NotificationService.swift` (54 lines) — will be MODIFIED to add threshold logic
- NotificationServiceProtocol.swift EXISTS at `cc-hdrm/Services/NotificationServiceProtocol.swift` (10 lines) — will be MODIFIED to add threshold methods
- MockNotificationService.swift EXISTS at `cc-hdrmTests/Mocks/MockNotificationService.swift` — will need UPDATING to conform to extended protocol
- PollingEngine.swift EXISTS at `cc-hdrm/Services/PollingEngine.swift` — will be MODIFIED to call evaluateThresholds
- AppDelegate.swift EXISTS at `cc-hdrm/App/AppDelegate.swift` — will be MODIFIED to pass notificationService to PollingEngine

### File Structure Requirements

Files to modify:
```
cc-hdrm/Services/NotificationServiceProtocol.swift   # EXTEND — add evaluateThresholds, threshold state accessors
cc-hdrm/Services/NotificationService.swift            # EXTEND — add ThresholdState enum, state machine, notification delivery
cc-hdrm/Services/PollingEngine.swift                  # MODIFY — add notificationService dependency, call evaluateThresholds after fetch
cc-hdrm/Services/PollingEngineProtocol.swift           # MODIFY if init signature changes
cc-hdrm/App/AppDelegate.swift                         # MODIFY — pass notificationService to PollingEngine
cc-hdrmTests/Mocks/MockNotificationService.swift       # EXTEND — add threshold mock properties
cc-hdrmTests/Services/NotificationServiceTests.swift   # EXTEND — add threshold state machine tests
```

No new files to create.

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on ALL tests (NotificationService is `@MainActor`)
- **Mock strategy:** Extend MockNotificationService to track `evaluateThresholds` calls and expose threshold states. For notification delivery testing, use the injectable `notificationCenter` — but note UNUserNotificationCenter is difficult to mock. Focus on state machine transitions and method call verification.
- **Key test scenarios:** See Task 5 subtasks above for complete list.
- **Boundary condition:** Headroom at exactly 20.0% should NOT trigger warning (must be strictly below 20%).
- **All existing tests must continue passing (zero regressions).**

### Library & Framework Requirements

- `UserNotifications` — already imported in `cc-hdrm/Services/NotificationService.swift` (Story 5.1). No new framework imports needed.
- `cc-hdrm/Extensions/Date+Formatting.swift` — `countdownString()` and `absoluteTimeString()` already exist and will be used for notification body.
- No new external dependencies. Zero external packages.

### Anti-Patterns to Avoid

- DO NOT put threshold state machines in AppState — they belong in NotificationService per architecture boundary
- DO NOT observe AppState from NotificationService — pass WindowState values explicitly via method call
- DO NOT fire notifications repeatedly for the same crossing — state machine enforces fire-once semantics
- DO NOT add sound to warning notifications — sound is for critical (5%) threshold in Story 5.3
- DO NOT implement the critical (5%) notification delivery in this story — only the state transition to `warned5` (delivery is Story 5.3)
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT use `DispatchQueue` or GCD — use async/await
- DO NOT use `print()` — use `os.Logger`
- DO NOT cache or persist threshold state across app launches — threshold state resets on launch (starts at `aboveWarning`)
- DO NOT skip headroom < 5% transition to `warned5` — the state transition must happen even though the notification delivery is deferred to Story 5.3

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 5.2] — Full acceptance criteria for threshold state machine and warning notifications
- [Source: _bmad-output/planning-artifacts/architecture.md#Notification Strategy] — Framework: UserNotifications, thresholds: 20% and 5%, fire once per crossing, re-arm on recovery, both windows tracked independently
- [Source: _bmad-output/planning-artifacts/architecture.md#line 532] — Threshold state machines live inside NotificationService, not AppState
- [Source: _bmad-output/planning-artifacts/architecture.md#line 533] — NotificationService reads from AppState to detect threshold crossings
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Threshold Notification Rules] — Fire once per crossing, reset on recovery, two thresholds (20%, 5%), both windows independent
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Notification Content Pattern] — "Claude [window] headroom at [X]% — resets in [relative] (at [absolute])"
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Notification Persistence] — Warning (20%): standard notification; Critical (5%): persistent with sound (Story 5.3)
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Threshold State Machine] — ABOVE_20 → WARNED_20 → WARNED_5, re-arm on recovery above 20%
- [Source: cc-hdrm/Services/NotificationService.swift] — Existing authorization logic, injectable notificationCenter
- [Source: cc-hdrm/Services/NotificationServiceProtocol.swift] — Current protocol with requestAuthorization and isAuthorized
- [Source: cc-hdrm/State/AppState.swift:14-22] — WindowState struct with utilization and resetsAt
- [Source: cc-hdrm/Models/HeadroomState.swift:24-35] — Headroom thresholds: >40% normal, 20-40% caution, 5-20% warning, <5% critical, 0% exhausted
- [Source: cc-hdrm/Extensions/Date+Formatting.swift:42-65] — countdownString() for notification body
- [Source: cc-hdrm/Extensions/Date+Formatting.swift:82-88] — absoluteTimeString() for notification body
- [Source: cc-hdrm/App/AppDelegate.swift:82-84] — NotificationService creation and wiring
- [Source: cc-hdrm/App/AppDelegate.swift:66-73] — PollingEngine creation with service injection
- [Source: _bmad-output/planning-artifacts/project-context.md#Architectural Boundaries] — NotificationService boundary: only component importing UserNotifications

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

- Build error: Swift 6 strict concurrency requires `self.` prefix in `os.Logger` string interpolation closures — fixed.
- Build error: Test file missing `import Foundation` for `Date` type — fixed.

### Completion Notes List

- ThresholdState enum defined in NotificationServiceProtocol.swift (colocated with protocol for visibility)
- NotificationServiceProtocol extended with `evaluateThresholds(fiveHour:sevenDay:)` and read-only threshold state accessors
- NotificationService implements full state machine: aboveWarning → warned20 → warned5, with re-arm on recovery >= 20%
- Notification delivery: title "cc-hdrm", body includes window prefix ("7-day " for 7d), headroom %, countdown, absolute time. No sound.
- PollingEngine wired: optional `notificationService` parameter (default nil), called after `appState.updateWindows`
- AppDelegate: NotificationService created before PollingEngine so it can be injected
- PollingEngineProtocol unchanged (init signature change doesn't affect protocol)
- 14 new threshold tests in ThresholdStateMachineTests.swift covering all AC scenarios
- MockNotificationService extended with threshold state properties and call tracking
- 249 total tests post-implementation, all passing, zero regressions (was 235 in story 5.1)
- Code review added 11 tests (notification delivery, content format, 7-day body, evaluateWindow direct, rounding) → 260 total

### Change Log

- 2026-02-01: Story 5.2 implemented — threshold state machine, warning notifications, PollingEngine wiring, 14 new tests
- 2026-02-01: Code review fixes — H1: added NotificationCenterProtocol + SpyNotificationCenter for notification delivery verification; H2: fixed Int(headroom) truncation → rounded(); M1: documented sprint-status.yaml in File List; M2/M3: added notification content format and 7-day body tests; L1: evaluateWindow made internal; L2: documented identifier reuse. 260 tests passing.

### File List

- cc-hdrm/Services/NotificationServiceProtocol.swift (modified — added ThresholdState enum, evaluateThresholds, threshold accessors)
- cc-hdrm/Services/NotificationService.swift (modified — added state machine, evaluateThresholds, sendNotification)
- cc-hdrm/Services/PollingEngine.swift (modified — added notificationService parameter, evaluateThresholds call)
- cc-hdrm/App/AppDelegate.swift (modified — moved NotificationService creation before PollingEngine, injected into PollingEngine)
- cc-hdrmTests/Mocks/MockNotificationService.swift (modified — added threshold state, evaluateThresholds tracking)
- cc-hdrmTests/Services/ThresholdStateMachineTests.swift (new — 14 threshold + 11 review tests = 25 total)
- cc-hdrm/Services/NotificationCenterProtocol.swift (new — protocol abstraction over UNUserNotificationCenter)
- cc-hdrmTests/Mocks/SpyNotificationCenter.swift (new — spy for notification delivery verification)
- _bmad-output/implementation-artifacts/sprint-status.yaml (modified — story 5.2 status update)
