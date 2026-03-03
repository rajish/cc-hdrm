# Story 18.3: First-Run Onboarding Popup

Status: done

## Story

As a first-time cc-hdrm user,
I want to see a welcoming popup explaining what the app does and that sign-in is needed,
so that I understand why I'm being asked to authenticate and feel confident proceeding.

## Acceptance Criteria

1. **Given** the app launches for the first time (no stored credentials, `hasCompletedOnboarding == false` in UserDefaults), **when** `AppDelegate.applicationDidFinishLaunching` completes initialization, **then** an onboarding popup appears automatically as a centered NSPanel within 1 second of launch, and the menu bar icon is visible behind it showing "✳ —".

2. **Given** the onboarding popup is visible, **when** it renders, **then** it displays:
   - App icon (AppIcon from asset catalog, 64pt)
   - App name "cc-hdrm" as headline
   - Description: "Monitor your Claude subscription usage from the menu bar — always visible, zero tokens spent."
   - Explanation: "Sign in with your Anthropic account to get started. This is a one-time setup."
   - Primary button: "Sign In" (accent-colored, prominent)
   - Secondary button: "Later" (plain/text style)

3. **Given** the user clicks "Sign In", **when** the button is pressed, **then** the popup dismisses, `hasCompletedOnboarding` is set to `true`, and `AppDelegate.performSignIn()` is triggered (starting the existing OAuth browser flow).

4. **Given** the user clicks "Later", **when** the button is pressed, **then** the popup dismisses and `hasCompletedOnboarding` is set to `true`. The popover shows the existing unauthenticated state with its "Sign In" button (existing behavior from Story 18.1).

5. **Given** the user clicks outside the popup or presses Escape, **when** the event is detected, **then** the popup does NOT dismiss (modal behavior — user must explicitly choose Sign In or Later).

6. **Given** a previously authenticated user who signed out, **when** the app shows the unauthenticated state, **then** the onboarding popup does NOT appear (`hasCompletedOnboarding` is already `true`).

7. **Given** the user has completed onboarding (either via Sign In or Later), **when** the app launches on any subsequent run, **then** the onboarding popup never appears again.

8. **Given** VoiceOver is active, **when** the onboarding popup appears, **then** all text is accessible and the "Sign In" button receives initial keyboard focus.

## Tasks / Subtasks

- [x] **Task 1: PreferencesManager — Add onboarding flag** (AC: 1, 6, 7)
  - [x] Add key `static let hasCompletedOnboarding = "com.cc-hdrm.hasCompletedOnboarding"` to `PreferencesManager.Keys`
  - [x] Add `var hasCompletedOnboarding: Bool { get set }` to `cc-hdrm/Services/PreferencesManagerProtocol.swift`
  - [x] Add `hasCompletedOnboarding: Bool` computed property to `PreferencesManager` (getter from UserDefaults defaulting to `false`, setter with logger.info)
  - [x] Add `hasCompletedOnboarding` to `resetToDefaults()` method (set to `false`) — intentional: "Reset Preferences" gives a fresh-start experience including re-showing onboarding
  - [x] Update `cc-hdrmTests/Mocks/MockPreferencesManager.swift` to add `hasCompletedOnboarding` property (simple stored `Bool = false`)
  - [x] This is a UserDefaults flag, NOT credential presence — distinguishes true first-run from signed-out state

- [x] **Task 2: OnboardingWindowController** (AC: 1, 2, 5, 8)
  - [x] Create `cc-hdrm/Views/OnboardingWindowController.swift`
  - [x] Create an NSPanel (similar pattern to `AnalyticsWindow`):
    - `styleMask: [.titled, .closable]` — but override close button to do nothing (modal)
    - `.isMovableByWindowBackground = true`
    - `.level = .modalPanel` (above floating windows)
    - `.center()` on screen
    - No dock icon (app remains LSUIElement)
    - No Cmd+Tab entry
  - [x] Size: 420×400px, non-resizable
  - [x] Host a SwiftUI `OnboardingView` via `NSHostingView`
  - [x] Expose `show()` and `dismiss()` methods
  - [x] `show()` calls `NSApp.activate(ignoringOtherApps: true)` to bring the panel to front even on first launch
  - [x] Override `windowShouldClose(_:)` to return `false` (prevent close button / Escape dismiss — or subclass NSPanel and override `close()` as no-op)
  - [x] Run `xcodegen generate` after creating new Swift files

