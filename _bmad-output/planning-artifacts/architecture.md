---
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8, 9]
status: 'complete'
completedAt: '2026-02-03'
lastStep: 9
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/product-brief-cc-usage-2026-01-30.md
  - _bmad-output/planning-artifacts/ux-design-specification.md
  - _bmad-output/planning-artifacts/ux-design-specification-phase3.md
workflowType: 'architecture'
project_name: 'cc-hdrm'
user_name: 'Boss'
date: '2026-02-03'
editHistory:
  - date: '2026-02-03'
    changes: 'Added Phase 3 architectural decisions: SQLite persistence, slope calculation, headroom analysis, analytics window'
---

# Architecture Decision Document

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

## Project Context Analysis

### Requirements Overview

**Functional Requirements:**
24 FRs across 6 domains. The architectural spine is a poll-parse-render pipeline: retrieve OAuth credentials from Keychain (FR1-2), fetch usage data from Claude API with fallback strategies (FR3-5), render headroom state to menu bar and popover (FR6-13), poll automatically in the background (FR14-16), fire threshold notifications (FR17-19), handle disconnected/error states gracefully (FR20-22), and manage app lifecycle without configuration (FR23-24).

**Non-Functional Requirements:**
13 NFRs constrain performance (< 50MB memory, < 1% CPU, < 200ms popover, < 2s UI update, < 10s poll cycle), security (Keychain-only credential access, no disk persistence, HTTPS-only, no third-party data transmission), and integration resilience (graceful degradation on missing/expired/malformed credentials, defensive API parsing, auto-recovery within one poll cycle).

**Scale & Complexity:**

- Primary domain: Native macOS menu bar app (Swift/SwiftUI)
- Complexity level: Low
- Estimated architectural components: 6-8 (Keychain service, API client, polling engine, state manager, menu bar renderer, popover view, notification manager, and potentially a Cloudflare fallback chain)

### Technical Constraints & Dependencies

- **Platform:** macOS 13+ (Ventura), Apple Silicon + Intel universal binary
- **Framework:** Swift 5.9+, SwiftUI, AppKit interop for NSStatusItem
- **App type:** Menu bar-only (LSUIElement = true), no dock icon, no main window
- **Authentication:** Read-only macOS Keychain access via Security framework — depends on Claude Code having stored OAuth credentials
- **API dependency:** Claude usage API at claude.ai — undocumented/unofficial, subject to Cloudflare protection and format changes
- **Kill gate:** If all Cloudflare fallback strategies fail to reach the API from a standalone macOS process, project is killed
- **Distribution:** Open source, build from source (Xcode). No code signing for MVP.
- **No persistent storage:** All state in-memory. No database, no UserDefaults for usage data, no cache files.

### Cross-Cutting Concerns Identified

- **HeadroomState enum** — shared across menu bar renderer, popover gauges, notification logic, and accessibility announcements. Must be the single source of truth for all UI decisions.
- **Error handling / graceful degradation** — every component must handle disconnected, token-expired, and no-credentials states consistently using the same grey "—" visual language.
- **Accessibility** — VoiceOver labels, color independence (number + color + font weight), keyboard navigation, reduced motion support. Applies to all custom UI components.
- **Data freshness** — staleness tracking affects menu bar display, popover timestamp, and StatusMessageView visibility. Must be centrally managed.
- **Dual-window logic** — both 5h and 7d headroom tracked independently with independent threshold state machines. The "tighter constraint" promotion logic affects menu bar display.

## Starter Template Evaluation

### Primary Technology Domain

Native macOS desktop application (Swift/SwiftUI) — determined by PRD requirements for menu bar presence, Keychain access, and native macOS notification integration.

### Starter Options Considered

1. **Xcode macOS App template (Apple)** — Standard Xcode project generation. Provides SwiftUI app lifecycle, Info.plist, entitlements file, asset catalog. Universally maintained by Apple, always current with latest Xcode/Swift versions.
2. **Community menu bar templates** — Several GitHub repos exist (2 stars max). Not actively maintained, minimal adoption, no meaningful advantage over configuring the standard template.
3. **Bare Swift Package Manager** — Pure SPM without Xcode project. Not suitable for a GUI app requiring asset catalogs, Keychain entitlements, and Info.plist configuration.

### Selected Starter: Xcode macOS App Template

**Rationale for Selection:**
- Zero external dependencies — the template ships with Xcode
- Always current with latest Swift/SwiftUI/macOS SDK
- Menu bar configuration is minimal code (~30 lines), not worth a specialized template
- Entitlements, asset catalog, and Info.plist are needed and included
- Every macOS developer knows this starting point — maximum familiarity for contributors

**Initialization Command:**

```bash
# Create via Xcode: File → New → Project → macOS → App
# Configuration:
#   Product Name: cc-hdrm
#   Interface: SwiftUI
#   Language: Swift
#   Testing System: Swift Testing (or XCTest)
#   Target: macOS 13.0+
```

**Architectural Decisions Provided by Starter:**

- **Language & Runtime:** Swift 5.9+, SwiftUI app lifecycle (`@main App`)
- **UI Framework:** SwiftUI with AppKit interop for `NSStatusItem`
- **Build Tooling:** Xcode build system, universal binary (arm64 + x86_64)
- **Testing Framework:** Swift Testing or XCTest (built into Xcode)
- **Code Organization:** Standard Xcode project structure with sources, assets, tests
- **Development Experience:** Xcode previews, debugger, Instruments profiling

**Manual Configuration Required After Template:**
- Set `LSUIElement = true` in Info.plist (hides dock icon)
- Add Keychain Access entitlement
- Configure `NSStatusItem` in app delegate or SwiftUI lifecycle
- Remove default `ContentView` / window scene (menu bar-only)

**Note:** Project initialization using Xcode should be the first implementation story.

## Core Architectural Decisions

### Decision Priority Analysis

**Critical Decisions (Block Implementation):**
1. App architecture pattern → MVVM with service layer
2. Concurrency model → Hybrid (async/await for services, `@Observable` for UI)
3. Keychain access → Thin internal wrapper around Security framework
4. API client → Standard `URLSession` to `api.anthropic.com` (no Cloudflare concern)
5. Token refresh → Try refresh ourselves, fall back to "run Claude Code" message
6. State management → Single `@Observable` AppState, macOS 14+ minimum

**Important Decisions (Shape Architecture):**
7. Response parsing → Codable with defensive defaults (all fields optional/defaulted)
8. Polling engine → Simple `Task.sleep` loop
9. Notifications → `UserNotifications` framework
10. Testing → Swift Testing, protocol-based service interfaces for mocking

**Phase 2 Decisions (Now Resolved):**
11. Settings persistence → `UserDefaults` via `PreferencesManager`
12. Settings UI → `SettingsView` embedded in gear menu as a submenu/sheet
13. Launch at login → `SMAppService` (ServiceManagement framework, macOS 13+)
14. Update check → `UpdateCheckService` polling GitHub Releases API
15. Release packaging → Scripted ZIP build + GitHub Release via `gh` CLI

16. CI/CD → GitHub Actions: keyword-driven release from PR merge to `master`

**Deferred Decisions (Post-MVP, Post-Phase 2):**
- Sonnet-specific / extra usage display

### App Architecture

**Pattern:** MVVM with Service Layer

```
┌─────────────────────────────────────────────┐
│                   Views                      │
│  MenuBarTextRenderer  │  PopoverView         │
│  HeadroomRingGauge    │  StatusMessageView   │
│  CountdownLabel       │  GearMenu            │
└──────────────┬──────────────────────────────┘
               │ observes
┌──────────────▼──────────────────────────────┐
│              AppState (@Observable)           │
│  fiveHour: WindowState                       │
│  sevenDay: WindowState                       │
│  connectionStatus: ConnectionStatus          │
│  lastUpdated: Date?                          │
│  subscriptionTier: String?                   │
└──────────────▲──────────────────────────────┘
               │ writes
┌──────────────┴──────────────────────────────┐
│             Services (protocols)              │
│  KeychainService  │  APIClient               │
│  PollingEngine    │  NotificationService     │
│  TokenRefreshService                         │
└─────────────────────────────────────────────┘
```

**Concurrency model:** Services use async/await internally. `AppState` is `@Observable` (Observation framework, macOS 14+). Views observe `AppState` directly — no Combine, no `@Published`.

### Platform Target

**Minimum:** macOS 14.0 (Sonoma) — required for `@Observable` macro.
**Note:** Updates PRD from macOS 13+. Sonoma adoption is high enough (released Oct 2023) that this is a reasonable trade-off for cleaner code.

### API Integration

**Usage endpoint:** `GET https://api.anthropic.com/api/oauth/usage`

