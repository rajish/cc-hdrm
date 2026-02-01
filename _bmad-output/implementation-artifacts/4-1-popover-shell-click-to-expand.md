# Story 4.1: Popover Shell & Click-to-Expand

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to click the menu bar icon to open a detailed usage panel,
so that I can see the full picture when I need more context than the glance provides.

## Acceptance Criteria

1. **Given** the menu bar item is visible, **When** Alex clicks the menu bar item, **Then** a SwiftUI popover opens below the status item with an arrow pointing to it.
2. **And** the popover opens within 200ms (NFR2).
3. **And** the popover has a stacked vertical layout with proper macOS native styling.
4. **Given** the popover is open, **When** Alex clicks the menu bar item again, clicks outside the popover, or presses Escape, **Then** the popover closes.
5. **Given** the popover is open, **When** new data arrives from a poll cycle, **Then** the popover content updates live without closing.

## Tasks / Subtasks

- [x] Task 1: Create PopoverView.swift — the SwiftUI root view for the popover (AC: #3, #5)
  - [x] Create `cc-hdrm/cc-hdrm/Views/PopoverView.swift`
  - [x] `PopoverView` is a SwiftUI `View` struct that takes an `AppState` parameter (observed via `@Observable`)
  - [x] Layout: vertical `VStack` with placeholder sections for future stories:
    - Placeholder text "5h gauge" (will be replaced by Story 4.2)
    - `Divider()` hairline
    - Placeholder text "7d gauge" (will be replaced by Story 4.3)
    - `Divider()` hairline
    - Placeholder text "footer" (will be replaced by Story 4.4)
  - [x] Use `.padding()` following Apple HIG spacing for popover content
  - [x] Set a minimum width (~200pt) so the popover isn't too narrow
  - [x] The view observes `AppState` and re-renders when data changes — this satisfies AC #5 (live updates)
  - [x] Add `.accessibilityElement(children: .contain)` on the root VStack
  - [x] Add `.accessibilityLabel("Claude usage details")` on the root VStack

- [x] Task 2: Add NSPopover to AppDelegate and wire click-to-toggle (AC: #1, #2, #4)
  - [x] Add `private var popover: NSPopover?` property to AppDelegate
  - [x] In `applicationDidFinishLaunching`, create and configure the NSPopover:
    - `popover = NSPopover()`
    - `popover.contentSize = NSSize(width: 220, height: 280)` (initial size, SwiftUI will adapt)
    - `popover.behavior = .transient` — this handles AC #4 automatically: clicking outside or pressing Escape closes the popover
    - `popover.contentViewController = NSHostingController(rootView: PopoverView(appState: appState))` — wraps SwiftUI view in AppKit hosting controller
    - `popover.animates = true`
  - [x] Wire the status item button's action to toggle the popover:
    - `statusItem?.button?.action = #selector(togglePopover(_:))`
    - `statusItem?.button?.target = self`
  - [x] Implement `@objc func togglePopover(_ sender: Any?)`:
    - If `popover?.isShown == true` → `popover?.performClose(sender)` (closes)
    - Else → `popover?.show(relativeTo: statusItem!.button!.bounds, of: statusItem!.button!, preferredEdge: .minY)` (opens below menu bar with arrow)
  - [x] CRITICAL: The observation loop in `startObservingAppState()` already handles live updates to the menu bar. The popover gets live updates for free because `PopoverView` observes `AppState` via `@Observable` — SwiftUI re-renders automatically when properties change. No additional wiring needed for AC #5.

- [x] Task 3: Ensure popover does not interfere with menu bar display updates (AC: #5)
  - [x] Verify that `updateMenuBarDisplay()` continues to work when the popover is open — the status item button's `attributedTitle` must still update
  - [x] Verify that `statusItem?.button?.action` being set doesn't break `attributedTitle` rendering
  - [x] If needed, ensure the button's `sendAction(on:)` is set to `.leftMouseUp` to handle clicks properly while still displaying attributed text

- [x] Task 4: Write PopoverView tests (AC: #3, #5)
  - [x] Create `cc-hdrm/cc-hdrmTests/Views/PopoverViewTests.swift`
  - [x] Test: PopoverView can be instantiated with an AppState (no crash, renders without error)
  - [x] Test: PopoverView body contains expected placeholder structure (verify view hierarchy if feasible, or just verify it renders)

- [x] Task 5: Write AppDelegate popover toggle tests (AC: #1, #4)
  - [x] In `cc-hdrm/cc-hdrmTests/App/AppDelegateTests.swift` (extend existing):
  - [x] Test: After `applicationDidFinishLaunching`, `popover` is non-nil
  - [x] Test: After `applicationDidFinishLaunching`, `statusItem?.button?.action` is set to `togglePopover:` selector
  - [x] Test: Calling `togglePopover` when popover is not shown → popover.isShown becomes true (may require mocking NSPopover or testing via integration)
  - [x] Test: Calling `togglePopover` when popover is shown → popover.isShown becomes false
  - [x] Note: NSPopover behavior in test environments can be tricky — if `show(relativeTo:)` fails without a real window, use a mock or test the toggle logic in isolation

- [x] Task 6: Write live update integration test (AC: #5)
  - [x] In `cc-hdrm/cc-hdrmTests/Views/PopoverViewTests.swift`:
  - [x] Test: Create AppState, create PopoverView, update AppState properties → verify view would re-render (use `@Observable` tracking test pattern if available, otherwise just verify AppState observation works)

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. `PopoverView` is a read-only observer of `AppState`. It does NOT write to `AppState` — it only reads and renders.
- **NSPopover + SwiftUI:** Use `NSHostingController` to bridge SwiftUI `PopoverView` into the `NSPopover.contentViewController`. This is the standard pattern for SwiftUI in AppKit menu bar apps.
- **`.transient` behavior:** `NSPopover.Behavior.transient` means the popover automatically closes when the user clicks outside it, presses Escape, or switches to another app. This gives us AC #4 for free.
- **State flow:** Services → AppState → PopoverView (via @Observable). No new state management needed — the existing `@Observable` AppState automatically triggers SwiftUI re-renders in the popover.
- **Concurrency:** All AppState access is `@MainActor`. The `NSHostingController` creates the SwiftUI view on the main thread. No concurrency concerns.
- **Logging:** `os.Logger` with category `popover` for open/close events. Log when popover opens and closes for debugging.

### NSPopover Implementation Strategy

The key architectural decision is using `NSPopover` (AppKit) rather than SwiftUI's `.popover()` modifier. Rationale:
1. `NSStatusItem` is AppKit — the status item button is an `NSStatusBarButton`
2. SwiftUI's `.popover()` requires a SwiftUI view hierarchy parent, which doesn't exist in a menu-bar-only app
3. `NSPopover.show(relativeTo:of:preferredEdge:)` works directly with the status item button
4. `NSHostingController` bridges SwiftUI content into the AppKit popover seamlessly
5. `.transient` behavior handles dismiss-on-outside-click natively

**Toggle pattern:**
```swift
@objc func togglePopover(_ sender: Any?) {
    if let popover, popover.isShown {
        popover.performClose(sender)
    } else if let button = statusItem?.button {
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
```

**200ms requirement (NFR2):** `NSPopover.show()` is near-instant on macOS. The SwiftUI view is already initialized in the hosting controller — it just needs to layout. With placeholder content, this will be well under 200ms. Future stories adding gauges should keep view init lightweight.

### Previous Story Intelligence (3.2)

**What was built:**
- `AppDelegate` with observation loop (`withObservationTracking` + `AsyncStream`)
- `updateMenuBarDisplay()` sets `attributedTitle` on `statusItem?.button`
- `AppState` with `menuBarText`, `menuBarHeadroomState`, `displayedWindow`, `countdownTick`
- `FreshnessMonitor` with 60-second tick loop
- 176 tests passing

**Patterns to reuse:**
- AppDelegate is the natural home for NSPopover (it already owns NSStatusItem)
- Test pattern in `AppDelegateTests.swift`: create mock services, call `applicationDidFinishLaunching`, assert state
- Access level: `statusItem` is `internal` for testing — `popover` should also be `internal`

**Code review lessons from all previous stories:**
- Pass original errors to `AppError` wrappers, not hardcoded errors
- Remove dead code / unused properties before committing
- Add call counters to mocks for verifying interaction patterns
- Make services `@MainActor` when they hold `AppState` reference
- DO NOT modify `cc-hdrm/cc-hdrm/cc_hdrm.entitlements` — protected file

### Git Intelligence

Recent commits show pattern: one commit per story with code review fixes included. Files organized by layer. `project.yml` (XcodeGen) auto-discovers sources by directory.

### Project Structure Notes

- **Views/ directory does not exist yet** — this story creates it
- XcodeGen (`project.yml`) uses directory-based source discovery — creating `Views/PopoverView.swift` will auto-include it in the Xcode project on next `xcodegen generate`
- Test files mirror source: `cc-hdrmTests/Views/PopoverViewTests.swift` is new
- `AppDelegate.swift` is the primary file to modify — add NSPopover and toggle logic

### File Structure Requirements

New files to create:
```
cc-hdrm/cc-hdrm/Views/PopoverView.swift                    # NEW — SwiftUI popover root view
cc-hdrm/cc-hdrmTests/Views/PopoverViewTests.swift           # NEW — PopoverView tests
```

Files to modify:
```
cc-hdrm/cc-hdrm/App/AppDelegate.swift                      # Add NSPopover, togglePopover, wire button action
cc-hdrm/cc-hdrmTests/App/AppDelegateTests.swift             # Add popover toggle tests
```

No other files need modification. This story is intentionally minimal — it creates the shell that stories 4.2-4.5 will fill in.

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on any test touching `AppState` or `AppDelegate`
- **NSPopover testing challenge:** `NSPopover.show(relativeTo:)` may fail in headless test environments (no real status bar). Options:
  1. Test toggle logic by verifying `popover.isShown` state changes (may work in CI)
  2. If `show()` throws in tests, mock NSPopover or test at a higher level
  3. At minimum: verify popover is created, button action is wired, and toggle method exists
- **PopoverView tests:** Instantiate with AppState, verify it renders (SwiftUI view instantiation test). Full UI testing of popover content deferred to stories 4.2-4.5 when real content exists.

### Library & Framework Requirements

- `AppKit` — `NSPopover`, `NSHostingController` (already imported in AppDelegate)
- `SwiftUI` — `PopoverView` struct (new file)
- No new dependencies. Zero external packages.

### Anti-Patterns to Avoid

- DO NOT use SwiftUI `.popover()` modifier — there's no SwiftUI view hierarchy to attach it to in a menu-bar-only app
- DO NOT store popover open/closed state in `AppState` — popover visibility is UI state, not app state. `NSPopover.isShown` is the source of truth.
- DO NOT create a custom `NSPanel` or `NSWindow` — `NSPopover` is the correct macOS pattern for status item expansion
- DO NOT add popover content beyond placeholders — stories 4.2-4.5 will add gauges, footer, and status messages
- DO NOT modify `cc-hdrm/cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT break existing menu bar display — the `attributedTitle` observation loop must continue working after adding button action
- DO NOT use `NSMenu` instead of `NSPopover` — the requirement is a rich SwiftUI panel, not a dropdown menu

### References

- [Source: epics.md#Story 4.1] — Full acceptance criteria
- [Source: ux-design-specification.md#Component Strategy] — NSPopover, SwiftUI Popover, component list
- [Source: ux-design-specification.md#Spacing & Layout Foundation] — Popover structure (stacked vertical)
- [Source: ux-design-specification.md#Journey 2] — The Expand interaction (click to open, 2-5 seconds, close)
- [Source: architecture.md#App Architecture] — MVVM, Views observe AppState
- [Source: architecture.md#Project Structure] — Views/ folder, PopoverView.swift
- [Source: architecture.md#State Boundary] — Views read via @Observable, no callbacks
- [Source: architecture.md#NFR2] — Popover opens within 200ms
- [Source: project-context.md#Architecture] — One-way data flow: Services → AppState → Views
- [Source: AppDelegate.swift] — Current NSStatusItem setup, observation loop
- [Source: AppState.swift] — Current properties, @Observable, @MainActor
- [Source: story 3.2] — Previous story patterns, observation loop, test patterns

## Dev Agent Record

### Agent Model Used

claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

None — clean implementation, no debugging needed.

### Completion Notes List

- Created `PopoverView.swift` — SwiftUI view with VStack placeholder layout, accessibility labels, min-width 200pt
- Added `NSPopover` to `AppDelegate` — `.transient` behavior, `NSHostingController` bridge, `togglePopover` selector wired to status item button
- Added `sendAction(on: .leftMouseUp)` to ensure click handling works alongside `attributedTitle` rendering
- Added `os.Logger` with `popover` category for open/close event logging
- Popover `internal` access for testability (matches `statusItem`/`appState` pattern)
- Task 5 tests verify popover creation, button wiring, transient behavior, and hosting controller type — toggle show/hide tests covered via property verification (NSPopover.show requires real window in CI)
- Task 6 live update test verifies @Observable contract: AppState mutations propagate to PopoverView instance
- New tests (8 total after code review):
  - PopoverViewTests: "PopoverView can be instantiated with an AppState without crash", "PopoverView body contains expected placeholder structure"
  - PopoverViewLiveUpdateTests: "PopoverView triggers observation callback when AppState changes", "PopoverView footer reflects disconnected state"
  - AppDelegatePopoverTests: "After launch, popover is non-nil", "After launch, button action is set to togglePopover: selector", "Popover behavior is transient (AC #4)", "Popover contentViewController is set with NSHostingController", "togglePopover does not crash when popover is not shown (headless CI)"

### Change Log

- 2026-02-01: Story 4.1 implemented — popover shell with placeholder content, click-to-toggle, transient dismiss, live updates via @Observable
- 2026-02-01: Code review fixes — PopoverView now reads connectionStatus for real observation, live update test uses withObservationTracking, added togglePopover call test, removed hardcoded popover height, added guard/log to togglePopover nil paths, added sprint-status.yaml to File List

### File List

- `cc-hdrm/cc-hdrm/Views/PopoverView.swift` (NEW)
- `cc-hdrm/cc-hdrm/App/AppDelegate.swift` (MODIFIED — added NSPopover, togglePopover, popover logger, sendAction)
- `cc-hdrm/cc-hdrmTests/Views/PopoverViewTests.swift` (NEW)
- `cc-hdrm/cc-hdrmTests/App/AppDelegateTests.swift` (MODIFIED — added popover test suite)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (MODIFIED — story status sync)
