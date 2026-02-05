import Foundation
import os

/// Background polling engine that orchestrates the poll-parse-update pipeline.
/// Reads credentials fresh each cycle, checks token expiry, fetches usage data,
/// and updates AppState accordingly. Errors are caught and mapped to connection status.
@MainActor
final class PollingEngine: PollingEngineProtocol {
    private let keychainService: any KeychainServiceProtocol
    private let tokenRefreshService: any TokenRefreshServiceProtocol
    private let apiClient: any APIClientProtocol
    private let appState: AppState
    private let notificationService: (any NotificationServiceProtocol)?
    private let preferencesManager: any PreferencesManagerProtocol
    private let historicalDataService: (any HistoricalDataServiceProtocol)?
    private let slopeCalculationService: (any SlopeCalculationServiceProtocol)?
    private var pollingTask: Task<Void, Never>?
    private var sparklineRefreshTask: Task<Void, Never>?

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "polling"
    )

    init(
        keychainService: any KeychainServiceProtocol,
        tokenRefreshService: any TokenRefreshServiceProtocol,
        apiClient: any APIClientProtocol,
        appState: AppState,
        notificationService: (any NotificationServiceProtocol)? = nil,
        preferencesManager: any PreferencesManagerProtocol = PreferencesManager(),
        historicalDataService: (any HistoricalDataServiceProtocol)? = nil,
        slopeCalculationService: (any SlopeCalculationServiceProtocol)? = nil
    ) {
        self.keychainService = keychainService
        self.tokenRefreshService = tokenRefreshService
        self.apiClient = apiClient
        self.appState = appState
        self.notificationService = notificationService
        self.preferencesManager = preferencesManager
        self.historicalDataService = historicalDataService
        self.slopeCalculationService = slopeCalculationService
    }

    func start() async {
        Self.logger.info("Polling engine starting — performing initial fetch")
        await performPollCycle()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.preferencesManager.pollInterval ?? PreferencesDefaults.pollInterval
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                Self.logger.debug("Poll cycle triggered")
                await self?.performPollCycle()
            }
            Self.logger.info("Polling engine stopped")
        }
    }

    func stop() {
        Self.logger.info("Polling engine stopping")
        pollingTask?.cancel()
        pollingTask = nil
        sparklineRefreshTask?.cancel()
        sparklineRefreshTask = nil
    }

    // MARK: - Internal (exposed for testing)

    /// Executes a single poll cycle: read credentials → check token → fetch usage → update state.
    func performPollCycle() async {
        do {
            let credentials = try await keychainService.readCredentials()
            appState.updateSubscriptionTier(credentials.subscriptionType)

            let status = TokenExpiryChecker.tokenStatus(for: credentials)

            switch status {
            case .valid:
                Self.logger.debug("Token valid — fetching usage data")
                await fetchUsageData(credentials: credentials)

            case .expired, .expiringSoon:
                Self.logger.info("Token \(status == .expired ? "expired" : "expiring soon") — attempting refresh")
                await attemptTokenRefresh(credentials: credentials)
            }
        } catch {
            handleCredentialError(error)
        }
    }

    // MARK: - Private

    private func attemptTokenRefresh(credentials: KeychainCredentials) async {
        guard let refreshToken = credentials.refreshToken else {
            Self.logger.info("No refresh token available — setting token expired status")
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
            Self.logger.info("Token refresh succeeded — credentials updated in Keychain")
        } catch {
            Self.logger.error("Token refresh failed: \(error.localizedDescription)")
            appState.updateConnectionStatus(.tokenExpired)
            appState.updateStatusMessage(StatusMessage(
                title: "Token expired",
                detail: "Run any Claude Code command to refresh"
            ))
        }
    }

    private func fetchUsageData(credentials: KeychainCredentials) async {
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

            // Resolve credit limits from tier string each cycle (tier could change on subscription upgrade)
            let resolvedLimits = RateLimitTier.resolve(
                tierString: credentials.rateLimitTier,
                preferencesManager: preferencesManager
            )
            appState.updateCreditLimits(resolvedLimits)

            appState.updateWindows(fiveHour: fiveHourState, sevenDay: sevenDayState)
            await notificationService?.evaluateThresholds(fiveHour: fiveHourState, sevenDay: sevenDayState)
            appState.updateConnectionStatus(.connected)
            appState.updateStatusMessage(nil)

            // Persist to database asynchronously (fire-and-forget, does not block UI)
            // Pass tier for reset event recording
            let tier = credentials.rateLimitTier
            Task {
                do {
                    try await historicalDataService?.persistPoll(response, tier: tier)
                } catch {
                    Self.logger.error("Failed to persist poll data: \(error.localizedDescription)")
                    // Continue without retrying - data for this cycle is lost
                }
            }

            // Update slope calculation with new poll data
            if let slopeService = slopeCalculationService {
                // Convert UsageResponse to UsagePoll for slope service
                let poll = UsagePoll(
                    id: 0, // Not from DB, ID doesn't matter
                    timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                    fiveHourUtil: response.fiveHour?.utilization,
                    fiveHourResetsAt: nil, // Not needed for slope
                    sevenDayUtil: response.sevenDay?.utilization,
                    sevenDayResetsAt: nil
                )
                slopeService.addPoll(poll)

                let normFactor = resolvedLimits?.normalizationFactor
                let fiveHourSlope = slopeService.calculateSlope(for: .fiveHour)
                let sevenDaySlope = slopeService.calculateSlope(for: .sevenDay, normalizationFactor: normFactor)
                appState.updateSlopes(fiveHour: fiveHourSlope, sevenDay: sevenDaySlope)
            }

            // Cancel any in-flight sparkline refresh to prevent races
            sparklineRefreshTask?.cancel()

            // Refresh sparkline data for popover (async, non-blocking)
            sparklineRefreshTask = Task { [weak self] in
                guard let self, !Task.isCancelled else { return }
                do {
                    if let data = try await historicalDataService?.getRecentPolls(hours: 24) {
                        guard !Task.isCancelled else { return }
                        // MainActor.run required: Task escapes @MainActor context of PollingEngine
                        await MainActor.run {
                            appState.updateSparklineData(data)
                        }
                        Self.logger.debug("Sparkline data refreshed: \(data.count) points")
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    Self.logger.error("Failed to refresh sparkline data: \(error.localizedDescription)")
                }
            }

            Self.logger.info("Usage data fetched and applied successfully")
        } catch let error as AppError {
            await handleAPIError(error, credentials: credentials)
        } catch {
            Self.logger.error("Unexpected non-AppError during usage fetch: \(error.localizedDescription)")
            appState.updateConnectionStatus(.disconnected)
            appState.updateStatusMessage(StatusMessage(
                title: "Unexpected error",
                detail: "Will retry automatically"
            ))
        }
    }

    private func handleAPIError(_ error: AppError, credentials: KeychainCredentials) async {
        switch error {
        case .apiError(statusCode: 401, _):
            Self.logger.info("API returned 401 — triggering token refresh")
            await attemptTokenRefresh(credentials: credentials)
        case .networkUnreachable:
            Self.logger.error("Network unreachable during usage fetch")
            appState.updateConnectionStatus(.disconnected)
            appState.updateStatusMessage(StatusMessage(
                title: "Unable to reach Claude API",
                detail: "Will retry automatically"
            ))
        case .apiError(let statusCode, let body):
            Self.logger.error("API error \(statusCode): \(body ?? "no body")")
            appState.updateConnectionStatus(.disconnected)
            appState.updateStatusMessage(StatusMessage(
                title: "API error (\(statusCode))",
                detail: body ?? "Unknown error"
            ))
        case .parseError:
            Self.logger.error("Failed to parse API response")
            appState.updateConnectionStatus(.disconnected)
            appState.updateStatusMessage(StatusMessage(
                title: "Unexpected API response format",
                detail: "Will retry automatically"
            ))
        default:
            Self.logger.error("Unexpected error during usage fetch: \(String(describing: error))")
            appState.updateConnectionStatus(.disconnected)
            appState.updateStatusMessage(StatusMessage(
                title: "Unexpected error",
                detail: "Will retry automatically"
            ))
        }
    }

    private func handleCredentialError(_ error: any Error) {
        appState.updateCreditLimits(nil)
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
}
