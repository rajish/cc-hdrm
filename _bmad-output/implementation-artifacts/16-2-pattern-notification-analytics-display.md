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

- [x] Task 1: Add cooldownKey to PatternFinding model (AC: 4)
  - [x] 1.1 Add `var cooldownKey: String` computed property to `cc-hdrm/Models/PatternFinding.swift`
  - [x] 1.2 Return deterministic key based on finding type only (not associated values), e.g. `"forgottenSubscription"`
  - [x] 1.3 Add unit tests for cooldownKey in `cc-hdrmTests/Models/PatternFindingTests.swift`

- [x] Task 2: Add pattern notification cooldown tracking to PreferencesManager (AC: 4, 7)
  - [x] 2.1 Add `patternNotificationCooldowns: [String: Date]` to `cc-hdrm/Services/PreferencesManagerProtocol.swift`
  - [x] 2.2 Add `dismissedPatternFindings: Set<String>` to `cc-hdrm/Services/PreferencesManagerProtocol.swift`
  - [x] 2.3 Implement both properties in `cc-hdrm/Services/PreferencesManager.swift` with UserDefaults Keys
  - [x] 2.4 Clear both in `resetToDefaults()` method
  - [x] 2.5 Add both properties to `cc-hdrmTests/Mocks/MockPreferencesManager.swift`

- [x] Task 3: Create PatternNotificationServiceProtocol (AC: 1-3)
  - [x] 3.1 Create `cc-hdrm/Services/PatternNotificationServiceProtocol.swift`
  - [x] 3.2 Define `func processFindings(_ findings: [PatternFinding]) async`
  - [x] 3.3 Add `@MainActor` and `Sendable` conformance

- [x] Task 4: Implement PatternNotificationService (AC: 1-4, 6)
  - [x] 4.1 Create `cc-hdrm/Services/PatternNotificationService.swift` conforming to protocol
  - [x] 4.2 Constructor takes `NotificationCenterProtocol`, `PreferencesManagerProtocol`, `NotificationServiceProtocol`
  - [x] 4.3 Implement `isNotifiableType()` -- only forgottenSubscription, chronicOverpaying, chronicUnderpowering trigger notifications
  - [x] 4.4 Implement `shouldNotify()` -- check 30-day cooldown per cooldownKey
  - [x] 4.5 Implement `sendNotification()` -- build UNNotificationRequest with correct title/body per finding type
  - [x] 4.6 Implement `notificationBody()` -- match AC 1-3 body text exactly
  - [x] 4.7 Check `notificationService.isAuthorized` before sending (AC: 6)
  - [x] 4.8 Update cooldown timestamp in PreferencesManager after successful notification
  - [x] 4.9 Add `os.Logger` with category `"pattern-notification"`

- [x] Task 5: Wire pattern analysis trigger into PollingEngine (AC: 1-3)
  - [x] 5.1 Add `patternDetector: (any SubscriptionPatternDetectorProtocol)?` to `cc-hdrm/Services/PollingEngine.swift` init
  - [x] 5.2 Add `patternNotificationService: (any PatternNotificationServiceProtocol)?` to init
  - [x] 5.3 After `persistPoll()` call, run `detector.analyzePatterns()` and pass findings to notifier (fire-and-forget Task)

- [x] Task 6: Create PatternFindingCard SwiftUI component (AC: 5, 7)
  - [x] 6.1 Create `cc-hdrm/Views/PatternFindingCard.swift`
  - [x] 6.2 Display finding title (`.caption` bold) and summary (`.caption2` secondary) in HStack
  - [x] 6.3 Add dismiss button (xmark icon) with `onDismiss` callback
  - [x] 6.4 Style with `.quaternary.opacity(0.5)` background, 6pt corner radius, compact padding

- [x] Task 7: Integrate pattern findings into AnalyticsView value section (AC: 5, 6, 7)
  - [x] 7.1 Add `patternDetector` and `preferencesManager` optional parameters to `cc-hdrm/Views/AnalyticsView.swift`
  - [x] 7.2 Add `@State private var patternFindings: [PatternFinding]` state
  - [x] 7.3 Add `.task` modifier to call `loadPatternFindings()` on appear
  - [x] 7.4 Build `patternFindingCards` ViewBuilder filtering out dismissed findings
  - [x] 7.5 Implement `dismissFinding()` to persist dismissal and update local state
  - [x] 7.6 Insert cards between value bar and summary in value section

