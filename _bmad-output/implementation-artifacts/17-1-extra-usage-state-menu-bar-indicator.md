# Story 17.1: Extra Usage State Propagation & Menu Bar Indicator

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want the menu bar to visually distinguish "over plan quota and burning extra credits" from "exhausted and waiting for reset,"
so that I know at a glance when I'm spending real money beyond my subscription.

## Acceptance Criteria

1. **Given** `UsageResponse.extraUsage` is returned by the API
   **When** `AppState` processes the poll response
   **Then** the following extra usage fields are surfaced as observable properties:
   - `extraUsageEnabled: Bool`
   - `extraUsageMonthlyLimit: Double?`
   - `extraUsageUsedCredits: Double?`
   - `extraUsageUtilization: Double?`

2. **Given** `extraUsage.isEnabled == true` AND either the 5h or 7d plan utilization is at 100% (`.exhausted` state)
   **When** the menu bar renders
   **Then** the gauge icon switches to "extra usage mode":
   - The gauge **repurposes** to show prepaid extra usage balance draining
   - The text label shows a **currency amount** (e.g., "$27.39") representing the remaining balance, instead of a headroom percentage
   - The needle direction **reverses** compared to headroom: the arc is **full on the left** and **empty on the right** -- the needle sweeps left-to-right as the prepaid balance drains (opposite of headroom where full is on the right)
   - This reversed direction + currency symbol makes it unmistakable that the gauge is showing prepaid balance, not plan headroom
   - The arc color follows a calm-to-warm-to-hot progression as the balance drains toward zero, using colors distinct from the headroom state palette (e.g., a dedicated "extra usage" color ramp that avoids confusion with the green-to-yellow-to-orange-to-red headroom states)

3. **Given** `extraUsage.monthlyLimit` is known
   **When** the gauge renders in extra usage mode
   **Then** the needle position reflects remaining balance: `(monthlyLimit - usedCredits) / monthlyLimit` -- full balance = needle on the left (full arc), depleted = needle on the right (empty arc)

4. **Given** `extraUsage.monthlyLimit` is nil (no limit set)
   **When** the gauge renders in extra usage mode
   **Then** the text shows the spent amount only (e.g., "$15.61 spent") and the needle position is not meaningful -- use a fixed position or hide the needle

5. **Given** `extraUsage.isEnabled == false` AND plan utilization is at 100%
   **When** the menu bar renders
   **Then** it shows the existing `.exhausted` state unchanged

6. **Given** `extraUsage.isEnabled == true` but plan utilization is below 100%
   **When** the menu bar renders
   **Then** no extra usage indicator is shown -- normal headroom display applies

7. **Given** `extraUsage` is nil (API did not return it)
   **When** `AppState` processes the response
   **Then** extra usage fields default to disabled/nil and no extra usage UI appears

8. **Given** VoiceOver is active and the menu bar is in "burning extra" state
   **When** VoiceOver reads the status item
   **Then** it announces: "Claude usage: extra usage active, [amount] spent of [limit]"

9. **Currency note:** The `ExtraUsage` API model (`cc-hdrm/Models/UsageResponse.swift:30-43`) returns `usedCredits` and `monthlyLimit` as raw `Double` values with no currency indicator. Default to `$` (USD) display. If a currency field is discovered during implementation, parse and use it.

## Tasks / Subtasks

- [x] Task 1: Add extra usage state properties to AppState (AC: 1, 7)
  - [x] 1.1 Add `private(set) var extraUsageEnabled: Bool = false` to `cc-hdrm/State/AppState.swift`
  - [x] 1.2 Add `private(set) var extraUsageMonthlyLimit: Double? = nil`
  - [x] 1.3 Add `private(set) var extraUsageUsedCredits: Double? = nil`
  - [x] 1.4 Add `private(set) var extraUsageUtilization: Double? = nil`
  - [x] 1.5 Add computed `var isExtraUsageActive: Bool` -- returns `true` when `extraUsageEnabled == true` AND at least one window is `.exhausted`
  - [x] 1.6 Add computed `var extraUsageRemainingBalance: Double?` -- returns `monthlyLimit - usedCredits` when both are available, nil otherwise
  - [x] 1.7 Add `func updateExtraUsage(enabled: Bool, monthlyLimit: Double?, usedCredits: Double?, utilization: Double?)` method
  - [x] 1.8 When extra usage is nil from API, call `updateExtraUsage(enabled: false, monthlyLimit: nil, usedCredits: nil, utilization: nil)`

