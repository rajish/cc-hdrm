# Story 15.2: Custom Credit Limit Override

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to manually set credit limits for unknown tiers,
so that headroom analysis works even if Anthropic introduces new tiers.

## Acceptance Criteria

1. **Given** the settings view is open
   **When** SettingsView renders
   **Then** an "Advanced" section appears (collapsed by default) with:
   - Custom 5h credit limit: optional number field
   - Custom 7d credit limit: optional number field
   - Hint text: "Override credit limits if your tier isn't recognized"

2. **Given** Alex enters custom credit limits and the tier is NOT recognized
   **When** HeadroomAnalysisService needs limits
   **Then** it uses the custom limits from PreferencesManager as a fallback

3. **Given** custom limits are set AND tier is recognized
   **When** HeadroomAnalysisService needs limits
   **Then** tier lookup values take precedence (custom limits are fallback only for unknown tiers)

4. **Given** invalid values are entered (e.g., negative numbers, zero)
   **When** validation runs
   **Then** the invalid values are rejected with inline error message
   **And** previous valid values are retained

## Tasks / Subtasks

- [x] Task 1: Add "Advanced" disclosure group to SettingsView (AC: 1)
  - [x] 1.1 Add `@State private var showAdvanced = false` for disclosure group expansion state
  - [x] 1.2 Add `@State private var customFiveHourText: String` initialized from `preferencesManager.customFiveHourCredits` (empty string if nil)
  - [x] 1.3 Add `@State private var customSevenDayText: String` initialized from `preferencesManager.customSevenDayCredits` (empty string if nil)
  - [x] 1.4 Add `@State private var fiveHourError: String?` and `@State private var sevenDayError: String?` for inline validation messages
  - [x] 1.5 Add Divider and `DisclosureGroup("Advanced", isExpanded: $showAdvanced)` section between Historical Data section and the Reset to Defaults divider
  - [x] 1.6 Inside disclosure group: add hint text "Override credit limits if your tier isn't recognized" with `.font(.caption)` and `.foregroundStyle(.secondary)`
  - [x] 1.7 Add "5-hour credit limit" labeled TextField with `.textFieldStyle(.roundedBorder)` and number formatting
  - [x] 1.8 Add "7-day credit limit" labeled TextField with `.textFieldStyle(.roundedBorder)` and number formatting
  - [x] 1.9 Add conditional error text below each field: `if let error = fiveHourError { Text(error).font(.caption).foregroundStyle(.red) }`
  - [x] 1.10 Add accessibility labels: "Custom five hour credit limit" and "Custom seven day credit limit"

- [x] Task 2: Wire TextField onChange validation and persistence (AC: 1, 4)
  - [x] 2.1 Add `.onChange(of: customFiveHourText)` handler with isUpdating guard pattern
  - [x] 2.2 Validation logic: if text is empty → set `preferencesManager.customFiveHourCredits = nil` (clears override), clear error
  - [x] 2.3 Validation logic: if text parses to Int and value > 0 → set `preferencesManager.customFiveHourCredits = value`, clear error
  - [x] 2.4 Validation logic: if text fails to parse or value <= 0 → set `fiveHourError = "Must be a positive number"`, do NOT write to PreferencesManager (retain previous valid value)
  - [x] 2.5 Repeat identical pattern for customSevenDayText → customSevenDayCredits → sevenDayError
  - [x] 2.6 Ensure `resetToDefaults()` handler clears both text fields and error states (add to existing reset logic at `cc-hdrm/Views/SettingsView.swift` reset button action)

- [x] Task 3: Write tests for SettingsView Advanced section (AC: 1, 4)
  - [x] 3.1 Test SettingsView renders Advanced disclosure group when SettingsView is created
  - [x] 3.2 Test custom credit fields display existing values from PreferencesManager
  - [x] 3.3 Test empty field clears the preference (sets to nil)
  - [x] 3.4 Test valid positive integer is persisted to PreferencesManager
  - [x] 3.5 Test invalid input (zero, negative, non-numeric) shows inline error and retains previous value
  - [x] 3.6 Test Reset to Defaults clears custom credit fields and error states

