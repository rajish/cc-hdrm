# Story 6.3: Configurable Notification Thresholds

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to set my own notification thresholds,
so that I get alerted at the headroom levels that matter for my workflow.

## Acceptance Criteria

1. **Given** the user has set warning threshold to 30% and critical threshold to 10%, **When** 5-hour headroom drops below 30%, **Then** a warning notification fires with the same format as Story 5.2 (FR27) **And** the 20% default is no longer used.

2. **Given** the user has set critical threshold to 10%, **When** headroom drops below 10% (after warning has fired), **Then** a critical notification fires with the same format as Story 5.3 (FR27).

3. **Given** the user changes thresholds while headroom is already below the old threshold, **When** the new threshold is set, **Then** the threshold state machine re-evaluates immediately against current headroom **And** if headroom is above the new threshold, state resets to `aboveWarning` (re-armed) **And** if headroom is below the new threshold and no notification fired for it yet, notification fires.

## Tasks / Subtasks

- [x] Task 1: Wire threshold change notification from SettingsView to NotificationService (AC: #3)
  - [x] Add a mechanism for NotificationService to re-evaluate thresholds on preference change
  - [x] Ensure SettingsView threshold changes trigger immediate re-evaluation, not just on next poll cycle
  - [x] Add `reevaluateThresholds()` method to NotificationServiceProtocol that forces a re-evaluation using current AppState headroom values

- [x] Task 2: Implement immediate re-evaluation in NotificationService (AC: #3)
  - [x] Add `reevaluateThresholds()` to `cc-hdrm/cc-hdrm/Services/NotificationService.swift` that reads current headroom from AppState and calls `evaluateThresholds`
  - [x] Ensure re-arming logic in `evaluateThresholds` (lines 38-58) correctly handles mid-session threshold changes
  - [x] If headroom is above new warning threshold and state is `warned20` or `warned5`, reset to `aboveWarning`
  - [x] If headroom is below new threshold and state is `aboveWarning`, fire the appropriate notification

- [x] Task 3: Connect SettingsView to trigger re-evaluation (AC: #1, #2, #3)
  - [x] In `cc-hdrm/cc-hdrm/Views/SettingsView.swift`, after writing threshold changes to PreferencesManager, call the re-evaluation trigger
  - [x] Consider approach: SettingsView needs access to NotificationService (or a callback/closure) to trigger re-evaluation
  - [x] Evaluate threading: SettingsView is on MainActor, NotificationService is @MainActor — direct call is safe

- [x] Task 4: Write tests for configurable threshold behavior (AC: #1, #2, #3)
  - [x] Test: Warning notification fires at custom 30% threshold instead of default 20%
  - [x] Test: Critical notification fires at custom 10% threshold instead of default 5%
  - [x] Test: Threshold change from 20/5 to 30/10 while headroom is 25% — state re-arms (25% < 30%)
  - [x] Test: Threshold change from 20/5 to 10/3 while headroom is 15% and state is `warned20` — state stays `warned20` (15% > 10% but still below new 10%? No — 15% > 10%, so warning is still valid, critical hasn't fired)
  - [x] Test: Threshold change while headroom is above new threshold re-arms and fires new notification on next crossing
  - [x] Test: Both 5h and 7d windows independently use custom thresholds
  - [x] Test: `reevaluateThresholds()` fires notification if headroom is below new threshold with state `aboveWarning`

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. No new files needed — this story wires existing components together.
- **State flow:** SettingsView writes to PreferencesManager → NotificationService reads from PreferencesManager on each `evaluateThresholds` call (already hot-reconfigurable from Story 6.1).
- **Key insight:** The threshold re-arming logic already exists in `NotificationService.evaluateThresholds` (lines 38-58). The `lastWarningThreshold`/`lastCriticalThreshold` tracking detects changes and re-arms when appropriate. The main gap is: **threshold changes only take effect on the next poll cycle** (every 30s). This story may need to trigger an immediate re-evaluation when thresholds change.
- **Concurrency:** NotificationService is `@MainActor`. SettingsView runs on MainActor. Direct calls are safe.

### Key Implementation Details

**The re-arming logic already works.** Story 6.1 implemented threshold change detection in `evaluateThresholds` (lines 38-58 of NotificationService.swift):
- Each call reads fresh thresholds from PreferencesManager
- Compares to `lastWarningThreshold`/`lastCriticalThreshold`
- If changed and headroom >= new warning threshold: resets state to `.aboveWarning`
- Updates last-used values

**What's missing for immediate effect:**

Currently, `evaluateThresholds` is only called from `PollingEngine` during poll cycles. If the user changes thresholds in Settings, the change won't be evaluated until the next poll (up to 30s delay). Two approaches:

**Option A (Recommended): Add `reevaluateThresholds()` to NotificationService**
- New method that reads current headroom from AppState and calls the existing `evaluateThresholds`
- Wire into SettingsView via closure or direct reference
- Pro: Immediate feedback. Con: Requires NotificationService access from SettingsView.

**Option B: Accept poll-cycle delay**
- The re-arming logic already works on next poll. 30s max delay.
- Pro: Zero new code. Con: User changes threshold, notification fires 30s later — confusing UX.

**Recommended wiring for Option A:**

Thread `NotificationService` (or a closure) through the view hierarchy alongside `PreferencesManager`:

```swift
// In SettingsView, after threshold .onChange:
preferencesManager.warningThreshold = newValue
// ... re-read values ...
onThresholdChange?()  // Trigger re-evaluation
```

Or pass `notificationService.reevaluateThresholds` as a closure:
```swift
// AppDelegate wiring:
let onThresholdChange = { [notificationService, appState] in
    // Read current headroom from appState, call evaluateThresholds
}
```

**IMPORTANT: evaluateThresholds requires WindowState parameters.** It needs current headroom values from AppState. The `reevaluateThresholds` method must access AppState to extract current `fiveHourHeadroom` and `sevenDayHeadroom` (or their `WindowState` equivalents).

**Existing evaluateWindow default parameters:** `evaluateWindow` already uses `PreferencesDefaults` values as default parameters (lines 106-107 of NotificationService.swift). Custom thresholds are passed explicitly from `evaluateThresholds`. This means direct `evaluateWindow` calls in tests still use defaults unless overridden — existing tests remain unaffected.

**Notification format unchanged:** Warning and critical notification content format is identical to Stories 5.2/5.3. Only the threshold VALUES change, not the notification text format. The body already reads: `"Claude headroom at [X]% — resets in [relative] (at [absolute])"`.

### Previous Story Intelligence (6.2)

**What was built:**
- `SettingsView.swift` at `cc-hdrm/cc-hdrm/Views/SettingsView.swift` — Stepper controls for warning (6-50%) and critical (1-49%) thresholds
- onChange pattern: writes to PreferencesManager, re-reads both thresholds to handle clamping/reset
- `isUpdating` guard prevents re-entrant onChange loops
- PreferencesManager threaded through: AppDelegate → PopoverView → PopoverFooterView → GearMenuView → SettingsView (via .sheet)
- PreferencesManagerProtocol is `: AnyObject` (set in 6.2)
- 318 tests passing, zero regressions

**What was built in 6.1:**
- `NotificationService.evaluateThresholds` reads fresh from PreferencesManager each call
- `lastWarningThreshold`/`lastCriticalThreshold` change detection with re-arming
- `evaluateWindow` accepts configurable thresholds via parameters (defaults to PreferencesDefaults)
- PreferencesManager cross-validates warning > critical, restores defaults on violation
- MockPreferencesManager for test injection

**Code review lessons from 6.2:**
- Added `isUpdating` re-entrancy guard to ALL .onChange handlers — follow this pattern if adding new onChange triggers
- PreferencesManager is exposed as `internal` on AppDelegate for testability
- Sheet presentation pattern: `.sheet(isPresented:)` on the Menu's outer view, NOT inside menu items

### Git Intelligence

Last 2 commits: Stories 6.1 and 6.2 (preferences + settings UI). Key files changed:
- `NotificationService.swift` — threshold parameterization, re-arming logic
- `PreferencesManager.swift` — full implementation with clamping
- `SettingsView.swift` — threshold controls with onChange
- `AppDelegate.swift` — service wiring, preferencesManager as instance property

### No Tests Yet for Re-Arming Logic

The `ThresholdStateMachineTests.swift` (614 lines) covers state machine transitions, fire-once, recovery, independent windows, boundary conditions, notification content — but does NOT test:
- Threshold change mid-session re-arming (`lastWarningThreshold`/`lastCriticalThreshold` logic)
- Custom threshold values passed to `evaluateThresholds` (tests use default 20/5)
- `reevaluateThresholds()` if implemented

This is a critical testing gap that story 6.3 must fill.

### Project Structure Notes

- No new files expected — this story modifies existing files
- If `reevaluateThresholds()` is added, it goes in `NotificationService.swift` and `NotificationServiceProtocol.swift`
- Test additions go in `cc-hdrm/cc-hdrmTests/Services/ThresholdStateMachineTests.swift`

### File Structure Requirements

Files to MODIFY:
```
cc-hdrm/cc-hdrm/Services/NotificationService.swift           # MODIFY — add reevaluateThresholds() method
cc-hdrm/cc-hdrm/Services/NotificationServiceProtocol.swift   # MODIFY — add reevaluateThresholds() to protocol
cc-hdrm/cc-hdrm/Views/SettingsView.swift                     # MODIFY — trigger re-evaluation on threshold change
cc-hdrm/cc-hdrm/Views/GearMenuView.swift                     # MODIFY — pass re-evaluation callback or notificationService through
cc-hdrm/cc-hdrm/Views/PopoverFooterView.swift                # MODIFY — pass re-evaluation callback through
cc-hdrm/cc-hdrm/Views/PopoverView.swift                      # MODIFY — pass re-evaluation callback through
cc-hdrm/cc-hdrm/App/AppDelegate.swift                        # MODIFY — wire re-evaluation closure/service to PopoverView
cc-hdrm/cc-hdrmTests/Services/ThresholdStateMachineTests.swift # MODIFY — add tests for custom thresholds and re-arming
```

Files NOT to modify:
```
cc-hdrm/cc-hdrm/cc_hdrm.entitlements                         # PROTECTED — do not touch
cc-hdrm/cc-hdrm/Services/PreferencesManager.swift            # No changes needed — already complete from 6.1
cc-hdrm/cc-hdrm/Services/PreferencesManagerProtocol.swift    # No changes needed
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on all notification tests
- **Mock strategy:** Use existing `MockPreferencesManager` and `SpyNotificationCenter`
- **Key test scenarios:**
  - Custom 30%/10% thresholds fire at correct levels
  - Threshold change re-arms state when headroom >= new warning
  - Threshold change fires notification when headroom < new threshold and state was `aboveWarning`
  - Both 5h and 7d independently respect custom thresholds
  - `reevaluateThresholds()` reads from AppState and triggers correct state transitions
  - Default threshold behavior unchanged (existing tests must still pass)
- **Regression:** All 318+ existing tests must continue passing (zero regressions)

### Library & Framework Requirements

- No new dependencies. Zero external packages.
- All frameworks already imported in affected files.

### Anti-Patterns to Avoid

- DO NOT duplicate threshold validation in SettingsView or NotificationService — PreferencesManager handles all clamping
- DO NOT store threshold values separately from PreferencesManager — always read fresh
- DO NOT bypass the existing re-arming logic in evaluateThresholds — extend it, don't replace it
- DO NOT modify `cc-hdrm/cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT change notification content format — only threshold VALUES change
- DO NOT use `DispatchQueue` or GCD — structured concurrency only
- DO NOT use `print()` — use `os.Logger`
- DO NOT break backward compatibility of `evaluateWindow` default parameters — existing tests rely on them
- DO NOT pass NotificationService directly to SettingsView if a closure approach is cleaner — evaluate both options

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` #Story 6.3] — Full acceptance criteria for Configurable Notification Thresholds
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Settings Persistence] — Hot-reconfigurable preference reads
- [Source: `cc-hdrm/cc-hdrm/Services/NotificationService.swift` lines 33-58] — evaluateThresholds with threshold change detection and re-arming
- [Source: `cc-hdrm/cc-hdrm/Services/NotificationService.swift` lines 103-133] — evaluateWindow pure state machine with configurable threshold params
- [Source: `cc-hdrm/cc-hdrm/Services/NotificationService.swift` lines 27-28] — lastWarningThreshold/lastCriticalThreshold init
- [Source: `cc-hdrm/cc-hdrm/Services/NotificationServiceProtocol.swift` lines 1-10] — ThresholdState enum
- [Source: `cc-hdrm/cc-hdrm/Services/PreferencesManager.swift` lines 28-92] — warningThreshold/criticalThreshold getters/setters with cross-validation
- [Source: `cc-hdrm/cc-hdrm/Views/SettingsView.swift` lines 33-75] — Threshold stepper controls with onChange pattern
- [Source: `cc-hdrm/cc-hdrm/Views/SettingsView.swift` lines 43-51] — onChange writes to PreferencesManager, re-reads both values
- [Source: `cc-hdrm/cc-hdrmTests/Services/ThresholdStateMachineTests.swift`] — 614 lines of existing threshold tests (no re-arming tests yet)
- [Source: `cc-hdrm/cc-hdrmTests/Mocks/MockPreferencesManager.swift`] — In-memory mock for test injection
- [Source: `cc-hdrm/cc-hdrmTests/Mocks/SpyNotificationCenter.swift`] — Spy for notification delivery verification
- [Source: `_bmad-output/implementation-artifacts/6-1-preferences-manager-userdefaults-persistence.md`] — PreferencesManager details, threshold re-arming design
- [Source: `_bmad-output/implementation-artifacts/6-2-settings-view-ui.md`] — SettingsView binding pattern, view hierarchy wiring
- [Source: `_bmad-output/planning-artifacts/project-context.md`] — Architecture overview, coding patterns

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

None — clean implementation, no debugging required.

### Completion Notes List

- ✅ Implemented Option A from Dev Notes: added `reevaluateThresholds()` to `NotificationServiceProtocol` and `NotificationService`
- ✅ `reevaluateThresholds()` reads current `fiveHour`/`sevenDay` from `AppState` via weak reference, calls existing `evaluateThresholds`
- ✅ Added `weak var appState: AppState?` to `NotificationService`, wired in `AppDelegate.applicationDidFinishLaunching`
- ✅ Threaded `onThresholdChange` closure through view hierarchy: AppDelegate → PopoverView → PopoverFooterView → GearMenuView → SettingsView
- ✅ SettingsView calls `onThresholdChange?()` after both warning and critical `.onChange` handlers, and after "Reset to Defaults"
- ✅ Existing re-arming logic in `evaluateThresholds` (lines 38-58) handles all AC #3 scenarios — no modifications needed
- ✅ 11 new tests covering: custom warning/critical thresholds, re-arming on threshold change, threshold lowering, both windows independent, `reevaluateThresholds()` with AppState, nil appState safety, `evaluateWindow` with custom params
- ✅ All 329 tests pass (318 existing + 11 new), zero regressions
- ✅ No new dependencies, no new files created — only modified existing files as specified

### Change Log

- 2026-02-02: Story 6.3 implementation complete — configurable notification thresholds with immediate re-evaluation on preference change
- 2026-02-02: Code review (claude-opus-4-5) — 0 HIGH, 1 MEDIUM, 4 LOW issues found and fixed. Added onThresholdChange closure test, thread-safety comments, Task wrapper comment, sprint-status.yaml to File List. 330 tests passing.

### File List

- `cc-hdrm/cc-hdrm/Services/NotificationService.swift` — added `weak var appState`, `reevaluateThresholds()` method
- `cc-hdrm/cc-hdrm/Services/NotificationServiceProtocol.swift` — added `reevaluateThresholds()` to protocol
- `cc-hdrm/cc-hdrm/Views/SettingsView.swift` — added `onThresholdChange` closure, called from threshold `.onChange` and Reset
- `cc-hdrm/cc-hdrm/Views/GearMenuView.swift` — added `onThresholdChange` pass-through, forwarded to SettingsView
- `cc-hdrm/cc-hdrm/Views/PopoverFooterView.swift` — added `onThresholdChange` pass-through to GearMenuView
- `cc-hdrm/cc-hdrm/Views/PopoverView.swift` — added `onThresholdChange` pass-through to PopoverFooterView
- `cc-hdrm/cc-hdrm/App/AppDelegate.swift` — wired `onThresholdChange` closure calling `notificationService.reevaluateThresholds()`, set `appState` on NotificationService
- `cc-hdrm/cc-hdrmTests/Services/ThresholdStateMachineTests.swift` — added 11 tests for custom thresholds, re-arming, reevaluateThresholds
- `cc-hdrm/cc-hdrmTests/Mocks/MockNotificationService.swift` — added `reevaluateThresholds()` stub + call counter
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — story status updated to done
- `cc-hdrm/cc-hdrmTests/Views/SettingsViewTests.swift` — added onThresholdChange closure acceptance test (code review fix)
