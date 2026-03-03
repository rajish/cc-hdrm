# Story 4.6: Clickable Ring Gauges as Analytics Launchers

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to click a ring gauge in the popover to open analytics for that time window,
so that I can drill into detailed trends directly from the element I'm already looking at.

## Acceptance Criteria

1. **Given** the 5h ring gauge section is visible in the popover, **When** Alex clicks/taps anywhere in the 5h gauge section, **Then** the analytics window opens (or comes to front) with "24h" time range pre-selected, **And** the popover remains open, **And** a subtle hover state indicates the gauge section is clickable, **And** cursor changes to pointer (hand) on hover.

2. **Given** the 7d ring gauge section is visible in the popover, **When** Alex clicks/taps anywhere in the 7d gauge section, **Then** the analytics window opens (or comes to front) with "7d" time range pre-selected, **And** the popover remains open, **And** a subtle hover state indicates the gauge section is clickable, **And** cursor changes to pointer (hand) on hover.

3. **Given** the analytics window is already open, **When** Alex clicks a ring gauge, **Then** the analytics window comes to front and switches to the corresponding time range, **And** no duplicate window is created.

4. **Given** historical data is unavailable (no SQLite data yet / historicalDataService is nil), **When** Alex clicks a ring gauge, **Then** the click does nothing (no error, no empty window).

5. **Given** a VoiceOver user focuses a ring gauge section, **When** VoiceOver reads the element, **Then** it includes "Double-tap to open analytics" in the accessibility hint.

## Tasks / Subtasks

- [x] Task 1: Add `show(timeRange:)` method to AnalyticsWindow (AC: 1, 2, 3)
  - [x] Add `requestedAnalyticsTimeRange` property to `AppState` with setter method `setRequestedAnalyticsTimeRange(_:)`
  - [x] Add `show(timeRange: TimeRange)` to `AnalyticsWindow` that sets `appState.requestedAnalyticsTimeRange` then opens/brings to front
  - [x] Add `.onChange(of: appState.requestedAnalyticsTimeRange)` to `AnalyticsView` to update `@State selectedTimeRange`
  - [x] Existing `toggle()` behavior unchanged — Sparkline still uses it

- [x] Task 2: Extract shared InteractionOverlay from Sparkline (AC: 1, 2)
  - [x] Create `cc-hdrm/Views/InteractionOverlay.swift` — extract `SparklineInteractionOverlay` + `SparklineInteractionNSView` to generic `InteractionOverlay` + `InteractionNSView`
  - [x] Parameters: `onTap: (() -> Void)?`, `onHoverChange: ((Bool) -> Void)?`
  - [x] Same NSViewRepresentable pattern: `resetCursorRects`, `updateTrackingAreas`, `cursorUpdate`, `mouseEntered`/`mouseExited`, `mouseUp`, `acceptsFirstMouse`
  - [x] Update `Sparkline.swift` to use `InteractionOverlay` instead of private `SparklineInteractionOverlay`
  - [x] Delete private `SparklineInteractionOverlay` and `SparklineInteractionNSView` from `Sparkline.swift`
  - [x] Run `xcodegen generate` after adding new file

- [x] Task 3: Add click handling and hover state to FiveHourGaugeSection (AC: 1, 4, 5)
  - [x] Add `var onTap: (() -> Void)? = nil` parameter to `FiveHourGaugeSection`
  - [x] Add `@State private var isHovered: Bool = false`
  - [x] Wrap body VStack with hover background: `.background(isHovered ? Color(nsColor: .quaternarySystemFill).opacity(0.3) : Color.clear)`
  - [x] Add `.cornerRadius(6)` for subtle rounded hover highlight
  - [x] Add `.contentShape(Rectangle())` for full-section hit testing
  - [x] Add `.overlay(InteractionOverlay(onTap: { onTap?() }, onHoverChange: { isHovered = $0 }))` when `onTap != nil`
  - [x] Add `.accessibilityHint(onTap != nil ? "Double-tap to open analytics" : "")` (AC 5)

