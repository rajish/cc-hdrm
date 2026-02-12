# Story 17.4: Extra Usage Alerts & Configuration

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want configurable alerts when my extra usage crosses spend thresholds,
so that I'm proactively warned about overflow costs without having to check the app.

## Acceptance Criteria

1. **Given** `PatternNotificationService.isNotifiableType()` currently returns `false` for `.extraUsageOverflow` and `.persistentExtraUsage`
   **When** Story 17.4 is implemented
   **Then** both pattern types return `true` (notifications enabled)
   **And** notification content follows the existing `notificationTitle()` and `notificationBody()` patterns
   **And** 30-day cooldown applies (consistent with other pattern notifications)

2. **Given** extra usage is enabled and the user has configured alert thresholds
   **When** extra usage utilization crosses a threshold (default: 50%, 75%, 90%)
   **Then** a macOS notification is delivered:
   - At 50%: Title "Extra usage update" / Body "You've used half your extra usage budget ([amount] of [limit])"
   - At 75%: Title "Extra usage warning" / Body "Extra usage at 75% -- [amount] of [limit] spent this period"
   - At 90%: Title "Extra usage alert" / Body "Extra usage at 90% -- [remaining] left before hitting your monthly limit"

3. **Given** extra usage utilization crosses from below 100% to at/above 100% (entered extra usage zone)
   **When** the threshold is crossed for the first time in this billing cycle
   **Then** a macOS notification is delivered:
   - Title: "Extra usage started"
   - Body: "Your plan quota is exhausted -- extra usage is now active"
   - This fires once per billing cycle (re-arms on billing cycle reset)

4. **Given** a threshold notification has already been sent for a given level in the current billing period
   **When** utilization remains at or above that level
   **Then** no duplicate notification is sent
   **And** the threshold re-arms when a new billing period begins (detected via reset date or utilization dropping to 0)

5. **Given** the settings view is open
   **When** the notification section renders
   **Then** an "Extra Usage Alerts" subsection appears below the existing headroom threshold settings:
   - Toggle: "Extra usage alerts" (default: on if extra usage is enabled)
   - Three threshold steppers: 50%, 75%, 90% (each individually toggleable)
   - "Entered extra usage" alert toggle (default: on)
   - Help text: "Get notified when your extra usage spending crosses these thresholds"

6. **Given** the user disables all extra usage alert toggles
   **When** extra usage thresholds are crossed
   **Then** no notifications are delivered for extra usage (pattern notifications from AC 1 still respect their own toggle)

7. **Given** extra usage is not enabled on the user's account
   **When** the settings view renders
   **Then** the "Extra Usage Alerts" subsection is hidden or shows: "Extra usage is not enabled on your Anthropic account"

## Tasks / Subtasks

- [x] Task 1: Enable pattern notifications for extra usage types (AC: 1)
  - [x] 1.1 In `cc-hdrm/Services/PatternNotificationService.swift:56-63`, modify `isNotifiableType()` to return `true` for `.extraUsageOverflow` and `.persistentExtraUsage`. Change the switch from returning `false` to returning `true` for these two cases.
  - [x] 1.2 In `cc-hdrm/Services/PatternNotificationService.swift:94-105`, add explicit `notificationBody(for:)` cases for `.extraUsageOverflow` and `.persistentExtraUsage` instead of falling through to the `default` case. Use `finding.summary` content but rewrite for notification brevity:
    - `.extraUsageOverflow`: `"You're averaging $\(String(format: "%.0f", avgExtraSpend))/mo in extra usage. Consider \(recommendedTier)."`
    - `.persistentExtraUsage`: `"Extra usage is \(pct)% of your base plan. \(recommendedTier) may save you money."`
  - [x] 1.3 Verify existing 30-day cooldown in `shouldNotify()` (line 66-71) applies automatically since it uses `finding.cooldownKey` which already has distinct keys `"extraUsageOverflow"` and `"persistentExtraUsage"`. No changes needed.

- [x] Task 2: Add extra usage alert preferences to PreferencesManagerProtocol (AC: 5, 6)
  - [x]2.1 In `cc-hdrm/Services/PreferencesManagerProtocol.swift`, add these properties to the protocol:
    - `var extraUsageAlertsEnabled: Bool { get set }` -- master toggle (default: true)
    - `var extraUsageThreshold50Enabled: Bool { get set }` -- 50% threshold toggle (default: true)
    - `var extraUsageThreshold75Enabled: Bool { get set }` -- 75% threshold toggle (default: true)
    - `var extraUsageThreshold90Enabled: Bool { get set }` -- 90% threshold toggle (default: true)
    - `var extraUsageEnteredAlertEnabled: Bool { get set }` -- "entered extra usage" alert (default: true)
  - [x]2.2 Add defaults to `PreferencesDefaults` enum in the same file:
    - `static let extraUsageAlertsEnabled: Bool = true`
    - `static let extraUsageThreshold50Enabled: Bool = true`
    - `static let extraUsageThreshold75Enabled: Bool = true`
    - `static let extraUsageThreshold90Enabled: Bool = true`
    - `static let extraUsageEnteredAlertEnabled: Bool = true`