- [x] Task 8: Update AnalyticsWindow to pass new dependencies (AC: 5)
  - [x] 8.1 Add `patternDetector` and `preferencesManager` parameters to `cc-hdrm/Views/AnalyticsWindow.swift` configure/createPanel/reset methods
  - [x] 8.2 Pass through to AnalyticsView initializer

- [x] Task 9: Wire up dependencies in AppDelegate (AC: 1-3)
  - [x] 9.1 Create `SubscriptionPatternDetector` and `PatternNotificationService` instances in `cc-hdrm/App/AppDelegate.swift`
  - [x] 9.2 Pass to PollingEngine and AnalyticsWindow

- [x] Task 10: Create MockPatternNotificationService (for tests)
  - [x] 10.1 Create `cc-hdrmTests/Mocks/MockPatternNotificationService.swift`
  - [x] 10.2 Add `processedFindings: [[PatternFinding]]` and `processCallCount` tracking

- [x] Task 11: Write unit tests for PatternNotificationService (AC: 1-4, 6)
  - [x] 11.1 Create `cc-hdrmTests/Services/PatternNotificationServiceTests.swift`
  - [x] 11.2 Test forgottenSubscription delivers notification with correct title/body (AC: 1)
  - [x] 11.3 Test chronicOverpaying delivers notification with correct title/body (AC: 2)
  - [x] 11.4 Test chronicUnderpowering delivers notification with correct title/body (AC: 3)
  - [x] 11.5 Test cooldown prevents duplicate notification within 30 days (AC: 4)
  - [x] 11.6 Test cooldown expired allows re-notification (AC: 4)
  - [x] 11.7 Test cooldown timestamp updated after notification (AC: 4)
  - [x] 11.8 Test notifications skipped when not authorized (AC: 6)
  - [x] 11.9 Test usageDecay and extraUsageOverflow do NOT trigger notifications
  - [x] 11.10 Test empty findings array produces no notifications

- [x] Task 12: Run `xcodegen generate` and verify compilation + tests pass

## Dev Notes

### Architecture Context

This story extends Story 16.1's pattern detection with user-facing output: macOS notifications and analytics view cards. It follows the established protocol-based service pattern and integrates into the existing PollingEngine and AnalyticsView infrastructure.

**Key design decisions:**
- `PatternNotificationService` is a thin adapter between pattern findings and `UNUserNotificationCenter`
- Only 3 of 6 finding types trigger notifications (the "actionable" ones); the rest are display-only in analytics
- 30-day cooldown per finding type (not per finding value) prevents notification fatigue
- Pattern analysis runs fire-and-forget after each `persistPoll()` -- does not block the polling cycle
- Analytics view loads findings independently on appear, filtered by dismiss state

### Key Integration Points

**Files consumed (read-only):**
- `cc-hdrm/Services/SubscriptionPatternDetectorProtocol.swift` -- `analyzePatterns()` API from Story 16.1
- `cc-hdrm/Models/PatternFinding.swift` -- enum cases with `title`, `summary` computed properties (Story 16.1)
- `cc-hdrm/Services/NotificationServiceProtocol.swift` -- `isAuthorized` check for notification permission
- `cc-hdrm/Services/PollingEngineProtocol.swift` -- existing polling lifecycle
- `cc-hdrm/Views/AnalyticsView.swift:92-134` -- value section layout where cards are inserted
- `cc-hdrm/Views/AnalyticsWindow.swift` -- panel configuration and dependency passing

**Files modified:**
- `cc-hdrm/Models/PatternFinding.swift` -- add `cooldownKey` computed property
- `cc-hdrm/Services/PreferencesManagerProtocol.swift` -- add `patternNotificationCooldowns` and `dismissedPatternFindings`
- `cc-hdrm/Services/PreferencesManager.swift` -- implement cooldown/dismissal storage with UserDefaults
- `cc-hdrm/Services/PollingEngine.swift` -- add `patternDetector` and `patternNotificationService` optional dependencies, call after `persistPoll()`
- `cc-hdrm/Views/AnalyticsView.swift` -- add `patternDetector`/`preferencesManager` params, pattern finding cards in value section
- `cc-hdrm/Views/AnalyticsWindow.swift` -- pass new dependencies through configure/createPanel/reset
- `cc-hdrm/App/AppDelegate.swift` -- wire up SubscriptionPatternDetector and PatternNotificationService