- [x] Task 4: Add click handling and hover state to SevenDayGaugeSection (AC: 2, 4, 5)
  - [x] Same changes as Task 3 applied to `SevenDayGaugeSection`
  - [x] Add `var onTap: (() -> Void)? = nil` parameter
  - [x] Add `@State private var isHovered: Bool = false`
  - [x] Same hover background, cornerRadius, contentShape, overlay, accessibility hint

- [x] Task 5: Wire ring gauge clicks in PopoverView (AC: 1, 2, 3, 4)
  - [x] Update `FiveHourGaugeSection` instantiation in `authenticatedView`:
    ```swift
    FiveHourGaugeSection(
        appState: appState,
        onTap: historicalDataService != nil ? { AnalyticsWindow.shared.show(timeRange: .day) } : nil
    )
    ```
  - [x] Update `SevenDayGaugeSection` instantiation in `authenticatedView`:
    ```swift
    SevenDayGaugeSection(
        appState: appState,
        onTap: historicalDataService != nil ? { AnalyticsWindow.shared.show(timeRange: .week) } : nil
    )
    ```
  - [x] Guard: pass `nil` for `onTap` when `historicalDataService == nil` (AC 4) — no hover, no cursor, no hint

- [x] Task 6: Write tests (AC: 1-5)
  - [x] `cc-hdrmTests/Views/InteractionOverlayTests.swift` (NEW) — instantiation test for `InteractionOverlay` via `NSHostingView`
  - [x] Extend `cc-hdrmTests/Views/FiveHourGaugeSectionTests.swift`:
    - Test: renders with onTap callback without crash
    - Test: renders without onTap callback without crash
    - Test: accessibility hint present when onTap provided
    - Test: accessibility hint absent when onTap is nil
  - [x] Extend `cc-hdrmTests/Views/SevenDayGaugeSectionTests.swift`:
    - Same tests as FiveHourGaugeSection
  - [x] Extend `cc-hdrmTests/Views/AnalyticsWindowTests.swift`:
    - Test: `show(timeRange: .day)` opens window
    - Test: `show(timeRange: .week)` opens window
    - Test: `show(timeRange:)` when already open brings to front (no duplicate)
  - [x] Extend `cc-hdrmTests/Views/PopoverViewTests.swift`:
    - Test: renders without crash when historicalDataService is nil
    - Test: renders without crash when historicalDataService is provided
  - [x] Verify all existing tests pass (zero regressions)

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. Ring gauge sections are presentational views that receive an optional `onTap` callback. PopoverView decides whether to wire the callback based on data availability. AnalyticsWindow is the controller that manages the analytics panel.
- **State flow for time range:** PopoverView click → `AnalyticsWindow.show(timeRange:)` → `AppState.requestedAnalyticsTimeRange` → AnalyticsView observes via `.onChange` and updates `@State selectedTimeRange` → `.task(id: selectedTimeRange)` reloads data.
- **Concurrency:** All interactions are synchronous tap handlers on `@MainActor`. No async work for the click itself.

### Key Implementation Details

**AnalyticsWindow.show(timeRange:) — Use AppState as communication channel:**

This follows the existing MVVM reactive pattern (controller → AppState → View). The `AnalyticsView` already reloads data via `.task(id: selectedTimeRange)` when the range changes, so updating the range reactively works seamlessly.

```swift
// AppState.swift — add property + setter (follow setAnalyticsWindowOpen pattern at line 304)
private(set) var requestedAnalyticsTimeRange: TimeRange = .week

func setRequestedAnalyticsTimeRange(_ timeRange: TimeRange) {
    self.requestedAnalyticsTimeRange = timeRange
}
```

```swift
// AnalyticsWindow.swift — add show(timeRange:) alongside existing toggle()
func show(timeRange: TimeRange) {
    guard appState != nil else {
        assertionFailure("show(timeRange:) called before configure()")
        Self.logger.error("show(timeRange:) called before configure() - ignoring")
        return
    }
    appState?.setRequestedAnalyticsTimeRange(timeRange)
    if let panel, panel.isVisible {
        Self.logger.info("Analytics window switching to \(timeRange.displayLabel) and bringing to front")
        panel.orderFront(nil)
    } else {
        Self.logger.info("Analytics window opening at \(timeRange.displayLabel)")
        openWindow()
    }
}
```

