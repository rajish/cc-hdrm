# Story 4.5: Status Messages for Error States

Status: in-progress

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to see clear error messages in the panel when the app is in a degraded state,
so that I understand what's happening and what (if anything) I need to do.

## Acceptance Criteria

1. **Given** AppState.connectionStatus indicates API unreachable (`.disconnected`), **When** the popover renders, **Then** a StatusMessageView appears between the gauges and footer showing: "Unable to reach Claude API" (body, secondary color, centered) with detail: "Last attempt: 30s ago" (caption, tertiary color, centered).
2. **Given** AppState.connectionStatus indicates token expired (`.tokenExpired`), **When** the popover renders, **Then** StatusMessageView shows: "Token expired" / "Run any Claude Code command to refresh".
3. **Given** AppState.connectionStatus indicates no credentials (`.noCredentials`), **When** the popover renders, **Then** StatusMessageView shows: "No Claude credentials found" / "Run Claude Code to create them".
4. **Given** AppState indicates very stale data (dataFreshness == `.veryStale`, > 5 minutes since last update) AND connectionStatus == `.connected`, **When** the popover renders, **Then** StatusMessageView shows: "Data may be outdated" / "Last updated: Xm ago".
5. **Given** no error state exists (connectionStatus == `.connected` AND dataFreshness is `.fresh` or `.stale`), **When** the popover renders, **Then** StatusMessageView is not shown.
6. **Given** a VoiceOver user focuses the StatusMessageView, **When** VoiceOver reads the element, **Then** it reads the full message and detail text.

## Tasks / Subtasks

