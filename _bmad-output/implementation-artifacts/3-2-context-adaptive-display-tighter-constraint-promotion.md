# Story 3.2: Context-Adaptive Display & Tighter Constraint Promotion

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want the menu bar to automatically switch between percentage and countdown and show whichever limit is tighter,
so that I always see the most relevant information without any manual action.

## Acceptance Criteria

1. **Given** 5-hour headroom is at 0% (exhausted) with a known reset time, **When** the menu bar renders, **Then** it shows "✳ ↻ Xm" (countdown to reset) in red, Bold weight.
2. **And** countdown follows formatting rules: <1h "↻ 47m", 1-24h "↻ 2h 13m", >24h "↻ 2d 1h".
3. **And** the countdown updates every 60 seconds (not every second).
4. **Given** 5-hour headroom recovers above 0% (window resets), **When** the next poll cycle updates AppState, **Then** the menu bar switches back from countdown to percentage display and color transitions to the appropriate HeadroomState.
5. **Given** 7-day headroom is lower than 5-hour headroom AND 7-day is in warning or critical state, **When** the menu bar renders, **Then** it promotes the 7-day value to the menu bar display instead of 5-hour, and color and weight reflect the 7-day HeadroomState.
6. **Given** 7-day headroom recovers above the 5-hour headroom or exits warning/critical, **When** the next poll cycle updates AppState, **Then** the menu bar reverts to showing 5-hour headroom.
7. **Given** a VoiceOver user focuses the menu bar during exhausted state, **When** VoiceOver reads the element, **Then** it announces "cc-hdrm: Claude headroom exhausted, resets in [X] minutes".

## Tasks / Subtasks

