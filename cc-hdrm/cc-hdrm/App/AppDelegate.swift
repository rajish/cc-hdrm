import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    internal var appState: AppState?
    private let keychainService: any KeychainServiceProtocol
    private let tokenRefreshService: any TokenRefreshServiceProtocol
    private var pollingTask: Task<Void, Never>?

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "AppDelegate"
    )

    private static let tokenLogger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "token"
    )

    override init() {
        self.keychainService = KeychainService()
        self.tokenRefreshService = TokenRefreshService()
        super.init()
    }

    /// Test-only initializer for injecting mock services.
    init(
        keychainService: any KeychainServiceProtocol,
        tokenRefreshService: any TokenRefreshServiceProtocol = TokenRefreshService()
    ) {
        self.keychainService = keychainService
        self.tokenRefreshService = tokenRefreshService
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.logger.info("Application launching — configuring menu bar status item")

        let state = AppState()
        self.appState = state

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = "\u{2733} --"
            button.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.contentTintColor = .systemGray
        }

        Self.logger.info("Menu bar status item configured with placeholder")

        // Initial credential read and start polling
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.performCredentialRead()
            await self.startPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingTask?.cancel()
    }

    /// Exposed for testing. In production, called internally by polling loop.
    func performCredentialReadForTesting() async {
        await performCredentialRead()
    }

    private func performCredentialRead() async {
        guard let appState else { return }
        do {
            let credentials = try await keychainService.readCredentials()
            appState.updateSubscriptionTier(credentials.subscriptionType)

            // Check token expiry status
            let status = TokenExpiryChecker.tokenStatus(for: credentials)

            switch status {
            case .valid:
                appState.updateConnectionStatus(.connected)
                appState.updateStatusMessage(nil)
                Self.logger.info("Credentials found — token valid, connection status set to connected")

            case .expired, .expiringSoon:
                Self.tokenLogger.info("Token \(status == .expired ? "expired" : "expiring soon") — attempting refresh")
                await attemptTokenRefresh(credentials: credentials, appState: appState)
            }
        } catch {
            handleCredentialError(error, appState: appState)
        }
    }

    private func attemptTokenRefresh(credentials: KeychainCredentials, appState: AppState) async {
        guard let refreshToken = credentials.refreshToken else {
            Self.tokenLogger.info("No refresh token available — setting token expired status")
            appState.updateConnectionStatus(.tokenExpired)
            appState.updateStatusMessage(StatusMessage(
                title: "Token expired",
                detail: "Run any Claude Code command to refresh"
            ))
            return
        }

        do {
            let refreshedCredentials = try await tokenRefreshService.refreshToken(using: refreshToken)

            // Merge refreshed fields with original credentials to preserve subscriptionType, rateLimitTier, scopes
            let mergedCredentials = KeychainCredentials(
                accessToken: refreshedCredentials.accessToken,
                refreshToken: refreshedCredentials.refreshToken,
                expiresAt: refreshedCredentials.expiresAt,
                subscriptionType: credentials.subscriptionType,
                rateLimitTier: credentials.rateLimitTier,
                scopes: credentials.scopes
            )

            try await keychainService.writeCredentials(mergedCredentials)

            appState.updateConnectionStatus(.connected)
            appState.updateStatusMessage(nil)
            Self.tokenLogger.info("Token refresh succeeded — credentials updated in Keychain")
        } catch {
            Self.tokenLogger.error("Token refresh failed: \(error.localizedDescription)")
            appState.updateConnectionStatus(.tokenExpired)
            appState.updateStatusMessage(StatusMessage(
                title: "Token expired",
                detail: "Run any Claude Code command to refresh"
            ))
        }
    }

    private func handleCredentialError(_ error: any Error, appState: AppState) {
        appState.updateConnectionStatus(.noCredentials)
        appState.updateStatusMessage(StatusMessage(
            title: "No Claude credentials found",
            detail: "Run Claude Code to create them"
        ))

        if let appError = error as? AppError {
            switch appError {
            case .keychainNotFound:
                Self.logger.info("No credentials in Keychain — waiting for user to run Claude Code")
            case .keychainAccessDenied:
                Self.logger.error("Keychain access denied")
            case .keychainInvalidFormat:
                Self.logger.error("Keychain contains malformed credential data")
            default:
                Self.logger.error("Unexpected error reading credentials: \(String(describing: appError))")
            }
        }
    }

    private func startPolling() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { break }
            await performCredentialRead()
        }
    }
}
