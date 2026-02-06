# Story 13.4: Series Toggle Controls

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to toggle 5h and 7d series visibility,
So that I can focus on the window that matters for my analysis.

## Acceptance Criteria

1. **Given** the series toggle controls are visible
   **When** they render
   **Then** "5h" and "7d" appear as toggle buttons with distinct visual states
   **And** both are selected by default

2. **Given** Alex toggles off "7d"
   **When** the chart re-renders
   **Then** only the 5h series is visible
   **And** the 7d toggle shows as unselected (outline only)

3. **Given** both series are toggled off
   **When** the chart re-renders
   **Then** the chart shows empty state with message: "Select a series to display"

4. **Given** a time range is selected
   **When** the series toggle state is remembered
   **Then** toggle state persists per time range within the session
   **And** switching from 24h to 7d and back preserves the 24h toggle state

## Tasks / Subtasks

- [x] Task 1: Verify existing series toggle UI compliance (AC: 1, 2)
  - [x] 1.1 Audit `cc-hdrm/Views/AnalyticsView.swift:176-216` — confirm "5h" and "7d" toggle buttons render with correct labels
  - [x] 1.2 Confirm selected state shows filled circle icon (`circle.fill`) with accent color text
  - [x] 1.3 Confirm unselected state shows outline circle icon (`circle`) with secondary color text
  - [x] 1.4 Confirm both `fiveHourVisible` and `sevenDayVisible` default to `true` (line 19-20)
  - [x] 1.5 Confirm toggle buttons have `.accessibilityLabel` with series name and enabled/disabled state
  - [x] 1.6 Confirm toggle buttons have `.accessibilityHint("Press to toggle")`

- [x] Task 2: Verify series visibility propagation to UsageChart (AC: 2, 3)
  - [x] 2.1 Confirm `UsageChart` receives `fiveHourVisible` and `sevenDayVisible` props from `AnalyticsView.swift:44-45`
  - [x] 2.2 Confirm `UsageChart.swift:45-46` computes `anySeriesVisible` from the two props
  - [x] 2.3 Confirm both-off state renders `noSeriesMessage` ("Select a series to display") in `UsageChart.swift:54-62`
  - [x] 2.4 Confirm toggling one off hides only that series (once chart rendering is real in Stories 13.5-13.7, this prop flows correctly)

- [x] Task 3: Implement per-time-range toggle state persistence (AC: 4)
  - [x] 3.1 Replace `@State private var fiveHourVisible: Bool = true` and `@State private var sevenDayVisible: Bool = true` with a `@State private var seriesVisibility: [TimeRange: SeriesVisibility]` dictionary in `cc-hdrm/Views/AnalyticsView.swift`
  - [x] 3.2 Create a small `SeriesVisibility` struct (fiveHour: Bool, sevenDay: Bool, defaults both true) — define as a private struct inside `AnalyticsView` or as a standalone file if needed for testability
  - [x] 3.3 Add computed properties `fiveHourVisible` and `sevenDayVisible` that look up current `selectedTimeRange` in the dictionary, falling back to default (both true) for unvisited ranges
  - [x] 3.4 Update toggle button bindings to write into `seriesVisibility[selectedTimeRange]`
  - [x] 3.5 Verify `UsageChart` still receives correct `fiveHourVisible`/`sevenDayVisible` after refactor
  - [x] 3.6 Session-only persistence — no UserDefaults needed; dictionary resets on window close/reopen

- [x] Task 4: Add test coverage for series toggle behavior (AC: 1, 2, 3, 4)
  - [x] 4.1 Add test: both series visible by default (verify initial state for any TimeRange key)
  - [x] 4.2 Add test: toggling 5h off for `.day` range, switching to `.week`, then back to `.day` — verify 5h is still off for `.day`
  - [x] 4.3 Add test: toggling 7d off for `.week` does not affect `.day` range's toggle state
  - [x] 4.4 Add test: unvisited ranges default to both-visible
  - [x] 4.5 Add test: both series off produces `anySeriesVisible == false` in UsageChart
  - [x] 4.6 Add test: `fetchData` is NOT re-triggered by series toggle changes (only time range triggers reload)

- [x] Task 5: Build verification (AC: all)
  - [x] 5.1 Run `xcodegen generate`
  - [x] 5.2 Run `xcodebuild -scheme cc-hdrm -destination 'platform=macOS' build`
  - [x] 5.3 Run full test suite — all existing + new tests pass
  - [ ] 5.4 Manual: Open analytics, toggle 5h off on 24h view, switch to 7d, switch back — verify 5h still off on 24h
  - [ ] 5.5 Manual: Toggle both off — verify "Select a series to display" message
  - [ ] 5.6 Manual: Close and reopen analytics window — verify toggles reset to both-on

