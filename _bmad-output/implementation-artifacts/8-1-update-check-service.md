# Story 8.1: Update Check Service

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want the app to check for updates on launch,
so that I know when a newer version is available without leaving the app.

## Acceptance Criteria

1. **Given** the app launches, **When** `UpdateCheckService` runs, **Then** it fetches `https://api.github.com/repos/{owner}/{repo}/releases/latest` **And** includes headers: `Accept: application/vnd.github.v3+json`, `User-Agent: cc-hdrm/<version>` **And** compares the response `tag_name` (stripped of `v` prefix) against `Bundle.main.infoDictionary["CFBundleShortVersionString"]` **And** `UpdateCheckService` conforms to `UpdateCheckServiceProtocol` for testability.

2. **Given** the latest release version is newer than the running version, **When** the comparison completes, **Then** `AppState.availableUpdate` is set with the version string and download URL (`browser_download_url` of the DMG asset preferred, falling back to ZIP asset, falling back to `html_url`).

3. **Given** the latest release version is equal to or older than the running version, **When** the comparison completes, **Then** `AppState.availableUpdate` remains nil, no badge is shown.

4. **Given** the GitHub API request fails (network error, rate limit, etc.), **When** the fetch fails, **Then** the failure is silent — no error state, no UI impact, no log noise beyond `.debug` level **And** the app functions normally without update awareness.

## Tasks / Subtasks

