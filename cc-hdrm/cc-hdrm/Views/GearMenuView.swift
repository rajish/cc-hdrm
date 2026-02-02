import SwiftUI

extension Notification.Name {
    /// Posted by GearMenuView when the settings popover dismisses, so AppDelegate can close the main popover.
    static let dismissPopover = Notification.Name("cc-hdrm.dismissPopover")
}

/// Gear icon with a dropdown menu containing Settings and Quit actions (AC #1, #3, #5-#8).
/// Accepts a PreferencesManagerProtocol to pass to SettingsView.
struct GearMenuView: View {
    let preferencesManager: PreferencesManagerProtocol
    @State private var showingSettings = false

    var body: some View {
        Menu {
            Button("Settings...") {
                showingSettings = true
            }
            Divider()
            Button("Quit cc-hdrm") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Settings")
        .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
            SettingsView(preferencesManager: preferencesManager) {
                showingSettings = false
            }
            .onDisappear {
                // Close the parent NSPopover when settings dismisses for any reason
                // (Done button, Esc, or click-outside)
                NotificationCenter.default.post(name: .dismissPopover, object: nil)
            }
        }
    }
}
