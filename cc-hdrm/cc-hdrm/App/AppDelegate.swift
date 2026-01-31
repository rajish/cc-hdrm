import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    internal var appState: AppState?
    private let keychainService: any KeychainServiceProtocol
    private let tokenRefreshService: any TokenRefreshServiceProtocol
    private let apiClient: any APIClientProtocol
    private var pollingTask: Task<Void, Never>?

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "AppDelegate"
    )

    private static let tokenLogger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "token"
    )

    private static let apiLogger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "api"
    )

    override init() {
        self.keychainService = KeychainService()
        self.tokenRefreshService = TokenRefreshService()
        self.apiClient = APIClient()
        super.init()
    }

    /// Test-only initializer for injecting mock services.
    init(
        keychainService: any KeychainServiceProtocol,
        tokenRefreshService: any TokenRefreshServiceProtocol = TokenRefreshService(),
        apiClient: any APIClientProtocol = APIClient()
    ) {
        self.keychainService = keychainService
        self.tokenRefreshService = tokenRefreshService
        self.apiClient = apiClient
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
                Self.logger.info("Credentials found — token valid, fetching usage data")
                await fetchUsageData(credentials: credentials, appState: appState)

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

    private func fetchUsageData(credentials: KeychainCredentials, appState: AppState) async {
        do {
            let response = try await apiClient.fetchUsage(token: credentials.accessToken)

            let fiveHourState = response.fiveHour.map { window in
                WindowState(
                    utilization: window.utilization ?? 0.0,
                    resetsAt: window.resetsAt.flatMap { Date.fromISO8601($0) }
                )
            }
            let sevenDayState = response.sevenDay.map { window in
                WindowState(
                    utilization: window.utilization ?? 0.0,
                    resetsAt: window.resetsAt.flatMap { Date.fromISO8601($0) }
                )
            }

            // Note: sevenDaySonnet and extraUsage are intentionally not mapped to WindowState yet.
            // These will be surfaced in a future story when the UI supports additional windows.
            appState.updateWindows(fiveHour: fiveHourState, sevenDay: sevenDayState)
            appState.updateConnectionStatus(.connected)
            appState.updateStatusMessage(nil)
            Self.apiLogger.info("Usage data fetched and applied successfully")
        } catch let error as AppError {
            switch error {
            case .apiError(statusCode: 401, _):
                Self.apiLogger.info("API returned 401 — triggering token refresh")
                await attemptTokenRefresh(credentials: credentials, appState: appState)
            case .networkUnreachable:
                Self.apiLogger.error("Network unreachable during usage fetch")
                appState.updateConnectionStatus(.disconnected)
                appState.updateStatusMessage(StatusMessage(
                    title: "Unable to reach Claude API",
                    detail: "Will retry automatically"
                ))
            case .apiError(let statusCode, let body):
                Self.apiLogger.error("API error \(statusCode): \(body ?? "no body")")
                appState.updateConnectionStatus(.disconnected)
                appState.updateStatusMessage(StatusMessage(
                    title: "API error (\(statusCode))",
                    detail: body ?? "Unknown error"
                ))
            case .parseError:
                Self.apiLogger.error("Failed to parse API response")
                appState.updateConnectionStatus(.disconnected)
                appState.updateStatusMessage(StatusMessage(
                    title: "Unexpected API response format",
                    detail: "Will retry automatically"
                ))
            default:
                Self.apiLogger.error("Unexpected error during usage fetch: \(String(describing: error))")
                appState.updateConnectionStatus(.disconnected)
                appState.updateStatusMessage(StatusMessage(
                    title: "Unexpected error",
                    detail: "Will retry automatically"
                ))
            }
        } catch {
            Self.apiLogger.error("Unexpected non-AppError during usage fetch: \(error.localizedDescription)")
            appState.updateConnectionStatus(.disconnected)
            appState.updateStatusMessage(StatusMessage(
                title: "Unexpected error",
                detail: "Will retry automatically"
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
