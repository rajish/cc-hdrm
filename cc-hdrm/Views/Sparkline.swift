import AppKit
import SwiftUI

// MARK: - SparklinePathBuilder

/// Builds path segments for sparkline rendering. Contains pure functions for testability.
struct SparklinePathBuilder {

    /// A segment of the sparkline path.
    struct PathSegment {
        /// Coordinate points for this segment (x, y in view coordinates).
        let points: [(x: CGFloat, y: CGFloat)]
        /// Whether this segment represents a data gap (no interpolation).
        let isGap: Bool
    }

    /// Builds path segments from poll data for rendering.
    /// - Parameters:
    ///   - polls: Poll data sorted by timestamp ascending
    ///   - size: The drawing area size
    ///   - gapThresholdMs: Gap detection threshold in milliseconds
    /// - Returns: Array of path segments (gaps and data segments)
    static func buildSegments(
        from polls: [UsagePoll],
        size: CGSize,
        gapThresholdMs: Int64
    ) -> [PathSegment] {
        // Filter to valid polls only (fiveHourUtil not nil, in range 0-100)
        let validPolls = polls.filter { poll in
            guard let util = poll.fiveHourUtil else { return false }
            return util >= 0 && util <= 100
        }

        guard validPolls.count >= 2 else { return [] }

        // Determine time range from valid poll data bounds
        guard let firstTimestamp = validPolls.first?.timestamp,
              let lastTimestamp = validPolls.last?.timestamp,
              lastTimestamp > firstTimestamp else {
            return []
        }

        let timeRange = firstTimestamp...lastTimestamp
        var segments: [PathSegment] = []
        var currentSegmentPoints: [(x: CGFloat, y: CGFloat)] = []
        var previousPoll: UsagePoll?

        for poll in validPolls {
            // Skip if we can't get the utilization (should not happen after filter, but defensive)
            guard let currentUtil = poll.fiveHourUtil else { continue }

            let x = xPosition(for: poll.timestamp, in: size, timeRange: timeRange)
            let y = yPosition(for: currentUtil, in: size)

            if let prev = previousPoll {
                let timeDelta = poll.timestamp - prev.timestamp

                // Check for gap
                if timeDelta > gapThresholdMs {
                    // End current segment if it has points
                    if !currentSegmentPoints.isEmpty {
                        segments.append(PathSegment(points: currentSegmentPoints, isGap: false))
                    }

                    // Add gap segment
                    let gapStartX = xPosition(for: prev.timestamp, in: size, timeRange: timeRange)
                    let gapEndX = x
                    segments.append(PathSegment(
                        points: [(x: gapStartX, y: size.height), (x: gapEndX, y: size.height)],
                        isGap: true
                    ))

                    // Start new segment
                    currentSegmentPoints = [(x: x, y: y)]
                } else if isResetBoundary(from: prev, to: poll) {
                    // Reset boundary: drop to baseline then start fresh
                    if let prevUtil = prev.fiveHourUtil {
                        let prevY = yPosition(for: prevUtil, in: size)
                        // Add horizontal line to current timestamp at previous util
                        currentSegmentPoints.append((x: x, y: prevY))
                        // Drop to baseline
                        currentSegmentPoints.append((x: x, y: size.height))
                    }
                    // End this segment
                    if !currentSegmentPoints.isEmpty {
                        segments.append(PathSegment(points: currentSegmentPoints, isGap: false))
                    }
                    // Start new segment from baseline
                    currentSegmentPoints = [(x: x, y: size.height), (x: x, y: y)]
                } else {
                    // Normal step: horizontal then vertical (step-area pattern)
                    if let prevUtil = prev.fiveHourUtil {
                        let prevY = yPosition(for: prevUtil, in: size)
                        // Horizontal line from previous point to current timestamp at previous util level
                        currentSegmentPoints.append((x: x, y: prevY))
                    }
                    // Vertical step to current util level
                    currentSegmentPoints.append((x: x, y: y))
                }
            } else {
                // First valid point
                currentSegmentPoints.append((x: x, y: y))
            }

            previousPoll = poll
        }

        // Add final segment if any points remain
        if !currentSegmentPoints.isEmpty {
            segments.append(PathSegment(points: currentSegmentPoints, isGap: false))
        }

        return segments
    }