```swift
// AnalyticsView.swift — add onChange handler (alongside existing .task(id:) at line 95)
.onChange(of: appState.requestedAnalyticsTimeRange) { _, newRange in
    selectedTimeRange = newRange
}
```

**Why AppState approach, not close/reopen:** No visual flash when switching time range on an already-open window. The `.task(id: selectedTimeRange)` handler already reloads data on range change.

**InteractionOverlay — Extract from Sparkline, don't duplicate:**

The `SparklineInteractionOverlay` + `SparklineInteractionNSView` in `Sparkline.swift` (lines 465-535) provides exactly the cursor, hover, and click handling needed. This ~70-line NSViewRepresentable handles three macOS-specific edge cases documented in comments (lines 462-464):
1. `.onHover` + `NSCursor.push()/pop()` — cursor stack corrupted on window changes
2. `.onHover` + `NSCursor.set()` — overridden by cursor rect system of key window
3. `addCursorRect` + `window?.makeKey()` — makeKey doesn't stick for popover windows

Extract to shared `InteractionOverlay` rather than duplicating. The implementation is identical — only the type name changes.

**Data availability guard:**

Pass `onTap: nil` when `historicalDataService == nil`. When `onTap` is nil:
- No `InteractionOverlay` rendered (no cursor change)
- No hover background
- No accessibility hint
- Ring gauges render as purely visual (existing behavior)

This is a synchronous guard at the PopoverView level — no async checks needed.

**Hover visual feedback:**

Use `Color(nsColor: .quaternarySystemFill).opacity(0.3)` — matches the Sparkline hover pattern (`Sparkline.swift` line 385). Add `.cornerRadius(6)` for a subtle rounded highlight that feels like a button affordance without looking like a standard button.

**Popover remains open on click:**

NSPopover doesn't close on internal clicks — this is existing behavior. Sparkline clicks don't close the popover, and ring gauge clicks won't either. No special handling needed.

### Previous Story Intelligence (4.5)

**What was built:**
- StatusMessageView.swift — pure presentational component (title + detail)
- PopoverView extended with `resolvedStatusMessage` computed property
- Pattern: views take simple value parameters, logic lives in parent

**Code review lessons from 4.5:**
- Use `.foregroundStyle()` not deprecated `.foregroundColor()`
- Test names should honestly reflect what they validate
- File List should not include gitignored files (xcodeproj)
- Follow existing section patterns: VStack, padding, accessibility

**Patterns to follow exactly:**
- Views take `appState: AppState` + optional callbacks
- `@MainActor` on all tests touching AppState
- Use `@Test`, `#expect`, `@Suite` from Swift Testing framework
- Run `xcodegen generate` after adding new files

### Git Intelligence

Recent commits:
```
bf263a5 fix: exclude current partial month from chronic underpowering detection
50512a2 fix: gate onboarding with keychain check for existing user upgrades
ebee8c1 feat: add first-run onboarding popup, update README and app icon
384cf95 chore: update changelog for v1.4.4 [skip ci]
3569a3a [patch] fix: changelog generation uses wrong git log range
```

Pattern: One feature commit, followed by fix commits from code review. XcodeGen auto-discovers new files in `cc-hdrm/` and `cc-hdrmTests/`.

### Project Structure Notes

- `Views/` currently contains: PopoverView, PopoverFooterView, GearMenuView, HeadroomRingGauge, CountdownLabel, FiveHourGaugeSection, SevenDayGaugeSection, Sparkline, StatusMessageView, AnalyticsView, AnalyticsWindow, ExtraUsageCardView, UpdateBadgeView, and more
- **InteractionOverlay.swift does NOT exist yet** — this story creates it (extracted from Sparkline.swift)
- Ring gauge sections are simple VStack compositions with no existing interaction handling

### File Structure Requirements

New files to create:
```
cc-hdrm/Views/InteractionOverlay.swift                    # NEW — shared cursor/click/hover overlay
cc-hdrmTests/Views/InteractionOverlayTests.swift           # NEW — instantiation tests
```

