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

    /// Pre-computed gap ranges — periods with no rollup data between first and last data point.
    let gapRanges: [BarGapRange]

    /// 7-day series color — reuses StepAreaChartView constant.
    static let sevenDayColor = StepAreaChartView.sevenDayColor

    // MARK: - Data Types

    /// A time range where no rollup data exists between the first and last data points.
    struct BarGapRange: Identifiable {
        let id: Int
        let start: Date   // Period start of first missing period
        let end: Date      // Period end of last missing period in this gap
    }

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
        /// Extra usage spend in cents for this period (nil if unavailable)
        var extraUsageSpend: Double? = nil
        /// Extra usage utilization percentage 0-100 for this period (nil if unavailable)
        var extraUsageUtilization: Double? = nil
        /// Extra usage delta: SUM of credits consumed in this period (nil if unavailable)
        var extraUsageDelta: Double? = nil
    }

    // MARK: - Init

    init(rollups: [UsageRollup], timeRange: TimeRange, fiveHourVisible: Bool, sevenDayVisible: Bool) {
        self.timeRange = timeRange
        self.fiveHourVisible = fiveHourVisible
        self.sevenDayVisible = sevenDayVisible
        let points = Self.makeBarPoints(from: rollups, timeRange: timeRange)
        self.barPoints = points
        self.gapRanges = Self.findGapRanges(in: points, timeRange: timeRange)
    }

    // MARK: - Body

    var body: some View {
        BarChartWithHoverOverlay(
            barPoints: barPoints,
            gapRanges: gapRanges,
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

            // Aggregate: max for peak, min for min, simple average for avg, sum for resets
            let fiveHourPeaks = rollups.compactMap(\.fiveHourPeak)
            let sevenDayPeaks = rollups.compactMap(\.sevenDayPeak)
            let fiveHourAvgs = rollups.compactMap(\.fiveHourAvg)
            let sevenDayAvgs = rollups.compactMap(\.sevenDayAvg)
            let fiveHourMins = rollups.compactMap(\.fiveHourMin)
            let sevenDayMins = rollups.compactMap(\.sevenDayMin)
            let totalResets = rollups.reduce(0) { $0 + $1.resetCount }

            // Extra usage: take MAX across rollups in this period
            // (cumulative within billing cycle, so max = latest/highest reading)
            let extraUsageValues = rollups.compactMap(\.extraUsageUsedCredits)
            let extraUsageSpend: Double? = extraUsageValues.isEmpty ? nil : extraUsageValues.max()
            let extraUtilValues = rollups.compactMap(\.extraUsageUtilization)
            let extraUsageUtil: Double? = extraUtilValues.isEmpty ? nil : extraUtilValues.max()

            // Extra usage delta: SUM across rollups in this period
            let deltaValues = rollups.compactMap(\.extraUsageDelta)
            let extraUsageDelta: Double? = deltaValues.isEmpty ? nil : deltaValues.reduce(0, +)

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
                resetCount: totalResets,
                extraUsageSpend: extraUsageSpend,
                extraUsageUtilization: extraUsageUtil,
                extraUsageDelta: extraUsageDelta
            )
        }
    }

    // MARK: - Gap Detection

    /// Detects missing periods in the bar point sequence and returns merged gap ranges.
    ///
    /// For `.week`: each expected period is one hour.
    /// For `.month` / `.all`: each expected period is one day.
    /// Gaps are only detected WITHIN the data range (between first and last bar point).
    /// Consecutive missing periods are merged into a single `BarGapRange` (AC 3).
    static func findGapRanges(in barPoints: [BarPoint], timeRange: TimeRange) -> [BarGapRange] {
        guard barPoints.count >= 2 else { return [] }

        let calendar = Calendar.current
        let periodComponent: Calendar.Component = timeRange == .week ? .hour : .day

        // Build set of actual period start dates
        let actualPeriods = Set(barPoints.map { $0.periodStart })

        // Walk expected periods from first to last bar point
        guard let firstStart = barPoints.first?.periodStart,
              let lastStart = barPoints.last?.periodStart else { return [] }

        var gaps: [BarGapRange] = []
        var currentDate = firstStart
        var gapStart: Date?

        while currentDate <= lastStart {
            let nextDate = calendar.date(byAdding: periodComponent, value: 1, to: currentDate) ?? currentDate

            if !actualPeriods.contains(currentDate) {
                // Missing period — start or extend gap
                if gapStart == nil {
                    gapStart = currentDate
                }
            } else {
                // Data exists — close any open gap
                if let start = gapStart {
                    gaps.append(BarGapRange(id: gaps.count, start: start, end: currentDate))
                    gapStart = nil
                }
            }

            currentDate = nextDate
        }

        // Close trailing gap (gap runs up to but not including last data point's period)
        // Note: gaps within data range only — if last period has data, gap already closed above.
        // If last period is missing, the gap extends to the end of the last missing period.
        if let start = gapStart {
            // The gap extends to the next period after the last missing one we saw
            gaps.append(BarGapRange(id: gaps.count, start: start, end: currentDate))
        }

        return gaps
    }
}