- [x] Task 2: Wire PollingEngine to propagate extra usage data (AC: 1, 7)
  - [x] 2.1 In `cc-hdrm/Services/PollingEngine.swift:fetchUsageData()`, extract extra usage from `response.extraUsage` BEFORE `appState.updateWindows()` to avoid transient UI flicker
  - [x] 2.2 Call `appState.updateExtraUsage(enabled:monthlyLimit:usedCredits:utilization:)` with values from `response.extraUsage` (defaulting `enabled` to `false` when `extraUsage` is nil)
  - [x] 2.3 Ensure extra usage state is cleared on credential error (in `handleCredentialError()`)

- [x] Task 3: Create extra usage color tokens (AC: 2)
  - [x] 3.1 Add `ExtraUsageColors/` color set folder in `cc-hdrm/Resources/Assets.xcassets/` with 4 colors: `ExtraUsageCool`, `ExtraUsageWarm`, `ExtraUsageHot`, `ExtraUsageCritical` -- distinct from headroom palette (blue-to-purple-to-magenta-to-red ramp)
  - [x] 3.2 Add `NSColor.extraUsageColor(for utilization: Double) -> NSColor` extension in `cc-hdrm/Extensions/Color+Headroom.swift` that maps extra usage utilization (0-1) to the 4-tier color ramp
  - [x] 3.3 Add corresponding SwiftUI `Color` static properties: `.extraUsageCool`, `.extraUsageWarm`, `.extraUsageHot`, `.extraUsageCritical`
  - [x] 3.4 Add fallback programmatic colors for test targets (same pattern as `fallbackColor(for:)`)
  - [x] 3.5 Add `NSFont.extraUsageMenuBarFont(for utilization: Double) -> NSFont` -- uses `.semibold` for 0-0.75, `.bold` for 0.75+

- [x] Task 4: Add extra usage gauge mode to GaugeIcon (AC: 2, 3, 4)
  - [x] 4.1 Add `static func makeExtraUsage(remainingFraction: Double, utilization: Double) -> NSImage` to `cc-hdrm/Views/GaugeIcon.swift`
  - [x] 4.2 **Reversed needle direction**: `remainingFraction` of 1.0 (full balance) puts needle at LEFT (pi radians), 0.0 (depleted) puts needle at RIGHT (0 radians). Angle formula: `theta = pi * remainingFraction`
  - [x] 4.3 **Reversed fill arc**: fill sweeps from RIGHT (0 radians) toward LEFT -- the filled portion represents the *drained* balance
  - [x] 4.4 Color from `NSColor.extraUsageColor(for: utilization)` -- varies by how much of the limit has been consumed
  - [x] 4.5 Track arc at 25% opacity of the extra usage color (same pattern as headroom gauge)
  - [x] 4.6 Add `static func makeExtraUsageNoLimit(utilization: Double) -> NSImage` for the no-limit case -- fixed needle at midpoint, fill at 50%, uses extra usage color
  - [x] 4.7 No 7d overlay in extra usage mode (7d is not relevant when showing extra usage balance)

- [x] Task 5: Update AppState.menuBarText for extra usage mode (AC: 2, 4)
  - [x] 5.1 Add computed `var menuBarExtraUsageText: String?` to `cc-hdrm/State/AppState.swift` that returns non-nil only when `isExtraUsageActive`
  - [x] 5.2 When `monthlyLimit` is known: format remaining balance as currency -- e.g., `"$27.39"` using `String(format: "$%.2f", remainingBalance)`
  - [x] 5.3 When `monthlyLimit` is nil: format as `"$15.61 spent"` using `String(format: "$%.2f spent", usedCredits)`
  - [x] 5.4 Modify `var menuBarText: String` to check `menuBarExtraUsageText` first -- if non-nil, return it instead of the normal headroom text

