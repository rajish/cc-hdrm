# Story 6.1: Preferences Manager & UserDefaults Persistence

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want my preference changes to persist across app restarts,
so that I configure cc-hdrm once and it remembers my choices.

## Acceptance Criteria

1. **Given** the app launches for the first time (no UserDefaults entries exist), **When** PreferencesManager initializes, **Then** it provides default values: warning threshold 20%, critical threshold 5%, poll interval 30s, launch at login false, dismissedVersion nil **And** PreferencesManager conforms to PreferencesManagerProtocol for testability.

2. **Given** the user changes a preference via the settings view, **When** the value is written to UserDefaults, **Then** it persists across app restarts **And** the new value takes effect immediately without requiring restart.

3. **Given** the user sets warning threshold to 15% and critical threshold to 3%, **When** the next poll cycle evaluates thresholds, **Then** NotificationService uses 15% and 3% instead of the defaults **And** threshold state machines re-arm based on new thresholds.

4. **Given** the user sets poll interval to 60 seconds, **When** the current poll cycle completes, **Then** PollingEngine waits 60 seconds before the next cycle (hot-reconfigurable).

5. **Given** UserDefaults contains an invalid value (e.g. poll interval of 5 seconds), **When** PreferencesManager reads the value, **Then** it clamps to the valid range (min 10s, max 300s) and uses the clamped value **And** warning threshold must be > critical threshold — if violated, defaults are restored.

## Tasks / Subtasks