- [x] **Task 3: OnboardingView (SwiftUI)** (AC: 2, 3, 4, 8)
  - [x] Create `cc-hdrm/Views/OnboardingView.swift`
  - [x] Layout (VStack, centered):
    - App icon: `Image(nsImage: NSApplication.shared.applicationIconImage)` at 64×64 (resolves to AppIcon from asset catalog)
    - "cc-hdrm" in `.title2` weight `.bold`
    - Description text in `.body`, `.secondary` color, multiline centered
    - Explanation text in `.callout`, `.secondary` color, multiline centered
    - 16pt spacer
    - "Sign In" button: `.buttonStyle(.borderedProminent)`, `.controlSize(.large)`
    - "Later" button: `.buttonStyle(.plain)`, `.foregroundStyle(.secondary)`, `.font(.callout)`
  - [x] Padding: 32pt horizontal, 24pt vertical
  - [x] Callbacks: `onSignIn: () -> Void` and `onLater: () -> Void`
  - [x] VoiceOver: set `.accessibilityElement(children: .contain)` on container, `.accessibilityFocused` on Sign In button via `@AccessibilityFocusState`

- [x] **Task 4: AppDelegate Integration** (AC: 1, 3, 4, 6, 7)
  - [x] Add `private var onboardingWindowController: OnboardingWindowController?` property
  - [x] In `applicationDidFinishLaunching`, AFTER all services are initialized and status bar is set up:
    ```swift
    if !preferencesManager.hasCompletedOnboarding {
        if oauthKeychainService?.hasCredentials() == true {
            preferencesManager.hasCompletedOnboarding = true
        } else {
            showOnboarding()
        }
    }
    ```
  - [x] `showOnboarding()` method:
    - Create `OnboardingWindowController` with `OnboardingView`
    - Wire `onSignIn` callback: set `preferencesManager.hasCompletedOnboarding = true`, dismiss onboarding, set `onboardingWindowController = nil`, then call `Task { await self.performSignIn() }` (performSignIn is `private async` — same async bridge pattern as popover's onSignIn at line ~183)
    - Wire `onLater` callback: set `preferencesManager.hasCompletedOnboarding = true`, dismiss onboarding, set `onboardingWindowController = nil`
    - Call `onboardingWindowController.show()`
  - [x] Insertion point: after `startObservingAppState()` (line ~216), before the `Task` block that starts polling (line ~228)
  - [x] Do NOT show onboarding if `hasCompletedOnboarding == true` (covers signed-out users)
  - [x] Do NOT show onboarding if `oauthState != .unauthenticated` (covers users who already have credentials)

- [x] **Task 5: Tests** (AC: 1-8)
  - [x] Unit tests for PreferencesManager:
    - `hasCompletedOnboarding` defaults to `false`
    - Setting `true` persists and reads back
    - `resetToDefaults()` resets to `false`
  - [x] Unit tests for OnboardingView:
    - Verify Sign In callback fires
    - Verify Later callback fires
  - [x] Test the onboarding-trigger condition logic in isolation (extract the `shouldShowOnboarding` check as a testable function or test via `MockPreferencesManager` + `AppState`):
    - First launch (no credentials, flag false) → should show
    - Subsequent launch (flag true) → should NOT show
    - Signed-out user (flag true, no credentials) → should NOT show
    - Already authenticated (flag false but credentials exist) → should NOT show
  - [x] Update `cc-hdrmTests/Mocks/MockPreferencesManager.swift` with `hasCompletedOnboarding` support
  - [x] Test files: `cc-hdrmTests/Views/OnboardingViewTests.swift`, update `cc-hdrmTests/Services/PreferencesManagerTests.swift`

## Dev Notes

### Why This Story Exists

Story 18.1 replaced silent Keychain credential discovery with an active browser OAuth flow. The app now requires a one-time sign-in, but a brand new user launching cc-hdrm sees only a "Sign In" button in the popover with no context about what the app does or why authentication is needed. This creates a confusing first impression.

### Sprint Change Proposal Reference

Added per Sprint Change Proposal 2026-03-02 (Change 3). The user explicitly requested the popup appear automatically on first launch (not on popover open).

### NSPanel Pattern — Reuse from AnalyticsWindow

`cc-hdrm/Views/AnalyticsWindow.swift` is the existing reference for creating standalone NSPanel windows. Key differences for onboarding:

| Aspect | AnalyticsWindow | OnboardingWindow |
|--------|----------------|-----------------|
| Level | `.floating` | `.modalPanel` (higher — must be above everything) |
| Resizable | Yes (600×500 default) | No (fixed ~360×280) |
| Close behavior | Standard close/Escape | Blocked (must use buttons) |
| Persistence | Remembers position/size | Always centered, no persistence |
| Singleton | Yes (toggle pattern) | Yes (show once, dismiss forever) |

### Detection Logic — UserDefaults NOT Credential Presence

The `hasCompletedOnboarding` flag is deliberately stored in UserDefaults, NOT derived from credential presence. This is critical:

| Scenario | Credentials | Flag | Onboarding? |
|----------|-------------|------|-------------|
| True first launch | None | `false` | YES |
| Launched, clicked Later | None | `true` | NO |
| Signed in, relaunched | Present | `true` | NO |
| Signed out | None | `true` | NO |
| Reset preferences | None | `false` | YES (correct — user wants fresh start) |

### Existing Code to Reuse

- `cc-hdrm/Views/AnalyticsWindow.swift` — NSPanel creation pattern (adapt for modal, non-resizable)
- `cc-hdrm/Services/PreferencesManager.swift` — UserDefaults key pattern (lines 14-36 for Keys enum, lines 140-148 for computed property pattern)
- `cc-hdrm/App/AppDelegate.swift:258-300` — `performSignIn()` is the existing sign-in trigger to call from onboarding
- `cc-hdrm/Views/PopoverView.swift:34-79` — unauthenticatedView shows the current "bare" sign-in UI for reference

### Existing Code That Does NOT Change

- `PopoverView.swift` — unauthenticated view stays as-is (fallback if user clicks Later)
- `OAuthService.swift` — OAuth flow unchanged
- `AppState.swift` — no new state needed (onboarding is a one-shot UI, not app state)
- `GearMenuView.swift` — Sign Out unchanged

### AppDelegate Launch Sequence (Insertion Point)

In `cc-hdrm/App/AppDelegate.swift:applicationDidFinishLaunching` (lines 54-256), the onboarding check goes AFTER:
1. All services initialized (DatabaseManager, PreferencesManager, AppState, etc.)
2. Status bar item created (menu bar icon visible)
3. NSPopover configured
4. Event monitor installed

But BEFORE or concurrent with:
5. `startPolling()` (lines 241-256) — polling can start in background while onboarding is shown
6. `startUpdateCheck()` — update check is fine to run

The onboarding window appears on top of everything. If user clicks Sign In → OAuth browser opens → user completes auth → onboarding is already dismissed → polling picks up authenticated state.

### UI Design Details

The popup should feel native macOS, not flashy:
- Use system font (SF Pro via SwiftUI defaults)
- Respect dark mode automatically (SwiftUI handles this)
- Use `.secondary` color for description text (not custom colors)
- Use `.borderedProminent` for Sign In button (system accent color)
- Adequate spacing — don't crowd the panel

### Project Structure Notes

- New files go in `cc-hdrm/Views/` (consistent with `AnalyticsWindow.swift`)
- Test files go in `cc-hdrmTests/Views/`
- Run `xcodegen generate` after adding new Swift files
- All file paths are project-relative

### References

- [Source: cc-hdrm/Views/AnalyticsWindow.swift] NSPanel creation pattern to adapt
- [Source: cc-hdrm/Services/PreferencesManager.swift:14-36] Keys enum pattern for UserDefaults
- [Source: cc-hdrm/Services/PreferencesManager.swift:140-148] Computed property pattern (dismissedVersion)
- [Source: cc-hdrm/Services/PreferencesManager.swift:330-353] resetToDefaults() to extend
- [Source: cc-hdrm/App/AppDelegate.swift:54-256] applicationDidFinishLaunching — insertion point for onboarding check
- [Source: cc-hdrm/App/AppDelegate.swift:258-300] performSignIn() — existing OAuth trigger
- [Source: cc-hdrm/Views/PopoverView.swift:34-79] unauthenticatedView — current bare sign-in UI
- [Source: cc-hdrm/State/AppState.swift:36-51] OAuthState enum and updateOAuthState
- [Source: _bmad-output/planning-artifacts/sprint-change-proposal-2026-03-02.md] Sprint change proposal with full context
- [Source: _bmad-output/implementation-artifacts/18-1-independent-oauth-authentication.md] Story 18.1 — OAuth flow implementation details
- [Source: _bmad-output/implementation-artifacts/18-2-oauth-profile-tier-resolution.md] Story 18.2 — profile fetch pattern

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

None — clean implementation, no debug issues encountered.

### Completion Notes List

- Task 1: Added `hasCompletedOnboarding` UserDefaults flag to PreferencesManager, protocol, mock, and resetToDefaults. 3 new tests (default false, persistence, reset). All 44 PreferencesManager tests pass.
- Task 2: Created OnboardingWindowController with modal NSPanel (`.modalPanel` level, non-resizable 420x400, `windowShouldClose` returns false, `cancelOperation` overridden to block Escape). Pattern adapted from AnalyticsWindow.
- Task 3: Created OnboardingView SwiftUI layout with app icon (64pt), title, description/explanation text, Sign In (borderedProminent) and Later (plain) buttons. VoiceOver support via `@AccessibilityFocusState` on Sign In button. Closures typed `@MainActor` for Sendable safety.
- Task 4: Integrated into AppDelegate — onboarding check inserted after `startObservingAppState()`, before polling Task. `showOnboarding()` wires both callbacks to set `hasCompletedOnboarding = true` and dismiss. Sign In callback chains to `performSignIn()` via async Task.
- Task 5: 9 new tests across 2 suites (OnboardingViewTests, OnboardingTriggerLogicTests). Tests cover callback firing, all 5 onboarding-trigger scenarios (first launch, subsequent, signed-out, authenticated, authorizing), and mock support. All pass.
- Pre-existing failure: `chronicUnderpowering detected when rate-limited N+ times for 2+ cycles` in SubscriptionPatternDetectorTests — confirmed failing on master before changes.
- Code Review Fixes (AI-1): H1 — increased panel size from 360x280 to 420x400 to prevent content clipping. H2 — replaced deprecated `NSApp.activate(ignoringOtherApps:)` with `NSApp.activate()`. H3 — removed `.closable` from styleMask to eliminate non-functional close button. M1 — added 4 OnboardingWindowController unit tests (windowShouldClose, panel size, panel level, dismiss behavior). Changed `panel` to `private(set)` for test access.
- Code Review Fixes (AI-2): M1 — fixed test description "360x380" → "420x400" to match actual assertion. M2 — corrected completion notes referencing wrong panel dimensions. M3 — removed dead `state.oauthState == .unauthenticated` condition from AppDelegate (always true at launch, hasCompletedOnboarding flag alone covers all cases); simplified trigger logic tests accordingly, removed 3 tests that validated unreachable oauthState scenarios. L1 — added defensive-code comment to windowShouldClose test. L2 — added SwiftUI testing limitation comment to callback tests.

### Change Log

- 2026-03-03: Story 18.3 implemented — first-run onboarding popup with PreferencesManager flag, OnboardingWindowController, OnboardingView, AppDelegate integration, and 12 new tests.
- 2026-03-03: Code review fixes (AI-1) — panel size 360x280→420x400, deprecated API replaced, `.closable` removed, 4 controller tests added (16 total new tests).
- 2026-03-03: Code review fixes (AI-2) — fixed test description, corrected completion notes dimensions, removed dead oauthState condition from AppDelegate, simplified trigger logic tests (13 total new tests).

### File List

New files:
- cc-hdrm/Views/OnboardingWindowController.swift
- cc-hdrm/Views/OnboardingView.swift
- cc-hdrmTests/Views/OnboardingViewTests.swift

Modified files:
- cc-hdrm/Services/PreferencesManager.swift (added hasCompletedOnboarding key, property, resetToDefaults entry)
- cc-hdrm/Services/PreferencesManagerProtocol.swift (added hasCompletedOnboarding to protocol)
- cc-hdrm/App/AppDelegate.swift (added onboardingWindowController property, onboarding check in launch, showOnboarding method)
- cc-hdrmTests/Mocks/MockPreferencesManager.swift (added hasCompletedOnboarding property and reset)
- cc-hdrmTests/Services/PreferencesManagerTests.swift (added 3 onboarding flag tests)