**Existing mocks available:**
- `cc-hdrmTests/Mocks/MockPreferencesManager.swift` -- add `patternNotificationCooldowns`, `dismissedPatternFindings`
- `cc-hdrmTests/Mocks/MockNotificationService.swift` -- has `isAuthorized` flag
- `cc-hdrmTests/Mocks/SpyNotificationCenter.swift` -- captures `addedRequests` for verification

### Notification Architecture

Three finding types trigger macOS notifications:
1. `.forgottenSubscription` -- Title: "Subscription check-in", Body includes weeks count
2. `.chronicOverpaying` -- Title: "Tier recommendation", Body includes recommended tier and savings
3. `.chronicUnderpowering` -- Title: "Tier recommendation", Body includes rate-limit count and suggested tier

Three finding types are display-only (analytics view cards only):
4. `.usageDecay` -- informational, no actionable recommendation
5. `.extraUsageOverflow` -- overlaps with chronicUnderpowering
6. `.persistentExtraUsage` -- overlaps with chronicOverpaying

### Cooldown Mechanism

```swift
// Key: PatternFinding.cooldownKey (type-based, e.g. "forgottenSubscription")
// Value: Date when last notified
var patternNotificationCooldowns: [String: Date]

// Cooldown check:
let interval = TimeInterval(30 * 24 * 60 * 60) // 30 days
return Date().timeIntervalSince(lastNotified) >= interval
```

Cooldown is type-based, not value-based: if a user is notified about `forgottenSubscription(weeks: 3)`, a subsequent `forgottenSubscription(weeks: 4)` won't re-notify within 30 days. This prevents notification fatigue while still updating the analytics card.

### Dismiss Persistence

Dismissed findings use a separate `Set<String>` in UserDefaults (not the cooldown dict). A dismissed finding stays dismissed until:
- The finding type stops being detected (conditions change materially)
- The user resets preferences

### PollingEngine Integration

Pattern analysis is wired as a fire-and-forget `Task` after `persistPoll()`:

```swift
Task { [patternDetector, patternNotificationService] in
    try await historicalDataService?.persistPoll(response, tier: tier)
    if let detector = patternDetector, let notifier = patternNotificationService {
        let findings = try await detector.analyzePatterns()
        if !findings.isEmpty {
            await notifier.processFindings(findings)
        }
    }
}
```

**Important:** The `patternDetector` and `patternNotificationService` are captured explicitly in the Task closure to avoid capturing `self`.

### Potential Pitfalls

1. **Cooldown key must be type-based:** Using associated values in the cooldown key would mean `forgottenSubscription(weeks: 3)` and `forgottenSubscription(weeks: 4)` are different keys, causing duplicate notifications. The cooldownKey must strip associated values.

2. **Dismiss vs. cooldown are separate concerns:** Dismiss = user action in analytics UI (persisted in `dismissedPatternFindings`). Cooldown = notification throttle (persisted in `patternNotificationCooldowns`). They serve different purposes and use different storage.

3. **Authorization check before notification:** Check `notificationService.isAuthorized` before attempting to send. Do NOT call `UNUserNotificationCenter.requestAuthorization()` -- the app handles that at startup.

4. **`@MainActor` on service:** `PatternNotificationService` is `@MainActor` because `UNUserNotificationCenter` interactions should be on main actor. The protocol must also be `@MainActor`.

5. **Optional dependencies in PollingEngine:** Both `patternDetector` and `patternNotificationService` are optional to maintain backward compatibility with existing PollingEngine callers and tests.

6. **Analytics view loads findings independently:** The view calls `analyzePatterns()` in a `.task` modifier, not relying on notification timing. This ensures findings display even if notifications are disabled (AC: 6).

7. **Fire-and-forget error handling:** Pattern analysis errors in PollingEngine are logged but do not affect the polling cycle. Similarly, notification delivery failures are logged but don't crash.

### Project Structure Notes

New files to create:
```
cc-hdrm/Services/PatternNotificationServiceProtocol.swift  # NEW - Protocol with processFindings()
cc-hdrm/Services/PatternNotificationService.swift           # NEW - Implementation with cooldown + notification
cc-hdrm/Views/PatternFindingCard.swift                      # NEW - Compact SwiftUI card component
cc-hdrmTests/Mocks/MockPatternNotificationService.swift     # NEW - Mock for testing
cc-hdrmTests/Services/PatternNotificationServiceTests.swift # NEW - 12 tests covering AC 1-4, 6
```

