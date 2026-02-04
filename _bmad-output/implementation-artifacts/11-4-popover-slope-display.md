# Story 11.4: Popover Slope Display (Always Visible)

Status: done

## Story

As a developer using Claude Code,
I want to see slope indicators on both gauges in the popover,
So that I have full visibility into burn rate for both windows.

## Acceptance Criteria

1. **Given** the popover is open
   **When** FiveHourGaugeSection renders for 5h window
   **Then** a SlopeIndicator appears inside the ring, below the percentage text
   **And** the slope level matches AppState.fiveHourSlope
   **And** all three levels are visible in the popover (flat, rising, steep)

2. **Given** the popover is open
   **When** SevenDayGaugeSection renders for 7d window
   **Then** a SlopeIndicator appears with AppState.sevenDaySlope
   **And** display is consistent with the 5h gauge

3. **Given** slope data is insufficient (< 10 minutes of history)
   **When** the popover renders
   **Then** slope displays as flat arrow as the default

4. **Given** a VoiceOver user focuses a gauge
   **When** VoiceOver reads the element
   **Then** it announces slope as part of the gauge reading: "[window] headroom: [X] percent, [slope level], resets in..."

## Tasks / Subtasks

- [x] Task 1: Create SlopeIndicator component (AC: 1, 2)
  - [x] 1.1 Create `cc-hdrm/Views/SlopeIndicator.swift`
  - [x] 1.2 Accept `SlopeLevel` and `HeadroomState` parameters
  - [x] 1.3 Display the arrow character from `SlopeLevel.arrow`
  - [x] 1.4 Apply color from `SlopeLevel.color(for: headroomState)`
  - [x] 1.5 Use `.caption` font size for consistency with gauge labels
  - [x] 1.6 Add `.accessibilityHidden(true)` since parent gauge handles accessibility
  - [x] 1.7 Add `#Preview` for visual iteration
  - [x] 1.8 Run `xcodegen generate` to add new file to project

- [x] Task 2: Add slope display to HeadroomRingGauge (AC: 1, 2)
  - [x] 2.1 Add `slopeLevel: SlopeLevel? = nil` optional parameter with default
  - [x] 2.2 Wrap center content in VStack with `spacing: 0`
  - [x] 2.3 Display SlopeIndicator below percentage text when slope is provided
  - [x] 2.4 Pass existing computed `headroomState` to SlopeIndicator for color context
  - [x] 2.5 Hide slope indicator when `headroomPercentage` is nil (disconnected state)

- [x] Task 3: Integrate slope into FiveHourGaugeSection (AC: 1, 3)
  - [x] 3.1 Pass `appState.fiveHourSlope` to HeadroomRingGauge's new `slopeLevel` parameter

- [x] Task 4: Integrate slope into SevenDayGaugeSection (AC: 2, 3)
  - [x] 4.1 Pass `appState.sevenDaySlope` to HeadroomRingGauge's new `slopeLevel` parameter

- [x] Task 5: Update accessibility announcements (AC: 4)
  - [x] 5.1 Modify FiveHourGaugeSection's `combinedAccessibilityLabel` to include slope level
  - [x] 5.2 Modify SevenDayGaugeSection's `combinedAccessibilityLabel` to include slope level
  - [x] 5.3 Format: "5-hour headroom: X percent, [slope level], resets in..."

- [x] Task 6: Write unit tests
  - [x] 6.1 Create `cc-hdrmTests/Views/SlopeIndicatorTests.swift`
  - [x] 6.2 Test SlopeLevel.arrow returns correct Unicode for each level
  - [x] 6.3 Test SlopeLevel.color(for:) returns .secondary for flat, headroom color for rising/steep
  - [x] 6.4 Test accessibility labels include slope in FiveHourGaugeSection (create AppState, set slope, verify label string contains slope)
  - [x] 6.5 Test accessibility labels include slope in SevenDayGaugeSection
  - [x] 6.6 Run `xcodegen generate` if creating new test file

- [x] Task 7: Build verification and regression check
  - [x] 7.1 Run `xcodebuild -scheme cc-hdrm -destination 'platform=macOS' build`
  - [x] 7.2 Run full test suite (currently 521+ tests)
  - [x] 7.3 Manually verify popover displays slope arrows for both gauges

