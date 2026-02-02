# Story 4.2: 5-Hour Headroom Ring Gauge with Countdown

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to see a detailed 5-hour headroom gauge with countdown in the expanded panel,
so that I know exactly how much session capacity remains and when it resets.

## Acceptance Criteria

1. **Given** AppState contains valid 5-hour usage data, **When** the popover renders, **Then** it shows a circular ring gauge (96px diameter, 7px stroke) as the primary element.
2. **And** the ring depletes clockwise from 12 o'clock as headroom decreases.
3. **And** ring fill color matches the HeadroomState color token.
4. **And** ring track (unfilled) uses system tertiary color.
5. **And** percentage is displayed centered inside the ring, bold, headroom-colored.
6. **And** "5h" label appears above the gauge in caption size, secondary color.
7. **And** relative countdown appears below: "resets in 47m" (secondary text).
8. **And** absolute time appears below that: "at 4:52 PM" (tertiary text).
9. **Given** 5-hour headroom is at 0% (exhausted), **When** the popover renders, **Then** the ring is empty (no fill), center shows "0%" in red.
10. **And** countdown shows "resets in Xm" in headroom color (red) for emphasis.
11. **Given** 5-hour data is unavailable (disconnected/no credentials), **When** the popover renders, **Then** the ring is empty with grey track, center shows "---" in grey, and no countdown is displayed.
12. **Given** gauge fill changes between poll cycles, **When** new data arrives, **Then** the ring animates smoothly to the new fill level (`.animation(.easeInOut(duration: 0.5))`).
13. **And** if `accessibilityReduceMotion` is enabled, the gauge snaps instantly.
14. **Given** a VoiceOver user focuses the 5h gauge, **When** VoiceOver reads the element, **Then** it announces "5-hour headroom: [X] percent, resets in [relative], at [absolute]".

## Tasks / Subtasks