Files to modify:
```
cc-hdrm/State/AppState.swift                               # ADD requestedAnalyticsTimeRange property + setter
cc-hdrm/Views/AnalyticsWindow.swift                        # ADD show(timeRange:) method
cc-hdrm/Views/AnalyticsView.swift                          # ADD .onChange(of: appState.requestedAnalyticsTimeRange)
cc-hdrm/Views/FiveHourGaugeSection.swift                   # ADD onTap, hover state, overlay, accessibility hint
cc-hdrm/Views/SevenDayGaugeSection.swift                   # ADD onTap, hover state, overlay, accessibility hint
cc-hdrm/Views/PopoverView.swift                            # WIRE onTap closures with historicalDataService guard
cc-hdrm/Views/Sparkline.swift                              # REFACTOR to use shared InteractionOverlay
cc-hdrmTests/Views/FiveHourGaugeSectionTests.swift         # ADD onTap + accessibility hint tests
cc-hdrmTests/Views/SevenDayGaugeSectionTests.swift         # ADD onTap + accessibility hint tests
cc-hdrmTests/Views/AnalyticsWindowTests.swift              # ADD show(timeRange:) tests
cc-hdrmTests/Views/PopoverViewTests.swift                  # ADD historicalDataService guard tests
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on any test touching AppState
- **SwiftUI view tests:** Instantiate views with parameters, verify no crash. Full visual testing out of scope.
- **Key test scenarios:**
  - InteractionOverlay renders via NSHostingView without crash
  - FiveHourGaugeSection with/without onTap callback — both render
  - SevenDayGaugeSection with/without onTap callback — both render
  - Accessibility hint present when onTap provided, absent when nil
  - AnalyticsWindow.show(timeRange:) opens window
  - AnalyticsWindow.show(timeRange:) on already-open window brings to front
  - PopoverView renders correctly with/without historicalDataService
- **All existing tests must continue passing (zero regressions)**

### Library & Framework Requirements

- `SwiftUI` — Views (already used)
- `AppKit` — `NSViewRepresentable` for InteractionOverlay (already used in Sparkline)
- No new dependencies. Zero external packages.

### Anti-Patterns to Avoid

- DO NOT add click handling to `HeadroomRingGauge` — it's a reusable pure-display component; interaction belongs at the Section level
- DO NOT duplicate `SparklineInteractionOverlay` code — extract to shared `InteractionOverlay`
- DO NOT use SwiftUI `.onHover` + `NSCursor.push()/pop()` for cursor — doesn't work reliably in NSPopover (see `Sparkline.swift` lines 462-464)
- DO NOT close/reopen analytics window to switch time range — use AppState reactive update
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT use `DispatchQueue` or timers — all interactions are synchronous on @MainActor
- DO NOT use `print()` — use `os.Logger` if logging needed
- DO NOT use deprecated `.foregroundColor()` — use `.foregroundStyle()`
- DO NOT add click handler when `historicalDataService` is nil — pass `onTap: nil`

### References

- [Source: _bmad-output/planning-artifacts/epics/epic-4-detailed-usage-panel.md - Story 4.6] — Full acceptance criteria and implementation note
- [Source: _bmad-output/planning-artifacts/sprint-change-proposal-2026-03-02.md - Change 1] — Ring click proposal, PRD amendments, UX updates
- [Source: cc-hdrm/Views/AnalyticsWindow.swift:47-62] — Current `toggle()` method
- [Source: cc-hdrm/Views/AnalyticsWindow.swift:80-119] — `createPanel()` creates AnalyticsView with default time range
- [Source: cc-hdrm/Views/AnalyticsWindow.swift:123-131] — `windowWillClose` nils panel for fresh @State on reopen
- [Source: cc-hdrm/Views/AnalyticsView.swift:30] — `@State private var selectedTimeRange: TimeRange = .week`
- [Source: cc-hdrm/Views/AnalyticsView.swift:95] — `.task(id: selectedTimeRange)` reloads data on range change
- [Source: cc-hdrm/Views/Sparkline.swift:465-535] — `SparklineInteractionOverlay` — cursor/click/hover reference implementation
- [Source: cc-hdrm/Views/Sparkline.swift:385-386] — Sparkline hover background pattern
- [Source: cc-hdrm/Views/FiveHourGaugeSection.swift:5-58] — Current section, no interaction
- [Source: cc-hdrm/Views/SevenDayGaugeSection.swift:6-73] — Current section, no interaction
- [Source: cc-hdrm/Views/PopoverView.swift:108-120] — Current gauge section instantiation
- [Source: cc-hdrm/Views/PopoverView.swift:132-137] — Sparkline `onTap` wiring pattern
- [Source: cc-hdrm/Models/TimeRange.swift] — `.day` (24h), `.week` (7d), `.month` (30d), `.all`
- [Source: cc-hdrm/State/AppState.swift:74] — `isAnalyticsWindowOpen` property
- [Source: cc-hdrm/State/AppState.swift:304-305] — `setAnalyticsWindowOpen()` setter pattern
- [Source: _bmad-output/planning-artifacts/project-context.md] — MVVM, @Observable, zero external deps

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

None — clean implementation, no debugging required.

### Completion Notes List

- Task 1: Added `requestedAnalyticsTimeRange` property + `setRequestedAnalyticsTimeRange(_:)` setter to AppState. Added `show(timeRange:)` to AnalyticsWindow that sets the requested range then opens/brings-to-front. Added `.onChange(of: appState.requestedAnalyticsTimeRange)` to AnalyticsView to update `@State selectedTimeRange`. Existing `toggle()` unchanged.
- Task 2: Extracted `SparklineInteractionOverlay` + `SparklineInteractionNSView` from Sparkline.swift into shared `InteractionOverlay` + `InteractionNSView` in new file. Updated Sparkline to use shared component. Deleted ~70 lines of private duplicate code.
- Task 3: Added `onTap` parameter, `@State isHovered`, hover background, cornerRadius, contentShape, conditional InteractionOverlay, and conditional accessibility hint to FiveHourGaugeSection.
- Task 4: Same changes as Task 3 applied to SevenDayGaugeSection.
- Task 5: Wired `onTap` closures in PopoverView — 5h→`.day`, 7d→`.week`. Guard: `onTap: nil` when `historicalDataService == nil`.
- Task 6: Created InteractionOverlayTests (2 tests), FiveHourGaugeSectionTests (6 tests), extended SevenDayGaugeSectionTests (+4 tests), AnalyticsWindowTests (+3 tests), PopoverViewTests (+2 tests). All 1377 tests pass, zero regressions.

### Change Log

- 2026-03-03: Story 4.6 implementation complete — clickable ring gauges as analytics launchers
- 2026-03-03: Code review — fixed 4 issues (2 MEDIUM, 2 LOW): reset requestedAnalyticsTimeRange on window close to preserve toggle() default behavior, renamed misleading accessibility hint test names, swapped .onAppear/.task(id:) order to avoid wasted data load

### File List

New files:
- cc-hdrm/Views/InteractionOverlay.swift
- cc-hdrmTests/Views/InteractionOverlayTests.swift
- cc-hdrmTests/Views/FiveHourGaugeSectionTests.swift

Modified files:
- cc-hdrm/State/AppState.swift
- cc-hdrm/Views/AnalyticsWindow.swift
- cc-hdrm/Views/AnalyticsView.swift
- cc-hdrm/Views/FiveHourGaugeSection.swift
- cc-hdrm/Views/SevenDayGaugeSection.swift
- cc-hdrm/Views/PopoverView.swift
- cc-hdrm/Views/Sparkline.swift
- cc-hdrmTests/Views/SevenDayGaugeSectionTests.swift
- cc-hdrmTests/Views/AnalyticsWindowTests.swift
- cc-hdrmTests/Views/PopoverViewTests.swift
- _bmad-output/implementation-artifacts/sprint-status.yaml
- _bmad-output/implementation-artifacts/4-6-clickable-ring-gauges-analytics-launcher.md
