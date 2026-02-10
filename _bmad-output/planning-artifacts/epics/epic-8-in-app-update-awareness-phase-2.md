# Epic 8: In-App Update Awareness (Phase 2)

Alex sees a subtle badge in the popover when a new version is available — one click to download, one click to dismiss. No nag, no interruption, just awareness.

## Story 8.1: Update Check Service

As a developer using Claude Code,
I want the app to check for updates on launch,
So that I know when a newer version is available without leaving the app.

**Acceptance Criteria:**

**Given** the app launches
**When** UpdateCheckService runs
**Then** it fetches `https://api.github.com/repos/{owner}/{repo}/releases/latest`
**And** includes headers: `Accept: application/vnd.github.v3+json`, `User-Agent: cc-hdrm/<version>`
**And** compares the response `tag_name` (stripped of `v` prefix) against `Bundle.main.infoDictionary["CFBundleShortVersionString"]`
**And** UpdateCheckService conforms to UpdateCheckServiceProtocol for testability

**Given** the latest release version is newer than the running version
**When** the comparison completes
**Then** AppState.availableUpdate is set with the version string and download URL (browser_download_url of the ZIP asset, falling back to html_url)

**Given** the latest release version is equal to or older than the running version
**When** the comparison completes
**Then** AppState.availableUpdate remains nil, no badge is shown

**Given** the GitHub API request fails (network error, rate limit, etc.)
**When** the fetch fails
**Then** the failure is silent — no error state, no UI impact, no log noise beyond `.debug` level
**And** the app functions normally without update awareness

## Story 8.2: Dismissable Update Badge & Download Link

As a developer using Claude Code,
I want to see and dismiss an update badge in the popover,
So that I'm aware of updates without being nagged.

**Acceptance Criteria:**

**Given** AppState.availableUpdate is set (newer version available)
**And** PreferencesManager.dismissedVersion != the available version
**When** the popover renders
**Then** a subtle badge appears in the popover (e.g., above the footer or below the gauges): "v{version} available" with a download icon/link (FR25)
**And** the download link opens the release URL in the default browser (FR26)
**And** a dismiss button (X or "Dismiss") is visible next to the badge

**Given** Alex clicks the dismiss button
**When** the badge is dismissed
**Then** PreferencesManager.dismissedVersion is set to the available version
**And** the badge disappears immediately
**And** the badge does not reappear on subsequent launches or popover opens

**Given** a _newer_ version is released after Alex dismissed a previous update
**When** UpdateCheckService detects a version newer than dismissedVersion
**Then** the badge reappears for the new version
**And** the cycle repeats (dismiss stores the new version)

**Given** Alex installed via Homebrew
**When** the update badge is shown
**Then** the badge also shows "or `brew upgrade cc-hdrm`" as alternative update path

**Given** a VoiceOver user focuses the update badge
**When** VoiceOver reads the element
**Then** it announces "Update available: version {version}. Activate to download. Double tap to dismiss."