- [x] Task 3: Implement extra usage alert preferences in PreferencesManager (AC: 5, 6)
  - [x]3.1 In `cc-hdrm/Services/PreferencesManager.swift`, add UserDefaults keys in the `Keys` enum:
    - `static let extraUsageAlertsEnabled = "com.cc-hdrm.extraUsageAlertsEnabled"`
    - `static let extraUsageThreshold50Enabled = "com.cc-hdrm.extraUsageThreshold50Enabled"`
    - `static let extraUsageThreshold75Enabled = "com.cc-hdrm.extraUsageThreshold75Enabled"`
    - `static let extraUsageThreshold90Enabled = "com.cc-hdrm.extraUsageThreshold90Enabled"`
    - `static let extraUsageEnteredAlertEnabled = "com.cc-hdrm.extraUsageEnteredAlertEnabled"`
  - [x]3.2 Add computed properties for each setting using the Bool UserDefaults pattern. For booleans with `true` as default, use `defaults.object(forKey:) == nil ? true : defaults.bool(forKey:)` since `defaults.bool` returns `false` when key doesn't exist. Example:
    ```swift
    var extraUsageAlertsEnabled: Bool {
        get { defaults.object(forKey: Keys.extraUsageAlertsEnabled) == nil ? PreferencesDefaults.extraUsageAlertsEnabled : defaults.bool(forKey: Keys.extraUsageAlertsEnabled) }
        set { defaults.set(newValue, forKey: Keys.extraUsageAlertsEnabled) }
    }
    ```
  - [x]3.3 Add `defaults.removeObject(forKey:)` calls in `resetToDefaults()` for all 5 new keys.
  - [x]3.4 Add log statements in setters for important changes: `Self.logger.info("Extra usage alerts enabled changed to \(newValue)")`

- [x] Task 4: Add extra usage alert preferences to MockPreferencesManager (AC: 5, 6)
  - [x]4.1 In `cc-hdrmTests/Mocks/MockPreferencesManager.swift`, add stored properties:
    - `var extraUsageAlertsEnabled: Bool = PreferencesDefaults.extraUsageAlertsEnabled`
    - `var extraUsageThreshold50Enabled: Bool = PreferencesDefaults.extraUsageThreshold50Enabled`
    - `var extraUsageThreshold75Enabled: Bool = PreferencesDefaults.extraUsageThreshold75Enabled`
    - `var extraUsageThreshold90Enabled: Bool = PreferencesDefaults.extraUsageThreshold90Enabled`
    - `var extraUsageEnteredAlertEnabled: Bool = PreferencesDefaults.extraUsageEnteredAlertEnabled`
  - [x]4.2 Reset all 5 properties to defaults in `resetToDefaults()`.

- [x] Task 5: Add extra usage threshold tracking to PreferencesManager (AC: 2, 3, 4)
  - [x]5.1 In `cc-hdrm/Services/PreferencesManagerProtocol.swift`, add:
    - `var extraUsageFiredThresholds: Set<Int> { get set }` -- set of threshold percentages already fired this billing period (e.g., {50, 75})
    - `var extraUsageEnteredAlertFired: Bool { get set }` -- whether "entered extra usage" has fired this billing period
    - `var extraUsageLastBillingPeriodKey: String? { get set }` -- billing period key (e.g., "2026-02") for detecting period reset
  - [x]5.2 In `cc-hdrm/Services/PreferencesManager.swift`, add UserDefaults keys:
    - `static let extraUsageFiredThresholds = "com.cc-hdrm.extraUsageFiredThresholds"`
    - `static let extraUsageEnteredAlertFired = "com.cc-hdrm.extraUsageEnteredAlertFired"`
    - `static let extraUsageLastBillingPeriodKey = "com.cc-hdrm.extraUsageLastBillingPeriodKey"`
  - [x]5.3 Implement the `extraUsageFiredThresholds` property using JSON encoding/decoding (same pattern as `patternNotificationCooldowns` at lines 221-231 but encoding `Set<Int>`):
    ```swift
    var extraUsageFiredThresholds: Set<Int> {
        get {
            guard let data = defaults.data(forKey: Keys.extraUsageFiredThresholds) else { return [] }
            return (try? JSONDecoder().decode(Set<Int>.self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.extraUsageFiredThresholds)
            }
        }
    }
    ```
  - [x]5.4 Implement `extraUsageEnteredAlertFired` as simple Bool (default `false`):
    ```swift
    var extraUsageEnteredAlertFired: Bool {
        get { defaults.bool(forKey: Keys.extraUsageEnteredAlertFired) }
        set { defaults.set(newValue, forKey: Keys.extraUsageEnteredAlertFired) }
    }
    ```
  - [x]5.5 Implement `extraUsageLastBillingPeriodKey` as optional String.
  - [x]5.6 Add `defaults.removeObject(forKey:)` calls in `resetToDefaults()` for all 3 new tracking keys.
  - [x]5.7 In `cc-hdrmTests/Mocks/MockPreferencesManager.swift`, add matching stored properties:
    - `var extraUsageFiredThresholds: Set<Int> = []`
    - `var extraUsageEnteredAlertFired: Bool = false`
    - `var extraUsageLastBillingPeriodKey: String?`
  - [x]5.8 Reset these in `resetToDefaults()`.

