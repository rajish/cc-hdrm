# Story 6.4: Launch at Login

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want cc-hdrm to start automatically when I log in,
so that usage monitoring is always running without me remembering to launch it.

## Acceptance Criteria

1. **Given** the user enables "Launch at login" in settings, **When** the toggle is switched on, **Then** the app registers as a login item via `SMAppService.mainApp.register()` (FR29) **And** on next macOS login, cc-hdrm launches automatically.

2. **Given** the user disables "Launch at login" in settings, **When** the toggle is switched off, **Then** the app unregisters via `SMAppService.mainApp.unregister()` **And** cc-hdrm no longer launches on login.

3. **Given** the app launches, **When** PreferencesManager reads the `launchAtLogin` preference, **Then** the toggle in settings reflects the actual `SMAppService.mainApp.status` (not just the stored preference) **And** if there's a mismatch (user changed it in System Settings), the UI reflects reality.

## Tasks / Subtasks

- [x] Task 1: Create LaunchAtLoginService with SMAppService integration (AC: #1, #2)
  - [x] Create `LaunchAtLoginServiceProtocol` in `cc-hdrm/Services/LaunchAtLoginServiceProtocol.swift`
  - [x] Create `LaunchAtLoginService` in `cc-hdrm/Services/LaunchAtLoginService.swift`
  - [x] Implement `register()` calling `SMAppService.mainApp.register()`
  - [x] Implement `unregister()` calling `SMAppService.mainApp.unregister()`
  - [x] Implement `isEnabled` computed property that reads `SMAppService.mainApp.status == .enabled`
  - [x] Add `import ServiceManagement` — this is the ONLY file that imports ServiceManagement
  - [x] Log register/unregister/errors via `os.Logger` (category: "preferences")

- [x] Task 2: Wire LaunchAtLoginService into SettingsView toggle (AC: #1, #2, #3)
  - [x] Thread `LaunchAtLoginServiceProtocol` through view hierarchy: AppDelegate -> PopoverView -> PopoverFooterView -> GearMenuView -> SettingsView
  - [x] In SettingsView, modify `launchAtLogin` toggle `.onChange` to call `launchAtLoginService.register()` or `.unregister()` based on new value
  - [x] On SettingsView `init`, read initial state from `launchAtLoginService.isEnabled` (NOT from PreferencesManager) to reflect System Settings reality (AC #3)
  - [x] After register/unregister, re-read `launchAtLoginService.isEnabled` to confirm actual state (handles permission denial)
  - [x] Update `preferencesManager.launchAtLogin` to match the actual state after register/unregister attempt

- [x] Task 3: Handle SMAppService errors gracefully (AC: #1, #2)
  - [x] `SMAppService.mainApp.register()` can throw — catch and log the error
  - [x] If registration fails (e.g., sandboxing issues), toggle should revert to off state
  - [x] If unregistration fails, toggle should revert to on state
  - [x] No user-facing error message required — just log and revert toggle

- [x] Task 4: Handle Reset to Defaults for launch at login (AC: #2)
  - [x] When "Reset to Defaults" is clicked in SettingsView, call `launchAtLoginService.unregister()` (default is off)
  - [x] Update toggle state to reflect actual `isEnabled` after unregister

- [x] Task 5: Write tests for launch at login (AC: #1, #2, #3)
  - [x] Create `MockLaunchAtLoginService` in `cc-hdrmTests/Mocks/MockLaunchAtLoginService.swift`
  - [x] Test: `register()` sets `isEnabled` to true
  - [x] Test: `unregister()` sets `isEnabled` to false
  - [x] Test: SettingsView initializes toggle from `launchAtLoginService.isEnabled`, not `preferencesManager.launchAtLogin`
  - [x] Test: Register failure reverts toggle to off
  - [x] Test: Mismatch between PreferencesManager and SMAppService resolves to SMAppService truth
  - [x] Test: Reset to Defaults calls unregister
  - [x] Ensure all existing tests pass (330+ tests, zero regressions)

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. New service (`LaunchAtLoginService`) follows existing protocol-based pattern.
- **Boundary:** `LaunchAtLoginService` is the ONLY component that imports `ServiceManagement` — same boundary pattern as KeychainService owning Security, NotificationService owning UserNotifications.
- **State flow:** SettingsView toggle -> LaunchAtLoginService.register()/unregister() -> re-read isEnabled -> update UI + PreferencesManager.
- **Concurrency:** `SMAppService.mainApp.register()` and `unregister()` are synchronous throwing calls. No async needed. SettingsView is on MainActor — direct calls are safe.

### Key Implementation Details

**SMAppService API (macOS 13+, we target macOS 14+):**

```swift
import ServiceManagement

// Register as login item
try SMAppService.mainApp.register()

// Unregister
try SMAppService.mainApp.unregister()

// Check current status
let status = SMAppService.mainApp.status
// status is one of: .notRegistered, .enabled, .requiresApproval, .notFound
```

**Critical design decision: Source of truth for toggle state.**

The `launchAtLogin` toggle in SettingsView must reflect **reality** (SMAppService.mainApp.status), not just the stored UserDefaults preference. This is because the user can change login items in System Settings > General > Login Items, bypassing the app. AC #3 explicitly requires: "if there's a mismatch (user changed it in System Settings), the UI reflects reality."

**Implementation approach:**

1. `LaunchAtLoginService.isEnabled` reads `SMAppService.mainApp.status == .enabled`
2. SettingsView `init` reads from `launchAtLoginService.isEnabled`, NOT `preferencesManager.launchAtLogin`
3. On toggle change: call register/unregister, then re-read `isEnabled` to confirm
4. Update `preferencesManager.launchAtLogin` to match actual state (keeps UserDefaults in sync for future reads outside SettingsView, e.g., if any other component cares)

**Why a separate service instead of putting SMAppService calls in PreferencesManager?**

- Architectural boundary: ServiceManagement is a system framework, like Security and UserNotifications. Each system framework gets its own service wrapper.
- Testability: `MockLaunchAtLoginService` can simulate registration success/failure without touching the real `SMAppService`.
- Single responsibility: PreferencesManager handles UserDefaults only. LaunchAtLoginService handles login item registration only.

**SettingsView threading change:**

Currently SettingsView takes `preferencesManager` and `onThresholdChange` through the view hierarchy. This story adds `launchAtLoginService` as another dependency. The threading path is:

```
AppDelegate -> PopoverView -> PopoverFooterView -> GearMenuView -> SettingsView
                                                                    ^
                                                                    + launchAtLoginService
```

This matches the existing pattern used for `preferencesManager` and `onThresholdChange`.

**Error handling in register/unregister:**

```swift
func register() {
    do {
        try SMAppService.mainApp.register()
        logger.info("Registered as login item")
    } catch {
        logger.error("Failed to register as login item: \(error.localizedDescription, privacy: .public)")
    }
}
```

The toggle must re-read `isEnabled` after the call to detect if the operation actually succeeded.

### Previous Story Intelligence (6.3)

**What was built:**
- `reevaluateThresholds()` threaded through view hierarchy via `onThresholdChange` closure pattern
- `isUpdating` re-entrancy guard on all `.onChange` handlers — **follow this pattern** for the launchAtLogin toggle change
- View hierarchy wiring: AppDelegate -> PopoverView -> PopoverFooterView -> GearMenuView -> SettingsView
- 330 tests passing, zero regressions

**Key pattern to follow:**
- The `onThresholdChange` closure threading pattern is the model for threading `launchAtLoginService`
- Use `isUpdating` guard in the launchAtLogin `.onChange` handler to prevent re-entrancy

**What exists for launchAtLogin already:**
- `PreferencesManager.launchAtLogin` property — reads/writes UserDefaults (lines 111-120 of `cc-hdrm/Services/PreferencesManager.swift`)
- `PreferencesManagerProtocol.launchAtLogin` — declared in protocol (line 17 of `cc-hdrm/Services/PreferencesManagerProtocol.swift`)
- `PreferencesDefaults.launchAtLogin = false` — default value (line 8 of `cc-hdrm/Services/PreferencesManagerProtocol.swift`)
- `SettingsView` already has a `Toggle("Launch at login", ...)` with `.onChange` handler (lines 102-109 of `cc-hdrm/Views/SettingsView.swift`) — this writes to `preferencesManager.launchAtLogin` but does NOT call SMAppService
- `MockPreferencesManager.launchAtLogin` — already supports `launchAtLogin` (line 9 of `cc-hdrmTests/Mocks/MockPreferencesManager.swift`)
- `resetToDefaults()` resets `launchAtLogin` to false — needs to also call `unregister()` in this story

### Git Intelligence

Last 3 commits: Stories 6.1, 6.2, 6.3. Key patterns:
- `AppDelegate.swift` wires services and passes them through PopoverView
- View hierarchy threading: each view adds a parameter, passes it to the next view down
- SettingsView `.onChange` pattern: guard `isUpdating`, set value, re-read, unguard
- Test pattern: create mock, inject into view, verify behavior

### Project Structure Notes

- `LaunchAtLoginService.swift` follows the same Service + Protocol pattern as all other services
- Placed in `cc-hdrm/Services/` alongside existing services
- Test mock in `cc-hdrmTests/Mocks/`
- Tests in `cc-hdrmTests/Services/LaunchAtLoginServiceTests.swift`

### File Structure Requirements

Files to CREATE:
```
cc-hdrm/Services/LaunchAtLoginServiceProtocol.swift    # NEW — protocol + isEnabled, register(), unregister()
cc-hdrm/Services/LaunchAtLoginService.swift            # NEW — SMAppService wrapper, os.Logger
cc-hdrmTests/Mocks/MockLaunchAtLoginService.swift      # NEW — in-memory mock for tests
cc-hdrmTests/Services/LaunchAtLoginServiceTests.swift   # NEW — tests for mock behavior and integration
```

Files to MODIFY:
```
cc-hdrm/Views/SettingsView.swift                       # MODIFY — add launchAtLoginService dependency, wire toggle to register/unregister, init from isEnabled
cc-hdrm/Views/GearMenuView.swift                       # MODIFY — add launchAtLoginService pass-through
cc-hdrm/Views/PopoverFooterView.swift                  # MODIFY — add launchAtLoginService pass-through
cc-hdrm/Views/PopoverView.swift                        # MODIFY — add launchAtLoginService pass-through
cc-hdrm/App/AppDelegate.swift                          # MODIFY — create LaunchAtLoginService, pass to PopoverView
cc-hdrmTests/Views/SettingsViewTests.swift              # MODIFY — update tests with launchAtLoginService parameter
cc-hdrmTests/Views/PopoverViewTests.swift               # MODIFY — update PopoverView init calls if needed
cc-hdrmTests/Views/PopoverFooterViewTests.swift         # MODIFY — update init calls if needed
cc-hdrmTests/Views/GearMenuViewTests.swift              # MODIFY — update init calls if needed
cc-hdrmTests/App/AppDelegateTests.swift                 # MODIFY — verify LaunchAtLoginService creation if needed
```

Files NOT to modify:
```
cc-hdrm/cc_hdrm.entitlements                           # PROTECTED — do not touch
cc-hdrm/Services/PreferencesManager.swift              # No changes needed — launchAtLogin property stays as-is for UserDefaults sync
cc-hdrm/Services/PreferencesManagerProtocol.swift       # No changes needed
cc-hdrm/Services/NotificationService.swift              # No changes needed
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on all tests involving SettingsView or service interactions
- **Mock strategy:** `MockLaunchAtLoginService` with `isEnabled: Bool`, `registerCallCount`, `unregisterCallCount`, `shouldThrowOnRegister: Bool`, `shouldThrowOnUnregister: Bool`
- **Key test scenarios:**
  - Register sets `isEnabled` to true in mock
  - Unregister sets `isEnabled` to false in mock
  - SettingsView toggle calls `register()` when switched on
  - SettingsView toggle calls `unregister()` when switched off
  - SettingsView init reads from `launchAtLoginService.isEnabled`, not `preferencesManager.launchAtLogin`
  - Register failure: `isEnabled` stays false, toggle reverts
  - Reset to Defaults triggers `unregister()`
  - Mismatch scenario: `preferencesManager.launchAtLogin = true` but `launchAtLoginService.isEnabled = false` -> toggle shows off
- **Regression:** All 330+ existing tests must continue passing (zero regressions)

### Library & Framework Requirements

- **New import:** `ServiceManagement` — ONLY in `LaunchAtLoginService.swift`
- No new external dependencies. Zero third-party packages.
- `SMAppService` available macOS 13+. We target macOS 14+. No compatibility concern.

### Anti-Patterns to Avoid

- DO NOT call `SMAppService.mainApp.register()` directly from SettingsView — go through `LaunchAtLoginService`
- DO NOT import `ServiceManagement` in any file other than `LaunchAtLoginService.swift`
- DO NOT use `preferencesManager.launchAtLogin` as the source of truth for toggle state — use `launchAtLoginService.isEnabled`
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT use `DispatchQueue` or GCD — structured concurrency only
- DO NOT use `print()` — use `os.Logger`
- DO NOT skip the `isUpdating` re-entrancy guard in the toggle `.onChange` handler
- DO NOT swallow register/unregister errors silently — log them via `os.Logger`
- DO NOT assume register() always succeeds — always re-read `isEnabled` after the call

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` #Story 6.4] — Full acceptance criteria for Launch at Login
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Launch at Login] — SMAppService decision, macOS 13+ availability (lines 660-665)
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Phase 2 Requirements to Structure Mapping] — FR29 mapped to PreferencesManager + SettingsView (line 756)
- [Source: `cc-hdrm/Services/PreferencesManager.swift` lines 109-120] — Existing `launchAtLogin` UserDefaults property
- [Source: `cc-hdrm/Services/PreferencesManagerProtocol.swift` line 8] — `PreferencesDefaults.launchAtLogin = false`
- [Source: `cc-hdrm/Services/PreferencesManagerProtocol.swift` line 17] — `launchAtLogin` in protocol
- [Source: `cc-hdrm/Views/SettingsView.swift` lines 102-109] — Existing launch at login toggle with `.onChange`
- [Source: `cc-hdrm/Views/SettingsView.swift` lines 19-27] — SettingsView init with dependency injection pattern
- [Source: `cc-hdrm/Views/SettingsView.swift` lines 117-124] — Reset to Defaults button handler
- [Source: `cc-hdrm/App/AppDelegate.swift` lines 54-68] — PopoverView creation with service wiring pattern
- [Source: `cc-hdrmTests/Mocks/MockPreferencesManager.swift`] — Existing mock pattern to follow
- [Source: `cc-hdrmTests/Views/SettingsViewTests.swift`] — Existing SettingsView tests to update
- [Source: `_bmad-output/implementation-artifacts/6-3-configurable-notification-thresholds.md`] — Previous story with view hierarchy threading pattern
- [Source: `_bmad-output/planning-artifacts/project-context.md`] — Architecture overview, coding patterns

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

None — clean implementation, no issues encountered.

### Code Review Fixes (CR by claude-opus-4-5)

- **H1 fixed:** Rewrote `LaunchAtLoginServiceTests` — replaced 3 assertion-free "structural" tests with real behavioral tests that verify no spurious register/unregister calls on init, proving toggle reads from `launchAtLoginService.isEnabled` not `preferencesManager.launchAtLogin`
- **H2 fixed:** Rewrote `resetToDefaultsCallsUnregister` test — now exercises the exact Reset to Defaults sequence (resetToDefaults + unregister + state sync) with full assertions on all side effects
- **M1 fixed:** Added `sprint-status.yaml` to File List
- **M2 fixed:** Added `AppDelegateTests.swift` to File List; added 2 new tests verifying `launchAtLoginService` creation and injection in AppDelegate
- **M3 fixed:** Stored `launchAtLoginService` as `internal var` on AppDelegate (matching `preferencesManager` pattern); added to test-only init for injection; `applicationDidFinishLaunching` creates if not injected
- **L1 fixed:** Renamed test suite from "LaunchAtLoginService Tests" to "MockLaunchAtLoginService Tests" + split behavioral tests into "SettingsView LaunchAtLogin Behavior Tests"
- **L2 verified:** 341 tests passing, zero regressions (was 338 → +3 new: 2 AppDelegate wiring + 1 register failure behavioral)

### Completion Notes List

- Created `LaunchAtLoginServiceProtocol` and `LaunchAtLoginService` wrapping `SMAppService.mainApp` with `os.Logger` logging (category: "preferences")
- `ServiceManagement` imported ONLY in `LaunchAtLoginService.swift` — boundary pattern maintained
- SettingsView init reads toggle state from `launchAtLoginService.isEnabled` (AC #3 source-of-truth from SMAppService)
- Toggle `.onChange` calls register/unregister, re-reads `isEnabled` to confirm actual state, syncs back to `preferencesManager.launchAtLogin`
- Error handling: register/unregister failures caught and logged; toggle reverts to actual `isEnabled` state
- Reset to Defaults calls `launchAtLoginService.unregister()` and reads actual state
- `launchAtLoginService` threaded through full view hierarchy: AppDelegate -> PopoverView -> PopoverFooterView -> GearMenuView -> SettingsView
- 11 tests across 2 suites in `LaunchAtLoginServiceTests.swift` covering mock behavior, SettingsView init, mismatch, reset, and register failure
- 2 tests in `AppDelegateTests.swift` verifying launchAtLoginService creation and injection
- All existing test call sites updated with `launchAtLoginService` parameter
- 341 tests passing, zero regressions (was 330)

### Change Log

- 2026-02-02: Implemented Story 6.4 — Launch at Login with SMAppService integration
- 2026-02-02: Code review fixes — improved test quality, AppDelegate testability, File List accuracy

### File List

**Created:**
- `cc-hdrm/Services/LaunchAtLoginServiceProtocol.swift`
- `cc-hdrm/Services/LaunchAtLoginService.swift`
- `cc-hdrmTests/Mocks/MockLaunchAtLoginService.swift`
- `cc-hdrmTests/Services/LaunchAtLoginServiceTests.swift`

**Modified:**
- `cc-hdrm/Views/SettingsView.swift`
- `cc-hdrm/Views/GearMenuView.swift`
- `cc-hdrm/Views/PopoverFooterView.swift`
- `cc-hdrm/Views/PopoverView.swift`
- `cc-hdrm/App/AppDelegate.swift`
- `cc-hdrmTests/Views/SettingsViewTests.swift`
- `cc-hdrmTests/Views/PopoverViewTests.swift`
- `cc-hdrmTests/Views/PopoverFooterViewTests.swift`
- `cc-hdrmTests/Views/GearMenuViewTests.swift`
- `cc-hdrmTests/App/AppDelegateTests.swift`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