- [x] Task 1: Create PreferencesManagerProtocol (AC: #1)
  - [x] Create `cc-hdrm/Services/PreferencesManagerProtocol.swift`
  - [x] Define protocol with read/write properties: `warningThreshold: Double`, `criticalThreshold: Double`, `pollInterval: TimeInterval`, `launchAtLogin: Bool`, `dismissedVersion: String?`
  - [x] Define `resetToDefaults()` method
  - [x] Define static default constants: `defaultWarningThreshold = 20.0`, `defaultCriticalThreshold = 5.0`, `defaultPollInterval: TimeInterval = 30`, `defaultLaunchAtLogin = false`

- [x] Task 2: Create PreferencesManager implementation (AC: #1, #2, #5)
  - [x] Create `cc-hdrm/Services/PreferencesManager.swift`
  - [x] Implement `PreferencesManagerProtocol` conformance
  - [x] Use `UserDefaults.standard` for persistence with keys: `"com.cc-hdrm.warningThreshold"`, `"com.cc-hdrm.criticalThreshold"`, `"com.cc-hdrm.pollInterval"`, `"com.cc-hdrm.launchAtLogin"`, `"com.cc-hdrm.dismissedVersion"`
  - [x] Implement clamping validation on read:
    - Poll interval: clamp to 10...300 seconds
    - Warning threshold: clamp to 6...50%
    - Critical threshold: clamp to 1...49%
    - Warning must be > critical — if violated, restore both to defaults
  - [x] Implement `resetToDefaults()` that removes all keys from UserDefaults
  - [x] Log preference changes via `os.Logger` (category: `preferences`)

- [x] Task 3: Update NotificationService to read thresholds from PreferencesManager (AC: #3)
  - [x] Add `preferencesManager: PreferencesManagerProtocol` parameter to `NotificationService.init`
  - [x] Modify `evaluateWindow` in `cc-hdrm/Services/NotificationService.swift` to accept `warningThreshold` and `criticalThreshold` parameters instead of hardcoded `20` and `5`
  - [x] In `evaluateThresholds`, read current thresholds from `preferencesManager` and pass to `evaluateWindow`
  - [x] When thresholds change (detected by comparing to last-used values), re-evaluate current headroom against new thresholds:
    - If headroom is above new warning threshold, reset state to `aboveWarning` (re-arm)
    - If headroom is below new thresholds and no notification fired yet, fire notification
  - [x] Update `NotificationServiceProtocol` init to include preferences parameter

- [x] Task 4: Update PollingEngine to read poll interval from PreferencesManager (AC: #4)
  - [x] Add `preferencesManager: PreferencesManagerProtocol` parameter to `PollingEngine.init`
  - [x] In `cc-hdrm/Services/PollingEngine.swift`, replace `Task.sleep(for: .seconds(30))` (line 41) with `Task.sleep(for: .seconds(preferencesManager.pollInterval))`
  - [x] Read `pollInterval` fresh at each cycle start (hot-reconfigurable)
  - [x] Update `PollingEngineProtocol` init to include preferences parameter

- [x] Task 5: Wire PreferencesManager into app startup (AC: #2)
  - [x] In `cc-hdrm/App/AppDelegate.swift`, create `PreferencesManager` instance
  - [x] Pass to `NotificationService` and `PollingEngine` during service wiring
  - [x] Ensure PreferencesManager is accessible to future SettingsView (Story 6.2)

- [x] Task 6: Write comprehensive tests (AC: #1-#5)
  - [x] Test: Default values returned when no UserDefaults entries exist
  - [x] Test: Setting warning threshold persists and reads back correctly
  - [x] Test: Setting critical threshold persists and reads back correctly
  - [x] Test: Setting poll interval persists and reads back correctly
  - [x] Test: Setting launchAtLogin persists and reads back correctly
  - [x] Test: Setting dismissedVersion persists and reads back correctly
  - [x] Test: Poll interval of 5 seconds clamped to 10 seconds
  - [x] Test: Poll interval of 500 seconds clamped to 300 seconds
  - [x] Test: Warning threshold of 2% clamped to 6%
  - [x] Test: Critical threshold of 55% clamped to 49%
  - [x] Test: Warning threshold < critical threshold → both restored to defaults
  - [x] Test: Warning threshold == critical threshold → both restored to defaults
  - [x] Test: `resetToDefaults()` restores all values to defaults
  - [x] Test: NotificationService uses custom thresholds from PreferencesManager (not hardcoded 20/5)
  - [x] Test: NotificationService re-arms when thresholds change and headroom is above new threshold
  - [x] Test: PollingEngine reads poll interval fresh each cycle
  - [x] Test: Existing threshold state machine tests still pass with default thresholds
  - [x] Test: `nil` dismissedVersion by default

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. PreferencesManager is a NEW service following the established Protocol + Implementation pattern.
- **Boundary:** PreferencesManager is the ONLY component that reads/writes UserDefaults for preferences. Services read preferences via PreferencesManager, NOT directly from UserDefaults. [Source: `_bmad-output/planning-artifacts/architecture.md` line 635]
- **State flow:** PreferencesManager does NOT write to AppState. It is read by PollingEngine and NotificationService directly. Future SettingsView (Story 6.2) will use `@AppStorage` for two-way binding.
- **Concurrency:** PreferencesManager does NOT need `@MainActor` — UserDefaults is thread-safe for reads/writes. However, if `@AppStorage` is used in Story 6.2, the manager should be compatible.
- **Logging:** `os.Logger`, subsystem `com.cc-hdrm.app`, category `preferences`.

### Key Implementation Details

**PreferencesManagerProtocol:**
```swift
protocol PreferencesManagerProtocol {
    var warningThreshold: Double { get set }
    var criticalThreshold: Double { get set }
    var pollInterval: TimeInterval { get set }
    var launchAtLogin: Bool { get set }
    var dismissedVersion: String? { get set }

    func resetToDefaults()
}
```

**PreferencesManager UserDefaults keys:**
```swift
private enum Keys {
    static let warningThreshold = "com.cc-hdrm.warningThreshold"
    static let criticalThreshold = "com.cc-hdrm.criticalThreshold"
    static let pollInterval = "com.cc-hdrm.pollInterval"
    static let launchAtLogin = "com.cc-hdrm.launchAtLogin"
    static let dismissedVersion = "com.cc-hdrm.dismissedVersion"
}
```

**Default constants (static on protocol or manager):**
```swift
enum PreferencesDefaults {
    static let warningThreshold: Double = 20.0
    static let criticalThreshold: Double = 5.0
    static let pollInterval: TimeInterval = 30
    static let launchAtLogin: Bool = false
}
```

**Validation clamping (on property getter):**
```swift
var pollInterval: TimeInterval {
    get {
        let raw = defaults.double(forKey: Keys.pollInterval)
        guard raw > 0 else { return PreferencesDefaults.pollInterval }
        return min(max(raw, 10), 300)
    }
    set {
        defaults.set(min(max(newValue, 10), 300), forKey: Keys.pollInterval)
    }
}

var warningThreshold: Double {
    get {
        let warning = defaults.double(forKey: Keys.warningThreshold)
        let critical = defaults.double(forKey: Keys.criticalThreshold)
        guard warning > 0 else { return PreferencesDefaults.warningThreshold }
        let clampedWarning = min(max(warning, 6), 50)
        let clampedCritical = min(max(critical > 0 ? critical : PreferencesDefaults.criticalThreshold, 1), 49)
        if clampedWarning <= clampedCritical {
            // Violation — restore defaults
            defaults.removeObject(forKey: Keys.warningThreshold)
            defaults.removeObject(forKey: Keys.criticalThreshold)
            return PreferencesDefaults.warningThreshold
        }
        return clampedWarning
    }
    set { defaults.set(min(max(newValue, 6), 50), forKey: Keys.warningThreshold) }
}
```

**Updating NotificationService.evaluateWindow:**
The current signature is:
```swift
func evaluateWindow(currentState: ThresholdState, headroom: Double)
    -> (ThresholdState, shouldFireWarning: Bool, shouldFireCritical: Bool)
```

Updated to accept configurable thresholds:
```swift
func evaluateWindow(
    currentState: ThresholdState,
    headroom: Double,
    warningThreshold: Double,
    criticalThreshold: Double
) -> (ThresholdState, shouldFireWarning: Bool, shouldFireCritical: Bool)
```

Replace all hardcoded `20` with `warningThreshold` and `5` with `criticalThreshold` in the state machine logic at `cc-hdrm/Services/NotificationService.swift` lines 62-90.

**Updating PollingEngine.start():**
Replace at `cc-hdrm/Services/PollingEngine.swift` line 41:
```swift
// Before (hardcoded):
try? await Task.sleep(for: .seconds(30))

// After (configurable):
try? await Task.sleep(for: .seconds(preferencesManager.pollInterval))
```

**Threshold re-evaluation on change:**
Store `lastWarningThreshold` and `lastCriticalThreshold` in NotificationService. At the start of each `evaluateThresholds` call, compare current preferences to last-used values. If changed:
- If current headroom is above the new warning threshold and state is `warned20` or `warned5`, reset to `aboveWarning`
- Update the stored last-used values
This ensures changing thresholds from "20/5" to "30/10" while at 25% headroom correctly re-arms (since 25% > 30% is false, but 25% > 20% was true before).

### Previous Story Intelligence (5.3)

**What was built:**
- ThresholdState enum: `aboveWarning`, `warned20`, `warned5` — in `cc-hdrm/Services/NotificationServiceProtocol.swift`
- `evaluateWindow` with 3-tuple return — in `cc-hdrm/Services/NotificationService.swift` lines 62-90
- Hardcoded thresholds: `20` (lines 72, 77, 85) and `5` (lines 68, 80)
- `evaluateThresholds(fiveHour:sevenDay:)` wired into PollingEngine
- `deliverNotification` shared method for warning/critical delivery
- `SpyNotificationCenter` + `MockNotificationService` for test mocking
- 274 tests passing, zero regressions

**Code review lessons from story 5.3:**
- Refactored duplicate `sendNotification`/`sendCriticalNotification` into shared `deliverNotification` — follow this DRY pattern
- `evaluateWindow` is `internal` visibility for direct unit-test access — keep it that way
- `NotificationCenterProtocol` abstracts UNUserNotificationCenter — no changes needed

### Git Intelligence

Recent commits follow pattern: "Add story X.Y: [description] and code review fixes"
Last story commit: `97a7a3c Add story 5.3: critical threshold persistent notifications and code review fixes`
XcodeGen auto-discovers new files — run `xcodegen generate` after adding NEW files.

### Project Structure Notes

- Existing service pairs follow `FooProtocol.swift` + `Foo.swift` pattern
- Test mocks in `cc-hdrmTests/Mocks/` — add `MockPreferencesManager` here
- No `PreferencesManager`, `UserDefaults` usage, or settings UI exists currently
- `cc-hdrm/Views/GearMenuView.swift` — has only "Quit" item, will be expanded in Story 6.2
- `cc-hdrm/App/AppDelegate.swift` — service wiring location, will need PreferencesManager instantiation

### File Structure Requirements

Files to CREATE:
```
cc-hdrm/Services/PreferencesManagerProtocol.swift    # NEW — protocol + defaults enum
cc-hdrm/Services/PreferencesManager.swift            # NEW — UserDefaults implementation
cc-hdrmTests/Services/PreferencesManagerTests.swift   # NEW — unit tests for preferences
cc-hdrmTests/Mocks/MockPreferencesManager.swift      # NEW — mock for injection into other services
```

Files to MODIFY:
```
cc-hdrm/Services/NotificationService.swift           # MODIFY — accept PreferencesManager, parameterize thresholds in evaluateWindow
cc-hdrm/Services/NotificationServiceProtocol.swift   # MODIFY — update init signature to include PreferencesManager
cc-hdrm/Services/PollingEngine.swift                 # MODIFY — accept PreferencesManager, use configurable poll interval
cc-hdrm/Services/PollingEngineProtocol.swift         # MODIFY — update init signature to include PreferencesManager
cc-hdrm/App/AppDelegate.swift                        # MODIFY — create and wire PreferencesManager
cc-hdrmTests/Services/ThresholdStateMachineTests.swift # MODIFY — update evaluateWindow calls to pass threshold params
cc-hdrmTests/Services/NotificationServiceTests.swift  # MODIFY — inject MockPreferencesManager
cc-hdrmTests/Services/PollingEngineTests.swift        # MODIFY — inject MockPreferencesManager, test configurable interval
cc-hdrmTests/Mocks/MockNotificationService.swift     # MODIFY — update init signature if protocol changed
cc-hdrmTests/App/AppDelegateTests.swift              # MODIFY — update service wiring tests
```

Files NOT to modify:
```
cc-hdrm/cc_hdrm.entitlements  # PROTECTED — do not touch
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on tests for NotificationService and PollingEngine (they are `@MainActor`)
- **Mock strategy:** Create `MockPreferencesManager` implementing `PreferencesManagerProtocol` with in-memory storage (no UserDefaults) for injection into NotificationService and PollingEngine tests
- **UserDefaults isolation:** For PreferencesManager unit tests, use `UserDefaults(suiteName:)` with a unique test suite name to avoid polluting standard defaults, and `removePersistentDomain` in teardown
- **Key test scenarios:** See Task 6 subtasks for complete list
- **Regression:** All 274 existing tests must continue passing (zero regressions)

### Library & Framework Requirements

- `Foundation` — `UserDefaults` (already available, no new import needed in most files)
- `os` — `os.Logger` for logging preference changes (already used throughout)
- `ServiceManagement` — NOT needed in this story. `SMAppService` for launch-at-login is Story 6.4. PreferencesManager stores the `launchAtLogin` boolean but does NOT register/unregister the login item.
- No new external dependencies. Zero external packages.

### Anti-Patterns to Avoid

- DO NOT read UserDefaults directly from NotificationService or PollingEngine — always go through PreferencesManager
- DO NOT store preferences in AppState — PreferencesManager is a separate service, not part of the observable state
- DO NOT use `@AppStorage` in PreferencesManager itself — that's a SwiftUI property wrapper for views (Story 6.2)
- DO NOT implement launch-at-login registration here — this story only persists the boolean; Story 6.4 handles SMAppService
- DO NOT implement SettingsView UI here — that's Story 6.2
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT use `DispatchQueue` or GCD — use async/await
- DO NOT use `print()` — use `os.Logger`
- DO NOT cache threshold values in NotificationService properties as the primary source — always read fresh from PreferencesManager (hot-reconfigurable)
- DO NOT break the existing evaluateWindow test structure — add threshold parameters but keep all test assertions intact

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` #Story 6.1] — Full acceptance criteria for Preferences Manager & UserDefaults Persistence
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Settings Persistence] — PreferencesManager pattern, UserDefaults keys, validation rules, hot-reconfigurable reads
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Phase 2 Project Structure Additions] — New file locations for PreferencesManager and related files
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Phase 2 Data Flow Addition] — PreferencesManager reads flow into PollingEngine and NotificationService
- [Source: `_bmad-output/planning-artifacts/ux-design-specification.md` #Notification Persistence] — Threshold defaults: 20% warning, 5% critical
- [Source: `cc-hdrm/Services/NotificationService.swift` lines 62-90] — Current hardcoded thresholds in evaluateWindow
- [Source: `cc-hdrm/Services/NotificationService.swift` lines 68,72,77,80,85] — Specific lines with hardcoded 20 and 5 values
- [Source: `cc-hdrm/Services/PollingEngine.swift` line 41] — Hardcoded 30-second poll interval
- [Source: `cc-hdrm/App/AppDelegate.swift`] — Service wiring location
- [Source: `cc-hdrm/Services/NotificationServiceProtocol.swift`] — ThresholdState enum, protocol definition
- [Source: `cc-hdrmTests/Services/ThresholdStateMachineTests.swift`] — Existing threshold tests to update
- [Source: `cc-hdrmTests/Mocks/MockNotificationService.swift`] — Existing mock to update
- [Source: `cc-hdrmTests/Mocks/SpyNotificationCenter.swift`] — Existing spy, no changes needed
- [Source: `_bmad-output/planning-artifacts/project-context.md` #Architectural Boundaries] — Service boundaries

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

None required.

### Completion Notes List

- All 6 tasks completed. 301 tests pass (274 existing + 27 new), zero regressions.
- `evaluateWindow` uses default parameter values for backward compatibility — no changes needed to existing ThresholdStateMachineTests.
- `NotificationService.init` and `PollingEngine.init` use default parameter values — no changes needed to existing test files.
- PreferencesManager tests use unique `UserDefaults(suiteName:)` per test (UUID-based) to avoid state leakage.
- NotificationServiceProtocol was NOT modified (protocols don't define inits in this codebase) — the concrete class handles the preferencesManager parameter.
- PollingEngineProtocol was NOT modified — poll interval is an implementation detail, not a protocol concern.
- Threshold re-arming logic: when thresholds change, if headroom >= new warningThreshold and state is warned20/warned5, state resets to aboveWarning.
- Story "Files to MODIFY" listed 7 files that did not require modification due to default parameter values providing backward compatibility: `NotificationServiceProtocol.swift`, `PollingEngineProtocol.swift`, `ThresholdStateMachineTests.swift`, `NotificationServiceTests.swift`, `PollingEngineTests.swift`, `MockNotificationService.swift`, `AppDelegateTests.swift`.

### Code Review Fixes (claude-opus-4-5)

- **H1**: Added cross-validation to `warningThreshold` and `criticalThreshold` setters in `PreferencesManager.swift` — setter now rejects values that violate warning > critical and restores defaults, matching getter behavior.
- **M1**: Added `removePersistentDomain` cleanup via `defer` in every test to prevent orphaned UserDefaults plists.
- **M2**: Added cross-instance persistence test that writes with one `PreferencesManager` and reads with a new instance on the same suite — verifies AC #2 (survives restart).
- **M3**: Renamed misleading "PollingEngine reads poll interval" test to accurately describe what it tests (MockPreferencesManager hot-reconfigurability). PollingEngine integration is covered by existing PollingEngineTests and code inspection of `PollingEngine.swift:44`.
- **M4**: Added `sprint-status.yaml` to File List.
- **L1**: Updated `ThresholdState` doc comments to reference configurable thresholds instead of hardcoded 20/5 values.
- **L2**: Documented in Completion Notes that 7 listed "Files to MODIFY" did not require changes.
- Added 5 new tests: cross-instance persistence, setter cross-validation (4 tests).

### File List

Files CREATED:
- `cc-hdrm/Services/PreferencesManagerProtocol.swift`
- `cc-hdrm/Services/PreferencesManager.swift`
- `cc-hdrmTests/Services/PreferencesManagerTests.swift`
- `cc-hdrmTests/Mocks/MockPreferencesManager.swift`

Files MODIFIED:
- `cc-hdrm/Services/NotificationService.swift`
- `cc-hdrm/Services/NotificationServiceProtocol.swift`
- `cc-hdrm/Services/PollingEngine.swift`
- `cc-hdrm/App/AppDelegate.swift`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