- [x] Task 6: Update AppDelegate.updateMenuBarDisplay() for extra usage mode (AC: 2, 3, 4, 5, 6)
  - [x] 6.1 In `cc-hdrm/App/AppDelegate.swift:updateMenuBarDisplay()`, add an early check: if `appState.isExtraUsageActive`, branch to extra usage rendering
  - [x] 6.2 Extra usage rendering path: computes remainingFraction, utilization, generates icon, applies extra usage color + font
  - [x] 6.3 Normal rendering path (existing code) remains unchanged for all non-extra-usage states

- [x] Task 7: Update VoiceOver accessibility for extra usage mode (AC: 8)
  - [x] 7.1 In `cc-hdrm/App/AppDelegate.swift:updateMenuBarDisplay()`, add extra usage accessibility path
  - [x] 7.2 When `isExtraUsageActive` AND `monthlyLimit` is known: `"cc-hdrm: Claude usage: extra usage active, [usedCredits] dollars spent of [monthlyLimit] dollar limit"`
  - [x] 7.3 When `isExtraUsageActive` AND `monthlyLimit` is nil: `"cc-hdrm: Claude usage: extra usage active, [usedCredits] dollars spent, no limit set"`

- [x] Task 8: Write unit tests for AppState extra usage properties (AC: 1, 5, 6, 7)
  - [x] 8.1 Extended tests in `cc-hdrmTests/State/AppStateTests.swift`
  - [x] 8.2 Test `isExtraUsageActive` returns `true` when enabled AND 5h exhausted
  - [x] 8.3 Test `isExtraUsageActive` returns `true` when enabled AND 7d exhausted
  - [x] 8.4 Test `isExtraUsageActive` returns `false` when enabled but no window exhausted
  - [x] 8.5 Test `isExtraUsageActive` returns `false` when disabled even if exhausted
  - [x] 8.6 Test `extraUsageRemainingBalance` computation
  - [x] 8.7 Test `menuBarText` returns currency format when extra usage active with known limit
  - [x] 8.8 Test `menuBarText` returns "$X.XX spent" format when extra usage active with no limit
  - [x] 8.9 Test `menuBarText` returns normal headroom when extra usage inactive
  - [x] 8.10 Test `updateExtraUsage` clears previous values when called with nil

- [x] Task 9: Write unit tests for GaugeIcon extra usage mode (AC: 2, 3, 4)
  - [x] 9.1 Extended tests in `cc-hdrmTests/Views/GaugeIconTests.swift`
  - [x] 9.2 Test `makeExtraUsage` returns non-nil NSImage
  - [x] 9.3 Test reversed angle formula: `remainingFraction=1.0` produces angle at pi (left), `remainingFraction=0.0` produces angle at 0 (right)
  - [x] 9.4 Test `makeExtraUsageNoLimit` returns non-nil NSImage

- [x] Task 10: Write unit tests for extra usage color mapping (AC: 2)
  - [x] 10.1 Test `NSColor.extraUsageColor(for: 0.0)` returns `ExtraUsageCool` color
  - [x] 10.2 Test `NSColor.extraUsageColor(for: 0.6)` returns `ExtraUsageWarm` color
  - [x] 10.3 Test `NSColor.extraUsageColor(for: 0.8)` returns `ExtraUsageHot` color
  - [x] 10.4 Test `NSColor.extraUsageColor(for: 0.95)` returns `ExtraUsageCritical` color

- [x] Task 11: Run `xcodegen generate` and verify compilation + all tests pass

## Dev Notes

### Architecture Context

