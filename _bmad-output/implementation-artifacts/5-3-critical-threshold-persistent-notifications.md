# Story 5.3: Critical Threshold & Persistent Notifications

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to receive a persistent notification with sound when my headroom drops below 5%,
so that I have maximum warning to wrap up before hitting the limit.

## Acceptance Criteria

1. **Given** the threshold state is `WARNED_20` (already received 20% warning), **When** a poll cycle reports headroom below 5%, **Then** a persistent macOS notification fires with sound: "Claude headroom at [X]% — resets in [relative] (at [absolute])" (FR18, FR19) **And** the notification remains in Notification Center **And** the threshold state transitions from `WARNED_20` to `WARNED_5`.

2. **Given** headroom drops directly from above 20% to below 5% in a single poll, **When** the crossing is detected, **Then** only the critical (5%) notification fires (skip the 20% notification — go straight to the more urgent alert) **And** the threshold state transitions directly to `WARNED_5`.

3. **Given** the threshold state is `WARNED_5`, **When** subsequent poll cycles report headroom still below 5%, **Then** no additional notification fires.

4. **Given** headroom recovers above 20% after being in `WARNED_5`, **When** a poll cycle reports the recovery, **Then** both thresholds re-arm (state returns to `ABOVE_20`).

5. **Given** notification permission was denied by the user, **When** a threshold crossing occurs, **Then** no notification is attempted, no error is shown **And** the menu bar color/weight changes still reflect the state (visual fallback).

## Tasks / Subtasks

