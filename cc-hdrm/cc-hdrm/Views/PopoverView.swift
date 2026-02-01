import SwiftUI

/// Root SwiftUI view displayed inside the NSPopover when the user clicks the menu bar item.
/// Observes `AppState` via `@Observable` — re-renders automatically when data changes (AC #5).
struct PopoverView: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Reading connectionStatus and countdownTick registers observation dependencies,
            // ensuring SwiftUI re-renders this view when AppState changes.
            let status = appState.connectionStatus
            let _ = appState.countdownTick

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

            Divider()

            Text(status == .disconnected ? "disconnected" : "footer")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
        .frame(minWidth: 200)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude usage details")
    }
}