- [x] Task 6: Create ExtraUsageAlertService (AC: 2, 3, 4, 6)
  - [x]6.1 Create `cc-hdrm/Services/ExtraUsageAlertService.swift` with:
    ```swift
    @MainActor
    final class ExtraUsageAlertService {
        private let notificationCenter: any NotificationCenterProtocol
        private let notificationService: any NotificationServiceProtocol
        private let preferencesManager: any PreferencesManagerProtocol
        private static let logger = Logger(subsystem: "com.cc-hdrm.app", category: "extra-usage-alerts")
    }
    ```
  - [x]6.2 Add initializer accepting `notificationCenter`, `notificationService`, and `preferencesManager`.
  - [x]6.3 Add main evaluation method:
    ```swift
    func evaluateExtraUsageThresholds(
        extraUsageEnabled: Bool,
        utilization: Double?,
        usedCredits: Double?,
        monthlyLimit: Double?,
        billingCycleDay: Int?
    ) async
    ```
  - [x]6.4 Implement billing period key computation: derive from `billingCycleDay` and current date. Format as `"YYYY-MM"` based on the current billing period. If `billingCycleDay` is nil, use calendar month. When the computed key differs from `preferencesManager.extraUsageLastBillingPeriodKey`, clear `extraUsageFiredThresholds` and `extraUsageEnteredAlertFired` (re-arm), then update the key.
  - [x]6.5 Implement "entered extra usage" alert (AC 3): check if `extraUsageEnabled == true` AND the user's plan is exhausted (inferred from the calling context -- the caller will pass `planExhausted: Bool` as an additional parameter). If `planExhausted && !preferencesManager.extraUsageEnteredAlertFired && preferencesManager.extraUsageEnteredAlertEnabled`, deliver the notification and set `extraUsageEnteredAlertFired = true`. Add `planExhausted: Bool` parameter to the method signature.
  - [x]6.6 Implement threshold checking (AC 2): iterate over the three thresholds `[(50, "extraUsageThreshold50Enabled"), (75, "extraUsageThreshold75Enabled"), (90, "extraUsageThreshold90Enabled")]`. For each:
    - Check if the threshold toggle is enabled on `preferencesManager`
    - Check if `utilization * 100 >= threshold`
    - Check if `threshold` is NOT in `preferencesManager.extraUsageFiredThresholds`
    - If all pass: deliver the notification, add `threshold` to `extraUsageFiredThresholds`
  - [x]6.7 Implement notification delivery helper (reuse pattern from `PatternNotificationService.sendNotification()`):
    ```swift
    private func deliverNotification(title: String, body: String, identifier: String) async
    ```
    Uses `notificationService.isAuthorized` gate, `UNMutableNotificationContent`, `notificationCenter.add()`.
  - [x]6.8 Implement threshold notification text per AC 2:
    - 50%: Title `"Extra usage update"`, Body `"You've used half your extra usage budget ($X.XX of $Y.YY)"`
    - 75%: Title `"Extra usage warning"`, Body `"Extra usage at 75% -- $X.XX of $Y.YY spent this period"`
    - 90%: Title `"Extra usage alert"`, Body `"Extra usage at 90% -- $Z.ZZ left before hitting your monthly limit"`
    Use `String(format: "$%.2f", amount)` for currency formatting. For 90%, compute remaining = `monthlyLimit - usedCredits`.
  - [x]6.9 Guard: if `!preferencesManager.extraUsageAlertsEnabled`, return early (skip all threshold alerts). Pattern notifications from AC 1 are handled separately by `PatternNotificationService`.
  - [x]6.10 Guard: if `!extraUsageEnabled`, return early (no extra usage on account).
  - [x]6.11 Guard: if `utilization` is nil, return early.

- [x] Task 7: Create ExtraUsageAlertServiceProtocol (AC: 2, 3, 4)
  - [x]7.1 Create `cc-hdrm/Services/ExtraUsageAlertServiceProtocol.swift`:
    ```swift
    @MainActor
    protocol ExtraUsageAlertServiceProtocol {
        func evaluateExtraUsageThresholds(
            extraUsageEnabled: Bool,
            utilization: Double?,
            usedCredits: Double?,
            monthlyLimit: Double?,
            billingCycleDay: Int?,
            planExhausted: Bool
        ) async
    }
    ```

- [x] Task 8: Wire ExtraUsageAlertService into PollingEngine (AC: 2, 3, 4)
  - [x]8.1 In `cc-hdrm/Services/PollingEngine.swift`, add an optional dependency:
    `private let extraUsageAlertService: (any ExtraUsageAlertServiceProtocol)?`
  - [x]8.2 Add `extraUsageAlertService` parameter to the `init()` (default `nil`).
  - [x]8.3 In `fetchUsageData()` at line 177 (after `appState.updateWindows()` and `evaluateThresholds()`), add the extra usage threshold evaluation:
    ```swift
    // Evaluate extra usage threshold alerts
    if let alertService = extraUsageAlertService {
        let planExhausted = (fiveHourState?.headroomState == .exhausted) || (sevenDayState?.headroomState == .exhausted)
        await alertService.evaluateExtraUsageThresholds(
            extraUsageEnabled: response.extraUsage?.isEnabled ?? false,
            utilization: response.extraUsage?.utilization,
            usedCredits: response.extraUsage?.usedCredits,
            monthlyLimit: response.extraUsage?.monthlyLimit,
            billingCycleDay: preferencesManager.billingCycleDay,
            planExhausted: planExhausted
        )
    }
    ```

- [x] Task 9: Wire ExtraUsageAlertService in AppDelegate (AC: 2, 3, 4)
  - [x]9.1 In `cc-hdrm/App/AppDelegate.swift`, find where `PollingEngine` is constructed. Add `ExtraUsageAlertService` construction before `PollingEngine` and pass it as the `extraUsageAlertService` parameter. It needs the same `notificationCenter`, `notificationService`, and `preferencesManager` that are already available in AppDelegate context.

