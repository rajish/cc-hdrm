import Charts
import SwiftUI

/// Bar chart for 7d/30d/All time ranges showing peak utilization per period.
///
/// Performance design mirrors `StepAreaChartView`: static chart content is separated
/// from hover overlay so hover state changes only redraw the tooltip, not the chart marks.
struct BarChartView: View {
    let fiveHourVisible: Bool
    let sevenDayVisible: Bool
    let timeRange: TimeRange

    /// Pre-computed bar points — built in init, never recomputed on hover.
    let barPoints: [BarPoint]

    /// 7-day series color — reuses StepAreaChartView constant.
    static let sevenDayColor = StepAreaChartView.sevenDayColor

    // MARK: - Data Types

    struct BarPoint: Identifiable {
        /// Stable identity derived from periodStart — survives data reloads for the same period.
        let id: Int
        let periodStart: Date
        let periodEnd: Date
        let midpoint: Date
        let fiveHourPeak: Double?
        let sevenDayPeak: Double?
        let fiveHourAvg: Double?
        let sevenDayAvg: Double?
        let fiveHourMin: Double?
        let sevenDayMin: Double?
        let resetCount: Int
    }

    // MARK: - Init

    init(rollups: [UsageRollup], timeRange: TimeRange, fiveHourVisible: Bool, sevenDayVisible: Bool) {
        self.timeRange = timeRange
        self.fiveHourVisible = fiveHourVisible
        self.sevenDayVisible = sevenDayVisible
        self.barPoints = Self.makeBarPoints(from: rollups, timeRange: timeRange)
    }

    // MARK: - Body

    var body: some View {
        BarChartWithHoverOverlay(
            barPoints: barPoints,
            timeRange: timeRange,
            fiveHourVisible: fiveHourVisible,
            sevenDayVisible: sevenDayVisible
        )
        .accessibilityLabel("\(timeRange.displayLabel) bar usage chart")
    }

    // MARK: - Data Transformation

    /// Groups rollup data into bar points at the appropriate resolution for the time range.
    ///
    /// - `.week`: aggregates into hourly bars
    /// - `.month`, `.all`: aggregates into daily bars
    static func makeBarPoints(from rollups: [UsageRollup], timeRange: TimeRange) -> [BarPoint] {
        guard !rollups.isEmpty else { return [] }

        let calendar = Calendar.current

        // Group rollups by target period
        let grouped: [Date: [UsageRollup]]
        switch timeRange {
        case .week:
            // Group by hour
            grouped = Dictionary(grouping: rollups) { rollup in
                let date = Date(timeIntervalSince1970: Double(rollup.periodStart) / 1000.0)
                return calendar.dateInterval(of: .hour, for: date)?.start ?? date
            }
        case .month, .all:
            // Group by day
            grouped = Dictionary(grouping: rollups) { rollup in
                let date = Date(timeIntervalSince1970: Double(rollup.periodStart) / 1000.0)
                return calendar.startOfDay(for: date)
            }
        case .day:
            // Should not be called for .day — return empty
            return []
        }

        // Convert each group into a BarPoint
        let sortedKeys = grouped.keys.sorted()
        return sortedKeys.compactMap { periodStart in
            guard let rollups = grouped[periodStart] else { return nil }

            let periodEnd: Date
            switch timeRange {
            case .week:
                periodEnd = calendar.date(byAdding: .hour, value: 1, to: periodStart) ?? periodStart
            case .month, .all:
                periodEnd = calendar.date(byAdding: .day, value: 1, to: periodStart) ?? periodStart
            case .day:
                return nil
            }

            let midpoint = Date(
                timeIntervalSince1970: (periodStart.timeIntervalSince1970 + periodEnd.timeIntervalSince1970) / 2.0
            )

            // Aggregate: max for peak, min for min, weighted average for avg, sum for resets
            let fiveHourPeaks = rollups.compactMap(\.fiveHourPeak)
            let sevenDayPeaks = rollups.compactMap(\.sevenDayPeak)
            let fiveHourAvgs = rollups.compactMap(\.fiveHourAvg)
            let sevenDayAvgs = rollups.compactMap(\.sevenDayAvg)
            let fiveHourMins = rollups.compactMap(\.fiveHourMin)
            let sevenDayMins = rollups.compactMap(\.sevenDayMin)
            let totalResets = rollups.reduce(0) { $0 + $1.resetCount }

            return BarPoint(
                id: Int(periodStart.timeIntervalSince1970),
                periodStart: periodStart,
                periodEnd: periodEnd,
                midpoint: midpoint,
                fiveHourPeak: fiveHourPeaks.isEmpty ? nil : fiveHourPeaks.max(),
                sevenDayPeak: sevenDayPeaks.isEmpty ? nil : sevenDayPeaks.max(),
                fiveHourAvg: fiveHourAvgs.isEmpty ? nil : fiveHourAvgs.reduce(0, +) / Double(fiveHourAvgs.count),
                sevenDayAvg: sevenDayAvgs.isEmpty ? nil : sevenDayAvgs.reduce(0, +) / Double(sevenDayAvgs.count),
                fiveHourMin: fiveHourMins.isEmpty ? nil : fiveHourMins.min(),
                sevenDayMin: sevenDayMins.isEmpty ? nil : sevenDayMins.min(),
                resetCount: totalResets
            )
        }
    }
}

