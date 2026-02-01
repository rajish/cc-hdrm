import SwiftUI

/// Gear icon with a dropdown menu containing the Quit action (AC #3, #5-#8).
/// Self-contained — no parameters required.
struct GearMenuView: View {
    var body: some View {
        Menu {
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
    }
}
