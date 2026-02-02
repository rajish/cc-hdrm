# Story 5.1: Notification Permission & Service Setup

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want the app to set up macOS notification capabilities,
so that threshold alerts can be delivered when headroom drops.

## Acceptance Criteria

1. **Given** the app launches for the first time, **When** the NotificationService initializes, **Then** it requests notification authorization via `UserNotifications` framework (`UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])`) **And** authorization status is tracked internally in NotificationService **And** if the user denies permission, the app continues functioning without notifications (no crash, no nag).
2. **Given** the app launches on subsequent runs, **When** the NotificationService initializes, **Then** it checks existing authorization status via `UNUserNotificationCenter.current().notificationSettings()` without re-prompting **And** updates its internal `isAuthorized` state accordingly.

## Tasks / Subtasks

- [x] Task 1: Create NotificationServiceProtocol.swift (AC: #1-#2)
  - [x] Create `cc-hdrm/Services/NotificationServiceProtocol.swift`
  - [x] Define protocol:
    ```swift
    @MainActor
    protocol NotificationServiceProtocol: Sendable {
        func requestAuthorization() async
        var isAuthorized: Bool { get }
    }
    ```
  - [x] Keep protocol minimal — threshold evaluation will be added in Story 5.2

- [x] Task 2: Create NotificationService.swift (AC: #1-#2)
  - [x] Create `cc-hdrm/Services/NotificationService.swift`
  - [x] Import `UserNotifications` and `os`
  - [x] `@MainActor final class NotificationService: NotificationServiceProtocol`
  - [x] Private properties:
    - `private(set) var isAuthorized: Bool = false`
    - `private let notificationCenter: UNUserNotificationCenter`
    - `private static let logger = Logger(subsystem: "com.cc-hdrm.app", category: "notification")`
  - [x] Init takes `notificationCenter: UNUserNotificationCenter = .current()` for testability
  - [x] `requestAuthorization()` method:
    1. Check current settings via `notificationCenter.notificationSettings()`
    2. If `.authorized` → set `isAuthorized = true`, log, return (no re-prompt)
    3. If `.notDetermined` → call `notificationCenter.requestAuthorization(options: [.alert, .sound])`
    4. If granted → set `isAuthorized = true`, log success
    5. If denied → set `isAuthorized = false`, log (not error — user choice), continue
    6. If `.denied` (previously denied) → set `isAuthorized = false`, log, return (no nag)
    7. Catch any errors → set `isAuthorized = false`, log error
  - [x] NEVER log sensitive data
  - [x] Use `os.Logger` with `notification` category

- [x] Task 3: Wire NotificationService into AppDelegate (AC: #1-#2)
  - [x] In `cc-hdrm/App/AppDelegate.swift`:
  - [x] Add property: `private var notificationService: (any NotificationServiceProtocol)?`
  - [x] In `applicationDidFinishLaunching`:
    - After PollingEngine/FreshnessMonitor creation, before `Task { ... }`:
    - Create NotificationService: `notificationService = NotificationService()`
    - Inside the existing `Task { ... }` block, add: `await notificationService?.requestAuthorization()`
  - [x] In `applicationWillTerminate`: no cleanup needed (NotificationService is stateless re: system resources)
  - [x] Update test-only initializer to accept optional `notificationService` parameter

- [x] Task 4: Write NotificationService tests (AC: #1-#2)
  - [x] Create `cc-hdrmTests/Services/NotificationServiceTests.swift`
  - [x] Use `@Test`, `@Suite`, `#expect` from Swift Testing framework
  - [x] `@MainActor` on all tests (NotificationService is @MainActor)
  - [x] Test: NotificationService can be instantiated — verify `isAuthorized` defaults to `false`
  - [x] Test: `requestAuthorization()` can be called without crash (note: UNUserNotificationCenter behavior varies in test environment — focus on instantiation and no-crash verification)
  - [x] Test: Protocol conformance — `NotificationService` conforms to `NotificationServiceProtocol`
  - [x] Note: Full authorization flow testing requires mock UNUserNotificationCenter which is non-trivial — defer comprehensive mocking to Story 5.2 when threshold logic needs it

- [x] Task 5: Write MockNotificationService for testing (AC: #1-#2)
  - [x] Create `cc-hdrmTests/Mocks/MockNotificationService.swift`
  - [x] Implement `NotificationServiceProtocol` with controllable properties:
    ```swift
    @MainActor
    final class MockNotificationService: NotificationServiceProtocol {
        var isAuthorized: Bool = false
        var requestAuthorizationCallCount = 0

        func requestAuthorization() async {
            requestAuthorizationCallCount += 1
        }
    }
    ```
  - [x] This mock enables AppDelegate tests in future stories without triggering real notification prompts

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. NotificationService is a service-layer component. It follows the existing protocol-based pattern (KeychainServiceProtocol/KeychainService, APIClientProtocol/APIClient, etc.).
- **Boundary:** NotificationService is the ONLY component that imports `UserNotifications` — per architecture boundary rules.
- **State flow:** NotificationService will read from AppState (in Story 5.2) to detect threshold crossings. For now, it only manages its own authorization state.
- **Concurrency:** `@MainActor` consistent with all other services. `async` for authorization request.
- **Logging:** `os.Logger`, subsystem `com.cc-hdrm.app`, category `notification` — per architecture spec.

### Key Implementation Details

**NotificationService initialization pattern (matches existing services):**
```swift
import UserNotifications
import os

@MainActor
final class NotificationService: NotificationServiceProtocol {
    private(set) var isAuthorized: Bool = false
    private let notificationCenter: UNUserNotificationCenter
    
    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "notification"
    )
    
    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }
    
    func requestAuthorization() async {
        let settings = await notificationCenter.notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            isAuthorized = true
            Self.logger.info("Notification authorization already granted")
            return
        case .denied:
            isAuthorized = false
            Self.logger.info("Notification authorization previously denied by user")
            return
        case .notDetermined:
            break // proceed to request
        case .ephemeral:
            isAuthorized = true
            Self.logger.info("Notification authorization ephemeral")
            return
        @unknown default:
            break // proceed to request
        }
        
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            isAuthorized = granted
            if granted {
                Self.logger.info("Notification authorization granted")
            } else {
                Self.logger.info("Notification authorization denied by user")
            }
        } catch {
            isAuthorized = false
            Self.logger.error("Notification authorization request failed: \(error.localizedDescription)")
        }
    }
}
```

**AppDelegate wiring (addition to existing code):**
```swift
// In AppDelegate, add property:
private var notificationService: (any NotificationServiceProtocol)?

// In applicationDidFinishLaunching, after FreshnessMonitor creation:
if notificationService == nil {
    notificationService = NotificationService()
}

// Inside the existing Task block:
Task {
    await pollingEngine?.start()
    await freshnessMonitor?.start()
    await notificationService?.requestAuthorization()
}
```

**Why NotificationService does NOT take AppState:**
In this story, NotificationService only handles authorization. In Story 5.2, it will be extended to accept AppState and observe threshold crossings. Keeping this story focused avoids premature coupling.

### Previous Story Intelligence (4.5)

**What was built:**
- StatusMessageView for error states in popover
- PopoverView updated with resolvedStatusMessage computed property
- All 4 error states covered (disconnected, tokenExpired, noCredentials, veryStale)
- 232+ tests passing (some systemic SIGILL crashes in test runner — pre-existing, not story-related)

**Code review lessons from story 4.5:**
- Use `StatusMessage` struct (already in AppState.swift) instead of anonymous tuples
- Add `@MainActor` to ALL tests touching `@MainActor` types
- Don't include xcodeproj files in File List (gitignored, auto-generated by XcodeGen)
- Test names should honestly reflect what they validate (no overclaiming)

**Patterns to follow exactly:**
- Protocol in separate file: `NotificationServiceProtocol.swift`
- Implementation in separate file: `NotificationService.swift`
- Mock in `cc-hdrmTests/Mocks/` directory (consistent with mock placement if any exist; otherwise create directory)
- `@MainActor` on service class
- `os.Logger` with per-service category
- `init` with injectable dependencies for testability

### Git Intelligence

Recent commits follow pattern: "Add story X.Y: [description] and code review fixes"
XcodeGen auto-discovers new files — run `xcodegen generate` after adding files.
Last commit: `c004e48 Add story 4.5: status messages for error states and code review fixes`

### Project Structure Notes

- `Services/` directory currently contains: KeychainService, KeychainServiceProtocol, APIClient, APIClientProtocol, PollingEngine, PollingEngineProtocol, TokenRefreshService, TokenRefreshServiceProtocol, FreshnessMonitor, FreshnessMonitorProtocol, TokenExpiryChecker
- **NotificationService.swift does NOT exist yet** — this story creates it
- **NotificationServiceProtocol.swift does NOT exist yet** — this story creates it
- No existing `Mocks/` directory in tests — check if mocks are inline in test files or in a dedicated directory before creating

### File Structure Requirements

New files to create:
```
cc-hdrm/Services/NotificationServiceProtocol.swift    # NEW — protocol definition
cc-hdrm/Services/NotificationService.swift             # NEW — UserNotifications authorization
cc-hdrmTests/Services/NotificationServiceTests.swift   # NEW — service tests
cc-hdrmTests/Mocks/MockNotificationService.swift       # NEW — mock for future test use
```

Files to modify:
```
cc-hdrm/App/AppDelegate.swift                         # ADD NotificationService wiring
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on ALL tests (NotificationService is `@MainActor`)
- **Key test scenarios:**
  - NotificationService instantiation — `isAuthorized` defaults to `false`
  - `requestAuthorization()` can be called without crash
  - Protocol conformance verified
  - MockNotificationService tracks call count correctly
- **Limitation:** `UNUserNotificationCenter` cannot be fully mocked in Swift Testing without significant infrastructure. Tests focus on instantiation, protocol conformance, and no-crash behavior. The injectable `notificationCenter` parameter enables future test enhancement.
- **All existing tests must continue passing (zero regressions).**

### Library & Framework Requirements

- `UserNotifications` — Apple framework, ships with macOS SDK. **Only imported in NotificationService.swift** per architecture boundary.
- No new external dependencies. Zero external packages.

### Anti-Patterns to Avoid

- DO NOT import `UserNotifications` anywhere except `NotificationService.swift` — architecture boundary rule
- DO NOT re-prompt for notification permission if previously denied — check settings first
- DO NOT crash or show error if permission denied — app functions fully without notifications
- DO NOT add threshold logic to this story — that's Story 5.2
- DO NOT give NotificationService an AppState dependency yet — that's Story 5.2
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file, and UserNotifications does NOT require an entitlement
- DO NOT use `DispatchQueue` or GCD — use async/await
- DO NOT use `print()` — use `os.Logger`
- DO NOT cache authorization status across app launches — always check fresh on init

### References

- [Source: epics.md#Story 5.1] — Full acceptance criteria for notification permission and service setup
- [Source: architecture.md#Notification Strategy] — Framework: UserNotifications, thresholds: 20% and 5%, fire once per crossing, re-arm on recovery, both windows tracked independently
- [Source: architecture.md#Notification Boundary] — NotificationService is the only component that imports UserNotifications
- [Source: architecture.md#Implementation Patterns] — Protocol-based service interfaces for testability
- [Source: architecture.md#Logging Patterns] — category: `notification`, `.info` fired
- [Source: ux-design-specification.md#Notification Patterns] — Threshold state machine: ABOVE_20 → WARNED_20 → WARNED_5, re-arm on recovery above 20%
- [Source: ux-design-specification.md#Notification Content Pattern] — "Claude [window] headroom at [X]% — resets in [relative] (at [absolute])"
- [Source: ux-design-specification.md#Notification Persistence] — Warning (20%): standard notification; Critical (5%): persistent with sound
- [Source: AppDelegate.swift] — Service wiring pattern: create in `applicationDidFinishLaunching`, start in Task block
- [Source: PollingEngine.swift] — Pattern reference for @MainActor service with protocol, logger, injectable dependencies
- [Source: AppState.swift:6-11] — ConnectionStatus enum
- [Source: AppState.swift:14-22] — WindowState with derived headroomState
- [Source: HeadroomState.swift:24-35] — Headroom thresholds: >40% normal, 20-40% caution, 5-20% warning, <5% critical, 0% exhausted
- [Source: Date+Formatting.swift] — countdownString() and absoluteTimeString() for notification content (Story 5.2)
- [Source: project-context.md#Architectural Boundaries] — NotificationService boundary: only component importing UserNotifications

## Dev Agent Record

### Agent Model Used

claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

### Completion Notes List

- All 5 tasks implemented per story spec. 235 tests pass (3 new + 232 existing), zero regressions.
- NotificationServiceProtocol: minimal @MainActor protocol with `requestAuthorization()` and `isAuthorized`.
- NotificationService: checks `notificationSettings()` first to avoid re-prompting; handles all authorization states including `.provisional`, `.ephemeral`, `@unknown default`. Uses `os.Logger` category `notification`.
- AppDelegate: NotificationService created after FreshnessMonitor, `requestAuthorization()` called in existing Task block. Test-only init updated with optional `notificationService` parameter.
- Tests: 3 tests — default state, protocol conformance, no-crash `requestAuthorization()` call.
- MockNotificationService: in `cc-hdrmTests/Mocks/` directory, tracks `requestAuthorizationCallCount` for future AppDelegate tests.
- `UserNotifications` imported ONLY in `NotificationService.swift` per architecture boundary.
- No entitlements modified. No external dependencies added.

### Code Review Fixes (claude-opus-4-5)

- **M1**: Removed unnecessary `import Foundation` from `NotificationServiceProtocol.swift` — matches other protocol files which have zero imports.
- **M2**: Added `///` doc comments to `NotificationServiceProtocol` and its members — matches `PollingEngineProtocol`, `FreshnessMonitorProtocol` patterns.
- **M3**: Fixed `sprint-status.yaml` story 4-5 status from `in-progress` to `done` (was committed as done in c004e48 but status not synced).
- **L1**: Added test `mockTracksCallCount` to `NotificationServiceTests.swift` verifying `MockNotificationService.requestAuthorizationCallCount` increments correctly.
- **L2**: Injected `MockNotificationService()` in all `AppDelegateTests.swift` call sites to prevent real `UNUserNotificationCenter` calls during unrelated tests.

### File List

- cc-hdrm/Services/NotificationServiceProtocol.swift (NEW, review-fixed)
- cc-hdrm/Services/NotificationService.swift (NEW)
- cc-hdrm/App/AppDelegate.swift (MODIFIED)
- cc-hdrmTests/Services/NotificationServiceTests.swift (NEW, review-fixed)
- cc-hdrmTests/Mocks/MockNotificationService.swift (NEW)
- cc-hdrmTests/App/AppDelegateTests.swift (MODIFIED — review fix L2)
