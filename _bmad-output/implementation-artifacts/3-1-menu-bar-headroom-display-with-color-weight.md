# Story 3.1: Menu Bar Headroom Display with Color & Weight

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to see my current headroom percentage in the menu bar with color-coded severity,
so that I know my remaining capacity at a glance without any interaction.

## Acceptance Criteria

1. **Given** AppState contains valid 5-hour usage data, **When** the menu bar renders, **Then** it shows Claude sparkle icon (✳) + headroom percentage (e.g., "✳ 83%").
2. **And** text color matches the HeadroomState color token:
   - \> 40% headroom → `.headroomNormal` (muted green), Regular weight
   - 20-40% → `.headroomCaution` (yellow), Medium weight
   - 5-20% → `.headroomWarning` (orange), Semibold weight
   - < 5% → `.headroomCritical` (red), Bold weight
   - 0% → `.headroomExhausted` (red), Bold weight
   - Disconnected → `.disconnected` (grey), Regular weight, shows "✳ —"
3. **And** the sparkle icon color matches the text color (shifts with state).
4. **And** the display updates within 2 seconds of AppState changes (NFR1).
5. **Given** AppState indicates disconnected, token expired, or no credentials, **When** the menu bar renders, **Then** it shows "✳ —" in grey with Regular weight.
6. **Given** a VoiceOver user focuses the menu bar item, **When** VoiceOver reads the element, **Then** it announces "cc-hdrm: Claude headroom [X] percent, [state]".
7. **And** state changes trigger NSAccessibility.Notification.valueChanged.

## Tasks / Subtasks

