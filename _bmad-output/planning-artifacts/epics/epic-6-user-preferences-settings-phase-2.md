# Epic 6: User Preferences & Settings (Phase 2)

Alex tweaks cc-hdrm to fit his workflow — adjustable notification thresholds, custom poll interval, launch at login. All accessible from a settings view in the gear menu, all taking effect immediately.

## Story 6.1: Preferences Manager & UserDefaults Persistence

As a developer using Claude Code,
I want my preference changes to persist across app restarts,
So that I configure cc-hdrm once and it remembers my choices.

**Acceptance Criteria:**

**Given** the app launches for the first time (no UserDefaults entries exist)
**When** PreferencesManager initializes
**Then** it provides default values: warning threshold 20%, critical threshold 5%, poll interval 30s, launch at login false, dismissedVersion nil
**And** PreferencesManager conforms to PreferencesManagerProtocol for testability

**Given** the user changes a preference via the settings view
**When** the value is written to UserDefaults
**Then** it persists across app restarts
**And** the new value takes effect immediately without requiring restart

**Given** the user sets warning threshold to 15% and critical threshold to 3%
**When** the next poll cycle evaluates thresholds
**Then** NotificationService uses 15% and 3% instead of the defaults
**And** threshold state machines re-arm based on new thresholds

**Given** the user sets poll interval to 60 seconds
**When** the current poll cycle completes
**Then** PollingEngine waits 60 seconds before the next cycle (hot-reconfigurable)

**Given** UserDefaults contains an invalid value (e.g. poll interval of 5 seconds)
**When** PreferencesManager reads the value
**Then** it clamps to the valid range (min 10s, max 300s) and uses the clamped value
**And** warning threshold must be > critical threshold — if violated, defaults are restored

## Story 6.2: Settings View UI

As a developer using Claude Code,
I want to access a settings view from the gear menu,
So that I can configure cc-hdrm's behavior without editing files.

**Acceptance Criteria:**

**Given** the popover is open and Alex clicks the gear icon
**When** the gear menu appears
**Then** it shows "Settings..." as a menu item above "Quit cc-hdrm" (FR30)

**Given** Alex selects "Settings..."
**When** the settings view opens
**Then** it displays:
**And** Warning threshold: stepper or slider (range 6-50%, default 20%)
**And** Critical threshold: stepper or slider (range 1-49%, must be < warning threshold)
**And** Poll interval: picker with options 10s, 15s, 30s, 60s, 120s, 300s (default 30s)
**And** Launch at login: toggle switch (default off)
**And** "Reset to Defaults" button

**Given** Alex changes any preference value
**When** the value changes
**Then** it takes effect immediately (no save button required)
**And** the value is persisted to UserDefaults via @AppStorage bindings

**Given** Alex clicks "Reset to Defaults"
**When** the reset executes
**Then** all preferences return to default values (20%, 5%, 30s, off)
**And** changes take effect immediately

**Given** a VoiceOver user navigates the settings view
**When** VoiceOver reads each control
**Then** each has a descriptive accessibility label (e.g., "Warning notification threshold, 20 percent")

## Story 6.3: Configurable Notification Thresholds

As a developer using Claude Code,
I want to set my own notification thresholds,
So that I get alerted at the headroom levels that matter for my workflow.

**Acceptance Criteria:**

**Given** the user has set warning threshold to 30% and critical threshold to 10%
**When** 5-hour headroom drops below 30%
**Then** a warning notification fires with the same format as Story 5.2 (FR27)
**And** the 20% default is no longer used

**Given** the user has set critical threshold to 10%
**When** headroom drops below 10% (after warning has fired)
**Then** a critical notification fires with the same format as Story 5.3 (FR27)

**Given** the user changes thresholds while headroom is already below the old threshold
**When** the new threshold is set
**Then** the threshold state machine re-evaluates immediately against current headroom
**And** if headroom is above the new threshold, state resets to ABOVE_WARNING (re-armed)
**And** if headroom is below the new threshold and no notification fired for it yet, notification fires

## Story 6.4: Launch at Login

As a developer using Claude Code,
I want cc-hdrm to start automatically when I log in,
So that usage monitoring is always running without me remembering to launch it.

**Acceptance Criteria:**

**Given** the user enables "Launch at login" in settings
**When** the toggle is switched on
**Then** the app registers as a login item via SMAppService.mainApp.register() (FR29)
**And** on next macOS login, cc-hdrm launches automatically

**Given** the user disables "Launch at login" in settings
**When** the toggle is switched off
**Then** the app unregisters via SMAppService.mainApp.unregister()
**And** cc-hdrm no longer launches on login

**Given** the app launches
**When** PreferencesManager reads the launchAtLogin preference
**Then** the toggle in settings reflects the actual SMAppService.mainApp.status (not just the stored preference)
**And** if there's a mismatch (user changed it in System Settings), the UI reflects reality
