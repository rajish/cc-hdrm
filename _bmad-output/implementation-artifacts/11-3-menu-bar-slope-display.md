# Story 11.3: Menu Bar Slope Display (Escalation-Only)

Status: review

## Story

As a developer using Claude Code,
I want to see a slope arrow in the menu bar only when burn rate is actionable,
So that the compact footprint is preserved during calm periods.

## Acceptance Criteria

1. **Given** AppState.fiveHourSlope is .rising or .steep
   **And** connection status is normal (not disconnected/expired)
   **And** headroom is not exhausted
   **When** MenuBarTextRenderer renders
   **Then** it displays "XX% arrow-rising" or "XX% arrow-steep" (slope arrow appended)
   **And** the arrow uses the same color as the percentage

2. **Given** AppState.fiveHourSlope is .flat
   **When** MenuBarTextRenderer renders
   **Then** it displays "XX%" (no arrow) - same as Phase 1

3. **Given** headroom is exhausted (showing countdown)
   **When** MenuBarTextRenderer renders
   **Then** it displays "recycle-arrow Xm" (no slope arrow) - countdown takes precedence

4. **Given** 7d headroom is promoted to menu bar (tighter constraint)
   **When** MenuBarTextRenderer renders with slope
   **Then** it uses AppState.sevenDaySlope instead of fiveHourSlope for the arrow

5. **Given** a VoiceOver user focuses the menu bar with slope visible
   **When** VoiceOver reads the element
   **Then** it announces "cc-hdrm: Claude headroom [X] percent, [state], [slope]" (e.g., "rising")

## Tasks / Subtasks

- [x] Task 1: Extend AppState.menuBarText to include slope arrow (AC: 1, 2, 3)
  - [x] 1.1 In `cc-hdrm/State/AppState.swift`, modify `menuBarText` computed property
  - [x] 1.2 After calculating headroom percentage, check if slope is actionable
  - [x] 1.3 If `displayedSlope.isActionable` is true AND not exhausted, append slope arrow
  - [x] 1.4 Ensure disconnected state returns em dash only (no slope)
  - [x] 1.5 Ensure exhausted state returns countdown only (no slope)

- [x] Task 2: Add displayedSlope computed property to AppState (AC: 4)
  - [x] 2.1 Add `displayedSlope: SlopeLevel` computed property that returns the slope for the currently displayed window
  - [x] 2.2 If `displayedWindow == .fiveHour`, return `fiveHourSlope`
  - [x] 2.3 If `displayedWindow == .sevenDay`, return `sevenDaySlope`

- [x] Task 3: Update accessibility announcements (AC: 5)
  - [x] 3.1 In `cc-hdrm/App/AppDelegate.swift`, modify `updateMenuBarDisplay()` accessibility logic
  - [x] 3.2 When slope is actionable, append slope level to accessibility value
  - [x] 3.3 Format: "cc-hdrm: Claude headroom X percent, [state], [slope]"
  - [x] 3.4 When slope is .flat, omit slope from announcement (same as Phase 1)

- [x] Task 4: Write unit tests for menu bar slope display (AC: 1, 2, 3, 4, 5)
  - [x] 4.1 Add new test suite to `cc-hdrmTests/State/AppStateTests.swift` (or create `AppStateSlopeTests.swift`)
  - [x] 4.2 Test menuBarText includes arrow when fiveHourSlope is .rising
  - [x] 4.3 Test menuBarText includes arrow when fiveHourSlope is .steep
  - [x] 4.4 Test menuBarText excludes arrow when fiveHourSlope is .flat
  - [x] 4.5 Test menuBarText excludes arrow when exhausted (countdown mode)
  - [x] 4.6 Test menuBarText excludes arrow when disconnected
  - [x] 4.7 Test displayedSlope returns sevenDaySlope when 7d is promoted
  - [x] 4.8 Test menuBarText uses sevenDaySlope arrow when 7d is promoted
  - [x] 4.9 Test menuBarText shows no arrow when slope has not been set (default .flat)
  - [x] 4.10 Test menuBarText excludes arrow when 7d is promoted AND exhausted (shows countdown)
  - [x] 4.11 If creating new test file, run `xcodegen generate` to add it to project