- [x] Task 1: Update `evaluateWindow` state machine for critical threshold notification firing (AC: #1, #2)
  - [x] In `cc-hdrm/cc-hdrm/Services/NotificationService.swift`, modify `evaluateWindow` to return a second flag `shouldFireCritical: Bool`
  - [x] `warned20` + headroom < 5% → transition to `warned5`, return `shouldFireCritical: true`
  - [x] `aboveWarning` + headroom < 5% → transition directly to `warned5`, return `shouldFireCritical: true` (skip warning)
  - [x] `aboveWarning` + headroom < 5% → `shouldFireWarning: false` (do NOT fire both — only critical)

- [x] Task 2: Create `sendCriticalNotification` delivery method (AC: #1)
  - [x] Create private `sendCriticalNotification(window:headroom:resetsAt:)` in `cc-hdrm/cc-hdrm/Services/NotificationService.swift`
  - [x] Build `UNMutableNotificationContent`:
    - `title`: `"cc-hdrm"`
    - `body`: `"Claude [window] headroom at [X]% — resets in [relative] (at [absolute])"` (same format as warning)
    - `sound`: `.default` (critical notifications include sound per UX spec)
  - [x] Use identifier `"headroom-critical-5h"` / `"headroom-critical-7d"` (distinct from warning identifiers to avoid replacement)
  - [x] Deliver via `notificationCenter.add(request)`
  - [x] Log delivery success/failure via `os.Logger`

- [x] Task 3: Wire critical notification in `evaluateThresholds` (AC: #1-#4)
  - [x] Update `evaluateThresholds(fiveHour:sevenDay:)` in `cc-hdrm/cc-hdrm/Services/NotificationService.swift` to handle the new `shouldFireCritical` return value
  - [x] Call `sendCriticalNotification` when `shouldFireCritical` is true
  - [x] Ensure re-arm logic (AC #4) continues working — recovery above 20% resets to `aboveWarning`, re-arming both thresholds

- [x] Task 4: Write comprehensive tests (AC: #1-#5)
  - [x] Test: `warned20` + headroom drops to 4% → state becomes `warned5`, critical notification sent with sound
  - [x] Test: `aboveWarning` + headroom drops directly to 3% → state becomes `warned5`, ONLY critical notification fires (no warning)
  - [x] Test: `warned5` + headroom stays at 2% → no additional notification
  - [x] Test: `warned5` + headroom recovers to 25% → state resets to `aboveWarning`
  - [x] Test: After re-arm from `warned5`, headroom drops to 4% again → warning fires at <20% (not critical directly unless skipping)
  - [x] Test: `isAuthorized = false` → no critical notification attempted on crossing
  - [x] Test: Critical notification content includes `.default` sound
  - [x] Test: Critical notification uses distinct identifier from warning (`"headroom-critical-5h"` vs `"headroom-warning-5h"`)
  - [x] Test: 5h and 7d critical thresholds tracked independently
  - [x] Test: `nil` WindowState → no crash, no state change
  - [x] Test: Headroom at exactly 5% does NOT trigger critical (must be strictly below 5%)
  - [x] Test: Critical notification body format matches spec — includes countdown and absolute time

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. NotificationService is modified (not replaced) from Story 5.2. Threshold state machines remain inside NotificationService, NOT AppState — per architecture boundary (`_bmad-output/planning-artifacts/architecture.md` line 532).
- **Boundary:** NotificationService remains the ONLY component importing `UserNotifications`.
- **State flow:** PollingEngine calls `evaluateThresholds` after each successful fetch (wired in Story 5.2). No changes to PollingEngine needed.
- **Concurrency:** `@MainActor` consistent with all services. `async` for notification delivery.
- **Logging:** `os.Logger`, subsystem `com.cc-hdrm.app`, category `notification`. Log `.info` on critical threshold crossings and notification delivery.

### Key Implementation Details

**Updated `evaluateWindow` signature:**
The current `evaluateWindow` returns `(ThresholdState, shouldFireWarning: Bool)`. This needs to be extended to also return a `shouldFireCritical` flag. Two approaches:

**Approach A — Tuple expansion:**
```swift
func evaluateWindow(
    currentState: ThresholdState,
    headroom: Double
) -> (ThresholdState, shouldFireWarning: Bool, shouldFireCritical: Bool) {
    switch currentState {
    case .aboveWarning:
        if headroom < 5 {
            // Skip warning, go straight to critical
            return (.warned5, shouldFireWarning: false, shouldFireCritical: true)
        }
        if headroom < 20 {
            return (.warned20, shouldFireWarning: true, shouldFireCritical: false)
        }
        return (.aboveWarning, shouldFireWarning: false, shouldFireCritical: false)
    case .warned20:
        if headroom >= 20 {
            return (.aboveWarning, shouldFireWarning: false, shouldFireCritical: false)
        }
        if headroom < 5 {
            return (.warned5, shouldFireWarning: false, shouldFireCritical: true)
        }
        return (.warned20, shouldFireWarning: false, shouldFireCritical: false)
    case .warned5:
        if headroom >= 20 {
            return (.aboveWarning, shouldFireWarning: false, shouldFireCritical: false)
        }
        return (.warned5, shouldFireWarning: false, shouldFireCritical: false)
    }
}
```

**Critical notification delivery:**
```swift
private func sendCriticalNotification(window: String, headroom: Int, resetsAt: Date?) async {
    guard isAuthorized else {
        Self.logger.info("Skipping critical notification — not authorized")
        return
    }

    let content = UNMutableNotificationContent()
    content.title = "cc-hdrm"

    let windowPrefix = window == "7d" ? "7-day " : ""
    var body = "Claude \(windowPrefix)headroom at \(headroom)%"

    if let resetsAt {
        body += " — resets in \(resetsAt.countdownString()) (\(resetsAt.absoluteTimeString()))"
    }

    content.body = body
    content.sound = .default  // Critical threshold includes sound

    let identifier = "headroom-critical-\(window)"
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

    do {
        try await notificationCenter.add(request)
        Self.logger.info("Critical notification delivered: \(window, privacy: .public) headroom \(headroom)%")
    } catch {
        Self.logger.error("Failed to deliver critical notification: \(error.localizedDescription)")
    }
}
```

**Updated `evaluateThresholds` integration:**
```swift
func evaluateThresholds(fiveHour: WindowState?, sevenDay: WindowState?) async {
    if let fiveHour {
        let headroom = 100.0 - fiveHour.utilization
        let (newState, shouldFireWarning, shouldFireCritical) = evaluateWindow(
            currentState: fiveHourThresholdState,
            headroom: headroom
        )
        if newState != fiveHourThresholdState {
            Self.logger.info("5h threshold: \(self.fiveHourThresholdState.rawValue, privacy: .public) → \(newState.rawValue, privacy: .public) (headroom \(headroom, format: .fixed(precision: 1))%)")
            fiveHourThresholdState = newState
        }
        if shouldFireWarning {
            await sendNotification(window: "5h", headroom: Int(headroom.rounded()), resetsAt: fiveHour.resetsAt)
        }
        if shouldFireCritical {
            await sendCriticalNotification(window: "5h", headroom: Int(headroom.rounded()), resetsAt: fiveHour.resetsAt)
        }
    }

    if let sevenDay {
        let headroom = 100.0 - sevenDay.utilization
        let (newState, shouldFireWarning, shouldFireCritical) = evaluateWindow(
            currentState: sevenDayThresholdState,
            headroom: headroom
        )
        if newState != sevenDayThresholdState {
            Self.logger.info("7d threshold: \(self.sevenDayThresholdState.rawValue, privacy: .public) → \(newState.rawValue, privacy: .public) (headroom \(headroom, format: .fixed(precision: 1))%)")
            sevenDayThresholdState = newState
        }
        if shouldFireWarning {
            await sendNotification(window: "7d", headroom: Int(headroom.rounded()), resetsAt: sevenDay.resetsAt)
        }
        if shouldFireCritical {
            await sendCriticalNotification(window: "7d", headroom: Int(headroom.rounded()), resetsAt: sevenDay.resetsAt)
        }
    }
}
```

### Previous Story Intelligence (5.2)

**What was built:**
- ThresholdState enum: `aboveWarning`, `warned20`, `warned5` — defined in `cc-hdrm/cc-hdrm/Services/NotificationServiceProtocol.swift`
- Full state machine in `evaluateWindow` (internal visibility for testing)
- Warning notification delivery via `sendNotification` — no sound, identifier `"headroom-warning-5h"` / `"headroom-warning-7d"`
- `evaluateThresholds(fiveHour:sevenDay:)` wired into PollingEngine
- NotificationCenterProtocol + SpyNotificationCenter for testable notification delivery
- 260 tests passing, zero regressions

**Code review lessons from story 5.2:**
- Added `NotificationCenterProtocol` abstraction over `UNUserNotificationCenter` for testable notification delivery — use `SpyNotificationCenter` in tests
- Fixed `Int(headroom)` truncation to `Int(headroom.rounded())` for correct rounding
- Made `evaluateWindow` `internal` (not private) for direct unit-test access
- Notification identifiers intentionally reuse per-window to replace undismissed notifications rather than stacking duplicates
- For critical notifications, use DIFFERENT identifiers (`"headroom-critical-*"`) from warning identifiers so critical doesn't replace the warning in Notification Center

**Patterns established:**
- `SpyNotificationCenter` captures `addedRequests: [UNNotificationRequest]` for verification
- Test assertions check `spy.addedRequests.count`, `spy.addedRequests.first?.content.body`, `spy.addedRequests.first?.content.sound`
- `evaluateWindow` can be tested directly (unit) without going through `evaluateThresholds` (integration)

### Git Intelligence

Recent commits follow pattern: "Add story X.Y: [description] and code review fixes"
Last commit: `b7d788f Add story 5.2: threshold state machine warning notifications and code review fixes`
XcodeGen auto-discovers new files — run `xcodegen generate` after adding files (only needed if NEW files created).

### Project Structure Notes

- `cc-hdrm/cc-hdrm/Services/NotificationService.swift` (155 lines) — will be MODIFIED to update `evaluateWindow` return type and add `sendCriticalNotification`
- `cc-hdrm/cc-hdrm/Services/NotificationServiceProtocol.swift` (30 lines) — NO changes needed (protocol and ThresholdState already support this story)
- `cc-hdrm/cc-hdrm/Services/PollingEngine.swift` — NO changes needed (already calls `evaluateThresholds`)
- `cc-hdrm/cc-hdrm/App/AppDelegate.swift` — NO changes needed (already wired)
- `cc-hdrm/cc-hdrmTests/Mocks/MockNotificationService.swift` — NO changes needed (already conforms to protocol)
- `cc-hdrm/cc-hdrmTests/Services/ThresholdStateMachineTests.swift` — will be EXTENDED with critical threshold tests
- `cc-hdrm/cc-hdrmTests/Mocks/SpyNotificationCenter.swift` — NO changes needed (already captures requests)
- `cc-hdrm/cc-hdrm/Services/NotificationCenterProtocol.swift` — NO changes needed

### File Structure Requirements

Files to modify:
```
cc-hdrm/cc-hdrm/Services/NotificationService.swift            # MODIFY — update evaluateWindow return type, add sendCriticalNotification, update evaluateThresholds
cc-hdrm/cc-hdrmTests/Services/ThresholdStateMachineTests.swift # EXTEND — add critical threshold tests
```

No new files to create. No other files need modification.

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on ALL tests (NotificationService is `@MainActor`)
- **Mock strategy:** Use existing `SpyNotificationCenter` to verify critical notification delivery — check `addedRequests` for content with `.default` sound and `"headroom-critical-*"` identifiers.
- **Key test scenarios:** See Task 4 subtasks above for complete list.
- **Boundary condition:** Headroom at exactly 5.0% should NOT trigger critical (must be strictly below 5%).
- **Regression:** All 260 existing tests must continue passing (zero regressions).

### Library & Framework Requirements

- `UserNotifications` — already imported in `cc-hdrm/cc-hdrm/Services/NotificationService.swift`. No new framework imports needed.
- `cc-hdrm/cc-hdrm/Extensions/Date+Formatting.swift` — `countdownString()` and `absoluteTimeString()` already exist and will be used for notification body.
- No new external dependencies. Zero external packages.

### Anti-Patterns to Avoid

- DO NOT put threshold state machines in AppState — they belong in NotificationService per architecture boundary
- DO NOT fire both warning AND critical when dropping directly from >20% to <5% — only fire critical
- DO NOT fire notifications repeatedly for the same crossing — state machine enforces fire-once semantics
- DO NOT use a different notification body format for critical vs warning — same content template, only difference is sound and identifier
- DO NOT modify `cc-hdrm/cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT modify PollingEngine or AppDelegate — already wired from Story 5.2
- DO NOT use `DispatchQueue` or GCD — use async/await
- DO NOT use `print()` — use `os.Logger`
- DO NOT cache or persist threshold state across app launches — threshold state resets on launch
- DO NOT use the same notification identifier for critical as warning (`"headroom-warning-*"` vs `"headroom-critical-*"`) — critical should appear alongside warning in Notification Center, not replace it

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 5.3] — Full acceptance criteria for critical threshold and persistent notifications
- [Source: _bmad-output/planning-artifacts/architecture.md#Notification Strategy] — Framework: UserNotifications, thresholds: 20% and 5%, fire once per crossing, re-arm on recovery, both windows tracked independently
- [Source: _bmad-output/planning-artifacts/architecture.md#line 532] — Threshold state machines live inside NotificationService, not AppState
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Notification Persistence] — Warning (20%): standard notification; Critical (5%): persistent with sound
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Threshold State Machine] — ABOVE_20 → WARNED_20 → WARNED_5, re-arm on recovery above 20%
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#line 894] — WARNED_20 --[drops below 5%]--> WARNED_5 (fire notification)
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#line 922] — Critical (5%): Persistent notification with sound
- [Source: cc-hdrm/cc-hdrm/Services/NotificationService.swift] — Current implementation with evaluateWindow, sendNotification, evaluateThresholds
- [Source: cc-hdrm/cc-hdrm/Services/NotificationServiceProtocol.swift] — ThresholdState enum, protocol with evaluateThresholds
- [Source: cc-hdrm/cc-hdrm/Services/NotificationCenterProtocol.swift] — Protocol abstraction over UNUserNotificationCenter
- [Source: cc-hdrm/cc-hdrmTests/Mocks/SpyNotificationCenter.swift] — Spy for notification delivery verification
- [Source: cc-hdrm/cc-hdrmTests/Services/ThresholdStateMachineTests.swift] — Existing threshold tests to extend
- [Source: cc-hdrm/cc-hdrm/Extensions/Date+Formatting.swift:42-65] — countdownString() for notification body
- [Source: cc-hdrm/cc-hdrm/Extensions/Date+Formatting.swift:82-88] — absoluteTimeString() for notification body
- [Source: _bmad-output/planning-artifacts/project-context.md#Architectural Boundaries] — NotificationService boundary

## Dev Agent Record

### Agent Model Used

claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

None required.

### Completion Notes List

- Extended `evaluateWindow` return type from 2-tuple to 3-tuple adding `shouldFireCritical: Bool`
- Added `aboveWarning` → `warned5` direct transition (skipping warning) when headroom < 5%
- Added `warned20` → `warned5` transition when headroom < 5% with critical flag
- Created `sendCriticalNotification` with `.default` sound and `"headroom-critical-*"` identifiers (distinct from `"headroom-warning-*"`)
- Wired `shouldFireCritical` in `evaluateThresholds` for both 5h and 7d windows
- Updated 4 existing `evaluateWindow` direct tests to handle new 3-tuple return
- Added 13 new tests covering all AC scenarios: critical from warned20, direct skip, no repeat, recovery, re-arm, unauthorized, sound, distinct identifiers, independent tracking, nil state, boundary at exactly 5%, body format
- 273 total tests passing, zero regressions (up from 260)
- [Code Review] Refactored `sendNotification` and `sendCriticalNotification` into shared `deliverNotification` method eliminating ~28 lines of duplication
- [Code Review] Added test for critical notification with `nil` resetsAt — verifies body omits countdown
- 274 total tests passing after code review fixes

### Change Log

- 2026-02-02: Implemented critical threshold persistent notifications with sound (Story 5.3)
- 2026-02-02: Code review fixes — refactored notification delivery duplication, added nil resetsAt test

### File List

- `cc-hdrm/cc-hdrm/Services/NotificationService.swift` — MODIFIED: extended evaluateWindow return type, added sendCriticalNotification, wired in evaluateThresholds
- `cc-hdrm/cc-hdrmTests/Services/ThresholdStateMachineTests.swift` — MODIFIED: updated 4 existing evaluateWindow tests for new return type, added 13 new critical threshold tests