    /// Calculates the X position for a timestamp within the drawing area.
    /// - Parameters:
    ///   - timestamp: Unix timestamp in milliseconds
    ///   - size: Drawing area size
    ///   - timeRange: The time range represented by the sparkline
    /// - Returns: X coordinate in view space
    static func xPosition(for timestamp: Int64, in size: CGSize, timeRange: ClosedRange<Int64>) -> CGFloat {
        let duration = Double(timeRange.upperBound - timeRange.lowerBound)
        guard duration > 0 else { return 0 }
        let offset = Double(timestamp - timeRange.lowerBound)
        return CGFloat(offset / duration) * size.width
    }

    /// Calculates the Y position for a utilization value within the drawing area.
    /// Y=0 is top (100% util), Y=height is bottom (0% util).
    /// - Parameters:
    ///   - utilization: Utilization percentage (0-100)
    ///   - size: Drawing area size
    /// - Returns: Y coordinate in view space
    static func yPosition(for utilization: Double, in size: CGSize) -> CGFloat {
        // Clamp utilization to valid range
        let clamped = min(max(utilization, 0), 100)
        // Y=0 at top = 100% util; Y=height at bottom = 0% util
        return size.height * (1 - clamped / 100.0)
    }

    /// Determines if there's a reset boundary between two consecutive polls.
    /// - Parameters:
    ///   - previous: The previous poll
    ///   - current: The current poll
    /// - Returns: True if a reset occurred between the polls
    static func isResetBoundary(from previous: UsagePoll, to current: UsagePoll) -> Bool {
        // Primary detection: fiveHourResetsAt changed
        if let prevResetsAt = previous.fiveHourResetsAt,
           let currResetsAt = current.fiveHourResetsAt,
           prevResetsAt != currResetsAt {
            return true
        }

        // Fallback: >50% utilization drop indicates reset
        // Normal usage is monotonically increasing within a window
        if let prevUtil = previous.fiveHourUtil,
           let currUtil = current.fiveHourUtil,
           prevUtil - currUtil > 50.0 {
            return true
        }

        return false
    }

    /// Calculates the gap threshold based on poll interval.
    /// - Parameter pollInterval: The poll interval in seconds
    /// - Returns: Gap threshold in milliseconds (1.5x poll interval)
    static func gapThresholdMs(pollInterval: TimeInterval) -> Int64 {
        Int64(pollInterval * 1000 * 1.5)
    }
}

// MARK: - Sparkline View

/// Displays a 24-hour sparkline showing 5h utilization trends.
/// Uses a step-area chart to honor monotonically increasing utilization within windows.
struct Sparkline: View {
    /// Poll data for rendering (sorted by timestamp ascending).
    let data: [UsagePoll]
    /// Poll interval for gap detection (in seconds).
    let pollInterval: TimeInterval
    /// Callback when the sparkline is tapped (for analytics window toggle).
    var onTap: (() -> Void)?
    /// Whether the analytics window is currently open.
    var isAnalyticsOpen: Bool = false

    /// Minimum height for the sparkline.
    private static let height: CGFloat = 40
    /// Minimum width for the sparkline.
    private static let minWidth: CGFloat = 180

    /// Tracks hover state for visual feedback.
    @State private var isHovered: Bool = false