## Dev Notes

### CRITICAL: Slope is Always Visible in Popover (When Connected)

Unlike the menu bar (which only shows slope for rising/steep), the popover **always** displays the slope indicator for both gauges when connected. This includes showing the flat arrow when slope is .flat.

**Exception:** When disconnected (headroomPercentage is nil), the slope indicator is hidden. Showing a slope arrow when there's no usage data is misleading.

### CRITICAL: This Story Creates SlopeIndicator

Story 11.5 in the epics file is titled "SlopeIndicator Component" but describes making it reusable. **This story (11.4) creates the initial SlopeIndicator.** Story 11.5 should be considered satisfied by this implementation or re-scoped to any additional enhancements. The dev agent should mark 11.5 as done or cancelled after completing 11.4.

### CRITICAL: Accessibility - Avoid Double Announcements

SlopeIndicator uses `.accessibilityHidden(true)` because the parent gauge sections use `.accessibilityElement(children: .ignore)` with a combined label. The slope is announced via the gauge's `combinedAccessibilityLabel`, NOT via SlopeIndicator's own accessibility. This prevents VoiceOver from reading the slope twice.

### Implementation: SlopeIndicator Component

```swift
// cc-hdrm/Views/SlopeIndicator.swift
import SwiftUI

/// Displays a slope level arrow with appropriate styling.
/// Used in popover gauges to show burn rate.
/// Note: Uses accessibilityHidden since parent gauge handles accessibility.
struct SlopeIndicator: View {
    let slopeLevel: SlopeLevel
    let headroomState: HeadroomState
    
    var body: some View {
        Text(slopeLevel.arrow)
            .font(.caption)
            .foregroundStyle(slopeLevel.color(for: headroomState))
            .accessibilityHidden(true)  // Parent gauge provides combined label
    }
}

#Preview("Flat - Normal") {
    SlopeIndicator(slopeLevel: .flat, headroomState: .normal)
}

#Preview("Rising - Warning") {
    SlopeIndicator(slopeLevel: .rising, headroomState: .warning)
}

#Preview("Steep - Critical") {
    SlopeIndicator(slopeLevel: .steep, headroomState: .critical)
}
```

### Implementation: HeadroomRingGauge Modification (Complete)

```swift
// cc-hdrm/Views/HeadroomRingGauge.swift
import SwiftUI

struct HeadroomRingGauge: View {
    let headroomPercentage: Double?
    let windowLabel: String
    let ringSize: CGFloat
    let strokeWidth: CGFloat
    let slopeLevel: SlopeLevel?  // NEW: Optional slope, defaults to nil
    
    // Default initializer for backward compatibility
    init(
        headroomPercentage: Double?,
        windowLabel: String,
        ringSize: CGFloat,
        strokeWidth: CGFloat,
        slopeLevel: SlopeLevel? = nil  // Default nil preserves existing behavior
    ) {
        self.headroomPercentage = headroomPercentage
        self.windowLabel = windowLabel
        self.ringSize = ringSize
        self.strokeWidth = strokeWidth
        self.slopeLevel = slopeLevel
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var headroomState: HeadroomState {
        guard let headroomPercentage else { return .disconnected }
        return HeadroomState(from: 100.0 - headroomPercentage)
    }

    private var fillAmount: CGFloat {
        max(0, (headroomPercentage ?? 0)) / 100.0
    }

    private var fillColor: Color {
        headroomState.swiftUIColor
    }

    private var centerText: String {
        guard let headroomPercentage else { return "\u{2014}" }
        return "\(Int(max(0, headroomPercentage)))%"
    }

    private var accessibilityDescription: String {
        guard let headroomPercentage else {
            return "\(windowLabel) headroom: unavailable"
        }
        return "\(windowLabel) headroom: \(Int(max(0, headroomPercentage))) percent"
    }

    var body: some View {
        ZStack {
            // Track (full ring, tertiary color)
            Circle()
                .stroke(
                    Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )

            // Fill (partial ring, headroom color)
            Circle()
                .trim(from: 0, to: fillAmount)
                .stroke(
                    fillColor,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? .none : .easeInOut(duration: 0.5),
                    value: fillAmount
                )

            // Center content: percentage + optional slope
            VStack(spacing: 0) {
                Text(centerText)
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(fillColor)
                
                // Slope indicator: shown only when slope provided AND connected
                if let slope = slopeLevel, headroomPercentage != nil {
                    SlopeIndicator(slopeLevel: slope, headroomState: headroomState)
                }
            }
        }
        .frame(width: ringSize, height: ringSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(
            headroomPercentage.map { "\(Int(max(0, $0))) percent" } ?? ""
        )
    }
}
```