After adding files, run `xcodegen generate` to regenerate the Xcode project.

### References

- [Source: _bmad-output/planning-artifacts/epics/epic-16-subscription-intelligence-phase-4.md:95-140] - Story 16.2 acceptance criteria
- [Source: _bmad-output/planning-artifacts/architecture.md:967-993] - SubscriptionPatternDetector architecture
- [Source: _bmad-output/implementation-artifacts/16-1-slow-burn-pattern-detection-service.md] - Story 16.1 implementation (predecessor)
- [Source: cc-hdrm/Models/PatternFinding.swift:1-79] - PatternFinding enum with title/summary
- [Source: cc-hdrm/Services/SubscriptionPatternDetectorProtocol.swift] - analyzePatterns() protocol
- [Source: cc-hdrm/Services/PollingEngine.swift:161-193] - persistPoll integration point
- [Source: cc-hdrm/Views/AnalyticsView.swift:92-134] - Value section layout
- [Source: cc-hdrm/Views/AnalyticsWindow.swift] - Panel configuration
- [Source: cc-hdrm/Services/NotificationServiceProtocol.swift] - isAuthorized check
- [Source: cc-hdrm/Services/PreferencesManagerProtocol.swift:14-40] - PreferencesManager protocol
- [Source: cc-hdrmTests/Mocks/SpyNotificationCenter.swift] - Spy for notification verification
- [Source: cc-hdrmTests/Mocks/MockNotificationService.swift] - Mock with isAuthorized flag

## Change Log

- 2026-02-12: Initial implementation by track-a agent. 14 files changed (5 new, 9 modified), 12 new PatternNotificationService tests + 2 cooldownKey tests. All 959 tests pass.
- 2026-02-12: Retroactive story enrichment to BMAD standards -- added Dev Notes (architecture context, integration points, notification architecture, cooldown mechanism, pitfalls, references), expanded Tasks/Subtasks with file paths and granular subtasks, added Change Log.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (claude-opus-4-6)

### Debug Log References

N/A

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
- `cc-hdrm/Services/PatternNotificationServiceProtocol.swift` -- Protocol with `@MainActor processFindings()` method
- `cc-hdrm/Services/PatternNotificationService.swift` -- Notification delivery with 30-day cooldown per finding type
- `cc-hdrm/Views/PatternFindingCard.swift` -- Compact SwiftUI card with title, summary, dismiss button
- `cc-hdrmTests/Mocks/MockPatternNotificationService.swift` -- Mock tracking processedFindings and call count
- `cc-hdrmTests/Services/PatternNotificationServiceTests.swift` -- 12 tests for notification text, cooldown, authorization

Modified files:
- `cc-hdrm/Models/PatternFinding.swift` -- Added cooldownKey computed property (type-based, no associated values)
- `cc-hdrm/Services/PreferencesManagerProtocol.swift` -- Added patternNotificationCooldowns: [String: Date], dismissedPatternFindings: Set<String>
- `cc-hdrm/Services/PreferencesManager.swift` -- Implemented cooldown/dismissal storage with UserDefaults Keys, JSON encoding for cooldowns, string array for dismissals, resetToDefaults cleanup
- `cc-hdrm/Services/PollingEngine.swift` -- Added patternDetector + patternNotificationService optional dependencies, fire-and-forget pattern analysis after persistPoll
- `cc-hdrm/Views/AnalyticsView.swift` -- Added patternDetector/preferencesManager params, @State patternFindings, loadPatternFindings(), dismissFinding(), patternFindingCards ViewBuilder
- `cc-hdrm/Views/AnalyticsWindow.swift` -- Added patternDetector + preferencesManager to configure(), createPanel(), reset()
- `cc-hdrm/App/AppDelegate.swift` -- Wired up SubscriptionPatternDetector + PatternNotificationService instances
- `cc-hdrmTests/Mocks/MockPreferencesManager.swift` -- Added patternNotificationCooldowns, dismissedPatternFindings properties
- `cc-hdrmTests/Models/PatternFindingTests.swift` -- Added 2 cooldownKey tests
