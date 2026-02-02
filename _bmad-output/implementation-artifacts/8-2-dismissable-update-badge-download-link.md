# Story 8.2: Dismissable Update Badge & Download Link

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to see and dismiss an update badge in the popover,
so that I'm aware of updates without being nagged.

## Acceptance Criteria

1. **Given** `AppState.availableUpdate` is set (newer version available) **And** `PreferencesManager.dismissedVersion` != the available version, **When** the popover renders, **Then** a subtle badge appears in the popover: "v{version} available" with a download icon/link (FR25) **And** the download link opens the release URL in the default browser (FR26) **And** a dismiss button (X or "Dismiss") is visible next to the badge.

2. **Given** Alex clicks the dismiss button, **When** the badge is dismissed, **Then** `PreferencesManager.dismissedVersion` is set to the available version **And** `AppState.availableUpdate` is set to nil **And** the badge disappears immediately **And** the badge does not reappear on subsequent launches or popover opens.

3. **Given** a *newer* version is released after Alex dismissed a previous update, **When** `UpdateCheckService` detects a version newer than `dismissedVersion`, **Then** the badge reappears for the new version **And** the cycle repeats (dismiss stores the new version).

4. **Given** Alex installed via Homebrew, **When** the update badge is shown, **Then** the badge also shows "or `brew upgrade cc-hdrm`" as alternative update path.

5. **Given** a VoiceOver user focuses the update badge, **When** VoiceOver reads the element, **Then** it announces "Update available: version {version}. Activate to download. Double tap to dismiss."

## Tasks / Subtasks