### Implementation: FiveHourGaugeSection Integration

```swift
// cc-hdrm/Views/FiveHourGaugeSection.swift - Add slope parameter
HeadroomRingGauge(
    headroomPercentage: headroom,
    windowLabel: "5h",
    ringSize: 96,
    strokeWidth: 7,
    slopeLevel: appState.fiveHourSlope  // NEW
)

// Update combinedAccessibilityLabel to include slope
private var combinedAccessibilityLabel: String {
    guard let headroom else {
        return "5-hour headroom: unavailable"
    }
    var label = "5-hour headroom: \(Int(max(0, headroom))) percent, \(appState.fiveHourSlope.accessibilityLabel)"
    if let resetsAt = appState.fiveHour?.resetsAt {
        label += ", resets in \(resetsAt.countdownString()), \(resetsAt.absoluteTimeString())"
    }
    return label
}
```

### Implementation: SevenDayGaugeSection Integration

```swift
// cc-hdrm/Views/SevenDayGaugeSection.swift - Add slope parameter
HeadroomRingGauge(
    headroomPercentage: headroom,
    windowLabel: "7d",
    ringSize: 56,
    strokeWidth: 4,
    slopeLevel: appState.sevenDaySlope  // NEW
)

// Update combinedAccessibilityLabel to include slope
private var combinedAccessibilityLabel: String {
    guard let headroom else {
        return "7-day headroom: unavailable"
    }
    var label = "7-day headroom: \(Int(max(0, headroom))) percent, \(appState.sevenDaySlope.accessibilityLabel)"
    if let resetsAt = appState.sevenDay?.resetsAt {
        label += ", resets in \(resetsAt.countdownString()), \(resetsAt.absoluteTimeString())"
    }
    return label
}
```

### Layout Considerations

**5h ring (96px):** Ample space for percentage text (~20px) + slope arrow (~12px caption). VStack with `spacing: 0` keeps them tight.

**7d ring (56px):** Tighter fit but still sufficient. The percentage text is ~16px at body size, slope arrow ~10px at caption size. Total ~26px vertical content fits within 56px diameter minus stroke width.

If layout issues arise, consider:
- Reducing slope arrow to `.caption2` font
- Adding negative spacing: `VStack(spacing: -2)`

### Project Structure Notes

**New files to create:**
```text
cc-hdrm/Views/SlopeIndicator.swift           # Reusable slope display component
cc-hdrmTests/Views/SlopeIndicatorTests.swift # Unit tests
```

**Files to modify:**
```text
cc-hdrm/Views/HeadroomRingGauge.swift        # Add slopeLevel parameter, VStack center content
cc-hdrm/Views/FiveHourGaugeSection.swift     # Pass fiveHourSlope, update accessibility
cc-hdrm/Views/SevenDayGaugeSection.swift     # Pass sevenDaySlope, update accessibility
```

**XcodeGen reminder:** After creating new Swift files:
```bash
xcodegen generate
```

### SlopeLevel Reference (from cc-hdrm/Models/SlopeLevel.swift)

```swift
enum SlopeLevel: String, Sendable, Equatable, CaseIterable {
    case flat    // arrow: "\u{2192}" (right arrow: ->)
    case rising  // arrow: "\u{2197}" (north-east: upper-right arrow)
    case steep   // arrow: "\u{2B06}" (up arrow)
    
    var arrow: String { ... }
    var accessibilityLabel: String { rawValue }  // "flat", "rising", "steep"
    func color(for headroomState: HeadroomState) -> Color { ... }
    var isActionable: Bool { ... }  // false for flat, true for rising/steep
}
```

### AppState Slope Properties (from cc-hdrm/State/AppState.swift:48-49)

```swift
private(set) var fiveHourSlope: SlopeLevel = .flat
private(set) var sevenDaySlope: SlopeLevel = .flat
```

