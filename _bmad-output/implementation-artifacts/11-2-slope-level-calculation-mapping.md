# Story 11.2: Slope Level Calculation & Mapping

Status: done

## Story

As a developer using Claude Code,
I want burn rate mapped to discrete slope levels with appropriate visual styling,
So that the display is simple, actionable, and visually consistent with the headroom state.

## Acceptance Criteria

1. **Given** the ring buffer contains 10+ minutes of poll data for a window
   **When** calculateSlope(for: .fiveHour) is called
   **Then** it computes the average rate of change (% per minute) across the buffer
   **And** maps the rate to SlopeLevel (3 levels only - no Cooling because utilization cannot decrease):
   - Rate < 0.3% per min -> .flat (arrow: ->)
   - Rate 0.3 to 1.5% per min -> .rising (arrow: north-east)
   - Rate > 1.5% per min -> .steep (arrow: up)

2. **Given** slope is calculated for both windows
   **When** the calculation completes
   **Then** AppState.fiveHourSlope and AppState.sevenDaySlope are updated
   **And** updates happen on @MainActor to ensure UI consistency

3. **Given** the SlopeLevel enum is defined
   **When** referenced across the codebase
   **Then** it includes properties: arrow (String), color (Color), accessibilityLabel (String)
   **And** .flat uses secondary color; .rising and .steep use headroom color

## Tasks / Subtasks