**Required headers:**
- `Authorization: Bearer <oauth_access_token>`
- `anthropic-beta: oauth-2025-04-20`
- `User-Agent: claude-code/<version>`

**Response parsing:** `Codable` structs with optional/defaulted fields. Unknown keys silently ignored. Missing windows degrade gracefully (hide that gauge in popover).

**Token refresh endpoint:** `POST https://platform.claude.com/v1/oauth/token`

**Refresh strategy:** On 401 response or pre-emptive check of `expiresAt` → attempt refresh using `refreshToken` → on success, update Keychain → on failure, show "Token expired — run Claude Code to refresh" and poll Keychain for new credentials.

### Keychain Integration

**Service name:** `Claude Code-credentials`

**Format:** JSON with `claudeAiOauth` object containing:
- `accessToken`, `refreshToken`, `expiresAt` (Unix ms)
- `subscriptionType`, `rateLimitTier`, `scopes`

**Access:** Read-only via `SecItemCopyMatching`. Thin `KeychainService` protocol wrapping Security framework. Write access only for token refresh (updating the stored credential).

### Polling Engine

**Implementation:** `Task.sleep` loop in an async context.
**Default interval:** 30 seconds.
**Lifecycle:** Started on app launch, runs indefinitely. Cancellable via structured concurrency.

### Notification Strategy

**Framework:** `UserNotifications`
**Thresholds (MVP):** 20% headroom (warning), 5% headroom (critical) — per UX spec
**Behavior:** Fire once per threshold crossing, re-arm on recovery above threshold. Both 5h and 7d windows tracked independently.

### Testing Strategy

**Framework:** Swift Testing (modern, ships with Xcode)
**Approach:** Protocol-based service interfaces (`KeychainServiceProtocol`, `APIClientProtocol`, etc.) enable dependency injection and mocking. State logic testable without UI. Integration tests against real Keychain/API deferred to manual validation.

### Infrastructure

**MVP:** No CI/CD, no automated deployment. Build from source via Xcode.
**Logging:** `os.Logger` for structured logging. Zero overhead when not observed.
**Dependencies:** Zero external dependencies for MVP.

### Decision Impact Analysis

**Implementation Sequence:**
1. Xcode project setup (LSUIElement, entitlements, macOS 14 target)
2. `KeychainService` — read credentials, validate format
3. `APIClient` — fetch usage data, parse response
4. `AppState` — central observable state
5. `PollingEngine` — async loop wiring KeychainService → APIClient → AppState
6. `MenuBarTextRenderer` — NSStatusItem with headroom display
7. `PopoverView` — HeadroomRingGauge, CountdownLabel, StatusMessageView
8. `NotificationService` — threshold state machines, UserNotifications
9. `TokenRefreshService` — refresh flow with Keychain write-back
10. Error states and graceful degradation across all components

**Cross-Component Dependencies:**
- `AppState` is the hub — every service writes to it, every view reads from it
- `HeadroomState` enum must be defined first — used by AppState, all views, and NotificationService
- `KeychainService` feeds both `APIClient` (token) and `AppState` (subscription tier)
- `TokenRefreshService` depends on `KeychainService` (read refresh token, write new access token) and `APIClient` (detect 401)

## Implementation Patterns & Consistency Rules

### Critical Conflict Points Identified

8 areas where AI agents could make different choices, addressed below.

### Naming Patterns

**Swift Naming Conventions (Apple API Design Guidelines):**
- Types: `UpperCamelCase` — `HeadroomState`, `KeychainService`, `AppState`
- Functions/methods: `lowerCamelCase` — `fetchUsage()`, `refreshToken()`
- Properties/variables: `lowerCamelCase` — `fiveHourUtilization`, `resetTime`
- Protocols: `UpperCamelCase` with capability suffix — `KeychainServiceProtocol`, `APIClientProtocol`
- Enum cases: `lowerCamelCase` — `.normal`, `.warning`, `.critical`, `.exhausted`, `.disconnected`
- Constants: `lowerCamelCase` — `let defaultPollInterval: TimeInterval = 30`
- Boolean properties: read as assertions — `isExpired`, `isDisconnected`, `hasCredentials`

**File Naming:**
- One primary type per file, file name matches type — `HeadroomState.swift`, `KeychainService.swift`
- Protocol + implementation can share a file if small, or split as `KeychainServiceProtocol.swift` + `KeychainService.swift`
- Extensions: `TypeName+Category.swift` — `Color+Headroom.swift`, `Date+Formatting.swift`

### Structure Patterns

**Project Organization: By layer, not by feature.**

Rationale: The app has one feature (usage monitoring). Organizing by layer (services, models, views) provides clearer separation for AI agents than feature folders would.

```
cc-hdrm/
├── App/
│   └── cc_hdrmApp.swift          # @main entry, NSStatusItem setup
├── Models/
│   ├── HeadroomState.swift       # Shared enum
│   ├── UsageResponse.swift       # Codable API response
│   ├── KeychainCredentials.swift # Codable Keychain JSON
│   └── WindowState.swift         # Per-window state model
├── Services/
│   ├── KeychainServiceProtocol.swift
│   ├── KeychainService.swift
│   ├── APIClientProtocol.swift
│   ├── APIClient.swift
│   ├── PollingEngine.swift
│   ├── NotificationService.swift
│   └── TokenRefreshService.swift
├── State/
│   └── AppState.swift            # @Observable, single source of truth
├── Views/
│   ├── MenuBarTextRenderer.swift
│   ├── PopoverView.swift
│   ├── HeadroomRingGauge.swift
│   ├── CountdownLabel.swift
│   ├── StatusMessageView.swift
│   └── GearMenu.swift
├── Extensions/
│   ├── Color+Headroom.swift
│   └── Date+Formatting.swift
├── Resources/
│   └── Assets.xcassets           # Headroom colors defined here
└── Tests/
    ├── Services/
    │   ├── KeychainServiceTests.swift
    │   ├── APIClientTests.swift
    │   └── PollingEngineTests.swift
    ├── Models/
    │   └── HeadroomStateTests.swift
    └── State/
        └── AppStateTests.swift
```

**Test location:** Mirror the source structure under `Tests/`. One test file per source file.

### Format Patterns

**API Response Mapping:**
- API returns `snake_case` JSON (`five_hour`, `resets_at`) — use `Codable` with `CodingKeys` to map to Swift `lowerCamelCase` properties
- All response fields are optional in the Swift model — missing fields result in `nil`, not crashes
- Example:

```swift
struct UsageResponse: Codable {
    let fiveHour: WindowUsage?
    let sevenDay: WindowUsage?
    let sevenDaySonnet: WindowUsage?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }
}

struct WindowUsage: Codable {
    let utilization: Double?
    let resetsAt: String?     // ISO 8601, parsed to Date separately

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}
```

**Date/Time Formatting Rules (from UX spec):**
- Relative countdown under 1h: `"resets in 47m"`
- Relative countdown 1-24h: `"resets in 2h 13m"`
- Relative countdown over 24h: `"resets in 2d 1h"`
- Absolute time same day: `"at 4:52 PM"`
- Absolute time different day: `"at Mon 7:05 PM"`
- Countdown updates every 60 seconds (not every second)
- All formatting in a `Date+Formatting.swift` extension — single source of truth

### State Management Patterns

**AppState Mutation Rules:**
- Only services write to `AppState` — views are read-only observers
- All `AppState` property updates happen on `@MainActor` — ensures UI consistency
- Services call `AppState` methods (not set properties directly) to enforce invariants

```swift
// Good: method encapsulates update logic
appState.updateUsage(fiveHour: response.fiveHour, sevenDay: response.sevenDay)

// Bad: direct property mutation from service
appState.fiveHour = response.fiveHour
```

- `HeadroomState` is computed from `utilization` value, never stored separately — avoids state/display mismatch

```swift
// HeadroomState is always derived, never manually set
var headroomState: HeadroomState {
    HeadroomState(from: utilization)
}
```

### Error Handling Patterns

**Swift error handling approach:**
- Services use `async throws` — callers handle errors explicitly
- No `Result` type wrapping — use native Swift error handling
- Define a single `AppError` enum for all app-level errors:

```swift
enum AppError: Error {
    case keychainNotFound
    case keychainAccessDenied
    case keychainInvalidFormat
    case tokenExpired
    case tokenRefreshFailed(underlying: Error)
    case networkUnreachable
    case apiError(statusCode: Int, body: String?)
    case parseError(underlying: Error)
}
```

- `PollingEngine` catches all errors and maps them to `AppState.connectionStatus` — errors never propagate to views
- Views read `connectionStatus` from `AppState`, never handle errors directly

### Logging Patterns

**Framework:** `os.Logger` (unified logging)

**Subsystem:** `com.cc-hdrm.app`

