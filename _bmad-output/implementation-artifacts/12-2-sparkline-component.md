# Story 12.2: Sparkline Component

Status: done

## Story

As a developer using Claude Code,
I want a compact sparkline showing the 24h usage sawtooth pattern,
So that I can see recent trends at a glance and quickly access deeper analytics.

## Acceptance Criteria

1. **Given** `AppState.sparklineData` contains 24h of poll data
   **When** `Sparkline` component renders
   **Then** it displays a step-area chart (not line chart) honoring the monotonically increasing nature of utilization
   **And** only 5h utilization is shown (7d is too slow-moving for 24h sparkline)
   **And** reset boundaries are visible as vertical drops to the baseline
   **And** the sparkline height is exactly 40px, width fills container (minimum 180px)

2. **Given** gaps exist in the sparkline data (cc-hdrm wasn't running)
   **When** `Sparkline` renders
   **Then** gaps are rendered as breaks in the path (no interpolation, no fake data)
   **And** gap regions are filled with system tertiary color at 20% opacity

3. **Given** the sparkline data is empty or insufficient (`hasSparklineData == false`)
   **When** `Sparkline` renders
   **Then** it shows placeholder text "Building history..." instead of an empty chart

4. **Given** a VoiceOver user focuses the sparkline
   **When** VoiceOver reads the element
   **Then** it announces "24-hour usage chart. Double-tap to open analytics."

5. **Given** poll data contains invalid `fiveHourUtil` values (nil, negative, or >100)
   **When** `Sparkline` renders
   **Then** invalid points are skipped (treated as gaps)
   **And** the chart continues with the next valid data point

6. **Given** new poll data arrives while the sparkline is visible
   **When** `sparklineData` updates
   **Then** the sparkline redraws immediately without animation (snap to new state)

## Tasks / Subtasks

- [x] Task 1: Create Sparkline view component (AC: 1, 2, 3, 5, 6)
  - [x] 1.1 Create `cc-hdrm/Views/Sparkline.swift` with SwiftUI Canvas-based rendering
  - [x] 1.2 Implement step-area path generation that honors monotonically increasing utilization
  - [x] 1.3 Detect and render reset boundaries as vertical drops to baseline (when `fiveHourResetsAt` changes between consecutive polls)
  - [x] 1.4 Implement gap detection using dynamic threshold (1.5x current poll interval from PreferencesManager)
  - [x] 1.5 Render gaps as path breaks with system tertiary fill at 20% opacity
  - [x] 1.6 Display placeholder text when `data.count < 2`
  - [x] 1.7 Skip invalid data points (nil, negative, >100 fiveHourUtil values)
  - [x] 1.8 Implement X-axis as proportional 24-hour window (oldest point at left edge, newest at right)

- [x] Task 2: Add hover/click interaction support (AC: 4, prep for Story 12.3)
  - [x] 2.1 Add `onTap: () -> Void` callback property for analytics window toggle (Story 12.3 will wire this to AnalyticsWindowController.toggle())
  - [x] 2.2 Add `isAnalyticsOpen: Bool` property that renders a 4px accent-color dot in the bottom-right corner when true
  - [x] 2.3 Implement hover highlight: background color changes to system quaternary at 30% opacity
  - [x] 2.4 Change cursor to pointer on hover using `NSCursor.pointingHand.push()/pop()` in onHover modifier
  - [x] 2.5 Add VoiceOver accessibility label "24-hour usage chart" and hint "Double-tap to open analytics"
  - [x] 2.6 Add `.accessibilityAddTraits(.isButton)` for VoiceOver interaction

- [x] Task 3: Add unit tests for Sparkline component
  - [x] 3.1 Create `cc-hdrmTests/Views/SparklineTests.swift`
  - [x] 3.2 Extract path generation into a testable `SparklinePathBuilder` struct with pure functions
  - [x] 3.3 Test step-area path point generation with sample data (verify coordinate calculations)
  - [x] 3.4 Test reset boundary detection with fiveHourResetsAt changes
  - [x] 3.5 Test reset boundary fallback detection with >50% utilization drops
  - [x] 3.6 Test gap detection with various timestamp deltas
  - [x] 3.7 Test invalid data point filtering (nil, negative, >100)
  - [x] 3.8 Test placeholder display condition (data.count < 2)
  - [x] 3.9 Test X-axis proportional mapping calculations
  - [x] 3.10 Test accessibility properties are correctly configured

## Dev Notes

### Architecture Patterns

- **Location:** `cc-hdrm/Views/Sparkline.swift` (new file)
- **Framework:** SwiftUI with Canvas for custom drawing
- **Data source:** `AppState.sparklineData: [UsagePoll]` (already implemented in Story 12.1)
- **Sizing:** Height exactly 40px, width flexible (minimum 180px, fills container)

### Key Data Structures

```swift
// From cc-hdrm/Models/UsagePoll.swift (already exists)
struct UsagePoll: Sendable, Equatable {
    let id: Int64
    let timestamp: Int64        // Unix milliseconds
    let fiveHourUtil: Double?   // 0-100 percentage (nil/negative/>100 = invalid)
    let fiveHourResetsAt: Int64?
    let sevenDayUtil: Double?
    let sevenDayResetsAt: Int64?
}
```

### Testable Path Builder Pattern

To enable unit testing of Canvas rendering logic, extract coordinate calculations into a pure function:

```swift
struct SparklinePathBuilder {
    struct PathSegment {
        let points: [(x: CGFloat, y: CGFloat)]
        let isGap: Bool
    }
    
    /// Pure function that converts poll data to drawable path segments
    /// - Parameters:
    ///   - polls: Sorted array of UsagePoll (ascending by timestamp)
    ///   - size: The drawing area size
    ///   - gapThresholdMs: Gap detection threshold in milliseconds
    /// - Returns: Array of path segments for rendering
    static func buildSegments(
        from polls: [UsagePoll],
        size: CGSize,
        gapThresholdMs: Int64
    ) -> [PathSegment]
}
```

Unit tests verify the PathSegment output (coordinates and gap flags), not the Canvas rendering itself.

### Step-Area Chart Algorithm

The sparkline must honor the **monotonically increasing** nature of utilization within windows:

1. **Filter invalid points first:** Skip any poll where `fiveHourUtil` is nil, negative, or >100
2. **Iterate through sorted polls** (already sorted by timestamp ascending in `sparklineData`)
3. **For each poll with valid `fiveHourUtil`:**
   - Draw horizontal line from previous point to current timestamp at previous utilization
   - Draw vertical line from previous utilization to current utilization
   - This creates the "step" pattern
4. **Reset detection:** When `fiveHourResetsAt` changes between consecutive polls:
   - Draw vertical drop to 0% (baseline)
   - Start new segment from 0%
5. **Gap detection:** When `timestamp` delta exceeds the dynamic gap threshold:
   - End current path segment
   - Start new path segment after gap
   - Fill gap region with system tertiary color at 20% opacity

### X-Axis Mapping (24-Hour Proportional Window)

The X-axis represents a 24-hour window proportionally:

```swift
// Calculate X position for a given timestamp
func xPosition(for timestamp: Int64, in size: CGSize, timeRange: ClosedRange<Int64>) -> CGFloat {
    let duration = Double(timeRange.upperBound - timeRange.lowerBound)
    guard duration > 0 else { return 0 }
    let offset = Double(timestamp - timeRange.lowerBound)
    return CGFloat(offset / duration) * size.width
}

// Time range is determined by the data bounds (not fixed 24h from now)
let timeRange = polls.first!.timestamp...polls.last!.timestamp
```

### Dynamic Gap Threshold

Gap threshold is 1.5x the user's configured poll interval (not a fixed value):

```swift
// Inject PreferencesManager to get current poll interval
func gapThresholdMs(preferencesManager: PreferencesManagerProtocol) -> Int64 {
    // Poll interval is in seconds, convert to milliseconds and multiply by 1.5
    return Int64(preferencesManager.pollInterval * 1000 * 1.5)
}

// Example: 30s poll interval → 45,000ms threshold
// Example: 60s poll interval → 90,000ms threshold
// Example: 10s poll interval → 15,000ms threshold
```

**Rationale:** Using a fixed 90,000ms threshold would miss gaps when poll interval is 10s (gap after just 15s of missing data), and be too aggressive when poll interval is 300s (5 minutes).

### Reset Boundary Detection

```swift
func isResetBoundary(from previous: UsagePoll, to current: UsagePoll) -> Bool {
    guard let prevResetsAt = previous.fiveHourResetsAt,
          let currResetsAt = current.fiveHourResetsAt else {
        // Fallback: large utilization drop (>50%) indicates reset
        // This threshold is chosen because normal usage patterns don't show
        // >50% drops within a single poll interval. Resets drop to ~0%.
        if let prevUtil = previous.fiveHourUtil,
           let currUtil = current.fiveHourUtil,
           prevUtil - currUtil > 50.0 {
            return true
        }
        return false
    }
    return prevResetsAt != currResetsAt
}
```

**Fallback rationale:** The >50% threshold catches resets when `fiveHourResetsAt` is unavailable (edge case). Normal utilization increases monotonically; a drop >50% strongly indicates a window reset. Smaller drops (e.g., 30%) could occur from API timing quirks and should not trigger false reset boundaries.

### Visual Design

| Element | Specification |
|---------|---------------|
| Chart type | Step-area (filled below the line) |
| Fill color | `headroomNormal` at 30% opacity |
| Stroke color | `headroomNormal` at 100% opacity, 1px width |
| Gap fill | System tertiary color at 20% opacity |
| Reset markers | Implicit via vertical drop to baseline |
| Axis labels | None (the shape tells the story) |
| Height | Exactly 40px |
| Width | Minimum 180px, fills container |
| Hover highlight | System quaternary color at 30% opacity background |
| Analytics indicator dot | 4px circle, accent color, bottom-right corner (visible when `isAnalyticsOpen == true`) |
| Animation | None (immediate snap to new state on data update) |

### Cursor Change Implementation (macOS)

SwiftUI doesn't provide native cursor control. Use NSCursor with onHover:

```swift
.onHover { hovering in
    if hovering {
        NSCursor.pointingHand.push()
    } else {
        NSCursor.pop()
    }
}
```

**Important:** Always balance push/pop calls to avoid cursor state leaks.

### Accessibility Requirements

```swift
.accessibilityLabel("24-hour usage chart")
.accessibilityHint("Double-tap to open analytics")
.accessibilityAddTraits(.isButton)
```

**Note:** The sparkline serves dual purpose: (1) showing trends at a glance, and (2) acting as a button to open the analytics window. The VoiceOver hint communicates the interactive aspect.

### Story 12.3 Integration Context

Task 2 prepares the component for Story 12.3 (Sparkline as Analytics Toggle) which will:
- Wire `onTap` callback to `AnalyticsWindowController.toggle()`
- Bind `isAnalyticsOpen` to `AppState.isAnalyticsWindowOpen`
- Handle the popover remaining open when analytics opens

By including these properties now, Story 12.3 can focus on the window controller integration without modifying Sparkline's interface.

### Project Structure Notes

- **New file:** `cc-hdrm/Views/Sparkline.swift`
- **Test file:** `cc-hdrmTests/Views/SparklineTests.swift`
- **Integration point:** Story 12.4 will integrate into PopoverView between 7d gauge and footer
- **No external dependencies** - uses only SwiftUI Canvas and AppKit NSCursor

### References

- [Source: `_bmad-output/planning-artifacts/ux-design-specification-phase3.md` - Feature 2: Historical Usage Tracking, Popover Sparkline section]
- [Source: `_bmad-output/planning-artifacts/architecture.md` - Phase 3 Architectural Additions, Analytics Window Architecture]
- [Source: `_bmad-output/planning-artifacts/epics.md` - Epic 12, Stories 12.2 and 12.3 acceptance criteria]
- [Source: `cc-hdrm/State/AppState.swift:51-61` - sparklineData property and hasSparklineData computed property]
- [Source: `cc-hdrm/Models/UsagePoll.swift` - UsagePoll struct definition]
- [Source: `cc-hdrm/Views/PopoverView.swift` - current popover layout for integration context]
- [Source: `cc-hdrm/Services/PreferencesManager.swift:96-105` - pollInterval property for dynamic gap threshold]

### Testing Standards

- Use Swift Testing framework (`@Test`, `#expect`)
- Test the `SparklinePathBuilder` pure functions, not Canvas rendering
- Mock data using `UsagePoll` instances with known values
- Test edge cases: empty data, single point, gaps, multiple resets, invalid values
- Verify accessibility properties are correctly set (use accessibility identifiers)

### Previous Story Intelligence

From Story 12.1 commit (748b3e6):
- `AppState.sparklineData: [UsagePoll]` already implemented
- `AppState.hasSparklineData` computed property returns true when count >= 2
- `AppState.updateSparklineData(_:)` method exists for updates
- `PollingEngine` refreshes sparkline data on each successful poll cycle
- Data is preserved across connection state changes (not cleared on disconnect)

### Git Context

Recent commits show Phase 3 slope indicator implementation pattern:
- `SlopeIndicator.swift` created in Story 11.4 as a reusable component
- Similar pattern can be followed for Sparkline component
- Tests follow the `*Tests.swift` naming convention in `cc-hdrmTests/`

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

N/A

### Completion Notes List

- Created `Sparkline.swift` with SwiftUI Canvas-based rendering implementing step-area chart visualization
- Implemented `SparklinePathBuilder` struct with pure functions for testable path generation logic
- Step-area chart honors monotonically increasing utilization pattern with horizontal-then-vertical steps
- Reset boundary detection via `fiveHourResetsAt` changes with fallback to >50% drop heuristic
- Gap detection using dynamic 1.5x poll interval threshold, rendered as path breaks with tertiary fill
- Placeholder "Building history..." displayed when insufficient data (<2 points)
- Invalid data points (nil, negative, >100) filtered before path generation
- X-axis proportional mapping from oldest to newest timestamp
- Hover interaction: quaternary background highlight, pointer cursor via NSCursor push/pop
- Analytics indicator: 4px accent-color dot in bottom-right when `isAnalyticsOpen == true`
- VoiceOver accessibility: label "24-hour usage chart", hint "Double-tap to open analytics", button trait
- Created comprehensive test suite with 30 tests covering path builder and view component
- All project tests pass with no regressions

### File List

**New Files:**
- `cc-hdrm/Views/Sparkline.swift` - Sparkline view component with SparklinePathBuilder
- `cc-hdrmTests/Views/SparklineTests.swift` - Unit tests for Sparkline component (30 tests)

### Senior Developer Review (AI)

**Reviewer:** claude-opus-4-5
**Date:** 2026-02-04
**Outcome:** APPROVED (with fixes applied)

**Issues Found & Fixed:**
| Severity | Issue | Fix Applied |
|----------|-------|-------------|
| HIGH | NSCursor leak potential - cursor not cleaned up on view removal | Added `onDisappear` modifier to pop cursor if hovering when view disappears |
| MEDIUM | Weak test assertions for invalid data filtering | Improved tests to verify segment count, type, and point structure |
| MEDIUM | Missing boundary case test for exactly 50% drop | Added test verifying 50% drop does NOT trigger reset |
| MEDIUM | Weak stepAreaPathGeneration test assertion | Added specific point structure verification |
| LOW | Missing zero-duration time range test | Added test for edge case when all timestamps are equal |
| LOW | Preview data in production code | Wrapped `SparklinePreviewData` and previews in `#if DEBUG` |

**Verification:**
- All 6 Acceptance Criteria verified as implemented
- All 18 tasks verified as complete
- Test count increased from 28 to 30 (added 2 edge case tests)
- Full test suite passes with no regressions
- Git status matches story File List

## Change Log

| Date | Change |
|------|--------|
| 2026-02-04 | Story implementation complete: Sparkline component with step-area chart, gap detection, reset boundaries, hover/click interaction, VoiceOver accessibility, and comprehensive tests |
| 2026-02-04 | Code review complete: Fixed cursor leak, improved test assertions, added 2 edge case tests, wrapped preview code in DEBUG. Status → done |
