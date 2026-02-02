import AppKit
import SwiftUI

/// Displays a dismissable update badge with download link when a newer version is available.
/// AC #1: Badge shows "v{version} available" with download icon/link.
/// AC #4: Always shows Homebrew hint (no runtime detection).
/// AC #5: VoiceOver announces version, download action, and dismiss hint.
struct UpdateBadgeView: View {
    let update: AvailableUpdate
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.blue)
                    Text("v\(update.version) available")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                Text("or brew upgrade cc-hdrm")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(update.downloadURL)
            } label: {
                Text("Download")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss update notification")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Update available: version \(update.version). Activate to download. Double tap to dismiss.")
    }
}