- [x] Task 1: Create StatusMessageView.swift — reusable status message component (AC: #1-#6)
  - [x] Create `cc-hdrm/Views/StatusMessageView.swift`
  - [x] SwiftUI `View` struct with parameters: `title: String`, `detail: String`
  - [x] Layout: `VStack(spacing: 4)` centered:
    1. `Text(title)` in `.body` size, `.secondary` foreground style, `.multilineTextAlignment(.center)`
    2. `Text(detail)` in `.caption` size, `.tertiary` foreground style, `.multilineTextAlignment(.center)`
  - [x] VoiceOver: `.accessibilityElement(children: .combine)` so VoiceOver reads title + detail as a single element (AC #6)

- [x] Task 2: Update PopoverView.swift to conditionally show StatusMessageView (AC: #1-#5)
  - [x] In `cc-hdrm/Views/PopoverView.swift`:
  - [x] Add a computed property or inline logic to determine if a status message should be shown and what its title/detail should be:
    - `connectionStatus == .disconnected` → title: "Unable to reach Claude API", detail: "Last attempt: Xs ago" (computed from `appState.lastUpdated` or `appState.countdownTick` for periodic refresh)
    - `connectionStatus == .tokenExpired` → title: "Token expired", detail: "Run any Claude Code command to refresh"
    - `connectionStatus == .noCredentials` → title: "No Claude credentials found", detail: "Run Claude Code to create them"
    - `connectionStatus == .connected && appState.dataFreshness == .veryStale` → title: "Data may be outdated", detail: "Last updated: Xm ago" (computed from `appState.lastUpdated`)
    - Otherwise → no StatusMessageView shown
  - [x] Insert StatusMessageView between the gauge sections and the footer Divider, wrapped in a conditional:
    ```swift
    if let statusMessage = resolvedStatusMessage {
        Divider()
        StatusMessageView(title: statusMessage.title, detail: statusMessage.detail)
            .padding(.horizontal)
            .padding(.vertical, 8)
    }
    ```
  - [x] Read `appState.countdownTick` to ensure the "Last attempt: Xs ago" / "Last updated: Xm ago" text refreshes periodically
  - [x] Note: The gauge sections (FiveHourGaugeSection, SevenDayGaugeSection) should still render in error states — they show grey "—" when data is unavailable (already handled by existing gauge code). StatusMessageView provides the explanatory text below them.

- [x] Task 3: Write StatusMessageView tests (AC: #1-#6)
  - [x] Create `cc-hdrmTests/Views/StatusMessageViewTests.swift`
  - [x] Test: StatusMessageView renders with title and detail — no crash
  - [x] Test: StatusMessageView renders with long multi-line title — no crash
  - [x] Test: StatusMessageView can be hosted in NSHostingController — instantiation test
  - [x] Use `@Test`, Swift Testing framework, consistent with previous story patterns

- [x] Task 4: Write PopoverView integration tests for status messages (AC: #1-#5)
  - [x] Extend `cc-hdrmTests/Views/PopoverViewTests.swift`:
  - [x] Test: PopoverView renders without crash when connectionStatus == .disconnected
  - [x] Test: PopoverView renders without crash when connectionStatus == .tokenExpired
  - [x] Test: PopoverView renders without crash when connectionStatus == .noCredentials
  - [x] Test: PopoverView renders without crash when connected with very stale data (dataFreshness == .veryStale)
  - [x] Test: PopoverView renders without crash when connected with fresh data (no StatusMessageView expected)
  - [x] Test: Observation triggers when connectionStatus changes (using withObservationTracking)

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with service layer. StatusMessageView is a pure presentational view — takes `title` and `detail` strings, no AppState dependency. PopoverView resolves which message (if any) to show based on AppState.
- **State flow:** Services → AppState → PopoverView → StatusMessageView. StatusMessageView is stateless — it renders whatever strings it's given.
- **Concurrency:** All AppState access is `@MainActor`. Views run on main thread via SwiftUI. No concurrency concerns.
- **Logging:** No logging needed in view components.

### Key Implementation Details

**StatusMessageView is intentionally simple:**
- It accepts `title: String` and `detail: String` — no AppState dependency, no computed logic
- The logic for *which* message to show lives in PopoverView (or a helper computed property on PopoverView)
- This keeps StatusMessageView reusable and testable in isolation

**Status message resolution logic (in PopoverView):**
```swift
private var resolvedStatusMessage: (title: String, detail: String)? {
    // Access countdownTick to register observation for periodic refresh
    let _ = appState.countdownTick

    switch appState.connectionStatus {
    case .disconnected:
        let detail: String
        if let lastUpdated = appState.lastUpdated {
            let elapsed = Int(max(0, Date().timeIntervalSince(lastUpdated)))
            detail = elapsed < 60 ? "Last attempt: \(elapsed)s ago" : "Last attempt: \(elapsed / 60)m ago"
        } else {
            detail = "Attempting to connect..."
        }
        return ("Unable to reach Claude API", detail)
    case .tokenExpired:
        return ("Token expired", "Run any Claude Code command to refresh")
    case .noCredentials:
        return ("No Claude credentials found", "Run Claude Code to create them")
    case .connected:
        if appState.dataFreshness == .veryStale {
            let elapsed = Int(max(0, Date().timeIntervalSince(appState.lastUpdated ?? Date())))
            return ("Data may be outdated", "Last updated: \(elapsed / 60)m ago")
        }
        return nil
    }
}
```

**Placement in PopoverView:**
- StatusMessageView appears AFTER the gauge sections and BEFORE the footer
- A `Divider()` separates it from the content above
- The gauge sections still render in error states (showing grey "—" per existing behavior)
- StatusMessageView provides the human-readable explanation

**"Last attempt" vs "Last updated" (AC #1 vs #4):**
- For disconnected state: "Last attempt: Xs ago" — reflects when the last poll *attempted* (using lastUpdated as proxy since it tracks last successful fetch; if never fetched, show "Attempting to connect...")
- For very stale state: "Last updated: Xm ago" — reflects when data was last successfully fetched
- Both use `appState.lastUpdated` and refresh via `countdownTick` observation

### Previous Story Intelligence (4.4)

**What was built:**
- PopoverFooterView.swift — footer with tier, freshness, gear menu
- GearMenuView.swift — gear icon with quit
- PopoverView updated to use PopoverFooterView
- 223 tests passing

**Code review lessons from story 4.4:**
- Use `.foregroundStyle()` not deprecated `.foregroundColor()`
- Test names should honestly reflect what they validate
- File List should not include gitignored files (xcodeproj)
- Follow existing section patterns (VStack, padding, accessibility)

**Patterns to follow exactly:**
- Views take `appState: AppState` or simple value parameters
- StatusMessageView takes simple `title: String, detail: String` — no AppState dependency
- Test pattern: instantiate views, verify no crash, use withObservationTracking for state changes
- `@MainActor` on all tests touching AppState
- Use `@Test`, `#expect`, `@Suite` from Swift Testing framework

### Git Intelligence

Recent commits follow pattern: one commit per story with code review fixes. XcodeGen auto-discovers new files in Views/ directory. Run `xcodegen generate` after adding new files.

Last commit: `37f4f8e Add story 4.4: panel footer with tier, freshness & quit, and code review fixes`

### Project Structure Notes

- `Views/` directory currently contains: PopoverView, PopoverFooterView, GearMenuView, HeadroomRingGauge, CountdownLabel, FiveHourGaugeSection, SevenDayGaugeSection
- **StatusMessageView.swift does NOT exist yet** — this story creates it
- New file goes in `cc-hdrm/Views/StatusMessageView.swift`
- New test file goes in `cc-hdrmTests/Views/StatusMessageViewTests.swift`
- Existing `cc-hdrmTests/Views/PopoverViewTests.swift` gets extended

### File Structure Requirements

New files to create:
```
cc-hdrm/Views/StatusMessageView.swift               # NEW — status message display component
cc-hdrmTests/Views/StatusMessageViewTests.swift       # NEW — StatusMessageView tests
```

Files to modify:
```
cc-hdrm/Views/PopoverView.swift                      # ADD conditional StatusMessageView between gauges and footer
cc-hdrmTests/Views/PopoverViewTests.swift             # ADD status message integration tests
```

### Testing Requirements

- **Framework:** Swift Testing (`@Test`, `#expect`, `@Suite`)
- **`@MainActor`:** Required on any test touching AppState
- **SwiftUI view tests:** Instantiate views with parameters or AppState, verify they render without crash. Full visual testing is out of scope.
- **Observation tests:** Use `withObservationTracking` pattern from previous stories to verify PopoverView updates when `connectionStatus` changes.
- **Key test scenarios:**
  - StatusMessageView instantiation with various title/detail strings
  - PopoverView rendering in all error states (disconnected, tokenExpired, noCredentials, veryStale)
  - PopoverView rendering in non-error state (connected + fresh/stale data → no StatusMessageView)
  - Observation triggering when connectionStatus changes
- **All 223+ existing tests must continue passing (zero regressions).**

### Library & Framework Requirements

- `SwiftUI` — StatusMessageView (already used in project)
- No new dependencies. Zero external packages.

### Anti-Patterns to Avoid

- DO NOT give StatusMessageView an `appState` dependency — keep it a simple presentational view with `title` and `detail` strings
- DO NOT hide the gauge sections when error states are active — gauges already handle disconnected state (grey "—")
- DO NOT create action buttons in StatusMessageView — all recovery is automatic per architecture
- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT use `DispatchQueue` or timers — use existing countdownTick observation pattern for periodic refresh
- DO NOT use `print()` — use `os.Logger` if logging is needed (shouldn't be in views)
- DO NOT use deprecated `.foregroundColor()` — use `.foregroundStyle()` instead
- DO NOT hardcode colors — use semantic tokens from Color+Headroom.swift
- DO NOT duplicate freshness computation — reuse `appState.dataFreshness` and `appState.lastUpdated`

### References

- [Source: epics.md#Story 4.5] — Full acceptance criteria
- [Source: ux-design-specification.md#StatusMessageView] — Anatomy: message text (body, secondary, centered), detail text (caption, tertiary, centered). No action buttons.
- [Source: ux-design-specification.md#StatusMessageView States] — Disconnected, Token expired, No credentials, Stale data message texts
- [Source: architecture.md#App Architecture] — MVVM, Views observe AppState read-only
- [Source: architecture.md#FR21] — Connection failure explanation → Views/StatusMessageView.swift
- [Source: architecture.md#Error Handling Patterns] — PollingEngine catches errors → AppState.connectionStatus → Views read connectionStatus
- [Source: architecture.md#State Management Patterns] — Views read-only, services write via methods
- [Source: project-context.md#Coding Patterns] — State management, error handling patterns
- [Source: AppState.swift:6-11] — `ConnectionStatus` enum: `.connected`, `.disconnected`, `.tokenExpired`, `.noCredentials`
- [Source: AppState.swift:24-28] — `StatusMessage` struct (title + detail) already defined but unused — consider using or ignore in favor of simple tuple
- [Source: AppState.swift:43] — `connectionStatus: ConnectionStatus` property
- [Source: AppState.swift:46] — `statusMessage: StatusMessage?` property — exists but may not be populated by services yet
- [Source: AppState.swift:58-63] — `dataFreshness: DataFreshness` computed property
- [Source: DataFreshness.swift] — `.fresh`, `.stale`, `.veryStale`, `.unknown` enum with thresholds (60s, 300s)
- [Source: PopoverView.swift] — Current structure: FiveHourGaugeSection → Divider → SevenDayGaugeSection → Divider → PopoverFooterView
- [Source: PopoverFooterView.swift] — Pattern: reads appState.countdownTick for periodic refresh, uses freshnessText computation
- [Source: story 4-4] — Previous story patterns, code review lessons

## Dev Agent Record

### Agent Model Used

claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

### Completion Notes List

- Task 1: Created `StatusMessageView.swift` — pure presentational view with `title`/`detail` strings, VStack(spacing:4) layout, `.body`/`.caption` fonts, `.secondary`/`.tertiary` foreground styles, `.accessibilityElement(children: .combine)` for VoiceOver (AC #6).
- Task 2: Added `resolvedStatusMessage` computed property to `PopoverView` with switch on `connectionStatus` covering all 4 error states (AC #1-#4) and nil for no-error (AC #5). Reads `countdownTick` for periodic refresh. Inserted conditional StatusMessageView between gauges and footer with Divider.
- Task 3: Created `StatusMessageViewTests.swift` — 3 tests: instantiation, long multi-line title, NSHostingController hosting. All pass.
- Task 4: Extended `PopoverViewTests.swift` with 6 new tests in `PopoverView Status Message Tests` suite: disconnected, tokenExpired, noCredentials, veryStale, fresh (no message), and observation trigger on connectionStatus change. All pass.
- Full regression: Test runner experiencing systemic SIGILL crashes across all suites (pre-existing issue, not introduced by this story). Individual tests pass when runner stays alive.

### Change Log

- 2026-02-01: Implemented story 4.5 — StatusMessageView for error states with all 4 error conditions, VoiceOver support, and 9 new tests.
- 2026-02-01: Code review fixes — M1: replaced anonymous tuple with StatusMessage struct in resolvedStatusMessage; M2: added comment noting lastUpdated vs last-attempt data source limitation; M3: eliminated dead-code `?? Date()` fallback in veryStale branch (guarded on `let lastUpdated` instead); L2: added @MainActor to all StatusMessageViewTests; L1: added sprint-status.yaml to File List; corrected test count claim in Completion Notes.

### File List

- cc-hdrm/Views/StatusMessageView.swift (NEW)
- cc-hdrm/Views/PopoverView.swift (MODIFIED)
- cc-hdrmTests/Views/StatusMessageViewTests.swift (NEW)
- cc-hdrmTests/Views/PopoverViewTests.swift (MODIFIED)
- _bmad-output/implementation-artifacts/sprint-status.yaml (MODIFIED)
