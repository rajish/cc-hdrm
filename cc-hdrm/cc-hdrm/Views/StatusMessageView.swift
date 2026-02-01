import SwiftUI

/// A reusable status message component displaying a title and detail text.
/// Pure presentational view — takes simple strings, no AppState dependency.
struct StatusMessageView: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }
}
