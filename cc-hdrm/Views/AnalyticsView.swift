import SwiftUI

/// Placeholder view for the analytics window content.
/// Full implementation will be in Story 13.1.
struct AnalyticsView: View {
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Usage Analytics")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close analytics window")
            }
            .padding(.horizontal)
            .padding(.top)

            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Coming in Story 13.1")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Historical charts, time range selection, and headroom breakdown will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Spacer()
        }
        .frame(minWidth: 400, minHeight: 350)
    }
}

#if DEBUG
#Preview {
    AnalyticsView(onClose: {})
        .frame(width: 600, height: 500)
}
#endif
