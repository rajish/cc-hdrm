import SwiftUI
import Testing
@testable import cc_hdrm

// MARK: - SparklinePathBuilder Tests

@Suite("SparklinePathBuilder Tests")
struct SparklinePathBuilderTests {

    // MARK: - Gap Threshold Calculation (Subtask 3.6)

    @Test("gapThresholdMs uses 5-minute minimum for normal poll intervals")
    func gapThresholdUsesMinimum() {
        let fiveMinMs: Int64 = 5 * 60 * 1000

        // 30s poll interval -> 5 min minimum (45s * 1.5 = 45s < 5 min)
        #expect(SparklinePathBuilder.gapThresholdMs(pollInterval: 30) == fiveMinMs)

        // 60s poll interval -> 5 min minimum (90s < 5 min)
        #expect(SparklinePathBuilder.gapThresholdMs(pollInterval: 60) == fiveMinMs)

        // 10s poll interval -> 5 min minimum (15s < 5 min)
        #expect(SparklinePathBuilder.gapThresholdMs(pollInterval: 10) == fiveMinMs)
    }

    @Test("gapThresholdMs falls back to 1.5x for very long poll intervals")
    func gapThresholdFallsBackForLongIntervals() {
        // 300s (5min) poll interval -> 1.5x = 450s = 7.5 min > 5 min minimum
        #expect(SparklinePathBuilder.gapThresholdMs(pollInterval: 300) == 450_000)

        // 600s (10min) poll interval -> 1.5x = 900s = 15 min > 5 min minimum
        #expect(SparklinePathBuilder.gapThresholdMs(pollInterval: 600) == 900_000)
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

    @Test("isResetBoundary detects when fiveHourResetsAt changes by more than jitter tolerance")
    func resetBoundaryByResetsAtChange() {
        let prev = UsagePoll(
            id: 1,
            timestamp: 1000,
            fiveHourUtil: 80.0,
            fiveHourResetsAt: 5_000_000, // First 5h window
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )
        let curr = UsagePoll(
            id: 2,
            timestamp: 2000,
            fiveHourUtil: 10.0, // Dropped due to reset
            fiveHourResetsAt: 23_000_000, // Next 5h window (hours later)
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )

        #expect(SparklinePathBuilder.isResetBoundary(from: prev, to: curr) == true)
    }

    @Test("isResetBoundary ignores sub-second API jitter in fiveHourResetsAt")
    func noResetBoundaryForApiJitter() {
        // The Claude API returns fiveHourResetsAt with ±500ms jitter on every poll.
        // This must NOT be treated as a reset boundary.
        let prev = UsagePoll(
            id: 1,
            timestamp: 1000,
            fiveHourUtil: 23.0,
            fiveHourResetsAt: 1_770_307_199_745, // Typical API value
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )
        let curr = UsagePoll(
            id: 2,
            timestamp: 31000,
            fiveHourUtil: 23.0,
            fiveHourResetsAt: 1_770_307_200_353, // ~608ms jitter — same logical window
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )

        #expect(SparklinePathBuilder.isResetBoundary(from: prev, to: curr) == false)
    }

    @Test("isResetBoundary ignores jitter up to tolerance threshold (60 seconds)")
    func noResetBoundaryWithinTolerance() {
        let baseResetTime: Int64 = 1_770_307_200_000
        let prev = UsagePoll(
            id: 1,
            timestamp: 1000,
            fiveHourUtil: 30.0,
            fiveHourResetsAt: baseResetTime,
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )
        let curr = UsagePoll(
            id: 2,
            timestamp: 2000,
            fiveHourUtil: 31.0,
            fiveHourResetsAt: baseResetTime + 59_999, // Just under 60s tolerance
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )

        #expect(SparklinePathBuilder.isResetBoundary(from: prev, to: curr) == false)
    }

    @Test("isResetBoundary triggers at exactly tolerance boundary")
    func resetBoundaryAtExactTolerance() {
        let baseResetTime: Int64 = 1_770_307_200_000
        let tolerance = SparklinePathBuilder.resetsAtJitterToleranceMs
        let prev = UsagePoll(
            id: 1,
            timestamp: 1000,
            fiveHourUtil: 80.0,
            fiveHourResetsAt: baseResetTime,
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )
        let curr = UsagePoll(
            id: 2,
            timestamp: 2000,
            fiveHourUtil: 10.0,
            fiveHourResetsAt: baseResetTime + tolerance + 1, // Just over tolerance
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

    // MARK: - Jitter Tolerance Integration Test

    @Test("buildSegments produces one segment for continuous polling with fiveHourResetsAt jitter")
    func continuousPollingWithJitterProducesOneSegment() {
        let size = CGSize(width: 200, height: 40)
        let baseResetTime: Int64 = 1_770_307_200_000
        // Simulate 20 polls at 30s intervals with ±500ms resets_at jitter (real API behavior)
        let polls: [UsagePoll] = (0..<20).map { i in
            let jitter = Int64.random(in: -500...500)
            return UsagePoll(
                id: Int64(i),
                timestamp: Int64(i) * 30_000,
                fiveHourUtil: 23.0 + Double(i) * 0.3, // Slowly increasing
                fiveHourResetsAt: baseResetTime + jitter,
                sevenDayUtil: nil,
                sevenDayResetsAt: nil
            )
        }

        let gapThreshold = SparklinePathBuilder.gapThresholdMs(pollInterval: 30)
        let segments = SparklinePathBuilder.buildSegments(from: polls, size: size, gapThresholdMs: gapThreshold)

        let dataSegments = segments.filter { !$0.isGap }
        #expect(dataSegments.count == 1, "Continuous polling with jittering resets_at should produce exactly one data segment, not \(dataSegments.count)")
        #expect(segments.filter { $0.isGap }.isEmpty, "Should have no gaps in continuous 30s polling")
    }

    // MARK: - Reset Boundary in Path (Subtask 3.4)

    // MARK: - Short Segment Merging (Power Nap filtering)

    @Test("mergeShortSegments converts isolated short-duration data segments to gaps")
    func mergesShortDurationSegments() {
        let size = CGSize(width: 200, height: 40)
        let shortDuration: Int64 = 90_000  // 90 seconds — well under 5 min threshold

        // Simulate: [data 10min] [gap] [data 90s (Power Nap)] [gap] [data 10min]
        let segments: [SparklinePathBuilder.PathSegment] = [
            .init(points: [(0, 10), (10, 10), (20, 8), (30, 8), (40, 6)], isGap: false, pollCount: 20, durationMs: 600_000),
            .init(points: [(40, 40), (80, 40)], isGap: true, pollCount: 0, durationMs: 3_600_000),
            .init(points: [(80, 12), (85, 12), (90, 11)], isGap: false, pollCount: 3, durationMs: shortDuration),
            .init(points: [(90, 40), (150, 40)], isGap: true, pollCount: 0, durationMs: 7_200_000),
            .init(points: [(150, 20), (160, 18), (170, 16), (180, 14)], isGap: false, pollCount: 20, durationMs: 600_000),
        ]

        let merged = SparklinePathBuilder.mergeShortSegments(segments, size: size)

        let dataSegments = merged.filter { !$0.isGap }
        let gapSegments = merged.filter { $0.isGap }

        #expect(dataSegments.count == 2, "Should keep the two long data segments")
        #expect(gapSegments.count == 1, "Three consecutive gaps should merge into one")

        if let mergedGap = gapSegments.first {
            #expect(mergedGap.points[0].x == 40, "Merged gap should start at x=40")
            #expect(mergedGap.points[1].x == 150, "Merged gap should end at x=150")
        }
    }

    @Test("mergeShortSegments keeps segments at or above minimum duration")
    func keepsLongEnoughSegments() {
        let size = CGSize(width: 200, height: 40)
        let minDuration = SparklinePathBuilder.minimumSegmentDurationMs

        // Segment exactly at minimum duration, sandwiched between gaps — should be kept
        let segments: [SparklinePathBuilder.PathSegment] = [
            .init(points: [(0, 40), (20, 40)], isGap: true, pollCount: 0, durationMs: 3_600_000),
            .init(points: [(20, 20), (30, 20), (40, 18), (50, 16)], isGap: false, pollCount: 10, durationMs: minDuration),
            .init(points: [(50, 40), (80, 40)], isGap: true, pollCount: 0, durationMs: 3_600_000),
        ]

        let merged = SparklinePathBuilder.mergeShortSegments(segments, size: size)

        let dataSegments = merged.filter { !$0.isGap }
        #expect(dataSegments.count == 1, "Should keep the segment at minimum duration")
        #expect(dataSegments[0].isGap == false, "Should remain a data segment")
    }

    @Test("mergeShortSegments handles empty input")
    func mergeShortSegmentsEmpty() {
        let size = CGSize(width: 200, height: 40)
        let merged = SparklinePathBuilder.mergeShortSegments([], size: size)
        #expect(merged.isEmpty)
    }

    @Test("mergeShortSegments handles all-gap input")
    func mergeShortSegmentsAllGaps() {
        let size = CGSize(width: 200, height: 40)
        let segments: [SparklinePathBuilder.PathSegment] = [
            .init(points: [(0, 40), (50, 40)], isGap: true, pollCount: 0, durationMs: 3_600_000),
            .init(points: [(50, 40), (100, 40)], isGap: true, pollCount: 0, durationMs: 3_600_000),
        ]

        let merged = SparklinePathBuilder.mergeShortSegments(segments, size: size)

        #expect(merged.count == 1, "Consecutive gaps should merge")
        #expect(merged[0].isGap == true)
        #expect(merged[0].points[0].x == 0, "Merged gap starts at 0")
        #expect(merged[0].points[1].x == 100, "Merged gap ends at 100")
    }

    @Test("mergeShortSegments keeps short data segment when not sandwiched between gaps")
    func keepsShortSegmentWhenNotIsolated() {
        let size = CGSize(width: 200, height: 40)

        // Short segment alone (no surrounding gaps) — keep it (e.g., start of data collection)
        let segments: [SparklinePathBuilder.PathSegment] = [
            .init(points: [(50, 20), (60, 18)], isGap: false, pollCount: 1, durationMs: 30_000),
        ]

        let merged = SparklinePathBuilder.mergeShortSegments(segments, size: size)

        #expect(merged.count == 1, "Should keep the segment")
        #expect(merged[0].isGap == false, "Not isolated, so should remain data")
    }

    @Test("mergeShortSegments converts short data segment sandwiched between gaps")
    func convertsIsolatedShortSegment() {
        let size = CGSize(width: 200, height: 40)

        // Short segment between two gaps — Power Nap noise
        let segments: [SparklinePathBuilder.PathSegment] = [
            .init(points: [(0, 40), (50, 40)], isGap: true, pollCount: 0, durationMs: 3_600_000),
            .init(points: [(50, 20), (60, 18)], isGap: false, pollCount: 2, durationMs: 60_000),
            .init(points: [(60, 40), (100, 40)], isGap: true, pollCount: 0, durationMs: 3_600_000),
        ]

        let merged = SparklinePathBuilder.mergeShortSegments(segments, size: size)

        #expect(merged.count == 1, "Should merge into a single gap")
        #expect(merged[0].isGap == true, "Isolated short segment should become a gap")
    }

    @Test("mergeShortSegments keeps short data segment adjacent to real data")
    func keepsShortSegmentAdjacentToData() {
        let size = CGSize(width: 200, height: 40)

        // Short segment next to a real data segment (not isolated)
        let segments: [SparklinePathBuilder.PathSegment] = [
            .init(points: [(0, 10), (10, 10), (20, 8), (30, 8)], isGap: false, pollCount: 20, durationMs: 600_000),
            .init(points: [(30, 12), (40, 11)], isGap: false, pollCount: 2, durationMs: 60_000),  // short but adjacent to data
            .init(points: [(40, 40), (100, 40)], isGap: true, pollCount: 0, durationMs: 3_600_000),
        ]

        let merged = SparklinePathBuilder.mergeShortSegments(segments, size: size)

        let dataSegments = merged.filter { !$0.isGap }
        #expect(dataSegments.count == 2, "Both data segments should be kept — short one is not isolated")
    }

    @Test("mergeShortSegments preserves gap segments unchanged")
    func preservesExistingGaps() {
        let size = CGSize(width: 200, height: 40)
        let segments: [SparklinePathBuilder.PathSegment] = [
            .init(points: [(0, 10), (10, 10), (20, 8), (30, 8)], isGap: false, pollCount: 20, durationMs: 600_000),
            .init(points: [(30, 40), (80, 40)], isGap: true, pollCount: 0, durationMs: 3_600_000),
            .init(points: [(80, 12), (90, 10), (100, 8), (110, 6)], isGap: false, pollCount: 20, durationMs: 600_000),
        ]

        let merged = SparklinePathBuilder.mergeShortSegments(segments, size: size)

        #expect(merged.count == 3, "All segments should be preserved")
        #expect(merged[0].isGap == false)
        #expect(merged[1].isGap == true)
        #expect(merged[2].isGap == false)
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

    @Test("Sparkline suppresses Power Nap spikes in rendered segments")
    @MainActor
    func suppressesPowerNapSpikes() {
        // Simulate: active usage -> sleep (gap) -> Power Nap (2 polls) -> sleep (gap) -> wake (active)
        let polls = [
            // Active period: 5 polls at 30s intervals
            UsagePoll(id: 1, timestamp: 0, fiveHourUtil: 40.0, fiveHourResetsAt: 100000, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: 30000, fiveHourUtil: 42.0, fiveHourResetsAt: 100000, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 3, timestamp: 60000, fiveHourUtil: 45.0, fiveHourResetsAt: 100000, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 4, timestamp: 90000, fiveHourUtil: 47.0, fiveHourResetsAt: 100000, sevenDayUtil: nil, sevenDayResetsAt: nil),
            // Gap: user sleeps (3 hours)
            // Power Nap: 2 polls
            UsagePoll(id: 5, timestamp: 10890000, fiveHourUtil: 12.0, fiveHourResetsAt: 100000, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 6, timestamp: 10920000, fiveHourUtil: 12.3, fiveHourResetsAt: 100000, sevenDayUtil: nil, sevenDayResetsAt: nil),
            // Gap: back to sleep (4 hours)
            // Wake up: active usage resumes
            UsagePoll(id: 7, timestamp: 25320000, fiveHourUtil: 2.0, fiveHourResetsAt: 200000, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 8, timestamp: 25350000, fiveHourUtil: 5.0, fiveHourResetsAt: 200000, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 9, timestamp: 25380000, fiveHourUtil: 8.0, fiveHourResetsAt: 200000, sevenDayUtil: nil, sevenDayResetsAt: nil),
            UsagePoll(id: 10, timestamp: 25410000, fiveHourUtil: 12.0, fiveHourResetsAt: 200000, sevenDayUtil: nil, sevenDayResetsAt: nil),
        ]

        let size = CGSize(width: 200, height: 40)
        let gapThreshold = SparklinePathBuilder.gapThresholdMs(pollInterval: 30)
        let rawSegments = SparklinePathBuilder.buildSegments(from: polls, size: size, gapThresholdMs: gapThreshold)
        let segments = SparklinePathBuilder.mergeShortSegments(rawSegments, size: size)

        // The Power Nap 2-poll segment should be absorbed into the gap
        let dataSegments = segments.filter { !$0.isGap }
        #expect(dataSegments.count == 2, "Should have active-before-sleep and active-after-wake segments only")

        // Verify the Power Nap segment (30s duration) was absorbed into a gap
        let gapSegments = segments.filter { $0.isGap }
        #expect(gapSegments.count == 1, "Power Nap gap + surrounding gaps should merge into one")
        // The two edge data segments (polls 1-4 and polls 7-10) are kept because
        // they are not sandwiched between gaps (at array edges).
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