Both default to `.flat`, so popover will always have a valid slope to display even before 10 minutes of data collection.

### Color Context Behavior

Per Story 11.2, SlopeLevel colors are context-dependent:
- `.flat` always returns `.secondary` (muted gray)
- `.rising` and `.steep` return the current headroom state's color

This means when headroom is critical (red), a steep arrow is also red - reinforcing urgency visually.

### Previous Story Intelligence

**From Story 11.1:**
- SlopeCalculationService uses 15-minute ring buffer
- Requires 10+ minutes / 20+ entries for valid calculation
- Returns `.flat` when insufficient data
- AppState.updateSlopes() called by PollingEngine after each fetch

**From Story 11.2:**
- `SlopeLevel.color(for:)` returns `.secondary` for flat, headroom color for rising/steep
- `SlopeLevel.arrow` returns Unicode arrow character
- `SlopeLevel.accessibilityLabel` returns "flat", "rising", or "steep"

**From Story 11.3:**
- Menu bar only shows slope when `isActionable` is true (rising/steep)
- Popover is different - always shows all three levels (when connected)

### Testing Strategy

```swift
// cc-hdrmTests/Views/SlopeIndicatorTests.swift
import Testing
import SwiftUI
@testable import cc_hdrm

@Suite("SlopeIndicator Tests")
struct SlopeIndicatorTests {
    
    // MARK: - SlopeLevel.arrow Tests
    
    @Test("flat arrow is right arrow Unicode")
    func flatArrowCharacter() {
        #expect(SlopeLevel.flat.arrow == "\u{2192}")
    }
    
    @Test("rising arrow is north-east Unicode")
    func risingArrowCharacter() {
        #expect(SlopeLevel.rising.arrow == "\u{2197}")
    }
    
    @Test("steep arrow is up arrow Unicode")
    func steepArrowCharacter() {
        #expect(SlopeLevel.steep.arrow == "\u{2B06}")
    }
    
    // MARK: - SlopeLevel.color Tests
    
    @Test("flat color is secondary for all headroom states")
    func flatColorIsSecondary() {
        for state in HeadroomState.allCases {
            let color = SlopeLevel.flat.color(for: state)
            #expect(color == .secondary)
        }
    }
    
    @Test("rising color matches headroom state color")
    func risingColorMatchesHeadroom() {
        let normalColor = SlopeLevel.rising.color(for: .normal)
        let criticalColor = SlopeLevel.rising.color(for: .critical)
        // Colors should differ between normal and critical states
        #expect(normalColor != criticalColor)
    }
    
    @Test("steep color matches headroom state color")
    func steepColorMatchesHeadroom() {
        let normalColor = SlopeLevel.steep.color(for: .normal)
        let criticalColor = SlopeLevel.steep.color(for: .critical)
        #expect(normalColor != criticalColor)
    }
    
    // MARK: - Accessibility Label Tests
    
    @Test("accessibility labels are lowercase slope names")
    func accessibilityLabels() {
        #expect(SlopeLevel.flat.accessibilityLabel == "flat")
        #expect(SlopeLevel.rising.accessibilityLabel == "rising")
        #expect(SlopeLevel.steep.accessibilityLabel == "steep")
    }
}

@Suite("Gauge Section Accessibility Tests")
@MainActor
struct GaugeSectionAccessibilityTests {
    
    @Test("5h gauge accessibility includes slope level")
    func fiveHourAccessibilityIncludesSlope() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateSlopes(fiveHour: .rising, sevenDay: .flat)
        
        // Create section and verify accessibility label contains "rising"
        let section = FiveHourGaugeSection(appState: appState)
        // Note: Access combinedAccessibilityLabel via reflection or make it internal for testing
        // The label should contain "rising" when fiveHourSlope is .rising
    }
    
    @Test("7d gauge accessibility includes slope level")
    func sevenDayAccessibilityIncludesSlope() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 30.0, resetsAt: Date().addingTimeInterval(86400))
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .steep)
        
        // Verify 7d accessibility label contains "steep"
    }
}
```

### Edge Cases to Handle

