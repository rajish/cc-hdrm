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
        /// Number of source poll data points that contributed to this segment.
        /// Step-area rendering inflates path points (N polls → ~2N-1 points),
        /// so this tracks the actual poll count for filtering decisions.
        let pollCount: Int
        /// Time span of this segment in milliseconds (last poll timestamp - first poll timestamp).
        /// Used to filter brief wake events (Power Nap) that produce short data segments.
        let durationMs: Int64
    }

    /// Minimum utilization change (in percentage points) to render a visible step.
    /// Changes below this are API noise (floating-point jitter in the sliding window)
    /// and are suppressed — the horizontal line continues at the last rendered level.
    static let utilizationNoiseThreshold: Double = 1.0

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
        var currentSegmentPollCount = 0
        var currentSegmentStartTimestamp: Int64 = 0
        var currentSegmentLastTimestamp: Int64 = 0
        var previousPoll: UsagePoll?
        // Track the last utilization level that was actually rendered as a step.
        // Small fluctuations below the noise threshold extend the horizontal line
        // at this level instead of creating a visible step.
        var renderedUtil: Double?

        for poll in validPolls {
            // Skip if we can't get the utilization (should not happen after filter, but defensive)
            guard let currentUtil = poll.fiveHourUtil else { continue }

            let x = xPosition(for: poll.timestamp, in: size, timeRange: timeRange)

            if let prev = previousPoll {
                let timeDelta = poll.timestamp - prev.timestamp

                // Check for gap
                if timeDelta > gapThresholdMs {
                    // End current segment if it has points
                    if !currentSegmentPoints.isEmpty {
                        segments.append(PathSegment(
                            points: currentSegmentPoints, isGap: false,
                            pollCount: currentSegmentPollCount,
                            durationMs: currentSegmentLastTimestamp - currentSegmentStartTimestamp
                        ))
                    }

                    // Add gap segment
                    let gapStartX = xPosition(for: prev.timestamp, in: size, timeRange: timeRange)
                    let gapEndX = x
                    segments.append(PathSegment(
                        points: [(x: gapStartX, y: size.height), (x: gapEndX, y: size.height)],
                        isGap: true,
                        pollCount: 0,
                        durationMs: timeDelta
                    ))

                    // Start new segment — reset rendered level
                    let y = yPosition(for: currentUtil, in: size)
                    currentSegmentPoints = [(x: x, y: y)]
                    currentSegmentPollCount = 1
                    currentSegmentStartTimestamp = poll.timestamp
                    currentSegmentLastTimestamp = poll.timestamp
                    renderedUtil = currentUtil
                } else if isResetBoundary(from: prev, to: poll) {
                    // Reset boundary: drop to baseline then start fresh
                    if let rendered = renderedUtil {
                        let renderedY = yPosition(for: rendered, in: size)
                        currentSegmentPoints.append((x: x, y: renderedY))
                        currentSegmentPoints.append((x: x, y: size.height))
                    }
                    if !currentSegmentPoints.isEmpty {
                        segments.append(PathSegment(
                            points: currentSegmentPoints, isGap: false,
                            pollCount: currentSegmentPollCount,
                            durationMs: currentSegmentLastTimestamp - currentSegmentStartTimestamp
                        ))
                    }
                    // Start new segment from baseline — reset rendered level
                    let y = yPosition(for: currentUtil, in: size)
                    currentSegmentPoints = [(x: x, y: size.height), (x: x, y: y)]
                    currentSegmentPollCount = 1
                    currentSegmentStartTimestamp = poll.timestamp
                    currentSegmentLastTimestamp = poll.timestamp
                    renderedUtil = currentUtil
                } else {
                    // Normal step: check if the change is significant enough to render
                    let changeFromRendered = abs(currentUtil - (renderedUtil ?? currentUtil))

                    if changeFromRendered >= utilizationNoiseThreshold {
                        // Significant change: create a visible step
                        if let rendered = renderedUtil {
                            let renderedY = yPosition(for: rendered, in: size)
                            currentSegmentPoints.append((x: x, y: renderedY))
                        }
                        let y = yPosition(for: currentUtil, in: size)
                        currentSegmentPoints.append((x: x, y: y))
                        renderedUtil = currentUtil
                    }
                    // else: change is noise — skip this poll's vertical step,
                    // the horizontal line continues at the rendered level
                    currentSegmentPollCount += 1
                    currentSegmentLastTimestamp = poll.timestamp
                }
            } else {
                // First valid point
                let y = yPosition(for: currentUtil, in: size)
                currentSegmentPoints.append((x: x, y: y))
                currentSegmentPollCount = 1
                currentSegmentStartTimestamp = poll.timestamp
                currentSegmentLastTimestamp = poll.timestamp
                renderedUtil = currentUtil
            }

            previousPoll = poll
        }

        // Add final segment: extend horizontal line to the last timestamp
        if !currentSegmentPoints.isEmpty {
            if let rendered = renderedUtil, let lastPoll = validPolls.last {
                let lastX = xPosition(for: lastPoll.timestamp, in: size, timeRange: timeRange)
                let renderedY = yPosition(for: rendered, in: size)
                // Extend the last rendered level to the end of the data
                if let lastPoint = currentSegmentPoints.last,
                   lastPoint.x < lastX {
                    currentSegmentPoints.append((x: lastX, y: renderedY))
                }
            }
            segments.append(PathSegment(
                points: currentSegmentPoints, isGap: false,
                pollCount: currentSegmentPollCount,
                durationMs: currentSegmentLastTimestamp - currentSegmentStartTimestamp
            ))
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

    /// Maximum jitter in milliseconds tolerated for fiveHourResetsAt comparisons.
    /// The Claude API returns fiveHourResetsAt with sub-second jitter (±500ms)
    /// around the same logical reset timestamp. A real reset shifts the value by
    /// hours (next 5-hour window). 60 seconds is well above jitter but far below
    /// any real window change.
    static let resetsAtJitterToleranceMs: Int64 = 60_000

    /// Determines if there's a reset boundary between two consecutive polls.
    /// - Parameters:
    ///   - previous: The previous poll
    ///   - current: The current poll
    /// - Returns: True if a reset occurred between the polls
    static func isResetBoundary(from previous: UsagePoll, to current: UsagePoll) -> Bool {
        // Primary detection: fiveHourResetsAt changed significantly
        // (ignoring sub-second API jitter)
        if let prevResetsAt = previous.fiveHourResetsAt,
           let currResetsAt = current.fiveHourResetsAt,
           abs(prevResetsAt - currResetsAt) > resetsAtJitterToleranceMs {
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

    /// Minimum duration in milliseconds for an isolated segment to be rendered as data.
    /// Isolated segments (sandwiched between gaps) shorter than this are Power Nap noise.
    /// 5 minutes filters brief wake events while keeping real active sessions.
    static let minimumSegmentDurationMs: Int64 = 5 * 60 * 1000

    /// Post-processes segments to merge isolated short data segments into gaps.
    /// Brief wake events (e.g., Power Nap) produce short data segments between
    /// two gaps that appear as noise spikes. Only these isolated short segments are
    /// absorbed — short segments at the edges or adjacent to other data are kept.
    /// - Parameters:
    ///   - segments: Raw segments from buildSegments
    ///   - size: Drawing area size for gap coordinate calculation
    /// - Returns: Cleaned segments with isolated short data segments converted to gaps
    static func mergeShortSegments(
        _ segments: [PathSegment],
        size: CGSize
    ) -> [PathSegment] {
        guard !segments.isEmpty else { return [] }

        // First pass: convert only isolated short data segments to gaps.
        // A segment is "isolated" if both its neighbors are actual gap segments.
        let processed: [PathSegment] = segments.enumerated().map { index, segment in
            guard !segment.isGap && segment.durationMs < minimumSegmentDurationMs else {
                return segment
            }

            let prevIsGap = index > 0 && segments[index - 1].isGap
            let nextIsGap = index < segments.count - 1 && segments[index + 1].isGap

            // Only convert if sandwiched between two gaps
            guard prevIsGap && nextIsGap else { return segment }

            guard let firstX = segment.points.first?.x,
                  let lastX = segment.points.last?.x else {
                return segment
            }
            return PathSegment(
                points: [(x: firstX, y: size.height), (x: lastX, y: size.height)],
                isGap: true,
                pollCount: 0,
                durationMs: 0
            )
        }

        // Second pass: merge consecutive gaps
        var merged: [PathSegment] = []
        for segment in processed {
            if segment.isGap,
               let last = merged.last,
               last.isGap,
               let lastStart = last.points.first,
               let currentEnd = segment.points.last {
                // Merge: extend previous gap to cover this one
                merged[merged.count - 1] = PathSegment(
                    points: [(x: lastStart.x, y: size.height), (x: currentEnd.x, y: size.height)],
                    isGap: true,
                    pollCount: 0,
                    durationMs: 0
                )
            } else {
                merged.append(segment)
            }
        }

        return merged
    }

    /// Minimum gap duration to be visually significant in the sparkline.
    /// Brief interruptions (Power Nap, system sleep < 5 min) are absorbed into the
    /// current segment where the noise threshold suppresses API jitter.
    /// Only gaps >= 5 minutes create a visible break in the sparkline.
    static let sparklineGapThresholdMs: Int64 = 5 * 60 * 1000

    /// Calculates the gap threshold based on poll interval.
    /// Uses a fixed 5-minute minimum to absorb brief Power Nap wakes,
    /// falling back to 1.5x poll interval if the poll interval is very long.
    /// - Parameter pollInterval: The poll interval in seconds
    /// - Returns: Gap threshold in milliseconds
    static func gapThresholdMs(pollInterval: TimeInterval) -> Int64 {
        max(sparklineGapThresholdMs, Int64(pollInterval * 1000 * 1.5))
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
            let rawSegments = SparklinePathBuilder.buildSegments(from: data, size: size, gapThresholdMs: gapThreshold)
            let segments = SparklinePathBuilder.mergeShortSegments(rawSegments, size: size)

            for segment in segments {
                if segment.isGap {
                    drawGapRegion(context: context, segment: segment, size: size)
                } else {
                    drawDataSegment(context: context, segment: segment, size: size)
                }
            }

            // Draw analytics open indicator dot if needed
            if isAnalyticsOpen {
                drawAnalyticsIndicatorDot(context: context, size: size)
            }
        }
        .background(isHovered ? Color(nsColor: .quaternarySystemFill).opacity(0.3) : Color.clear)
        .overlay(SparklineInteractionOverlay(onTap: { onTap?() }, onHoverChange: { isHovered = $0 }))
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

        // Gap fill visible in both light and dark mode
        context.fill(path, with: .color(Color.gray.opacity(0.15)))
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

// MARK: - Sparkline Interaction Overlay

/// AppKit overlay that provides reliable hand cursor and click handling for the sparkline.
///
/// Uses `addCursorRect(_:cursor:)` for cursor management — the only mechanism that reliably
/// persists across window activation changes. `addCursorRect` requires winning `hitTest`,
/// so this view sits as an `.overlay()` and handles both cursor and clicks in one place.
///
/// This replaces a SwiftUI `Button` which had two problems in `NSPopover` context:
/// 1. `.onHover` + `NSCursor.push()`/`pop()` — cursor stack corrupted on window changes
/// 2. `.onHover` + `NSCursor.set()` — immediately overridden by AppKit's cursor rect system
private struct SparklineInteractionOverlay: NSViewRepresentable {
    var onTap: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?

    func makeNSView(context: Context) -> SparklineInteractionNSView {
        let view = SparklineInteractionNSView()
        view.onTap = onTap
        view.onHoverChange = onHoverChange
        return view
    }

    func updateNSView(_ nsView: SparklineInteractionNSView, context: Context) {
        nsView.onTap = onTap
        nsView.onHoverChange = onHoverChange
    }

    final class SparklineInteractionNSView: NSView {
        var onTap: (() -> Void)?
        var onHoverChange: ((Bool) -> Void)?

        // --- Cursor ---
        // Two mechanisms cover all window-key states:
        // 1. addCursorRect: works when this window IS key (managed by window server)
        // 2. NSTrackingArea + NSCursor.set(): works when this window is NOT key
        //    (no cursor rect system active to override it)

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas {
                removeTrackingArea(area)
            }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Make the popover window key so addCursorRect works immediately
            // (without requiring the user to click the popover first).
            window?.makeKey()
            window?.invalidateCursorRects(for: self)
        }

        override func mouseEntered(with event: NSEvent) {
            // Fallback cursor set for when the window is not key
            // (addCursorRect only works for the key window)
            NSCursor.pointingHand.set()
            onHoverChange?(true)
        }

        override func mouseExited(with event: NSEvent) {
            NSCursor.arrow.set()
            onHoverChange?(false)
        }

        // --- Click ---

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseUp(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            if bounds.contains(location) {
                onTap?()
            }
        }
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
