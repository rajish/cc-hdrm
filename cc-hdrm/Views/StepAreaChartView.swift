import Charts
import SwiftUI
import os

/// Step-area chart for 24h view that honors the sawtooth utilization pattern.
///
/// Performance design: The static chart content is in a separate `StaticChartContent` view
/// that does NOT depend on hover state. When `hoveredIndex` changes, only the overlay redraws —
/// the Chart marks never re-evaluate.
struct StepAreaChartView: View {
    let fiveHourVisible: Bool
    let sevenDayVisible: Bool

    // Pre-computed in init — never recomputed
    let chartPoints: [ChartPoint]
    /// Flat array of points with non-nil fiveHourUtil (segment field handles pen-up/pen-down)
    let fiveHourPoints: [ChartPoint]
    /// Flat array of points with non-nil sevenDayUtil
    let sevenDayPoints: [ChartPoint]
    let resetTimestamps: [Date]
    /// Time ranges where no data exists (gaps between segments).
    let gapRanges: [GapRange]

    /// 7-day series color — distinct blue.
    static let sevenDayColor = Color.blue

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "analytics"
    )

    // MARK: - Init

    init(polls: [UsagePoll], fiveHourVisible: Bool, sevenDayVisible: Bool) {
        self.fiveHourVisible = fiveHourVisible
        self.sevenDayVisible = sevenDayVisible

        let points = Self.makeChartPoints(from: polls)

        // Enforce monotonic utilization within segments (suppress API noise dips)
        let monotonicPoints = Self.enforceMonotonicWithinSegments(points)

        // Absorb isolated short segments (Power Nap wakes) into gaps,
        // matching the sparkline's mergeShortSegments behavior.
        let cleanedPoints = Self.absorbIsolatedSegments(monotonicPoints)

        self.chartPoints = cleanedPoints
        self.resetTimestamps = Self.findResetTimestamps(in: polls)
        self.fiveHourPoints = cleanedPoints.filter { $0.fiveHourUtil != nil }
        self.sevenDayPoints = cleanedPoints.filter { $0.sevenDayUtil != nil }
        self.gapRanges = Self.findGapRanges(in: cleanedPoints)
    }

    /// Identifies time ranges where no data exists by finding boundaries between segments.
    /// A gap is the time span between the last point of one segment and the first point
    /// of the next segment (where the segment ID differs).
    private static func findGapRanges(in points: [ChartPoint]) -> [GapRange] {
        // Only consider points that have actual data (non-nil utilization)
        let dataPoints = points.filter { $0.fiveHourUtil != nil || $0.sevenDayUtil != nil }
        guard dataPoints.count >= 2 else { return [] }

        var gaps: [GapRange] = []
        var lastSegment = dataPoints[0].segment
        var lastDate = dataPoints[0].date

        for point in dataPoints {
            if point.segment != lastSegment {
                // Segment changed — the time between lastDate and point.date is a gap
                gaps.append(GapRange(id: gaps.count, start: lastDate, end: point.date))
                lastSegment = point.segment
            }
            lastDate = point.date
        }

        return gaps
    }

    /// Converts isolated short data segments into gaps by setting utilization to nil.
    ///
    /// Mirrors `SparklinePathBuilder.mergeShortSegments`: if a segment has fewer than
    /// `minimumSegmentDurationMs` of data and is sandwiched between two gaps, its points
    /// are excluded from rendering.
    private static func absorbIsolatedSegments(_ points: [ChartPoint]) -> [ChartPoint] {
        guard !points.isEmpty else { return [] }

        let minDuration = SparklinePathBuilder.minimumSegmentDurationMs

        // Group points by segment
        var segmentGroups: [(segment: Int, startIndex: Int, endIndex: Int, durationMs: Int64)] = []
        var currentSeg = points[0].segment
        var startIdx = 0

        for i in 1..<points.count {
            if points[i].segment != currentSeg {
                let duration = points[i - 1].date.timeIntervalSince(points[startIdx].date)
                segmentGroups.append((segment: currentSeg, startIndex: startIdx, endIndex: i - 1,
                                      durationMs: Int64(duration * 1000)))
                currentSeg = points[i].segment
                startIdx = i
            }
        }
        // Last group
        let lastDuration = points[points.count - 1].date.timeIntervalSince(points[startIdx].date)
        segmentGroups.append((segment: currentSeg, startIndex: startIdx, endIndex: points.count - 1,
                              durationMs: Int64(lastDuration * 1000)))

        // Identify which segments to absorb: short segments sandwiched between gaps.
        // A "gap" here means the segment boundary came from a time gap in the data.
        // Since segments are numbered sequentially (0, 1, 2...), a gap exists between
        // segmentGroups[i] and segmentGroups[i+1] (that's why they're different segments).
        var segmentsToAbsorb: Set<Int> = []
        for i in 0..<segmentGroups.count {
            let group = segmentGroups[i]
            if group.durationMs < minDuration {
                let prevIsGap = i > 0  // gap before (different segment number means time gap)
                let nextIsGap = i < segmentGroups.count - 1
                if prevIsGap && nextIsGap {
                    segmentsToAbsorb.insert(group.segment)
                }
            }
        }

        guard !segmentsToAbsorb.isEmpty else { return points }

        // Null out utilization for absorbed segments (effectively removing them from rendering)
        return points.map { point in
            if segmentsToAbsorb.contains(point.segment) {
                return ChartPoint(
                    id: point.id,
                    date: point.date,
                    fiveHourUtil: nil,
                    sevenDayUtil: nil,
                    slopeLevel: nil,
                    segment: point.segment,
                    extraUsageActive: nil,
                    extraUsageUsedCredits: nil
                )
            }
            return point
        }
    }

    // MARK: - Body

    var body: some View {
        ChartWithHoverOverlay(
            chartPoints: chartPoints,
            fiveHourPoints: fiveHourPoints,
            sevenDayPoints: sevenDayPoints,
            resetTimestamps: resetTimestamps,
            gapRanges: gapRanges,
            fiveHourVisible: fiveHourVisible,
            sevenDayVisible: sevenDayVisible
        )
        .accessibilityLabel("24-hour step-area usage chart")
    }

    // MARK: - Data Types

    struct ChartPoint: Identifiable {
        let id: Int
        let date: Date
        let fiveHourUtil: Double?
        let sevenDayUtil: Double?
        let slopeLevel: SlopeLevel?
        let segment: Int
        var extraUsageActive: Bool? = nil
        var extraUsageUsedCredits: Double? = nil
    }

    /// A time range where no poll data exists (sleep, system off, etc.)
    struct GapRange: Identifiable {
        let id: Int
        let start: Date
        let end: Date
    }

    // MARK: - Data Transformation

    static func makeChartPoints(from polls: [UsagePoll]) -> [ChartPoint] {
        guard !polls.isEmpty else { return [] }

        let slopes = computeSlopeAtEachPoint(polls: polls)
        let gapThreshold = SparklinePathBuilder.sparklineGapThresholdMs
        var currentSegment = 0

        return polls.enumerated().map { index, poll in
            if index > 0 {
                let timeDelta = poll.timestamp - polls[index - 1].timestamp
                if timeDelta > gapThreshold {
                    currentSegment += 1
                }
            }

            let isExtraUsageActive = poll.extraUsageEnabled == true
                && ((poll.fiveHourUtil ?? 0) >= 99.5 || (poll.sevenDayUtil ?? 0) >= 99.5)

            return ChartPoint(
                id: index,
                date: Date(timeIntervalSince1970: Double(poll.timestamp) / 1000.0),
                fiveHourUtil: poll.fiveHourUtil,
                sevenDayUtil: poll.sevenDayUtil,
                slopeLevel: slopes[index],
                segment: currentSegment,
                extraUsageActive: isExtraUsageActive,
                extraUsageUsedCredits: poll.extraUsageUsedCredits
            )
        }
    }

    /// Finds reset boundary timestamps for dashed vertical line rendering.
    ///
    /// Uses a stricter criterion than `SparklinePathBuilder.isResetBoundary`:
    /// requires an actual utilization **drop** (not just a `resetsAt` timestamp shift).
    /// The sparkline's `isResetBoundary` also fires on `resetsAt` drift (the sliding
    /// window's reset time shifts naturally every poll), which creates false positives
    /// when rendered as dashed lines on the 24h chart.
    ///
    /// Detection: 5h utilization dropped by ≥ 10 percentage points between consecutive
    /// polls. This catches real resets (typically 80% → 5%) while ignoring normal
    /// API noise (± 1-2%).
    static func findResetTimestamps(in polls: [UsagePoll]) -> [Date] {
        guard polls.count >= 2 else { return [] }

        let dropThreshold: Double = 10.0

        var resets: [Date] = []
        for i in 1..<polls.count {
            let resetDate = Date(timeIntervalSince1970: Double(polls[i].timestamp) / 1000.0)
            var detected = false

            // Check 5h utilization drop
            if let prevUtil = polls[i - 1].fiveHourUtil,
               let currUtil = polls[i].fiveHourUtil,
               prevUtil - currUtil >= dropThreshold {
                detected = true
            }

            // Check 7d utilization drop
            if !detected,
               let prevUtil = polls[i - 1].sevenDayUtil,
               let currUtil = polls[i].sevenDayUtil,
               prevUtil - currUtil >= dropThreshold {
                detected = true
            }

            if detected {
                resets.append(resetDate)
            }
        }
        return resets
    }

    static func computeSlopeAtEachPoint(polls: [UsagePoll]) -> [SlopeLevel?] {
        guard !polls.isEmpty else { return [] }

        let windowMs: Int64 = 5 * 60 * 1000

        return polls.enumerated().map { index, currentPoll in
            guard let currentUtil = currentPoll.fiveHourUtil else { return nil }

            var windowStartIndex = index
            for j in stride(from: index - 1, through: 0, by: -1) {
                if currentPoll.timestamp - polls[j].timestamp > windowMs { break }
                windowStartIndex = j
            }

            guard windowStartIndex != index,
                  let startUtil = polls[windowStartIndex].fiveHourUtil else {
                return SlopeLevel.flat
            }

            let timeDeltaMs = currentPoll.timestamp - polls[windowStartIndex].timestamp
            guard timeDeltaMs > 0 else { return SlopeLevel.flat }

            let ratePerMin = (currentUtil - startUtil) / (Double(timeDeltaMs) / 60_000.0)

            if ratePerMin > 1.5 {
                return .steep
            } else if ratePerMin > 0.3 {
                return .rising
            } else {
                return .flat
            }
        }
    }

    /// Enforces monotonically increasing utilization within each segment.
    ///
    /// The Claude API returns monotonically increasing utilization within a usage window,
    /// but small noise (±0.5%) can cause tiny dips. At sparkline scale (40px) the
    /// `utilizationNoiseThreshold` suppresses this; at analytics scale (300+px) a 1%
    /// dip is ~3px — marginally visible. This clamps any dip to the running maximum
    /// within each segment, resetting at segment boundaries and reset events.
    static func enforceMonotonicWithinSegments(_ points: [ChartPoint]) -> [ChartPoint] {
        guard !points.isEmpty else { return [] }

        let resetDropThreshold: Double = 10.0
        var maxFiveHour: Double?
        var maxSevenDay: Double?
        var currentSegment = points[0].segment

        var result: [ChartPoint] = []
        result.reserveCapacity(points.count)

        for point in points {
            // Reset tracking on segment change
            if point.segment != currentSegment {
                maxFiveHour = nil
                maxSevenDay = nil
                currentSegment = point.segment
            }

            // Reset tracking on utilization reset (large drop)
            if let util = point.fiveHourUtil, let maxF = maxFiveHour,
               maxF - util >= resetDropThreshold {
                maxFiveHour = nil
                maxSevenDay = nil
            }

            let clampedFive: Double?
            if let util = point.fiveHourUtil {
                if let maxF = maxFiveHour {
                    clampedFive = max(util, maxF)
                } else {
                    clampedFive = util
                }
                maxFiveHour = clampedFive
            } else {
                clampedFive = nil
            }

            let clampedSeven: Double?
            if let util = point.sevenDayUtil {
                if let maxS = maxSevenDay {
                    clampedSeven = max(util, maxS)
                } else {
                    clampedSeven = util
                }
                maxSevenDay = clampedSeven
            } else {
                clampedSeven = nil
            }

            if clampedFive == point.fiveHourUtil && clampedSeven == point.sevenDayUtil {
                result.append(point)
            } else {
                result.append(ChartPoint(
                    id: point.id,
                    date: point.date,
                    fiveHourUtil: clampedFive,
                    sevenDayUtil: clampedSeven,
                    slopeLevel: point.slopeLevel,
                    segment: point.segment,
                    extraUsageActive: point.extraUsageActive,
                    extraUsageUsedCredits: point.extraUsageUsedCredits
                ))
            }
        }

        return result
    }

}