**Categories and levels:**

| Category       | Logger                             | Usage                                      |
| -------------- | ---------------------------------- | ------------------------------------------ |
| `keychain`     | `.info` found, `.error` fail       | Credential discovery, read errors          |
| `api`          | `.info` success, `.error` fail     | Request/response, status codes             |
| `polling`      | `.debug` cycle, `.info` state change | Poll loop lifecycle                      |
| `notification` | `.info` fired                      | Threshold crossings, notification delivery |
| `token`        | `.info` refresh, `.error` fail     | Token refresh attempts                     |

**Rules:**
- NEVER log credentials, tokens, or sensitive data — even at `.debug` level
- Log state transitions (e.g., "headroom state changed from .normal to .warning")
- Log error context (e.g., "API returned 401, attempting token refresh")
- Keep log messages factual and grep-friendly

### Accessibility Patterns

**All custom views MUST include:**
- `.accessibilityLabel()` — human-readable description
- `.accessibilityValue()` — dynamic values (percentages, countdowns)
- Color is never the only signal — number + color + font weight always triple-encode state

**VoiceOver announcement format:**
- Gauges: `"5-hour headroom: 83 percent, resets in 2 hours 13 minutes, at 4:52 PM"`
- Menu bar: `"Claude headroom: 83 percent, normal"`
- Status: `"Disconnected, unable to reach Claude API"`

### Enforcement Guidelines

**All AI Agents MUST:**
1. Follow Apple's Swift API Design Guidelines for all naming
2. Place files in the correct layer folder (Models/Services/State/Views/Extensions)
3. Never mutate `AppState` from views — views are read-only
4. Use `async throws` for service methods, not `Result` or optional returns
5. Map all errors to `AppError` enum cases
6. Include accessibility labels on every custom view
7. Never log sensitive data (tokens, credentials)
8. Use `CodingKeys` for snake_case → camelCase API mapping
9. Derive `HeadroomState` from utilization values, never store it manually
10. Put all date/time formatting in `Date+Formatting.swift`

**Anti-Patterns to Avoid:**
- Creating a "Utils" or "Helpers" dump folder — use specific extensions instead
- Using `DispatchQueue` or GCD — use structured concurrency (async/await)
- Storing computed state (like `HeadroomState`) as a separate property that can go stale
- Using print() for logging — use `os.Logger`
- Catching errors silently with empty catch blocks — always update `connectionStatus`

## Project Structure & Boundaries

### Complete Project Directory Structure

```
cc-hdrm/
├── cc-hdrm.xcodeproj/
├── cc-hdrm/
│   ├── Info.plist                    # LSUIElement=true, bundle ID
│   ├── cc_hdrm.entitlements         # Keychain access entitlement
│   ├── App/
│   │   └── cc_hdrmApp.swift          # @main, NSStatusItem setup, service wiring
│   ├── Models/
│   │   ├── HeadroomState.swift       # .normal/.caution/.warning/.critical/.exhausted/.disconnected
│   │   ├── WindowState.swift         # Per-window: utilization, resetsAt, computed headroomState
│   │   ├── UsageResponse.swift       # Codable API response (five_hour, seven_day, etc.)
│   │   ├── KeychainCredentials.swift # Codable Keychain JSON (claudeAiOauth object)
│   │   └── AppError.swift            # Unified error enum
│   ├── Services/
│   │   ├── KeychainServiceProtocol.swift
│   │   ├── KeychainService.swift     # SecItemCopyMatching wrapper, JSON parsing
│   │   ├── APIClientProtocol.swift
│   │   ├── APIClient.swift           # URLSession GET to api.anthropic.com
│   │   ├── TokenRefreshService.swift # POST to platform.claude.com, Keychain write-back
│   │   ├── PollingEngine.swift       # Task.sleep loop, orchestrates fetch cycle
│   │   └── NotificationService.swift # UserNotifications, threshold state machines
│   ├── State/
│   │   └── AppState.swift            # @Observable, @MainActor, single source of truth
│   ├── Views/
│   │   ├── MenuBarTextRenderer.swift # NSStatusItem view, sparkle icon + percentage/countdown
│   │   ├── PopoverView.swift         # Main popover container, stacked vertical layout
│   │   ├── HeadroomRingGauge.swift   # Circular ring gauge (96px primary, 56px secondary)
│   │   ├── CountdownLabel.swift      # Relative + absolute reset time display
│   │   ├── StatusMessageView.swift   # Error/status messages (disconnected, expired, etc.)
│   │   └── GearMenu.swift            # SF Symbol gear → Quit (Phase 2: settings)
│   ├── Extensions/
│   │   ├── Color+Headroom.swift      # .headroomNormal/.caution/.warning/.critical/.exhausted/.disconnected
│   │   └── Date+Formatting.swift     # Relative countdown + absolute time formatting
│   └── Resources/
│       └── Assets.xcassets/
│           └── HeadroomColors/       # Light/dark variants for all headroom color tokens
├── cc-hdrmTests/
│   ├── Models/
│   │   ├── HeadroomStateTests.swift  # State derivation from utilization values
│   │   ├── UsageResponseTests.swift  # Defensive parsing, missing fields, unknown keys
│   │   └── KeychainCredentialsTests.swift
│   ├── Services/
│   │   ├── KeychainServiceTests.swift  # Mock SecItemCopyMatching results
│   │   ├── APIClientTests.swift        # Mock URLSession responses
│   │   ├── PollingEngineTests.swift    # Lifecycle, error mapping to AppState
│   │   ├── NotificationServiceTests.swift # Threshold state machine transitions
│   │   └── TokenRefreshServiceTests.swift
│   ├── State/
│   │   └── AppStateTests.swift       # Update methods, invariants, derived state
│   └── Extensions/
│       └── DateFormattingTests.swift  # All countdown/absolute formatting rules
├── .gitignore
├── README.md
└── LICENSE
```

### Architectural Boundaries

**External API Boundary:**
- Single outbound integration: `api.anthropic.com` (usage data)
- Single outbound integration: `platform.claude.com` (token refresh)
- `APIClient` is the only component that makes HTTP requests — all other components go through it
- All external communication is HTTPS, no exceptions

**Keychain Boundary:**
- `KeychainService` is the only component that touches the Security framework
- Read access: credential discovery (all poll cycles)
- Write access: token refresh only (via `TokenRefreshService` calling back through `KeychainService`)
- No other component imports `Security` framework directly

**State Boundary:**
- `AppState` is `@MainActor` — all property access is main-thread safe
- Services write via `AppState` methods — no direct property mutation
- Views read via `@Observable` — no callbacks, no delegates, no notifications
- One-way data flow: Services → AppState → Views

**Notification Boundary:**
- `NotificationService` is the only component that imports `UserNotifications`
- Threshold state machines live inside `NotificationService`, not `AppState`
- `NotificationService` reads from `AppState` to detect threshold crossings

### Requirements to Structure Mapping

**FR Category: Usage Data Retrieval (FR1-FR5)**
- FR1 (Keychain read) → `Services/KeychainService.swift`
- FR2 (Subscription type) → `Models/KeychainCredentials.swift` + `State/AppState.swift`
- FR3 (Fetch usage) → `Services/APIClient.swift`
- FR4 (Fallback strategies) → `Services/APIClient.swift` (simplified: standard error handling, no Cloudflare)
- FR5 (Token expired) → `Services/TokenRefreshService.swift` + `Views/StatusMessageView.swift`

**FR Category: Usage Display (FR6-FR13)**
- FR6 (Menu bar percentage) → `Views/MenuBarTextRenderer.swift`
- FR7 (Color-coded indicator) → `Views/MenuBarTextRenderer.swift` + `Extensions/Color+Headroom.swift`
- FR8 (Click-to-expand) → `Views/PopoverView.swift`
- FR9-FR10 (Usage bars) → `Views/HeadroomRingGauge.swift`
- FR11-FR12 (Reset countdowns) → `Views/CountdownLabel.swift` + `Extensions/Date+Formatting.swift`
- FR13 (Subscription tier) → `Views/PopoverView.swift`

**FR Category: Background Monitoring (FR14-FR16)**
- FR14 (Polling) → `Services/PollingEngine.swift`
- FR15 (Auto-update display) → `State/AppState.swift` (observable) + all Views
- FR16 (Background running) → `App/cc_hdrmApp.swift` (LSUIElement configuration)

**FR Category: Notifications (FR17-FR19)**
- FR17-FR18 (Threshold notifications) → `Services/NotificationService.swift`
- FR19 (Countdown in notifications) → `Services/NotificationService.swift` + `Extensions/Date+Formatting.swift`

