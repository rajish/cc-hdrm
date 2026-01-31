# Project Context: cc-hdrm

## Project Overview

**cc-hdrm** is a native macOS menu bar utility that gives Claude Pro/Max subscribers always-visible, glanceable usage headroom data. It polls the Claude usage API in the background and displays live usage bars, reset countdowns, and color-coded warnings directly in the menu bar — zero tokens spent, zero workflow interruption.

**Repository:** cc-usage (monorepo root) / cc-hdrm (Xcode project)
**Status:** Active development, MVP phase
**Distribution:** Open source, build from source (Xcode)

---

## Technology Stack

| Category          | Technology                          | Version/Notes                    |
| ----------------- | ----------------------------------- | -------------------------------- |
| Language          | Swift                               | 5.9+                             |
| UI Framework      | SwiftUI + AppKit interop            | NSStatusItem for menu bar        |
| Platform          | macOS                               | 14.0+ (Sonoma) minimum          |
| State Management  | Observation framework (`@Observable`) | Requires macOS 14               |
| Concurrency       | Swift structured concurrency        | async/await, no GCD             |
| Networking        | URLSession                          | Built-in, no third-party        |
| Security          | Security framework                  | Keychain access                  |
| Notifications     | UserNotifications framework         | Native macOS notifications       |
| Logging           | os.Logger                           | Unified logging, zero overhead   |
| Testing           | Swift Testing                       | Ships with Xcode                 |
| Build System      | Xcode                               | Universal binary (arm64+x86_64) |
| External Deps     | **None**                            | Zero external dependencies       |

---

## Architecture

**Pattern:** MVVM with Service Layer

**Data Flow:** One-way — Services -> AppState -> Views

```
Services (async throws)  -->  AppState (@Observable, @MainActor)  -->  Views (read-only)
```

**Key Components:**
- `AppState` — single `@Observable` source of truth, `@MainActor`, services write via methods only
- `PollingEngine` — `Task.sleep` loop (30s), orchestrates: Keychain read -> token check -> API fetch -> state update
- `KeychainService` — thin wrapper around Security framework, reads `Claude Code-credentials`
- `APIClient` — `URLSession` GET to `api.anthropic.com/api/oauth/usage`
- `TokenRefreshService` — POST to `platform.claude.com/v1/oauth/token`
- `NotificationService` — threshold state machines, `UserNotifications`

---

## Project Structure

**Organization:** By layer, not by feature.

```
cc-hdrm/
├── cc-hdrm.xcodeproj/
├── cc-hdrm/
│   ├── Info.plist                    # LSUIElement=true
│   ├── cc_hdrm.entitlements         # Keychain access (DO NOT MODIFY without explicit instruction)
│   ├── App/                          # @main entry, NSStatusItem setup, service wiring
│   ├── Models/                       # Data types: HeadroomState, UsageResponse, AppError, etc.
│   ├── Services/                     # Protocol + implementation pairs for all services
│   ├── State/                        # AppState (@Observable, single source of truth)
│   ├── Views/                        # All UI: MenuBar, Popover, Gauges, StatusMessage, GearMenu
│   ├── Extensions/                   # Targeted extensions: Color+Headroom, Date+Formatting
│   └── Resources/
│       └── Assets.xcassets/          # HeadroomColors with light/dark variants
├── cc-hdrmTests/                     # Mirrors source structure: Models/, Services/, State/, Extensions/
├── .gitignore
├── README.md
└── LICENSE
```

**Rule:** One primary type per file. File name matches the type name. Tests mirror source structure.

---

## Naming Conventions

Follow **Apple Swift API Design Guidelines** consistently:

| Element          | Convention        | Example                                      |
| ---------------- | ----------------- | -------------------------------------------- |
| Types            | UpperCamelCase    | `HeadroomState`, `KeychainService`           |
| Functions        | lowerCamelCase    | `fetchUsage()`, `refreshToken()`             |
| Properties       | lowerCamelCase    | `fiveHourUtilization`, `resetTime`           |
| Protocols        | +Protocol suffix  | `KeychainServiceProtocol`, `APIClientProtocol` |
| Enum cases       | lowerCamelCase    | `.normal`, `.warning`, `.critical`           |
| Constants        | lowerCamelCase    | `let defaultPollInterval: TimeInterval = 30` |
| Booleans         | Assertions        | `isExpired`, `isDisconnected`, `hasCredentials` |
| Files            | TypeName.swift    | `HeadroomState.swift`, `KeychainService.swift` |
| Extensions       | Type+Category     | `Color+Headroom.swift`, `Date+Formatting.swift` |

---

## Coding Patterns & Rules

### State Management
- Only services write to `AppState` — views are read-only observers
- All `AppState` updates happen on `@MainActor`
- Services call `AppState` methods, never set properties directly
- `HeadroomState` is always **derived** from `utilization`, never stored separately

### Error Handling
- Services use `async throws` — no `Result` type wrapping
- Single `AppError` enum for all app-level errors
- `PollingEngine` catches all errors and maps to `AppState.connectionStatus`
- Views read `connectionStatus`, never handle errors directly
- No empty catch blocks — always update connection status