> **Note:** Tasks 5.4-5.6 require human manual verification.

## Dev Notes

### CRITICAL: Mostly Pre-Built, One Key Gap

Stories 13.1 and 13.2 already implemented the series toggle UI:

- **Story 13.1** created the toggle buttons inline in `cc-hdrm/Views/AnalyticsView.swift:176-216` with filled/outline circle styling, accent color, accessibility labels and hints, and `@Binding` toggle behavior.
- **Story 13.2** wired `UsageChart` to accept `fiveHourVisible`/`sevenDayVisible` props and render the "Select a series to display" empty state when both are off.

**The one missing AC is AC-4: per-time-range toggle state persistence.** Currently `fiveHourVisible` and `sevenDayVisible` are simple `@State` booleans (`cc-hdrm/Views/AnalyticsView.swift:19-20`) — they're global, not per-range. Switching from 24h to 7d and back resets them because they share state.

### Implementation Approach for Per-Range Persistence

The simplest approach: replace two `@State` booleans with a `@State` dictionary keyed by `TimeRange`.

```swift
// BEFORE (current):
@State private var fiveHourVisible: Bool = true
@State private var sevenDayVisible: Bool = true

// AFTER:
struct SeriesVisibility {
    var fiveHour: Bool = true
    var sevenDay: Bool = true
}

@State private var seriesVisibility: [TimeRange: SeriesVisibility] = [:]

private var currentVisibility: SeriesVisibility {
    seriesVisibility[selectedTimeRange] ?? SeriesVisibility()
}

private var fiveHourVisible: Bool {
    currentVisibility.fiveHour
}

private var sevenDayVisible: Bool {
    currentVisibility.sevenDay
}
```

Toggle buttons update `seriesVisibility[selectedTimeRange]` directly.

**Important:** The `.task(id: selectedTimeRange)` modifier in `AnalyticsView.swift:55` triggers `loadData()` only on `selectedTimeRange` changes. Series toggle changes should NOT trigger data reload — they only control which series `UsageChart` renders. This is already correct because `fiveHourVisible`/`sevenDayVisible` are not part of the `.task(id:)` trigger. Preserve this behavior after refactoring.

### Existing Toggle Button Implementation (Reference)

```swift
// cc-hdrm/Views/AnalyticsView.swift:196-216
private func seriesToggleButton(
    label: String,
    isActive: Binding<Bool>,
    accessibilityPrefix: String
) -> some View {
    Button(action: {
        isActive.wrappedValue.toggle()
    }) {
        HStack(spacing: 4) {
            Image(systemName: isActive.wrappedValue ? "circle.fill" : "circle")
                .font(.system(size: 8))
                .foregroundStyle(isActive.wrappedValue ? Color.accentColor : .secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(isActive.wrappedValue ? .primary : .secondary)
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(accessibilityPrefix), \(isActive.wrappedValue ? "enabled" : "disabled")")
    .accessibilityHint("Press to toggle")
}
```

This `seriesToggleButton` function takes a `Binding<Bool>`. After refactoring to per-range state, the binding must be derived from the `seriesVisibility` dictionary for the current `selectedTimeRange`. Use a computed `Binding` that reads and writes the correct dictionary entry:

```swift
private var fiveHourBinding: Binding<Bool> {
    Binding(
        get: { seriesVisibility[selectedTimeRange, default: SeriesVisibility()].fiveHour },
        set: { seriesVisibility[selectedTimeRange, default: SeriesVisibility()].fiveHour = $0 }
    )
}
```

### UsageChart Series Handling (Reference)

`cc-hdrm/Views/UsageChart.swift:24-27`:
```swift
private var anySeriesVisible: Bool {
    fiveHourVisible || sevenDayVisible
}
```