    var body: some View {
        Group {
            if data.count < 2 {
                placeholderView
            } else {
                chartView
            }
        }
        .frame(minWidth: Self.minWidth, maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height)
        .accessibilityLabel("24-hour usage chart")
        .accessibilityHint("Double-tap to open analytics")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Placeholder View

    private var placeholderView: some View {
        Text("Building history...")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chart View

    private var chartView: some View {
        Canvas { context, size in
            let gapThreshold = SparklinePathBuilder.gapThresholdMs(pollInterval: pollInterval)
            let segments = SparklinePathBuilder.buildSegments(from: data, size: size, gapThresholdMs: gapThreshold)

            for segment in segments {
                if segment.isGap {
                    // Render gap as filled region with tertiary color at 20% opacity
                    drawGapRegion(context: context, segment: segment, size: size)
                } else {
                    // Render data segment as step-area path
                    drawDataSegment(context: context, segment: segment, size: size)
                }
            }

            // Draw analytics open indicator dot if needed
            if isAnalyticsOpen {
                drawAnalyticsIndicatorDot(context: context, size: size)
            }
        }
        .background(isHovered ? Color(nsColor: .quaternarySystemFill).opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            // Ensure cursor is restored if view disappears while hovering
            if isHovered {
                NSCursor.pop()
            }
        }
    }

    // MARK: - Drawing Helpers

    private func drawDataSegment(context: GraphicsContext, segment: SparklinePathBuilder.PathSegment, size: CGSize) {
        guard segment.points.count >= 2 else { return }

        var path = Path()
        let firstPoint = segment.points[0]

        // Start at baseline below first point
        path.move(to: CGPoint(x: firstPoint.x, y: size.height))
        // Move up to first point
        path.addLine(to: CGPoint(x: firstPoint.x, y: firstPoint.y))

        // Add remaining points
        for point in segment.points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }

        // Close to baseline
        if let lastPoint = segment.points.last {
            path.addLine(to: CGPoint(x: lastPoint.x, y: size.height))
        }
        path.closeSubpath()

        // Fill with headroom normal color at 30% opacity
        context.fill(path, with: .color(Color.headroomNormal.opacity(0.3)))

        // Stroke the top edge
        var strokePath = Path()
        strokePath.move(to: CGPoint(x: firstPoint.x, y: firstPoint.y))
        for point in segment.points.dropFirst() {
            strokePath.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        context.stroke(strokePath, with: .color(Color.headroomNormal), lineWidth: 1)
    }

    private func drawGapRegion(context: GraphicsContext, segment: SparklinePathBuilder.PathSegment, size: CGSize) {
        guard segment.points.count >= 2 else { return }

        let startX = segment.points[0].x
        let endX = segment.points[1].x

        var path = Path()
        path.addRect(CGRect(x: startX, y: 0, width: endX - startX, height: size.height))

        // System tertiary fill at 20% opacity
        context.fill(path, with: .color(Color(nsColor: .tertiarySystemFill).opacity(0.2)))
    }

    private func drawAnalyticsIndicatorDot(context: GraphicsContext, size: CGSize) {
        let dotSize: CGFloat = 4
        let padding: CGFloat = 2
        let dotRect = CGRect(
            x: size.width - dotSize - padding,
            y: size.height - dotSize - padding,
            width: dotSize,
            height: dotSize
        )
        let path = Path(ellipseIn: dotRect)
        context.fill(path, with: .color(Color.accentColor))
    }
}

// MARK: - Preview Data Helpers & Previews

#if DEBUG
private enum SparklinePreviewData {
    static func makeSamplePolls() -> [UsagePoll] {
        let now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        var result: [UsagePoll] = []
        for i in 0..<24 {
            let poll = UsagePoll(
                id: Int64(i),
                timestamp: now - Int64((23 - i) * 3600000),
                fiveHourUtil: Double(i * 4),
                fiveHourResetsAt: now + 3600000,
                sevenDayUtil: nil,
                sevenDayResetsAt: nil
            )
            result.append(poll)
        }
        return result
    }

    static func makeMinimalPolls() -> [UsagePoll] {
        let now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        let poll1 = UsagePoll(id: 1, timestamp: now - 3600000, fiveHourUtil: 20.0, fiveHourResetsAt: now, sevenDayUtil: nil, sevenDayResetsAt: nil)
        let poll2 = UsagePoll(id: 2, timestamp: now, fiveHourUtil: 40.0, fiveHourResetsAt: now, sevenDayUtil: nil, sevenDayResetsAt: nil)
        return [poll1, poll2]
    }
}

#Preview("With Data") {
    Sparkline(data: SparklinePreviewData.makeSamplePolls(), pollInterval: 30)
        .frame(width: 200, height: 40)
        .padding()
}

#Preview("Placeholder - No Data") {
    Sparkline(data: [], pollInterval: 30)
        .frame(width: 200, height: 40)
        .padding()
}

#Preview("With Analytics Indicator") {
    Sparkline(data: SparklinePreviewData.makeSamplePolls(), pollInterval: 30, isAnalyticsOpen: true)
        .frame(width: 200, height: 40)
        .padding()
}

#Preview("Minimal Data") {
    Sparkline(data: SparklinePreviewData.makeMinimalPolls(), pollInterval: 30)
        .frame(width: 200, height: 40)
        .padding()
}
#endif