// MARK: - Chart With Hover Overlay (manages hover state separately from chart content)

/// Wrapper that puts the static chart and the hover overlay together.
/// Hover state changes only affect the overlay, not the chart marks.
private struct ChartWithHoverOverlay: View {
    let chartPoints: [StepAreaChartView.ChartPoint]
    let fiveHourPoints: [StepAreaChartView.ChartPoint]
    let sevenDayPoints: [StepAreaChartView.ChartPoint]
    let resetTimestamps: [Date]
    let gapRanges: [StepAreaChartView.GapRange]
    let fiveHourVisible: Bool
    let sevenDayVisible: Bool

    @State private var hoveredIndex: Int?
    /// The resolved cursor date from ChartProxy — used for gap range detection.
    @State private var hoveredDate: Date?

    var body: some View {
        StaticChartContent(
            fiveHourPoints: fiveHourPoints,
            sevenDayPoints: sevenDayPoints,
            resetTimestamps: resetTimestamps,
            gapRanges: gapRanges,
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

                    HoverOverlayContent(
                        chartPoints: chartPoints,
                        gapRanges: gapRanges,
                        hoveredIndex: hoveredIndex,
                        hoveredDate: hoveredDate,
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

    /// Binary search for nearest point (O(log n) instead of O(n)).
    private func findNearestIndex(to date: Date) -> Int? {
        guard !chartPoints.isEmpty else { return nil }

        var low = 0
        var high = chartPoints.count - 1

        while low < high {
            let mid = (low + high) / 2
            if chartPoints[mid].date < date {
                low = mid + 1
            } else {
                high = mid
            }
        }

        // Check neighbors to find actual nearest
        let candidates = [low - 1, low, low + 1].filter { $0 >= 0 && $0 < chartPoints.count }
        var bestIndex = low
        var bestDistance = abs(chartPoints[low].date.timeIntervalSince(date))

        for i in candidates {
            let distance = abs(chartPoints[i].date.timeIntervalSince(date))
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = i
            }
        }

        return bestIndex
    }
}

// MARK: - Static Chart Content (NEVER re-evaluates on hover)

/// The actual Chart marks. This view only depends on the data arrays and visibility flags,
/// NOT on hover state. When hoveredIndex changes, this view is not invalidated.
///
/// Each point carries a `segment` field. The `series:` parameter on each mark uses
/// a unique string per (seriesName, segment) pair — this is what tells Swift Charts
/// NOT to connect points across different segments (pen-up/pen-down).
private struct StaticChartContent: View {
    let fiveHourPoints: [StepAreaChartView.ChartPoint]
    let sevenDayPoints: [StepAreaChartView.ChartPoint]
    let resetTimestamps: [Date]
    let gapRanges: [StepAreaChartView.GapRange]
    let fiveHourVisible: Bool
    let sevenDayVisible: Bool

    var body: some View {
        Chart {
            // Layer 0: No-data gap regions (grey background)
            ForEach(gapRanges) { gap in
                RectangleMark(
                    xStart: .value("Start", gap.start),
                    xEnd: .value("End", gap.end),
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

            // 5h series: area + line (green)
            // series: "5h-N" creates separate pen strokes per segment
            if fiveHourVisible {
                ForEach(fiveHourPoints) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        y: .value("Utilization", point.fiveHourUtil ?? 0),
                        series: .value("Seg", "5h-\(point.segment)")
                    )
                    .foregroundStyle(Color.headroomNormal.opacity(0.15))
                    .interpolationMethod(.stepEnd)
                }

                ForEach(fiveHourPoints) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Utilization", point.fiveHourUtil ?? 0),
                        series: .value("Seg", "5h-\(point.segment)")
                    )
                    .foregroundStyle(Color.headroomNormal)
                    .interpolationMethod(.stepEnd)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }

            // 7d series: line only (blue)
            // series: "7d-N" — separate from 5h and per-segment
            if sevenDayVisible {
                ForEach(sevenDayPoints) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Utilization", point.sevenDayUtil ?? 0),
                        series: .value("Seg", "7d-\(point.segment)")
                    )
                    .foregroundStyle(StepAreaChartView.sevenDayColor)
                    .interpolationMethod(.stepEnd)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }

            // Extra usage annotations — colored dots at y=100 where extra usage is active (Story 17.3)
            ForEach(fiveHourPoints.filter { $0.extraUsageActive == true }) { point in
                PointMark(
                    x: .value("Time", point.date),
                    y: .value("Utilization", 100)
                )
                .symbolSize(30)
                .foregroundStyle(Color.extraUsageCool.opacity(0.8))
                .accessibilityLabel("Extra usage active: \(AppState.formatCents(Int((point.extraUsageUsedCredits ?? 0).rounded()))) spent this period")
            }

            // Reset boundaries — orange so they're visually distinct from grey grid lines
            ForEach(Array(resetTimestamps.enumerated()), id: \.offset) { _, resetDate in
                RuleMark(x: .value("Reset", resetDate))
                    .foregroundStyle(Color.orange.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }
        }
        .chartYScale(domain: 0...105)
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
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.secondary.opacity(0.3))
                AxisValueLabel(format: .dateTime.hour())
            }
        }
    }
}

