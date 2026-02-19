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
    private let patternDetector: (any SubscriptionPatternDetectorProtocol)?
    private let patternNotificationService: (any PatternNotificationServiceProtocol)?
    private let extraUsageAlertService: (any ExtraUsageAlertServiceProtocol)?
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
        slopeCalculationService: (any SlopeCalculationServiceProtocol)? = nil,
        patternDetector: (any SubscriptionPatternDetectorProtocol)? = nil,
        patternNotificationService: (any PatternNotificationServiceProtocol)? = nil,
        extraUsageAlertService: (any ExtraUsageAlertServiceProtocol)? = nil
    ) {
        self.keychainService = keychainService
        self.tokenRefreshService = tokenRefreshService
        self.apiClient = apiClient
        self.appState = appState
        self.notificationService = notificationService
        self.preferencesManager = preferencesManager
        self.historicalDataService = historicalDataService
        self.slopeCalculationService = slopeCalculationService
        self.patternDetector = patternDetector
        self.patternNotificationService = patternNotificationService
        self.extraUsageAlertService = extraUsageAlertService
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

    /// Executes a single poll cycle: read credentials → fetch usage → handle 401 with refresh.
    func performPollCycle() async {
        do {
            let credentials = try await keychainService.readCredentials()
            appState.updateSubscriptionTier(credentials.subscriptionType)
            if appState.oauthState != .authenticated {
                appState.updateOAuthState(.authenticated)
            }

            Self.logger.debug("Credentials loaded — fetching usage data")
            await fetchUsageData(credentials: credentials)
        } catch {
            handleCredentialError(error)
        }
    }

    // MARK: - Private

    private func attemptTokenRefresh(credentials: KeychainCredentials) async {
        guard let refreshToken = credentials.refreshToken else {
            Self.logger.info("No refresh token available — triggering re-authentication")
            appState.updateOAuthState(.unauthenticated)
            appState.updateConnectionStatus(.tokenExpired)
            appState.updateStatusMessage(StatusMessage(
                title: "Session expired",
                detail: "Sign in again to continue"
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

            // Write refreshed tokens to our own Keychain item (safe — no ACL contention)
            try await keychainService.writeCredentials(mergedCredentials)

            appState.updateConnectionStatus(.connected)
            appState.updateStatusMessage(nil)
            Self.logger.info("Token refresh succeeded — credentials persisted to Keychain")
        } catch {
            Self.logger.error("Token refresh failed: \(error.localizedDescription)")
            appState.updateOAuthState(.unauthenticated)
            appState.updateConnectionStatus(.tokenExpired)
            appState.updateStatusMessage(StatusMessage(
                title: "Session expired",
                detail: "Sign in again to continue"
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

            // Propagate extra usage state before windows to avoid transient UI flicker
            if let extra = response.extraUsage {
                appState.updateExtraUsage(
                    enabled: extra.isEnabled ?? false,
                    monthlyLimit: extra.monthlyLimit,
                    usedCredits: extra.usedCredits,
                    utilization: extra.utilization
                )
            } else {
                appState.updateExtraUsage(enabled: false, monthlyLimit: nil, usedCredits: nil, utilization: nil)
            }

            appState.updateWindows(fiveHour: fiveHourState, sevenDay: sevenDayState)
            await notificationService?.evaluateThresholds(fiveHour: fiveHourState, sevenDay: sevenDayState)

            // Evaluate extra usage threshold alerts
            if let alertService = extraUsageAlertService {
                let planExhausted = (fiveHourState?.headroomState == .exhausted) || (sevenDayState?.headroomState == .exhausted)
                await alertService.evaluateExtraUsageThresholds(
                    extraUsageEnabled: response.extraUsage?.isEnabled ?? false,
                    utilization: response.extraUsage?.utilization,
                    usedCreditsCents: response.extraUsage?.usedCredits.map { Int($0.rounded()) },
                    monthlyLimitCents: response.extraUsage?.monthlyLimit.map { Int($0.rounded()) },
                    billingCycleDay: preferencesManager.billingCycleDay,
                    planExhausted: planExhausted
                )
            }

            appState.updateConnectionStatus(.connected)
            appState.updateStatusMessage(nil)

            // Persist to database asynchronously (fire-and-forget, does not block UI)
            // Pass tier for reset event recording, then run pattern analysis
            let tier = credentials.rateLimitTier
            Task { [patternDetector, patternNotificationService] in
                do {
                    try await historicalDataService?.persistPoll(response, tier: tier)
                } catch {
                    Self.logger.error("Failed to persist poll data: \(error.localizedDescription)")
                    // Continue without retrying - data for this cycle is lost
                }

                // Run pattern analysis after persistence (non-blocking)
                if let detector = patternDetector, let notifier = patternNotificationService {
                    do {
                        let findings = try await detector.analyzePatterns()
                        if !findings.isEmpty {
                            await notifier.processFindings(findings)
                        }
                    } catch {
                        Self.logger.error("Pattern analysis failed: \(error.localizedDescription)")
                    }
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
            appState.updateExtraUsage(enabled: false, monthlyLimit: nil, usedCredits: nil, utilization: nil)
            appState.updateConnectionStatus(.disconnected)
            appState.updateStatusMessage(StatusMessage(
                title: "Unable to reach Claude API",
                detail: "Will retry automatically"
            ))
        case .apiError(let statusCode, let body):
            Self.logger.error("API error \(statusCode): \(body ?? "no body")")
            appState.updateExtraUsage(enabled: false, monthlyLimit: nil, usedCredits: nil, utilization: nil)
            appState.updateConnectionStatus(.disconnected)
            appState.updateStatusMessage(StatusMessage(
                title: "API error (\(statusCode))",
                detail: body ?? "Unknown error"
            ))
        case .parseError:
            Self.logger.error("Failed to parse API response")
            appState.updateExtraUsage(enabled: false, monthlyLimit: nil, usedCredits: nil, utilization: nil)
            appState.updateConnectionStatus(.disconnected)
            appState.updateStatusMessage(StatusMessage(
                title: "Unexpected API response format",
                detail: "Will retry automatically"
            ))
        default:
            Self.logger.error("Unexpected error during usage fetch: \(String(describing: error))")
            appState.updateExtraUsage(enabled: false, monthlyLimit: nil, usedCredits: nil, utilization: nil)
            appState.updateConnectionStatus(.disconnected)
            appState.updateStatusMessage(StatusMessage(
                title: "Unexpected error",
                detail: "Will retry automatically"
            ))
        }
    }

    private func handleCredentialError(_ error: any Error) {
        appState.updateCreditLimits(nil)
        appState.updateExtraUsage(enabled: false, monthlyLimit: nil, usedCredits: nil, utilization: nil)
        appState.updateOAuthState(.unauthenticated)
        appState.updateConnectionStatus(.noCredentials)
        appState.updateStatusMessage(StatusMessage(
            title: "Not signed in",
            detail: "Click Sign In to authenticate"
        ))

        if let appError = error as? AppError {
            switch appError {
            case .keychainNotFound:
                Self.logger.info("No OAuth credentials in Keychain — user needs to sign in")
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