This story is the first in Epic 17, propagating the `ExtraUsage` data (already fetched from API and persisted to SQLite since PR 43) upward through `AppState` to the menu bar display layer. The data pipeline is complete -- what's missing is the view-layer surface area.

**Key design decisions:**
- Extra usage is NOT a new `HeadroomState` case -- it's a separate display mode that takes over the gauge when active. `HeadroomState` remains unchanged.
- The gauge *repurposes* rather than adding a second icon. The reversed needle direction + currency text + distinct color palette provides a clear visual break from the headroom gauge.
- Extra usage mode activates only when `extraUsageEnabled == true` AND at least one plan window is `.exhausted`. If the user hasn't hit their plan limits, normal headroom display applies even if extra usage is enabled on their account.
- Currency defaults to `$` (USD). The `ExtraUsage` model does not currently include a currency field. If one is discovered, Story 17.2+ can add parsing.

### Key Integration Points

**Files consumed (read-only):**
- `cc-hdrm/Models/UsageResponse.swift:30-43` -- `ExtraUsage` struct with `isEnabled`, `monthlyLimit`, `usedCredits`, `utilization`
- `cc-hdrm/Models/UsagePoll.swift:17-24` -- `extraUsageEnabled`, `extraUsageMonthlyLimit`, `extraUsageUsedCredits`, `extraUsageUtilization` fields
- `cc-hdrm/Services/DatabaseManager.swift:240-243` -- SQLite columns for extra usage persistence
- `cc-hdrm/Services/HistoricalDataService.swift:76-79` -- Extra usage extracted from `UsageResponse` during persistence
- `cc-hdrm/Models/HeadroomState.swift` -- `.exhausted` detection for triggering extra usage mode

**Files to modify:**
- `cc-hdrm/State/AppState.swift` -- Add 4 extra usage properties, `isExtraUsageActive` computed property, `extraUsageRemainingBalance`, `updateExtraUsage()` method, modify `menuBarText`
- `cc-hdrm/Services/PollingEngine.swift` -- Wire `response.extraUsage` to `appState.updateExtraUsage()` in `fetchUsageData()` and clear in `handleCredentialError()`
- `cc-hdrm/Views/GaugeIcon.swift` -- Add `makeExtraUsage()` and `makeExtraUsageNoLimit()` factory methods with reversed needle geometry
- `cc-hdrm/App/AppDelegate.swift` -- Add extra usage branch in `updateMenuBarDisplay()` for icon, text color, font, and VoiceOver
- `cc-hdrm/Extensions/Color+Headroom.swift` -- Add `extraUsageColor(for:)` NSColor extension, SwiftUI Color statics, NSFont extension

**Files to create:**
- `cc-hdrm/Resources/Assets.xcassets/ExtraUsageColors/` -- 4 new color sets (ExtraUsageCool, ExtraUsageWarm, ExtraUsageHot, ExtraUsageCritical) with light/dark variants

**No new Swift source files needed** -- all changes fit into existing files.

### Gauge Reversal Geometry

The headroom gauge uses:
- Angle: `theta = pi * (1 - headroom/100)` -- 100% headroom = 0 (right), 0% = pi (left)
- Fill: sweeps from LEFT (pi) toward the needle -- filled = available capacity

The extra usage gauge reverses both:
- Angle: `theta = pi * remainingFraction` -- 100% remaining = pi (left), 0% = 0 (right)
- Fill: sweeps from RIGHT (0) toward the needle -- filled = consumed balance
- Visual effect: as money drains, needle sweeps right and filled arc shrinks from right

```
Headroom gauge (normal):          Extra usage gauge (reversed):
   Full ●──────⟩  Empty              Empty ⟨──────● Full balance
   100%           0%                  0%             100%
   needle→right   needle→left        needle→left     needle→right
   fill from left                    fill from right
```

### Extra Usage Color Ramp

The extra usage color ramp must be **distinct from the headroom palette** to avoid confusion:

| Headroom (plan)     | Extra Usage (money)     |
|---------------------|------------------------|
| Green (normal)      | Cool blue/teal (calm)  |
| Yellow (caution)    | Purple/indigo (warm)   |
| Orange (warning)    | Magenta/pink (hot)     |
| Red (critical/exhausted) | Deep red (critical) |

Suggested HSB values for Asset Catalog color sets:
- `ExtraUsageCool`: HSB(200, 60%, 80%) -- blue-teal
- `ExtraUsageWarm`: HSB(270, 60%, 75%) -- purple
- `ExtraUsageHot`: HSB(320, 70%, 80%) -- magenta
- `ExtraUsageCritical`: HSB(350, 80%, 85%) -- deep red-pink

Dark mode variants should increase brightness by ~10-15% for readability against dark backgrounds.

### Currency Formatting

- Use `String(format: "$%.2f", amount)` for consistent 2-decimal currency display
- When `monthlyLimit` is known: show remaining balance `"$27.39"` (compact, fits menu bar)
- When `monthlyLimit` is nil: show spent amount `"$15.61 spent"` (longer but clear)
- Amounts are API `Double` values -- no locale-specific formatting needed for USD default
- Future stories can add proper `NumberFormatter` with `.currency` style if API adds currency info

### Extra Usage Mode Activation Logic

```swift
var isExtraUsageActive: Bool {
    guard extraUsageEnabled else { return false }
    let fiveHourExhausted = fiveHour?.headroomState == .exhausted
    let sevenDayExhausted = sevenDay?.headroomState == .exhausted
    return fiveHourExhausted || sevenDayExhausted
}
```

Priority order in `updateMenuBarDisplay()`:
1. **Disconnected** -- show X icon + em dash (existing)
2. **Extra usage active** -- show reversed gauge + currency text (NEW)
3. **Normal headroom** -- show headroom gauge + percentage/countdown (existing)

### Potential Pitfalls

1. **Race between `updateWindows()` and `updateExtraUsage()`**: Both are called in `fetchUsageData()`. Since both run on `@MainActor`, they're sequential. But the observation loop in `startObservingAppState()` could trigger a re-render between the two calls, showing a transient inconsistent state. Solution: call `updateExtraUsage()` BEFORE `updateWindows()` so extra usage state is set before window state triggers re-render. Alternatively, combine into a single update method.

2. **GaugeIcon canvas reuse**: The extra usage gauge reuses the same 18x18pt canvas and geometry constants (center, radius, needle length). Only the angle formula and color source change. Verify that the reversed fill arc draws correctly in flipped coordinates.

3. **Font width with currency text**: Currency text like "$27.39" is 6 characters, similar to "83% ↗" (5 chars). The `NSStatusItem.variableLength` accommodates this. But "$15.61 spent" is 12 characters -- significantly wider. Test that menu bar layout handles the longer text gracefully, especially on smaller displays. Consider truncating to "$15.61 spt" or just "$15.61" if space is tight.

4. **Extra usage utilization vs remaining fraction**: The API returns `utilization` (0-1 fraction of limit used) but the gauge shows *remaining* balance. `remainingFraction = 1.0 - utilization`. When `monthlyLimit` is nil, utilization may still be non-nil but is less meaningful -- use `usedCredits` for text display.

5. **Edge case: `usedCredits == 0` but extra usage enabled**: When the billing period resets, `usedCredits` may be 0 with `isEnabled == true` and plan not exhausted. The `isExtraUsageActive` check prevents display (plan must be exhausted first). But if plan IS exhausted and credits are 0, the gauge should show full balance remaining.

6. **Asset catalog color sets**: Must create actual `.colorset` directories with `Contents.json` files, not just Swift code. Each color set needs `Any Appearance` and `Dark` variants. Use the same structure as existing `HeadroomColors/` folder.

7. **Observation tracking**: `menuBarText` now branches based on `isExtraUsageActive`, which depends on `extraUsageEnabled`, `fiveHour`, and `sevenDay`. All are `@Observable` properties, so `withObservationTracking` will correctly pick up changes. But verify that the new `menuBarExtraUsageText` computed property accesses all the right properties to register tracking.