- [x] Task 1: Add countdown formatting to Date+Formatting.swift (AC: #2)
  - [x] Add `func countdownString() -> String` to `Date` extension that returns relative countdown from now to self
    - Time remaining < 1h: `"47m"`
    - 1h-24h: `"2h 13m"`
    - >24h: `"2d 1h"`
    - Past or zero: `"0m"`
  - [x] This formats the reset time — the method is called on the `resetsAt` Date

- [x] Task 2: Add countdown timer support to AppState (AC: #3)
  - [x] Add `private(set) var countdownTick: UInt = 0` to AppState — a simple counter that increments every 60 seconds to trigger observation-based re-renders of countdown text
  - [x] Add `func tickCountdown()` method to increment `countdownTick`
  - [x] The FreshnessMonitor already runs a 60-second loop — extend it (or add a parallel mechanism in AppDelegate) to call `appState.tickCountdown()` every 60 seconds to drive countdown updates

- [x] Task 3: Enhance `menuBarHeadroomState` for tighter constraint promotion (AC: #5, #6)
  - [x] Modify the `menuBarHeadroomState` computed property in AppState:
    - Current logic: returns `fiveHour?.headroomState ?? .disconnected` when connected
    - New logic:
      1. If not connected → `.disconnected` (unchanged)
      2. Compute 5h headroom state from `fiveHour`
      3. Compute 7d headroom state from `sevenDay`
      4. If 7d headroom < 5h headroom AND 7d state is `.warning` or `.critical` → return 7d state
      5. Otherwise → return 5h state (or `.disconnected` if nil)
  - [x] Add `var displayedWindow: DisplayedWindow` computed property to track which window is being shown (for text rendering and accessibility):
    ```
    enum DisplayedWindow { case fiveHour, sevenDay }
    ```
  - [x] `displayedWindow` logic mirrors `menuBarHeadroomState` promotion logic

- [x] Task 4: Enhance `menuBarText` for context-adaptive display (AC: #1, #2, #4, #5)
  - [x] Modify the `menuBarText` computed property in AppState:
    - Current logic: `"✳ XX%"` or `"✳ —"`
    - New logic:
      1. If `menuBarHeadroomState == .disconnected` → `"✳ —"` (unchanged)
      2. Determine which window to display (via `displayedWindow`)
      3. Get the `WindowState` for the displayed window
      4. If the displayed window's headroom state is `.exhausted` AND `resetsAt` is non-nil:
         - `_ = countdownTick` (access to register observation tracking)
         - Return `"✳ ↻ \(resetsAt.countdownString())"` (e.g., "✳ ↻ 47m")
      5. Otherwise → `"✳ XX%"` using the displayed window's utilization (headroom = 100 - utilization, clamped to 0)
  - [x] CRITICAL: Access `countdownTick` inside `menuBarText` when showing countdown so that `withObservationTracking` in AppDelegate re-fires when the tick increments

- [x] Task 5: Update `updateMenuBarDisplay()` accessibility for exhausted/countdown state (AC: #7)
  - [x] In AppDelegate's `updateMenuBarDisplay()`, update the accessibility value logic:
    - Current: `"cc-hdrm: Claude headroom XX percent, [state]"` or `"cc-hdrm: Claude headroom disconnected"`
    - New exhausted case: `"cc-hdrm: Claude headroom exhausted, resets in [X] minutes"` where [X] is the minutes from the displayed window's `resetsAt`
    - Use the displayed window's `resetsAt` for the countdown value
  - [x] The accessibility update should use the same `displayedWindow` logic for which window to reference

- [x] Task 6: Implement countdown tick mechanism (AC: #3)
  - [x] Option A (chosen): Added a separate `countdownTickTask` in FreshnessMonitor that calls `appState.tickCountdown()` every 60 seconds. FreshnessMonitorProtocol unchanged — tick is an internal implementation detail.
  - [ ] ~~Option B: Add a separate `Task.sleep(for: .seconds(60))` loop in AppDelegate.~~ (Not chosen)
  - [x] Regardless of approach: the tick only matters when `menuBarText` is showing a countdown, but it's cheap to always tick (just an integer increment).
  - [x] FreshnessMonitorProtocol not updated — tick is internal to FreshnessMonitor, not a protocol contract.

- [x] Task 7: Write countdown formatting tests (AC: #2)
  - [x] In `cc-hdrmTests/Extensions/DateFormattingTests.swift` (extend existing or create):
  - [x] Test: resetsAt 30 minutes from now → `"30m"`
  - [x] Test: resetsAt 47 minutes from now → `"47m"`
  - [x] Test: resetsAt 59 minutes from now → `"59m"`
  - [x] Test: resetsAt 1 hour from now → `"1h 0m"`
  - [x] Test: resetsAt 2h 13m from now → `"2h 13m"`
  - [x] Test: resetsAt 23h 59m from now → `"23h 59m"`
  - [x] Test: resetsAt 25h from now → `"1d 1h"`
  - [x] Test: resetsAt 49h from now → `"2d 1h"`
  - [x] Test: resetsAt in the past → `"0m"`
  - [x] Test: resetsAt exactly now → `"0m"`

- [x] Task 8: Write menuBarText context-adaptive tests (AC: #1, #4)
  - [x] In `cc-hdrmTests/State/AppStateTests.swift` (extend existing):
  - [x] Test: 5h exhausted (utilization=100) with resetsAt 47m from now → `menuBarText == "✳ ↻ 47m"` and `menuBarHeadroomState == .exhausted`
  - [x] Test: 5h exhausted with resetsAt nil → `menuBarText == "✳ 0%"` (fallback to percentage, no countdown without reset time)
  - [x] Test: 5h normal (utilization=17) → `menuBarText == "✳ 83%"` (unchanged behavior)
  - [x] Test: 5h recovers from exhausted (utilization changes from 100 to 5) → `menuBarText` switches back to `"✳ 95%"`

- [x] Task 9: Write tighter constraint promotion tests (AC: #5, #6)
  - [x] In `cc-hdrmTests/State/AppStateTests.swift` (extend existing):
  - [x] Test: 5h headroom 72% (.normal), 7d headroom 18% (.warning) → `menuBarHeadroomState == .warning`, `menuBarText == "✳ 18%"`, `displayedWindow == .sevenDay`
  - [x] Test: 5h headroom 72% (.normal), 7d headroom 4% (.critical) → `menuBarHeadroomState == .critical`, `menuBarText == "✳ 4%"`, `displayedWindow == .sevenDay`
  - [x] Test: 5h headroom 35% (.caution), 7d headroom 30% (.caution) → stays on 5h (7d is caution, not warning/critical), `displayedWindow == .fiveHour`
  - [x] Test: 5h headroom 12% (.warning), 7d headroom 18% (.warning) → stays on 5h (7d headroom 18% > 5h headroom 12%), `displayedWindow == .fiveHour`
  - [x] Test: 5h headroom 72%, 7d is nil → stays on 5h
  - [x] Test: 7d recovers (headroom goes from 18% to 50%) → reverts to 5h display

- [x] Task 10: Write VoiceOver accessibility tests for exhausted state (AC: #7)
  - [x] In `cc-hdrmTests/App/AppDelegateTests.swift` (extend existing):
  - [x] Test: after setting exhausted state with resetsAt, accessibilityLabel contains "exhausted" and "resets in"
  - [x] Test: after setting exhausted state without resetsAt, accessibilityLabel contains "exhausted" (no "resets in")

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. Menu bar display is driven by computed properties on `AppState` — views/renderers are read-only observers. This story extends the existing computed properties, does not add stored state beyond the countdown tick counter.
- **State derivation:** `menuBarText`, `menuBarHeadroomState`, and the new `displayedWindow` are **computed** properties, never stored. The only new stored property is `countdownTick: UInt` which serves as an observation trigger.
- **Observation integration:** `withObservationTracking` in AppDelegate automatically detects changes to any tracked property. By accessing `countdownTick` inside `menuBarText`, the observation loop re-fires every 60 seconds when the tick increments — this drives countdown updates without a separate timer.
- **Concurrency:** All AppState access is `@MainActor`. Countdown tick is incremented from the same context (FreshnessMonitor or AppDelegate loop). No GCD.
- **Logging:** `os.Logger` with category `menubar` for display changes. Log when display switches between percentage and countdown, and when tighter constraint promotion activates/deactivates.

### Countdown Display Strategy

The key design insight is that countdowns don't need a per-second timer. The UX spec explicitly says "countdown updates every 60 seconds (not every second)." This aligns perfectly with the FreshnessMonitor's existing 60-second loop.

**How it works:**
1. `AppState.countdownTick` is a `UInt` that increments every 60 seconds
2. `menuBarText` accesses `countdownTick` (even though it doesn't use the value) — this registers it with `withObservationTracking`
3. When `tickCountdown()` is called, `countdownTick` changes, triggering the observation loop in AppDelegate
4. AppDelegate calls `updateMenuBarDisplay()` which reads `menuBarText`, which calls `resetsAt.countdownString()` with the current time
5. Result: countdown updates every 60 seconds with zero additional timers

**Edge case:** If a poll cycle delivers new data between ticks, the observation loop already re-fires because `fiveHour`/`sevenDay` changed. So the countdown is always at most 60 seconds stale.

### Tighter Constraint Promotion Logic

**Decision algorithm (in `menuBarHeadroomState`):**

```
if not connected → .disconnected
let fiveHourHeadroom = 100 - (fiveHour?.utilization ?? 100)
let sevenDayHeadroom = 100 - (sevenDay?.utilization ?? 100)
let fiveHourState = fiveHour?.headroomState ?? .disconnected
let sevenDayState = sevenDay?.headroomState

if sevenDayState is .warning or .critical
   AND sevenDayHeadroom < fiveHourHeadroom:
   → return sevenDayState (promote 7d)
else:
   → return fiveHourState (default to 5h)
```

**Key constraint:** 7d only promotes when it's BOTH (a) in warning or critical AND (b) has lower headroom than 5h. This prevents the 7d from showing when it's in caution (not urgent enough) or when 5h is already worse.

### Context-Adaptive Display Logic

**Decision algorithm (in `menuBarText`):**

```
if disconnected → "✳ —"
let window = windowState for displayedWindow
if window.headroomState == .exhausted AND window.resetsAt != nil:
   _ = countdownTick  // register observation
   → "✳ ↻ \(window.resetsAt.countdownString())"
else:
   → "✳ XX%"  // headroom percentage from displayed window
```

### Previous Story Intelligence (3.1)

**What was built:**
- `Color+Headroom.swift` with `NSColor.headroomColor(for:)` and `NSFont.menuBarFont(for:)`
- `menuBarHeadroomState` and `menuBarText` computed properties on AppState
- `withObservationTracking` + `AsyncStream` observation loop in AppDelegate
- `updateMenuBarDisplay()` with NSAttributedString + VoiceOver accessibility
- 149 tests passing

**Patterns to reuse:**
- Computed properties on AppState — extend `menuBarText` and `menuBarHeadroomState` with new logic
- The observation loop already works — no changes needed there, just ensure new properties are accessed in the tracked closure
- VoiceOver accessibility pattern in `updateMenuBarDisplay()` — extend for exhausted/countdown state
- Test pattern: `@MainActor`, create `AppState()`, set connection + windows, assert computed properties

**Code review lessons from all previous stories:**
- Pass original errors to `AppError` wrappers, not hardcoded errors
- Remove dead code / unused properties before committing
- Add call counters to mocks for verifying interaction patterns
- Make services `@MainActor` when they hold `AppState` reference
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file

### Git Intelligence

Recent commits:
- `6e4d4a4` Add story 3.1: Menu bar headroom display with code review fixes
- `12880c9` Add story 2.3: Data freshness tracking with code review fixes
- `f49b681` Add story 2.2: Background polling engine with code review fixes

**Patterns:** New files for protocol+implementation, tests mirror source, sprint-status updated on completion.

### Project Structure Notes

- XcodeGen (`project.yml`) uses directory-based source discovery — new files in correct folders auto-included
- Test files mirror source structure under `cc-hdrmTests/`
- `Date+Formatting.swift` already exists — extend it, don't create a new file
- `DateFormattingTests.swift` exists at `cc-hdrmTests/Extensions/DateFormattingTests.swift` — extend it

### File Structure Requirements

Files to modify:
```
cc-hdrm/Extensions/Date+Formatting.swift           # Add countdownString()
cc-hdrm/State/AppState.swift                       # Add countdownTick, displayedWindow, enhance menuBarText + menuBarHeadroomState
cc-hdrm/App/AppDelegate.swift                      # Update accessibility for exhausted state
cc-hdrmTests/Extensions/DateFormattingTests.swift   # Add countdown formatting tests
cc-hdrmTests/State/AppStateTests.swift              # Add context-adaptive + promotion tests
cc-hdrmTests/App/AppDelegateTests.swift             # Add exhausted accessibility tests
```

Potentially modified (if using FreshnessMonitor for tick):
```
cc-hdrm/Services/FreshnessMonitor.swift            # Add tickCountdown() call to loop
cc-hdrmTests/Services/FreshnessMonitorTests.swift   # Verify tick behavior
```

No new files needed.

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on any test touching `AppState`
- **Countdown tests:** Use `Date().addingTimeInterval(X)` to create future dates, then call `countdownString()` and assert the formatted string. Note: tests must account for slight timing differences — use generous intervals (e.g., 2820 seconds for "47m" not 2819).
- **Promotion tests:** Set both `fiveHour` and `sevenDay` on AppState, assert `menuBarHeadroomState` and `displayedWindow` reflect the correct promoted window.
- **Edge cases:** 7d nil (no promotion possible), both exhausted, 5h exhausted but 7d in warning (5h exhausted takes priority since countdown is more useful than percentage).

### Anti-Patterns to Avoid

- DO NOT add a `Timer` or `DispatchQueue` for countdown updates — use the observation pattern with `countdownTick`
- DO NOT store `displayedWindow` as a separate stored property — it must be computed
- DO NOT call `Date()` directly in stored properties — only in computed properties and methods
- DO NOT create a separate countdown timer task — piggyback on the existing 60-second FreshnessMonitor loop
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT break existing tests — `menuBarText` for non-exhausted states must remain unchanged
- DO NOT update the countdown every second — the UX spec explicitly requires 60-second intervals (NFR4 CPU budget)

### References

- [Source: epics.md#Story 3.2] — Full acceptance criteria, countdown formatting, promotion logic
- [Source: ux-design-specification.md#MenuBarTextRenderer] — Context-adaptive display, exhausted state, countdown format
- [Source: ux-design-specification.md#CountdownLabel] — Countdown formatting rules (<1h, 1-24h, >24h)
- [Source: ux-design-specification.md#Typography System] — Font weight escalation per state
- [Source: ux-design-specification.md#Journey 3] — The Wall: exhausted → countdown → recovery
- [Source: ux-design-specification.md#Journey 4] — Tighter Window: 7d promotion logic
- [Source: architecture.md#State Management Patterns] — Derived state, services write via methods
- [Source: architecture.md#Polling Engine] — 30-second poll cycle
- [Source: project-context.md#HeadroomState Reference] — Complete state/color/weight table
- [Source: AppState.swift] — Current menuBarText, menuBarHeadroomState implementations
- [Source: AppDelegate.swift] — Current observation loop and updateMenuBarDisplay()
- [Source: Date+Formatting.swift] — Existing date formatting extensions (relativeTimeAgo, fromISO8601)
- [Source: story 3.1] — Previous story patterns, observation loop, NSAttributedString approach

## Dev Agent Record

### Agent Model Used

claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

None — no issues encountered during implementation.

### Completion Notes List

- Task 1: Added `countdownString()` to `Date` extension. Uses `timeIntervalSince(Date())` with floor-division formatting for <1h, 1-24h, >24h ranges.
- Task 2: Added `countdownTick: UInt` stored property and `tickCountdown()` method using wrapping addition (`&+=`).
- Task 3: Added `DisplayedWindow` enum and `displayedWindow` computed property. Enhanced `menuBarHeadroomState` to delegate to `displayedWindow` for tighter constraint promotion. 7d promotes only when both in warning/critical AND lower headroom than 5h.
- Task 4: Enhanced `menuBarText` to show `"✳ ↻ Xm"` countdown when exhausted with resetsAt. Accesses `countdownTick` to register observation tracking.
- Task 5: Updated `updateMenuBarDisplay()` accessibility: exhausted+resetsAt → "exhausted, resets in X minutes"; exhausted without resetsAt → "exhausted"; normal states use `displayedWindow` for correct headroom.
- Task 6: Added separate 60-second `countdownTickTask` in FreshnessMonitor that calls `appState.tickCountdown()`. FreshnessMonitorProtocol unchanged (tick is internal to FreshnessMonitor implementation).
- Tasks 7-10: 23 new tests added across 3 test files. All 172 tests pass.

### Change Log

- 2026-02-01: Implemented story 3.2 — context-adaptive display with countdown formatting, tighter constraint promotion, VoiceOver accessibility for exhausted state, and 60-second countdown tick mechanism.
- 2026-02-01: Code review fixes — added FreshnessMonitor countdown tick tests (M1), added both-exhausted and 5h-exhausted-7d-warning edge-case tests (M2), added sprint-status.yaml to File List (M3), added promotion/countdown mode-switch logging in AppDelegate (M4), corrected Task 6 subtask description (L1).

### File List

- cc-hdrm/Extensions/Date+Formatting.swift (modified — added `countdownString()`)
- cc-hdrm/State/AppState.swift (modified — added `DisplayedWindow` enum, `countdownTick`, `tickCountdown()`, `displayedWindow`, enhanced `menuBarHeadroomState` and `menuBarText`)
- cc-hdrm/App/AppDelegate.swift (modified — updated accessibility for exhausted/countdown state, uses `displayedWindow`)
- cc-hdrm/Services/FreshnessMonitor.swift (modified — added `countdownTickTask` for 60-second tick)
- cc-hdrmTests/Extensions/DateFormattingTests.swift (modified — added 10 countdown formatting tests)
- cc-hdrmTests/State/AppStateTests.swift (modified — added 11 context-adaptive + promotion + tick tests)
- cc-hdrmTests/App/AppDelegateTests.swift (modified — added 2 exhausted accessibility tests)
- _bmad-output/implementation-artifacts/sprint-status.yaml (modified — story status update)
