# Story 3.3: Refined 7d Promotion Rule, Credit-Math Slope Normalization & Popover Quotas Display

Status: done

<!-- Course correction story. Replaces Story 3.2 promotion logic, enhances slope calculation from Epic 11, and pulls forward RateLimitTier credit limits from Epic 14 (Story 14.1). -->

## Story

As a developer using Claude Code,
I want the 7d headroom to promote to the menu bar only when the remaining 7d budget can't sustain one more full 5h cycle, a colored dot on the gauge icon when 7d is in caution or worse, the slope calculation normalized to credit terms so 7d slope is meaningful, and a "quotas remaining" display in the popover 7d section,
So that I always see 5h limit and slope (my primary working context), get ambient 7d awareness without losing 5h info, and can see at a glance how many 5h cycles I have left in my weekly budget.

## Background & Rationale

The original Story 3.2 promotion rule (`7d headroom < 5h headroom AND 7d in warning/critical`) fires too aggressively in practice, hiding the 5h limit and slope indicator. The user finds themselves repeatedly clicking the menu bar number to reveal the hidden 5h data. This course correction:

1. **Replaces the promotion rule** with credit-math logic: promote 7d only when `remaining_7d_credits / 5h_credit_limit < 1` (can't fit one more full 5h cycle).
2. **Adds a 7d state dot** on the gauge icon corner for ambient 7d awareness without hiding 5h info.
3. **Adds a "7d" label** on the gauge icon when 7d is promoted, making the mode switch unambiguous.
4. **Normalizes slope calculation** to credit terms so 7d slope uses the same thresholds as 5h and produces meaningful readings.
5. **Adds "X full 5h quotas left"** to the popover 7d section so the promotion logic is transparent.

## Prerequisites

This story absorbs Story 14.1 (RateLimitTier credit limit enum) from Epic 14 as an internal implementation detail. The enum will be available for Epic 14 stories (14.2-14.5) when they are built later.

## Acceptance Criteria

### AC-1: RateLimitTier Credit Limit Enum

**Given** the RateLimitTier enum is defined
**When** referenced across the codebase
**Then** it includes cases: `.pro`, `.max5x`, `.max20x`
**And** each case provides `fiveHourCredits` and `sevenDayCredits` properties:
- Pro: 550,000 / 5,000,000
- Max 5x: 3,300,000 / 41,666,700
- Max 20x: 11,000,000 / 83,333,300

**Given** `rateLimitTier` is read from KeychainCredentials
**When** the tier string matches a known case (e.g., `"default_claude_max_5x"`)
**Then** it maps to the corresponding RateLimitTier enum case

**Given** `rateLimitTier` doesn't match any known tier
**When** credit limits are needed
**Then** it checks PreferencesManager for user-configured custom credit limits
**And** if custom limits exist, uses those
**And** if no custom limits, returns nil (features degrade to percentage-only behavior)
**And** a warning is logged: "Unknown rate limit tier: [tier]"

### AC-2: Credit-Math Promotion Rule

**Given** valid credit limits are available (known tier or user override)
**And** both 5h and 7d usage data are present
**When** `AppState.displayedWindow` is evaluated
**Then** it calculates:
```
remaining_7d_credits = (100% - 7d_utilization%) x 7d_credit_limit
quotas_remaining = remaining_7d_credits / 5h_credit_limit
```
**And** if `quotas_remaining < 1.0`, the 7d window is promoted (displayed in menu bar)
**And** if `quotas_remaining >= 1.0`, the 5h window is displayed (regardless of 7d headroom state)

**Given** credit limits are NOT available (unknown tier, no override)
**When** `AppState.displayedWindow` is evaluated
**Then** it falls back to the original percentage-comparison rule from Story 3.2 (7d headroom < 5h headroom AND 7d in warning/critical)

**Given** 7d is promoted AND 5h headroom reaches 0% (exhausted)
**When** the menu bar renders
**Then** the exhausted countdown takes precedence (same as current behavior)

### AC-3: GaugeIcon 7d Colored Dot

**Given** the 7d window is NOT promoted to the menu bar
**And** the 7d headroom state is `.caution`, `.warning`, or `.critical`
**When** the GaugeIcon renders
**Then** a small colored dot appears in a corner of the gauge icon
**And** the dot color matches the 7d HeadroomState color token (yellow for caution, orange for warning, red for critical)

**Given** the 7d window is NOT promoted
**And** the 7d headroom state is `.normal` (>40% headroom)
**When** the GaugeIcon renders
**Then** no dot is displayed (quiet when 7d is healthy)

**Given** the connection status is `.disconnected` or 7d data is unavailable
**When** the GaugeIcon renders
**Then** no dot is displayed

### AC-4: GaugeIcon "7d" Label When Promoted

**Given** the 7d window IS promoted to the menu bar (quotas_remaining < 1)
**When** the GaugeIcon renders
**Then** a small "7d" text label appears in the same corner position where the dot would be
**And** the label makes it unambiguous that the displayed number represents the 7d window, not 5h

**Given** the 7d window was promoted and then recovers (quotas_remaining >= 1 on next poll)
**When** the GaugeIcon renders
**Then** the "7d" label is removed
**And** the display reverts to showing 5h headroom (with or without dot depending on 7d state)

### AC-5: 5h Limit and Slope Always Visible When Not Promoted

**Given** the 5h window is displayed in the menu bar (7d not promoted)
**When** the menu bar renders
**Then** the 5h headroom percentage, color, weight, and slope arrow (when actionable) are all visible
**And** this behavior is identical to the current implementation -- no 5h information is ever hidden by 7d state

_(This AC confirms the existing behavior is preserved. The change is that the promotion fires far less often, so 5h data stays visible in practice.)_

### AC-6: Credit-Normalized Slope Calculation

**Given** valid credit limits are available (known tier or user override)
**When** `SlopeCalculationService.calculateSlope(for: .sevenDay)` is called
**Then** it computes the rate of change using credit normalization:
```
normalized_rate = raw_7d_rate_percent_per_min x (7d_credit_limit / 5h_credit_limit)
```
**And** maps the normalized rate to SlopeLevel using the existing thresholds:
- < 0.3 normalized %/min -> .flat
- 0.3 to 1.5 -> .rising
- > 1.5 -> .steep

**Given** valid credit limits are available
**When** `SlopeCalculationService.calculateSlope(for: .fiveHour)` is called
**Then** the calculation is unchanged (5h is already the reference scale)

**Given** credit limits are NOT available (unknown tier, no override)
**When** `SlopeCalculationService.calculateSlope(for: .sevenDay)` is called
**Then** it falls back to the raw percentage-based calculation (current behavior)

### AC-7: Popover "Quotas Remaining" Display

**Given** valid credit limits are available
**And** the popover is open with valid 7d usage data
**When** the SevenDayGaugeSection renders
**Then** it displays below the countdown/absolute time:
```
X full 5h quotas left
```
**Where** X is calculated as `floor(remaining_7d_credits / 5h_credit_limit)` for the integer part and the display shows the decimal (e.g., "6 full 5h quotas left" or "0 full 5h quotas left")

**Given** quotas_remaining is fractional (e.g., 2.7)
**When** the popover renders
**Then** it displays the floored integer: "2 full 5h quotas left"

**Given** quotas_remaining is 0 (7d can't sustain even one more 5h cycle)
**When** the popover renders
**Then** it displays "0 full 5h quotas left" in the 7d headroom color (warning/critical)

**Given** credit limits are NOT available
**When** the popover renders
**Then** the "quotas remaining" line is hidden (not shown at all)

**Given** a VoiceOver user focuses the 7d gauge section
**When** VoiceOver reads the element
**Then** it announces the quotas remaining as part of the gauge reading: "7-day headroom: [X] percent, [slope], resets in [time], [N] full 5-hour quotas left"

### AC-8: Test Coverage

**Given** the existing promotion tests in AppStateTests.swift
**When** the test suite runs
**Then** the old percentage-comparison promotion tests are replaced with credit-math promotion tests
**And** tests cover: promotion fires at quotas < 1, does not fire at quotas >= 1, fallback to percentage rule on unknown tier, exhausted countdown precedence

**Given** the slope calculation tests
**When** the test suite runs
**Then** tests verify credit-normalized 7d slope produces meaningful levels (e.g., 0.08%/min raw 7d rate maps to "rising" after normalization for Max 5x tier)
**And** tests verify 5h slope calculation is unchanged
**And** tests verify fallback to raw percentage on unknown tier

**Given** GaugeIcon tests
**When** the test suite runs
**Then** tests verify: dot appears only at caution/warning/critical, dot uses correct 7d color, "7d" label appears when promoted, no dot/label when 7d is normal or disconnected

**Given** popover tests
**When** the test suite runs
**Then** tests verify: quotas display shows correct integer, hidden when credit limits unavailable, "0 full 5h quotas left" colored appropriately

## Tasks / Subtasks

- [x] Task 1: Create `RateLimitTier` enum and `CreditLimits` struct (AC: 1)
  - [x] 1.1 Create NEW file `cc-hdrm/Models/RateLimitTier.swift`
  - [x] 1.2 Define `enum RateLimitTier: String, CaseIterable, Sendable` with raw values matching Keychain strings exactly:
    - `.pro = "default_claude_pro"`
    - `.max5x = "default_claude_max_5x"`
    - `.max20x = "default_claude_max_20x"`
  - [x] 1.3 Add computed properties `fiveHourCredits: Int` and `sevenDayCredits: Int` with values:
    - Pro: 550,000 / 5,000,000
    - Max 5x: 3,300,000 / 41,666,700
    - Max 20x: 11,000,000 / 83,333,300
  - [x] 1.4 Define `struct CreditLimits: Sendable, Equatable` in the same file with:
    ```swift
    struct CreditLimits: Sendable, Equatable {
        let fiveHourCredits: Int
        let sevenDayCredits: Int
        /// 7d_limit / 5h_limit — used for slope normalization.
        /// ~9.09 for Pro, ~12.63 for Max 5x, ~7.58 for Max 20x.
        var normalizationFactor: Double {
            Double(sevenDayCredits) / Double(fiveHourCredits)
        }
    }
    ```
    This struct is the common currency for credit limits. It supports both known tiers AND custom user-configured limits without a "synthetic enum case" (which is impossible with String raw-value enums).
  - [x] 1.5 Add `var creditLimits: CreditLimits` computed property to `RateLimitTier`:
    ```swift
    var creditLimits: CreditLimits {
        CreditLimits(fiveHourCredits: fiveHourCredits, sevenDayCredits: sevenDayCredits)
    }
    ```
  - [x] 1.6 Add `static func resolve(tierString: String?, preferencesManager: PreferencesManagerProtocol?) -> CreditLimits?`:
    - First try `RateLimitTier(rawValue: tierString ?? "")` for known tiers — if match, return `tier.creditLimits`
    - If no match, check `preferencesManager` for user-configured custom credit limits (see Task 1.7)
    - If both custom limits are non-nil, return `CreditLimits(fiveHourCredits:, sevenDayCredits:)`
    - If nothing matches, log warning "Unknown rate limit tier: [tier]" via `os.Logger` category `"tier"` and return nil
  - [x] 1.7 Add `customFiveHourCredits: Int?` and `customSevenDayCredits: Int?` to `PreferencesManagerProtocol` and `PreferencesManager` (new UserDefaults keys `com.cc-hdrm.customFiveHourCredits`, `com.cc-hdrm.customSevenDayCredits`). Getter returns nil if 0 or unset. These enable power users to configure limits for unknown tiers. NOT exposed in SettingsView yet (Epic 14 scope).
  - [x] 1.8 Run `xcodegen generate` after creating the new file

- [x] Task 2: Revise `displayedWindow` to credit-math promotion rule (AC: 2)
  - [x] 2.1 Add `private(set) var creditLimits: CreditLimits?` stored property to `AppState` (written by PollingEngine after resolving tier from Keychain credentials)
  - [x] 2.2 Add `func updateCreditLimits(_ limits: CreditLimits?)` method to `AppState`
  - [x] 2.3 Revise `displayedWindow` computed property in `cc-hdrm/State/AppState.swift` (lines 86-101):
    - **FIRST: Exhausted guard** (applies to ALL paths):
      ```swift
      // Exhausted countdown always takes precedence over 7d promotion
      if fiveHour?.headroomState == .exhausted { return .fiveHour }
      ```
      CRITICAL: This guard must be ABOVE both the credit-math path and the fallback path. Without it, the credit-math path would promote 7d even when 5h is exhausted (quotas < 1 is true when 7d is also nearly exhausted), hiding the 5h countdown.
    - **Credit-math path** (when `creditLimits` is non-nil AND both `fiveHour`/`sevenDay` are non-nil):
      ```swift
      if let limits = creditLimits, let sevenDay {
          let remaining7d = (100.0 - sevenDay.utilization) / 100.0 * Double(limits.sevenDayCredits)
          let quotas = remaining7d / Double(limits.fiveHourCredits)
          return quotas < 1.0 ? .sevenDay : .fiveHour
      }
      ```
    - **Fallback path** (when `creditLimits` is nil): preserve the existing Story 3.2 percentage-comparison logic (7d headroom < 5h headroom AND 7d in warning/critical)
  - [x] 2.4 In `PollingEngine`, after reading `KeychainCredentials`, call `RateLimitTier.resolve(tierString: credentials.rateLimitTier, preferencesManager: preferencesManager)` and pass result to `appState.updateCreditLimits(_:)`. This happens each poll cycle since tier could change (e.g., subscription upgrade). ALSO: if Keychain read fails (catch block), call `appState.updateCreditLimits(nil)` to clear stale tier data from the previous successful cycle.

- [x] Task 3: Add `quotasRemaining` computed property to AppState (AC: 2, 7)
  - [x] 3.1 Add `var quotasRemaining: Double?` computed property to `AppState`:
    ```swift
    var quotasRemaining: Double? {
        guard let limits = creditLimits,
              let sevenDay else { return nil }
        let remaining7d = (100.0 - sevenDay.utilization) / 100.0 * Double(limits.sevenDayCredits)
        return remaining7d / Double(limits.fiveHourCredits)
    }
    ```
  - [x] 3.2 CRITICAL: `displayedWindow` should use `quotasRemaining` rather than recomputing -- ensures single computation, consistent results. Refactor `displayedWindow` to call `quotasRemaining` internally.

- [x] Task 4: Add GaugeIcon 7d colored dot rendering (AC: 3)
  - [x] 4.1 Add new `static func make(headroomPercentage:state:sevenDayOverlay:)` method to `GaugeIcon` in `cc-hdrm/Views/GaugeIcon.swift` where `sevenDayOverlay` is an enum:
    ```swift
    enum SevenDayOverlay: Equatable {
        case none                           // 7d normal or data unavailable
        case dot(HeadroomState)             // colored dot for caution/warning/critical
        case promoted                       // "7d" label when promoted
    }
    ```
  - [x] 4.2 Define `SevenDayOverlay` enum inside `GaugeIcon` namespace (keeps it scoped, no new file needed)
  - [x] 4.3 Implement dot drawing: small filled circle at top-right corner of the 18x18 canvas (approximately x=14, y=3, radius=2.0). Color comes from `NSColor.headroomColor(for: overlayState)`. Draw AFTER gauge components so dot renders on top.
  - [x] 4.4 Add `Geometry` constants: `dotCenterX: CGFloat = 14.5`, `dotCenterY: CGFloat = 3.5`, `dotRadius: CGFloat = 2.0`, `labelFontSize: CGFloat = 6.0`
  - [x] 4.5 Update the legacy wrapper `makeGaugeIcon(headroomPercentage:state:)` to call the new method with `.none` overlay for backward compatibility

- [x] Task 5: Add GaugeIcon "7d" label when promoted (AC: 4)
  - [x] 5.1 In the `.promoted` case of `SevenDayOverlay`, draw a tiny "7d" text at the same corner position where the dot would be (top-right)
  - [x] 5.2 Use `NSFont.systemFont(ofSize: 6.0, weight: .bold)` and the 7d headroom state color (from the `state` parameter, since when promoted the gauge state IS the 7d state)
  - [x] 5.3 Position the "7d" label using `NSAttributedString.draw(at:)` with proper point calculation to center it in the dot area

- [x] Task 6: Wire 7d state into AppDelegate for GaugeIcon rendering (AC: 3, 4, 5)
  - [x] 6.1 In `AppDelegate.updateMenuBarDisplay()` (line 261+), compute `sevenDayOverlay`:
    ```swift
    let sevenDayOverlay: GaugeIcon.SevenDayOverlay
    if state == .disconnected || appState.sevenDay == nil {
        sevenDayOverlay = .none
    } else if appState.displayedWindow == .sevenDay {
        sevenDayOverlay = .promoted
    } else if let sdState = appState.sevenDay?.headroomState,
              sdState == .caution || sdState == .warning || sdState == .critical {
        sevenDayOverlay = .dot(sdState)
    } else {
        sevenDayOverlay = .none
    }
    ```
  - [x] 6.2 Replace the `makeGaugeIcon(...)` call (line 274) with `GaugeIcon.make(headroomPercentage: headroom, state: state, sevenDayOverlay: sevenDayOverlay)`
  - [x] 6.3 AC-5 verification: when `displayedWindow == .fiveHour`, the menu bar text, color, weight, and slope arrow continue to render from 5h data. No changes needed to text rendering -- this is preserved by the existing `displayedWindow` logic.

- [x] Task 7: Credit-normalize 7d slope in SlopeCalculationService (AC: 6)
  - [x] 7.1 Add a `normalizationFactor` parameter to `calculateSlope` on **both** the protocol and the concrete class:
    ```swift
    // SlopeCalculationServiceProtocol:
    func calculateSlope(for window: UsageWindow, normalizationFactor: Double?) -> SlopeLevel

    // Keep the old signature as a convenience overload with default nil:
    func calculateSlope(for window: UsageWindow) -> SlopeLevel
    ```
    The parameter approach is preferred over a stored property because: (a) no mutable state to protect with locks — eliminates the data race between MainActor writes and NSLock reads, (b) protocol-compatible — PollingEngine holds `any SlopeCalculationServiceProtocol`, so the method must be on the protocol, (c) callers explicitly pass context — no hidden coupling.
  - [x] 7.2 Add default implementation via protocol extension so existing callers don't break:
    ```swift
    extension SlopeCalculationServiceProtocol {
        func calculateSlope(for window: UsageWindow) -> SlopeLevel {
            calculateSlope(for: window, normalizationFactor: nil)
        }
    }
    ```
  - [x] 7.3 In `calculateSlope(for:normalizationFactor:)`, after computing `ratePerMinute`, apply normalization for `.sevenDay` only:
    ```swift
    let effectiveRate: Double
    if window == .sevenDay, let factor = normalizationFactor {
        effectiveRate = ratePerMinute * factor
    } else {
        effectiveRate = ratePerMinute
    }
    ```
    Then map `effectiveRate` to `SlopeLevel` using existing thresholds. 5h slope is unchanged. 7d slope with nil factor falls back to raw percentage.
  - [x] 7.4 In PollingEngine (where slopes are calculated each poll cycle), pass the normalization factor:
    ```swift
    let normFactor = creditLimits?.normalizationFactor
    let fiveHourSlope = slopeService.calculateSlope(for: .fiveHour)
    let sevenDaySlope = slopeService.calculateSlope(for: .sevenDay, normalizationFactor: normFactor)
    appState.updateSlopes(fiveHour: fiveHourSlope, sevenDay: sevenDaySlope)
    ```
    This is thread-safe by design — no shared mutable state.

- [x] Task 8: Add "quotas remaining" to SevenDayGaugeSection (AC: 7)
  - [x] 8.1 In `cc-hdrm/Views/SevenDayGaugeSection.swift`, add below the `CountdownLabel`:
    ```swift
    if let quotas = appState.quotasRemaining {
        let wholeQuotas = Int(floor(quotas))
        Text("\(wholeQuotas) full 5h quotas left")
            .font(.caption2)
            .foregroundStyle(Color.headroomColor(for: sevenDayState))
    }
    ```
  - [x] 8.2 Hidden when `appState.quotasRemaining` is nil (credit limits unavailable) -- the `if let` handles this
  - [x] 8.3 When `wholeQuotas == 0`, the text reads "0 full 5h quotas left" and the color naturally reflects the 7d headroom state (warning/critical), fulfilling that AC clause
  - [x] 8.4 Update `combinedAccessibilityLabel` to include quotas: append `, [N] full 5-hour quotas left` when `quotasRemaining` is non-nil:
    ```swift
    if let quotas = appState.quotasRemaining {
        label += ", \(Int(floor(quotas))) full 5-hour quotas left"
    }
    ```

- [x] Task 9: Write RateLimitTier tests (AC: 1, 8)
  - [x] 9.1 Create NEW file `cc-hdrmTests/Models/RateLimitTierTests.swift`
  - [x] 9.2 Test: `.pro` has `fiveHourCredits == 550_000` and `sevenDayCredits == 5_000_000`
  - [x] 9.3 Test: `.max5x` has `fiveHourCredits == 3_300_000` and `sevenDayCredits == 41_666_700`
  - [x] 9.4 Test: `.max20x` has `fiveHourCredits == 11_000_000` and `sevenDayCredits == 83_333_300`
  - [x] 9.5 Test: `RateLimitTier(rawValue: "default_claude_pro")` returns `.pro`
  - [x] 9.6 Test: `RateLimitTier(rawValue: "default_claude_max_5x")` returns `.max5x`
  - [x] 9.7 Test: `RateLimitTier(rawValue: "default_claude_max_20x")` returns `.max20x`
  - [x] 9.8 Test: `RateLimitTier(rawValue: "unknown_tier")` returns nil
  - [x] 9.9 Test: `resolve()` with known tier string returns `CreditLimits` matching the tier's values
  - [x] 9.10 Test: `resolve()` with unknown tier + custom limits in PreferencesManager returns `CreditLimits` with custom values
  - [x] 9.11 Test: `resolve()` with unknown tier + no custom limits returns nil
  - [x] 9.12 Test: `CreditLimits.normalizationFactor` is approximately correct (~9.09 for Pro, ~12.63 for Max 5x, ~7.58 for Max 20x)
  - [x] 9.13 Test: `RateLimitTier.creditLimits` returns a `CreditLimits` with matching values for each tier

- [x] Task 10: Write credit-math promotion tests (AC: 2, 8)
  - [x] 10.1 In `cc-hdrmTests/State/AppStateTests.swift`, REPLACE the existing "Tighter Constraint Promotion Tests" section (lines 344-471) with credit-math tests. KEEP the existing "both exhausted" and "5h exhausted 7d warning" edge-case tests as they still apply.
  - [x] 10.2 Test: Pro tier, 7d utilization 95% → remaining credits = 250,000 → quotas = 250,000/550,000 = 0.45 → promotes 7d (`displayedWindow == .sevenDay`)
  - [x] 10.3 Test: Pro tier, 7d utilization 80% → remaining credits = 1,000,000 → quotas = 1,000,000/550,000 = 1.82 → stays 5h (`displayedWindow == .fiveHour`)
  - [x] 10.4 Test: Max 5x tier, 7d utilization 95% → remaining credits = 2,083,335 → quotas = 2,083,335/3,300,000 = 0.63 → promotes 7d
  - [x] 10.5 Test: Max 5x tier, 7d utilization 90% → remaining credits = 4,166,670 → quotas = 4,166,670/3,300,000 = 1.26 → stays 5h
  - [x] 10.6 Test: nil tier (fallback) → uses Story 3.2 percentage rule: 5h headroom 72%, 7d headroom 18% warning → promotes 7d
  - [x] 10.7 Test: nil tier (fallback) → 5h headroom 35% caution, 7d headroom 30% caution → stays 5h (7d not warning/critical)
  - [x] 10.8 Test: 5h exhausted (util=100, resetsAt present) + Pro tier with 7d util 95% (quotas=0.45 < 1) → `displayedWindow == .fiveHour` despite quotas < 1, because exhausted guard fires first. This verifies the explicit `if fiveHour?.headroomState == .exhausted { return .fiveHour }` guard. Without this guard, credit-math would promote 7d and HIDE the 5h exhausted countdown.
  - [x] 10.9 Test: `quotasRemaining` computed property returns correct value for Pro tier with 7d utilization 90%
  - [x] 10.10 Test: `quotasRemaining` returns nil when `creditLimits` is nil
  - [x] 10.11 Test: `quotasRemaining` returns nil when `sevenDay` is nil
  - [x] 10.12 Test: Boundary — Pro tier, 7d utilization exactly 89% → remaining = 550,000 → quotas = 1.0 exactly → stays 5h (`displayedWindow == .fiveHour`). Verifies `< 1.0` (strict less-than), not `<= 1.0`.

- [x] Task 11: Write GaugeIcon dot/label tests (AC: 3, 4, 8)
  - [x] 11.1 In `cc-hdrmTests/Views/GaugeIconTests.swift`, add new section "7d Overlay Tests"
  - [x] 11.2 Test: `GaugeIcon.make(headroomPercentage: 83, state: .normal, sevenDayOverlay: .dot(.warning))` produces valid 18x18 image (basic render test -- verifying no crash with overlay)
  - [x] 11.3 Test: `GaugeIcon.make(headroomPercentage: 83, state: .normal, sevenDayOverlay: .dot(.caution))` produces valid 18x18 image
  - [x] 11.4 Test: `GaugeIcon.make(headroomPercentage: 83, state: .normal, sevenDayOverlay: .dot(.critical))` produces valid 18x18 image
  - [x] 11.5 Test: `GaugeIcon.make(headroomPercentage: 18, state: .warning, sevenDayOverlay: .promoted)` produces valid 18x18 image (7d label)
  - [x] 11.6 Test: `GaugeIcon.make(headroomPercentage: 83, state: .normal, sevenDayOverlay: .none)` produces valid image identical in size to existing gauge (backward compat)
  - [x] 11.7 Test: legacy `makeGaugeIcon(headroomPercentage:state:)` still works (no regression)

- [x] Task 12: Write credit-normalized slope tests (AC: 6, 8)
  - [x] 12.1 In `cc-hdrmTests/Services/SlopeCalculationServiceTests.swift`, add new section "Credit Normalization Tests"
  - [x] 12.2 Test: `calculateSlope(for: .sevenDay, normalizationFactor: 12.63)` with 7d raw rate 0.08%/min → effective rate ~1.01%/min → `.rising` (without normalization would be `.flat` at 0.08)
  - [x] 12.3 Test: `calculateSlope(for: .sevenDay, normalizationFactor: 12.63)` with 7d raw rate 0.15%/min → effective rate ~1.89%/min → `.steep`
  - [x] 12.4 Test: `calculateSlope(for: .fiveHour, normalizationFactor: 12.63)` — 5h slope is UNCHANGED regardless of normalization factor (factor only applies to 7d)
  - [x] 12.5 Test: `calculateSlope(for: .sevenDay, normalizationFactor: nil)` — falls back to raw rate (same as current behavior)
  - [x] 12.6 Test: `calculateSlope(for: .sevenDay, normalizationFactor: 9.09)` with 7d raw rate 0.02%/min → effective rate ~0.18%/min → `.flat` (even normalized, still below threshold)
  - [x] 12.7 Test: `calculateSlope(for: .sevenDay)` (no-arg convenience) → same as passing `normalizationFactor: nil` (backward compat)

- [x] Task 13: Write popover quotas display tests (AC: 7, 8)
  - [x] 13.1 In `cc-hdrmTests/Views/` create or extend `SevenDayGaugeSectionTests.swift`
  - [x] 13.2 Test: `combinedAccessibilityLabel` includes "N full 5-hour quotas left" when `quotasRemaining` is non-nil (test via AppState setup with tier + 7d data)
  - [x] 13.3 Test: `combinedAccessibilityLabel` does NOT include "quotas" when `quotasRemaining` is nil
  - [x] 13.4 Test: `quotasRemaining` of 2.7 → accessibility says "2 full 5-hour quotas left" (floored)
  - [x] 13.5 Test: `quotasRemaining` of 0.3 → accessibility says "0 full 5-hour quotas left"

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. `AppState` is the single `@Observable` source of truth. All new computed properties (`quotasRemaining`, revised `displayedWindow`) follow the "derived, never stored" rule.
- **State boundary:** `creditLimits: CreditLimits?` is the only new stored property on `AppState`. It is written via `updateCreditLimits(_:)` from PollingEngine after resolving the Keychain tier string. Must be declared directly on the `@Observable` class (not nested in a struct) for observation tracking to work.
- **Type design:** `RateLimitTier` is a String raw-value enum for known tiers. `CreditLimits` is a plain struct carrying `fiveHourCredits`, `sevenDayCredits`, and computed `normalizationFactor`. `resolve()` returns `CreditLimits?` — this supports both known tiers AND custom user-configured limits without trying to create runtime enum cases (impossible with raw-value enums).
- **Concurrency:** All `AppState` access is `@MainActor`. Slope normalization factor is passed as a parameter to `calculateSlope(for:normalizationFactor:)` — no shared mutable state, no thread-safety concern. No GCD.
- **Logging:** `os.Logger` with category `"tier"` for RateLimitTier resolution. Existing `"slope"` category for normalization logging.
- **Observation integration:** `quotasRemaining` accesses `creditLimits` and `sevenDay`, so `withObservationTracking` in AppDelegate re-fires when either changes. No additional observation wiring needed.

### Credit-Math Promotion vs. Percentage-Comparison

**Story 3.2 rule (now fallback):**
```
if 7d_headroom < 5h_headroom AND 7d is warning/critical → promote 7d
```
Fires too aggressively — e.g., 7d at 18% warning, 5h at 72% normal → promotes, hiding 5h info.

**Story 3.3 rule (new primary):**
```
remaining_7d_credits = (100% - 7d_util%) × 7d_credit_limit
quotas_remaining = remaining_7d_credits / 5h_credit_limit
if quotas_remaining < 1 → promote 7d
```
Only fires when you literally can't fit one more full 5h cycle — much higher bar for promotion.

**Example (Max 5x):**
- 7d at 90% util → remaining = 4,166,670 credits → quotas = 1.26 → NO promotion (stays 5h)
- 7d at 95% util → remaining = 2,083,335 credits → quotas = 0.63 → PROMOTE 7d

### Previous Story Intelligence (Story 3.2)

**What was built:**
- `DisplayedWindow` enum in `cc-hdrm/State/AppState.swift` (line 31-34) — reuse this
- `displayedWindow` computed property (lines 86-101) — REPLACE the body
- `menuBarHeadroomState` delegates to `displayedWindow` (lines 105-116) — no changes needed
- `menuBarText` uses `displayedWindow` (lines 132-154) — no changes needed
- `countdownTick` observation pattern (line 68, 141) — no changes
- Existing promotion tests in `AppStateTests.swift` (lines 344-471) — REPLACE these

**Patterns to reuse:**
- Computed property pattern on AppState — add `quotasRemaining` as computed
- Test pattern: `@MainActor`, create `AppState()`, set connection + windows + tier, assert
- GaugeIcon drawing pattern: NSBezierPath in flipped coordinates, draw in image context

**Code review lessons from all previous stories:**
- Pass original errors to `AppError` wrappers, not hardcoded errors
- Remove dead code / unused properties before committing
- Add call counters to mocks for verifying interaction patterns
- Make services `@MainActor` when they hold `AppState` reference
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file

### Git Intelligence

Recent commits:
- `8cc8208` chore: bump version to 1.1.3
- `0f58b26` fix: eliminate sparkline spikes from API jitter and Power Nap wakes
- `26fa9de` chore: update changelog for v1.1.2

**Patterns:** Version bump commits, fix commits for data-quality issues. Story impl PRs use `feat:` prefix.

### Project Structure Notes

- XcodeGen (`project.yml`) uses directory-based source discovery — new files in correct folders auto-included after `xcodegen generate`
- Test files mirror source structure under `cc-hdrmTests/`
- `RateLimitTier.swift` goes in `cc-hdrm/Models/` (model enum per architecture)
- `RateLimitTierTests.swift` goes in `cc-hdrmTests/Models/`
- `GaugeIcon.swift` already exists — extend it, don't create a new file
- `GaugeIconTests.swift` already exists at `cc-hdrmTests/Views/GaugeIconTests.swift` — extend it
- `PreferencesManager.swift` already exists — add custom credit limit properties there
- `PreferencesManagerProtocol.swift` already exists — add custom credit limit properties there

### File Structure Requirements

Files to create:
```
cc-hdrm/Models/RateLimitTier.swift                  # NEW — credit limit enum
cc-hdrmTests/Models/RateLimitTierTests.swift         # NEW — tier tests
```

Files to modify:
```
cc-hdrm/State/AppState.swift                         # Add creditLimits, quotasRemaining, revise displayedWindow with exhausted guard
cc-hdrm/Views/GaugeIcon.swift                        # Add SevenDayOverlay enum, dot/label drawing, new make() overload
cc-hdrm/Services/SlopeCalculationServiceProtocol.swift  # Add calculateSlope(for:normalizationFactor:) method
cc-hdrm/Services/SlopeCalculationService.swift       # Implement normalization parameter in calculateSlope
cc-hdrm/Views/SevenDayGaugeSection.swift             # Add quotas display line + accessibility
cc-hdrm/App/AppDelegate.swift                        # Compute sevenDayOverlay, pass to GaugeIcon
cc-hdrm/Services/PreferencesManagerProtocol.swift    # Add customFiveHourCredits, customSevenDayCredits
cc-hdrm/Services/PreferencesManager.swift            # Implement custom credit limit properties
cc-hdrmTests/State/AppStateTests.swift               # Replace promotion tests, add quotas + exhausted guard tests
cc-hdrmTests/Services/SlopeCalculationServiceTests.swift  # Add normalization parameter tests
cc-hdrmTests/Views/GaugeIconTests.swift              # Add dot/label overlay tests
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on any test touching `AppState`
- **Promotion tests:** Replace existing percentage-comparison tests (lines 344-471 in AppStateTests) with credit-math tests. Set `creditLimits` via `updateCreditLimits()`, set windows, assert `displayedWindow` and `quotasRemaining`. Include exhausted guard test and quotas==1.0 boundary test.
- **Fallback tests:** Set `creditLimits` to nil, verify Story 3.2 percentage rule still works.
- **Slope normalization tests:** Pass `normalizationFactor` parameter to `calculateSlope(for:normalizationFactor:)`, feed 7d polls, verify slope level changes with normalization. Also verify no-arg convenience overload.
- **GaugeIcon tests:** Render with different overlay enums, verify image size and no crash. Pixel-level color testing is not required (AppKit rendering varies).
- **Edge cases:** Both windows exhausted, 5h exhausted with 7d promoted, unknown tier, nil sevenDay.

### Anti-Patterns to Avoid

- DO NOT store `quotasRemaining` as a separate stored property — it must be computed from `creditLimits` and `sevenDay`
- DO NOT put credit limit values in a plist or JSON file — they are hardcoded constants in the enum (per architecture spec)
- DO NOT add `RateLimitTier` imports to views — views read `quotasRemaining` from AppState, which is already a `Double?`
- DO NOT use `DispatchQueue` or GCD — stick to structured concurrency and NSLock (existing pattern)
- DO NOT create a separate `CreditMathService` — the math is simple enough for computed properties on AppState
- DO NOT try to create "synthetic" enum cases at runtime — `RateLimitTier` is a String raw-value enum; use `CreditLimits` struct for custom limits
- DO NOT store `normalizationFactor` as mutable state on `SlopeCalculationService` — pass it as a parameter to `calculateSlope(for:normalizationFactor:)` to avoid data races between MainActor writes and NSLock reads
- DO NOT omit the exhausted guard in `displayedWindow` — without `if fiveHour?.headroomState == .exhausted { return .fiveHour }` at the top, credit-math will promote 7d when 5h is exhausted, hiding the countdown
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT break existing tests — 5h slope, 5h menu bar display, exhausted countdown must all remain unchanged

### References

- [Source: cc-hdrm/State/AppState.swift] — Current `displayedWindow` (lines 86-101), `menuBarText` (lines 132-154), `menuBarHeadroomState` (lines 105-116)
- [Source: cc-hdrm/Views/GaugeIcon.swift] — Current gauge drawing (lines 52-58 `make()`, lines 91-122 `drawGauge()`), Geometry constants (lines 20-37)
- [Source: cc-hdrm/Services/SlopeCalculationServiceProtocol.swift] — Protocol definition (lines 5-20), `calculateSlope(for:)` signature (line 15)
- [Source: cc-hdrm/Services/SlopeCalculationService.swift] — Ring buffer (lines 23-35), `calculateSlope()` (lines 84-141), thresholds (lines 46-49)
- [Source: cc-hdrm/Views/SevenDayGaugeSection.swift] — Current layout (lines 34-61), `combinedAccessibilityLabel` (lines 22-31)
- [Source: cc-hdrm/App/AppDelegate.swift] — `updateMenuBarDisplay()` (lines 261-336), gauge icon creation (lines 268-275)
- [Source: cc-hdrm/Models/KeychainCredentials.swift] — `rateLimitTier: String?` (line 10)
- [Source: cc-hdrm/Services/PreferencesManagerProtocol.swift] — Protocol definition (lines 12-21)
- [Source: cc-hdrm/Services/PreferencesManager.swift] — Implementation (lines 6-144)
- [Source: architecture.md, Phase 3, "Credit Limit Handling"] — `RateLimitTier` enum spec, raw values, credit values
- [Source: architecture.md, "Cross-Cutting Concerns"] — Dual-window credit-math promotion description
- [Source: architecture.md, Phase 3, "SlopeCalculationService"] — Credit normalization formula
- [Source: story 3.2] — Previous story patterns, `DisplayedWindow` enum, observation loop, promotion logic

### Relationship to Epic 14

This story absorbs Story 14.1's `RateLimitTier` enum definition. When Epic 14 stories 14.2-14.5 are implemented later, they will consume this enum directly. Story 14.1 should be marked as absorbed/done in sprint-status.yaml.

## Dev Agent Record

### Agent Model Used

Claude claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

None.

### Completion Notes List

- Created `RateLimitTier` enum with `.pro`, `.max5x`, `.max20x` cases and `CreditLimits` struct with `normalizationFactor` computed property
- Added `customFiveHourCredits`/`customSevenDayCredits` to `PreferencesManagerProtocol` and `PreferencesManager` for unknown tier fallback
- Revised `displayedWindow` with exhausted guard, credit-math path (`quotasRemaining < 1`), and Story 3.2 percentage-comparison fallback
- Added `quotasRemaining` computed property; `displayedWindow` uses it internally (single computation)
- Added `SevenDayOverlay` enum to `GaugeIcon` with `.none`, `.dot(HeadroomState)`, `.promoted` cases
- Implemented dot drawing (filled circle top-right corner) and "7d" label drawing in `GaugeIcon`
- Wired `sevenDayOverlay` computation into `AppDelegate.updateMenuBarDisplay()`
- Added `normalizationFactor` parameter to `SlopeCalculationServiceProtocol.calculateSlope(for:normalizationFactor:)` with backward-compatible convenience overload via protocol extension
- Applied credit normalization in `SlopeCalculationService` for 7d window only
- Wired normalization factor from `PollingEngine` to slope service and creditLimits to AppState per poll cycle
- Added "X full 5h quotas left" display to `SevenDayGaugeSection` with VoiceOver accessibility
- Replaced old percentage-comparison promotion tests with credit-math tests (Pro, Max 5x, fallback, boundary, exhausted guard)
- All 661 tests pass (0 regressions)

#### Code Review Fixes Applied

- [M1] Added defensive guard against `fiveHourCredits == 0` in `CreditLimits.normalizationFactor` (returns 0) and `AppState.quotasRemaining` (returns nil) — prevents inf propagation
- [M2] Added explicit tests for `resolve(tierString: nil, ...)` — nil with no custom limits returns nil; nil with custom limits returns custom CreditLimits
- [M3] Clamped GaugeIcon "7d" label draw position to canvas bounds — prevents right-edge clipping of the "d" character
- [M4] Added structural overlay assertions to GaugeIcon tests — verifies `.dot` and `.promoted` overlays produce different pixel data than `.none`
- [L1] Added guard in `drawSevenDayDot` to only draw for caution/warning/critical states — `assertionFailure` catches misuse in debug
- [L2] Added `validateCustomLimits()` with warning log when custom limits produce extreme normalization factor (< 0.1 or > 200)
- [L3] PollingEngine integration test for credit limit resolution wiring documented as follow-up (no PollingEngine test suite exists — pre-existing gap)
- Added defensive guard tests: `normalizationFactor` with zero fiveHourCredits, `quotasRemaining` with zero fiveHourCredits

### Review Follow-ups

- [ ] [AI-Review][LOW] Create PollingEngine test suite with credit limit resolution wiring test [cc-hdrm/Services/PollingEngine.swift:151-156]

### Change Log

- 2026-02-05: Implemented Story 3.3 - Credit-math 7d promotion, GaugeIcon 7d overlay, slope normalization, popover quotas display
- 2026-02-05: Code review fixes — defensive guards, nil tier test, label clamp, structural test assertions, dot state guard, custom limit validation

### File List

New files:
- cc-hdrm/Models/RateLimitTier.swift
- cc-hdrmTests/Models/RateLimitTierTests.swift

Modified files:
- cc-hdrm/State/AppState.swift
- cc-hdrm/Views/GaugeIcon.swift
- cc-hdrm/Views/SevenDayGaugeSection.swift
- cc-hdrm/App/AppDelegate.swift
- cc-hdrm/Services/SlopeCalculationServiceProtocol.swift
- cc-hdrm/Services/SlopeCalculationService.swift
- cc-hdrm/Services/PreferencesManagerProtocol.swift
- cc-hdrm/Services/PreferencesManager.swift
- cc-hdrm/Services/PollingEngine.swift
- cc-hdrmTests/State/AppStateTests.swift
- cc-hdrmTests/Views/GaugeIconTests.swift
- cc-hdrmTests/Services/SlopeCalculationServiceTests.swift
- cc-hdrmTests/Views/SevenDayGaugeSectionTests.swift
- cc-hdrmTests/Mocks/MockPreferencesManager.swift