// MARK: - Hover Overlay Content (lightweight, redraws on hover)

/// The hover visuals: vertical line, point markers, tooltip.
/// This is the only thing that redraws when hoveredIndex changes.
private struct HoverOverlayContent: View {
    let chartPoints: [StepAreaChartView.ChartPoint]
    let gapRanges: [StepAreaChartView.GapRange]
    let hoveredIndex: Int?
    let hoveredDate: Date?
    let fiveHourVisible: Bool
    let sevenDayVisible: Bool
    let proxy: ChartProxy
    let size: CGSize

    /// Check if the actual cursor date falls within a gap range.
    /// Uses `hoveredDate` (the real cursor position) instead of the nearest chart point's date,
    /// so the gap tooltip appears correctly even when the cursor is in the second half of a gap
    /// (where the nearest point is past the gap boundary).
    private var hoveredGap: StepAreaChartView.GapRange? {
        guard let date = hoveredDate else { return nil }
        return gapRanges.first { $0.start <= date && date < $0.end }
    }

    var body: some View {
        if let date = hoveredDate, let gap = hoveredGap,
           let xPos = proxy.position(forX: date) {
            // Cursor is in a gap region — show vertical line at cursor and gap tooltip
            Path { path in
                path.move(to: CGPoint(x: xPos, y: 0))
                path.addLine(to: CGPoint(x: xPos, y: size.height))
            }
            .stroke(Color.white.opacity(0.6), lineWidth: 1)

            gapTooltipView()
                .fixedSize()
                .position(
                    x: tooltipXPosition(chartX: xPos),
                    y: 45
                )
        } else if let index = hoveredIndex, index < chartPoints.count {
            let point = chartPoints[index]

            if let xPos = proxy.position(forX: point.date) {
                // Vertical hover line
                Path { path in
                    path.move(to: CGPoint(x: xPos, y: 0))
                    path.addLine(to: CGPoint(x: xPos, y: size.height))
                }
                .stroke(Color.white.opacity(0.6), lineWidth: 1)

                // 5h point marker
                if fiveHourVisible, let util = point.fiveHourUtil,
                   let yPos = proxy.position(forY: util) {
                    Circle()
                        .fill(Color.headroomNormal)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        .frame(width: 8, height: 8)
                        .position(x: xPos, y: yPos)
                }

                // 7d point marker
                if sevenDayVisible, let util = point.sevenDayUtil,
                   let yPos = proxy.position(forY: util) {
                    Circle()
                        .fill(StepAreaChartView.sevenDayColor)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        .frame(width: 8, height: 8)
                        .position(x: xPos, y: yPos)
                }

                // Tooltip
                tooltipView(for: point)
                    .fixedSize()
                    .position(
                        x: tooltipXPosition(chartX: xPos),
                        y: 45
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
    private func tooltipView(for point: StepAreaChartView.ChartPoint) -> some View {
        let slopeText = point.slopeLevel?.rawValue.capitalized ?? "Unknown"

        VStack(alignment: .leading, spacing: 2) {
            Text(point.date, format: .dateTime.hour().minute())
                .font(.caption)
                .fontWeight(.medium)
            if fiveHourVisible, let util = point.fiveHourUtil {
                HStack(spacing: 3) {
                    Circle().fill(Color.headroomNormal).frame(width: 6, height: 6)
                    Text(String(format: "5h: %.1f%%", util))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if sevenDayVisible, let util = point.sevenDayUtil {
                HStack(spacing: 3) {
                    Circle().fill(StepAreaChartView.sevenDayColor).frame(width: 6, height: 6)
                    Text(String(format: "7d: %.1f%%", util))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(slopeText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func tooltipXPosition(chartX: CGFloat) -> CGFloat {
        let offset: CGFloat = 60
        if chartX > size.width - 130 {
            return chartX - offset
        }
        return chartX + offset
    }
}