**FR Category: Connection State (FR20-FR22)**
- FR20 (Disconnected indicator) → `Views/MenuBarTextRenderer.swift`
- FR21 (Failure explanation) → `Views/StatusMessageView.swift`
- FR22 (Auto-resume) → `Services/PollingEngine.swift`

**FR Category: App Lifecycle (FR23-FR24)**
- FR23 (Zero-config launch) → `App/cc_hdrmApp.swift` + `Services/KeychainService.swift`
- FR24 (Quit from menu bar) → `Views/GearMenu.swift`

### Data Flow

```
┌───────────┐     ┌──────────────┐     ┌───────────────────┐
│  Keychain │────▶│ KeychainSvc  │────▶│                   │
│ (macOS)   │     │ (read creds) │     │                   │
└───────────┘     └──────────────┘     │                   │
                                       │  PollingEngine    │
┌───────────┐     ┌──────────────┐     │  (orchestrator)   │
│ anthropic │◀────│  APIClient   │◀────│                   │
│ .com API  │────▶│ (fetch usage)│────▶│                   │
└───────────┘     └──────────────┘     └────────┬──────────┘
                                                │ writes
┌───────────┐     ┌──────────────┐     ┌────────▼──────────┐
│ platform. │◀────│ TokenRefresh │◀────│                   │
│claude.com │────▶│  Service     │────▶│    AppState       │
└───────────┘     └──────────────┘     │  (@Observable)    │
                                       │  (@MainActor)     │
                                       └────────┬──────────┘
                                                │ observes
                  ┌──────────────┐     ┌────────▼──────────┐
                  │ Notification │◀────│     Views          │
                  │  Service     │     │ MenuBar/Popover   │
                  └──────┬───────┘     └───────────────────┘
                         │
                  ┌──────▼───────┐
                  │   macOS      │
                  │ Notification │
                  │   Center     │
                  └──────────────┘
```

**Poll cycle (every 30s):**
1. `PollingEngine` → `KeychainService.readCredentials()` → get token + metadata
2. `PollingEngine` → check `expiresAt` — if near expiry, `TokenRefreshService.refresh()`
3. `PollingEngine` → `APIClient.fetchUsage(token:)` → get `UsageResponse`
4. `PollingEngine` → `AppState.updateUsage(response:)` — updates all window states, connection status, timestamp
5. Views automatically re-render via `@Observable`
6. `NotificationService` observes `AppState`, fires notifications on threshold crossings

**Error flow:**
- Any service failure → `PollingEngine` catches → `AppState.setError(error:)` → `connectionStatus` updates → Views show grey "—" + `StatusMessageView`

## Phase 2 Architectural Additions

### Settings Persistence (UserDefaults)

**Framework:** `UserDefaults.standard` via a `PreferencesManager` service.

**Stored preferences:**
- `notificationWarningThreshold: Double` — headroom percentage for warning notification (default: 20.0)
- `notificationCriticalThreshold: Double` — headroom percentage for critical notification (default: 5.0)
- `pollInterval: TimeInterval` — seconds between poll cycles (default: 30, min: 10, max: 300)
- `launchAtLogin: Bool` — whether app registers as login item (default: false)
- `dismissedVersion: String?` — last version whose update badge was dismissed (for FR25)

**Pattern:**
- `PreferencesManager` conforms to `PreferencesManagerProtocol` for testability
- Uses `@AppStorage` property wrappers in `SettingsView` for two-way binding
- Services read preferences via `PreferencesManager` — not directly from `UserDefaults`
- `PollingEngine` reads `pollInterval` from `PreferencesManager` at each cycle start (hot-reconfigurable)
- `NotificationService` reads thresholds from `PreferencesManager` at each evaluation (hot-reconfigurable)

**Validation rules:**
- Warning threshold must be > critical threshold
- Poll interval clamped to 10-300 second range
- Invalid values silently replaced with defaults

### Settings UI

**Location:** `SettingsView.swift` in `Views/`

**Access:** Gear menu in popover footer expands to show "Settings..." menu item (alongside existing "Quit cc-hdrm"). Selecting "Settings..." presents a sheet/popover with preference controls.

**Layout:**
- Notification thresholds: two sliders or steppers (warning %, critical %)
- Poll interval: stepper or picker (10s, 15s, 30s, 60s, 120s, 300s)
- Launch at login: toggle switch
- Reset to defaults button

**Binding:** `@AppStorage` property wrappers bind directly to `UserDefaults` keys. Changes take effect immediately (no save button).

### Launch at Login

**Framework:** `ServiceManagement` — `SMAppService.mainApp`

**Implementation:**
- `SMAppService.mainApp.register()` / `unregister()` called from `PreferencesManager` when `launchAtLogin` changes
- Status checked on app launch via `SMAppService.mainApp.status`
- No helper app needed — `SMAppService` (macOS 13+) handles it natively

### Update Check Service

**Service:** `UpdateCheckService` conforming to `UpdateCheckServiceProtocol`

**Behavior:**
- On app launch, fetches latest release from `https://api.github.com/repos/{owner}/{repo}/releases/latest`
- Compares `tag_name` (semver) against `Bundle.main.infoDictionary["CFBundleShortVersionString"]`
- If newer version exists AND `tag_name != PreferencesManager.dismissedVersion`:
  - Sets `AppState.availableUpdate` with version string and download URL (`html_url` or asset browser_download_url)
- If user dismisses the badge, stores the version in `PreferencesManager.dismissedVersion`
- Badge does not reappear until a *newer* version (different `tag_name`) is released

**Request headers:**
- `Accept: application/vnd.github.v3+json`
- `User-Agent: cc-hdrm/<version>`
- No authentication required (public repo, GitHub API rate limit: 60 req/hr unauthenticated — more than sufficient for once-per-launch check)

**Error handling:** Update check failures are silent — no error state, no UI impact. App functions normally without update awareness.

### Release Packaging & CI/CD

**Versioning:** Semantic versioning. Version string in `Info.plist` (`CFBundleShortVersionString`) and git tag (`v1.0.0`, `v1.1.0`). Default branch: `master`.

**Release trigger:** Keyword in PR title: `[patch]`, `[minor]`, or `[major]`. No keyword = no release. Only PRs from maintainers trigger the release workflow (enforced via GitHub Actions permission check on actor).

**Pre-merge workflow (on PR with keyword detected):**
1. Detect `[patch]`/`[minor]`/`[major]` in PR title
2. Read current version from `Info.plist`
3. Bump version according to semver keyword
4. Commit updated `Info.plist` back to the PR branch
5. PR is ready for maintainer review and merge

**Post-merge workflow (on merge to `master`):**
1. Detect that merged PR had a version bump commit
2. Tag `master` with `v{new_version}`
3. Auto-generate changelog entry from merged PR titles since last tag
4. If the release PR body contains a section between `<!-- release-notes-start -->` and `<!-- release-notes-end -->` markers, prepend that as a preamble above the auto-generated list
5. Update `CHANGELOG.md` with the new entry and commit to `master`
6. Build universal binary via `xcodebuild` (arm64 + x86_64)
7. Create ZIP: `cc-hdrm-{version}-macos.zip`
8. Create GitHub Release with changelog entry as body and ZIP as asset
9. Update Homebrew formula in `{owner}/homebrew-tap` with new version and SHA256

**CHANGELOG.md:** Auto-generated and maintained in repo root. Each release gets a `## [version] - date` section with optional maintainer preamble followed by auto-generated PR list.

**GitHub Actions files:**
- `.github/workflows/release-prepare.yml` — runs on PR, detects keyword, bumps version, commits to PR branch
- `.github/workflows/release-publish.yml` — runs on merge to `master`, tags, builds, packages, publishes

### Homebrew Tap

**Repository:** Separate repo `{owner}/homebrew-tap` containing `Casks/cc-hdrm.rb`

**Cask** (not Formula — cc-hdrm is a macOS .app bundle, not a CLI binary):
- Downloads ZIP asset from GitHub Release
- Installs cc-hdrm.app to `/Applications`
- `brew upgrade --cask cc-hdrm` pulls latest release

**Maintenance:** Cask file auto-updated by `release-publish.yml` workflow step on each release.

### Phase 2 Project Structure Additions

```
cc-hdrm/
├── cc-hdrm/
│   ├── Services/
│   │   ├── PreferencesManagerProtocol.swift   # NEW
│   │   ├── PreferencesManager.swift           # NEW - UserDefaults wrapper
│   │   ├── UpdateCheckServiceProtocol.swift   # NEW
│   │   └── UpdateCheckService.swift           # NEW - GitHub Releases API
│   ├── Views/
│   │   └── SettingsView.swift                 # NEW - preferences UI
├── cc-hdrmTests/
│   ├── Services/
│   │   ├── PreferencesManagerTests.swift      # NEW
│   │   └── UpdateCheckServiceTests.swift      # NEW
├── .github/
│   └── workflows/
│       ├── release-prepare.yml                # NEW - PR keyword detection + version bump
│       └── release-publish.yml                # NEW - tag, build, package, publish
├── CHANGELOG.md                               # NEW
```

