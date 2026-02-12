# Story 16.2: Pattern Notification & Analytics Display

Status: review

## Story

As a developer using Claude Code,
I want slow-burn pattern findings to surface as macOS notifications and appear in the analytics view,
so that I'm alerted to costly patterns even when I'm not looking at the app.

## Acceptance Criteria

1. **Given** SubscriptionPatternDetector returns a .forgottenSubscription finding
   **When** the finding is new (not previously notified)
   **Then** a macOS notification is delivered:
   - Title: "Subscription check-in"
   - Body: "You've used less than 5% of your Claude capacity for [N] weeks. Worth reviewing?"
   - Action: Opens analytics window

2. **Given** SubscriptionPatternDetector returns a .chronicOverpaying finding
   **When** the finding is new (not previously notified)
   **Then** a macOS notification is delivered:
   - Title: "Tier recommendation"
   - Body: "Your usage fits [recommended tier] -- you could save $[amount]/mo"
   - Action: Opens analytics window

3. **Given** SubscriptionPatternDetector returns a .chronicUnderpowering finding
   **When** the finding is new (not previously notified)
   **Then** a macOS notification is delivered:
   - Title: "Tier recommendation"
   - Body: "You've been rate-limited [N] times recently. [higher tier] would cover your usage."
   - Action: Opens analytics window

4. **Given** a pattern finding has already been notified
   **When** the same pattern is detected again within 30 days
   **Then** no duplicate notification is sent
   **And** the cooldown period is tracked in UserDefaults

5. **Given** the analytics window is open and pattern findings exist
   **When** the value section renders
   **Then** active findings appear as a compact insight card below the subscription value bar
   **And** each card shows the finding summary in natural language
   **And** cards are dismissable (dismissed state persisted)

6. **Given** the user has disabled notifications in system preferences
   **When** a pattern is detected
   **Then** findings still appear in the analytics view
   **And** no macOS notification is attempted

7. **Given** the user dismisses a pattern finding card in the analytics view
   **When** the same pattern is detected again (within the same conditions)
   **Then** the card does not reappear until the pattern conditions change materially

## Tasks / Subtasks

- [x] Task 1: Add pattern notification cooldown tracking to PreferencesManager (AC: 4)
- [x] Task 2: Create PatternNotificationService (AC: 1-4, 6)
- [x] Task 3: Wire pattern analysis trigger into PollingEngine (AC: 1-3)
- [x] Task 4: Create PatternFindingCard SwiftUI component (AC: 5, 7)
- [x] Task 5: Integrate pattern findings into AnalyticsView value section (AC: 5, 6)
- [x] Task 6: Create MockPatternNotificationService (for tests)
- [x] Task 7: Write unit tests for PatternNotificationService (AC: 1-4, 6)
- [x] Task 8: Add cooldownKey to PatternFinding model (AC: 4)
- [x] Task 9: Run xcodegen generate and verify compilation + tests pass

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (claude-opus-4-6)

### Completion Notes List

- PatternNotificationService delivers macOS notifications for forgottenSubscription, chronicOverpaying, chronicUnderpowering only
- Other finding types (usageDecay, extraUsageOverflow, persistentExtraUsage) are display-only in analytics view
- 30-day cooldown per finding type tracked in UserDefaults via patternNotificationCooldowns
- Dismissed findings persisted in UserDefaults via dismissedPatternFindings
- Pattern analysis runs unconditionally after each persistPoll (fire-and-forget) -- cooldown logic prevents duplicate notifications
- PatternFinding.cooldownKey provides deterministic key based on finding type only (not associated values)
- AnalyticsView loads findings on appear and displays dismissable PatternFindingCard instances
- AnalyticsWindow.configure() extended with optional patternDetector and preferencesManager
- PollingEngine extended with optional patternDetector and patternNotificationService dependencies
- All 959 tests pass (12 new tests for PatternNotificationService + 2 new cooldownKey tests)

### File List

New files:
- cc-hdrm/Services/PatternNotificationServiceProtocol.swift
- cc-hdrm/Services/PatternNotificationService.swift
- cc-hdrm/Views/PatternFindingCard.swift
- cc-hdrmTests/Mocks/MockPatternNotificationService.swift
- cc-hdrmTests/Services/PatternNotificationServiceTests.swift

Modified files:
- cc-hdrm/Models/PatternFinding.swift (added cooldownKey computed property)
- cc-hdrm/Services/PreferencesManagerProtocol.swift (added patternNotificationCooldowns, dismissedPatternFindings)
- cc-hdrm/Services/PreferencesManager.swift (added Keys + implementations for cooldowns/dismissals + resetToDefaults)
- cc-hdrm/Services/PollingEngine.swift (added patternDetector + patternNotificationService dependencies, pattern analysis after persistPoll)
- cc-hdrm/Views/AnalyticsView.swift (added patternDetector + preferencesManager params, pattern finding cards in value section)
- cc-hdrm/Views/AnalyticsWindow.swift (added patternDetector + preferencesManager to configure(), createPanel(), reset())
- cc-hdrm/App/AppDelegate.swift (wired up SubscriptionPatternDetector + PatternNotificationService)
- cc-hdrmTests/Mocks/MockPreferencesManager.swift (added patternNotificationCooldowns, dismissedPatternFindings)
- cc-hdrmTests/Models/PatternFindingTests.swift (added cooldownKey tests)