- [x] Task 1: Create HeadroomRingGauge.swift -- reusable circular ring gauge component (AC: #1-#5, #9, #11-#13)
  - [x] Create `cc-hdrm/Views/HeadroomRingGauge.swift`
  - [x] SwiftUI `View` struct with parameters:
    - `headroomPercentage: Double?` (nil = disconnected)
    - `windowLabel: String` ("5h" or "7d")
    - `ringSize: CGFloat` (96 for 5h primary, 56 for 7d secondary)
    - `strokeWidth: CGFloat` (7 for 5h, 4 for 7d)
  - [x] Ring track: full circle using `.stroke(style:)` with `Color.secondary.opacity(0.3)` (system tertiary)
  - [x] Ring fill: partial arc from 12 o'clock (startAngle: -90°), depleting clockwise proportional to `(100 - headroom) / 100`
    - Fill amount = `max(0, headroomPercentage ?? 0) / 100.0`
    - Arc uses `trim(from: 0, to: fillAmount)` rotated -90° so it starts at top
  - [x] Fill color: derive HeadroomState from percentage, use `Color.headroomColor(for:)` (see Color+Headroom.swift extensions)
    - Since Color+Headroom.swift defines static properties like `Color.headroomNormal`, create a helper: `HeadroomState.swiftUIColor -> Color`
  - [x] Center text: percentage as integer (e.g., "83%"), bold, headroom-colored
    - Exhausted (0%): show "0%" in `.headroomExhausted` color
    - Disconnected (nil): show "\u{2014}" (em dash) in `.disconnected` color
  - [x] Animation: `.animation(.easeInOut(duration: 0.5), value: headroomPercentage)` on the ring fill
  - [x] Reduced motion: wrap animation in `@Environment(\.accessibilityReduceMotion)` check -- if true, use `.animation(.none)`
  - [x] Accessibility: `.accessibilityElement(children: .ignore)` on the gauge, with `.accessibilityLabel` and `.accessibilityValue` set based on state

- [x] Task 2: Add `swiftUIColor` computed property to HeadroomState (AC: #3, #5)
  - [x] In `cc-hdrm/Models/HeadroomState.swift`, add:
    ```swift
    import SwiftUI // add if not already imported
    
    var swiftUIColor: Color {
        switch self {
        case .normal: .headroomNormal
        case .caution: .headroomCaution
        case .warning: .headroomWarning
        case .critical: .headroomCritical
        case .exhausted: .headroomExhausted
        case .disconnected: .disconnected
        }
    }
    ```
  - [x] NOTE: HeadroomState.swift currently only imports Foundation. Adding `import SwiftUI` is appropriate since this property is only used by views. ALTERNATIVELY, put this in an extension file `HeadroomState+SwiftUI.swift` in Extensions/ to keep the model pure Foundation. Developer's choice -- either is acceptable.

- [x] Task 3: Add absolute time formatter to Date+Formatting.swift (AC: #8)
  - [x] In `cc-hdrm/Extensions/Date+Formatting.swift`, add:
    ```swift
    /// Returns an absolute time string for display below countdowns.
    /// - Same day: "at 4:52 PM"
    /// - Different day: "at Mon 7:05 PM"
    func absoluteTimeString() -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        
        if calendar.isDateInToday(self) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "EEE h:mm a"
        }
        
        return "at \(formatter.string(from: self))"
    }
    ```
  - [x] This follows the UX spec formatting rules and the architecture mandate that all date/time formatting lives in Date+Formatting.swift

- [x] Task 4: Create CountdownLabel.swift -- relative + absolute reset time display (AC: #7, #8, #10)
  - [x] Create `cc-hdrm/Views/CountdownLabel.swift`
  - [x] SwiftUI `View` struct with parameters:
    - `resetTime: Date?` (nil = no countdown to show)
    - `headroomState: HeadroomState`
    - `countdownTick: UInt` (pass through from AppState to trigger re-renders every 60s)
  - [x] Line 1 (relative): "resets in 47m" using `resetTime.countdownString()` (already exists in Date+Formatting)
    - Caption size (`.font(.caption)`)
    - Color: `.secondary` normally, but `headroomState.swiftUIColor` when `.exhausted` (red for emphasis per AC #10)
  - [x] Line 2 (absolute): "at 4:52 PM" using new `resetTime.absoluteTimeString()`
    - Mini size (`.font(.caption2)`)
    - Color: `.tertiary` (system tertiary)
  - [x] When `resetTime` is nil: don't render anything (return `EmptyView()`)
  - [x] Read `countdownTick` in body to register observation dependency for 60-second refresh
  - [x] Accessibility: `.accessibilityElement(children: .combine)` so VoiceOver reads both lines together: "Resets in 47 minutes, at 4:52 PM"

- [x] Task 5: Create FiveHourGaugeSection -- composed view for the 5h section in popover (AC: #1-#14)
  - [x] This can be either a standalone view or integrated directly into PopoverView. Recommend a standalone `FiveHourGaugeSection.swift` in Views/ for clarity, OR inline it in PopoverView. Developer's choice.
  - [x] Composition (VStack):
    1. "5h" label: `Text("5h").font(.caption).foregroundStyle(.secondary)` (AC #6)
    2. `HeadroomRingGauge(headroomPercentage: headroom, windowLabel: "5h", ringSize: 96, strokeWidth: 7)` (AC #1-#5)
    3. `CountdownLabel(resetTime: appState.fiveHour?.resetsAt, headroomState: fiveHourState, countdownTick: appState.countdownTick)` (AC #7, #8, #10)
  - [x] Headroom calculation: `let headroom = appState.fiveHour.map { 100.0 - $0.utilization }` (nil when no data = disconnected)
  - [x] Center the section horizontally in the popover

- [x] Task 6: Update PopoverView.swift to replace "5h gauge" placeholder (AC: all)
  - [x] In `cc-hdrm/Views/PopoverView.swift`:
  - [x] Replace the `Text("5h gauge")` placeholder with the composed 5h gauge section
  - [x] Keep the `Divider()` after the 5h section
  - [x] Keep "7d gauge" placeholder and "footer" placeholder intact (stories 4.3 and 4.4)
  - [x] Ensure `appState.countdownTick` is accessed in the view tree so countdown updates trigger re-renders

- [x] Task 7: Write HeadroomRingGauge tests (AC: #1-#5, #9, #11)
  - [x] Create `cc-hdrmTests/Views/HeadroomRingGaugeTests.swift`
  - [x] Test: gauge can be instantiated with normal headroom percentage (no crash)
  - [x] Test: gauge can be instantiated with nil percentage (disconnected state)
  - [x] Test: gauge can be instantiated with 0% headroom (exhausted state)
  - [x] Test: gauge can be instantiated with 100% headroom (full capacity)
  - [x] Test: verify HeadroomState derivation is correct for various percentages (leverages existing HeadroomStateTests patterns)

- [x] Task 8: Write CountdownLabel tests (AC: #7, #8, #10)
  - [x] Create `cc-hdrmTests/Views/CountdownLabelTests.swift`
  - [x] Test: CountdownLabel renders with a future reset time (no crash)
  - [x] Test: CountdownLabel with nil resetTime returns empty (no crash)
  - [x] Test: verify `absoluteTimeString()` produces "at HH:mm AM/PM" for same-day dates
  - [x] Test: verify `absoluteTimeString()` produces "at EEE HH:mm AM/PM" for different-day dates
  - [x] Note: absoluteTimeString tests should live in `cc-hdrmTests/Extensions/DateFormattingTests.swift` (extend existing file)

- [x] Task 9: Write PopoverView integration test for 5h gauge (AC: #1, #5)
  - [x] Extend `cc-hdrmTests/Views/PopoverViewTests.swift`:
  - [x] Test: PopoverView with valid 5h data in AppState renders without crash
  - [x] Test: PopoverView with nil fiveHour in AppState renders disconnected gauge without crash
  - [x] Test: Updating AppState.fiveHour triggers observation (reuse withObservationTracking pattern from story 4.1)

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. HeadroomRingGauge and CountdownLabel are pure presentational views -- read-only observers of data passed in via props. They do NOT write to AppState.
- **State flow:** Services -> AppState -> PopoverView -> HeadroomRingGauge/CountdownLabel
- **HeadroomState derivation:** The gauge derives HeadroomState from the headroom percentage internally. It does NOT store state separately. This follows the architecture mandate: "HeadroomState is computed from utilization value, never stored separately."
- **Concurrency:** All AppState access is `@MainActor`. Views run on main thread via SwiftUI. No concurrency concerns.
- **Logging:** No logging needed in view components. Logging happens in services (polling, API) and AppDelegate (popover open/close).

### Ring Gauge Implementation Strategy

The ring gauge uses SwiftUI's `Circle().trim(from:to:)` pattern:

```swift
ZStack {
    // Track (full ring, tertiary color)
    Circle()
        .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
    
    // Fill (partial ring, headroom color)
    Circle()
        .trim(from: 0, to: fillAmount)
        .stroke(fillColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
        .rotationEffect(.degrees(-90)) // Start from 12 o'clock
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.5), value: fillAmount)
    
    // Center percentage text
    Text(centerText)
        .font(.system(.body, weight: .bold))
        .foregroundStyle(fillColor)
}
.frame(width: ringSize, height: ringSize)
```

**Key decision:** The ring "depletes" as headroom decreases. So `fillAmount = headroom / 100`. At 83% headroom, the ring is 83% filled. At 0%, the ring is empty. This aligns with the fuel gauge mental model.

### Countdown Tick Mechanism

The `countdownTick` property on AppState is incremented every 60 seconds by `FreshnessMonitor`. CountdownLabel reads this value in its body to register an observation dependency, which triggers SwiftUI re-renders every 60 seconds. This is the same pattern used by the menu bar countdown in story 3.2.

```swift
// In CountdownLabel body:
let _ = countdownTick  // Register observation dependency for 60-second refresh
```

### Previous Story Intelligence (4.1)

**What was built:**
- `PopoverView.swift` -- VStack with placeholder "5h gauge", "7d gauge", "footer" text
- `AppDelegate` -- NSPopover with NSHostingController, togglePopover, `.transient` behavior
- PopoverView takes `appState: AppState` parameter
- PopoverView reads `appState.connectionStatus` to register observation dependency
- `sendAction(on: .leftMouseUp)` on status item button

**Patterns to reuse:**
- PopoverView is a struct, takes AppState directly (not binding)
- Test pattern: instantiate views with AppState, verify no crash, use `withObservationTracking` for live update tests
- XcodeGen auto-discovers new files in Views/ directory

**Code review lessons from all previous stories:**
- Pass original errors to AppError wrappers, not hardcoded errors
- Remove dead code / unused properties before committing
- Add call counters to mocks for verifying interaction patterns
- Make services `@MainActor` when they hold AppState reference
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` -- protected file

### Git Intelligence

Recent commits show one commit per story with code review fixes included. Files organized by layer. `project.yml` (XcodeGen) auto-discovers sources by directory -- new files in Views/ are automatically included on next `xcodegen generate`.

### Project Structure Notes

- `Views/` directory already exists (created in story 4.1 with PopoverView.swift)
- New files go in `cc-hdrm/Views/` and `cc-hdrmTests/Views/`
- `Date+Formatting.swift` already has `countdownString()` and `relativeTimeAgo()` -- add `absoluteTimeString()` there
- `Color+Headroom.swift` already has SwiftUI Color static properties (`.headroomNormal`, etc.)
- `HeadroomState.swift` has `colorTokenName` and `fontWeight` (String) but no SwiftUI Color mapping yet

### File Structure Requirements

New files to create:
```
cc-hdrm/Views/HeadroomRingGauge.swift              # NEW -- circular ring gauge component
cc-hdrm/Views/CountdownLabel.swift                  # NEW -- relative + absolute reset time
cc-hdrmTests/Views/HeadroomRingGaugeTests.swift      # NEW -- gauge tests
cc-hdrmTests/Views/CountdownLabelTests.swift         # NEW -- countdown tests
```

Files to modify:
```
cc-hdrm/Models/HeadroomState.swift                  # ADD swiftUIColor computed property (or create extension)
cc-hdrm/Extensions/Date+Formatting.swift            # ADD absoluteTimeString() method
cc-hdrm/Views/PopoverView.swift                     # REPLACE "5h gauge" placeholder with real gauge
cc-hdrmTests/Views/PopoverViewTests.swift            # ADD 5h gauge integration tests
cc-hdrmTests/Extensions/DateFormattingTests.swift    # ADD absoluteTimeString tests
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on any test touching AppState
- **SwiftUI view tests:** Instantiate views, verify they render without crash. Full visual testing is out of scope -- verify props, state derivation, and observation contracts.
- **Date formatting tests:** Test `absoluteTimeString()` with known dates. Use `Calendar.current` aware assertions. Consider timezone sensitivity.
- **Observation tests:** Use `withObservationTracking` pattern from story 4.1 to verify gauge updates when AppState changes.

### Library & Framework Requirements

- `SwiftUI` -- HeadroomRingGauge, CountdownLabel (already used in project)
- `Foundation` -- Date formatting (already imported)
- No new dependencies. Zero external packages.

### Anti-Patterns to Avoid

- DO NOT store HeadroomState as a property in the gauge -- always derive from percentage
- DO NOT update countdown every second -- the 60-second countdownTick mechanism is sufficient
- DO NOT add the 7d gauge in this story -- that's story 4.3
- DO NOT add the footer in this story -- that's story 4.4
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` -- protected file
- DO NOT use `DispatchQueue` or timers for countdown updates -- use the existing countdownTick observation pattern
- DO NOT use SwiftUI `.popover()` modifier -- the popover is AppKit NSPopover (story 4.1)
- DO NOT hardcode colors -- use the semantic color tokens from Color+Headroom.swift
- DO NOT use `print()` -- use `os.Logger` if logging is needed (it shouldn't be in views)

### References

- [Source: epics.md#Story 4.2] -- Full acceptance criteria
- [Source: ux-design-specification.md#HeadroomRingGauge] -- Ring gauge specs: 96px, 7px stroke, clockwise depletion, color tokens, states
- [Source: ux-design-specification.md#CountdownLabel] -- Relative + absolute time display, formatting rules
- [Source: ux-design-specification.md#Spacing & Layout Foundation] -- Popover structure: 5h gauge primary, stacked vertical
- [Source: ux-design-specification.md#Accessibility Considerations] -- VoiceOver labels, reduced motion, color independence
- [Source: architecture.md#App Architecture] -- MVVM, Views observe AppState read-only
- [Source: architecture.md#Format Patterns] -- Date/time formatting rules, Date+Formatting.swift
- [Source: architecture.md#Accessibility Patterns] -- .accessibilityLabel, .accessibilityValue, color + number + weight triple-encoding
- [Source: architecture.md#State Management Patterns] -- HeadroomState derived from utilization, never stored
- [Source: project-context.md#Date/Time Formatting] -- Countdown and absolute time formatting rules
- [Source: AppState.swift:14-22] -- WindowState struct with utilization, resetsAt, derived headroomState
- [Source: AppState.swift:49] -- countdownTick property for 60-second re-renders
- [Source: Date+Formatting.swift:42-65] -- Existing countdownString() method
- [Source: Color+Headroom.swift:59-66] -- SwiftUI Color static properties for headroom states
- [Source: HeadroomState.swift:16-36] -- HeadroomState init(from: Double?) derivation logic
- [Source: PopoverView.swift:14-17] -- Current "5h gauge" placeholder to replace
- [Source: story 4-1] -- Previous story patterns, PopoverView structure, test patterns

## Dev Agent Record

### Agent Model Used

claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

- Initial test run failed: new files not in Xcode project — resolved by running `xcodegen generate`
- Second test run: 3 failures — `absoluteTimeString` tests used case-sensitive "M" check but locale outputs lowercase "pm"; observation test tracked PopoverView.body which doesn't directly read `fiveHour` (delegated to FiveHourGaugeSection)
- Fixes: case-insensitive AM/PM assertions; observation test targets FiveHourGaugeSection directly

### Completion Notes List

- ✅ Task 1: Created HeadroomRingGauge.swift — reusable ring gauge with Circle().trim() pattern, animation with reduced motion support, full accessibility
- ✅ Task 2: Created HeadroomState+SwiftUI.swift extension in Extensions/ to keep HeadroomState.swift pure Foundation
- ✅ Task 3: Added absoluteTimeString() to Date+Formatting.swift — same-day "at h:mm a", different-day "at EEE h:mm a"
- ✅ Task 4: Created CountdownLabel.swift — relative countdown + absolute time, exhausted color emphasis, countdownTick observation
- ✅ Task 5: Created FiveHourGaugeSection.swift — composed view: "5h" label + ring gauge + countdown
- ✅ Task 6: Updated PopoverView.swift — replaced "5h gauge" placeholder with FiveHourGaugeSection, added countdownTick observation
- ✅ Task 7: 6 tests in HeadroomRingGaugeTests (normal, disconnected, exhausted, full, state derivation, secondary size)
- ✅ Task 8: 3 tests in CountdownLabelTests + 2 tests in DateFormattingTests for absoluteTimeString
- ✅ Task 9: 3 tests in PopoverView5hGaugeTests (valid data, nil data, fiveHour observation)
- All 199 tests pass (0 failures, 0 regressions)

### Change Log

- 2026-02-01: Implemented story 4.2 — 5-hour headroom ring gauge with countdown. Created 5 new source files, 2 new test files, modified 3 existing source files and 2 existing test files. 14 new tests added, all 199 tests passing.
- 2026-02-01: Code review fixes — M1: cached DateFormatters in absoluteTimeString; M2: FiveHourGaugeSection now provides single combined VoiceOver announcement per AC#14; M3: removed redundant accessibility value on disconnected gauge; M4: added negative headroom edge-case test; L2: added exhausted color logic test. 2 new tests added.

### File List

New files:
- cc-hdrm/Views/HeadroomRingGauge.swift
- cc-hdrm/Views/CountdownLabel.swift
- cc-hdrm/Views/FiveHourGaugeSection.swift
- cc-hdrm/Extensions/HeadroomState+SwiftUI.swift
- cc-hdrmTests/Views/HeadroomRingGaugeTests.swift
- cc-hdrmTests/Views/CountdownLabelTests.swift

Modified files:
- cc-hdrm/Extensions/Date+Formatting.swift
- cc-hdrm/Views/PopoverView.swift
- cc-hdrmTests/Views/PopoverViewTests.swift
- cc-hdrmTests/Extensions/DateFormattingTests.swift
- cc-hdrm/cc-hdrm.xcodeproj (regenerated via xcodegen, gitignored)
- _bmad-output/implementation-artifacts/sprint-status.yaml
