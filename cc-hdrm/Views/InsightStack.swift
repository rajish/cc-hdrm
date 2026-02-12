import SwiftUI

/// Displays up to two prioritized insights in the analytics value section.
/// Replaces ContextAwareValueSummary with priority-aware, multi-insight display.
///
/// - Primary insight: `.caption` font, `.primary` foreground
/// - Secondary insight: `.caption2` font, `.tertiary` foreground
/// - Hover tooltip shows `preciseDetail` when available
struct InsightStack: View {
    let insights: [ValueInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let primary = insights.first {
                Text(primary.text)
                    .font(.caption)
                    .foregroundStyle(primary.isQuiet ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(primary.preciseDetail ?? "")
                    .accessibilityLabel(accessibilityLabel(for: primary))

                if insights.count > 1, let secondary = insights.dropFirst().first, !secondary.isQuiet {
                    Text(secondary.text)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(secondary.preciseDetail ?? "")
                        .accessibilityLabel(accessibilityLabel(for: secondary))
                        .lineLimit(1)
                }
            } else {
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func accessibilityLabel(for insight: ValueInsight) -> String {
        if let detail = insight.preciseDetail {
            return "\(insight.text). \(detail)"
        }
        return insight.text
    }
}