### Phase 2 Requirements to Structure Mapping

- FR25 (Update badge) → `Services/UpdateCheckService.swift` + `Views/PopoverView.swift` (badge in popover)
- FR26 (Download link) → `Views/PopoverView.swift` (link opens in browser)
- FR27 (Configurable thresholds) → `Services/PreferencesManager.swift` + `Views/SettingsView.swift` + `Services/NotificationService.swift`
- FR28 (Configurable poll interval) → `Services/PreferencesManager.swift` + `Views/SettingsView.swift` + `Services/PollingEngine.swift`
- FR29 (Launch at login) → `Services/PreferencesManager.swift` + `Views/SettingsView.swift`
- FR30 (Settings view) → `Views/SettingsView.swift` + `Views/GearMenu.swift`

### Phase 2 Data Flow Addition

```
┌───────────────┐     ┌───────────────────┐
│ GitHub Releases│◀────│ UpdateCheckService │
│     API        │────▶│ (launch check)    │──────┐
└───────────────┘     └───────────────────┘      │ writes
                                                  ▼
┌───────────────┐     ┌───────────────────┐  ┌──────────┐
│  UserDefaults  │◀───▶│ PreferencesManager│  │ AppState │
└───────────────┘     └────────┬──────────┘  └──────────┘
                               │ reads                ▲
                    ┌──────────┼──────────┐           │
                    ▼          ▼          ▼           │
              PollingEngine  Notif.Svc  SettingsView──┘
              (poll interval) (thresholds)
```

## Phase 3 Architectural Additions

Phase 3 transforms cc-hdrm from a real-time fuel gauge into a historical analytics platform. Three interconnected features require significant architectural expansion:

1. **Historical Usage Tracking** — SQLite persistence, rollup engine, analytics window
2. **Underutilised Headroom Analysis** — Credit math, waste categorization, three-band visualization
3. **Usage Slope Indicator** — Rate-of-change calculation, discrete 4-level display

### Data Layer Architecture

**First persistent storage.** Phase 1-2 were entirely in-memory. Phase 3 introduces SQLite for historical data.

#### Database Location

**Path:** `~/Library/Application Support/cc-hdrm/usage.db`

**Rationale:** Standard macOS convention for application data. Survives app updates, keeps data separate from app bundle.

#### SQLite Schema

**Table: `usage_polls`** — Raw poll data, < 24h retention at full resolution

| Column              | Type    | Notes                      |
| ------------------- | ------- | -------------------------- |
| id                  | INTEGER | PRIMARY KEY                |
| timestamp           | INTEGER | Unix ms                    |
| five_hour_util      | REAL    | Percentage 0-100           |
| five_hour_resets_at | INTEGER | Unix ms, nullable          |
| seven_day_util      | REAL    | Percentage 0-100           |
| seven_day_resets_at | INTEGER | Unix ms, nullable          |

**Table: `usage_rollups`** — Aggregated data at decreasing resolution

| Column          | Type    | Notes                              |
| --------------- | ------- | ---------------------------------- |
| id              | INTEGER | PRIMARY KEY                        |
| period_start    | INTEGER | Unix ms                            |
| period_end      | INTEGER | Unix ms                            |
| resolution      | TEXT    | '5min' \| 'hourly' \| 'daily'      |
| five_hour_avg   | REAL    | Average utilization for period     |
| five_hour_peak  | REAL    | Maximum utilization for period     |
| five_hour_min   | REAL    | Minimum utilization for period     |
| seven_day_avg   | REAL    |                                    |
| seven_day_peak  | REAL    |                                    |
| seven_day_min   | REAL    |                                    |
| reset_count     | INTEGER | Number of 5h resets in period      |
| waste_credits   | REAL    | Calculated true waste              |

**Table: `reset_events`** — Captures each 5h window reset for headroom analysis

| Column              | Type    | Notes                         |
| ------------------- | ------- | ----------------------------- |
| id                  | INTEGER | PRIMARY KEY                   |
| timestamp           | INTEGER | Unix ms                       |
| five_hour_peak      | REAL    | Peak utilization before reset |
| seven_day_util      | REAL    | 7d utilization at reset time  |
| tier                | TEXT    | Rate limit tier string        |
| used_credits        | REAL    | Actual consumption            |
| constrained_credits | REAL    | 7d-blocked capacity           |
| waste_credits       | REAL    | True waste                    |

**Indexes:**
- `usage_polls(timestamp)` — for range queries
- `usage_rollups(resolution, period_start)` — for rollup lookups
- `reset_events(timestamp)` — for headroom analysis

#### Rollup Strategy

**Trigger:** On-demand when analytics window opens.

**Rationale:** CPU consumed only when user explicitly requests analytics. Zero rollup overhead if user never opens analytics window. User clicked something — they expect processing.

**Implementation:**
1. Track `last_rollup_timestamp` in database metadata
2. On analytics open, call `HistoricalDataService.ensureRollupsUpToDate()`
3. Process only records newer than last rollup
4. Typical case: < 100ms for a day's worth of polls

**Tiered Resolution:**

| Data Age   | Resolution        | Rollup Action                    |
| ---------- | ----------------- | -------------------------------- |
| < 24 hours | Per-poll (~60s)   | Keep raw, no rollup              |
| 1-7 days   | 5-minute averages | Aggregate raw → 5min rollups     |
| 7-30 days  | Hourly averages   | Aggregate 5min → hourly rollups  |
| 30+ days   | Daily summary     | Aggregate hourly → daily rollups |

**Retention:** Configurable via settings, default 1 year. Enforced by `pruneOldData()` called during rollup.

### New Services

#### HistoricalDataService

**Responsibility:** SQLite persistence, rollup engine, data queries.

```swift
protocol HistoricalDataServiceProtocol {
    func persistPoll(_ response: UsageResponse) async throws
    func ensureRollupsUpToDate() async throws
    func getRecentPolls(hours: Int) async throws -> [UsagePoll]
    func getRolledUpData(range: TimeRange) async throws -> [UsageRollup]
    func getResetEvents(range: TimeRange) async throws -> [ResetEvent]
    func pruneOldData(retentionDays: Int) async throws
    func getDatabaseSize() async throws -> Int64
}
```

**Reset Detection:** Primary: compare `resets_at` timestamps between consecutive polls. Fallback: detect large utilization drops (e.g., 80% → 2%) to catch edge cases where `resets_at` is missing.

#### SlopeCalculationService

**Responsibility:** Rate-of-change calculation, discrete level mapping.

```swift
protocol SlopeCalculationServiceProtocol {
    func addPoll(_ poll: UsagePoll)
    func calculateSlope(for window: UsageWindow) -> SlopeLevel
    func bootstrapFromHistory(_ polls: [UsagePoll])
}

enum SlopeLevel: String {
    case cooling  // ↘ utilization decreasing
    case flat     // → no meaningful change
    case rising   // ↗ moderate consumption
    case steep    // ⬆ heavy consumption
}
```

**Data Source:** In-memory ring buffer holding last 10-15 minutes of polls (~15-30 data points). On app launch, bootstrap buffer from SQLite via `HistoricalDataService.getRecentPolls(hours: 1)`.

**Calculation:**
1. Sample buffer for specified window (5h or 7d)
2. Compute average rate of change (% per minute)
3. Map to discrete level:

| Rate (% / min) | Level   |
| -------------- | ------- |
| < -0.5         | Cooling |
| -0.5 to 0.3    | Flat    |
| 0.3 to 1.5     | Rising  |
| > 1.5          | Steep   |

**Trigger:** Recalculate on every poll cycle. Slope calculation is trivial (average of ~15-30 numbers from in-memory buffer). Ensures menu bar slope arrow is always current.

#### HeadroomAnalysisService

**Responsibility:** Waste categorization math, credit limit lookup.

```swift
protocol HeadroomAnalysisServiceProtocol {
    func analyzeResetEvent(peak5h: Double, util7d: Double, tier: RateLimitTier) -> HeadroomBreakdown
    func aggregateBreakdown(_ events: [ResetEvent]) -> PeriodSummary
    func getCreditLimits(for tier: RateLimitTier) -> (fiveHour: Int, sevenDay: Int)?
}

struct HeadroomBreakdown {
    let usedPercent: Double
    let constrainedPercent: Double  // 7d-blocked, NOT waste
    let wastePercent: Double        // true waste
    let usedCredits: Int
    let constrainedCredits: Int
    let wasteCredits: Int
}
```

**Waste Calculation (at each 5h reset):**

