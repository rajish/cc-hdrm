import Foundation
import Testing
@testable import cc_hdrm

@Suite("WeeklyPace Tests")
struct WeeklyPaceTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86400

    /// Reset time for a week of which `elapsed` seconds have passed at `now`.
    private func resetsAt(elapsed: TimeInterval) -> Date {
        now.addingTimeInterval(7 * day - elapsed)
    }

    @Test("start of week: util 0, 1h elapsed → paceDelta = -100/168 ≈ -0.6, no run-out")
    func startOfWeek() throws {
        let pace = try #require(WeeklyPace(utilization: 0, resetsAt: resetsAt(elapsed: hour), now: now))
        #expect(abs(pace.paceDelta - (-100.0 / 168.0)) < 1e-9)
        #expect(abs(pace.paceDelta - (-0.6)) < 0.01)
        #expect(pace.runOut == nil)
    }

    @Test("mid-week on pace: util 50, 3.5d elapsed → paceDelta 0, no run-out, \"On pace\"")
    func midWeekOnPace() throws {
        let pace = try #require(WeeklyPace(utilization: 50, resetsAt: resetsAt(elapsed: 3.5 * day), now: now))
        #expect(abs(pace.paceDelta) < 1e-9)
        #expect(pace.runOut == nil)
        #expect(pace.paceLineText == "On pace")
        #expect(pace.accessibilityText == "on pace")
    }

    @Test("ahead of pace: util 60, 3d elapsed → paceDelta = 60 - 300/7 ≈ 17.1, run-out now+2d")
    func aheadOfPace() throws {
        let pace = try #require(WeeklyPace(utilization: 60, resetsAt: resetsAt(elapsed: 3 * day), now: now))
        #expect(abs(pace.paceDelta - (60.0 - 300.0 / 7.0)) < 1e-9)
        #expect(abs(pace.paceDelta - 17.1) < 0.05)
        // rate = 60% / 3d = 20%/d → remaining 40% lasts 2d
        let runOut = try #require(pace.runOut)
        #expect(abs(runOut.timeIntervalSince(now) - 2 * day) < 1e-3)
        #expect(pace.paceLineText == "Ahead of pace \u{2014} runs out ~\(runOut.dayTimeString())")
        #expect(pace.accessibilityText == "ahead of pace, runs out around \(runOut.dayTimeString())")
    }

    @Test("behind pace: util 20, 5d elapsed → paceDelta < 0, no run-out")
    func behindPace() throws {
        let pace = try #require(WeeklyPace(utilization: 20, resetsAt: resetsAt(elapsed: 5 * day), now: now))
        #expect(abs(pace.paceDelta - (20.0 - 500.0 / 7.0)) < 1e-9)
        #expect(pace.paceDelta < 0)
        #expect(pace.runOut == nil)
        #expect(pace.paceLineText == "On pace")
    }

    @Test("missing resets_at → no pace")
    func missingResetsAt() {
        #expect(WeeklyPace(utilization: 60, resetsAt: nil, now: now) == nil)
    }

    @Test("0% utilization: 3d elapsed → paceDelta = -300/7 ≈ -42.9, no run-out (no division by zero rate)")
    func zeroUtilization() throws {
        let pace = try #require(WeeklyPace(utilization: 0, resetsAt: resetsAt(elapsed: 3 * day), now: now))
        #expect(abs(pace.paceDelta - (-300.0 / 7.0)) < 1e-9)
        #expect(abs(pace.paceDelta - (-42.9)) < 0.05)
        #expect(pace.runOut == nil)
    }

    @Test("< 4h elapsed: util 10, 2h elapsed → paceDelta = 10 - 100/84 computed, no run-out")
    func underFourHoursElapsed() throws {
        let pace = try #require(WeeklyPace(utilization: 10, resetsAt: resetsAt(elapsed: 2 * hour), now: now))
        #expect(abs(pace.paceDelta - (10.0 - 100.0 / 84.0)) < 1e-9)
        #expect(pace.paceDelta > 0)
        #expect(pace.runOut == nil)
        #expect(pace.paceLineText == "On pace")
    }

    @Test("exactly 4h elapsed: util 10 → run-out at now + 90 × 4h / 10 = now + 36h")
    func exactlyFourHoursElapsed() throws {
        let pace = try #require(WeeklyPace(utilization: 10, resetsAt: resetsAt(elapsed: 4 * hour), now: now))
        let runOut = try #require(pace.runOut)
        #expect(abs(runOut.timeIntervalSince(now) - 36 * hour) < 1e-3)
    }

    @Test("exhausted: util ≥ 100 → no pace")
    func exhausted() {
        #expect(WeeklyPace(utilization: 100, resetsAt: resetsAt(elapsed: 3 * day), now: now) == nil)
        #expect(WeeklyPace(utilization: 104, resetsAt: resetsAt(elapsed: 3 * day), now: now) == nil)
    }

    @Test("now before week start → elapsed clamps to 0, paceDelta = utilization, no run-out")
    func elapsedClampsAtZero() throws {
        let pace = try #require(WeeklyPace(utilization: 5, resetsAt: now.addingTimeInterval(8 * day), now: now))
        #expect(pace.paceDelta == 5)
        #expect(pace.runOut == nil)
    }

    @Test("reset already passed, or passing now → no pace from a finished week")
    func resetPassedHasNoPace() {
        #expect(WeeklyPace(utilization: 80, resetsAt: now.addingTimeInterval(-hour), now: now) == nil)
        #expect(WeeklyPace(utilization: 80, resetsAt: now, now: now) == nil)
    }
}