- [x] Task 5: Verify integration with existing display logic
  - [x] 5.1 Ensure gauge icon rendering is unaffected (already done in recent commit)
  - [x] 5.2 Verify color/weight from HeadroomState still applies correctly
  - [x] 5.3 Run all 49 existing menu bar tests to confirm no regressions (they don't call updateSlopes, so slope defaults to .flat)
  - [x] 5.4 Run full test suite (currently 494 tests)

## Dev Notes

### CRITICAL: Slope is Escalation-Only in Menu Bar

Per UX spec, the slope arrow appears in the menu bar **only** when `.rising` or `.steep`. At `.flat`, the arrow is hidden to preserve the compact footprint. The `SlopeLevel.isActionable` property (from Story 11.2) already encodes this logic.

### CRITICAL: Observation Tracking

AppState is marked `@Observable`, so accessing `fiveHourSlope` or `sevenDaySlope` through the new `displayedSlope` computed property will automatically register for observation via `withObservationTracking`. When `PollingEngine` calls `appState.updateSlopes()`, the menu bar will re-render automatically. No additional observation setup is required.

### CRITICAL: Existing Test Compatibility

There are **49 existing tests** in `AppStateTests.swift` that check exact `menuBarText` values (e.g., `"83%"`, `"35%"`). These tests do NOT call `updateSlopes()`, so slope will remain at its default value (`.flat`). Since `.flat.isActionable == false`, no arrow will be appended and all existing tests will continue to pass without modification. **Verify this by running the test suite after implementation.**

### Architecture Context

This story modifies the existing menu bar display path established in Phase 1. The data flow:

```text
PollingEngine -> AppState.updateSlopes() -> fiveHourSlope/sevenDaySlope
                                                     |
                                                     v
                                          AppState.displayedSlope (new)
                                                     |
                                                     v
                                          AppState.menuBarText (modified)
                                                     |
                                                     v
                                          AppDelegate.updateMenuBarDisplay()
                                                     |
                                                     v
                                          NSStatusItem.button.attributedTitle
```

### Implementation: AppState.menuBarText Modification

Current implementation (cc-hdrm/State/AppState.swift:104-119):

```swift
var menuBarText: String {
    if menuBarHeadroomState == .disconnected {
        return "\u{2014}" // em dash only
    }

    let window: WindowState? = displayedWindow == .fiveHour ? fiveHour : sevenDay

    if let window, window.headroomState == .exhausted, let resetsAt = window.resetsAt {
        _ = countdownTick
        return "\u{21BB} \(resetsAt.countdownString())" // recycle Xm
    }

    let headroom = max(0, Int(100.0 - (window?.utilization ?? 0)))
    return "\(headroom)%"
}
```

**Modification required** - add slope arrow after percentage when actionable:

```swift
var menuBarText: String {
    if menuBarHeadroomState == .disconnected {
        return "\u{2014}" // em dash only
    }

    let window: WindowState? = displayedWindow == .fiveHour ? fiveHour : sevenDay

    if let window, window.headroomState == .exhausted, let resetsAt = window.resetsAt {
        _ = countdownTick
        return "\u{21BB} \(resetsAt.countdownString())" // recycle Xm - NO slope arrow
    }

    let headroom = max(0, Int(100.0 - (window?.utilization ?? 0)))
    let slope = displayedSlope
    
    // Append slope arrow only when actionable (rising/steep)
    if slope.isActionable {
        return "\(headroom)% \(slope.arrow)"
    }
    return "\(headroom)%"
}

/// The slope level for the currently displayed window.
var displayedSlope: SlopeLevel {
    switch displayedWindow {
    case .fiveHour:
        return fiveHourSlope
    case .sevenDay:
        return sevenDaySlope
    }
}
```

### Unicode Characters for Slope Arrows

From SlopeLevel.swift (already implemented in 11.1):
- `.flat` -> "arrow-right" (U+2192)
- `.rising` -> "arrow-upper-right" (U+2197)
- `.steep` -> "arrow-up" (U+2B06)

### Color Handling (AC#1: Arrow Uses Same Color as Percentage)

The slope arrow automatically uses the same color as the percentage because `AppDelegate.updateMenuBarDisplay()` applies color via `NSAttributedString` to the **entire** `menuBarText` string. The existing code at line 275-279:

```swift
let color = NSColor.headroomColor(for: state)
let font = NSFont.menuBarFont(for: state)
let attributes: [NSAttributedString.Key: Any] = [
    .foregroundColor: color,
    .font: font
]
statusItem?.button?.attributedTitle = NSAttributedString(string: text, attributes: attributes)
```

This means both "78%" and the appended arrow will share the same `NSColor.headroomColor(for:)`. **No additional implementation is required for color consistency.**

### Accessibility Update in AppDelegate

Current accessibility logic (cc-hdrm/App/AppDelegate.swift:281-297):

```swift
let accessibilityValue: String
if state == .disconnected {
    accessibilityValue = "cc-hdrm: Claude headroom disconnected"
} else if state == .exhausted {
    // ... countdown announcement
} else {
    let headroom = max(0, Int(100.0 - (window?.utilization ?? 0)))
    accessibilityValue = "cc-hdrm: Claude headroom \(headroom) percent, \(state.rawValue)"
}
```

**Modification required** - append slope when actionable:

```swift
} else {
    let headroom = max(0, Int(100.0 - (window?.utilization ?? 0)))
    let slope = appState.displayedSlope
    if slope.isActionable {
        accessibilityValue = "cc-hdrm: Claude headroom \(headroom) percent, \(state.rawValue), \(slope.accessibilityLabel)"
    } else {
        accessibilityValue = "cc-hdrm: Claude headroom \(headroom) percent, \(state.rawValue)"
    }
}
```

### Menu Bar Display Width Considerations

From UX spec, expected widths with slope:

| State                    | Menu Bar Display | Width     |
| ------------------------ | ---------------- | --------- |
| Normal, Flat             | `83%`            | ~4 chars  |
| Normal, Rising           | `78% arrow-rising`        | ~6 chars  |
| Normal, Steep            | `65% arrow-steep`        | ~6 chars  |
| Exhausted                | `recycle 12m`        | ~5 chars  |
| Disconnected             | `em-dash`            | ~1 char   |

Note: The gauge icon is now separate (commit 75f93a5), so text width is independent of icon.

### Previous Story Intelligence

**From Story 11.1:**
- SlopeLevel enum with 3 cases (flat/rising/steep - NO cooling level)
- Ring buffer with 15-min window, requires 10+ min for valid calculation
- AppState.fiveHourSlope and sevenDaySlope properties already exist
- AppState.updateSlopes() method already exists

**From Story 11.2:**
- SlopeLevel.isActionable property: false for .flat, true for .rising/.steep
- SlopeLevel.arrow property: unicode arrow character for each level
- SlopeLevel.accessibilityLabel property: "flat", "rising", "steep"
- SlopeLevel.color(for:) and nsColor(for:) methods for styling

### Project Structure Notes

**Files to modify:**
```text
cc-hdrm/State/AppState.swift
  - Add displayedSlope computed property (after line 99)
  - Modify menuBarText computed property (lines 104-119)

cc-hdrm/App/AppDelegate.swift
  - Modify updateMenuBarDisplay() accessibility logic (lines 281-297)
```

**Test file options (choose one):**
```text
Option A: Extend existing file
  cc-hdrmTests/State/AppStateTests.swift
  - Add new @Suite("AppState Menu Bar Slope Display") section

Option B: Create new file (recommended for clarity)
  cc-hdrmTests/State/AppStateSlopeTests.swift
  - If creating new file, run: xcodegen generate
```

**XcodeGen reminder:** Per AGENTS.md, if you create any new Swift files, run `xcodegen generate` to regenerate the Xcode project with auto-discovery.

### Testing Strategy

**Unit tests for AppState.menuBarText:**

```swift
@Suite("AppState Menu Bar Slope Display")
struct AppStateMenuBarSlopeTests {
    
    @Test("menuBarText includes rising arrow when slope is rising")
    @MainActor
    func menuBarTextIncludesRisingArrow() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 22.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateSlopes(fiveHour: .rising, sevenDay: .flat)
        
        #expect(appState.menuBarText == "78% \u{2197}")  // arrow-upper-right
    }
    
    @Test("menuBarText includes steep arrow when slope is steep")
    @MainActor
    func menuBarTextIncludesSteepArrow() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 35.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateSlopes(fiveHour: .steep, sevenDay: .flat)
        
        #expect(appState.menuBarText == "65% \u{2B06}")  // arrow-up
    }
    
    @Test("menuBarText excludes arrow when slope is flat")
    @MainActor
    func menuBarTextExcludesArrowWhenFlat() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 17.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .flat)
        
        #expect(appState.menuBarText == "83%")  // No arrow
    }
    
    @Test("menuBarText excludes arrow when exhausted")
    @MainActor
    func menuBarTextExcludesArrowWhenExhausted() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        let resetsAt = Date().addingTimeInterval(720)  // 12 minutes
        appState.updateWindows(
            fiveHour: WindowState(utilization: 100.0, resetsAt: resetsAt),
            sevenDay: nil
        )
        appState.updateSlopes(fiveHour: .steep, sevenDay: .flat)
        
        #expect(appState.menuBarText.hasPrefix("\u{21BB}"))  // Countdown, no slope
        #expect(!appState.menuBarText.contains("\u{2B06}"))  // No steep arrow
    }
    
    @Test("displayedSlope returns sevenDaySlope when 7d is promoted")
    @MainActor
    func displayedSlopeReturnsSevenDaySlopeWhenPromoted() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 88.0, resetsAt: Date().addingTimeInterval(86400))  // 12% headroom, warning
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .rising)
        
        // 7d is promoted (lower headroom AND in warning state)
        #expect(appState.displayedWindow == .sevenDay)
        #expect(appState.displayedSlope == .rising)
        #expect(appState.menuBarText == "12% \u{2197}")  // Uses 7d slope arrow
    }
    
    @Test("menuBarText shows no arrow when slope not set (default .flat)")
    @MainActor
    func menuBarTextDefaultSlopeNoArrow() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 17.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        // NOTE: updateSlopes() not called - slope remains default .flat
        
        #expect(appState.fiveHourSlope == .flat)  // Verify default
        #expect(appState.menuBarText == "83%")    // No arrow
    }
    
    @Test("7d exhausted does not promote - stays on 5h with no slope arrow")
    @MainActor
    func sevenDayExhaustedDoesNotPromote() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        let resetsAt7d = Date().addingTimeInterval(2 * 3600 + 13 * 60)  // 2h 13m
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 100.0, resetsAt: resetsAt7d)  // 0% headroom, exhausted
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .steep)
        
        // 7d exhausted is NOT promoted (displayedWindow requires warning/critical, not exhausted)
        // So 5h is displayed with 80% headroom and no slope arrow (fiveHourSlope is .flat)
        #expect(appState.displayedWindow == .fiveHour)
        #expect(appState.menuBarText == "80%")  // 5h headroom, no arrow (flat)
    }
}
```

### Manual Integration Test

After implementation, perform this manual verification:

1. **Launch app fresh** - verify menu bar shows percentage only (no arrow) since slope data needs 10+ minutes to calculate
2. **Wait 10+ minutes** with active Claude usage - verify slope arrow appears when burn rate increases
3. **Verify color consistency** - arrow should match percentage color in all headroom states
4. **Test VoiceOver** - focus menu bar item and verify announcement includes slope level when arrow is visible

### Edge Cases to Handle

| # | Condition | Expected Behavior | Menu Bar Output |
|---|-----------|-------------------|-----------------|
| 1 | Disconnected (any reason) | Em dash only, no slope | `—` |
| 2 | Token expired | Maps to disconnected | `—` |
| 3 | No credentials | Maps to disconnected | `—` |
| 4 | 5h exhausted with resetsAt | Countdown only, no slope | `↻ 47m` |
| 5 | 5h exhausted, no resetsAt | Percentage only (0%), no slope | `0%` |
| 6 | 5h normal, slope .flat | Percentage only | `83%` |
| 7 | 5h normal, slope .rising | Percentage + arrow | `78% ↗` |
| 8 | 5h normal, slope .steep | Percentage + arrow | `65% ⬆` |
| 9 | 7d promoted (warning), slope .rising | 7d percentage + 7d slope arrow | `12% ↗` |
| 10 | 7d exhausted (NOT promoted) | Stays on 5h (exhausted ≠ warning/critical) | `80%` (5h headroom) |
| 11 | Insufficient slope data (<10 min) | SlopeCalculationService returns .flat | `83%` (no arrow) |
| 12 | App just launched (default state) | Slope defaults to .flat | `XX%` (no arrow) |

**Key principle:** Countdown always takes precedence over slope display. If the displayed window is exhausted, show countdown without slope arrow.

### References

- [Source: cc-hdrm/State/AppState.swift:48-49] - Slope properties (fiveHourSlope, sevenDaySlope)
- [Source: cc-hdrm/State/AppState.swift:70-85] - displayedWindow computed property
- [Source: cc-hdrm/State/AppState.swift:104-119] - menuBarText computed property
- [Source: cc-hdrm/App/AppDelegate.swift:253-325] - updateMenuBarDisplay() method
- [Source: cc-hdrm/Models/SlopeLevel.swift] - SlopeLevel enum with arrow, isActionable, accessibilityLabel
- [Source: _bmad-output/planning-artifacts/ux-design-specification-phase3.md:78-91] - Menu bar display rules
- [Source: _bmad-output/planning-artifacts/epics.md:1203-1232] - Story 11.3 acceptance criteria
- [Source: _bmad-output/implementation-artifacts/11-1-slope-calculation-service-ring-buffer.md] - Story 11.1 context
- [Source: _bmad-output/implementation-artifacts/11-2-slope-level-calculation-mapping.md] - Story 11.2 context

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

None required.

### Completion Notes List

- Added `displayedSlope` computed property to AppState that returns the slope for the currently displayed window (fiveHourSlope or sevenDaySlope based on displayedWindow)
- Modified `menuBarText` to append slope arrow when `slope.isActionable && window?.headroomState != .exhausted`
- Updated AppDelegate `updateMenuBarDisplay()` accessibility logic to include slope level in VoiceOver announcements when actionable
- Created new test file `AppStateSlopeTests.swift` with 13 comprehensive tests covering all acceptance criteria
- Ran `xcodegen generate` to add new test file to project
- All 45 existing AppState tests pass (slope defaults to .flat, no arrow appended - backward compatible)
- Note: Task 4.10 test expectation adjusted - 7d exhausted does NOT promote (exhausted is not warning/critical per displayedWindow logic); test now verifies 5h remains displayed with no slope arrow

### Code Review Fixes (2026-02-04)

- **HIGH FIX:** Added 4 accessibility tests to `AppDelegateTests.swift` verifying AC #5 (slope in VoiceOver):
  - `accessibility includes slope when rising (AC #5)`
  - `accessibility includes slope when steep (AC #5)`
  - `accessibility excludes slope when flat (AC #5)`
  - `accessibility excludes slope when exhausted even with actionable slope (AC #5)`
- **MEDIUM FIX:** Strengthened edge case test in `AppStateSlopeTests.swift` to explicitly verify no arrow present when exhausted without resetsAt
- Full test suite: **521 tests pass** with 0 failures

### File List

**Modified:**
- cc-hdrm/State/AppState.swift - Added displayedSlope computed property, modified menuBarText to include slope arrow
- cc-hdrm/App/AppDelegate.swift - Updated accessibility logic to include slope in VoiceOver announcements
- cc-hdrmTests/App/AppDelegateTests.swift - Added 4 accessibility tests for slope in VoiceOver (code review fix)
- cc-hdrmTests/State/AppStateSlopeTests.swift - Strengthened edge case test (code review fix)

**Created:**
- cc-hdrmTests/State/AppStateSlopeTests.swift - New test suite with 13 tests for slope display

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2026-02-04 | Story 11.3 implementation complete - menu bar slope display with escalation-only arrows | Dev Agent (claude-opus-4-5) |
| 2026-02-04 | Code review fixes: added 4 accessibility tests for AC #5, strengthened edge case test (521 tests pass) | Code Review (claude-opus-4-5) |
