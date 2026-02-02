# Story 4.4: Panel Footer — Tier, Freshness & Quit

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to see my subscription tier, data freshness, and a quit option in the panel,
so that I have full context about my account and can control the app.

## Acceptance Criteria

1. **Given** AppState contains subscription tier data, **When** the popover renders the footer, **Then** subscription tier (e.g., "Max") appears left-aligned in caption size, tertiary color.
2. **And** "Updated Xs ago" timestamp appears center-aligned in mini size, tertiary color.
3. **And** a gear icon (SF Symbol) appears right-aligned.
4. **Given** the timestamp is in the stale range (60s-5m), **When** the footer renders, **Then** the "Updated Xm ago" text shows in amber/warning color.
5. **Given** Alex clicks the gear icon, **When** the menu opens, **Then** it shows "Quit cc-hdrm" as a menu item.
6. **And** selecting Quit terminates the application (FR24).
7. **And** the gear menu opens as a standard SwiftUI Menu dropdown.
8. **And** selecting Quit closes the popover and terminates the app.

## Tasks / Subtasks

- [x] Task 1: Create PopoverFooterView.swift -- footer view for popover (AC: #1-#4)
  - [x] Create `cc-hdrm/Views/PopoverFooterView.swift`
  - [x] SwiftUI `View` struct with parameter: `appState: AppState`
  - [x] Layout: `HStack` with three elements:
    1. Left: subscription tier `Text(appState.subscriptionTier ?? "—")` in `.caption` size, `.tertiary` foreground style (AC #1)
    2. Center: freshness timestamp `Text(freshnessText)` in `.caption2` size, tertiary color normally, `.headroomWarning` color when `appState.dataFreshness == .stale` (AC #2, #4)
    3. Right: `GearMenuView()`  (AC #3)
  - [x] Freshness text computation:
    - When `appState.lastUpdated` is nil: show "—"
    - When fresh (<60s): "Updated Xs ago" using elapsed seconds since `appState.lastUpdated`
    - When stale (60s-5m): "Updated Xm ago" in warning color
    - When very stale (>5m): "Updated Xm ago" (StatusMessageView handles the prominent message)
    - Access `appState.countdownTick` to register observation for periodic re-renders
  - [x] VoiceOver: `.accessibilityElement(children: .combine)` so the footer reads as a single element: "Subscription tier [tier], updated [X] seconds ago"

- [x] Task 2: Create GearMenuView.swift -- gear icon with quit menu (AC: #5-#8)
  - [x] Create `cc-hdrm/Views/GearMenuView.swift`
  - [x] SwiftUI `View` struct, no parameters (self-contained)
  - [x] Implementation: `Menu { Button("Quit cc-hdrm") { NSApplication.shared.terminate(nil) } } label: { Image(systemName: "gearshape").foregroundStyle(.secondary) }`
  - [x] Standard SwiftUI `Menu` dropdown behavior (AC #7)
  - [x] Selecting "Quit cc-hdrm" calls `NSApplication.shared.terminate(nil)` (AC #6, #8)
  - [x] `.accessibilityLabel("Settings")` on the gear icon

- [x] Task 3: Update PopoverView.swift to replace footer placeholder (AC: #1-#4)
  - [x] In `cc-hdrm/Views/PopoverView.swift`:
  - [x] Replace the `Text(status == .disconnected ? "disconnected" : "footer")` placeholder block (lines 30-33) with:
    ```swift
    PopoverFooterView(appState: appState)
        .padding(.horizontal)
        .padding(.vertical, 8)
    ```
  - [x] Remove the `let status = appState.connectionStatus` on line 12 -- it was only needed for the placeholder footer text. PopoverFooterView reads appState directly. (Note: if other parts of the body use `status`, keep it. Currently only the placeholder footer uses it, and the `let _ = appState.countdownTick` on line 13 can also be removed since PopoverFooterView and the gauge sections each read countdownTick themselves.)
  - [x] Actually, keep `let _ = appState.countdownTick` on line 13 if the FiveHourGaugeSection or SevenDayGaugeSection rely on PopoverView registering that observation. Check: FiveHourGaugeSection and SevenDayGaugeSection both read `appState.countdownTick` in their own body, so PopoverView's read is redundant. However, `connectionStatus` IS read by PopoverView's body to check `appState.sevenDay != nil` condition -- actually no, `appState.sevenDay` is read directly. The `status` variable was only used for the placeholder. Safe to remove both `let status` and `let _` lines.

- [x] Task 4: Write PopoverFooterView tests (AC: #1-#4)
  - [x] Create `cc-hdrmTests/Views/PopoverFooterViewTests.swift`
  - [x] Test: Footer renders with subscription tier data -- no crash
  - [x] Test: Footer renders with nil subscription tier -- shows "—"
  - [x] Test: Footer renders with fresh data (dataFreshness == .fresh)
  - [x] Test: Footer renders with stale data (dataFreshness == .stale) -- warning color
  - [x] Test: Footer renders when disconnected
  - [x] Test: Observation triggers when subscriptionTier changes
  - [x] Test: Observation triggers when lastUpdated changes
  - [x] Use `@MainActor`, `@Test`, Swift Testing framework, consistent with previous story patterns

- [x] Task 5: Write GearMenuView tests (AC: #5-#8)
  - [x] Create `cc-hdrmTests/Views/GearMenuViewTests.swift`
  - [x] Test: GearMenuView renders without crash
  - [x] Test: GearMenuView produces a valid body (instantiation test)
  - [x] Note: Testing actual menu interaction (tap -> quit) requires UI testing and is out of scope for unit tests. The quit action uses `NSApplication.shared.terminate(nil)` which is a well-known AppKit API.

- [x] Task 6: Update PopoverView integration tests (AC: #1-#4)
  - [x] Extend `cc-hdrmTests/Views/PopoverViewTests.swift`:
  - [x] Test: PopoverView with subscription tier renders footer without crash
  - [x] Test: PopoverView observation triggers on subscriptionTier change
  - [x] Update or remove the `footerReflectsDisconnectedState` test to match new footer implementation (no longer checks for "disconnected"/"footer" text)

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. PopoverFooterView is a pure presentational view -- read-only observer of AppState. Does NOT write to AppState.
- **State flow:** Services -> AppState -> PopoverView -> PopoverFooterView -> GearMenuView
- **Data freshness:** Derived from `appState.dataFreshness` computed property (already exists in AppState). Uses `DataFreshness` enum with `.fresh`, `.stale`, `.veryStale`, `.unknown` states.
- **Concurrency:** All AppState access is `@MainActor`. Views run on main thread via SwiftUI. No concurrency concerns.
- **Logging:** No logging needed in view components.

### Key Implementation Details

**Freshness timestamp computation:**
- `appState.lastUpdated` contains the `Date` of the last successful fetch
- `appState.countdownTick` increments every 60 seconds -- reading it in the footer body ensures the "Updated Xs ago" text refreshes periodically
- `appState.dataFreshness` returns the current freshness category
- Elapsed time: `Int(Date().timeIntervalSince(appState.lastUpdated ?? Date()))` for the "Xs ago" / "Xm ago" text
- Format: <60s show seconds ("Updated 23s ago"), >=60s show minutes ("Updated 2m ago")

**Stale color (AC #4):**
- When `appState.dataFreshness == .stale`, the timestamp text color changes to `.headroomWarning` (amber/orange) per UX spec
- When `.fresh` or `.veryStale`, use `.tertiary` foreground style
- When `.veryStale`, StatusMessageView (story 4.5) handles the prominent message

**Quit implementation (AC #6, #8):**
- `NSApplication.shared.terminate(nil)` is the standard macOS app termination API
- This properly closes the popover and terminates the app
- No cleanup or state saving needed (all state is in-memory per architecture)

### Previous Story Intelligence (4.3)

**What was built:**
- SevenDayGaugeSection.swift -- composed 7d gauge section
- PopoverView updated with conditional SevenDayGaugeSection
- All views follow the pattern: parameter is `appState: AppState`, read-only observation

**Code review lessons from story 4.3:**
- Remove unused imports (story 4.3 had `import os` removed from tests)
- File List in story document should not include gitignored files (xcodeproj)
- Follow existing section patterns (VStack, padding, accessibility)

**Patterns to follow exactly:**
- PopoverFooterView should take `appState: AppState` as its only parameter
- GearMenuView is self-contained (no parameters)
- Test pattern: instantiate views with AppState, verify no crash, use withObservationTracking
- `@MainActor` on all tests touching AppState

### Git Intelligence

Recent commits follow pattern: one commit per story with code review fixes. XcodeGen auto-discovers new files in Views/ directory. Run `xcodegen generate` after adding new files.

### Project Structure Notes

- `Views/` directory contains: PopoverView, HeadroomRingGauge, CountdownLabel, FiveHourGaugeSection, SevenDayGaugeSection
- New files go in `cc-hdrm/Views/PopoverFooterView.swift` and `cc-hdrm/Views/GearMenuView.swift`
- New test files go in `cc-hdrmTests/Views/`
- `StatusMessageView.swift` and `MenuBarTextRenderer.swift` do NOT exist yet -- they are in future stories (4.5 for StatusMessageView, 3.1 used NSAttributedString directly). Do NOT create them in this story.

### File Structure Requirements

New files to create:
```
cc-hdrm/Views/PopoverFooterView.swift           # NEW -- footer with tier, freshness, gear menu
cc-hdrm/Views/GearMenuView.swift                 # NEW -- gear icon with quit menu
cc-hdrmTests/Views/PopoverFooterViewTests.swift   # NEW -- footer tests
cc-hdrmTests/Views/GearMenuViewTests.swift        # NEW -- gear menu tests
```

Files to modify:
```
cc-hdrm/Views/PopoverView.swift                  # REPLACE footer placeholder with PopoverFooterView
cc-hdrmTests/Views/PopoverViewTests.swift         # UPDATE footer integration tests
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on any test touching AppState
- **SwiftUI view tests:** Instantiate views with AppState, verify they render without crash. Full visual testing is out of scope.
- **Observation tests:** Use `withObservationTracking` pattern from previous stories to verify footer updates when AppState properties change.
- **Key test scenarios:**
  - Subscription tier display with valid tier and nil tier
  - Freshness timestamp with fresh, stale, and disconnected states
  - Stale color change (warning color when 60s-5m elapsed)
  - GearMenuView instantiation (quit behavior is out of scope for unit tests)
- **All 212+ existing tests must continue passing (zero regressions).**

### Library & Framework Requirements

- `SwiftUI` -- PopoverFooterView, GearMenuView (already used in project)
- `AppKit` -- `NSApplication.shared.terminate(nil)` for quit (already available in macOS target)
- No new dependencies. Zero external packages.

### Anti-Patterns to Avoid

- DO NOT create a separate "freshness timer" -- use existing `countdownTick` observation pattern
- DO NOT store freshness state as a separate property -- use the derived `appState.dataFreshness` computed property
- DO NOT create StatusMessageView in this story -- that's story 4.5
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` -- protected file
- DO NOT use `DispatchQueue` or timers -- use existing countdownTick observation pattern
- DO NOT use `print()` -- use `os.Logger` if logging is needed (shouldn't be in views)
- DO NOT hardcode colors -- use semantic color tokens from Color+Headroom.swift and HeadroomState+SwiftUI.swift
- DO NOT add a "Settings" panel or additional menu items -- MVP is "Quit cc-hdrm" only

### References

- [Source: epics.md#Story 4.4] -- Full acceptance criteria
- [Source: ux-design-specification.md#GearMenu] -- Gear menu: SF Symbol gear, SwiftUI Menu, MVP: "Quit cc-hdrm", Phase 2: settings
- [Source: ux-design-specification.md#Spacing & Layout Foundation] -- Footer row: subscription tier (left), "updated Xs ago" (center), gear menu (right)
- [Source: ux-design-specification.md#Typography System] -- Subscription tier: caption size, tertiary. Timestamp: mini size, tertiary. Stale: amber/warning.
- [Source: ux-design-specification.md#Accessibility Considerations] -- VoiceOver labels, color independence
- [Source: architecture.md#App Architecture] -- MVVM, Views observe AppState read-only, GearMenu.swift in Views/
- [Source: architecture.md#FR24] -- Quit from menu bar -> Views/GearMenu.swift
- [Source: architecture.md#State Management Patterns] -- Services write to AppState, views read-only
- [Source: project-context.md#Date/Time Formatting] -- Countdown and freshness formatting rules
- [Source: AppState.swift:44] -- `subscriptionTier: String?` property
- [Source: AppState.swift:49] -- `countdownTick: UInt` property for periodic re-renders
- [Source: AppState.swift:58-63] -- `dataFreshness: DataFreshness` computed property
- [Source: DataFreshness.swift] -- `.fresh`, `.stale`, `.veryStale`, `.unknown` enum with thresholds
- [Source: PopoverView.swift:30-33] -- Current footer placeholder to replace
- [Source: story 4-3] -- Previous story patterns, test patterns, code review lessons

## Dev Agent Record

### Agent Model Used

claude-opus-4-5

### Debug Log References

None required.

### Completion Notes List

- ✅ Task 1: Created PopoverFooterView.swift — HStack layout with tier (caption/tertiary), freshness timestamp (caption2, conditional headroomWarning color for stale), and GearMenuView. Uses @ViewBuilder for conditional color styling. Reads countdownTick for periodic re-renders. VoiceOver combines children into single accessible element.
- ✅ Task 2: Created GearMenuView.swift — self-contained SwiftUI Menu with "Quit cc-hdrm" button calling NSApplication.shared.terminate(nil). Uses plain button style, gearshape SF Symbol, accessibilityLabel("Settings").
- ✅ Task 3: Updated PopoverView.swift — replaced placeholder Text with PopoverFooterView(appState:). Removed redundant `let status = appState.connectionStatus` and `let _ = appState.countdownTick` lines (both are read by child views directly).
- ✅ Task 4: Created PopoverFooterViewTests.swift — 7 tests covering: tier display (valid/nil), fresh/stale/disconnected states, observation tracking for subscriptionTier and lastUpdated changes.
- ✅ Task 5: Created GearMenuViewTests.swift — 2 tests: instantiation and NSHostingController hosting.
- ✅ Task 6: Updated PopoverViewTests.swift — renamed footerReflectsDisconnectedState to footerRendersInBothStates, added footerRendersWithSubscriptionTier test, added observationTriggersOnSevenDayChange test. Fixed existing appStateObservationTriggersReRender test to mutate sevenDay (PopoverView body no longer reads connectionStatus directly).
- All 223 tests pass (0 regressions). Build succeeds.

### Code Review Fixes (AI)

- **H1**: Renamed misleading `observationTriggersOnCountdownTick` test to `observationTriggersOnSevenDayChange` — PopoverView.body reads sevenDay directly (the `if` condition), not countdownTick (read by child views). Test now honestly reflects what it validates.
- **M1**: Replaced deprecated `.foregroundColor(.headroomWarning)` with `.foregroundStyle(Color.headroomWarning)` in PopoverFooterView.swift:39.
- **M4**: Improved `footerRendersInBothStates` test — now sets up connected state with tier/windows data and asserts `dataFreshness == .fresh`.
- **L1**: Fixed completion notes: "borderlessButton menu style" → "plain button style" to match actual implementation.
- **L2**: Fixed accessibility text to say "X minutes ago" when elapsed >= 60s, matching the visual "Xm ago" format.
- **M2** (non-deterministic Date() in computed properties): Acknowledged — would require injecting a clock abstraction. Out of scope for this story; deferred.
- **M3** (sprint-status unstaged): Process note — no code fix needed.

### Change Log

- 2026-02-01: Implemented story 4.4 — panel footer with subscription tier, data freshness timestamp, and gear menu with quit action.
- 2026-02-01: Code review fixes — deprecated API, misleading test, accessibility text, documentation accuracy.

### File List

- cc-hdrm/Views/PopoverFooterView.swift (NEW)
- cc-hdrm/Views/GearMenuView.swift (NEW)
- cc-hdrm/Views/PopoverView.swift (MODIFIED)
- cc-hdrmTests/Views/PopoverFooterViewTests.swift (NEW)
- cc-hdrmTests/Views/GearMenuViewTests.swift (NEW)
- cc-hdrmTests/Views/PopoverViewTests.swift (MODIFIED)