- [x] Task 1: Create `Color+Headroom.swift` extension (AC: #2, #3)
  - [x] Create `cc-hdrm/Extensions/Color+Headroom.swift`
  - [x] Define `extension Color` with static computed properties mapping to Asset Catalog names:
    - `.headroomNormal` → `Color("HeadroomNormal", bundle: .main)` (namespaced under HeadroomColors)
    - `.headroomCaution` → `Color("HeadroomCaution", bundle: .main)`
    - `.headroomWarning` → `Color("HeadroomWarning", bundle: .main)`
    - `.headroomCritical` → `Color("HeadroomCritical", bundle: .main)`
    - `.headroomExhausted` → `Color("HeadroomExhausted", bundle: .main)`
    - `.disconnected` → `Color("Disconnected", bundle: .main)`
  - [x] NOTE: Asset Catalog uses namespaced folder `HeadroomColors/` — check if `Color("HeadroomColors/HeadroomNormal")` is needed vs. just `Color("HeadroomNormal")` since `provides-namespace: true` is set. Test at build time.
  - [x] Add `NSColor` equivalents for menu bar use (NSStatusItem uses NSAttributedString, not SwiftUI Color):
    - `static func nsColor(for state: HeadroomState) -> NSColor` that maps HeadroomState to the corresponding `NSColor(named:)` from the Asset Catalog
  - [x] If namespace resolution fails at runtime, fallback to programmatic NSColor definitions matching the Asset Catalog values

- [x] Task 2: Create `NSFont` weight mapping for HeadroomState (AC: #2)
  - [x] In `Color+Headroom.swift` (or a new `NSFont+Headroom.swift` extension), add:
    - `static func menuBarFont(for state: HeadroomState) -> NSFont` that returns `NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: ...)` with:
      - `.normal` → `.regular`
      - `.caution` → `.medium`
      - `.warning` → `.semibold`
      - `.critical` → `.bold`
      - `.exhausted` → `.bold`
      - `.disconnected` → `.regular`
  - [x] NOTE: `HeadroomState.fontWeight` already returns a String ("regular", "medium", etc.) — the extension should use that or map directly. Prefer the direct NSFont.Weight mapping for type safety.

- [x] Task 3: Add `menuBarText` and `menuBarHeadroomState` computed properties to AppState (AC: #1, #4, #5)
  - [x] In `cc-hdrm/State/AppState.swift`, add:
    - `var menuBarHeadroomState: HeadroomState` — derived from the **displayed** window (5h by default). Returns:
      - `.disconnected` if `connectionStatus` is not `.connected`
      - Otherwise derives from `fiveHour?.headroomState ?? .disconnected`
    - `var menuBarText: String` — derived property:
      - If `menuBarHeadroomState == .disconnected` → `"✳ —"` (sparkle + em dash)
      - Otherwise → `"✳ XX%"` where XX is the headroom percentage: `Int(100 - (fiveHour?.utilization ?? 0))`
      - Percentage should never be negative: clamp to `max(0, headroom)`
  - [x] These are **computed** properties — never stored. Same pattern as `dataFreshness`.

- [x] Task 4: Update `AppDelegate` to observe AppState and update NSStatusItem (AC: #1, #2, #3, #4)
  - [x] In `cc-hdrm/App/AppDelegate.swift`:
    - Add an observation mechanism to watch `AppState` changes and update the status item
    - **IMPORTANT:** `@Observable` uses the Observation framework. For AppKit integration, use `withObservationTracking` in a loop or a `Task` that re-renders on change.
    - Pattern:
      ```swift
      private func startObservingAppState() {
          Task { @MainActor in
              while !Task.isCancelled {
                  withObservationTracking {
                      updateMenuBarDisplay()
                  } onChange: {
                      Task { @MainActor in /* triggers next loop iteration */ }
                  }
                  try? await Task.sleep(for: .milliseconds(100)) // yield
              }
          }
      }
      ```
    - `updateMenuBarDisplay()` reads `appState.menuBarText`, `appState.menuBarHeadroomState`, then:
      1. Gets the NSColor for the state via `Color+Headroom.nsColor(for:)`
      2. Gets the NSFont for the state via `NSFont+Headroom.menuBarFont(for:)` (or equivalent)
      3. Creates an `NSAttributedString` with the title, foreground color, and font
      4. Sets `statusItem.button?.attributedTitle = attributedString`
    - **CRITICAL:** The sparkle icon (✳) must be colored the same as the percentage text. Since both are in the same attributed string, a single foreground color attribute covers both.
    - Remove the current static `"✳ --"` placeholder setup — replace with initial call to `updateMenuBarDisplay()`
    - Start the observation in `applicationDidFinishLaunching` after creating AppState
  - [x] Store the observation task so it can be cancelled in `applicationWillTerminate`

- [x] Task 5: Add VoiceOver accessibility to the menu bar item (AC: #6, #7)
  - [x] In the `updateMenuBarDisplay()` method (or called from it):
    - Set `statusItem.button?.accessibilityLabel` = `"cc-hdrm"`
    - Set `statusItem.button?.accessibilityValue` based on state:
      - Disconnected: `"Claude headroom disconnected"`
      - Normal states: `"Claude headroom XX percent, [state name]"` where state name is the HeadroomState raw value
    - Post `NSAccessibility.Notification.valueChanged` to `statusItem.button` when the value changes (compare previous vs current state to avoid spamming)
  - [x] Track previous headroom state to detect changes for accessibility notifications

- [x] Task 6: Write `Color+Headroom` / `NSColor` mapping tests (AC: #2, #3)
  - [x] Create `cc-hdrmTests/Extensions/ColorHeadroomTests.swift`
  - [x] Test: each HeadroomState maps to a non-nil NSColor (validates Asset Catalog names resolve)
  - [x] Test: `.normal` → different color than `.critical` (basic sanity)
  - [x] Test: `.disconnected` returns a grey-family color
  - [x] Test: font weight mapping returns correct NSFont.Weight for each state

- [x] Task 7: Write `AppState.menuBarText` and `menuBarHeadroomState` tests (AC: #1, #3, #5)
  - [x] In `cc-hdrmTests/State/AppStateTests.swift` (extend existing):
  - [x] Test: `connectionStatus == .disconnected` → `menuBarHeadroomState == .disconnected`, `menuBarText == "✳ —"`
  - [x] Test: `connectionStatus == .connected`, `fiveHour = nil` → `.disconnected`, `"✳ —"`
  - [x] Test: `connectionStatus == .connected`, `fiveHour.utilization = 17.0` → headroom 83% → `.normal`, `"✳ 83%"`
  - [x] Test: `connectionStatus == .connected`, `fiveHour.utilization = 65.0` → headroom 35% → `.caution`, `"✳ 35%"`
  - [x] Test: `connectionStatus == .connected`, `fiveHour.utilization = 85.0` → headroom 15% → `.warning`, `"✳ 15%"`
  - [x] Test: `connectionStatus == .connected`, `fiveHour.utilization = 97.0` → headroom 3% → `.critical`, `"✳ 3%"`
  - [x] Test: `connectionStatus == .connected`, `fiveHour.utilization = 100.0` → headroom 0% → `.exhausted`, `"✳ 0%"`
  - [x] Test: `connectionStatus == .tokenExpired` → `.disconnected`, `"✳ —"`
  - [x] Test: `connectionStatus == .noCredentials` → `.disconnected`, `"✳ —"`
  - [x] Test: utilization > 100 (edge case) → headroom clamped to 0%, not negative

- [x] Task 8: Write `AppDelegate` menu bar update integration tests (AC: #4)
  - [x] In `cc-hdrmTests/App/AppDelegateTests.swift` (extend existing):
  - [x] Test: after `updateWindows(fiveHour:)` is called on AppState, the status item's `attributedTitle` reflects the new percentage (may need to expose `updateMenuBarDisplay()` as internal for testing)
  - [x] Test: status item button has an `accessibilityLabel` set
  - [x] Test: status item button has an `accessibilityValue` that includes "percent" for connected states

- [x] Task 9: Write headroom percentage edge case tests (AC: #1)
  - [x] Test: utilization = 0.0 → headroom = 100% → "✳ 100%"
  - [x] Test: utilization = 50.5 → headroom = 49% (or 50% — verify rounding: `Int(100 - utilization)` → 49 vs `Int(round(100 - utilization))` → 50. Use truncation `Int(...)` for consistency with mental model "at least X% left")
  - [x] Test: utilization = 99.9 → headroom = 0% (Int truncation) → `.critical` (actual headroom 0.1% is in critical range, not exhausted)

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. Menu bar display is driven by computed properties on `AppState` — views/renderers are read-only observers.
- **State derivation:** `menuBarText` and `menuBarHeadroomState` are **computed** properties, never stored. Same pattern as `WindowState.headroomState` and `dataFreshness`.
- **AppKit integration:** `NSStatusItem` is AppKit. SwiftUI `Color` cannot be used directly — must bridge to `NSColor` via `NSColor(named:)` from the Asset Catalog or `NSColor(Color(...))`.
- **Observation:** Use `withObservationTracking` for AppKit ↔ `@Observable` bridging. This is the Apple-recommended approach for non-SwiftUI consumers of `@Observable`.
- **Concurrency:** Observation loop runs as a `Task` on `@MainActor`. No GCD.
- **Logging:** `os.Logger` with subsystem `com.cc-hdrm.app`, category `menubar` for any display-related logging.

### NSStatusItem Display Details

The current `AppDelegate` creates the NSStatusItem like this:
```swift
statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
if let button = statusItem.button {
    button.title = "✳ --"
    button.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    button.contentTintColor = .systemGray
}
```

This needs to change to:
1. Use `NSAttributedString` for `attributedTitle` instead of plain `title` + `contentTintColor` — attributed strings give per-character control over color and weight.
2. Remove the static placeholder — the observation loop handles initial and subsequent renders.
3. The sparkle character "✳" (U+2733, EIGHT SPOKED ASTERISK) is already used — keep it.

### `withObservationTracking` Pattern for AppKit

```swift
// Conceptual — NOT copy-paste code
@MainActor
private func startObservingAppState() {
    observationTask = Task { [weak self] in
        while !Task.isCancelled {
            withObservationTracking {
                self?.updateMenuBarDisplay()
            } onChange: {
                // This closure fires when any tracked property changes
                // It runs on an arbitrary thread, so we dispatch back to MainActor
                Task { @MainActor [weak self] in
                    // The next loop iteration will call withObservationTracking again
                }
            }
            // Wait for the onChange signal before re-tracking
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
```

**Key insight:** `withObservationTracking` only tracks properties accessed in the closure during that one call. The `onChange` callback fires once then the tracking is gone. The loop pattern re-establishes tracking after each change.

**Alternative approach:** If the above is complex, a simpler polling pattern (check AppState every 500ms) is acceptable given the 2-second NFR1 requirement. The observation approach is preferred for responsiveness.

### NSAttributedString Construction

```swift
// Conceptual — NOT copy-paste code
private func updateMenuBarDisplay() {
    let state = appState.menuBarHeadroomState
    let text = appState.menuBarText

    let color = NSColor.headroomColor(for: state)  // from Color+Headroom
    let font = NSFont.menuBarFont(for: state)       // from font mapping

    let attributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: color,
        .font: font
    ]
    statusItem.button?.attributedTitle = NSAttributedString(string: text, attributes: attributes)

    // Accessibility
    statusItem.button?.accessibilityLabel = "cc-hdrm"
    let accessibilityValue: String
    if state == .disconnected {
        accessibilityValue = "Claude headroom disconnected"
    } else {
        let headroom = Int(max(0, 100 - (appState.fiveHour?.utilization ?? 0)))
        accessibilityValue = "Claude headroom \(headroom) percent, \(state.rawValue)"
    }

    if statusItem.button?.accessibilityValue() != accessibilityValue {
        statusItem.button?.setAccessibilityValue(accessibilityValue)
        NSAccessibility.post(element: statusItem.button!, notification: .valueChanged)
    }
}
```

### Asset Catalog Namespace Resolution

The HeadroomColors folder in Assets.xcassets has `provides-namespace: true`. This means color names may need to be referenced as `"HeadroomColors/HeadroomNormal"` — **or** just `"HeadroomNormal"` depending on how `NSColor(named:)` resolves namespaced colors.

**Action required:** Test both formats at build time. If `NSColor(named: "HeadroomNormal")` returns nil, use `NSColor(named: NSColor.Name("HeadroomColors/HeadroomNormal"))`.

The `HeadroomState.colorTokenName` property already returns un-namespaced names like `"HeadroomNormal"` and `"Disconnected"`. If namespace prefix is needed, update that property or handle in the mapping extension.

### Previous Story Intelligence (2.3)

**What was built:**
- `DataFreshness` enum with computed property on AppState
- `FreshnessMonitor` with `Task.sleep` loop, `@MainActor`, protocol-based
- `Date.relativeTimeAgo()` extension
- 127 tests passing

**Patterns to reuse:**
- Computed properties on `AppState` for derived state — `menuBarText` and `menuBarHeadroomState` follow the exact same pattern as `dataFreshness`
- `@MainActor` on anything touching AppState
- Protocol-based services for testability
- Test `internal` methods directly rather than testing through async loops
- `MockFreshnessMonitor` pattern for AppDelegate tests

**Code review lessons from all previous stories:**
- Pass original errors to `AppError` wrappers, not hardcoded errors
- Remove dead code / unused properties before committing
- Add call counters to mocks for verifying interaction patterns
- Make services `@MainActor` when they hold `AppState` reference
- Do NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file

### Git Intelligence

Recent commits:
- `12880c9` Add story 2.3: Data freshness tracking with code review fixes
- `f49b681` Add story 2.2: Background polling engine with code review fixes
- `b1a6173` Add project-context.md
- `b2d930a` Add story 2.1: API client & usage data fetch
- `d1ebbc8` Add story 1.3: Token expiry detection & refresh

**Patterns:** New files for protocol+implementation, tests mirror source, sprint-status updated on completion.

### Project Structure Notes

- XcodeGen (`project.yml`) uses directory-based source discovery — new files in correct folders auto-included
- Test files mirror source structure under `cc-hdrmTests/`
- No Views/ files exist yet — this story creates the first view-layer code (though it's AppKit, not SwiftUI views)

### File Structure Requirements

New files to create:
```
cc-hdrm/Extensions/Color+Headroom.swift
cc-hdrmTests/Extensions/ColorHeadroomTests.swift
```

Files to modify:
```
cc-hdrm/State/AppState.swift                    # Add menuBarText, menuBarHeadroomState
cc-hdrm/App/AppDelegate.swift                   # Add observation loop, updateMenuBarDisplay()
cc-hdrmTests/State/AppStateTests.swift           # Add menu bar property tests
cc-hdrmTests/App/AppDelegateTests.swift          # Add menu bar update tests
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on any test touching `AppState`
- **NSColor testing:** `NSColor(named:)` may return nil in test targets if the Asset Catalog isn't bundled with the test target. If so, either: (a) add the asset catalog to the test target, or (b) test the mapping logic (state → color name string) rather than the NSColor resolution.
- **AppDelegate testing:** Expose `updateMenuBarDisplay()` as `internal` for direct testing. Verify `statusItem.button?.attributedTitle` contains expected text and attributes.
- **Edge cases:** utilization > 100 (clamp to 0% headroom), utilization = 0 (100% headroom), nil fiveHour (disconnected).

### Anti-Patterns to Avoid

- DO NOT store `menuBarText` or `menuBarHeadroomState` as separate stored properties — they must be computed
- DO NOT use SwiftUI `Color` directly with NSStatusItem — bridge to `NSColor`
- DO NOT use `Timer` or `DispatchQueue` for the observation loop — use `Task` + `withObservationTracking`
- DO NOT update the menu bar from the polling engine — the observation pattern decouples polling from rendering
- DO NOT hardcode colors — always reference Asset Catalog via `NSColor(named:)`
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT use `print()` — use `os.Logger` with category `menubar`
- DO NOT post accessibility notifications on every render — only when value actually changes

### References

- [Source: epics.md#Story 3.1] — Full acceptance criteria, color/weight mapping
- [Source: ux-design-specification.md#MenuBarTextRenderer] — Component spec, sparkle icon, states table
- [Source: ux-design-specification.md#Typography System] — Font weight escalation per state
- [Source: ux-design-specification.md#Color System] — HeadroomState color tokens
- [Source: ux-design-specification.md#Accessibility Considerations] — VoiceOver labels, color independence
- [Source: architecture.md#State Management Patterns] — Derived state, services write via methods
- [Source: architecture.md#Accessibility Patterns] — VoiceOver announcement format
- [Source: architecture.md#Structure Patterns] — Layer-based file organization
- [Source: project-context.md#HeadroomState Reference] — Complete state/color/weight table
- [Source: AppDelegate.swift] — Current NSStatusItem setup (placeholder)
- [Source: AppState.swift] — WindowState struct, connectionStatus, fiveHour/sevenDay properties
- [Source: HeadroomState.swift] — Enum with colorTokenName and fontWeight properties

## Dev Agent Record

### Agent Model Used

claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

- Build succeeded after XcodeGen regeneration (new files auto-discovered)
- Asset Catalog namespace confirmed: `provides-namespace: true` requires `"HeadroomColors/ColorName"` format for `NSColor(named:)`
- Test fix: utilization 99.9 yields headroom 0.1% which is `.critical` (0<0.1<5), not `.exhausted` — corrected test expectation

### Completion Notes List

- Created `Color+Headroom.swift` with `NSColor.headroomColor(for:)` using namespaced Asset Catalog references with programmatic fallback, `NSFont.menuBarFont(for:)` weight mapping, and SwiftUI `Color` static properties
- Added `menuBarHeadroomState` and `menuBarText` computed properties to `AppState` — derived from connectionStatus and 5-hour window, never stored
- Replaced static `"✳ --"` placeholder in `AppDelegate` with `withObservationTracking` loop that re-renders on any AppState change via `updateMenuBarDisplay()`
- `updateMenuBarDisplay()` sets `NSAttributedString` with state-driven color and font weight, plus VoiceOver accessibility (label, value, valueChanged notification only on actual changes)
- 149 tests passing (22 new tests added including font weight verification on NSStatusItem), 0 regressions

### Change Log

- 2026-02-01: Implemented story 3.1 — menu bar headroom display with color-coded severity, font weight mapping, observation loop, and VoiceOver accessibility
- 2026-02-01: Code review fixes (7 issues) — H1: HeadroomState.fontWeight exhausted→bold, H2: VoiceOver label format matches AC#6, M1: AppDelegate tests verify actual NSStatusItem button state, M2: observation loop uses AsyncStream to suspend until onChange (NFR4), M3: headroom 40% boundary inclusive in .caution per AC#2, L1: removed redundant .disconnected case in Color+Headroom, L2: consolidated to single "menubar" logger category

### File List

New files:
- cc-hdrm/Extensions/Color+Headroom.swift
- cc-hdrmTests/Extensions/ColorHeadroomTests.swift

Modified files:
- cc-hdrm/State/AppState.swift
- cc-hdrm/App/AppDelegate.swift
- cc-hdrm/Models/HeadroomState.swift
- cc-hdrm/Extensions/Color+Headroom.swift
- cc-hdrmTests/State/AppStateTests.swift
- cc-hdrmTests/App/AppDelegateTests.swift
- cc-hdrmTests/Models/HeadroomStateTests.swift
- _bmad-output/implementation-artifacts/sprint-status.yaml
