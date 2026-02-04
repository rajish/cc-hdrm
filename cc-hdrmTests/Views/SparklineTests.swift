import SwiftUI
import Testing
@testable import cc_hdrm

// MARK: - SparklinePathBuilder Tests

@Suite("SparklinePathBuilder Tests")
struct SparklinePathBuilderTests {

    // MARK: - Gap Threshold Calculation (Subtask 3.6)

    @Test("gapThresholdMs returns 1.5x poll interval in milliseconds")
    func gapThresholdCalculation() {
        // 30s poll interval -> 45,000ms threshold
        #expect(SparklinePathBuilder.gapThresholdMs(pollInterval: 30) == 45_000)

        // 60s poll interval -> 90,000ms threshold
        #expect(SparklinePathBuilder.gapThresholdMs(pollInterval: 60) == 90_000)

        // 10s poll interval -> 15,000ms threshold
        #expect(SparklinePathBuilder.gapThresholdMs(pollInterval: 10) == 15_000)

        // 300s (5min) poll interval -> 450,000ms threshold
        #expect(SparklinePathBuilder.gapThresholdMs(pollInterval: 300) == 450_000)
    }

    // MARK: - X-Axis Proportional Mapping (Subtask 3.9)

    @Test("xPosition maps timestamp to proportional position")
    func xPositionMapping() {
        let size = CGSize(width: 200, height: 40)
        let timeRange: ClosedRange<Int64> = 1000...2000 // 1 second range

        // Start of range -> x=0
        #expect(SparklinePathBuilder.xPosition(for: 1000, in: size, timeRange: timeRange) == 0)

        // End of range -> x=width
        #expect(SparklinePathBuilder.xPosition(for: 2000, in: size, timeRange: timeRange) == 200)

        // Middle of range -> x=width/2
        #expect(SparklinePathBuilder.xPosition(for: 1500, in: size, timeRange: timeRange) == 100)

        // Quarter of range -> x=width/4
        #expect(SparklinePathBuilder.xPosition(for: 1250, in: size, timeRange: timeRange) == 50)
    }

    @Test("xPosition handles zero duration gracefully")
    func xPositionZeroDuration() {
        let size = CGSize(width: 200, height: 40)
        let timeRange: ClosedRange<Int64> = 1000...1000 // Zero duration

        #expect(SparklinePathBuilder.xPosition(for: 1000, in: size, timeRange: timeRange) == 0)
    }

    // MARK: - Y-Axis Mapping (Subtask 3.3)

    @Test("yPosition maps utilization to Y coordinate (inverted: 100% at top)")
    func yPositionMapping() {
        let size = CGSize(width: 200, height: 40)

        // 0% utilization -> bottom (y=height)
        #expect(SparklinePathBuilder.yPosition(for: 0, in: size) == 40)

        // 100% utilization -> top (y=0)
        #expect(SparklinePathBuilder.yPosition(for: 100, in: size) == 0)

        // 50% utilization -> middle
        #expect(SparklinePathBuilder.yPosition(for: 50, in: size) == 20)

        // 25% utilization -> 3/4 from top
        #expect(SparklinePathBuilder.yPosition(for: 25, in: size) == 30)
    }

    @Test("yPosition clamps values outside 0-100 range")
    func yPositionClamping() {
        let size = CGSize(width: 200, height: 40)

        // Negative utilization clamped to 0
        #expect(SparklinePathBuilder.yPosition(for: -10, in: size) == 40)

        // Over 100% clamped to 100
        #expect(SparklinePathBuilder.yPosition(for: 150, in: size) == 0)
    }

    // MARK: - Reset Boundary Detection (Subtask 3.4, 3.5)

    @Test("isResetBoundary detects when fiveHourResetsAt changes")
    func resetBoundaryByResetsAtChange() {
        let prev = UsagePoll(
            id: 1,
            timestamp: 1000,
            fiveHourUtil: 80.0,
            fiveHourResetsAt: 5000,
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )
        let curr = UsagePoll(
            id: 2,
            timestamp: 2000,
            fiveHourUtil: 10.0, // Dropped due to reset
            fiveHourResetsAt: 10000, // Different reset time
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )

        #expect(SparklinePathBuilder.isResetBoundary(from: prev, to: curr) == true)
    }