8. **PollingEngine ordering**: Currently `updateWindows()` is called at line 164, then `updateConnectionStatus()` at line 166. Extra usage update should go between them (or immediately after `updateWindows()`) to minimize transient UI flicker. The recommended approach is to call `updateExtraUsage()` at line 165, right after `updateWindows()`.

### Previous Story Intelligence

Key learnings from Epic 16 (Stories 16.1-16.6):
- **AppState update pattern**: All new state goes through `private(set) var` + dedicated `func update*()` methods. Never expose setters directly.
- **GaugeIcon extension pattern**: New factory methods (`make(...)`) alongside existing ones. The icon namespace is clean and extensible.
- **Color+Headroom extension**: Both `NSColor` and SwiftUI `Color` extensions live in the same file. Asset catalog + programmatic fallback is the established pattern.
- **AppDelegate display branch**: The existing code already has `if state == .disconnected` branch in `updateMenuBarDisplay()`. Adding an `if appState.isExtraUsageActive` branch follows the same pattern.
- **Test pattern**: Extend existing test files rather than creating new ones for property additions.

### Git Intelligence

Recent commits show consistent patterns:
- Story commits use `feat:` prefix with story reference
- No external dependencies added in recent stories
- Test counts explicitly tracked in completion notes
- Code review catches dead code and format inconsistencies

### Project Structure Notes

Modified files:
```
cc-hdrm/State/AppState.swift                    # ADD extra usage state + computed properties + update method + menuBarText branch
cc-hdrm/Services/PollingEngine.swift             # ADD updateExtraUsage() call in fetchUsageData() and handleCredentialError()
cc-hdrm/Views/GaugeIcon.swift                    # ADD makeExtraUsage() and makeExtraUsageNoLimit() factory methods
cc-hdrm/App/AppDelegate.swift                   # ADD extra usage branch in updateMenuBarDisplay()
cc-hdrm/Extensions/Color+Headroom.swift          # ADD NSColor.extraUsageColor(), Color statics, NSFont.extraUsageMenuBarFont()
```

New asset catalog entries (not Swift files -- directory/JSON only):
```
cc-hdrm/Resources/Assets.xcassets/ExtraUsageColors/ExtraUsageCool.colorset/
cc-hdrm/Resources/Assets.xcassets/ExtraUsageColors/ExtraUsageWarm.colorset/
cc-hdrm/Resources/Assets.xcassets/ExtraUsageColors/ExtraUsageHot.colorset/
cc-hdrm/Resources/Assets.xcassets/ExtraUsageColors/ExtraUsageCritical.colorset/
```

Test files to modify:
```
cc-hdrmTests/State/AppStateTests.swift           # ADD extra usage property tests
cc-hdrmTests/Views/GaugeIconTests.swift          # ADD extra usage gauge tests
```

After adding color sets, run `xcodegen generate` to regenerate the Xcode project.

### References

- [Source: _bmad-output/planning-artifacts/epics/epic-17-extra-usage-visibility-alerts-phase-5.md:36-87] - Story 17.1 acceptance criteria
- [Source: cc-hdrm/Models/UsageResponse.swift:30-43] - ExtraUsage struct definition
- [Source: cc-hdrm/Models/UsagePoll.swift:17-24] - Extra usage poll persistence fields
- [Source: cc-hdrm/State/AppState.swift:40-240] - Current AppState with all observable properties
- [Source: cc-hdrm/Views/GaugeIcon.swift:11-306] - GaugeIcon namespace with make(), makeDisconnected(), angle()
- [Source: cc-hdrm/Views/GaugeIcon.swift:113-117] - Headroom angle formula: theta = pi * (1 - p)
- [Source: cc-hdrm/Views/GaugeIcon.swift:177-194] - drawFillArc() implementation for reference
- [Source: cc-hdrm/App/AppDelegate.swift:310-399] - updateMenuBarDisplay() with gauge icon + accessibility rendering
- [Source: cc-hdrm/Extensions/Color+Headroom.swift:1-75] - NSColor/Color headroom color pattern
- [Source: cc-hdrm/Services/PollingEngine.swift:140-244] - fetchUsageData() where extra usage extraction goes
- [Source: cc-hdrm/Services/PollingEngine.swift:282-302] - handleCredentialError() where extra usage should be cleared
- [Source: cc-hdrm/Services/DatabaseManager.swift:240-243] - SQLite extra usage columns
- [Source: cc-hdrm/Services/HistoricalDataService.swift:76-79] - Extra usage extraction during persistence

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

