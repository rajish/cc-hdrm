---
title: 'Menu Bar Gauge Icon'
slug: 'menu-bar-gauge-icon'
created: '2026-02-04'
status: 'completed'
stepsCompleted: [1, 2, 3, 4]
tech_stack: [Swift, AppKit, NSImage, NSBezierPath, NSColor]
files_to_modify:
  - cc-hdrm/Views/GaugeIcon.swift (new)
  - cc-hdrm/App/AppDelegate.swift:255-314
  - cc-hdrmTests/Views/GaugeIconTests.swift (new)
code_patterns:
  - NSColor.headroomColor(for:) for state-based color resolution (Color+Headroom.swift:9-19)
  - NSFont.menuBarFont(for:) for state-based font weight
  - withObservationTracking + AsyncStream for reactive menu bar updates
  - WindowState.utilization for headroom data access
  - HeadroomState derivation via HeadroomState(from: utilization)
  - statusItem?.button?.attributedTitle for text display
  - statusItem?.button?.image for icon display
test_patterns:
  - Swift Testing framework (@Suite, @Test, #expect)
  - @MainActor for UI component tests
  - Tests mirror source structure under cc-hdrmTests/Views/
  - Boundary value testing for state thresholds
  - Instantiation + body access pattern for SwiftUI view tests
---

# Tech-Spec: Menu Bar Gauge Icon

**Created:** 2026-02-04

## Overview

### Problem Statement

The current menu bar indicator uses a static sparkle icon (✳) that doesn't convey headroom state visually. Users must read the percentage text to understand their current usage status. A visual gauge would provide at-a-glance state recognition through color and fill level.

### Solution

Replace the sparkle (✳) icon with a dynamically drawn semicircular gauge icon that reflects headroom at a glance. The gauge shows:
- Fill level corresponding to headroom percentage
- Color matching the current `HeadroomState` (normal/caution/warning/critical/exhausted)
- The percentage/countdown text remains unchanged beside the gauge

The gauge respects the existing window promotion logic — it displays whichever window (5h or 7d) is currently shown in the menu bar.

### Scope

**In Scope:**
- Create gauge drawing function that produces `NSImage` for given headroom/state
- Replace sparkle icon with gauge in `AppDelegate.updateMenuBarDisplay()`
- Respect `AppState.displayedWindow` for 5h/7d promotion
- Show 0% fill state when exhausted (countdown text remains as-is)
- Show distinct "X" or error icon for disconnected state (not a gauge)
- Maintain accessibility parity with current implementation
- Unit tests for gauge geometry and color mapping

**Out of Scope:**
- Removing or changing the percentage/countdown text
- Adding countdown information to the gauge itself
- Changing text formatting or font weights

## Context for Development

### Codebase Patterns

- **State access:** `AppState.displayedWindow` determines which window (5h/7d) is shown; `menuBarHeadroomState` is the derived state
- **Headroom calculation:** Headroom = 100 - utilization. `WindowState.utilization` is the API value; derive headroom from it
- **Color resolution:** `NSColor.headroomColor(for: HeadroomState)` already exists in `Color+Headroom.swift:9-19` — use this, don't recreate
- **Font resolution:** `NSFont.menuBarFont(for: HeadroomState)` exists for state-based font weights
- **Observation:** `withObservationTracking` + `AsyncStream` pattern in `startObservingAppState()` handles reactive updates — gauge will redraw automatically when AppState changes
- **Accessibility:** Current implementation sets both `accessibilityLabel` and `accessibilityValue` on the status button
- **Menu bar display:** Currently sets `statusItem?.button?.attributedTitle` for text; gauge will set `statusItem?.button?.image` for icon

### Files to Reference

| File | Purpose |
| ---- | ------- |
| `cc-hdrm/App/AppDelegate.swift:255-314` | `updateMenuBarDisplay()` — where gauge integration happens |
| `cc-hdrm/State/AppState.swift:41-42` | `fiveHour: WindowState?`, `sevenDay: WindowState?` — actual data source |
| `cc-hdrm/State/AppState.swift:70-85` | `displayedWindow` promotion logic (7d promotes when tighter AND warning/critical) |
| `cc-hdrm/State/AppState.swift:89-100` | `menuBarHeadroomState` derivation |
| `cc-hdrm/State/AppState.swift:103-118` | `menuBarText` — shows `✳ XX%` or `✳ ↻ Xm` countdown |
| `cc-hdrm/Models/HeadroomState.swift:16-36` | `HeadroomState.init(from: Double?)` — threshold derivation |
| `cc-hdrm/Models/HeadroomState.swift:39-48` | `colorTokenName` — maps state to asset catalog name |
| `cc-hdrm/Extensions/Color+Headroom.swift:9-19` | `NSColor.headroomColor(for:)` — reuse this |
| `cc-hdrm/Views/HeadroomRingGauge.swift` | Existing SwiftUI gauge — reference for pattern (uses `headroomPercentage: Double?`) |
| `cc-hdrmTests/Views/HeadroomRingGaugeTests.swift` | Test pattern reference — boundary testing, @MainActor, #expect |
| `_bmad-output/planning-artifacts/gauge-icon-preview.html` | Visual reference with geometry formulas |

### Technical Decisions

- **Canvas size:** 18×18pt (renders @2x on Retina as 36×36px) — validated in HTML preview
- **Drawing API:** `NSImage(size:flipped:drawingHandler:)` with `NSBezierPath` arcs — no static assets
- **Color source:** Use existing `NSColor.headroomColor(for:)` — resolves from Asset Catalog with fallbacks
- **Template mode:** `NSImage.isTemplate = false` — gauge uses semantic colors, not system tinting
- **Disconnected icon:** Distinct "X" glyph in gray, not a gauge — clearly different visual language
- **Gauge replaces sparkle only:** Text percentage/countdown remains unchanged

**Gauge Geometry (from HTML preview):**
```
Canvas: 18×18pt (36×36 @2x coordinate space)
Arc center: (cx, cy) = (18, 24) in @2x coords
Arc radius: r = 14
Needle length: ~10 (≈0.71 × r)
Stroke width: 3-3.5pt (track/fill), 2-2.5pt (needle)
Center dot radius: 2.5-3pt

Angle formula for headroom p (0.0–1.0):
  θ = π × (1 − p)
  arcEnd    = (cx + r·cos(θ), cy − r·sin(θ))
  needleEnd = (cx + needleLen·cos(θ), cy − needleLen·sin(θ))

Direction: 100% → needle right (3 o'clock), 0% → needle left (9 o'clock)

Elements drawn in order:
  1. Track arc — full semicircle, state color at 25% opacity
  2. Fill arc — partial semicircle from left to arcEnd, state color
  3. Needle line — from center to needleEnd, state color
  4. Center dot — small filled circle at center, state color
```

**HeadroomState Thresholds (from HeadroomState.swift:24-35):**
| State | Utilization | Headroom | Notes |
| ----- | ----------- | -------- | ----- |
| `.exhausted` | ≥ 100% | ≤ 0% | Show 0% fill, needle left |
| `.critical` | 95% to <100% | 0% to <5% | Red |
| `.warning` | 80% to <95% | 5% to <20% | Orange |
| `.caution` | 60% to 80% | 20% to 40% | Yellow (inclusive) |
| `.normal` | < 60% | > 40% | Green |
| `.disconnected` | nil | nil | Show "X" icon instead |

## Implementation Plan

### Tasks

#### Task 1: Create GaugeIcon drawing functions

- **File:** `cc-hdrm/Views/GaugeIcon.swift` (new)
- **Action:** Create a new file with two public functions:
  1. `makeGaugeIcon(headroomPercentage: Double, state: HeadroomState) -> NSImage` — draws the semicircular gauge
  2. `makeDisconnectedIcon() -> NSImage` — draws the "X" icon for disconnected state
- **Implementation details:**
  - Use `NSImage(size: NSSize(width: 18, height: 18), flipped: false, drawingHandler:)` for image creation
  - Use `NSBezierPath` for arc and line drawing
  - Call `NSColor.headroomColor(for: state)` to get the color — do NOT recreate color logic
  - Set `image.isTemplate = false` before returning
  - Geometry constants (in 18pt canvas, scale by 0.5 from HTML preview's 36pt coords):
    - Arc center: (9, 12)
    - Arc radius: 7
    - Needle length: 5
    - Stroke width: 1.5 (track/fill), 1.25 (needle)
    - Center dot radius: 1.25
  - Angle calculation: `θ = π × (1 − headroomPercentage/100)`
  - Draw order: track arc (25% opacity) → fill arc → needle → center dot
- **Notes:** Pure functions, no state — suitable for unit testing

#### Task 2: Create disconnected "X" icon

- **File:** `cc-hdrm/Views/GaugeIcon.swift` (same file as Task 1)
- **Action:** Implement `makeDisconnectedIcon()` function
- **Implementation details:**
  - Same 18×18pt canvas
  - Draw two diagonal lines forming an "X" in `.disconnected` color (gray)
  - Center the X in the canvas, similar visual weight to gauge
  - `isTemplate = false`
- **Notes:** Visually distinct from gauge — users instantly recognize disconnected state

#### Task 3: Integrate gauge into menu bar display

- **File:** `cc-hdrm/App/AppDelegate.swift:255-314`
- **Action:** Modify `updateMenuBarDisplay()` to:
  1. Compute headroom from displayed window: `let headroom = 100.0 - (window?.utilization ?? 0)`
  2. Generate appropriate icon based on state:
     - If `state == .disconnected`: use `makeDisconnectedIcon()`
     - Otherwise: use `makeGaugeIcon(headroomPercentage: headroom, state: state)`
  3. Set `statusItem?.button?.image = icon`
  4. Modify text to remove sparkle prefix: change from `"✳ XX%"` to `"XX%"` (strip `"\u{2733} "`)
- **Implementation details:**
  - Add `import` for GaugeIcon if needed (same module, should be automatic)
  - Keep all existing accessibility logic unchanged
  - Keep all existing font/color logic for text unchanged
  - The observation mechanism already triggers redraw on state changes — no new subscription needed
- **Notes:** Minimal change to existing function; gauge icon + stripped text replaces sparkle + text

#### Task 4: Update menuBarText to remove sparkle prefix

- **File:** `cc-hdrm/State/AppState.swift:103-118`
- **Action:** Modify `menuBarText` computed property to NOT include the sparkle prefix
- **Current:** Returns `"\u{2733} XX%"` or `"\u{2733} ↻ Xm"` or `"\u{2733} \u{2014}"`
- **New:** Returns `"XX%"` or `"↻ Xm"` or `"\u{2014}"` (em dash only for disconnected)
- **Notes:** Sparkle is now provided by the gauge icon, not the text

#### Task 5: Add unit tests for gauge drawing

- **File:** `cc-hdrmTests/Views/GaugeIconTests.swift` (new)
- **Action:** Create test suite covering:
  1. Gauge returns non-nil NSImage of correct size (18×18pt)
  2. Gauge at 0% has needle pointing left (angle = π)
  3. Gauge at 50% has needle pointing up (angle = π/2)
  4. Gauge at 100% has needle pointing right (angle = 0)
  5. Each HeadroomState produces valid image with `isTemplate = false`
  6. Disconnected icon returns non-nil NSImage of correct size
  7. Disconnected icon has `isTemplate = false`
- **Test patterns:**
  - Use Swift Testing framework (`@Suite`, `@Test`, `#expect`)
  - No `@MainActor` needed — these are pure functions
  - Test geometry via angle calculation helper (extract if needed for testability)
- **Notes:** Focus on output validity and geometry correctness, not pixel-level rendering

### Acceptance Criteria

#### Gauge Drawing (Task 1)

- [x] **AC1:** Given headroom of 100%, when `makeGaugeIcon` is called, then the returned image is 18×18pt and the needle angle equals 0 (pointing right)
- [x] **AC2:** Given headroom of 0%, when `makeGaugeIcon` is called, then the returned image is 18×18pt and the needle angle equals π (pointing left)
- [x] **AC3:** Given headroom of 50%, when `makeGaugeIcon` is called, then the needle angle equals π/2 (pointing up)
- [x] **AC4:** Given any `HeadroomState` (.normal, .caution, .warning, .critical, .exhausted), when `makeGaugeIcon` is called with that state, then the image uses the color from `NSColor.headroomColor(for:)`
- [x] **AC5:** Given any gauge image, when `isTemplate` is inspected, then it is `false`

#### Disconnected Icon (Task 2)

- [x] **AC6:** Given disconnected state, when `makeDisconnectedIcon` is called, then the returned image is 18×18pt with `isTemplate = false`
- [x] **AC7:** Given disconnected state, when the icon is displayed, then it shows an "X" glyph visually distinct from the gauge

#### Menu Bar Integration (Tasks 3 & 4)

- [x] **AC8:** Given the app launches with valid credentials, when the status item appears, then it displays the gauge icon followed by percentage text (no sparkle)
- [x] **AC9:** Given `AppState.menuBarHeadroomState` is `.disconnected`, when the menu bar updates, then it shows the "X" icon followed by an em dash
- [x] **AC10:** Given `AppState.displayedWindow` is `.sevenDay` (7d promoted), when the gauge renders, then it reflects the 7-day headroom, not 5-hour
- [x] **AC11:** Given headroom state is `.exhausted`, when the menu bar updates, then the gauge shows 0% fill and text shows countdown (e.g., "↻ 47m")
- [x] **AC12:** Given headroom changes from 67% to 30%, when the observation fires, then the gauge redraws with new fill level and color transitions from green to yellow

#### Accessibility (Task 3)

- [x] **AC13:** Given VoiceOver is active, when the user navigates to the status item, then VoiceOver announces the headroom percentage and state (unchanged from current behavior)
- [x] **AC14:** Given the gauge icon replaces the sparkle, when `accessibilityLabel` is read, then it still contains the full description (e.g., "cc-hdrm: Claude headroom 67 percent, normal")

#### Visual Quality

- [x] **AC15:** Given a Retina display, when the gauge renders, then the image appears sharp (no blurring from incorrect scaling)

## Additional Context

### Dependencies

None — uses only AppKit drawing APIs (`NSImage`, `NSBezierPath`, `NSColor`) already imported in the project.

### Testing Strategy

**Framework:** Swift Testing (`@Suite`, `@Test`, `#expect`)

**Unit Tests (GaugeIconTests.swift):**
- Test `makeGaugeIcon` returns valid NSImage for boundary headroom values (0, 50, 100)
- Test `makeGaugeIcon` returns valid NSImage for each HeadroomState
- Test `makeDisconnectedIcon` returns valid NSImage
- Test `isTemplate = false` for all returned images
- Optionally: extract angle calculation to a testable helper function and verify geometry

**Integration Testing:**
- Manual verification that gauge appears correctly in menu bar
- Manual verification of color transitions at threshold boundaries (40%, 20%, 5%, 0%)
- Manual verification of window promotion (force 7d to warning state, verify menu bar shows 7d data)
- VoiceOver testing to confirm accessibility parity

**Visual Testing:**
- Compare rendered gauge against HTML preview reference
- Test on Retina and non-Retina displays if available

### Notes

**High-Risk Items:**
- `NSBezierPath` arc drawing uses different semantics than SVG paths — verify arc direction (clockwise vs counterclockwise) matches HTML preview
- Menu bar icon sizing may need adjustment if 18×18pt doesn't align well with system text — test actual appearance
- Color appearance in menu bar may differ from popover due to vibrancy — verify Asset Catalog colors render correctly

**Known Limitations:**
- Gauge cannot show countdown information — users must read text for "resets in X" details
- No animation on gauge transitions (unlike SwiftUI HeadroomRingGauge) — acceptable for menu bar performance

**Future Considerations (Out of Scope):**
- Tooltip on hover showing detailed headroom info
- Different gauge styles for 5h vs 7d when both visible
- Dark/light mode specific gauge styling beyond Asset Catalog colors

## Review Notes

- **Adversarial review completed:** 2026-02-04
- **Findings:** 12 total, 5 fixed, 7 skipped (noise/invalid)
- **Resolution approach:** Auto-fix for real findings

**Fixes Applied:**
- F3: Added upper bound clamp in AppDelegate for defensive coding
- F6: Added detailed coordinate system documentation for arc drawing
- F8: Fixed unused `rect` parameter in drawing closures
- F10: Wrapped global functions in `GaugeIcon` enum namespace with legacy wrappers

**Skipped (noise/invalid):**
- F1 (invalid): Accessibility already handled by existing code
- F4 (noise): NSImage drawing handler handles Retina correctly
- F7 (noise): Menu bar updates infrequently; caching unnecessary
- F9 (noise): Magic numbers documented via Geometry enum and docstrings
- F11 (noise): Integer truncation is intentional and documented
- F12 (noise): Drawing handler returning true is standard pattern