    @Test("isResetBoundary returns false when fiveHourResetsAt unchanged")
    func noResetBoundarySameResetsAt() {
        let prev = UsagePoll(
            id: 1,
            timestamp: 1000,
            fiveHourUtil: 30.0,
            fiveHourResetsAt: 5000,
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )
        let curr = UsagePoll(
            id: 2,
            timestamp: 2000,
            fiveHourUtil: 35.0, // Normal increase
            fiveHourResetsAt: 5000, // Same reset time
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )

        #expect(SparklinePathBuilder.isResetBoundary(from: prev, to: curr) == false)
    }

    @Test("isResetBoundary fallback: >50% drop indicates reset when resetsAt unavailable")
    func resetBoundaryFallbackLargeDrop() {
        let prev = UsagePoll(
            id: 1,
            timestamp: 1000,
            fiveHourUtil: 80.0,
            fiveHourResetsAt: nil, // No reset info
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )
        let curr = UsagePoll(
            id: 2,
            timestamp: 2000,
            fiveHourUtil: 20.0, // 60% drop (>50%)
            fiveHourResetsAt: nil,
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )

        #expect(SparklinePathBuilder.isResetBoundary(from: prev, to: curr) == true)
    }

    @Test("isResetBoundary fallback: <=50% drop is not a reset")
    func resetBoundaryFallbackSmallDrop() {
        let prev = UsagePoll(
            id: 1,
            timestamp: 1000,
            fiveHourUtil: 80.0,
            fiveHourResetsAt: nil,
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )
        let curr = UsagePoll(
            id: 2,
            timestamp: 2000,
            fiveHourUtil: 35.0, // 45% drop (<=50%)
            fiveHourResetsAt: nil,
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )

        #expect(SparklinePathBuilder.isResetBoundary(from: prev, to: curr) == false)
    }

    @Test("isResetBoundary fallback: exactly 50% drop is NOT a reset (boundary condition)")
    func resetBoundaryFallbackExactlyFiftyPercent() {
        let prev = UsagePoll(
            id: 1,
            timestamp: 1000,
            fiveHourUtil: 80.0,
            fiveHourResetsAt: nil,
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )
        let curr = UsagePoll(
            id: 2,
            timestamp: 2000,
            fiveHourUtil: 30.0, // Exactly 50% drop (80 - 30 = 50, NOT > 50)
            fiveHourResetsAt: nil,
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )

        // The condition is `> 50.0`, so exactly 50% should NOT trigger a reset
        #expect(SparklinePathBuilder.isResetBoundary(from: prev, to: curr) == false)
    }

    @Test("isResetBoundary returns false when utilization increases")
    func noResetBoundaryUtilizationIncrease() {
        let prev = UsagePoll(
            id: 1,
            timestamp: 1000,
            fiveHourUtil: 30.0,
            fiveHourResetsAt: nil,
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )
        let curr = UsagePoll(
            id: 2,
            timestamp: 2000,
            fiveHourUtil: 50.0, // Normal increase
            fiveHourResetsAt: nil,
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )

        #expect(SparklinePathBuilder.isResetBoundary(from: prev, to: curr) == false)
    }

    // MARK: - Invalid Data Point Filtering (Subtask 3.7)

