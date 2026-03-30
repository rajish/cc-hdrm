import Charts
import SwiftUI

/// Swift Charts view rendering TPP trend data with two-tier visualization.
///
/// Renders:
/// - Passive points as circles with connecting lines (reduced opacity)
/// - Benchmark points as diamond markers (full opacity, accent color)
/// - Smoothed trend line (catmull-rom interpolation)
/// - Shift annotations as vertical rule marks
struct TPPTrendChartView: View {
    let chartData: TPPChartData
    let showPassive: Bool
    let showBenchmark: Bool
    let showTrend: Bool
    var timeRange: TimeRange = .day

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
            // Passive data points (dots only — connecting lines removed;
            // the trend line provides the meaningful visual continuity)
            if showPassive {
                ForEach(chartData.passivePoints) { point in
                    PointMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Passive", point.tppValue)
                    )
                    .foregroundStyle(Color.secondary.opacity(opacityForConfidence(point.confidence, base: 0.5)))
                    .symbol(.circle)
                    .symbolSize(30)
                }
            }

            // Benchmark points (diamond, full opacity, accent color)
            if showBenchmark {
                ForEach(chartData.benchmarkPoints) { point in
                    PointMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Benchmark", point.tppValue)
                    )
                    .foregroundStyle(Color.accentColor.opacity(opacityForConfidence(point.confidence, base: 1.0)))
                    .symbol(.diamond)
                    .symbolSize(50)
                }
            }

            // Trend line (smooth) — uses distinct series ID to prevent
            // Swift Charts from merging it with the passive PointMark data
            if showTrend && !chartData.trendLine.isEmpty {
                ForEach(chartData.trendLine) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Trend", point.tppValue),
                        series: .value("Series", "trend")
                    )
                    .foregroundStyle(Color.orange.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
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
}