### API Integration
- `Codable` with `CodingKeys` for `snake_case` -> `camelCase` mapping
- All response fields are **optional** — missing fields = `nil`, not crashes
- Unknown JSON keys silently ignored
- Fresh Keychain read every poll cycle (NFR7) — no token caching between cycles
- HTTPS exclusively (NFR9)

### Concurrency
- Structured concurrency only (`async/await`, `Task`)
- No `DispatchQueue`, no GCD, no Combine
- `@Observable` for UI reactivity (not `@Published`)

### Logging
- Framework: `os.Logger`, subsystem `com.cc-hdrm.app`
- Categories: `keychain`, `api`, `polling`, `notification`, `token`
- **NEVER** log credentials, tokens, or sensitive data at any level
- Log state transitions and error context factually

### Accessibility
- All custom views **must** include `.accessibilityLabel()` and `.accessibilityValue()`
- Color is never the only signal — number + color + font weight always triple-encode state
- Respect `accessibilityReduceMotion` for animations

### Date/Time Formatting
- All formatting in `Date+Formatting.swift` — single source of truth
- <1h: `"resets in 47m"` | 1-24h: `"resets in 2h 13m"` | >24h: `"resets in 2d 1h"`
- Same day: `"at 4:52 PM"` | Different day: `"at Mon 7:05 PM"`
- Countdown updates every 60 seconds (not every second)

---

## Allowed Dependencies

**MVP: Zero external dependencies.** The entire app uses only Apple SDK frameworks:
- SwiftUI, AppKit (UI)
- Security (Keychain)
- UserNotifications (alerts)
- os (logging)
- Foundation (networking, data, dates)

Do **not** add third-party packages without explicit approval.

---

## Key Constraints

1. **Menu bar-only** — `LSUIElement=true`, no dock icon, no main window
2. **No persistent storage** — all state in-memory, no database, no UserDefaults for usage data
3. **No data transmission** to any endpoint other than `api.anthropic.com` and `platform.claude.com` (NFR8)
4. **Performance budgets:** <50MB memory, <1% CPU between polls, <200ms popover open, <2s UI update, <10s poll
5. **Graceful degradation** — every component handles disconnected, token-expired, and no-credentials states
6. **Defensive parsing** — API response changes must not crash the app (NFR12)

---

## Anti-Patterns to Avoid

- Creating "Utils" or "Helpers" dump folders — use specific extensions
- Using `DispatchQueue` or GCD — use structured concurrency
- Storing computed state (like `HeadroomState`) as a separate property
- Using `print()` for logging — use `os.Logger`
- Catching errors silently with empty catch blocks
- Mutating `AppState` directly from views
- Caching tokens between poll cycles
- Adding external dependencies without explicit approval

---

## Architectural Boundaries

| Boundary        | Owner Component        | Rule                                                    |
| --------------- | ---------------------- | ------------------------------------------------------- |
| Keychain        | `KeychainService`      | Only component that imports `Security`                  |
| HTTP            | `APIClient`            | Only component that makes external HTTP requests        |
| Notifications   | `NotificationService`  | Only component that imports `UserNotifications`         |
| State           | `AppState`             | All state flows through here; views never write to it   |
| Entitlements    | `cc_hdrm.entitlements` | **Protected file** — do not modify without instruction  |

---

## External Integrations

| Integration         | Endpoint                                         | Purpose              |
| ------------------- | ------------------------------------------------ | -------------------- |
| Usage API           | `GET https://api.anthropic.com/api/oauth/usage`  | Fetch headroom data  |
| Token Refresh       | `POST https://platform.claude.com/v1/oauth/token`| Refresh expired OAuth|
| Keychain            | macOS Security framework                         | Read/write credentials|

**Required Headers (Usage API):**
- `Authorization: Bearer <oauth_access_token>`
- `anthropic-beta: oauth-2025-04-20`
- `User-Agent: claude-code/<version>`

---

## HeadroomState Reference

| State         | Headroom   | Color Token            | Font Weight | Menu Bar Display    |
| ------------- | ---------- | ---------------------- | ----------- | ------------------- |
| `.normal`     | > 40%      | `.headroomNormal`      | Regular     | `✳ 83%`            |
| `.caution`    | 20-40%     | `.headroomCaution`     | Medium      | `✳ 35%`            |
| `.warning`    | 5-20%      | `.headroomWarning`     | Semibold    | `✳ 12%`            |
| `.critical`   | < 5%       | `.headroomCritical`    | Bold        | `✳ 3%`             |
| `.exhausted`  | 0%         | `.headroomExhausted`   | Bold        | `✳ ↻ 47m`          |
| `.disconnected`| N/A       | `.disconnected`        | Regular     | `✳ —`              |

---

## Related Documents

- [Product Brief](./_bmad-output/planning-artifacts/product-brief-cc-usage-2026-01-30.md)
- [PRD](./_bmad-output/planning-artifacts/prd.md)
- [Architecture](./_bmad-output/planning-artifacts/architecture.md)
- [UX Design Specification](./_bmad-output/planning-artifacts/ux-design-specification.md)
- [Epics & Stories](./_bmad-output/planning-artifacts/epics.md)