```
5h_remaining_credits = (100% - 5h_peak%) × 5h_limit
7d_remaining_credits = (100% - 7d_util%) × 7d_limit
effective_headroom_credits = min(5h_remaining_credits, 7d_remaining_credits)

If 5h_remaining ≤ 7d_remaining:
    true_waste = 5h_remaining  (all unused 5h was genuinely available)
    7d_constrained = 0
Else:
    true_waste = 7d_remaining  (7d was the binding constraint)
    7d_constrained = 5h_remaining - 7d_remaining
```

#### DatabaseManager

**Responsibility:** SQLite connection, schema creation, migrations.

```swift
protocol DatabaseManagerProtocol {
    func getConnection() throws -> Connection
    func ensureSchema() throws
    func runMigrations() throws
}
```

**Location:** `~/Library/Application Support/cc-hdrm/usage.db`

**Schema creation:** On first launch, create tables and indexes. Track schema version for future migrations.

### Credit Limit Handling

**Source:** Hardcoded lookup table + user override in settings for power users / new tiers.

```swift
enum RateLimitTier: String, CaseIterable {
    case pro = "default_claude_pro"
    case max5x = "default_claude_max_5x"
    case max20x = "default_claude_max_20x"
    
    var fiveHourCredits: Int {
        switch self {
        case .pro: return 550_000
        case .max5x: return 3_300_000
        case .max20x: return 11_000_000
        }
    }
    
    var sevenDayCredits: Int {
        switch self {
        case .pro: return 5_000_000
        case .max5x: return 41_666_700
        case .max20x: return 83_333_300
        }
    }
}
```

**User Override:** Settings view includes optional fields for custom 5h/7d credit limits. If set, override the hardcoded values. Stored in `PreferencesManager`.

**Unknown Tier Handling:** If `rateLimitTier` from Keychain doesn't match known values AND no user override:
- Log warning for debugging
- Headroom breakdown section shows: "Headroom breakdown unavailable — unknown subscription tier."
- Percentage-based displays continue working normally

### Analytics Window Architecture

**First real window.** Phase 1-2 UI was entirely menu bar + popover. Phase 3 adds a detachable analytics panel.

#### Window Type

**NSPanel (utility window)** with `.nonactivatingPanel` style.

| Property       | Behavior                                          |
| -------------- | ------------------------------------------------- |
| Dock icon      | None — app stays LSUIElement                      |
| Cmd+Tab        | Not included                                      |
| Window level   | Floats above regular windows, below fullscreen    |
| Activation     | Non-activating — doesn't steal focus from user's app |
| Close          | Close button + Escape key                         |
| Size           | Default ~600×500px, resizable, remembers position |

#### Window Controller

```swift
class AnalyticsWindowController {
    static let shared = AnalyticsWindowController()  // Singleton
    
    private var panel: NSPanel?
    @Published var isOpen: Bool = false
    
    func toggle() {
        if isOpen { close() } else { open() }
    }
    
    func open() {
        if panel == nil { createPanel() }  // Lazy creation
        panel?.makeKeyAndOrderFront(nil)
        isOpen = true
    }
    
    func close() {
        panel?.close()
        isOpen = false
    }
}
```

**Lifecycle:**
- Singleton — only one analytics window ever exists
- Lazy creation — window instantiated on first open
- Toggle behavior — sparkline click opens OR brings to front
- State persistence — frame saved to UserDefaults
- Escape key handling — closes window

#### Window-Popover Relationship

**Independent.** Both can be visible simultaneously.

**Rationale:** Popover is "quick glance," analytics is "deep dive." User may want both: check current state in popover while historical chart is visible in analytics window.

#### Data Loading

**Load all upfront** when window opens or time range changes.

**Rationale:** At 1-year retention with daily rollups, "All" view is ~365 data points. Trivial to load entirely. No pagination complexity needed.

### Component Modifications

#### MenuBarTextRenderer (Phase 1 component)

**Modification:** Add optional slope arrow suffix (escalation-only).

**New rendering logic:**
```swift
func renderMenuBarText() -> String {
    guard connectionStatus != .disconnected else { return "✳ —" }
    guard headroomState != .exhausted else { return "✳ ↻ \(countdown)" }
    
    let base = "✳ \(percentage)%"
    
    // Phase 3: append slope only for Rising/Steep
    switch fiveHourSlope {
    case .rising: return "\(base) ↗"
    case .steep:  return "\(base) ⬆"
    case .flat, .cooling: return base
    }
}
```

**Width impact:** +2 characters when slope visible (~7 chars max vs ~5 chars Phase 1-2).

#### HeadroomRingGauge (Phase 1 component)

**Modification:** Add `SlopeIndicator` view below percentage.

**New layout:**
```
    ◯ (ring)
     78%
      ↗         ← NEW: slope indicator (always visible in popover)
resets in 1h 12m
  at 5:17 PM
```

**Props addition:** `slopeLevel: SlopeLevel`

#### PopoverView (Phase 1 component)

**Modification:** Add sparkline section between 7d gauge and footer.

**New structure:**
```
┌──────────────────┐
│  5h gauge + slope│
│  7d gauge + slope│
├──────────────────┤
│  24h Sparkline   │  ← NEW: clickable, launches analytics
├──────────────────┤
│  Footer          │
└──────────────────┘
```

**Sparkline data:** Cached in `AppState.sparklineData`, refreshed on each poll cycle. Popover opens instantly — no data fetch on open.

### New Components

#### SlopeIndicator

**Purpose:** Display discrete slope arrow with appropriate styling.

```swift
struct SlopeIndicator: View {
    let level: SlopeLevel
    let size: CGFloat
    
    var body: some View {
        Text(level.arrow)
            .font(.system(size: size))
            .foregroundColor(level.color)
            .accessibilityLabel(level.accessibilityLabel)
    }
}

extension SlopeLevel {
    var arrow: String {
        switch self {
        case .cooling: return "↘"
        case .flat: return "→"
        case .rising: return "↗"
        case .steep: return "⬆"
        }
    }
    
    var color: Color {
        switch self {
        case .cooling, .flat: return .secondary
        case .rising, .steep: return .headroomColor  // matches current headroom state
        }
    }
}
```

#### Sparkline

**Purpose:** Compact 24h usage visualization, acts as button to launch analytics.

```swift
struct Sparkline: View {
    let data: [UsagePoll]
    let isAnalyticsOpen: Bool
    let onTap: () -> Void
    
    // Renders step-area path honoring sawtooth shape
    // Gaps as path breaks (no interpolation)
    // Subtle hover/press state
    // Indicator dot when analytics window is open
}
```

**Accessibility:** "24-hour usage chart. Double-tap to open analytics."

#### AnalyticsView

**Purpose:** Main content view for analytics window.

**Layout:**
```
┌─────────────────────────────────────────────────────────┐
│  Usage Analytics                                    ✕   │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  [24h]  [7d]  [30d]  [All]          5h ● │ 7d ○        │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │              UsageChart                          │   │
│  │   (step-area for 24h, bars for 7d+)             │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
├─────────────────────────────────────────────────────────┤
│  Headroom Breakdown (selected period)                   │
│  ┌─────────────────────────────────────────────────┐    │
│  │▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░                       │    │
│  └─────────────────────────────────────────────────┘    │
│  ▓ Used: 52%   ░ 7d-constrained: 12%   □ Waste: 36%    │
│                                                         │
│  Avg peak: 64%  │  Total waste: 2.1M credits           │
└─────────────────────────────────────────────────────────┘
```

#### UsageChart

**Purpose:** Main chart supporting both step-area and bar modes.

**Props:**
- `data: [UsageDataPoint]` or `[UsageRollup]`
- `timeRange: TimeRange` — determines chart type
- `visibleSeries: Set<Series>` — 5h/7d toggles
- `showSlopeBands: Bool` — background color bands for steep periods

**Rendering by time range:**
- **24h:** Step-area chart honoring sawtooth shape, reset markers as dashed vertical lines
- **7d+:** Bar chart with peak values per period

**Gap handling:** Missing segments rendered as breaks, never interpolated. Hatched/grey region with "No data" hover label.

#### HeadroomBreakdownBar

**Purpose:** Three-band stacked horizontal bar.

```swift
struct HeadroomBreakdownBar: View {
    let used: Double
    let constrained: Double
    let waste: Double
    
    // Rendering:
    // Used: solid fill, headroom color
    // 7d-constrained: hatched pattern, muted slate blue
    // True waste: light/empty fill
}
```

**Accessibility:** "Headroom breakdown: 52% used, 12% constrained by weekly limit, 36% unused."

#### TimeRangeSelector

**Purpose:** Segmented control for time range selection.

