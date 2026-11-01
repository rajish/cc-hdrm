import Foundation

/// Points for the weekly chart of an account with no 5-hour number.
enum WeeklySparklineData {
    /// Raw polls can span the whole week at 10-second intervals, because they are only
    /// rolled up when analytics opens. One point per rollup bucket caps the array near 2,016.
    static let bucketMs: Int64 = 5 * 60 * 1000

    /// The current cycle in Unix milliseconds, from `resetsAt − 7 days` to `resetsAt`.
    /// Nil when the reset is unknown or already passed, since the cycle is then not knowable.
    static func cycle(resetsAt: Date?, now: Date) -> ClosedRange<Int64>? {
        guard let resetsAt, now < resetsAt else { return nil }
        let start = resetsAt.addingTimeInterval(-WeeklyPace.weekDuration)
        guard start < now else { return nil }
        return Int64(start.timeIntervalSince1970 * 1000)...Int64(resetsAt.timeIntervalSince1970 * 1000)
    }

    /// Merges raw polls and rollups into one ascending series for the cycle.
    /// Raw polls are the base because `getRolledUpData(range: .week)` misses raw polls older
    /// than 24 hours that have not been rolled up. Rollups only cover time before the raw polls,
    /// so later rows, including its copies of recent raw polls, are dropped as duplicates.
    /// - Parameters:
    ///   - rawPolls: Ascending, from `getRecentPolls(hours:)`. Must be fetched before `rollups`,
    ///     so a rollup running between the two reads cannot leave a hole.
    ///   - rollups: Ascending, from `getRolledUpData(range: .week)`.
    static func merge(rawPolls: [UsagePoll], rollups: [UsageRollup], cycle: ClosedRange<Int64>) -> [UsagePoll] {
        let recent = rawPolls.filter { cycle.contains($0.timestamp) }
        let firstRecent = recent.first?.timestamp ?? .max

        var points: [UsagePoll] = []
        for rollup in rollups where cycle.contains(rollup.periodStart) && rollup.periodStart < firstRecent {
            if let utilization = rollup.sevenDayPeak {
                add(point(timestamp: rollup.periodStart, utilization: utilization), to: &points)
            }
        }
        for poll in recent {
            if let utilization = poll.sevenDayUtil {
                add(point(timestamp: poll.timestamp, utilization: utilization), to: &points)
            }
        }
        return points
    }

    /// Adds the newest reading, replacing the last point when both share a bucket.
    static func appending(timestamp: Int64, utilization: Double, to points: [UsagePoll]) -> [UsagePoll] {
        var result = points
        add(point(timestamp: timestamp, utilization: utilization), to: &result)
        return result
    }

    private static func point(timestamp: Int64, utilization: Double) -> UsagePoll {
        UsagePoll(id: 0, timestamp: timestamp, fiveHourUtil: nil, fiveHourResetsAt: nil, sevenDayUtil: utilization, sevenDayResetsAt: nil)
    }

    private static func add(_ point: UsagePoll, to points: inout [UsagePoll]) {
        // An unusable reading must not replace a good point in its bucket
        guard let utilization = point.sevenDayUtil, (0...100).contains(utilization) else { return }
        guard let last = points.last else {
            points.append(point)
            return
        }
        guard point.timestamp > last.timestamp else { return }
        if point.timestamp / bucketMs == last.timestamp / bucketMs {
            points[points.count - 1] = point
        } else {
            points.append(point)
        }
    }
}
