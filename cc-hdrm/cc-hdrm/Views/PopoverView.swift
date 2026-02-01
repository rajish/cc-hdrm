import SwiftUI

/// Root SwiftUI view displayed inside the NSPopover when the user clicks the menu bar item.
/// Observes `AppState` via `@Observable` — re-renders automatically when data changes (AC #5).
struct PopoverView: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Reading appState.connectionStatus registers an observation dependency,
            // ensuring SwiftUI re-renders this view when AppState changes (AC #5).
            let status = appState.connectionStatus

            Text("5h gauge")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            Text("7d gauge")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)

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