// MARK: - Chart With Hover Overlay (manages hover state separately from chart content)

/// Wrapper that puts the static bar chart and the hover overlay together.
/// Hover state changes only affect the overlay, not the chart marks.
private struct BarChartWithHoverOverlay: View {
    let barPoints: [BarChartView.BarPoint]
    let gapRanges: [BarChartView.BarGapRange]
    let timeRange: TimeRange
    let fiveHourVisible: Bool
    let sevenDayVisible: Bool

    @State private var hoveredIndex: Int?
    /// The resolved cursor date from ChartProxy — used for gap range detection.
    @State private var hoveredDate: Date?

    var body: some View {
        StaticBarChartContent(
            barPoints: barPoints,
            gapRanges: gapRanges,
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
                                    hoveredDate = nil
                                    return
                                }
                                hoveredDate = date
                                hoveredIndex = findNearestIndex(to: date)
                            case .ended:
                                hoveredIndex = nil
                                hoveredDate = nil
                            }
                        }

                    BarHoverOverlayContent(
                        barPoints: barPoints,
                        gapRanges: gapRanges,
                        hoveredIndex: hoveredIndex,
                        hoveredDate: hoveredDate,
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
    let gapRanges: [BarChartView.BarGapRange]
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

    /// Computes the x-axis domain to cover the full selected time range,
    /// not just the data range. For `.all`, falls back to data bounds or 90 days.
    private var xAxisDomain: ClosedRange<Date> {
        let now = Date()
        // Add trailing buffer (half a bar period) so the rightmost bar
        // doesn't overlap the Y-axis percentage labels on the right edge.
        let trailingBuffer: TimeInterval
        switch timeRange {
        case .day:
            trailingBuffer = 1800   // 30 min (half of 1h bar)
            return Calendar.current.date(byAdding: .day, value: -1, to: now)!...now.addingTimeInterval(trailingBuffer)
        case .week:
            trailingBuffer = 1800   // 30 min (half of 1h bar)
            return Calendar.current.date(byAdding: .day, value: -7, to: now)!...now.addingTimeInterval(trailingBuffer)
        case .month:
            trailingBuffer = 43200  // 12h (half of 1d bar)
            return Calendar.current.date(byAdding: .day, value: -30, to: now)!...now.addingTimeInterval(trailingBuffer)
        case .all:
            trailingBuffer = 43200  // 12h (half of 1d bar)
            if let earliest = barPoints.first?.periodStart {
                return earliest...now.addingTimeInterval(trailingBuffer)
            }
            return Calendar.current.date(byAdding: .day, value: -90, to: now)!...now.addingTimeInterval(trailingBuffer)
        }
    }

    var body: some View {
        Chart {
            // Layer 0: No-data gap regions (grey background) — rendered before bars so bars draw on top
            ForEach(gapRanges) { gap in
                RectangleMark(
                    xStart: .value("GapStart", gap.start),
                    xEnd: .value("GapEnd", gap.end),
                    yStart: .value("Bottom", 0),
                    yEnd: .value("Top", 100)
                )
                .foregroundStyle(Color.secondary.opacity(0.08))
            }

            // 100% reference line (Story 17.3)
            RuleMark(y: .value("Threshold", 100))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 3]))
                .accessibilityHidden(true)

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

            // Extra usage faint background — cumulative utilization band (opacity 0.15)
            // Visible for all bars where extraUsageUtilization > 0
            ForEach(barPoints) { point in
                if let util = point.extraUsageUtilization, util > 0 {
                    let capTop = 100.0 + min(util / 100.0 * 5.0, 5.0)
                    if fiveHourVisible {
                        let bounds = barBounds(for: point, series: .fiveHour)
                        RectangleMark(
                            xStart: .value("Start", bounds.start),
                            xEnd: .value("End", bounds.end),
                            yStart: .value("Bottom", 100),
                            yEnd: .value("Top", capTop)
                        )
                        .foregroundStyle(Color.extraUsageCool.opacity(0.15))
                    }
                    if sevenDayVisible {
                        let bounds = barBounds(for: point, series: .sevenDay)
                        RectangleMark(
                            xStart: .value("Start", bounds.start),
                            xEnd: .value("End", bounds.end),
                            yStart: .value("Bottom", 100),
                            yEnd: .value("Top", capTop)
                        )
                        .foregroundStyle(Color.extraUsageCool.opacity(0.15))
                    }
                }
            }

            // Extra usage prominent foreground — active drain periods (opacity 0.6)
            // Only for bars where extraUsageDelta > 0 (credits actively consumed)
            ForEach(barPoints) { point in
                if let delta = point.extraUsageDelta, delta > 0,
                   let util = point.extraUsageUtilization {
                    let capTop = 100.0 + min(util / 100.0 * 5.0, 5.0)
                    if fiveHourVisible {
                        let bounds = barBounds(for: point, series: .fiveHour)
                        RectangleMark(
                            xStart: .value("Start", bounds.start),
                            xEnd: .value("End", bounds.end),
                            yStart: .value("Bottom", 100),
                            yEnd: .value("Top", capTop)
                        )
                        .foregroundStyle(Color.extraUsageCool.opacity(0.6))
                    }
                    if sevenDayVisible {
                        let bounds = barBounds(for: point, series: .sevenDay)
                        RectangleMark(
                            xStart: .value("Start", bounds.start),
                            xEnd: .value("End", bounds.end),
                            yStart: .value("Bottom", 100),
                            yEnd: .value("Top", capTop)
                        )
                        .foregroundStyle(Color.extraUsageCool.opacity(0.6))
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
        .chartYScale(domain: 0...105)
        .chartXScale(domain: xAxisDomain)
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
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                }
            case .month, .all:
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
    let gapRanges: [BarChartView.BarGapRange]
    let hoveredIndex: Int?
    let hoveredDate: Date?
    let timeRange: TimeRange
    let fiveHourVisible: Bool
    let sevenDayVisible: Bool
    let proxy: ChartProxy
    let size: CGSize

    /// Check if the hovered date falls within a gap range (gap check comes FIRST).
    private var hoveredGap: BarChartView.BarGapRange? {
        guard let date = hoveredDate else { return nil }
        return gapRanges.first { $0.start <= date && date < $0.end }
    }

    var body: some View {
        if let date = hoveredDate, let gap = hoveredGap,
           let xPos = proxy.position(forX: date) {
            // Cursor is in a gap region — show gap tooltip with vertical line
            Path { path in
                path.move(to: CGPoint(x: xPos, y: 0))
                path.addLine(to: CGPoint(x: xPos, y: size.height))
            }
            .stroke(Color.white.opacity(0.6), lineWidth: 1)

            gapTooltipView()
                .fixedSize()
                .position(
                    x: tooltipXPosition(chartX: xPos),
                    y: 55
                )
        } else if let index = hoveredIndex, index < barPoints.count {
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
    private func gapTooltipView() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("No data")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("cc-hdrm not running")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No data, cc-hdrm not running")
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

            // Extra usage indicator (Story 17.3)
            if let spend = point.extraUsageSpend, spend > 0 {
                Text("Extra: \(AppState.formatCents(Int(spend.rounded())))")
                    .font(.caption2)
                    .foregroundStyle(Color.extraUsageCool)
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