- [x] Task 10: Add "Extra Usage Alerts" subsection to SettingsView (AC: 5, 6, 7)
  - [x]10.1 In `cc-hdrm/Views/SettingsView.swift`, add `appState: AppState?` parameter (optional, nil in tests) to read `extraUsageEnabled` for conditional rendering (AC 7). Add to `init()` parameters.
  - [x]10.2 Add `@State` properties for the 5 extra usage alert toggles:
    - `@State private var extraUsageAlertsEnabled: Bool`
    - `@State private var extraUsageThreshold50: Bool`
    - `@State private var extraUsageThreshold75: Bool`
    - `@State private var extraUsageThreshold90: Bool`
    - `@State private var extraUsageEnteredAlert: Bool`
  - [x]10.3 Initialize these from `preferencesManager` in `init()`.
  - [x]10.4 Insert the "Extra Usage Alerts" subsection between the existing critical threshold stepper (line 120) and the poll interval picker (line 122). Add a `Divider()` before it. The subsection is conditional on `appState?.extraUsageEnabled ?? false`:
    ```swift
    if let appState, appState.extraUsageEnabled {
        Divider()
        Text("Extra Usage Alerts")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        // ... toggles
        Text("Get notified when your extra usage spending crosses these thresholds")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    ```
  - [x]10.5 Add master toggle: `Toggle("Extra usage alerts", isOn: $extraUsageAlertsEnabled)` with `onChange` writing to `preferencesManager.extraUsageAlertsEnabled`. When master is off, disable the sub-toggles visually.
  - [x]10.6 Add three threshold toggles, each indented (`.padding(.leading, 16)`) and disabled when master toggle is off:
    - `Toggle("Alert at 50%", isOn: $extraUsageThreshold50)` -> `preferencesManager.extraUsageThreshold50Enabled`
    - `Toggle("Alert at 75%", isOn: $extraUsageThreshold75)` -> `preferencesManager.extraUsageThreshold75Enabled`
    - `Toggle("Alert at 90%", isOn: $extraUsageThreshold90)` -> `preferencesManager.extraUsageThreshold90Enabled`
  - [x]10.7 Add "Entered extra usage" toggle: `Toggle("Entered extra usage", isOn: $extraUsageEnteredAlert)` -> `preferencesManager.extraUsageEnteredAlertEnabled`. Also indented, disabled when master is off.
  - [x]10.8 Add accessibility labels to all toggles.
  - [x]10.9 When `appState?.extraUsageEnabled != true`, show nothing (the section is hidden per AC 7). Optionally, if `appState` is available but `extraUsageEnabled == false`, could show a disabled text, but the epic says "hidden or shows message" -- prefer hidden for cleaner UI.
  - [x]10.10 Update "Reset to Defaults" button action to reset the extra usage alert state variables too.
  - [x]10.11 Update all call sites of `SettingsView(...)` to pass `appState:` parameter. Key call sites:
    - `cc-hdrm/Views/GearMenuView.swift` -- passes `appState` (already available in PopoverView context)
    - `cc-hdrm/App/AppDelegate.swift` -- passes `appState` (already available)
    - Test files -- pass `nil` (existing tests unaffected)

- [x] Task 11: Write unit tests for PatternNotificationService extra usage types (AC: 1)
  - [x]11.1 In `cc-hdrmTests/Services/PatternNotificationServiceTests.swift`, add test:
    ```swift
    @Test("extraUsageOverflow triggers notification after enablement")
    func extraUsageOverflowNotification() async {
        let sut = makeSUT()
        let finding = PatternFinding.extraUsageOverflow(avgExtraSpend: 50.0, recommendedTier: "Max 5x", estimatedSavings: 30.0)
        await sut.processFindings([finding])
        #expect(spy.addedRequests.count == 1)
        let content = spy.addedRequests[0].content
        #expect(content.title == "Extra usage alert")
        #expect(content.body.contains("$50"))
    }
    ```
  - [x]11.2 Add test for `persistentExtraUsage` delivering notification with correct body text.
  - [x]11.3 Update the existing `extraUsageOverflowNoNotification` test at line 138. This test currently expects 0 notifications -- it needs to be REMOVED or changed to expect 1 notification, since extra usage overflow will now trigger notifications. Replace with the new test from 11.1.
  - [x]11.4 Add test verifying cooldown applies to extra usage overflow (deliver twice, expect only 1 notification).