No debug issues encountered.

### Implementation Plan

- Added 4 extra usage stored properties + 2 computed properties + 1 update method to AppState
- Added `menuBarExtraUsageText` computed property and modified `menuBarText` to check it first
- Wired PollingEngine to propagate `response.extraUsage` to AppState (called BEFORE `updateWindows()` per Pitfall 1)
- Cleared extra usage state in `handleCredentialError()`
- Created 4 asset catalog color sets (ExtraUsageCool/Warm/Hot/Critical) with light+dark variants
- Added `NSColor.extraUsageColor(for:)` with 4-tier ramp + programmatic fallback
- Added `NSFont.extraUsageMenuBarFont(for:)` with semibold/bold threshold at 0.75
- Added SwiftUI Color statics for extra usage colors
- Added `GaugeIcon.makeExtraUsage()` and `makeExtraUsageNoLimit()` with reversed needle geometry
- Added extra usage branch in `AppDelegate.updateMenuBarDisplay()` for icon, color, font, and VoiceOver
- Extended 3 existing test files with 20 new tests covering all acceptance criteria

### Completion Notes List

- All 11 tasks and subtasks implemented and verified
- 1077 total tests pass (20 new extra usage tests added)
- All 9 acceptance criteria satisfied
- No new Swift source files created — all changes in existing files + asset catalog entries
- PollingEngine calls `updateExtraUsage()` BEFORE `updateWindows()` to prevent transient UI flicker (Pitfall 1)
- Extra usage gauge uses reversed needle formula: `theta = pi * remainingFraction` (opposite of headroom)
- Fill arc sweeps from RIGHT toward LEFT (opposite of headroom)
- Color ramp: blue-teal → purple → magenta → deep red (distinct from headroom's green → yellow → orange → red)

### Change Log

- 2026-02-12: Story 17.1 implemented — Extra usage state propagation and menu bar indicator
- 2026-02-12: Code review fixes — negative balance formatting, degenerate fill arc, nil credits fallback, API error cleanup, transition logging, 3 new tests

### File List

Modified:
- cc-hdrm/State/AppState.swift
- cc-hdrm/Services/PollingEngine.swift
- cc-hdrm/Views/GaugeIcon.swift
- cc-hdrm/App/AppDelegate.swift
- cc-hdrm/Extensions/Color+Headroom.swift
- cc-hdrmTests/State/AppStateTests.swift
- cc-hdrmTests/Views/GaugeIconTests.swift
- cc-hdrmTests/Extensions/ColorHeadroomTests.swift
- _bmad-output/implementation-artifacts/sprint-status.yaml
- _bmad-output/planning-artifacts/epics/epic-list.md

Created:
- cc-hdrm/Resources/Assets.xcassets/ExtraUsageColors/Contents.json
- cc-hdrm/Resources/Assets.xcassets/ExtraUsageColors/ExtraUsageCool.colorset/Contents.json
- cc-hdrm/Resources/Assets.xcassets/ExtraUsageColors/ExtraUsageWarm.colorset/Contents.json
- cc-hdrm/Resources/Assets.xcassets/ExtraUsageColors/ExtraUsageHot.colorset/Contents.json
- cc-hdrm/Resources/Assets.xcassets/ExtraUsageColors/ExtraUsageCritical.colorset/Contents.json