When both are false, it renders `noSeriesMessage` (`cc-hdrm/Views/UsageChart.swift:54-62`):
```swift
private var noSeriesMessage: some View {
    VStack(spacing: 6) {
        Image(systemName: "eye.slash")
            .font(.system(size: 24))
            .foregroundStyle(.secondary)
        Text("Select a series to display")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

This is already correct for AC-3. No changes needed to `UsageChart`.

### Existing Test Coverage

Tests already exist in:
- `cc-hdrmTests/Views/AnalyticsViewTests.swift` (284 lines) — 11 base tests + 11 data loading tests (from Story 13.3)
- `cc-hdrmTests/Views/UsageChartTests.swift` (165 lines) — 14 tests covering series visibility combos and empty states

**Relevant existing tests for series toggles:**
- `AnalyticsViewTests.seriesDefaultsDocumented()` — confirms both default true (AC-1 partial)
- `UsageChartTests.bothSeriesVisible/onlyFiveHourVisible/onlySevenDayVisible/bothSeriesOff` — confirms all visibility combos render (AC-2, AC-3)

**Gap:** No tests verify per-time-range toggle persistence (AC-4). Task 4 fills this.

### MockHistoricalDataService (Reference)

Located at `cc-hdrmTests/Mocks/MockHistoricalDataService.swift`. Has call count tracking (`getRecentPollsCallCount`, `getRolledUpDataCallCount`, etc.), configurable returns, error simulation, `lastQueriedTimeRange`, and `callOrder` tracking. Sufficient for all new tests.

### Project Structure Notes

**Modified files:**
```text
cc-hdrm/Views/AnalyticsView.swift          # Refactor toggle state to per-range dictionary
cc-hdrmTests/Views/AnalyticsViewTests.swift # Add per-range persistence tests
```

**No new files expected** unless `SeriesVisibility` is extracted to a standalone model file for testability.

**After any file changes, run:**
```bash
xcodegen generate
```

### Alignment with Existing Code Conventions

- **@MainActor:** `AnalyticsView` and its tests are `@MainActor`
- **Swift Testing framework:** Use `@Suite`, `@Test`, `#expect`
- **Protocol-based testing:** Use `MockHistoricalDataService`
- **Test naming:** `testNameDescribingBehavior` (e.g., `perRangeTogglePersistence`)
- **Logging:** `os.Logger(subsystem: "com.cc-hdrm.app", category: "analytics")`
- **Accessibility:** `.accessibilityLabel` + `.accessibilityHint` on all interactive elements

### Previous Story Intelligence

**From Story 13.3 (time-range-selector):**
- Extracted `fetchData(for:using:)` static method for testability — usable for verifying that series toggle changes don't trigger data reload (Task 4.6)
- 729 tests pass at Story 13.3 completion
- `AnalyticsView` uses `.task(id: selectedTimeRange)` — only time range changes trigger reload, not toggle state. Confirm this stays true after refactor.

**From Story 13.2 (analytics-view-layout):**
- `ensureRollupsUpToDate()` failure was decoupled from data loading (best-effort)
- `UsageChart` stub already handles all series visibility combos

**From Story 13.1 (analytics-window-shell):**
- TimeRangeSelector uses `HStack` of `Button` views
- Default time range `.week` was deliberate; series toggles should default to both-on regardless of range
- 691 tests at 13.1; 729 at 13.3

### Git Intelligence

Last 5 relevant commits:
- `42ecb1d` — resolve merge conflict: keep 13.3 done status
- `bed445f` — feat: verify time range selector and add data loading tests (Story 13.3)
- `40c35c5` — feat: analytics view layout with data wiring (Story 13.2)
- `f2fc561` — feat: Story 13.1 — Analytics Window Shell (NSPanel)
- `05d9df7` — feat: credit-math 7d promotion, gauge overlay, slope normalization (Story 3.3)

### Edge Cases

| No. | Condition | Expected Behavior |
|-----|-----------|-------------------|
| 1 | Toggle 5h off, switch range, switch back | 5h is still off for original range |
| 2 | Toggle both off on one range | Only that range shows "Select a series" — other ranges unaffected |
| 3 | First visit to a new range | Both series default to visible (no dictionary entry yet) |
| 4 | Close and reopen analytics window | All toggle states reset (session-only) |
| 5 | Toggle while data is loading | Toggle applies immediately (visual), no data reload triggered |
| 6 | Rapidly toggle and switch ranges | No race conditions — toggles are synchronous @State writes |

### References

- [Source: _bmad-output/planning-artifacts/epics.md:1510-1536] — Story 13.4 epic requirements
- [Source: _bmad-output/planning-artifacts/architecture.md:1190-1216] — AnalyticsView architecture spec
- [Source: _bmad-output/planning-artifacts/ux-design-specification-phase3.md:282-289] — Series toggle UX spec
- [Source: cc-hdrm/Views/AnalyticsView.swift:19-20] — Current toggle state declarations
- [Source: cc-hdrm/Views/AnalyticsView.swift:40-47] — UsageChart props including series visibility
- [Source: cc-hdrm/Views/AnalyticsView.swift:176-216] — Series toggle UI implementation
- [Source: cc-hdrm/Views/UsageChart.swift:24-27] — `anySeriesVisible` computation
- [Source: cc-hdrm/Views/UsageChart.swift:54-62] — "Select a series to display" empty state
- [Source: cc-hdrmTests/Views/AnalyticsViewTests.swift:59-68] — Existing series default test
- [Source: cc-hdrmTests/Views/UsageChartTests.swift:82-107] — Existing series visibility tests
- [Source: cc-hdrmTests/Mocks/MockHistoricalDataService.swift] — Shared mock for testing
- [Source: _bmad-output/implementation-artifacts/13-3-time-range-selector.md] — Previous story
- [Source: _bmad-output/implementation-artifacts/13-2-analytics-view-layout.md] — Layout wiring story
- [Source: _bmad-output/implementation-artifacts/13-1-analytics-window-shell.md] — Window shell story