// MARK: - Chart With Hover Overlay (manages hover state separately from chart content)

/// Wrapper that puts the static bar chart and the hover overlay together.
/// Hover state changes only affect the overlay, not the chart marks.
private struct BarChartWithHoverOverlay: View {
    let barPoints: [BarChartView.BarPoint]
    let timeRange: TimeRange
    let fiveHourVisible: Bool
    let sevenDayVisible: Bool

    @State private var hoveredIndex: Int?

    var body: some View {
        StaticBarChartContent(
            barPoints: barPoints,
            timeRange: timeRange,
            fiveHourVisible: fiveHourVisible,
            sevenDayVisible: sevenDayVisible
        )
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let date: Date = proxy.value(atX: location.x) else {
                                    hoveredIndex = nil
                                    return
                                }
                                hoveredIndex = findNearestIndex(to: date)
                            case .ended:
                                hoveredIndex = nil
                            }
                        }

                    BarHoverOverlayContent(
                        barPoints: barPoints,
                        hoveredIndex: hoveredIndex,
                        timeRange: timeRange,
                        fiveHourVisible: fiveHourVisible,
                        sevenDayVisible: sevenDayVisible,
                        proxy: proxy,
                        size: geometry.size
                    )
                    .allowsHitTesting(false)
                }
            }
        }
    }

    /// Binary search for nearest bar point by date (O(log n)).
    private func findNearestIndex(to date: Date) -> Int? {
        guard !barPoints.isEmpty else { return nil }

        var low = 0
        var high = barPoints.count - 1

        while low < high {
            let mid = (low + high) / 2
            if barPoints[mid].midpoint < date {
                low = mid + 1
            } else {
                high = mid
            }
        }

        // Check neighbors to find actual nearest
        let candidates = [low - 1, low, low + 1].filter { $0 >= 0 && $0 < barPoints.count }
        var bestIndex = low
        var bestDistance = abs(barPoints[low].midpoint.timeIntervalSince(date))

        for i in candidates {
            let distance = abs(barPoints[i].midpoint.timeIntervalSince(date))
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = i
            }
        }

        return bestIndex
    }
}

// MARK: - Static Bar Chart Content (NEVER re-evaluates on hover)

/// The actual Chart marks. This view only depends on the data arrays and visibility flags,
/// NOT on hover state. When hoveredIndex changes, this view is not invalidated.
private struct StaticBarChartContent: View {
    let barPoints: [BarChartView.BarPoint]
    let timeRange: TimeRange
    let fiveHourVisible: Bool
    let sevenDayVisible: Bool

    /// Whether both series are visible (determines grouped vs single bar mode).
    private var bothVisible: Bool {
        fiveHourVisible && sevenDayVisible
    }

    private enum Series {
        case fiveHour, sevenDay
    }

    /// Computes the x-axis start/end dates for a bar, handling grouped vs single mode.
    ///
    /// - Single series: bar spans 90% of the period (5% padding on each side).
    /// - Both series: period split in half with a 4% gap between the two halves.
    private func barBounds(for point: BarChartView.BarPoint, series: Series) -> (start: Date, end: Date) {
        let duration = point.periodEnd.timeIntervalSince(point.periodStart)
        let outerPadding = duration * 0.05

        if bothVisible {
            let halfDuration = duration * 0.5
            let innerGap = duration * 0.02
            switch series {
            case .fiveHour:
                let start = point.periodStart.addingTimeInterval(outerPadding)
                let end = point.periodStart.addingTimeInterval(halfDuration - innerGap)
                return (start, end)
            case .sevenDay:
                let start = point.periodStart.addingTimeInterval(halfDuration + innerGap)
                let end = point.periodEnd.addingTimeInterval(-outerPadding)
                return (start, end)
            }
        } else {
            let start = point.periodStart.addingTimeInterval(outerPadding)
            let end = point.periodEnd.addingTimeInterval(-outerPadding)
            return (start, end)
        }
    }