| # | Condition | Expected Behavior |
|---|-----------|-------------------|
| 1 | App just launched (no slope data) | Show flat arrow (AppState defaults to .flat) |
| 2 | Less than 10 min history | Show flat arrow (SlopeCalculationService returns .flat) |
| 3 | 5h normal, slope .flat | Show flat arrow in secondary color |
| 4 | 5h warning, slope .rising | Show rising arrow in warning (orange) color |
| 5 | 5h critical, slope .steep | Show steep arrow in critical (red) color |
| 6 | 7d data unavailable (nil) | 7d section hidden entirely - slope irrelevant |
| 7 | **Disconnected state** | **Slope hidden** - gauge shows em dash only, no slope arrow |

### Backward Compatibility

The `slopeLevel` parameter defaults to `nil` in the initializer:

```swift
init(..., slopeLevel: SlopeLevel? = nil)
```

This ensures any existing code that doesn't pass `slopeLevel` continues to work without modification.

### References

- [Source: cc-hdrm/Models/SlopeLevel.swift] - SlopeLevel enum with arrow, color, accessibilityLabel
- [Source: cc-hdrm/State/AppState.swift:48-49] - fiveHourSlope and sevenDaySlope properties
- [Source: cc-hdrm/Views/HeadroomRingGauge.swift] - Current gauge implementation
- [Source: cc-hdrm/Views/FiveHourGaugeSection.swift] - 5h gauge section
- [Source: cc-hdrm/Views/SevenDayGaugeSection.swift] - 7d gauge section
- [Source: _bmad-output/planning-artifacts/epics.md:1234-1260] - Story 11.4 acceptance criteria
- [Source: _bmad-output/planning-artifacts/ux-design-specification-phase3.md] - Slope display rules
- [Source: _bmad-output/implementation-artifacts/11-2-slope-level-calculation-mapping.md] - Previous story context
- [Source: _bmad-output/implementation-artifacts/11-3-menu-bar-slope-display.md] - Previous story context

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

None

### Completion Notes List

- Created SlopeIndicator component with `.caption` font and `.accessibilityHidden(true)`
- Added `slopeLevel: SlopeLevel? = nil` parameter to HeadroomRingGauge with backward-compatible default
- Wrapped gauge center content in VStack(spacing: 0) to stack percentage + slope
- Slope indicator hidden when headroomPercentage is nil (disconnected state)
- Updated FiveHourGaugeSection and SevenDayGaugeSection to pass slope to gauge
- Updated accessibility labels to include slope: "X percent, [slope level], resets in..."
- All 544 tests pass (23 new tests for Story 11.4)
- Note: Story 11.5 "SlopeIndicator Component" can be marked done or cancelled per Dev Notes

### Code Review Fixes (2026-02-04)

- **H1 Fixed:** Made `combinedAccessibilityLabel` internal (was private) for `@testable import` access
- **M1 Fixed:** Added format verification tests that check label order: percent → slope → resets
- **M2 Fixed:** Renamed tests from "includes" to "LabelContains" to accurately reflect behavior
- **L1 Fixed:** Consolidated 10 preview blocks into 3 using ForEach
- **L2 Fixed:** Added disconnected accessibility tests for both gauge sections
- All 548 tests pass (4 new review tests added)

### File List

**New Files:**
- cc-hdrm/Views/SlopeIndicator.swift
- cc-hdrmTests/Views/SlopeIndicatorTests.swift

**Modified Files:**
- cc-hdrm/Views/HeadroomRingGauge.swift (added slopeLevel parameter, VStack center content)
- cc-hdrm/Views/FiveHourGaugeSection.swift (pass fiveHourSlope, update accessibility, made combinedAccessibilityLabel internal)
- cc-hdrm/Views/SevenDayGaugeSection.swift (pass sevenDaySlope, update accessibility, made combinedAccessibilityLabel internal)

**Review Fix Changes:**
- cc-hdrm/Views/SlopeIndicator.swift (consolidated previews from 10 to 3)
- cc-hdrm/Views/FiveHourGaugeSection.swift (combinedAccessibilityLabel: private → internal)
- cc-hdrm/Views/SevenDayGaugeSection.swift (combinedAccessibilityLabel: private → internal)
- cc-hdrmTests/Views/SlopeIndicatorTests.swift (renamed tests, added 4 new format/disconnected tests)
