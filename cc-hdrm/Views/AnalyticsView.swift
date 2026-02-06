import SwiftUI

/// Main content view for the analytics window.
///
/// Layout:
/// - Title bar with "Usage Analytics" and close button
/// - Controls row: TimeRangeSelector (left) + series toggles (right)
/// - Chart area placeholder (expands to fill available space)
/// - Headroom breakdown placeholder (fixed height)
struct AnalyticsView: View {
    var onClose: () -> Void

    // Default to .week — shows recent trends without overwhelming detail.
    // 24h is too narrow for first impression; 30d/All require rollup data that may be sparse early on.
    @State private var selectedTimeRange: TimeRange = .week
    @State private var fiveHourVisible: Bool = true
    @State private var sevenDayVisible: Bool = true

    var body: some View {
        VStack(spacing: 12) {
            titleBar
            controlsRow
            chartPlaceholder
            breakdownPlaceholder
            // Summary stats (Avg peak, Total waste) deferred to Story 14.3-14.5 (HeadroomBreakdownBar)
        }
        .padding()
    }

    // MARK: - Title Bar

    private var titleBar: some View {
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
    }

    // MARK: - Controls Row

    private var controlsRow: some View {
        HStack {
            TimeRangeSelector(selected: $selectedTimeRange)
            Spacer()
            seriesToggles
        }
    }

    // MARK: - Series Toggles

    private var seriesToggles: some View {
        HStack(spacing: 8) {
            seriesToggleButton(
                label: "5h",
                isActive: $fiveHourVisible,
                accessibilityPrefix: "5-hour series"
            )

            Text("|")
                .font(.caption)
                .foregroundStyle(.quaternary)

            seriesToggleButton(
                label: "7d",
                isActive: $sevenDayVisible,
                accessibilityPrefix: "7-day series"
            )
        }
    }

    private func seriesToggleButton(
        label: String,
        isActive: Binding<Bool>,
        accessibilityPrefix: String
    ) -> some View {
        Button(action: {
            isActive.wrappedValue.toggle()
        }) {
            HStack(spacing: 4) {
                Image(systemName: isActive.wrappedValue ? "circle.fill" : "circle")
                    .font(.system(size: 8))
                    .foregroundStyle(isActive.wrappedValue ? Color.accentColor : .secondary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(isActive.wrappedValue ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityPrefix), \(isActive.wrappedValue ? "enabled" : "disabled")")
        .accessibilityHint("Press to toggle")
    }

    // MARK: - Chart Placeholder

    private var chartPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)

            VStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Chart: loading...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Breakdown Placeholder

    private var breakdownPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)

            Text("Headroom breakdown")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
    }
}

#if DEBUG
#Preview {
    AnalyticsView(onClose: {})
        .frame(width: 600, height: 500)
}
#endif