- [x] Task 4: Write tests for RateLimitTier.resolve() custom limit fallback (AC: 2, 3)
  - [x] 4.1 Test known tier string returns tier's built-in limits (custom limits ignored)
  - [x] 4.2 Test unknown tier string with both custom limits set returns custom CreditLimits
  - [x] 4.3 Test unknown tier string with only one custom limit set returns nil (both required)
  - [x] 4.4 Test unknown tier string with no custom limits returns nil
  - [x] 4.5 Test nil tier string with custom limits returns custom CreditLimits

## Dev Notes

### Architecture Context

This story is **primarily a UI task**. The entire backend infrastructure for custom credit limits already exists and is fully functional:

- **`PreferencesManagerProtocol`** already declares `customFiveHourCredits: Int?`, `customSevenDayCredits: Int?`, and `customMonthlyPrice: Double?` (`cc-hdrm/Services/PreferencesManagerProtocol.swift:24-29`)
- **`PreferencesManager`** already has UserDefaults keys, getters (return nil if ≤ 0), and setters (store value or remove key if nil) (`cc-hdrm/Services/PreferencesManager.swift:155-195`)
- **`RateLimitTier.resolve(tierString:preferencesManager:)`** already checks custom limits as fallback when tier string doesn't match a known enum case (`cc-hdrm/Models/RateLimitTier.swift:52-73`)
- **`HeadroomAnalysisService`** already receives `PreferencesManagerProtocol` in its constructor and passes it to `RateLimitTier.resolve()` (`cc-hdrm/Services/HeadroomAnalysisService.swift:15-17, 83-89`)
- **`resetToDefaults()`** already clears all three custom properties (`cc-hdrm/Services/PreferencesManager.swift:207-209`)
- **`MockPreferencesManager`** already supports all three custom properties (`cc-hdrmTests/Mocks/MockPreferencesManager.swift:25-27`)

**What needs to be built:** Only the SettingsView UI section to expose these existing properties to the user, plus validation tests.

### Key Integration Points

**SettingsView section placement:**
The "Advanced" section should be added between the "Historical Data" section (line ~202) and the divider before "Reset to Defaults" (line ~204) in `cc-hdrm/Views/SettingsView.swift`. Follow the same Divider + section header pattern used by "Historical Data".

**DisclosureGroup for collapsible section:**
Use SwiftUI `DisclosureGroup` for the collapsed-by-default behavior:
```swift
DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
    // Content here
}
```