- [x] Task 1: Add color method to SlopeLevel enum (AC: #3)
  - [x] 1.1 Add `import SwiftUI` to `cc-hdrm/Models/SlopeLevel.swift`
  - [x] 1.2 Add `color(for headroomState: HeadroomState) -> Color` method
  - [x] 1.3 Implement logic: `.flat` returns `.secondary`, `.rising`/`.steep` return headroom state's color
  - [x] 1.4 Add `isActionable` computed property (true for `.rising`/`.steep`, false for `.flat`) for menu bar display

- [x] Task 2: Add NSColor variant for menu bar rendering (AC: #3)
  - [x] 2.1 Add `nsColor(for headroomState: HeadroomState) -> NSColor` method for AppKit compatibility
  - [x] 2.2 Implementation mirrors SwiftUI color logic

- [x] Task 3: Verify @MainActor compliance (AC: #2)
  - [x] 3.1 Review PollingEngine.fetchUsageData() slope integration (lines 166-180)
  - [x] 3.2 Confirm AppState.updateSlopes() is called within @MainActor context
  - [x] 3.3 Add debug logging if needed to verify main thread execution

- [x] Task 4: Write unit tests for color method (AC: #3)
  - [x] 4.1 Extend `cc-hdrmTests/Models/SlopeLevelTests.swift`
  - [x] 4.2 Test `.flat` returns secondary color for all headroom states
  - [x] 4.3 Test `.rising` returns headroom state color for each HeadroomState case
  - [x] 4.4 Test `.steep` returns headroom state color for each HeadroomState case
  - [x] 4.5 Test `isActionable` property for all slope levels

- [x] Task 5: Validate slope calculation thresholds (AC: #1)
  - [x] 5.1 Review existing SlopeCalculationService thresholds (lines 46-49)
  - [x] 5.2 Confirm thresholds match AC: <0.3 flat, 0.3-1.5 rising, >1.5 steep
  - [x] 5.3 Verify negative rates (reset edge case) map to .flat
  - [x] 5.4 Run existing tests to confirm all pass

## Dev Notes

### CRITICAL: Color is Context-Dependent

The SlopeLevel `color` cannot be a static property because `.rising` and `.steep` must inherit the current headroom state's color. This creates visual coherence - when headroom is critical (red), a steep burn rate arrow is also red, reinforcing urgency.

```swift
// cc-hdrm/Models/SlopeLevel.swift
import SwiftUI

enum SlopeLevel: String, Sendable, Equatable, CaseIterable {
    case flat
    case rising
    case steep
    
    // Existing properties...
    var arrow: String { ... }
    var accessibilityLabel: String { ... }
    
    // NEW: Color method (context-dependent)
    /// Returns the display color for this slope level.
    /// - Parameter headroomState: The current headroom state for color inheritance.
    /// - Returns: `.secondary` for flat; headroom color for rising/steep.
    func color(for headroomState: HeadroomState) -> Color {
        switch self {
        case .flat:
            return .secondary
        case .rising, .steep:
            // Use the headroom state's color token from Asset Catalog
            return Color("HeadroomColors/\(headroomState.colorTokenName)", bundle: .main)
        }
    }
    
    // NEW: Actionability flag for menu bar display
    /// Whether this slope level should trigger menu bar display.
    /// Per UX spec: only rising and steep are shown in menu bar.
    var isActionable: Bool {
        switch self {
        case .flat:
            return false
        case .rising, .steep:
            return true
        }
    }
}
```

### NSColor Variant for Menu Bar

The menu bar uses AppKit's NSAttributedString, so we need an NSColor variant:

```swift
// Add to SlopeLevel.swift or Color+Headroom.swift
import AppKit

extension SlopeLevel {
    /// Returns NSColor for AppKit compatibility (menu bar rendering).
    func nsColor(for headroomState: HeadroomState) -> NSColor {
        switch self {
        case .flat:
            return .secondaryLabelColor
        case .rising, .steep:
            return NSColor.headroomColor(for: headroomState)
        }
    }
}
```

### Architecture Context

This story completes the slope display preparation. The data flow established in 11.1:

```text
PollingEngine (line 176-180) -> slopeService.addPoll()
                             -> slopeService.calculateSlope() 
                             -> appState.updateSlopes()
```

This story adds the visual styling layer. Stories 11.3 and 11.4 will consume these properties:
- 11.3: Menu bar displays slope arrow only when `isActionable == true`
- 11.4: Popover always displays slope arrow with `color(for:)`

### @MainActor Compliance Verification

PollingEngine is marked `@MainActor` (line 7-8 of PollingEngine.swift):

```swift
@MainActor
final class PollingEngine: PollingEngineProtocol { ... }
```

All methods including `fetchUsageData()` execute on the main actor. The call to `appState.updateSlopes()` at line 180 is therefore safely on @MainActor, matching AC #2.

### Threshold Calibration

Current thresholds in SlopeCalculationService (lines 46-49):
- `flatThreshold: Double = 0.3` (% per minute)
- `steepThreshold: Double = 1.5` (% per minute)

These match the AC exactly. No changes needed.

### Previous Story Intelligence (11.1)

From Story 11.1 completion notes:
- SlopeLevel enum implemented with 3 cases (no cooling)
- Ring buffer uses 15-minute window with time-based eviction
- Minimum 10 minutes / 20 entries required for valid calculation
- Negative rates (reset edge case) treated as flat
- All 479 tests pass including 28 slope-related tests

### Project Structure Notes

**Modified files:**
```text
cc-hdrm/Models/SlopeLevel.swift              # Add color(for:), isActionable, nsColor(for:)
cc-hdrmTests/Models/SlopeLevelTests.swift    # Add color and isActionable tests
```

No new files required. This story extends the existing SlopeLevel implementation from 11.1.

### Testing Strategy

Extend existing SlopeLevelTests.swift:

```swift
@Suite("SlopeLevel Color Tests")
struct SlopeLevelColorTests {
    
    @Test("flat always returns secondary color")
    func flatColorIsSecondary() {
        for state in HeadroomState.allCases {
            let color = SlopeLevel.flat.color(for: state)
            #expect(color == .secondary)
        }
    }
    
    @Test("rising returns headroom state color")
    func risingColorMatchesHeadroomState() {
        // Test with each HeadroomState
        let normalColor = SlopeLevel.rising.color(for: .normal)
        let criticalColor = SlopeLevel.rising.color(for: .critical)
        #expect(normalColor != criticalColor)
    }
    
    @Test("steep returns headroom state color")
    func steepColorMatchesHeadroomState() {
        let normalColor = SlopeLevel.steep.color(for: .normal)
        let criticalColor = SlopeLevel.steep.color(for: .critical)
        #expect(normalColor != criticalColor)
    }
    
    @Test("isActionable is false for flat")
    func flatNotActionable() {
        #expect(SlopeLevel.flat.isActionable == false)
    }
    
    @Test("isActionable is true for rising and steep")
    func risingAndSteepAreActionable() {
        #expect(SlopeLevel.rising.isActionable == true)
        #expect(SlopeLevel.steep.isActionable == true)
    }
}
```

### UX Design Reference

From UX Design Specification Phase 3 (lines 78-91):
- Menu bar shows slope only for Rising and Steep (escalation-only)
- Flat/Cooling hidden in menu bar to preserve compact footprint
- Popover always shows slope for both gauges
- "Slope is never color-only - the arrow shape conveys meaning independently"

### References

- [Source: cc-hdrm/Models/SlopeLevel.swift:1-28] - Current SlopeLevel implementation
- [Source: cc-hdrm/Models/HeadroomState.swift:39-48] - colorTokenName property
- [Source: cc-hdrm/Extensions/Color+Headroom.swift:59-66] - SwiftUI Color mapping
- [Source: cc-hdrm/Extensions/Color+Headroom.swift:6-37] - NSColor mapping
- [Source: cc-hdrm/Services/PollingEngine.swift:7-8] - @MainActor declaration
- [Source: cc-hdrm/Services/PollingEngine.swift:166-180] - Slope integration point
- [Source: cc-hdrm/Services/SlopeCalculationService.swift:46-49] - Threshold constants
- [Source: _bmad-output/planning-artifacts/ux-design-specification-phase3.md:78-91] - Menu bar display rules
- [Source: _bmad-output/planning-artifacts/epics.md:1177-1202] - Story 11.2 acceptance criteria
- [Source: _bmad-output/implementation-artifacts/11-1-slope-calculation-service-ring-buffer.md] - Previous story context

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

N/A - No debug logging added; @MainActor compliance verified via static analysis.

### Completion Notes List

- Added `import AppKit` and `import SwiftUI` to SlopeLevel.swift
- Implemented `color(for headroomState:) -> Color` method returning `.secondary` for flat, headroom color for rising/steep
- Implemented `nsColor(for headroomState:) -> NSColor` method mirroring SwiftUI logic
- Added `isActionable` computed property (false for flat, true for rising/steep)
- Verified @MainActor compliance: PollingEngine (line 7-8) is @MainActor, appState.updateSlopes() at line 180 executes within this context
- Confirmed slope thresholds match AC exactly: flatThreshold=0.3, steepThreshold=1.5
- Added 15 new tests: 10 color tests (SwiftUI + NSColor), 5 actionability tests
- All 494 tests pass (including 24 SlopeLevel tests)

**Code Review Fixes (2026-02-04):**
- Added `Color.headroomColor(for:)` static method to Color+Headroom.swift for API parity with NSColor
- Refactored `SlopeLevel.color(for:)` to use `Color.headroomColor(for:)` instead of inline path construction
- Enhanced documentation for `SlopeLevel.color(for:)` explaining color inheritance behavior
- Strengthened SwiftUI color tests with proper equality assertions matching NSColor test pattern
- All 494 tests pass

### File List

**Modified:**
- cc-hdrm/Models/SlopeLevel.swift
- cc-hdrm/Extensions/Color+Headroom.swift
- cc-hdrmTests/Models/SlopeLevelTests.swift

### Change Log

- 2026-02-04: Story 11.2 implemented. Added color(for:), nsColor(for:), and isActionable to SlopeLevel enum. 15 new tests added. All 494 tests pass.
- 2026-02-04: Code review fixes applied. Added Color.headroomColor(for:) method to Color+Headroom.swift for consistency with NSColor. Updated SlopeLevel.color(for:) to use new method. Improved SwiftUI color tests with proper equality assertions. All 494 tests pass.