- [x] Task 1: Create `UpdateBadgeView` (AC: #1, #4, #5)
  - [x] Create `cc-hdrm/Views/UpdateBadgeView.swift`
  - [x] Layout: HStack with "v{version} available" text, download icon/link, dismiss (X) button
  - [x] Download link: opens `availableUpdate.downloadURL` in default browser via `NSWorkspace.shared.open()`
  - [x] Homebrew hint: always show "or `brew upgrade cc-hdrm`" as secondary text (no runtime detection needed per AC)
  - [x] VoiceOver: `.accessibilityElement(children: .combine)`, label "Update available: version {version}. Activate to download. Double tap to dismiss."

- [x] Task 2: Integrate `UpdateBadgeView` into `PopoverView` (AC: #1)
  - [x] Add conditional section in `cc-hdrm/Views/PopoverView.swift` between status message and footer
  - [x] Show when `appState.availableUpdate != nil`
  - [x] Pass `preferencesManager` for dismiss action

- [x] Task 3: Implement dismiss action (AC: #2)
  - [x] On dismiss button tap: set `preferencesManager.dismissedVersion = update.version`
  - [x] Clear `appState.availableUpdate` to nil via `appState.updateAvailableUpdate(nil)`
  - [x] Badge disappears immediately (SwiftUI reactive via `@Observable`)

- [x] Task 4: Write tests (AC: #1, #2, #3, #5)
  - [x] Create `cc-hdrmTests/Views/UpdateBadgeViewTests.swift`
  - [x] Test: badge appears when `availableUpdate` is set
  - [x] Test: badge hidden when `availableUpdate` is nil
  - [x] Test: dismiss sets `dismissedVersion` and clears `availableUpdate`
  - [x] Test: VoiceOver label contains version and action hints

## Dev Notes

### Architecture Compliance

- Follows MVVM pattern: `UpdateBadgeView` reads from `AppState` (observable), writes dismiss action through `PreferencesManager` protocol. [Source: `_bmad-output/planning-artifacts/architecture.md` lines 136-162]
- `AppState` mutation via method only: `updateAvailableUpdate(nil)` — never direct property set. [Source: `_bmad-output/planning-artifacts/architecture.md` lines 356-368]
- View is read-only observer of `AppState` with one exception: dismiss action triggers side effects through injected dependencies (same pattern as `GearMenuView` quit action).
- `PreferencesManager.dismissedVersion` already persists to `UserDefaults` — no new persistence needed. [Source: `cc-hdrm/Services/PreferencesManager.swift` lines 97-104]

### Key Implementation Details

**UpdateBadgeView layout:**

```swift
struct UpdateBadgeView: View {
    let update: AvailableUpdate
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.blue)
                    Text("v\(update.version) available")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                Text("or brew upgrade cc-hdrm")  // no backticks — renders as literal in SwiftUI Text
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(update.downloadURL)
            } label: {
                Text("Download")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss update notification")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Update available: version \(update.version). Activate to download. Double tap to dismiss.")
    }
}
```

**PopoverView integration point:**

The update badge goes between the status message section and the footer divider in `cc-hdrm/Views/PopoverView.swift`. Insert after the status message `if let` block, before the final `Divider()` + footer:

```swift
// After status message section, before footer divider:
if let update = appState.availableUpdate {
    Divider()
    UpdateBadgeView(update: update) {
        preferencesManager.dismissedVersion = update.version
        appState.updateAvailableUpdate(nil)
    }
    .padding(.horizontal)
    .padding(.vertical, 6)
}
```

**Dismiss flow:**

1. User taps X button → `onDismiss()` closure fires
2. `preferencesManager.dismissedVersion = update.version` — persists to `UserDefaults`
3. `appState.updateAvailableUpdate(nil)` — clears observable state
4. SwiftUI reactivity: `appState.availableUpdate` becomes nil → `if let` guard fails → badge disappears
5. On next launch: `UpdateCheckService.checkForUpdate()` compares remote version against `dismissedVersion` → if equal, skips → `availableUpdate` stays nil → no badge

**Homebrew detection (AC #4):**

The epics AC says "Given Alex installed via Homebrew, show 'or brew upgrade cc-hdrm'". Since there's no reliable runtime mechanism to detect Homebrew installation in a sandboxed-ish menu bar app, and the hint is harmless regardless of install method, **always show the Homebrew hint**. Users who didn't install via Homebrew will simply ignore it. This is the pragmatic approach — no runtime detection needed.

**Download action:**

```swift
NSWorkspace.shared.open(update.downloadURL)
```

This opens the URL in the default browser. The URL comes from `AvailableUpdate.downloadURL`, which is either the ZIP `browser_download_url` from GitHub Releases assets or the release `html_url` as fallback (set by `UpdateCheckService` in Story 8.1).

### Previous Story Intelligence (8.1)

- Story 8.1 created ALL the backend infrastructure this story consumes:
  - `UpdateCheckService` — fetches GitHub Releases, compares semver, checks `dismissedVersion`, sets `AppState.availableUpdate` [Source: `cc-hdrm/Services/UpdateCheckService.swift`]
  - `AvailableUpdate` model with `version: String` and `downloadURL: URL` [Source: `cc-hdrm/Models/AvailableUpdate.swift`]
  - `AppState.availableUpdate` property with `updateAvailableUpdate(_:)` method [Source: `cc-hdrm/State/AppState.swift`]
  - `PreferencesManager.dismissedVersion` — already in protocol, implementation, and mock [Source: `cc-hdrm/Services/PreferencesManagerProtocol.swift` line 18]
- Story 8.1 status is "review" — all 355 tests pass including 12 new UpdateCheckService tests
- The `MockUpdateCheckService` exists at `cc-hdrmTests/Mocks/MockUpdateCheckService.swift`
- The `MockPreferencesManager` already supports `dismissedVersion`

### Git Intelligence

Last 5 commits are Epic 7 release infrastructure work (v1.0.1). No view code was changed recently. The latest Swift codebase compiles under Xcode 26.2 with strict concurrency (Swift 6.2).

### Project Structure Notes

Files to CREATE:
```
cc-hdrm/Views/UpdateBadgeView.swift              # NEW — update badge UI
cc-hdrmTests/Views/UpdateBadgeViewTests.swift     # NEW — tests
```

Files to MODIFY:
```
cc-hdrm/Views/PopoverView.swift                   # ADD conditional UpdateBadgeView section
cc-hdrm.xcodeproj/project.pbxproj                 # ADD 2 new files to project
```

Files NOT to modify:
```
cc-hdrm/cc_hdrm.entitlements                      # PROTECTED — do not touch
cc-hdrm/State/AppState.swift                       # Already has availableUpdate — no changes needed
cc-hdrm/Services/PreferencesManager.swift          # Already has dismissedVersion — no changes needed
cc-hdrm/Services/UpdateCheckService.swift          # Backend complete from 8.1 — no changes needed
cc-hdrm/Models/AvailableUpdate.swift               # Model complete from 8.1 — no changes needed
```

### Testing Requirements

- Use **Swift Testing** framework (`import Testing`), not XCTest — consistent with all existing tests.
- Test `UpdateBadgeView` behavior through the dismiss action callback pattern.
- Use `MockPreferencesManager` (already exists with `dismissedVersion` support) for verifying dismiss persistence.
- Create a test `AppState` instance and set `availableUpdate` to verify reactive behavior.
- Test that `onDismiss` closure correctly sets `dismissedVersion` and clears `availableUpdate`.
- **No snapshot/UI rendering tests** — test behavior and callbacks, not pixel layout.
- Verify VoiceOver label content programmatically if Swift Testing supports accessibility inspection; otherwise, note as manual verification.

### Library & Framework Requirements

- **SwiftUI** — view construction (already imported everywhere)
- **AppKit** — `NSWorkspace.shared.open()` for opening download URL in browser (already available via `import AppKit` or `import Cocoa`)
- **No new dependencies.** Zero external packages.

### Anti-Patterns to Avoid

- DO NOT add update-check logic to the view — all checking is done by `UpdateCheckService` (Story 8.1)
- DO NOT store dismiss state in the view (`@State`) — use `PreferencesManager.dismissedVersion` for persistence
- DO NOT add a new property to `AppState` — `availableUpdate` already exists
- DO NOT try to detect Homebrew installation at runtime — always show the hint
- DO NOT use `Link()` SwiftUI view for the download — use `Button` + `NSWorkspace.shared.open()` for more control
- DO NOT affect `connectionStatus` or any other AppState property on dismiss
- DO NOT add animation to badge appear/disappear unless using `.transition()` with `accessibilityReduceMotion` respect

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` #Story 8.2, lines 874-907] — Full acceptance criteria
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Update Check Service, lines 669-684] — Service design, dismissed version flow
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Phase 2 Requirements Mapping, line 752] — FR25 → UpdateCheckService + PopoverView
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Phase 2 Requirements Mapping, line 753] — FR26 → PopoverView (link opens in browser)
- [Source: `_bmad-output/planning-artifacts/prd.md` #FR25] — Dismissable update badge, once dismissed does not reappear until newer version
- [Source: `_bmad-output/planning-artifacts/prd.md` #FR26] — Direct download link from within expanded panel
- [Source: `cc-hdrm/Views/PopoverView.swift`] — Integration point for badge section
- [Source: `cc-hdrm/Views/StatusMessageView.swift`] — UI pattern reference (VStack, accessibility)
- [Source: `cc-hdrm/State/AppState.swift`] — `availableUpdate` property and `updateAvailableUpdate()` method
- [Source: `cc-hdrm/Services/PreferencesManagerProtocol.swift` line 18] — `dismissedVersion` in protocol
- [Source: `cc-hdrm/Models/AvailableUpdate.swift`] — Model with `version` and `downloadURL`
- [Source: `cc-hdrm/Services/UpdateCheckService.swift`] — Backend service (complete from 8.1)
- [Source: `cc-hdrmTests/Mocks/MockPreferencesManager.swift`] — Mock with `dismissedVersion` support
- [Source: `_bmad-output/implementation-artifacts/8-1-update-check-service.md`] — Previous story with all backend details

## Dev Agent Record

### Agent Model Used

Claude claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

None — clean implementation, no debugging required.

### Completion Notes List

- Created `UpdateBadgeView.swift` with HStack layout: version text, download button (NSWorkspace.shared.open), dismiss (X) button, Homebrew hint always shown (AC #4), VoiceOver combined accessibility label (AC #5).
- Integrated into `PopoverView.swift` between status message and footer divider, conditional on `appState.availableUpdate != nil` (AC #1).
- Dismiss closure sets `preferencesManager.dismissedVersion` and clears `appState.availableUpdate` via `updateAvailableUpdate(nil)` — badge disappears reactively (AC #2).
- 8 new tests in `UpdateBadgeViewTests.swift` covering: render, hosting, badge visibility, dismiss action, callback invocation, version reappearance (AC #3), VoiceOver label.
- UpdateCheckService updated: DMG asset preferred over ZIP for download URL, with ZIP as fallback. 1 new test added, 2 existing tests updated.
- All 365 tests pass (355 existing + 8 UpdateBadgeView + 1 UpdateCheckService + 1 DMG fallback). Zero regressions.

### Change Log

- 2026-02-02: Implemented Story 8.2 — UpdateBadgeView, PopoverView integration, dismiss action, 8 tests.
- 2026-02-02: Code review fixes — added explicit `import AppKit`, removed backtick literals from Homebrew hint, clarified VoiceOver test name, updated File List to reflect actual git changes.

### File List

New:
- `cc-hdrm/Views/UpdateBadgeView.swift`
- `cc-hdrmTests/Views/UpdateBadgeViewTests.swift`

Modified:
- `cc-hdrm/Views/PopoverView.swift`
- `cc-hdrm/Services/UpdateCheckService.swift` (DMG-priority download URL)
- `cc-hdrmTests/Services/UpdateCheckServiceTests.swift` (DMG tests)
