# Story 4.3: 7-Day Headroom Ring Gauge with Countdown

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to see a detailed 7-day headroom gauge with countdown in the expanded panel,
so that I can track my weekly limit alongside the session limit.

## Acceptance Criteria

1. **Given** AppState contains valid 7-day usage data, **When** the popover renders, **Then** it shows a circular ring gauge (56px diameter, 4px stroke) below a hairline divider after the 5h gauge.
2. **And** ring behavior matches Story 4.2 (depletes clockwise from 12 o'clock, color tokens, percentage centered, countdown below).
3. **And** "7d" label appears above the gauge.
4. **And** relative countdown: "resets in 2d 1h".
5. **And** absolute time: "at Mon 7:05 PM".
6. **Given** 7-day data is unavailable or null in the API response, **When** the popover renders, **Then** the 7d gauge section is hidden entirely (not shown as grey/empty).
7. **Given** a VoiceOver user focuses the 7d gauge, **When** VoiceOver reads the element, **Then** it announces "7-day headroom: [X] percent, resets in [relative], at [absolute]".

## Tasks / Subtasks

- [x] Task 1: Create SevenDayGaugeSection.swift -- composed view for the 7d section in popover (AC: #1-#5, #7)
  - [x] Create `cc-hdrm/Views/SevenDayGaugeSection.swift`
  - [x] SwiftUI `View` struct with parameter: `appState: AppState`
  - [x] Headroom calculation: `let headroom = appState.sevenDay.map { 100.0 - $0.utilization }` (nil when no data)
  - [x] HeadroomState derivation: `appState.sevenDay?.headroomState ?? .disconnected`
  - [x] Composition (VStack, spacing: 4):
    1. "7d" label: `Text("7d").font(.caption).foregroundStyle(.secondary)` (AC #3)
    2. `HeadroomRingGauge(headroomPercentage: headroom, windowLabel: "7d", ringSize: 56, strokeWidth: 4)` (AC #1-#2)
    3. `CountdownLabel(resetTime: appState.sevenDay?.resetsAt, headroomState: sevenDayState, countdownTick: appState.countdownTick)` (AC #4, #5)
  - [x] **Critical:** When `appState.sevenDay` is nil, the entire view body should return `EmptyView()` (AC #6 -- hide entirely, not grey/empty)
  - [x] Combined VoiceOver announcement (AC #7): `.accessibilityElement(children: .ignore)` with `.accessibilityLabel("7-day headroom: [X] percent, resets in [relative], at [absolute]")` -- mirroring FiveHourGaugeSection pattern
  - [x] NOTE: This view reuses `HeadroomRingGauge` and `CountdownLabel` from story 4.2 with no modifications to those components. Only the dimensions (56px/4px) and window label ("7d") differ.

- [x] Task 2: Update PopoverView.swift to replace "7d gauge" placeholder (AC: #1, #6)
  - [x] In `cc-hdrm/Views/PopoverView.swift`:
  - [x] Replace the `Text("7d gauge")` placeholder block (lines 21-24) with:
    ```swift
    // 7-day gauge section (hidden entirely when sevenDay is nil per AC #6)
    if appState.sevenDay != nil {
        Divider()

        SevenDayGaugeSection(appState: appState)
            .padding(.horizontal)
            .padding(.vertical, 8)
    }
    ```
  - [x] **Critical layout change:** The `Divider()` on line 19 (after 5h section) should be moved INSIDE the `if appState.sevenDay != nil` block. When 7d data is unavailable, neither the divider nor the gauge should appear. The divider belongs to the 7d section, not the 5h section.
  - [x] Keep the second `Divider()` (before footer) and footer placeholder intact (story 4.4)
  - [x] Ensure `appState.sevenDay` access registers observation so the section appears/disappears reactively

- [x] Task 3: Write SevenDayGaugeSection tests (AC: #1-#3, #6, #7)
  - [x] Create `cc-hdrmTests/Views/SevenDayGaugeSectionTests.swift`
  - [x] Test: Section renders with valid sevenDay data in AppState (no crash)
  - [x] Test: Section renders with nil sevenDay (verify empty/hidden behavior)
  - [x] Test: Section renders with exhausted (0%) sevenDay data
  - [x] Test: Section renders with various headroom states (normal, caution, warning, critical)
  - [x] Test: Verify HeadroomState derivation is correct for 7d window
  - [x] Use `@MainActor`, `@Test`, Swift Testing framework, consistent with story 4.2 test patterns

- [x] Task 4: Write PopoverView integration test for 7d gauge (AC: #1, #6)
  - [x] Extend `cc-hdrmTests/Views/PopoverViewTests.swift`:
  - [x] Test: PopoverView with valid sevenDay data in AppState renders 7d section without crash
  - [x] Test: PopoverView with nil sevenDay in AppState does NOT render 7d section
  - [x] Test: Updating AppState.sevenDay from nil to valid triggers observation and section appears
  - [x] Use `withObservationTracking` pattern from story 4.1/4.2

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. SevenDayGaugeSection is a pure presentational view -- read-only observer of AppState. Does NOT write to AppState.
- **State flow:** Services -> AppState -> PopoverView -> SevenDayGaugeSection -> HeadroomRingGauge/CountdownLabel
- **HeadroomState derivation:** Derived from `sevenDay.utilization` via `WindowState.headroomState` computed property. Never stored separately.
- **Concurrency:** All AppState access is `@MainActor`. Views run on main thread via SwiftUI. No concurrency concerns.
- **Logging:** No logging needed in view components.

### Key Behavioral Difference from Story 4.2

**This is the most important distinction:** When 7-day data is unavailable (nil), the entire 7d gauge section is **hidden** (`EmptyView()` / conditional rendering). This differs from the 5-hour gauge which shows a grey empty ring with an em dash when disconnected.

Rationale: The 5-hour gauge is the primary display and should always be visible (even showing "—" when disconnected). The 7-day gauge is secondary -- if there's no data for it, showing an empty placeholder wastes space and confuses users. Some API responses may not include 7-day data at all.

### Reuse from Story 4.2

All view components from story 4.2 are **fully reusable** with no modifications:
- `HeadroomRingGauge` -- accepts `ringSize` and `strokeWidth` parameters (56px/4px for 7d vs. 96px/7px for 5h)
- `CountdownLabel` -- accepts `resetTime`, `headroomState`, `countdownTick` (works identically for both windows)
- `HeadroomState+SwiftUI.swift` -- `swiftUIColor` property works for all states
- `Date+Formatting.swift` -- `countdownString()` and `absoluteTimeString()` handle all formatting including multi-day countdowns ("resets in 2d 1h")

No new extensions, no new models, no new formatting logic needed.

### Previous Story Intelligence (4.2)

**What was built:**
- `HeadroomRingGauge.swift` -- reusable, parameterized by ringSize/strokeWidth
- `CountdownLabel.swift` -- relative + absolute time, exhausted color emphasis, countdownTick observation
- `FiveHourGaugeSection.swift` -- composed view: "5h" label + ring gauge + countdown, combined VoiceOver
- `HeadroomState+SwiftUI.swift` -- `swiftUIColor` computed property in Extensions/
- `absoluteTimeString()` added to `Date+Formatting.swift`
- PopoverView updated with FiveHourGaugeSection replacing placeholder

**Code review lessons from story 4.2:**
- Cache DateFormatters (already done in absoluteTimeString)
- Provide single combined VoiceOver announcement per gauge section (accessibilityElement children: .ignore)
- Remove redundant accessibility values on disconnected states
- Test edge cases (negative headroom, locale-sensitive date assertions)

**Patterns to follow exactly:**
- SevenDayGaugeSection should mirror FiveHourGaugeSection structure
- Combined accessibility label on section level (children: .ignore)
- `let headroom = appState.sevenDay.map { 100.0 - $0.utilization }`
- Test pattern: instantiate views with AppState, verify no crash, use withObservationTracking

### Git Intelligence

Recent commits: one commit per story with code review fixes. XcodeGen auto-discovers new files in Views/ directory. Run `xcodegen generate` after adding new files.

### Project Structure Notes

- `Views/` directory already contains: PopoverView, HeadroomRingGauge, CountdownLabel, FiveHourGaugeSection, MenuBarTextRenderer, StatusMessageView
- New file goes in `cc-hdrm/Views/SevenDayGaugeSection.swift`
- New test file goes in `cc-hdrmTests/Views/SevenDayGaugeSectionTests.swift`
- Existing PopoverViewTests.swift gets additional test cases

### File Structure Requirements

New files to create:
```
cc-hdrm/Views/SevenDayGaugeSection.swift                # NEW -- composed 7d gauge section
cc-hdrmTests/Views/SevenDayGaugeSectionTests.swift       # NEW -- 7d gauge section tests
```

Files to modify:
```
cc-hdrm/Views/PopoverView.swift                         # REPLACE "7d gauge" placeholder with conditional SevenDayGaugeSection
cc-hdrmTests/Views/PopoverViewTests.swift                # ADD 7d gauge integration tests
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on any test touching AppState
- **SwiftUI view tests:** Instantiate views with AppState, verify they render without crash. Full visual testing is out of scope.
- **Observation tests:** Use `withObservationTracking` pattern from story 4.1/4.2 to verify gauge section appears/disappears when AppState.sevenDay changes.
- **Key test scenario:** Verify the conditional rendering -- when `appState.sevenDay` is nil, SevenDayGaugeSection should produce an empty view. When sevenDay has data, it should render the gauge.
- **All 199+ existing tests must continue passing (zero regressions).**

### Library & Framework Requirements

- `SwiftUI` -- SevenDayGaugeSection (already used in project)
- No new dependencies. Zero external packages.

### Anti-Patterns to Avoid

- DO NOT show a grey/empty ring when 7d data is unavailable -- hide the section entirely (AC #6)
- DO NOT modify HeadroomRingGauge.swift or CountdownLabel.swift -- they're already reusable
- DO NOT store HeadroomState as a property -- always derive from utilization
- DO NOT add the footer in this story -- that's story 4.4
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` -- protected file
- DO NOT use `DispatchQueue` or timers -- use existing countdownTick observation pattern
- DO NOT use `print()` -- use `os.Logger` if logging is needed (shouldn't be in views)
- DO NOT hardcode colors -- use semantic color tokens from Color+Headroom.swift

### References

- [Source: epics.md#Story 4.3] -- Full acceptance criteria
- [Source: ux-design-specification.md#HeadroomRingGauge] -- Ring gauge specs: 56px diameter, 4px stroke for secondary gauge
- [Source: ux-design-specification.md#CountdownLabel] -- Relative + absolute time display, formatting rules
- [Source: ux-design-specification.md#Spacing & Layout Foundation] -- Popover structure: 7d gauge secondary, stacked below 5h
- [Source: ux-design-specification.md#Accessibility Considerations] -- VoiceOver labels, reduced motion, color independence
- [Source: architecture.md#App Architecture] -- MVVM, Views observe AppState read-only
- [Source: architecture.md#Format Patterns] -- Date/time formatting rules, Date+Formatting.swift
- [Source: architecture.md#Accessibility Patterns] -- .accessibilityLabel, .accessibilityValue, color + number + weight triple-encoding
- [Source: architecture.md#State Management Patterns] -- HeadroomState derived from utilization, never stored
- [Source: project-context.md#Date/Time Formatting] -- Countdown and absolute time formatting rules
- [Source: AppState.swift:42] -- `sevenDay: WindowState?` property
- [Source: AppState.swift:67-82] -- displayedWindow logic referencing sevenDay
- [Source: AppState.swift:124-128] -- updateWindows method sets both fiveHour and sevenDay
- [Source: HeadroomRingGauge.swift] -- Reusable gauge, accepts ringSize/strokeWidth parameters
- [Source: CountdownLabel.swift] -- Reusable countdown, accepts resetTime/headroomState/countdownTick
- [Source: FiveHourGaugeSection.swift] -- Pattern to mirror for SevenDayGaugeSection
- [Source: PopoverView.swift:21-24] -- Current "7d gauge" placeholder to replace
- [Source: story 4-2] -- Previous story patterns, test patterns, code review lessons

## Dev Agent Record

### Agent Model Used

claude-opus-4-5 (Claude Code)

### Debug Log References

None required — no issues encountered.

### Completion Notes List

- Created SevenDayGaugeSection.swift mirroring FiveHourGaugeSection pattern: VStack with "7d" label, HeadroomRingGauge (56px/4px), CountdownLabel, combined VoiceOver accessibility label
- Conditional rendering via `@ViewBuilder`: returns content only when `appState.sevenDay != nil`, otherwise produces empty view (AC #6)
- Updated PopoverView.swift: replaced `Text("7d gauge")` placeholder with conditional `SevenDayGaugeSection`; moved divider inside the `if` block so neither divider nor gauge appear when 7d data is nil
- Created 8 unit tests in SevenDayGaugeSectionTests.swift covering: valid data, nil data (hidden), exhausted state, all headroom states (normal/caution/warning/critical), and HeadroomState derivation
- Added 3 integration tests to PopoverViewTests.swift: valid 7d rendering, nil 7d hidden, observation tracking for sevenDay changes
- All 212 tests pass (0 regressions, 13 new tests added)
- No modifications to HeadroomRingGauge, CountdownLabel, or any other existing components
- No new dependencies added
- XcodeGen project regenerated successfully

### Change Log

- 2026-02-01: Implemented story 4.3 — 7-day headroom ring gauge with countdown in popover
- 2026-02-01: Code review fixes — removed unused `import os` from SevenDayGaugeSectionTests.swift, corrected File List (removed gitignored xcodeproj, added sprint-status.yaml)

### File List

New:
- cc-hdrm/Views/SevenDayGaugeSection.swift
- cc-hdrmTests/Views/SevenDayGaugeSectionTests.swift

Modified:
- cc-hdrm/Views/PopoverView.swift
- cc-hdrmTests/Views/PopoverViewTests.swift
- _bmad-output/implementation-artifacts/sprint-status.yaml (status: backlog → review)
