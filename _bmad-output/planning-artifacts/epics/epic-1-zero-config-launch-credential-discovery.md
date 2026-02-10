# Epic 1: Zero-Config Launch & Credential Discovery

Alex launches the app and it silently finds his Claude credentials — or shows him exactly what's wrong. App runs as menu bar utility (no dock icon, no main window), reads OAuth credentials from macOS Keychain, detects subscription tier, and handles token expiry with clear actionable messaging.

## Story 1.1: Xcode Project Initialization & Menu Bar Shell

As a developer,
I want a properly configured Xcode project with a menu bar presence,
So that I have the foundation for all subsequent features.

**Acceptance Criteria:**

**Given** a fresh clone of the repository
**When** the developer opens and builds the project in Xcode
**Then** the app compiles and launches as a menu bar-only utility (no dock icon, no main window)
**And** an NSStatusItem appears in the menu bar showing a placeholder "✳ --"
**And** Info.plist has LSUIElement=true
**And** the project targets macOS 14.0+ (Sonoma)
**And** Keychain access entitlement is configured
**And** the project structure follows the Architecture's layer-based layout (App/, Models/, Services/, State/, Views/, Extensions/, Resources/)
**And** HeadroomState enum is defined with states: .normal, .caution, .warning, .critical, .exhausted, .disconnected
**And** AppError enum is defined with all error cases from Architecture
**And** AppState is created as @Observable @MainActor with placeholder properties

## Story 1.2: Keychain Credential Discovery

As a developer using Claude Code,
I want the app to automatically find my OAuth credentials in the macOS Keychain,
So that I never need to configure anything manually.

**Acceptance Criteria:**

**Given** Claude Code credentials exist in the Keychain (service: "Claude Code-credentials")
**When** the app launches
**Then** the app reads and parses the claudeAiOauth JSON object from the Keychain
**And** the app extracts accessToken, refreshToken, expiresAt, subscriptionType, and rateLimitTier
**And** the subscription tier is stored in AppState
**And** credentials are never persisted to disk, logs, or UserDefaults (NFR6)
**And** all Keychain access goes through KeychainServiceProtocol

**Given** no Claude Code credentials exist in the Keychain
**When** the app launches
**Then** the menu bar shows "✳ —" in grey
**And** a StatusMessageView-compatible status is set: "No Claude credentials found" / "Run Claude Code to create them"
**And** the app polls the Keychain every 30 seconds for new credentials
**And** when credentials appear, the app transitions to normal operation silently

**Given** the Keychain contains malformed JSON
**When** the app reads credentials
**Then** the app logs the parse error via os.Logger (keychain category)
**And** treats it as "no credentials" state
**And** does not crash (NFR11)

## Story 1.3: Token Expiry Detection & Refresh

As a developer using Claude Code,
I want the app to detect expired tokens and attempt refresh automatically,
So that I maintain continuous usage visibility without manual intervention.

**Acceptance Criteria:**

**Given** credentials exist with an expiresAt timestamp in the past
**When** the app reads credentials during a poll cycle
**Then** the app attempts token refresh via POST to platform.claude.com/v1/oauth/token
**And** if refresh succeeds, the new access token is written back to the Keychain
**And** normal operation resumes — Alex never knows it happened

**Given** token refresh fails (network error, invalid refresh token, etc.)
**When** the refresh attempt completes
**Then** the menu bar shows "✳ —" in grey
**And** a status is set: "Token expired" / "Run any Claude Code command to refresh"
**And** the error is logged via os.Logger (token category)
**And** the app continues polling the Keychain every 30 seconds for externally refreshed credentials

**Given** credentials exist with expiresAt approaching (within 5 minutes)
**When** the app reads credentials during a poll cycle
**Then** the app pre-emptively attempts token refresh before expiry