    var body: some View {
        Chart {
            // 5h series bars (green) — uses RectangleMark for explicit temporal boundaries
            if fiveHourVisible {
                ForEach(barPoints) { point in
                    if let peak = point.fiveHourPeak {
                        let bounds = barBounds(for: point, series: .fiveHour)
                        RectangleMark(
                            xStart: .value("Start", bounds.start),
                            xEnd: .value("End", bounds.end),
                            yStart: .value("Bottom", 0),
                            yEnd: .value("Peak", peak)
                        )
                        .foregroundStyle(Color.headroomNormal)
                    }
                }
            }

            // 7d series bars (blue)
            if sevenDayVisible {
                ForEach(barPoints) { point in
                    if let peak = point.sevenDayPeak {
                        let bounds = barBounds(for: point, series: .sevenDay)
                        RectangleMark(
                            xStart: .value("Start", bounds.start),
                            xEnd: .value("End", bounds.end),
                            yStart: .value("Bottom", 0),
                            yEnd: .value("Peak", peak)
                        )
                        .foregroundStyle(BarChartView.sevenDayColor)
                    }
                }
            }

            // Reset indicators — small orange point at baseline
            ForEach(barPoints) { point in
                if point.resetCount > 0 {
                    PointMark(
                        x: .value("Period", point.midpoint),
                        y: .value("Reset", 0)
                    )
                    .symbolSize(20)
                    .foregroundStyle(Color.orange.opacity(0.5))
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.secondary.opacity(0.3))
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("\(intValue)%")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            switch timeRange {
            case .week:
                AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated).hour())
                }
            case .month:
                AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            case .all:
                AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            case .day:
                // Should not be used with bar chart
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
        }
    }
}

// MARK: - Hover Overlay Content (lightweight, redraws on hover)

/// The hover visuals: vertical line, tooltip.
/// This is the only thing that redraws when hoveredIndex changes.
private struct BarHoverOverlayContent: View {
    let barPoints: [BarChartView.BarPoint]
    let hoveredIndex: Int?
    let timeRange: TimeRange
    let fiveHourVisible: Bool
    let sevenDayVisible: Bool
    let proxy: ChartProxy
    let size: CGSize

    var body: some View {
        if let index = hoveredIndex, index < barPoints.count {
            let point = barPoints[index]

            if let xPos = proxy.position(forX: point.midpoint) {
                // Vertical hover line
                Path { path in
                    path.move(to: CGPoint(x: xPos, y: 0))
                    path.addLine(to: CGPoint(x: xPos, y: size.height))
                }
                .stroke(Color.white.opacity(0.6), lineWidth: 1)

                // Tooltip
                tooltipView(for: point)
                    .fixedSize()
                    .position(
                        x: tooltipXPosition(chartX: xPos),
                        y: 55
                    )
            }
        }
    }

    @ViewBuilder
    private func tooltipView(for point: BarChartView.BarPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Period range header
            Text(periodRangeText(for: point))
                .font(.caption)
                .fontWeight(.medium)

            // 5h series stats
            if fiveHourVisible, let peak = point.fiveHourPeak {
                HStack(spacing: 3) {
                    Circle().fill(Color.headroomNormal).frame(width: 6, height: 6)
                    Text(seriesText(label: "5h", peak: peak, avg: point.fiveHourAvg))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 7d series stats
            if sevenDayVisible, let peak = point.sevenDayPeak {
                HStack(spacing: 3) {
                    Circle().fill(BarChartView.sevenDayColor).frame(width: 6, height: 6)
                    Text(seriesText(label: "7d", peak: peak, avg: point.sevenDayAvg))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Min value (lowest across visible series)
            let minValue = computeMinValue(for: point)
            if let minVal = minValue {
                Text(String(format: "Min: %.1f%%", minVal))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Reset indicator
            if point.resetCount > 0 {
                Text("\(point.resetCount) reset\(point.resetCount > 1 ? "s" : "")")
                    .font(.caption2)
                    .foregroundStyle(Color.orange)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    /// Cached date formatters — `DateFormatter` allocation is expensive, avoid per-frame creation.
    private static let hourlyStartFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h a"
        return f
    }()
    private static let hourlyEndFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f
    }()
    private static let dailyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private func periodRangeText(for point: BarChartView.BarPoint) -> String {
        switch timeRange {
        case .week:
            // Hourly bars: "Mon 2 PM - 3 PM"
            let start = Self.hourlyStartFormatter.string(from: point.periodStart)
            let end = Self.hourlyEndFormatter.string(from: point.periodEnd)
            return "\(start) - \(end)"
        case .month, .all:
            // Daily bars: "Mon, Jan 15"
            return Self.dailyFormatter.string(from: point.periodStart)
        case .day:
            return ""
        }
    }

    private func seriesText(label: String, peak: Double, avg: Double?) -> String {
        if let avg = avg {
            return String(format: "%@: Peak %.1f%% | Avg %.1f%%", label, peak, avg)
        }
        return String(format: "%@: Peak %.1f%%", label, peak)
    }

    private func computeMinValue(for point: BarChartView.BarPoint) -> Double? {
        var mins: [Double] = []
        if fiveHourVisible, let min = point.fiveHourMin {
            mins.append(min)
        }
        if sevenDayVisible, let min = point.sevenDayMin {
            mins.append(min)
        }
        return mins.min()
    }

    private func tooltipXPosition(chartX: CGFloat) -> CGFloat {
        let offset: CGFloat = 70
        if chartX > size.width - 160 {
            return chartX - offset
        }
        return chartX + offset
    }
}
