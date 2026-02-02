import SwiftUI

/// Root SwiftUI view displayed inside the NSPopover when the user clicks the menu bar item.
/// Observes `AppState` via `@Observable` — re-renders automatically when data changes (AC #5).
struct PopoverView: View {
    let appState: AppState
    let preferencesManager: PreferencesManagerProtocol

    var body: some View {
        VStack(spacing: 0) {
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

            if let statusMessage = resolvedStatusMessage {
                Divider()
                StatusMessageView(title: statusMessage.title, detail: statusMessage.detail)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }

            Divider()

            PopoverFooterView(appState: appState, preferencesManager: preferencesManager)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
        .frame(minWidth: 200)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude usage details")
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
            return StatusMessage(title: "Token expired", detail: "Run any Claude Code command to refresh")
        case .noCredentials:
            return StatusMessage(title: "No Claude credentials found", detail: "Run Claude Code to create them")
        case .connected:
            if appState.dataFreshness == .veryStale, let lastUpdated = appState.lastUpdated {
                let elapsed = Int(max(0, Date().timeIntervalSince(lastUpdated)))
                return StatusMessage(title: "Data may be outdated", detail: "Last updated: \(elapsed / 60)m ago")
            }
            return nil
        }
    }
}