- [x] Task 1: Create `UpdateCheckServiceProtocol` (AC: #1)
  - [x] Define protocol with `func checkForUpdate() async`
  - [x] Place in `cc-hdrm/Services/UpdateCheckServiceProtocol.swift`

- [x] Task 2: Create `AvailableUpdate` model (AC: #2)
  - [x] Define struct with `version: String` and `downloadURL: URL`
  - [x] Place in `cc-hdrm/Models/AvailableUpdate.swift`
  - [x] Conform to `Sendable` and `Equatable`

- [x] Task 3: Create `GitHubRelease` Codable model (AC: #1)
  - [x] Define private Codable struct for GitHub API response parsing
  - [x] Include `tagName`, `htmlUrl`, `assets` array with `browserDownloadUrl` and `name`
  - [x] Use `CodingKeys` for `snake_case` → `camelCase` mapping
  - [x] Can be defined inside `UpdateCheckService.swift` (not public model)

- [x] Task 4: Add `availableUpdate` to `AppState` (AC: #2, #3)
  - [x] Add `private(set) var availableUpdate: AvailableUpdate?` to `AppState` (`cc-hdrm/State/AppState.swift`)
  - [x] Add mutation method `func updateAvailableUpdate(_ update: AvailableUpdate?)`

- [x] Task 5: Implement `UpdateCheckService` (AC: #1, #2, #3, #4)
  - [x] Create `cc-hdrm/Services/UpdateCheckService.swift`
  - [x] Use injectable `DataLoader` pattern (same as `APIClient`)
  - [x] Implement semver comparison (major.minor.patch numeric comparison)
  - [x] Extract ZIP asset URL from `assets` array, fall back to `htmlUrl`
  - [x] All failures caught silently — log at `.debug` level only
  - [x] Accept `PreferencesManagerProtocol` dependency for `dismissedVersion` check

- [x] Task 6: Wire `UpdateCheckService` into app lifecycle (AC: #1)
  - [x] Create and call from `AppDelegate` after polling starts
  - [x] Fire-and-forget `Task` — do not block app launch
  - [x] Add `UpdateCheckService` to `AppDelegate` properties

- [x] Task 7: Write tests (AC: #1, #2, #3, #4)
  - [x] Create `cc-hdrmTests/Services/UpdateCheckServiceTests.swift`
  - [x] Create `cc-hdrmTests/Mocks/MockUpdateCheckService.swift`
  - [x] Test: newer version available → sets `availableUpdate`
  - [x] Test: same version → `availableUpdate` remains nil
  - [x] Test: older version → `availableUpdate` remains nil
  - [x] Test: network failure → silent, no error state
  - [x] Test: malformed JSON → silent, no error state
  - [x] Test: missing assets → falls back to `htmlUrl`
  - [x] Test: dismissed version matches → `availableUpdate` remains nil
  - [x] Test: semver comparison edge cases (1.0.9 vs 1.0.10, 2.0.0 vs 1.99.99)

## Dev Notes

### Architecture Compliance

- Architecture specifies `UpdateCheckService` design at `_bmad-output/planning-artifacts/architecture.md` lines 669-684.
- Service must conform to `UpdateCheckServiceProtocol` for testability — follows project-wide protocol pattern.
- Uses injectable `DataLoader` pattern matching `APIClient` (`cc-hdrm/Services/APIClient.swift` lines 13-27).
- `AppState` mutation via method only (`updateAvailableUpdate()`), never direct property set — per `_bmad-output/planning-artifacts/architecture.md` lines 356-368.
- This is a **new external HTTP endpoint** (`api.github.com`). Note: architecture boundary rule says `APIClient` is the "only component that makes external HTTP requests" (`_bmad-output/planning-artifacts/project-context.md` line 186). However, `UpdateCheckService` hits a completely different API (GitHub, not Anthropic) with different auth. The pragmatic approach: `UpdateCheckService` makes its own requests via the same injectable `DataLoader` pattern. This is consistent with how `TokenRefreshService` also makes HTTP requests to `platform.claude.com` independent of `APIClient`.
- **Silent failure is mandatory.** Update check errors must NEVER propagate to `AppState.connectionStatus` or affect usage monitoring. This is fundamentally different from `APIClient` errors which DO affect connection status.

### Key Implementation Details

**GitHub Releases API endpoint:**

```
GET https://api.github.com/repos/{owner}/{repo}/releases/latest
```

The `{owner}` and `{repo}` must be determined. Options:
1. Hardcode (simplest, appropriate for a single-repo project)
2. Read from a config constant

Recommend: Define a `private static let` constant in `UpdateCheckService` for owner/repo. The repo is `rajish/cc-hdrm` based on the git remote.

**Required headers:**

```swift
request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
request.setValue("cc-hdrm/\(currentVersion)", forHTTPHeaderField: "User-Agent")
```

No authentication required — public repo. GitHub unauthenticated rate limit: 60 req/hr (more than enough for once-per-launch).

**Response format (relevant fields only):**

```json
{
  "tag_name": "v1.0.1",
  "html_url": "https://github.com/rajish/cc-usage/releases/tag/v1.0.1",
  "assets": [
    {
      "name": "cc-hdrm-v1.0.1-macos.zip",
      "browser_download_url": "https://github.com/rajish/cc-usage/releases/download/v1.0.1/cc-hdrm-v1.0.1-macos.zip"
    },
    {
      "name": "cc-hdrm-v1.0.1.dmg",
      "browser_download_url": "https://github.com/rajish/cc-usage/releases/download/v1.0.1/cc-hdrm-v1.0.1.dmg"
    }
  ]
}
```

**Version comparison — semver numeric, not string:**

```swift
// WRONG: "1.0.9" > "1.0.10" (string comparison)
// RIGHT: Compare major, minor, patch as integers
func isNewer(_ remote: String, than local: String) -> Bool {
    let r = remote.split(separator: ".").compactMap { Int($0) }
    let l = local.split(separator: ".").compactMap { Int($0) }
    guard r.count == 3, l.count == 3 else { return false }
    return (r[0], r[1], r[2]) > (l[0], l[1], l[2])
}
```

**Strip `v` prefix from `tag_name`:**

```swift
let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
```

**ZIP asset selection:**

Find the first asset whose `name` contains `macos.zip`. Fall back to `htmlUrl` (the release page) if no ZIP asset exists.

**DismissedVersion check:**

Before setting `AppState.availableUpdate`, check if the version matches `preferencesManager.dismissedVersion`. If it does, do NOT set the update — the user already dismissed this version. This prevents the badge from reappearing.

```swift
if version == preferencesManager.dismissedVersion {
    logger.debug("Version \(version) was dismissed by user, skipping update notification")
    return
}
```

**Logging:**

Use a new logger category: `update`.

```swift
private static let logger = Logger(subsystem: "com.cc-hdrm.app", category: "update")
```

All log levels must be `.debug` for this service — update check failures are not actionable errors.

**Timeout:**

Use a shorter timeout than the usage API (e.g., 5 seconds). Update check is best-effort and should not delay app startup.

### Previous Story Intelligence (7.3)

- Story 7.3 created the release infrastructure that produces the GitHub Releases this service queries. Releases include ZIP and DMG assets with checksums.
- Asset naming convention from `release-publish.yml`: `cc-hdrm-v{version}-macos.zip` and `cc-hdrm-v{version}.dmg`.
- The first real release is v1.0.1. Current `Info.plist` version is `1.0.1`.
- **CI runner note from Epic 7 retro:** CI uses `macos-15` with Xcode 26.2 (Swift 6.2). Ensure any new code compiles under strict concurrency. Mark `UpdateCheckService` as `@unchecked Sendable` (same pattern as `APIClient`).

### Git Intelligence

Recent commits show the project is at v1.0.1 post-release. The last 10 commits are all Epic 7 work (release infrastructure). No Swift service code was changed in Epic 7 except CI-related fixes to `AppDelegate`, `NotificationCenterProtocol`, and `NotificationService`.

### Project Structure Notes

Files to CREATE:
```
cc-hdrm/Services/UpdateCheckServiceProtocol.swift    # NEW — protocol
cc-hdrm/Services/UpdateCheckService.swift            # NEW — implementation
cc-hdrm/Models/AvailableUpdate.swift                 # NEW — model
cc-hdrmTests/Services/UpdateCheckServiceTests.swift  # NEW — tests
cc-hdrmTests/Mocks/MockUpdateCheckService.swift      # NEW — mock for views/integration
```

Files to MODIFY:
```
cc-hdrm/State/AppState.swift                         # ADD availableUpdate property + mutation method
cc-hdrm/App/AppDelegate.swift                        # ADD UpdateCheckService wiring
```

Files NOT to modify:
```
cc-hdrm/cc_hdrm.entitlements                        # PROTECTED — do not touch
cc-hdrm/Services/APIClient.swift                     # Not involved — different endpoint
cc-hdrm/Services/PreferencesManager.swift            # Already has dismissedVersion — no changes needed
cc-hdrm/Models/AppError.swift                        # Update check errors are silent, no new cases needed
```

### Testing Requirements

- Use **Swift Testing** framework (`import Testing`), not XCTest — consistent with all existing tests.
- Follow injectable `DataLoader` pattern for network mocking — same as `cc-hdrmTests/Services/APIClientTests.swift`.
- Mock `PreferencesManagerProtocol` using existing `cc-hdrmTests/Mocks/MockPreferencesManager.swift` — it already supports `dismissedVersion`.
- `MockUpdateCheckService` should be minimal: store `availableUpdate` result, conform to protocol.
- Test the semver comparison logic thoroughly — this is the most error-prone part.
- Test that `AppState.availableUpdate` is nil when version is dismissed.
- Test that network/parse failures result in NO changes to `AppState` (not even `connectionStatus`).
- **No UI tests in this story.** Story 8.2 will add the badge UI.

### Library & Framework Requirements

- **Foundation** — `URLSession`, `URLRequest`, `JSONDecoder`, `Bundle` (already imported everywhere)
- **os** — `Logger` (already used by all services)
- **No new dependencies.** Zero external packages.
- GitHub API v3 — no authentication needed for public repos

### Anti-Patterns to Avoid

- DO NOT extend `APIClient` or `APIClientProtocol` — this is a separate service with different error semantics
- DO NOT add update-check error cases to `AppError` — failures are silent by design
- DO NOT use string comparison for semver — must compare numeric components
- DO NOT log at `.info` or `.error` level — update check failures are `.debug` only
- DO NOT affect `AppState.connectionStatus` on update check failure — usage monitoring is independent
- DO NOT block app launch waiting for update check — use fire-and-forget `Task`
- DO NOT cache the update check result beyond `AppState.availableUpdate` — one check per launch is sufficient
- DO NOT make requests to any domain other than `api.github.com` for this service (NFR8 spirit — minimize external calls)

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` #Story 8.1, lines 846-873] — Full acceptance criteria
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Update Check Service, lines 669-684] — Service design, headers, comparison logic, error handling
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Phase 2 Project Structure, lines 730-748] — File locations
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Phase 2 Data Flow, lines 760-775] — UpdateCheckService → AppState flow
- [Source: `_bmad-output/planning-artifacts/prd.md` #FR25] — Dismissable update badge (UI in Story 8.2, service logic here)
- [Source: `_bmad-output/planning-artifacts/prd.md` #FR26] — Direct download link (download URL extraction here)
- [Source: `cc-hdrm/Services/APIClient.swift`] — Injectable `DataLoader` pattern to replicate
- [Source: `cc-hdrm/State/AppState.swift`] — Current AppState (no update properties yet)
- [Source: `cc-hdrm/Services/PreferencesManagerProtocol.swift` line 18] — `dismissedVersion` already in protocol
- [Source: `cc-hdrmTests/Mocks/MockPreferencesManager.swift`] — Existing mock with `dismissedVersion` support
- [Source: `_bmad-output/implementation-artifacts/epic-7-retro-release-infrastructure.md`] — CI uses Xcode 26.2, strict concurrency

## Dev Agent Record

### Agent Model Used

Claude Opus 4.5 (anthropic/claude-opus-4-5)

### Debug Log References

None — clean implementation, no debugging required.

### Completion Notes List

- Created `UpdateCheckServiceProtocol` with `Sendable` conformance for safe cross-isolation usage
- Created `AvailableUpdate` model conforming to `Sendable` and `Equatable`
- Implemented `GitHubRelease` as private `Codable` struct inside `UpdateCheckService.swift` with `CodingKeys` for snake_case mapping
- Added `availableUpdate: AvailableUpdate?` property and `updateAvailableUpdate(_:)` mutation method to `AppState`
- Implemented `UpdateCheckService` with injectable `DataLoader` pattern, semver numeric comparison, ZIP asset extraction with `htmlUrl` fallback, dismissed version check, and all-silent `.debug`-level error handling
- Wired `UpdateCheckService` into `AppDelegate.applicationDidFinishLaunching` as fire-and-forget `Task`
- 12 comprehensive tests covering: newer/same/older version, network failure, malformed JSON, missing assets fallback, dismissed version, semver edge cases (1.0.9 vs 1.0.10, 2.0.0 vs 1.99.99, malformed), non-200 response, tag without v prefix
- All 355 tests pass (343 existing + 12 new)

### Architecture Deviations

- Added `Sendable` conformance to `UpdateCheckServiceProtocol` — required by Swift 6 strict concurrency since the service reference crosses `@MainActor` isolation boundary in `AppDelegate`'s fire-and-forget `Task`. Consistent with how `UpdateCheckService` is marked `@unchecked Sendable` (same as `APIClient`).

### Change Log

- 2026-02-02: Implemented UpdateCheckService — GitHub Releases API integration with semver comparison, silent failure handling, dismissed version check, and 12 unit tests. All 355 tests pass.
- 2026-02-02: Code review fixes — Updated AC #2 to reflect DMG-preferred asset selection (by design). Fixed test URLs from cc-usage to cc-hdrm. Fixed Dev Notes repo name. Added @MainActor to test initializer. Removed redundant instance isNewer wrapper. Added empty assets array test. Removed false pbxproj claim from File List.

### File List

**New files:**
- `cc-hdrm/Services/UpdateCheckServiceProtocol.swift`
- `cc-hdrm/Services/UpdateCheckService.swift`
- `cc-hdrm/Models/AvailableUpdate.swift`
- `cc-hdrmTests/Services/UpdateCheckServiceTests.swift`
- `cc-hdrmTests/Mocks/MockUpdateCheckService.swift`

**Modified files:**
- `cc-hdrm/State/AppState.swift` — added `availableUpdate` property and `updateAvailableUpdate()` method
- `cc-hdrm/App/AppDelegate.swift` — added `updateCheckService` property and fire-and-forget update check call
