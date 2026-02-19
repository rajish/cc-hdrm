import SwiftUI

/// Root SwiftUI view displayed inside the NSPopover when the user clicks the menu bar item.
/// Observes `AppState` via `@Observable` — re-renders automatically when data changes (AC #5).
struct PopoverView: View {
    let appState: AppState
    let preferencesManager: PreferencesManagerProtocol
    let launchAtLoginService: LaunchAtLoginServiceProtocol
    var historicalDataService: (any HistoricalDataServiceProtocol)?
    var onThresholdChange: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onSignIn: (() -> Void)?
    var onSignOut: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            switch appState.oauthState {
            case .unauthenticated:
                unauthenticatedView
            case .authorizing:
                authorizingView
            case .authenticated:
                authenticatedView
            }
        }
        .frame(minWidth: 200)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude usage details")
    }

    // MARK: - Auth State Views

    @ViewBuilder
    private var unauthenticatedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("Sign in to Anthropic")
                .font(.headline)

            Text("One-click sign-in via your browser. No API keys needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { onSignIn?() }) {
                Text("Sign In")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding()

        if let update = appState.availableUpdate {
            Divider()
            UpdateBadgeView(update: update) {
                preferencesManager.dismissedVersion = update.version
                appState.updateAvailableUpdate(nil)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }

        Divider()

        HStack {
            Spacer()
            GearMenuView(preferencesManager: preferencesManager, launchAtLoginService: launchAtLoginService, historicalDataService: historicalDataService, appState: appState, onThresholdChange: onThresholdChange, onClearHistory: onClearHistory, onSignOut: onSignOut)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var authorizingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            Text("Waiting for browser auth...")
                .font(.headline)

            Text("Complete sign-in in your browser, then return here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()

        Divider()

        HStack {
            Spacer()
            GearMenuView(preferencesManager: preferencesManager, launchAtLoginService: launchAtLoginService, historicalDataService: historicalDataService, appState: appState, onThresholdChange: onThresholdChange, onClearHistory: onClearHistory, onSignOut: onSignOut)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var authenticatedView: some View {
        FiveHourGaugeSection(appState: appState)
            .padding(.horizontal)
            .padding(.vertical, 8)

        // 7-day gauge section (hidden entirely when sevenDay is nil per AC #6)
        if appState.sevenDay != nil {
            Divider()

            SevenDayGaugeSection(appState: appState)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }

        // Extra usage card (Story 17.2): spend/limit/utilization with color-coded progress bar
        if appState.extraUsageEnabled {
            Divider()
            ExtraUsageCardView(appState: appState, preferencesManager: preferencesManager)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }

        // Sparkline section (Story 12.4): 24h usage trend visualization
        Divider()
        Sparkline(
            data: appState.sparklineData,
            pollInterval: preferencesManager.pollInterval,
            onTap: { AnalyticsWindow.shared.toggle() },
            isAnalyticsOpen: appState.isAnalyticsWindowOpen
        )
        .padding(.horizontal)
        .padding(.vertical, 8)

        if let statusMessage = resolvedStatusMessage {
            Divider()
            StatusMessageView(title: statusMessage.title, detail: statusMessage.detail)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }

        if let update = appState.availableUpdate {
            Divider()
            UpdateBadgeView(update: update) {
                preferencesManager.dismissedVersion = update.version
                appState.updateAvailableUpdate(nil)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }

        Divider()

        PopoverFooterView(appState: appState, preferencesManager: preferencesManager, launchAtLoginService: launchAtLoginService, historicalDataService: historicalDataService, onThresholdChange: onThresholdChange, onClearHistory: onClearHistory, onSignOut: onSignOut)
            .padding(.horizontal)
            .padding(.vertical, 8)
    }

    /// Resolves which status message (if any) to display based on current AppState.
    private var resolvedStatusMessage: StatusMessage? {
        // Access countdownTick to register observation for periodic refresh
        let _ = appState.countdownTick

        switch appState.connectionStatus {
        case .disconnected:
            // Note: lastUpdated tracks last *successful* fetch, not last poll attempt.
            // AC #1 specifies "Last attempt: Xs ago" wording; this is the best proxy available.
            let detail: String
            if let lastUpdated = appState.lastUpdated {
                let elapsed = Int(max(0, Date().timeIntervalSince(lastUpdated)))
                detail = elapsed < 60 ? "Last attempt: \(elapsed)s ago" : "Last attempt: \(elapsed / 60)m ago"
            } else {
                detail = "Attempting to connect..."
            }
            return StatusMessage(title: "Unable to reach Claude API", detail: detail)
        case .tokenExpired:
            return StatusMessage(title: "Session expired", detail: "Sign in again to continue")
        case .noCredentials:
            return StatusMessage(title: "Not signed in", detail: "Click Sign In to authenticate")
        case .connected:
            if appState.dataFreshness == .veryStale, let lastUpdated = appState.lastUpdated {
                let elapsed = Int(max(0, Date().timeIntervalSince(lastUpdated)))
                return StatusMessage(title: "Data may be outdated", detail: "Last updated: \(elapsed / 60)m ago")
            }
            return nil
        }
    }
}