```swift
struct TimeRangeSelector: View {
    @Binding var selected: TimeRange
    
    // Four buttons: 24h, 7d, 30d, All
}

enum TimeRange {
    case day, week, month, all
}
```

### Phase 3 State Additions

**AppState modifications:**

```swift
@Observable
class AppState {
    // Existing Phase 1-2 properties...
    
    // Phase 3 additions:
    var fiveHourSlope: SlopeLevel = .flat
    var sevenDaySlope: SlopeLevel = .flat
    var sparklineData: [UsagePoll] = []
    var isAnalyticsWindowOpen: Bool = false
}
```

**Sparkline data refresh:** `PollingEngine` updates `AppState.sparklineData` on each poll by calling `HistoricalDataService.getRecentPolls(hours: 24)`. This keeps popover open instant.

### Phase 3 Settings Additions

**PreferencesManager additions:**

```swift
// Historical data
var dataRetentionDays: Int  // default: 365

// Credit limit overrides (for unknown tiers or power users)
var customFiveHourCredits: Int?   // nil = use hardcoded
var customSevenDayCredits: Int?   // nil = use hardcoded
```

**SettingsView additions:**
- Data retention slider/picker (30 days to 5 years)
- "Advanced" section for custom credit limits
- Database size display with "Clear History" button

### Phase 3 Project Structure

```
cc-hdrm/
├── cc-hdrm/
│   ├── Models/
│   │   ├── SlopeLevel.swift                    # NEW
│   │   ├── RateLimitTier.swift                 # NEW
│   │   ├── UsagePoll.swift                     # NEW
│   │   ├── UsageRollup.swift                   # NEW
│   │   ├── ResetEvent.swift                    # NEW
│   │   ├── HeadroomBreakdown.swift             # NEW
│   │   └── TimeRange.swift                     # NEW
│   │
│   ├── Services/
│   │   ├── HistoricalDataServiceProtocol.swift # NEW
│   │   ├── HistoricalDataService.swift         # NEW
│   │   ├── SlopeCalculationServiceProtocol.swift # NEW
│   │   ├── SlopeCalculationService.swift       # NEW
│   │   ├── HeadroomAnalysisServiceProtocol.swift # NEW
│   │   ├── HeadroomAnalysisService.swift       # NEW
│   │   └── DatabaseManager.swift               # NEW
│   │
│   ├── State/
│   │   └── AppState.swift                      # MODIFIED
│   │
│   ├── Views/
│   │   ├── MenuBarTextRenderer.swift           # MODIFIED
│   │   ├── HeadroomRingGauge.swift             # MODIFIED
│   │   ├── PopoverView.swift                   # MODIFIED
│   │   ├── SettingsView.swift                  # MODIFIED
│   │   ├── SlopeIndicator.swift                # NEW
│   │   ├── Sparkline.swift                     # NEW
│   │   ├── AnalyticsWindow.swift               # NEW
│   │   ├── AnalyticsView.swift                 # NEW
│   │   ├── UsageChart.swift                    # NEW
│   │   ├── HeadroomBreakdownBar.swift          # NEW
│   │   └── TimeRangeSelector.swift             # NEW
│   │
│   ├── Extensions/
│   │   └── Date+Formatting.swift               # MODIFIED: chart axis formatters
│   │
│   └── Resources/
│       └── Assets.xcassets/
│           └── AnalyticsColors/                # NEW
│
├── cc-hdrmTests/
│   ├── Models/
│   │   ├── SlopeLevelTests.swift               # NEW
│   │   ├── RateLimitTierTests.swift            # NEW
│   │   └── HeadroomBreakdownTests.swift        # NEW
│   ├── Services/
│   │   ├── HistoricalDataServiceTests.swift    # NEW
│   │   ├── SlopeCalculationServiceTests.swift  # NEW
│   │   ├── HeadroomAnalysisServiceTests.swift  # NEW
│   │   └── DatabaseManagerTests.swift          # NEW
│   └── Views/
│       ├── SparklineTests.swift                # NEW
│       └── UsageChartTests.swift               # NEW
```

### Phase 3 Data Flow

```
                              ┌─────────────────────┐
                              │   PollingEngine     │
                              │   (existing)        │
                              └──────────┬──────────┘
                                         │ UsageResponse
                    ┌────────────────────┼────────────────────┐
                    │                    │                    │
                    ▼                    ▼                    ▼
        ┌───────────────────┐ ┌──────────────────┐ ┌──────────────────┐
        │ HistoricalData    │ │ SlopeCalculation │ │    AppState      │
        │ Service           │ │ Service          │ │   (existing)     │
        │                   │ │                  │ │                  │
        │ • persistPoll()   │ │ • addToBuffer()  │ │ • updateUsage()  │
        │ • detectReset()   │ │ • calculate()    │ │ • fiveHourSlope  │
        │                   │ │     ↓            │ │ • sevenDaySlope  │
        └────────┬──────────┘ │  SlopeLevel      │ │ • sparklineData  │
                 │            └────────┬─────────┘ └────────┬─────────┘
                 │                     │                    │
                 ▼                     └────────┬───────────┘
        ┌───────────────────┐                   │ observes
        │     SQLite        │                   ▼
        │ ~/Library/App...  │         ┌──────────────────────┐
        │                   │         │       Views          │
        │ • usage_polls     │         │                      │
        │ • usage_rollups   │         │ MenuBarTextRenderer  │◄── slope arrow
        │ • reset_events    │         │ HeadroomRingGauge    │◄── slope indicator
        └────────┬──────────┘         │ PopoverView          │◄── sparkline
                 │                    │ Sparkline ──────────────► click
                 │                    └──────────────────────┘      │
                 │                                                  │
                 │ on-demand query                                  │
                 │◄─────────────────────────────────────────────────┘
                 │
                 ▼
        ┌───────────────────┐         ┌──────────────────────┐
        │ HistoricalData    │────────►│   AnalyticsWindow    │
        │ Service           │ rolled  │   (NSPanel)          │
        │                   │  data   │                      │
        │ • ensureRollups() │         │ • UsageChart         │
        │ • getRolledUp()   │         │ • HeadroomBreakdown  │
        │ • getResetEvents()│         │ • TimeRangeSelector  │
        └───────────────────┘         └──────────────────────┘
                 ▲                               │
                 │                               ▼
        ┌────────┴──────────┐         ┌──────────────────────┐
        │ HeadroomAnalysis  │◄────────│   Reset Events +     │
        │ Service           │         │   Tier from Keychain │
        │                   │         └──────────────────────┘
        │ • analyzeReset()  │
        │ • aggregate()     │
        └───────────────────┘
```

### Phase 3 Requirements to Structure Mapping

| FR   | Requirement                                | Primary File(s)                                                |
| ---- | ------------------------------------------ | -------------------------------------------------------------- |
| FR33 | Persist poll snapshots to SQLite           | `HistoricalDataService.swift`, `DatabaseManager.swift`           |
| FR34 | Roll up data at decreasing resolution      | `HistoricalDataService.swift`                                    |
| FR35 | 24h sparkline in popover                   | `Sparkline.swift`, `PopoverView.swift`                           |
| FR36 | Full analytics window with zoomable charts | `AnalyticsWindow.swift`, `AnalyticsView.swift`, `UsageChart.swift` |
| FR37 | Render gaps as visually distinct           | `Sparkline.swift`, `UsageChart.swift`                            |
| FR38 | Configurable retention period              | `PreferencesManager.swift`, `SettingsView.swift`                 |
| FR39 | Calculate effective headroom               | `HeadroomAnalysisService.swift`                                  |
| FR40 | Detect resets, classify waste categories   | `HistoricalDataService.swift`, `HeadroomAnalysisService.swift`   |
| FR41 | Three-band breakdown in analytics          | `HeadroomBreakdownBar.swift`, `AnalyticsView.swift`              |
| FR42 | Compute usage rate of change               | `SlopeCalculationService.swift`                                  |
| FR43 | Map rate to 4-level slope indicator        | `SlopeCalculationService.swift`, `SlopeLevel.swift`              |
| FR44 | Slope indicator in menu bar                | `MenuBarTextRenderer.swift`                                      |
| FR45 | Per-window slope in popover                | `HeadroomRingGauge.swift`, `SlopeIndicator.swift`                |

### Phase 3 Implementation Patterns

#### Gap Rendering Pattern

