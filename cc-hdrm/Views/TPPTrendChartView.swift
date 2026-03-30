import Charts
import SwiftUI

/// Swift Charts view rendering TPP trend data with two-tier visualization.
///
/// Renders:
/// - Passive points as scatter dots
/// - Benchmark points as diamond markers (accent color)
/// - Smoothed trend line (monotone interpolation, separate series)
/// - Shift annotations as vertical rule marks
/// - Hover cursor with vertical line and value tooltip
struct TPPTrendChartView: View {
    let chartData: TPPChartData
    let showPassive: Bool
    let showBenchmark: Bool
    let showTrend: Bool
    var timeRange: TimeRange = .day

    @State private var hoveredDate: Date?

    /// X-axis domain matching the usage chart's time range.
    private var xDomain: ClosedRange<Date> {
        let now = Date()
        let start = Date(timeIntervalSince1970: Double(timeRange.startTimestamp) / 1000.0)
        return start...now
    }

    /// X-axis label format matched to the selected time range.
    private var xAxisFormat: Date.FormatStyle {
        switch timeRange {
        case .day:
            return .dateTime.hour()
        case .week:
            return .dateTime.weekday(.abbreviated).hour()
        case .month:
            return .dateTime.month(.abbreviated).day()
        case .all:
            return .dateTime.month(.abbreviated).day()
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)

            if chartData.isEmpty {
                emptyState
            } else {
                chartContent
                    .padding(12)
            }
        }
        .frame(minHeight: 180)
    }

    // MARK: - Chart Content

    @ViewBuilder
    private var chartContent: some View {
        Chart {
            // Passive data points (scatter dots)
            if showPassive {
                ForEach(chartData.passivePoints) { point in
                    PointMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Passive", point.tppValue)
                    )
                    .foregroundStyle(Color.secondary.opacity(opacityForConfidence(point.confidence, base: 0.7)))
                    .symbol(.circle)
                    .symbolSize(50)
                }
            }

            // Benchmark points (diamond, accent color)
            if showBenchmark {
                ForEach(chartData.benchmarkPoints) { point in
                    PointMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Benchmark", point.tppValue)
                    )
                    .foregroundStyle(Color.accentColor.opacity(opacityForConfidence(point.confidence, base: 1.0)))
                    .symbol(.diamond)
                    .symbolSize(70)
                }
            }

            // Trend line — monotone interpolation prevents non-monotonic X artifacts
            if showTrend && !chartData.trendLine.isEmpty {
                ForEach(chartData.trendLine) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Trend", point.tppValue),
                        series: .value("Series", "trend")
                    )
                    .foregroundStyle(Color.orange.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                }
            }

            // Shift annotations as vertical rule marks
            ForEach(chartData.shiftAnnotations) { annotation in
                RuleMark(x: .value("Shift", annotation.date))
                    .foregroundStyle(annotation.direction == .down ? Color.red.opacity(0.5) : Color.green.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(annotation.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(2)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                            .cornerRadius(3)
                    }
            }

            // Hover cursor vertical line
            if let date = hoveredDate {
                RuleMark(x: .value("Cursor", date))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: xDomain)
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: xAxisFormat)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartYAxisLabel("tokens/%", position: .trailing)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let date: Date = proxy.value(atX: location.x),
                                  date <= Date() else {
                                hoveredDate = nil
                                return
                            }
                            hoveredDate = date
                        case .ended:
                            hoveredDate = nil
                        }
                    }

                // Tooltip
                if let date = hoveredDate {
                    hoverTooltip(date: date, proxy: proxy, size: geometry.size)
                }
            }
        }
    }

    // MARK: - Hover Tooltip

    /// Find the nearest trend line point to a given date.
    private func findNearestTrendPoint(to date: Date) -> TPPChartPoint? {
        guard !chartData.trendLine.isEmpty else { return nil }
        var best: TPPChartPoint?
        var bestDistance: TimeInterval = .greatestFiniteMagnitude
        for point in chartData.trendLine {
            let distance = abs(point.timestamp.timeIntervalSince(date))
            if distance < bestDistance {
                bestDistance = distance
                best = point
            }
        }
        return best
    }

    @ViewBuilder
    private func hoverTooltip(date: Date, proxy: ChartProxy, size: CGSize) -> some View {
        let nearest = findNearestPoint(to: date)
        let nearestTrend = showTrend ? findNearestTrendPoint(to: date) : nil
        if (nearest != nil || nearestTrend != nil), let xPos = proxy.position(forX: date) {
            let tooltipX = xPos < size.width / 2
                ? xPos + 10
                : xPos - 10

            VStack(alignment: .leading, spacing: 2) {
                Text(date, format: .dateTime.hour().minute())
                    .font(.caption2.bold())

                if let point = nearest {
                    HStack(spacing: 4) {
                        Circle().fill(Color.secondary).frame(width: 6, height: 6)
                        Text("\(point.source == .benchmark ? "Benchmark" : "Passive"): \(formatTPP(point.tppValue))")
                            .font(.caption2)
                    }
                }

                if let trend = nearestTrend {
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                        Text("Trend: \(formatTPP(trend.tppValue))")
                            .font(.caption2)
                    }
                }
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
            .cornerRadius(4)
            .position(
                x: tooltipX,
                y: 30
            )
            .allowsHitTesting(false)
        }
    }

    /// Find the nearest passive or benchmark point to a given date.
    private func findNearestPoint(to date: Date) -> TPPChartPoint? {
        let allPoints = (showPassive ? chartData.passivePoints : [])
            + (showBenchmark ? chartData.benchmarkPoints : [])
        guard !allPoints.isEmpty else { return nil }

        let maxDistance: TimeInterval = {
            switch timeRange {
            case .day: return 600    // 10 min
            case .week: return 3600  // 1 hour
            case .month: return 86400 // 1 day
            case .all: return 604800  // 1 week
            }
        }()

        var best: TPPChartPoint?
        var bestDistance: TimeInterval = .greatestFiniteMagnitude

        for point in allPoints {
            let distance = abs(point.timestamp.timeIntervalSince(date))
            if distance < bestDistance {
                bestDistance = distance
                best = point
            }
        }

        return bestDistance <= maxDistance ? best : nil
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("No TPP data for this time range")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    /// Returns opacity adjusted for measurement confidence level.
    private func opacityForConfidence(_ confidence: MeasurementConfidence, base: Double) -> Double {
        switch confidence {
        case .high: return base
        case .medium: return base * 0.7
        case .low: return base * 0.5
        }
    }

    private func formatTPP(_ tpp: Double) -> String {
        if tpp >= 1_000_000 {
            return String(format: "%.1fM", tpp / 1_000_000)
        } else if tpp >= 1000 {
            return String(format: "%.0fK", tpp / 1000)
        } else {
            return String(format: "%.0f", tpp)
        }
    }
}