**TextField for optional number input:**
Since these are optional Int values, use text-based input with manual parsing rather than a Stepper (which can't represent "unset"):
```swift
HStack {
    Text("5-hour credit limit")
    Spacer()
    TextField("None", text: $customFiveHourText)
        .textFieldStyle(.roundedBorder)
        .frame(width: 100)
        .multilineTextAlignment(.trailing)
}
```

**onChange validation pattern (match existing SettingsView pattern):**
```swift
.onChange(of: customFiveHourText) { _, newValue in
    guard !isUpdating else { return }
    isUpdating = true
    if newValue.isEmpty {
        preferencesManager.customFiveHourCredits = nil
        fiveHourError = nil
    } else if let value = Int(newValue), value > 0 {
        preferencesManager.customFiveHourCredits = value
        fiveHourError = nil
    } else {
        fiveHourError = "Must be a positive number"
        // Do NOT write to PreferencesManager — retain previous valid value
    }
    isUpdating = false
}
```

**Reset to Defaults integration:**
The existing reset button action (around line 210-222) calls `preferencesManager.resetToDefaults()` which already clears custom credits. The SettingsView just needs to also clear the local `@State` text fields and errors:
```swift
// Add after existing reset logic:
customFiveHourText = ""
customSevenDayText = ""
fiveHourError = nil
sevenDayError = nil
showAdvanced = false
```

### Existing RateLimitTier.resolve() Flow

The resolution priority is already correct per AC 2 and 3:
1. **Known tier match** (Pro, Max5x, Max20x) → returns built-in `CreditLimits` (AC 3: tier lookup takes precedence)
2. **Unknown tier + custom limits set** → returns custom `CreditLimits` (AC 2: fallback for unknown tiers)
3. **Unknown tier + no custom limits** → returns nil, event skipped

No changes needed to `RateLimitTier.resolve()` or `HeadroomAnalysisService`.

### Validation Notes

- The PreferencesManager getter already returns nil for values ≤ 0, but the **UI** should provide immediate feedback rather than silently swallowing bad input
- Epic says "previous valid values are retained" on invalid input — this means the `@State` text field can show the invalid text (with error), but PreferencesManager retains the last valid value
- The `customMonthlyPrice` property exists in PreferencesManager but is NOT part of this story's epic spec — do NOT add UI for it

### Potential Pitfalls

1. **DisclosureGroup styling in popover:** macOS SwiftUI `DisclosureGroup` may have different default styling in a popover context vs a standard window. The default chevron disclosure indicator should work, but test that it renders correctly within the 280px-wide settings popover.

2. **TextField width constraint:** The settings popover is 280px wide. TextField needs explicit `.frame(width:)` to prevent layout issues. Use `width: 100` to match the available space after the label.

3. **Number formatting edge cases:** Users might paste text with spaces, commas, or decimal points. `Int(newValue)` handles most cases, but consider trimming whitespace: `Int(newValue.trimmingCharacters(in: .whitespaces))`.

4. **@State initialization from optional:** Initialize text fields in `init()` following the existing pattern at `cc-hdrm/Views/SettingsView.swift:25-29`:
   ```swift
   _customFiveHourText = State(initialValue: preferencesManager.customFiveHourCredits.map(String.init) ?? "")
   _customSevenDayText = State(initialValue: preferencesManager.customSevenDayCredits.map(String.init) ?? "")
   ```

5. **isUpdating shared state:** The existing `isUpdating` flag is shared across all onChange handlers. This is fine because onChange handlers execute synchronously on the main thread, so they can't interleave.

### Previous Story Intelligence (15.1)

Key learnings from Story 15.1 that apply here:
- **View hierarchy threading** is already established — no new parameters need to be threaded through PopoverView → PopoverFooterView → GearMenuView since PreferencesManager (which holds the custom limits) is already passed through
- **`.alert()` in popover** works fine on macOS for confirmation dialogs (successfully used for Clear History)
- **`isUpdating` guard pattern** is critical — all `.onChange` handlers must use it
- **`@State` init from protocol property** must use `_propertyName = State(initialValue:)` in `init()`
- **`ByteCountFormatter`** and similar Foundation formatters work well in this context
- **Accessibility labels** are required on all new controls

### Git Intelligence

Recent commit `c35bce3` (Story 15.1) modified SettingsView extensively — added 122+ lines including the Historical Data section, retention picker, database size display, and Clear History dialog. The new "Advanced" section should be placed after this section.

Files touched by 15.1 that will also be touched by 15.2:
- `cc-hdrm/Views/SettingsView.swift` — add Advanced section
- `cc-hdrmTests/Views/SettingsViewTests.swift` — add tests for Advanced section

No other files need modification since the backend is already complete.

### Project Structure Notes

- **No new files needed.** All changes are within existing files.
- SettingsView remains the ONLY view that exposes preference settings
- PreferencesManager remains the ONLY component that touches UserDefaults
- RateLimitTier.resolve() remains the single resolution point for credit limits
- No changes to view parameter threading (PreferencesManager is already passed through)

### References

- [Source: cc-hdrm/Services/PreferencesManagerProtocol.swift:24-29] - Existing customFiveHourCredits, customSevenDayCredits, customMonthlyPrice protocol properties
- [Source: cc-hdrm/Services/PreferencesManager.swift:14-24] - UserDefaults keys for custom limits
- [Source: cc-hdrm/Services/PreferencesManager.swift:155-195] - Getter/setter implementations (nil if ≤ 0, remove key if nil)
- [Source: cc-hdrm/Services/PreferencesManager.swift:199-210] - resetToDefaults() already clears custom properties
- [Source: cc-hdrm/Models/RateLimitTier.swift:6-9] - Known tier enum cases (pro, max5x, max20x)
- [Source: cc-hdrm/Models/RateLimitTier.swift:12-36] - Hardcoded credit limits per tier
- [Source: cc-hdrm/Models/RateLimitTier.swift:52-73] - resolve() method with custom limit fallback
- [Source: cc-hdrm/Models/RateLimitTier.swift:75-83] - validateCustomLimits normalization factor check
- [Source: cc-hdrm/Models/RateLimitTier.swift:87-106] - CreditLimits struct definition
- [Source: cc-hdrm/Services/HeadroomAnalysisService.swift:15-17] - Constructor accepts PreferencesManagerProtocol
- [Source: cc-hdrm/Services/HeadroomAnalysisService.swift:83-89] - resolve() call in aggregateBreakdown
- [Source: cc-hdrm/Views/SettingsView.swift:25-29] - @State init pattern in init()
- [Source: cc-hdrm/Views/SettingsView.swift:74-83] - isUpdating guard pattern example
- [Source: cc-hdrm/Views/SettingsView.swift:148-202] - Historical Data section (15.1 pattern to follow)
- [Source: cc-hdrm/Views/SettingsView.swift:204-231] - Divider + Reset to Defaults + Done buttons
- [Source: cc-hdrmTests/Mocks/MockPreferencesManager.swift:25-27] - Mock already supports custom credit properties
- [Source: cc-hdrmTests/Views/SettingsViewTests.swift] - Existing SettingsView test patterns
- [Source: _bmad-output/planning-artifacts/epics/epic-15-phase-3-settings-data-retention-phase-3.md] - Epic definition with AC
- [Source: _bmad-output/planning-artifacts/project-context.md] - Tech stack and architectural patterns
- [Source: _bmad-output/implementation-artifacts/15-1-data-retention-configuration.md] - Previous story learnings

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

None — clean implementation, no debugging needed.

### Completion Notes List

- Task 1-2: Added "Advanced" DisclosureGroup section to SettingsView between Historical Data and Reset to Defaults. Includes hint text, two TextFields for custom 5h/7d credit limits with `.roundedBorder` styling and `.frame(width: 100)`, conditional error text, and accessibility labels. `@State` init from optional PreferencesManager properties using `.map(String.init) ?? ""` pattern. `onChange` handlers use existing `isUpdating` guard pattern with whitespace trimming. Reset to Defaults handler clears text fields, errors, and collapses disclosure group.
- Task 3: Added 6 tests in `SettingsViewAdvancedTests` suite covering: render without crash, existing values display, empty field clears preference, valid input persists, invalid input retains previous value (negative/zero/non-numeric), reset clears custom credits.
- Task 4: Added 3 new tests to `RateLimitTierTests`: known tier ignores custom limits (AC 3), unknown tier with only 5h set returns nil, unknown tier with only 7d set returns nil. Existing tests already covered 4.2 (unknown + both custom), 4.4 (unknown + no custom), 4.5 (nil tier + custom).
- No backend changes needed — PreferencesManager, RateLimitTier.resolve(), HeadroomAnalysisService, and MockPreferencesManager already had full support.
- Full regression suite: 976 tests, 0 failures.

### File List

- `cc-hdrm/Views/SettingsView.swift` — Added Advanced section with DisclosureGroup, TextFields, validation, error display, reset handling (modified)
- `cc-hdrmTests/Views/SettingsViewTests.swift` — Added SettingsViewAdvancedTests suite with 6 tests (modified)
- `cc-hdrmTests/Models/RateLimitTierTests.swift` — Added 3 tests for custom limit fallback edge cases (modified)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — Sprint status updated for story 15.2 (modified)