Gaps (periods when cc-hdrm wasn't running) are rendered consistently across all visualizations:

| Component            | Gap Rendering                              |
| -------------------- | ------------------------------------------ |
| Sparkline            | Break in the line                          |
| UsageChart (24h)     | Missing segment, no path drawn             |
| UsageChart (7d+ bars)| Missing bars, "No data" on hover           |
| HeadroomBreakdown    | Gaps excluded from calculation             |

**Rule:** Never interpolate. The visualization admits what it doesn't know.

#### Slope Communication Pattern

Slope is communicated consistently across all locations:

| Location        | Flat/Cooling | Rising | Steep |
| --------------- | ------------ | ------ | ----- |
| Menu bar        | Hidden       | ↗      | ⬆     |
| Popover 5h      | →/↘          | ↗      | ⬆     |
| Popover 7d      | →/↘          | ↗      | ⬆     |
| Analytics chart | No tint      | Tint   | Tint  |

#### Accessibility Pattern

All Phase 3 components maintain color independence:

| Element            | Color Signal      | Non-Color Signal         |
| ------------------ | ----------------- | ------------------------ |
| Slope arrow        | Headroom color    | Arrow direction shape    |
| Slope bands        | Warm tint         | Presence/absence         |
| Used band          | Headroom color    | Solid fill pattern       |
| 7d-constrained     | Slate blue        | Hatched pattern          |
| True waste         | Light/transparent | Empty/outline pattern    |
| Gap regions        | Grey              | Hatched pattern + label  |

## Architecture Validation Results

### Coherence Validation ✅

**Decision Compatibility:**
All technology choices are compatible. Swift 5.9+ / SwiftUI / macOS 14 / @Observable / async-await / URLSession / Codable / SQLite — standard Apple stack with no version conflicts or dependency issues. Phase 3 adds SQLite (bundled with macOS) as the only new framework dependency.

**Pattern Consistency:**
Naming follows Apple API Design Guidelines throughout. Layer-based folder structure matches MVVM service layer pattern. Error handling (async throws → AppError → connectionStatus) is consistent end to end. Logging categories map 1:1 to service components. Phase 3 services follow the same protocol-based pattern established in Phase 1.

**Structure Alignment:**
Every architectural component has a defined file location. Boundaries are enforced by which component imports which framework (only KeychainService imports Security, only APIClient uses URLSession for external calls, only NotificationService imports UserNotifications, only DatabaseManager imports SQLite). Test structure mirrors source structure.

### Requirements Coverage Validation ✅

**Functional Requirements:** All 45 FRs have traceable architectural support with specific file mappings:
- FR1-FR24 (Phase 1): See "Requirements to Structure Mapping" section
- FR25-FR32 (Phase 2): See "Phase 2 Requirements to Structure Mapping" section
- FR33-FR45 (Phase 3): See "Phase 3 Requirements to Structure Mapping" section

**Non-Functional Requirements:** All 13 NFRs are addressed architecturally.

**NFR Coverage:** All 13 NFRs aligned between PRD and architecture. NFR7 specifies fresh Keychain read each poll cycle (no token caching). NFR8 correctly references `api.anthropic.com` and `platform.claude.com`. Phase 3 persistent storage (SQLite) does not violate NFR6 — credentials are never written to the database, only usage metrics.

### Implementation Readiness Validation ✅

**Decision Completeness:** 
- Phase 1: 10 core architectural decisions documented
- Phase 2: 6 additional decisions (settings, CI/CD, update checks)
- Phase 3: 8 additional decisions (SQLite, rollups, slope, analytics window)
All with rationale. Technology versions specified. All critical choices made.

**Structure Completeness:** Every source file named and placed across all phases. Directory structure is complete and specific, not generic. Phase 3 adds 7 new model files, 7 new service files, 7 new view files.

**Pattern Completeness:** Naming, structure, state management, error handling, logging, and accessibility patterns all defined with concrete examples and anti-patterns. Phase 3 adds gap rendering pattern and slope communication pattern.

### Gap Analysis Results

**Critical Gaps:** None.

**Resolved Gaps (fixed in PRD 2026-01-31):**
1. ~~PRD endpoint inconsistency~~ — NFR8 now references `api.anthropic.com` and `platform.claude.com`
2. ~~PRD platform target~~ — now says macOS 14+ (Sonoma), matching architecture's `@Observable` requirement
3. ~~PRD Keychain access~~ — now says read/write, acknowledging token refresh write-back
4. ~~FR4 stale Cloudflare fallback~~ — replaced with standard HTTP error handling language
5. ~~NFR7 token caching ambiguity~~ — now specifies fresh Keychain read each poll cycle
6. ~~Stale Cloudflare references~~ — removed or marked as resolved throughout PRD

**Remaining Minor Inconsistency:**
- PRD threshold framing uses usage percentages (80%/95%), UX spec and architecture use headroom percentages (20%/5%). Values are mathematically equivalent — not a conflict, just different framing. Architecture follows UX spec convention.

**Open Items (non-blocking):**
- Token refresh OAuth request format (grant_type, client_id, etc.) needs discovery during implementation

### Architecture Completeness Checklist

**✅ Requirements Analysis**
- [x] Project context thoroughly analyzed
- [x] Scale and complexity assessed
- [x] Technical constraints identified
- [x] Cross-cutting concerns mapped

**✅ Architectural Decisions**
- [x] Critical decisions documented (Phase 1: 10, Phase 2: 6, Phase 3: 8)
- [x] Technology stack fully specified (Swift/SwiftUI/macOS 14/SQLite)
- [x] Integration patterns defined (API, Keychain, Notifications, SQLite)
- [x] Performance considerations addressed (NFRs mapped)

**✅ Implementation Patterns**
- [x] Naming conventions established (Apple API Design Guidelines)
- [x] Structure patterns defined (layer-based organization)
- [x] State management patterns specified (@Observable, mutation rules)
- [x] Error handling, logging, accessibility patterns documented
- [x] Gap rendering pattern defined (Phase 3)
- [x] Slope communication pattern defined (Phase 3)

**✅ Project Structure**
- [x] Complete directory structure defined (every file named)
- [x] Component boundaries established (4 boundary types + SQLite boundary)
- [x] Integration points mapped (data flow diagrams for all phases)
- [x] All 45 FRs mapped to specific files (FR1-24 Phase 1, FR25-32 Phase 2, FR33-45 Phase 3)

### Architecture Readiness Assessment

**Overall Status:** READY FOR IMPLEMENTATION (All Phases)

**Confidence Level:** High

**Key Strengths:**
- API spike eliminated the highest-risk unknown — concrete endpoint, auth headers, and response format are documented
- Minimal external dependencies — SQLite bundled with macOS, nothing else
- Single @Observable AppState provides clear, testable state management
- Every FR (45 total) has a traceable path to a specific file
- Patterns are prescriptive enough to prevent agent divergence without being over-engineered
- Phase 3 data layer is well-bounded — SQLite only touched by DatabaseManager and HistoricalDataService
- On-demand rollup strategy ensures CPU is consumed only when user expects it

**Resolved Design Questions (Phase 3):**
- Database location: `~/Library/Application Support/cc-hdrm/`
- Rollup trigger: On-demand when analytics opens
- Slope data source: In-memory ring buffer, bootstrapped from SQLite
- Reset detection: Primary (resets_at shift) + fallback (utilization drop)
- Analytics window: NSPanel, non-activating, independent from popover
- Credit limits: Hardcoded + user override in settings

**Areas for Future Enhancement:**
- Token refresh request format needs discovery during implementation
- Slope threshold tuning (% per minute) needs validation with real usage data
- Historical API research — if Anthropic exposes endpoint, could backfill gaps

### Implementation Handoff

**AI Agent Guidelines:**
- Follow all architectural decisions exactly as documented
- Use implementation patterns consistently across all components
- Respect project structure and boundaries
- Refer to this document for all architectural questions
- Phase 3 components should follow the same protocol-based testing pattern as Phase 1

**Phase 1 Implementation Priority:**
1. Create Xcode project with macOS 14 target, LSUIElement=true, Keychain entitlement
2. Implement HeadroomState enum and AppError enum (shared types first)
3. Implement KeychainService — validate that credentials can be read
4. Implement APIClient — validate that usage data can be fetched
5. Wire up AppState + PollingEngine — prove the core pipeline works
6. Build views on top of working data pipeline

**Phase 2 Implementation Priority:**
1. PreferencesManager + SettingsView
2. UpdateCheckService
3. Launch at login (SMAppService)
4. CI/CD workflows

**Phase 3 Implementation Priority:**
1. DatabaseManager + SQLite schema — foundation for all Phase 3 features
2. HistoricalDataService — persist polls, implement rollup logic
3. SlopeLevel enum + SlopeCalculationService — enables menu bar/popover modifications
4. Modify MenuBarTextRenderer + HeadroomRingGauge — add slope indicators
5. Sparkline component + PopoverView modification
6. AnalyticsWindow + AnalyticsView — full analytics experience
7. UsageChart — step-area and bar chart modes
8. HeadroomAnalysisService + HeadroomBreakdownBar — waste categorization
9. RateLimitTier with credit limits + settings override
10. Gap rendering across all chart components