## Change Log

- 2026-02-06: Implemented per-time-range series toggle persistence (AC-4). Replaced two @State booleans with dictionary-keyed SeriesVisibility struct.
- 2026-02-06: Added 9 new tests in AnalyticsViewSeriesToggleTests suite covering all ACs (default visibility, per-range persistence, range isolation, unvisited defaults, both-off state, fetchData isolation, Equatable, independent state).
- 2026-02-06: Fixed window close/reopen state reset — nil out cached panel in `windowWillClose` so a fresh AnalyticsView with reset @State is created on next open.
- 2026-02-06: Code review fixes — added 4 Binding-level tests (get/set closure verification), added explicit `internal` access modifier on SeriesVisibility, unified Binding get pattern to optional chaining for consistency with computed properties, documented panel recreation tradeoff.

## Dev Agent Record

### Agent Model Used

claude-opus-4-6

### Debug Log References

- Code signing issue on first test run resolved by clean build (`xcodebuild clean` + re-run)

### Completion Notes List

- Task 1: Audited existing toggle UI in AnalyticsView.swift — all 6 subtasks verified (labels, icons, colors, defaults, accessibility). No changes needed.
- Task 2: Audited UsageChart prop wiring — all 4 subtasks verified (props received, anySeriesVisible computed, noSeriesMessage renders, single-series hide works). No changes needed.
- Task 3: Replaced `@State fiveHourVisible/sevenDayVisible` booleans with `@State seriesVisibility: [TimeRange: SeriesVisibility]` dictionary. Added `SeriesVisibility` struct (Equatable, defaults both true) inside AnalyticsView. Added computed properties and computed `Binding` properties for per-range read/write. Updated toggle button bindings from `$fiveHourVisible`/`$sevenDayVisible` to `fiveHourBinding`/`sevenDayBinding`. UsageChart receives correct values via computed properties. Session-only — no UserDefaults.
- Task 4: Added 9 new tests in "AnalyticsView Series Toggle Persistence Tests" suite covering: defaults (4.1), per-range persistence across switches (4.2), range isolation (4.3), unvisited range defaults (4.4), both-off UsageChart behavior (4.5), fetchData not triggered by toggles (4.6), Equatable conformance, and independent state across all ranges.
- Task 5: xcodegen generate succeeded, build succeeded, 738/738 tests passed (729 existing + 9 new). Manual verification tasks (5.4-5.6) left for human review.
- Bug fix: Manual test 5.6 failed — toggle state survived window close/reopen because AnalyticsWindow cached the panel (and its AnalyticsView @State). Fixed by niling out `panel` in `windowWillClose` so a fresh AnalyticsView is created on next open. 738 tests still pass.
- Performance tradeoff (panel = nil): Niling the panel in `windowWillClose` means `createPanel()` runs on every reopen (new NSPanel + NSHostingView + AnalyticsView + `.task` re-triggers `loadData()`). Previously the panel was cached and reused, which was faster but prevented @State reset. Acceptable tradeoff since window open/close is an infrequent user action. Future optimization: selectively reset @State without destroying the panel (e.g., resetToken pattern).

### File List

- `cc-hdrm/Views/AnalyticsView.swift` — Modified: replaced @State booleans with per-range dictionary, added SeriesVisibility struct (explicit `internal` access), computed properties, computed bindings with consistent optional-chaining get pattern
- `cc-hdrm/Views/AnalyticsWindow.swift` — Modified: nil out panel in windowWillClose so @State resets on window close/reopen (fixes manual test 5.6)
- `cc-hdrmTests/Views/AnalyticsViewTests.swift` — Modified: updated seriesDefaultsDocumented test, added 9 per-range persistence tests + 4 Binding get/set closure verification tests (13 new total)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — Modified: 13-4-series-toggle-controls status ready-for-dev -> in-progress -> review
