import Foundation
import Testing
@testable import cc_hdrm

@Suite("AppState Weekly Pace Menu Bar")
@MainActor
struct AppStateWeeklyPaceTests {

    private func connectedState(utilization: Double, resetsIn: TimeInterval?) -> AppState {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: utilization, resetsAt: resetsIn.map { Date().addingTimeInterval($0) })
        )
        return appState
    }

    @Test("ahead of pace with run-out before reset → \"40% ↗\"")
    func aheadShowsArrow() {
        let appState = connectedState(utilization: 60, resetsIn: 4 * 86400)
        #expect(appState.weeklyPace?.runOut != nil)
        #expect(appState.menuBarText == "40% \u{2197}")
    }

    @Test("ahead of pace in the critical band → \"3% ↗\"")
    func aheadInCriticalBandShowsArrow() {
        let appState = connectedState(utilization: 97, resetsIn: 4 * 86400)
        #expect(appState.sevenDay?.headroomState == .critical)
        #expect(appState.weeklyPace?.runOut != nil)
        #expect(appState.menuBarText == "3% \u{2197}")
    }

    @Test("behind pace → no arrow")
    func behindHasNoArrow() {
        let appState = connectedState(utilization: 20, resetsIn: 2 * 86400)
        #expect(appState.weeklyPace?.runOut == nil)
        #expect(appState.menuBarText == "80%")
    }

    @Test("ahead of pace in the first 4h → pace exists but no run-out, so no arrow")
    func firstHoursHaveNoArrow() throws {
        let appState = connectedState(utilization: 10, resetsIn: 7 * 86400 - 2 * 3600)
        let pace = try #require(appState.weeklyPace)
        #expect(pace.paceDelta > 0)
        #expect(pace.runOut == nil)
        #expect(appState.menuBarText == "90%")
    }

    @Test("missing resets_at → no pace, no arrow")
    func missingResetsAtHasNoArrow() {
        let appState = connectedState(utilization: 60, resetsIn: nil)
        #expect(appState.weeklyPace == nil)
        #expect(appState.menuBarText == "40%")
    }

    @Test("exhausted → countdown, no arrow")
    func exhaustedHasNoArrow() {
        let appState = connectedState(utilization: 100, resetsIn: 2 * 86400)
        #expect(appState.weeklyPace == nil)
        #expect(appState.menuBarText.hasPrefix("\u{21BB}"))
        #expect(!appState.menuBarText.contains("\u{2197}"))
    }

    @Test("disconnected → em dash, no arrow")
    func disconnectedHasNoArrow() {
        let appState = connectedState(utilization: 60, resetsIn: 4 * 86400)
        appState.updateConnectionStatus(.disconnected)
        #expect(appState.menuBarText == "\u{2014}")
    }
}
