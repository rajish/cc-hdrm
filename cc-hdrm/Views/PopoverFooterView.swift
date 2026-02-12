import SwiftUI

/// Footer view for the popover showing subscription tier, data freshness, and gear menu (AC #1-#4).
/// Read-only observer of AppState — does not write any state.
struct PopoverFooterView: View {
    let appState: AppState
    let preferencesManager: PreferencesManagerProtocol
    let launchAtLoginService: LaunchAtLoginServiceProtocol
    var historicalDataService: (any HistoricalDataServiceProtocol)?
    var onThresholdChange: (() -> Void)?
    var onClearHistory: (() -> Void)?

    var body: some View {
        // Access countdownTick to register observation for periodic re-renders
        let _ = appState.countdownTick

        HStack {
            // Left: subscription tier (AC #1)
            Text(appState.subscriptionTier ?? "—")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            // Center: freshness timestamp (AC #2, #4)
            freshnessTimestamp

            Spacer()

            // Right: gear menu (AC #3)
            GearMenuView(preferencesManager: preferencesManager, launchAtLoginService: launchAtLoginService, historicalDataService: historicalDataService, appState: appState, onThresholdChange: onThresholdChange, onClearHistory: onClearHistory)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Freshness Computation

    @ViewBuilder
    private var freshnessTimestamp: some View {
        if appState.dataFreshness == .stale {
            Text(freshnessText)
                .font(.caption2)
                .foregroundStyle(Color.headroomWarning)
        } else {
            Text(freshnessText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var freshnessText: String {
        guard let lastUpdated = appState.lastUpdated else {
            return "—"
        }
        let elapsed = Int(max(0, Date().timeIntervalSince(lastUpdated)))
        if elapsed < 60 {
            return "Updated \(elapsed)s ago"
        } else {
            return "Updated \(elapsed / 60)m ago"
        }
    }

    private var accessibilityText: String {
        let tier = appState.subscriptionTier ?? "unknown"
        guard let lastUpdated = appState.lastUpdated else {
            return "Subscription tier \(tier)"
        }
        let elapsed = Int(max(0, Date().timeIntervalSince(lastUpdated)))
        if elapsed < 60 {
            return "Subscription tier \(tier), updated \(elapsed) seconds ago"
        } else {
            return "Subscription tier \(tier), updated \(elapsed / 60) minutes ago"
        }
    }
}