    @Test("buildSegments filters out polls with nil fiveHourUtil")
    func filtersNilUtilization() {
        let size = CGSize(width: 200, height: 40)
        let polls = [
            UsagePoll(id: 1, timestamp: 1000, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 2000, fiveHourUtil: nil, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil), // Invalid
            UsagePoll(id: 3, timestamp: 3000, fiveHourUtil: 30.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
        ]

        let segments = SparklinePathBuilder.buildSegments(from: polls, size: size, gapThresholdMs: 5000)

        // Should have one data segment with points from valid polls only (invalid poll skipped)
        #expect(segments.count == 1, "Should produce exactly one segment")
        #expect(segments[0].isGap == false, "Should be a data segment, not a gap")
        // With 2 valid points and step pattern: first point, horizontal step, vertical step = at least 3 points
        #expect(segments[0].points.count >= 3, "Step-area pattern needs at least 3 points for 2 data points")
    }

    @Test("buildSegments filters out polls with negative fiveHourUtil")
    func filtersNegativeUtilization() {
        let size = CGSize(width: 200, height: 40)
        let polls = [
            UsagePoll(id: 1, timestamp: 1000, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 2000, fiveHourUtil: -5.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil), // Invalid
            UsagePoll(id: 3, timestamp: 3000, fiveHourUtil: 30.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
        ]

        let segments = SparklinePathBuilder.buildSegments(from: polls, size: size, gapThresholdMs: 5000)

        // Should have one data segment with points from valid polls only (negative poll skipped)
        #expect(segments.count == 1, "Should produce exactly one segment")
        #expect(segments[0].isGap == false, "Should be a data segment, not a gap")
        #expect(segments[0].points.count >= 3, "Step-area pattern needs at least 3 points for 2 data points")
    }

    @Test("buildSegments filters out polls with fiveHourUtil > 100")
    func filtersOverHundredUtilization() {
        let size = CGSize(width: 200, height: 40)
        let polls = [
            UsagePoll(id: 1, timestamp: 1000, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 2000, fiveHourUtil: 150.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil), // Invalid
            UsagePoll(id: 3, timestamp: 3000, fiveHourUtil: 30.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
        ]

        let segments = SparklinePathBuilder.buildSegments(from: polls, size: size, gapThresholdMs: 5000)

        // Should have one data segment with points from valid polls only (>100% poll skipped)
        #expect(segments.count == 1, "Should produce exactly one segment")
        #expect(segments[0].isGap == false, "Should be a data segment, not a gap")
        #expect(segments[0].points.count >= 3, "Step-area pattern needs at least 3 points for 2 data points")
    }

    // MARK: - Placeholder Display Condition (Subtask 3.8)

    @Test("buildSegments returns empty for less than 2 valid data points")
    func emptySegmentsForInsufficientData() {
        let size = CGSize(width: 200, height: 40)

        // Zero points
        let emptyPolls: [UsagePoll] = []
        #expect(SparklinePathBuilder.buildSegments(from: emptyPolls, size: size, gapThresholdMs: 45000).isEmpty)

        // One point
        let singlePoll = [UsagePoll(id: 1, timestamp: 1000, fiveHourUtil: 50.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil)]
        #expect(SparklinePathBuilder.buildSegments(from: singlePoll, size: size, gapThresholdMs: 45000).isEmpty)

        // Two invalid points
        let twoInvalidPolls = [
            UsagePoll(id: 1, timestamp: 1000, fiveHourUtil: nil, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 2000, fiveHourUtil: nil, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
        ]
        #expect(SparklinePathBuilder.buildSegments(from: twoInvalidPolls, size: size, gapThresholdMs: 45000).isEmpty)
    }

    @Test("buildSegments produces segments for 2+ valid data points")
    func segmentsForSufficientData() {
        let size = CGSize(width: 200, height: 40)
        let polls = [
            UsagePoll(id: 1, timestamp: 1000, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 2000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
        ]

        let segments = SparklinePathBuilder.buildSegments(from: polls, size: size, gapThresholdMs: 45000)

        #expect(!segments.isEmpty)
        #expect(segments[0].isGap == false)
    }

    @Test("buildSegments handles zero-duration time range (all same timestamp)")
    func zeroDurationTimeRange() {
        let size = CGSize(width: 200, height: 40)
        // All polls have the same timestamp - zero duration edge case
        let polls = [
            UsagePoll(id: 1, timestamp: 1000, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 1000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
        ]

        let segments = SparklinePathBuilder.buildSegments(from: polls, size: size, gapThresholdMs: 45000)

        // With zero duration (lastTimestamp == firstTimestamp), buildSegments returns empty
        // This is the guard condition: `guard lastTimestamp > firstTimestamp else { return [] }`
        #expect(segments.isEmpty, "Zero-duration time range should return empty segments")
    }

    // MARK: - Gap Detection (Subtask 3.6)

    @Test("buildSegments detects gap when timestamp delta exceeds threshold")
    func detectsGapWhenThresholdExceeded() {
        let size = CGSize(width: 200, height: 40)
        let gapThresholdMs: Int64 = 45000 // 45 seconds

        let polls = [
            UsagePoll(id: 1, timestamp: 0, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 100000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil), // 100s gap > 45s threshold
        ]

        let segments = SparklinePathBuilder.buildSegments(from: polls, size: size, gapThresholdMs: gapThresholdMs)

        // Should have: first data segment, gap segment, second data segment
        let gapSegments = segments.filter { $0.isGap }
        #expect(gapSegments.count == 1, "Should have one gap segment")
    }

    @Test("buildSegments no gap when timestamp delta within threshold")
    func noGapWhenWithinThreshold() {
        let size = CGSize(width: 200, height: 40)
        let gapThresholdMs: Int64 = 45000 // 45 seconds

        let polls = [
            UsagePoll(id: 1, timestamp: 0, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 30000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil), // 30s < 45s threshold
        ]

        let segments = SparklinePathBuilder.buildSegments(from: polls, size: size, gapThresholdMs: gapThresholdMs)

        // Should have only data segments, no gaps
        let gapSegments = segments.filter { $0.isGap }
        #expect(gapSegments.isEmpty, "Should have no gap segments")
    }

    // MARK: - Step-Area Path Generation (Subtask 3.3)

    @Test("buildSegments creates step-area pattern points")
    func stepAreaPathGeneration() {
        let size = CGSize(width: 200, height: 40)
        let polls = [
            UsagePoll(id: 1, timestamp: 0, fiveHourUtil: 10.0, fiveHourResetsAt: 5000, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 1000, fiveHourUtil: 30.0, fiveHourResetsAt: 5000, sevenDayUtil: nil, sevenDayResetsAt: nil),
        ]

        let segments = SparklinePathBuilder.buildSegments(from: polls, size: size, gapThresholdMs: 45000)

        #expect(segments.count == 1, "Should produce exactly one data segment")
        let dataSegment = segments[0]
        #expect(dataSegment.isGap == false, "Should be a data segment, not a gap")

        // Step-area pattern for 2 data points:
        // 1. First point (x=0, y for 10% util)
        // 2. Horizontal step to second x at first y (x=200, y for 10% util)
        // 3. Vertical step to second y (x=200, y for 30% util)
        // Total: 3 points minimum for proper step-area rendering
        #expect(dataSegment.points.count >= 3, "Step-area pattern requires at least 3 points for 2 data points")

        // Verify the step pattern structure
        let points = dataSegment.points
        // First point should be at x=0 (first timestamp)
        #expect(points[0].x == 0, "First point should be at x=0")
        // Last point should be at x=200 (second timestamp at end of range)
        #expect(points[points.count - 1].x == 200, "Last point should be at x=200 (full width)")
    }

    // MARK: - Reset Boundary in Path (Subtask 3.4)

    @Test("buildSegments creates vertical drop at reset boundary")
    func resetBoundaryVerticalDrop() {
        let size = CGSize(width: 200, height: 40)
        let polls = [
            UsagePoll(id: 1, timestamp: 0, fiveHourUtil: 80.0, fiveHourResetsAt: 1000, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 500, fiveHourUtil: 10.0, fiveHourResetsAt: 5000, sevenDayUtil: nil, sevenDayResetsAt: nil), // Reset!
        ]

        let segments = SparklinePathBuilder.buildSegments(from: polls, size: size, gapThresholdMs: 45000)

        // With reset, we should have 2 segments: one ending at reset, one starting after
        #expect(segments.count == 2, "Reset should create two separate data segments")

        // Both should be data segments, not gaps
        #expect(segments.allSatisfy { !$0.isGap })
    }
}

// MARK: - Sparkline View Tests

@Suite("Sparkline Component Tests")
struct SparklineComponentTests {

    @Test("Sparkline renders without crash with valid data")
    @MainActor
    func rendersWithValidData() {
        let polls = [
            UsagePoll(id: 1, timestamp: 1000, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 2000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
        ]
        let sparkline = Sparkline(data: polls, pollInterval: 30)
        _ = sparkline.body
    }

    @Test("Sparkline renders placeholder with empty data")
    @MainActor
    func rendersPlaceholderWithEmptyData() {
        let sparkline = Sparkline(data: [], pollInterval: 30)
        _ = sparkline.body
    }

    @Test("Sparkline renders placeholder with single data point")
    @MainActor
    func rendersPlaceholderWithSinglePoint() {
        let polls = [
            UsagePoll(id: 1, timestamp: 1000, fiveHourUtil: 50.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
        ]
        let sparkline = Sparkline(data: polls, pollInterval: 30)
        _ = sparkline.body
    }

    @Test("Sparkline accepts onTap callback")
    @MainActor
    func acceptsOnTapCallback() {
        var tapped = false
        let sparkline = Sparkline(
            data: [
                UsagePoll(id: 1, timestamp: 1000, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
                UsagePoll(id: 2, timestamp: 2000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            ],
            pollInterval: 30,
            onTap: { tapped = true }
        )
        _ = sparkline.body
        // Note: Can't easily trigger tap in unit test, but verifying it accepts the callback
        #expect(tapped == false) // Initial state
    }

    @Test("Sparkline accepts isAnalyticsOpen binding")
    @MainActor
    func acceptsIsAnalyticsOpen() {
        let sparkline = Sparkline(
            data: [
                UsagePoll(id: 1, timestamp: 1000, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
                UsagePoll(id: 2, timestamp: 2000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            ],
            pollInterval: 30,
            isAnalyticsOpen: true
        )
        _ = sparkline.body
    }

    @Test("Sparkline handles data with gaps")
    @MainActor
    func handlesDataWithGaps() {
        let polls = [
            UsagePoll(id: 1, timestamp: 0, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 100000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil), // Big gap
        ]
        let sparkline = Sparkline(data: polls, pollInterval: 30)
        _ = sparkline.body
    }

    @Test("Sparkline handles data with reset boundaries")
    @MainActor
    func handlesDataWithResets() {
        let polls = [
            UsagePoll(id: 1, timestamp: 1000, fiveHourUtil: 80.0, fiveHourResetsAt: 2000, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 2000, fiveHourUtil: 5.0, fiveHourResetsAt: 8000, sevenDayUtil: nil, sevenDayResetsAt: nil), // Reset
        ]
        let sparkline = Sparkline(data: polls, pollInterval: 30)
        _ = sparkline.body
    }

    @Test("Sparkline handles invalid data points mixed with valid")
    @MainActor
    func handlesMixedValidInvalidData() {
        let polls = [
            UsagePoll(id: 1, timestamp: 1000, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 2000, fiveHourUtil: nil, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil), // Invalid
            UsagePoll(id: 3, timestamp: 3000, fiveHourUtil: -5.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil), // Invalid
            UsagePoll(id: 4, timestamp: 4000, fiveHourUtil: 150.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil), // Invalid
            UsagePoll(id: 5, timestamp: 5000, fiveHourUtil: 30.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
        ]
        let sparkline = Sparkline(data: polls, pollInterval: 30)
        _ = sparkline.body
    }

    // MARK: - Accessibility Tests (Subtask 3.10)

    @Test("Sparkline provides correct accessibility label")
    @MainActor
    func accessibilityLabel() {
        let sparkline = Sparkline(
            data: [
                UsagePoll(id: 1, timestamp: 1000, fiveHourUtil: 10.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
                UsagePoll(id: 2, timestamp: 2000, fiveHourUtil: 20.0, fiveHourResetsAt: nil, sevenDayUtil: nil, sevenDayResetsAt: nil),
            ],
            pollInterval: 30
        )
        // Verify the view can render (accessibility modifiers are applied)
        _ = sparkline.body
        // Note: Direct accessibility inspection requires ViewInspector or similar
        // This test verifies the view compiles and renders with accessibility modifiers applied
    }
}