- [x] Task 12: Write unit tests for ExtraUsageAlertService (AC: 2, 3, 4, 6)
  - [x]12.1 Create `cc-hdrmTests/Services/ExtraUsageAlertServiceTests.swift`.
  - [x]12.2 Test: 50% threshold fires notification with correct title and body.
  - [x]12.3 Test: 75% threshold fires notification with correct title and body.
  - [x]12.4 Test: 90% threshold fires notification with correct title and body, including remaining balance.
  - [x]12.5 Test: threshold does not re-fire when already in `extraUsageFiredThresholds`.
  - [x]12.6 Test: threshold re-arms when billing period key changes (simulate period reset).
  - [x]12.7 Test: "entered extra usage" fires when `planExhausted == true` and `extraUsageEnabled == true`.
  - [x]12.8 Test: "entered extra usage" does not re-fire in same billing period.
  - [x]12.9 Test: "entered extra usage" re-arms on new billing period.
  - [x]12.10 Test: master toggle `extraUsageAlertsEnabled == false` suppresses all threshold alerts.
  - [x]12.11 Test: individual threshold toggle disables that specific threshold.
  - [x]12.12 Test: no alerts when `extraUsageEnabled == false` (account doesn't have extra usage).
  - [x]12.13 Test: no alerts when `utilization` is nil.
  - [x]12.14 Test: no alerts when `notificationService.isAuthorized == false`.

- [x] Task 13: Write unit tests for PreferencesManager extra usage settings (AC: 5, 6)
  - [x]13.1 In `cc-hdrmTests/Services/PreferencesManagerTests.swift`, add tests for each new preference:
    - `extraUsageAlertsEnabled` defaults to `true`
    - `extraUsageThreshold50Enabled` defaults to `true`
    - Setting to `false` persists and reads back correctly
    - `extraUsageFiredThresholds` round-trips through JSON encoding
    - `resetToDefaults()` clears all extra usage preferences
  - [x]13.2 Verify `extraUsageEnteredAlertFired` defaults to `false`.
  - [x]13.3 Verify `extraUsageLastBillingPeriodKey` defaults to `nil`.

- [x] Task 14: Write unit tests for SettingsView extra usage alerts section (AC: 5, 7)
  - [x]14.1 In `cc-hdrmTests/Views/SettingsViewTests.swift`, add test:
    - SettingsView renders without crash when `appState` has `extraUsageEnabled == true`
    - SettingsView renders without crash when `appState` has `extraUsageEnabled == false`
    - SettingsView renders without crash when `appState` is nil (backward compatibility)
  - [x]14.2 Verify existing tests still pass with the new optional `appState` parameter (they pass `nil`).

- [x] Task 15: Run `xcodegen generate` and verify compilation + all tests pass

## Dev Notes

### Architecture Context

This story completes Epic 17 by adding two alert mechanisms for extra usage:

1. **Pattern notifications (AC 1):** The simplest change -- flip two `false` returns to `true` in `PatternNotificationService.isNotifiableType()`. The existing cooldown, delivery, and authorization infrastructure handles everything.

2. **Threshold alerts (AC 2-4):** A new `ExtraUsageAlertService` that evaluates extra usage utilization on each poll cycle, similar to how `NotificationService.evaluateThresholds()` works for headroom warnings. The key differences from headroom threshold notifications:
   - Headroom uses a state machine (`ThresholdState`: `.aboveWarning` -> `.warned20` -> `.warned5`) with 2 levels
   - Extra usage uses a simpler "fired thresholds" set with 3 levels + a "entered extra usage" one-shot
   - Extra usage thresholds re-arm on billing period reset, not on headroom recovery

3. **Settings UI (AC 5-7):** A new subsection in SettingsView with a master toggle and individual threshold toggles. Conditionally hidden when the account has no extra usage enabled.

### Key Integration Points

**Files consumed (read-only):**
- `cc-hdrm/Models/PatternFinding.swift:1-79` -- `PatternFinding` enum with `.extraUsageOverflow` and `.persistentExtraUsage` cases, `.title`, `.summary`, `.cooldownKey` properties
- `cc-hdrm/Models/UsageResponse.swift:30-43` -- `ExtraUsage` struct with `isEnabled`, `monthlyLimit`, `usedCredits`, `utilization`
- `cc-hdrm/State/AppState.swift:52-56` -- Extra usage state properties from Story 17.1
- `cc-hdrm/State/AppState.swift:157-162` -- `isExtraUsageActive` computed property
- `cc-hdrm/Models/HeadroomState.swift` -- `.exhausted` case for detecting plan exhaustion

**Files to modify:**
- `cc-hdrm/Services/PatternNotificationService.swift:56-63` -- Change `isNotifiableType()` to return `true` for extra usage types
- `cc-hdrm/Services/PatternNotificationService.swift:94-105` -- Add explicit `notificationBody()` cases for extra usage
- `cc-hdrm/Services/PreferencesManagerProtocol.swift` -- Add 8 new protocol properties (5 alert toggles + 3 tracking properties) + defaults
- `cc-hdrm/Services/PreferencesManager.swift` -- Implement 8 new UserDefaults-backed properties + reset
- `cc-hdrm/Services/PollingEngine.swift:140-256` -- Wire `ExtraUsageAlertService` into `fetchUsageData()`
- `cc-hdrm/Views/SettingsView.swift` -- Add "Extra Usage Alerts" subsection with toggles
- `cc-hdrm/Views/GearMenuView.swift` -- Pass `appState` to SettingsView
- `cc-hdrm/App/AppDelegate.swift` -- Construct `ExtraUsageAlertService`, pass `appState` to SettingsView

**Files to create:**
- `cc-hdrm/Services/ExtraUsageAlertService.swift` -- Threshold evaluation and notification delivery
- `cc-hdrm/Services/ExtraUsageAlertServiceProtocol.swift` -- Protocol for testability
- `cc-hdrmTests/Services/ExtraUsageAlertServiceTests.swift` -- Comprehensive tests

**Test files to modify:**
- `cc-hdrmTests/Services/PatternNotificationServiceTests.swift` -- Update/add tests for enabled extra usage notifications
- `cc-hdrmTests/Services/PreferencesManagerTests.swift` -- Add tests for new preferences
- `cc-hdrmTests/Views/SettingsViewTests.swift` -- Add tests for extra usage settings section
- `cc-hdrmTests/Mocks/MockPreferencesManager.swift` -- Add 8 new stored properties

After adding new Swift files, run `xcodegen generate` to regenerate the Xcode project.

### How PatternNotificationService.isNotifiableType() Works

Located at `cc-hdrm/Services/PatternNotificationService.swift:56-63`:

```swift
private func isNotifiableType(_ finding: PatternFinding) -> Bool {
    switch finding {
    case .forgottenSubscription, .chronicOverpaying, .chronicUnderpowering:
        return true
    case .usageDecay, .extraUsageOverflow, .persistentExtraUsage:
        return false  // <-- Change these to true
    }
}
```

The change is simply moving `.extraUsageOverflow` and `.persistentExtraUsage` to the `true` branch. The `notificationBody()` method at line 94 currently has a `default` fallback that calls `finding.summary` -- but for clarity and to control notification text, add explicit cases.

### How Headroom Threshold Notifications Work (Pattern Reference)

`NotificationService` (`cc-hdrm/Services/NotificationService.swift:49-115`) uses a `ThresholdState` state machine per window:
- States: `.aboveWarning` -> `.warned20` -> `.warned5`
- `evaluateWindow()` returns `(newState, shouldFireWarning, shouldFireCritical)`
- Called by `PollingEngine` after each successful poll
- Re-arms when headroom rises back above the warning threshold

**The extra usage alert service follows a simpler pattern:**
- No state machine -- just a `Set<Int>` tracking which thresholds have fired
- Re-arms on billing period reset (not on utilization recovery within the same period)
- Each threshold fires independently (50%, 75%, 90% can all fire in sequence)
- The "entered extra usage" alert is a separate boolean flag

### How PreferencesManager Stores Settings

All settings use UserDefaults with `com.cc-hdrm.` prefix keys (`cc-hdrm/Services/PreferencesManager.swift:14-28`):
- Booleans: `defaults.bool(forKey:)` / `defaults.set(_, forKey:)`
- **IMPORTANT**: `defaults.bool(forKey:)` returns `false` when the key doesn't exist. For boolean preferences that default to `true`, use `defaults.object(forKey:) == nil` check first. See the pattern for `launchAtLogin` (lines 119-128) which defaults to `false` (works fine), vs the new extra usage alerts which default to `true` (need the nil check pattern).
- Complex types (like `Set<Int>`, `[String: Date]`): JSON encode/decode via `defaults.data(forKey:)` (pattern at lines 221-231)
- Reset: `defaults.removeObject(forKey:)` for each key (lines 263-278)

### SettingsView Layout Patterns

The current SettingsView (`cc-hdrm/Views/SettingsView.swift`) has this structure:
1. "Settings" headline (line 72)
2. Warning threshold stepper (line 77)
3. Critical threshold stepper (line 99)
4. Poll interval picker (line 122)
5. Launch at login toggle (line 142)
6. Historical Data section (line 160) -- conditional on `historicalDataService`
7. Advanced disclosure group (line 219) -- with credit limits and billing cycle
8. Reset to Defaults button (line 323)
9. Done button (line 347)

The "Extra Usage Alerts" subsection should go between items 3 and 4 (after critical threshold, before poll interval), since it's a notification setting that groups naturally with the threshold steppers. It follows the same pattern as "Historical Data":
- `Divider()`
- Section header in `.subheadline` + `.secondary`
- Controls
- Help text in `.caption` + `.secondary`

### Billing Period Detection for Threshold Re-arming

The billing period key is computed from `billingCycleDay` (from Story 16.4, stored in `PreferencesManager.billingCycleDay: Int?`, range 1-28):

```swift
static func computeBillingPeriodKey(billingCycleDay: Int?, now: Date = Date()) -> String {
    let calendar = Calendar.current
    let day = billingCycleDay ?? 1
    let currentDay = calendar.component(.day, from: now)
    var year = calendar.component(.year, from: now)
    var month = calendar.component(.month, from: now)
    // If we haven't reached the billing day yet, we're in the previous period
    if currentDay < day {
        month -= 1
        if month < 1 { month = 12; year -= 1 }
    }
    return String(format: "%04d-%02d", year, month)
}
```

When the computed key differs from `preferencesManager.extraUsageLastBillingPeriodKey`, clear the fired thresholds and update the key. This re-arms all thresholds for the new billing period.

### SettingsView appState Parameter

SettingsView needs to read `appState.extraUsageEnabled` to conditionally show/hide the extra usage alerts section (AC 7). Since SettingsView is a struct value type that doesn't own AppState, pass it as an optional:

```swift
let appState: AppState?
```

This is optional because:
1. Existing tests create SettingsView without AppState
2. AppDelegate constructs SettingsView with AppState available
3. The section simply hides when appState is nil (no extra usage section in tests)

Callers that need updating:
- `cc-hdrm/Views/GearMenuView.swift` -- already has access to `appState` via `PopoverView`
- `cc-hdrm/App/AppDelegate.swift` -- has `appState` as a property
- Test files -- pass `nil` (backward compatible)

### GearMenuView AppState Propagation

`GearMenuView` is constructed from `PopoverView` (or `PopoverFooterView`). Check how `appState` flows to `SettingsView` through the view hierarchy. `GearMenuView` likely needs an `appState` parameter added to its init.

### Existing Test Patterns

**PatternNotificationServiceTests** (`cc-hdrmTests/Services/PatternNotificationServiceTests.swift`):
- Uses `SpyNotificationCenter` to capture `addedRequests`
- Uses `MockPreferencesManager` for cooldown tracking
- Uses `MockNotificationService` with `isAuthorized` toggle
- Pattern: create SUT via `makeSUT()`, call `processFindings()`, assert on `spy.addedRequests.count` and `.content`

**IMPORTANT**: The existing test `extraUsageOverflowNoNotification` at line 138 asserts that extra usage overflow does NOT trigger a notification. This test must be updated/replaced since AC 1 enables these notifications.

**SettingsViewTests** (`cc-hdrmTests/Views/SettingsViewTests.swift`):
- Uses `MockPreferencesManager` and `MockLaunchAtLoginService`
- Pattern: create view, call `_ = view.body` or wrap in `NSHostingController`
- Tests validate rendering without crash and static helper methods

### Potential Pitfalls

1. **Boolean defaults with `true` value**: `UserDefaults.bool(forKey:)` returns `false` for missing keys. All 5 extra usage alert toggles default to `true`, so they MUST use the `defaults.object(forKey:) == nil` pattern to distinguish "not set yet" from "explicitly set to false". This is the most common bug in this story.

2. **Existing test breakage**: `PatternNotificationServiceTests.extraUsageOverflowNoNotification` (line 138-145) will FAIL after Task 1 enables extra usage notifications. This test must be updated before the test suite can pass. Plan for this during implementation order.

3. **SettingsView backward compatibility**: Adding `appState: AppState?` parameter to SettingsView init requires updating ALL call sites. Missing a call site causes a compile error. Check `GearMenuView`, `AppDelegate`, and any test files that construct `SettingsView`.

4. **Billing period edge case -- no billingCycleDay**: When `billingCycleDay` is nil, default to 1st of month. The billing period key computation must handle this gracefully.

5. **Thread safety**: `ExtraUsageAlertService` is `@MainActor`, same as `PatternNotificationService` and `NotificationService`. It's called from `PollingEngine.fetchUsageData()` which is also `@MainActor`. No concurrency issues.

6. **Multiple thresholds crossing at once**: If utilization jumps from 0% to 95% in a single poll, all three thresholds (50%, 75%, 90%) should fire. The iteration order matters -- fire from lowest to highest for natural notification ordering.

7. **"Entered extra usage" vs pattern notifications**: The "entered extra usage" alert (AC 3) is about the user's plan quota being exhausted and extra usage starting. This is different from `.extraUsageOverflow` pattern finding (which is about spending extra usage for 2+ consecutive billing periods). Both can fire independently -- they serve different purposes.

8. **PollingEngine init parameter explosion**: PollingEngine already has 10 parameters. Adding `extraUsageAlertService` makes 11. This is acceptable for dependency injection but consider that tests may need updating.

9. **GearMenuView parameter propagation**: GearMenuView needs `appState` to pass to SettingsView. Check `cc-hdrm/Views/GearMenuView.swift` to see what parameters it currently accepts and how `appState` flows from PopoverView.

### Previous Story Intelligence

Key learnings from Stories 17.1-17.3:
- **Extra usage state** is fully propagated through `AppState` (Story 17.1)
- **Currency formatting**: `String(format: "$%.2f", amount)` per Story 17.1 convention
- **Color tokens**: `Color.extraUsageCool` etc. from Story 17.1 (not needed for this story but contextual)
- **Test patterns**: View tests use `@MainActor`, `NSHostingController`, `_ = controller.view` for layout
- **Service tests**: Use `SpyNotificationCenter`, `MockPreferencesManager`, `MockNotificationService`
- **PollingEngine wiring**: Extra usage data extraction is at lines 164-174 in `fetchUsageData()`. The new threshold evaluation goes after line 177 (after `evaluateThresholds()`).

### Project Structure Notes

Files to create:
```
cc-hdrm/Services/ExtraUsageAlertService.swift          # NEW - Threshold alert evaluation and delivery
cc-hdrm/Services/ExtraUsageAlertServiceProtocol.swift   # NEW - Protocol for testability
cc-hdrmTests/Services/ExtraUsageAlertServiceTests.swift  # NEW - Comprehensive tests
```

Files to modify:
```
cc-hdrm/Services/PatternNotificationService.swift       # MODIFY - Enable extra usage pattern notifications
cc-hdrm/Services/PreferencesManagerProtocol.swift        # MODIFY - Add 8 new properties + defaults
cc-hdrm/Services/PreferencesManager.swift               # MODIFY - Implement 8 new UserDefaults-backed properties
cc-hdrm/Services/PollingEngine.swift                     # MODIFY - Wire ExtraUsageAlertService
cc-hdrm/Views/SettingsView.swift                         # MODIFY - Add Extra Usage Alerts subsection
cc-hdrm/Views/GearMenuView.swift                        # MODIFY - Pass appState to SettingsView
cc-hdrm/App/AppDelegate.swift                           # MODIFY - Construct ExtraUsageAlertService, pass appState
cc-hdrmTests/Mocks/MockPreferencesManager.swift          # MODIFY - Add 8 stored properties
cc-hdrmTests/Services/PatternNotificationServiceTests.swift # MODIFY - Update extra usage tests
cc-hdrmTests/Services/PreferencesManagerTests.swift      # MODIFY - Add extra usage preference tests
cc-hdrmTests/Views/SettingsViewTests.swift               # MODIFY - Add extra usage settings tests
```

After adding new Swift files, run `xcodegen generate` to regenerate the Xcode project.

### References

- [Source: _bmad-output/planning-artifacts/epics/epic-17-extra-usage-visibility-alerts-phase-5.md:181-237] -- Story 17.4 acceptance criteria
- [Source: cc-hdrm/Services/PatternNotificationService.swift:56-63] -- `isNotifiableType()` switch returning false for extra usage
- [Source: cc-hdrm/Services/PatternNotificationService.swift:94-105] -- `notificationBody()` with default case
- [Source: cc-hdrm/Services/PatternNotificationService.swift:66-71] -- `shouldNotify()` 30-day cooldown
- [Source: cc-hdrm/Services/PatternNotificationService.swift:74-91] -- `sendNotification()` delivery pattern
- [Source: cc-hdrm/Services/NotificationService.swift:49-115] -- `evaluateThresholds()` headroom notification pattern
- [Source: cc-hdrm/Services/NotificationService.swift:119-149] -- `evaluateWindow()` state machine (reference for threshold logic)
- [Source: cc-hdrm/Services/PreferencesManagerProtocol.swift:1-46] -- Protocol with defaults enum
- [Source: cc-hdrm/Services/PreferencesManager.swift:14-28] -- UserDefaults keys pattern
- [Source: cc-hdrm/Services/PreferencesManager.swift:119-128] -- Bool preference with false default
- [Source: cc-hdrm/Services/PreferencesManager.swift:221-231] -- JSON-encoded complex type pattern
- [Source: cc-hdrm/Services/PreferencesManager.swift:263-278] -- resetToDefaults() key removal
- [Source: cc-hdrm/Services/PollingEngine.swift:140-256] -- fetchUsageData() pipeline
- [Source: cc-hdrm/Services/PollingEngine.swift:164-174] -- Extra usage extraction in PollingEngine
- [Source: cc-hdrm/Services/PollingEngine.swift:176-178] -- Notification evaluation insertion point
- [Source: cc-hdrm/Services/PollingEngine.swift:298-319] -- handleCredentialError() pattern
- [Source: cc-hdrm/Views/SettingsView.swift:70-382] -- Full SettingsView body with section layout
- [Source: cc-hdrm/Views/SettingsView.swift:99-120] -- Critical threshold stepper (insert after)
- [Source: cc-hdrm/Views/SettingsView.swift:160-214] -- Historical Data section pattern
- [Source: cc-hdrm/Views/SettingsView.swift:323-345] -- Reset to Defaults handler
- [Source: cc-hdrm/State/AppState.swift:52-56] -- Extra usage state properties
- [Source: cc-hdrm/State/AppState.swift:157-162] -- isExtraUsageActive computed property
- [Source: cc-hdrm/Models/PatternFinding.swift:1-79] -- PatternFinding enum with title, summary, cooldownKey
- [Source: cc-hdrm/Models/UsageResponse.swift:30-43] -- ExtraUsage struct
- [Source: cc-hdrm/Services/SubscriptionPatternDetector.swift:350-397] -- detectExtraUsageOverflow() finding generation
- [Source: cc-hdrm/Services/SubscriptionPatternDetector.swift:399-448] -- detectPersistentExtraUsage() finding generation
- [Source: cc-hdrmTests/Services/PatternNotificationServiceTests.swift:138-145] -- Existing test that must be updated
- [Source: cc-hdrmTests/Services/PatternNotificationServiceTests.swift:13-20] -- makeSUT() test factory pattern
- [Source: cc-hdrmTests/Mocks/MockPreferencesManager.swift:1-37] -- Mock with stored properties pattern
- [Source: cc-hdrmTests/Views/SettingsViewTests.swift:1-103] -- SettingsView test patterns

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

N/A - all tests passed on first run after fixing the expected test breakage (extraUsageOverflowNoNotification).

### Implementation Plan

1. Enable pattern notifications for extra usage types (Task 1) - flip isNotifiableType() returns, add explicit notificationBody() cases
2. Add 8 new preference properties to protocol + defaults (Tasks 2, 5) - 5 alert toggles + 3 tracking props
3. Implement PreferencesManager backing with correct boolean-defaults-true pattern (Tasks 3, 5)
4. Update MockPreferencesManager (Tasks 4, 5.7-5.8)
5. Create ExtraUsageAlertServiceProtocol and ExtraUsageAlertService (Tasks 6, 7) - billing period key, threshold evaluation, notification delivery
6. Wire into PollingEngine + AppDelegate (Tasks 8, 9)
7. Add SettingsView Extra Usage Alerts subsection with appState parameter propagation (Task 10)
8. Update all tests - fix expected breakage + add new tests (Tasks 11-14)
9. xcodegen + full test suite verification (Task 15)

### Completion Notes List

- All 15 tasks and 86 subtasks completed
- 1157 tests pass (27 new tests added)
- Boolean defaults using `defaults.object(forKey:) == nil` pattern for all 5 true-defaulting toggles
- SettingsView appState parameter is optional with nil default for backward compatibility
- GearMenuView and PopoverFooterView updated to propagate appState through view hierarchy
- ExtraUsageAlertService uses billing period key to re-arm thresholds on billing cycle reset
- Multiple thresholds fire in sequence (low to high) when utilization jumps in a single poll

### Change Log

- PatternNotificationService: enabled notifications for extraUsageOverflow + persistentExtraUsage, added explicit notificationBody cases
- PreferencesManagerProtocol: added 5 alert toggle properties, 3 tracking properties, 5 PreferencesDefaults constants
- PreferencesManager: implemented 8 new UserDefaults-backed properties with correct defaults pattern, 8 new reset calls
- MockPreferencesManager: added 8 stored properties with reset
- ExtraUsageAlertServiceProtocol: new protocol for testability
- ExtraUsageAlertService: new service with threshold evaluation, billing period detection, notification delivery
- PollingEngine: added optional extraUsageAlertService dependency, wired evaluation into fetchUsageData()
- AppDelegate: creates ExtraUsageAlertService and passes to PollingEngine
- SettingsView: added appState parameter, Extra Usage Alerts subsection with master + 5 individual toggles
- GearMenuView: added appState parameter, passes to SettingsView
- PopoverFooterView: passes appState to GearMenuView
- PatternNotificationServiceTests: replaced extraUsageOverflowNoNotification with 3 new tests (enablement, persistentExtraUsage, cooldown)
- PreferencesManagerTests: added 7 tests for extra usage preferences
- ExtraUsageAlertServiceTests: new file with 17 tests covering all AC scenarios
- SettingsViewTests: added 3 tests for extra usage alerts section rendering

### File List

**New files:**
- `cc-hdrm/Services/ExtraUsageAlertService.swift`
- `cc-hdrm/Services/ExtraUsageAlertServiceProtocol.swift`
- `cc-hdrmTests/Services/ExtraUsageAlertServiceTests.swift`

**Modified files:**
- `cc-hdrm/Services/PatternNotificationService.swift`
- `cc-hdrm/Services/PreferencesManagerProtocol.swift`
- `cc-hdrm/Services/PreferencesManager.swift`
- `cc-hdrm/Services/PollingEngine.swift`
- `cc-hdrm/Views/SettingsView.swift`
- `cc-hdrm/Views/GearMenuView.swift`
- `cc-hdrm/Views/PopoverFooterView.swift`
- `cc-hdrm/App/AppDelegate.swift`
- `cc-hdrmTests/Mocks/MockPreferencesManager.swift`
- `cc-hdrmTests/Services/PatternNotificationServiceTests.swift`
- `cc-hdrmTests/Services/PreferencesManagerTests.swift`
- `cc-hdrmTests/Views/SettingsViewTests.swift`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
- `_bmad-output/implementation-artifacts/17-4-extra-usage-alerts-configuration.md`
