import SwiftUI
import os

/// Typed stub for the usage chart component.
///
/// Accepts real data types and interface that Stories 13.5-13.7 will flesh out.
/// Currently renders summary info (data point count, time range, series visibility state).
struct UsageChart: View {
    let pollData: [UsagePoll]
    let rollupData: [UsageRollup]
    let timeRange: TimeRange
    let fiveHourVisible: Bool
    let sevenDayVisible: Bool
    let isLoading: Bool
    /// Whether any historical data exists in the database (across all time ranges).
    /// When false and data is empty, shows "No data yet" instead of "No data for this time range".
    let hasAnyHistoricalData: Bool

    /// Total data points across both data sources.
    private var dataPointCount: Int {
        pollData.count + rollupData.count
    }

    /// Whether at least one series is toggled on.
    private var anySeriesVisible: Bool {
        fiveHourVisible || sevenDayVisible
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Usage chart")
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
        } else if !anySeriesVisible {
            noSeriesMessage
        } else if dataPointCount == 0 {
            emptyDataMessage
        } else {
            dataSummary
        }
    }

    private var noSeriesMessage: some View {
        VStack(spacing: 6) {
            Image(systemName: "eye.slash")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("Select a series to display")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyDataMessage: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(emptyDataText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyDataText: String {
        if hasAnyHistoricalData {
            return "No data for this time range"
        } else {
            return "No data yet \u{2014} usage history builds over time"
        }
    }

    private var dataSummary: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("\(dataPointCount) data points")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(timeRange.displayLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

#if DEBUG
#Preview {
    UsageChart(
        pollData: [],
        rollupData: [],
        timeRange: .week,
        fiveHourVisible: true,
        sevenDayVisible: true,
        isLoading: false,
        hasAnyHistoricalData: false
    )
    .frame(width: 500, height: 300)
}
#endif
