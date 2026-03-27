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
            // Passive connecting lines
            if showPassive {
                ForEach(chartData.passivePoints) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("TPP", point.tppValue)
                    )
                    .foregroundStyle(Color.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .interpolationMethod(.linear)
                }
                .symbol(.circle)
                .symbolSize(20)

                // Passive data points
                ForEach(chartData.passivePoints) { point in
                    PointMark(
                        x: .value("Time", point.timestamp),
                        y: .value("TPP", point.tppValue)
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
                        y: .value("TPP", point.tppValue)
                    )
                    .foregroundStyle(Color.accentColor.opacity(opacityForConfidence(point.confidence, base: 1.0)))
                    .symbol(.diamond)
                    .symbolSize(50)
                }
            }

            // Trend line (smooth)
            if showTrend && !chartData.trendLine.isEmpty {
                ForEach(chartData.trendLine) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("TPP", point.tppValue)
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
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
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
