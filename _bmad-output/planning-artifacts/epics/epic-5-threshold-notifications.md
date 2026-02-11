# Epic 5: Threshold Notifications

Alex gets notified before he hits the wall — macOS notifications fire at 20% and 5% headroom for both windows independently, with full context including reset countdowns and absolute times. Never misses a warning, even when AFK.

## Story 5.1: Notification Permission & Service Setup

As a developer using Claude Code,
I want the app to set up macOS notification capabilities,
So that threshold alerts can be delivered when headroom drops.

**Acceptance Criteria:**

**Given** the app launches for the first time
**When** the NotificationService initializes
**Then** it requests notification authorization via UserNotifications framework
**And** authorization status is tracked in AppState or NotificationService internal state
**And** if the user denies permission, the app continues functioning without notifications (no crash, no nag)

**Given** the app launches on subsequent runs
**When** the NotificationService initializes
**Then** it checks existing authorization status without re-prompting

## Story 5.2: Threshold State Machine & Warning Notifications

**Referenced Requirements:**
- FR17: User receives macOS notification when 5-hour headroom drops below 20%
- FR19: App includes reset countdown time in notification messages

As a developer using Claude Code,
I want to receive a macOS notification when my headroom drops below 20%,
So that I can make informed decisions about which Claude sessions to prioritize.

**Acceptance Criteria:**

**Given** 5-hour headroom is above 20%
**When** a poll cycle reports 5-hour headroom below 20%
**Then** a macOS notification fires: "Claude headroom at [X]% — resets in [relative] (at [absolute])" (FR17, FR19)
**Example format:** "Claude headroom at 18% — resets in 2h 15m (at 5:30 PM)"
**And** the notification is standard (not persistent)
**And** the threshold state transitions from ABOVE_20 to WARNED_20

**Given** the 5-hour threshold state is WARNED_20
**When** subsequent poll cycles report headroom still below 20% but above 5%
**Then** no additional notification fires (fire once per crossing)

**Given** 7-day headroom drops below 20% independently of 5-hour
**When** a poll cycle reports the crossing
**Then** a separate notification fires: "Claude 7-day headroom at [X]% — resets in [relative] (at [absolute])"
**And** 5h and 7d threshold states are tracked independently

**Given** headroom recovers above 20% (window reset)
**When** a poll cycle reports the recovery
**Then** the threshold state resets to ABOVE_20 (re-armed)
**And** if headroom drops below 20% again, a new notification fires

## Story 5.3: Critical Threshold & Persistent Notifications

**Referenced Requirements:**
- FR18: User receives macOS notification when 5-hour headroom drops below 5%
- FR19: App includes reset countdown time in notification messages

As a developer using Claude Code,
I want to receive a persistent notification when my headroom drops below 5%,
So that I have maximum warning to wrap up before hitting the limit.

**Acceptance Criteria:**

**Given** the threshold state is WARNED_20 (already received 20% warning)
**When** a poll cycle reports headroom below 5%
**Then** a macOS notification fires with `.timeSensitive` interruption level and sound: "Claude headroom at [X]% — resets in [relative] (at [absolute])" (FR18, FR19)
**And** the notification remains in Notification Center
**Note:** Whether the notification appears as a banner (auto-dismisses) or alert (stays on-screen) is controlled by the user's macOS notification settings, not by the app. The `.timeSensitive` level allows breaking through Focus modes (requires Time Sensitive Notifications entitlement: `com.apple.developer.usernotifications.time-sensitive`).
**And** the threshold state transitions from WARNED_20 to WARNED_5

**Given** headroom drops directly from above 20% to below 5% in a single poll
**When** the crossing is detected
**Then** only the critical (5%) notification fires (skip the 20% notification — go straight to the more urgent alert)
**And** the threshold state transitions to WARNED_5

**Given** the threshold state is WARNED_5
**When** subsequent poll cycles report headroom still below 5%
**Then** no additional notification fires

**Given** headroom recovers above 20% after being in WARNED_5
**When** a poll cycle reports the recovery
**Then** both thresholds re-arm (state returns to ABOVE_20)

**Given** notification permission was denied by the user
**When** a threshold crossing occurs
**Then** no notification is attempted, no error is shown
**And** the menu bar color/weight changes still reflect the state (visual fallback)
