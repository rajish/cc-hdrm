import Foundation
import Testing
@testable import cc_hdrm

@Suite("AppState Tests")
struct AppStateTests {

    // MARK: - Default State Tests

    @Test("default connectionStatus is .disconnected")
    @MainActor
    func defaultConnectionStatus() {
        let state = AppState()
        #expect(state.connectionStatus == .disconnected)
    }

    @Test("default fiveHour is nil")
    @MainActor
    func defaultFiveHourIsNil() {
        let state = AppState()
        #expect(state.fiveHour == nil)
    }

    @Test("default sevenDay is nil")
    @MainActor
    func defaultSevenDayIsNil() {
        let state = AppState()
        #expect(state.sevenDay == nil)
    }

    @Test("default lastUpdated is nil")
    @MainActor
    func defaultLastUpdatedIsNil() {
        let state = AppState()
        #expect(state.lastUpdated == nil)
    }

    @Test("default subscriptionTier is nil")
    @MainActor
    func defaultSubscriptionTierIsNil() {
        let state = AppState()
        #expect(state.subscriptionTier == nil)
    }

    // MARK: - WindowState Derived HeadroomState Tests

    @Test("WindowState derives headroomState from utilization")
    func windowStateDeriveHeadroomState() {
        let window = WindowState(utilization: 83, resetsAt: nil)
        #expect(window.headroomState == .warning)
    }

    @Test("WindowState with low utilization derives .normal")
    func windowStateNormal() {
        let window = WindowState(utilization: 30, resetsAt: nil)
        #expect(window.headroomState == .normal)
    }

    @Test("WindowState with high utilization derives .critical")
    func windowStateCritical() {
        let window = WindowState(utilization: 97, resetsAt: nil)
        #expect(window.headroomState == .critical)
    }

    // MARK: - ConnectionStatus Enum Tests

    @Test("ConnectionStatus has all expected cases")
    func connectionStatusCases() {
        let cases: [ConnectionStatus] = [.connected, .disconnected, .tokenExpired, .noCredentials]
        #expect(cases.count == 4)
    }

    // MARK: - Mutation via Methods Tests

    @Test("updateWindows sets fiveHour and sevenDay and lastUpdated")
    @MainActor
    func updateWindowsSetsValues() {
        let state = AppState()
        let fiveHour = WindowState(utilization: 50, resetsAt: nil)
        let sevenDay = WindowState(utilization: 70, resetsAt: Date())

        state.updateWindows(fiveHour: fiveHour, sevenDay: sevenDay)

        #expect(state.fiveHour?.utilization == 50)
        #expect(state.sevenDay?.utilization == 70)
        #expect(state.lastUpdated != nil)
    }

    @Test("updateConnectionStatus changes status")
    @MainActor
    func updateConnectionStatusWorks() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        #expect(state.connectionStatus == .connected)
    }

    @Test("updateSubscriptionTier changes tier")
    @MainActor
    func updateSubscriptionTierWorks() {
        let state = AppState()
        state.updateSubscriptionTier("pro")
        #expect(state.subscriptionTier == "pro")
    }

    // MARK: - StatusMessage Tests

    @Test("default statusMessage is nil")
    @MainActor
    func defaultStatusMessageIsNil() {
        let state = AppState()
        #expect(state.statusMessage == nil)
    }

    @Test("updateStatusMessage sets title and detail")
    @MainActor
    func updateStatusMessageSetsValues() {
        let state = AppState()
        state.updateStatusMessage(StatusMessage(title: "No Claude credentials found", detail: "Run Claude Code to create them"))
        #expect(state.statusMessage == StatusMessage(title: "No Claude credentials found", detail: "Run Claude Code to create them"))
    }

    @Test("updateStatusMessage clears with nil")
    @MainActor
    func updateStatusMessageClearsWithNil() {
        let state = AppState()
        state.updateStatusMessage(StatusMessage(title: "title", detail: "detail"))
        state.updateStatusMessage(nil)
        #expect(state.statusMessage == nil)
    }

    // MARK: - DataFreshness Derived Property Tests

    @Test("dataFreshness returns .unknown when lastUpdated is nil")
    @MainActor
    func dataFreshnessUnknownWhenNilLastUpdated() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        #expect(state.dataFreshness == .unknown)
    }

    @Test("dataFreshness returns .fresh when lastUpdated is recent and connected")
    @MainActor
    func dataFreshnessFreshWhenRecentAndConnected() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 50, resetsAt: nil), sevenDay: nil)
        #expect(state.dataFreshness == .fresh)
    }

    @Test("dataFreshness returns .unknown when disconnected regardless of lastUpdated")
    @MainActor
    func dataFreshnessUnknownWhenDisconnected() {
        let state = AppState()
        // Update windows to set lastUpdated, then disconnect
        state.updateWindows(fiveHour: WindowState(utilization: 50, resetsAt: nil), sevenDay: nil)
        state.updateConnectionStatus(.disconnected)
        #expect(state.dataFreshness == .unknown)
    }

    @Test("dataFreshness returns .veryStale when lastUpdated is old and connected")
    @MainActor
    func dataFreshnessVeryStaleWhenOldAndConnected() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.setLastUpdated(Date().addingTimeInterval(-600))
        #expect(state.dataFreshness == .veryStale)
    }

    // MARK: - Menu Bar Headroom State Tests (Task 7)

    @Test("disconnected connectionStatus → menuBarHeadroomState == .disconnected and menuBarText == sparkle em dash")
    @MainActor
    func menuBarDisconnected() {
        let state = AppState()
        // Default connectionStatus is .disconnected
        #expect(state.menuBarHeadroomState == .disconnected)
        #expect(state.menuBarText == "\u{2733} \u{2014}")
    }

    @Test("connected with nil fiveHour → .disconnected")
    @MainActor
    func menuBarConnectedNilFiveHour() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        #expect(state.menuBarHeadroomState == .disconnected)
        #expect(state.menuBarText == "\u{2733} \u{2014}")
    }

    @Test("connected with utilization 17.0 → headroom 83% → .normal")
    @MainActor
    func menuBarNormal83() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 17.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarHeadroomState == .normal)
        #expect(state.menuBarText == "\u{2733} 83%")
    }

    @Test("connected with utilization 65.0 → headroom 35% → .caution")
    @MainActor
    func menuBarCaution35() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 65.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarHeadroomState == .caution)
        #expect(state.menuBarText == "\u{2733} 35%")
    }

    @Test("connected with utilization 85.0 → headroom 15% → .warning")
    @MainActor
    func menuBarWarning15() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 85.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarHeadroomState == .warning)
        #expect(state.menuBarText == "\u{2733} 15%")
    }

    @Test("connected with utilization 97.0 → headroom 3% → .critical")
    @MainActor
    func menuBarCritical3() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 97.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarHeadroomState == .critical)
        #expect(state.menuBarText == "\u{2733} 3%")
    }

    @Test("connected with utilization 100.0 → headroom 0% → .exhausted")
    @MainActor
    func menuBarExhausted0() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 100.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarHeadroomState == .exhausted)
        #expect(state.menuBarText == "\u{2733} 0%")
    }

    @Test("tokenExpired → .disconnected")
    @MainActor
    func menuBarTokenExpired() {
        let state = AppState()
        state.updateConnectionStatus(.tokenExpired)
        #expect(state.menuBarHeadroomState == .disconnected)
        #expect(state.menuBarText == "\u{2733} \u{2014}")
    }

    @Test("noCredentials → .disconnected")
    @MainActor
    func menuBarNoCredentials() {
        let state = AppState()
        state.updateConnectionStatus(.noCredentials)
        #expect(state.menuBarHeadroomState == .disconnected)
        #expect(state.menuBarText == "\u{2733} \u{2014}")
    }

    @Test("utilization > 100 clamps headroom to 0%")
    @MainActor
    func menuBarUtilizationOver100() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 110.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarText == "\u{2733} 0%")
    }

    // MARK: - Headroom Percentage Edge Cases (Task 9)

    @Test("utilization 0.0 → headroom 100%")
    @MainActor
    func menuBarHeadroom100() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 0.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarText == "\u{2733} 100%")
    }

    @Test("utilization 50.5 → headroom 49% (Int truncation)")
    @MainActor
    func menuBarHeadroomTruncation() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 50.5, resetsAt: nil), sevenDay: nil)
        // Int(100 - 50.5) = Int(49.5) = 49
        #expect(state.menuBarText == "\u{2733} 49%")
    }

    @Test("utilization 99.9 → headroom 0% display (Int truncation) but .critical state (0.1% actual headroom)")
    @MainActor
    func menuBarHeadroom99_9() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 99.9, resetsAt: nil), sevenDay: nil)
        // Int(100 - 99.9) = Int(0.1) = 0 for display
        // But HeadroomState uses actual 0.1% headroom → 0<0.1<5 → .critical
        #expect(state.menuBarText == "\u{2733} 0%")
        #expect(state.menuBarHeadroomState == .critical)
    }

    // MARK: - Context-Adaptive Display Tests (Story 3.2, Task 8)

    @Test("5h exhausted with resetsAt 47m → countdown text")
    @MainActor
    func menuBarExhaustedWithCountdown() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        let resetsAt = Date().addingTimeInterval(47 * 60 + 10)
        state.updateWindows(fiveHour: WindowState(utilization: 100.0, resetsAt: resetsAt), sevenDay: nil)
        #expect(state.menuBarText == "\u{2733} \u{21BB} 47m")
        #expect(state.menuBarHeadroomState == .exhausted)
    }

    @Test("5h exhausted with resetsAt nil → fallback to percentage 0%")
    @MainActor
    func menuBarExhaustedNoResetsAt() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 100.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarText == "\u{2733} 0%")
    }

    @Test("5h normal utilization 17 → unchanged 83%")
    @MainActor
    func menuBarNormalUnchanged() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 17.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarText == "\u{2733} 83%")
    }

    @Test("5h recovers from exhausted → switches back to percentage")
    @MainActor
    func menuBarRecoveryFromExhausted() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        let resetsAt = Date().addingTimeInterval(30 * 60)
        state.updateWindows(fiveHour: WindowState(utilization: 100.0, resetsAt: resetsAt), sevenDay: nil)
        #expect(state.menuBarText.contains("\u{21BB}"))

        // Recovery: utilization drops to 5%
        state.updateWindows(fiveHour: WindowState(utilization: 5.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarText == "\u{2733} 95%")
    }

    // MARK: - Tighter Constraint Promotion Tests (Story 3.2, Task 9)

    @Test("5h 72% normal, 7d 18% warning → promotes 7d")
    @MainActor
    func promotionSevenDayWarning() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        // 5h: utilization 28 → headroom 72% → .normal
        // 7d: utilization 82 → headroom 18% → .warning
        state.updateWindows(
            fiveHour: WindowState(utilization: 28.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 82.0, resetsAt: nil)
        )
        #expect(state.menuBarHeadroomState == .warning)
        #expect(state.menuBarText == "\u{2733} 18%")
        #expect(state.displayedWindow == .sevenDay)
    }

    @Test("5h 72% normal, 7d 4% critical → promotes 7d")
    @MainActor
    func promotionSevenDayCritical() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(
            fiveHour: WindowState(utilization: 28.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 96.0, resetsAt: nil)
        )
        #expect(state.menuBarHeadroomState == .critical)
        #expect(state.menuBarText == "\u{2733} 4%")
        #expect(state.displayedWindow == .sevenDay)
    }

    @Test("5h 35% caution, 7d 30% caution → stays on 5h (7d not warning/critical)")
    @MainActor
    func noPromotionSevenDayCaution() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        // 5h: utilization 65 → headroom 35% → .caution
        // 7d: utilization 70 → headroom 30% → .caution
        state.updateWindows(
            fiveHour: WindowState(utilization: 65.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 70.0, resetsAt: nil)
        )
        #expect(state.menuBarHeadroomState == .caution)
        #expect(state.displayedWindow == .fiveHour)
    }

    @Test("5h 12% warning, 7d 18% warning → stays on 5h (7d headroom > 5h headroom)")
    @MainActor
    func noPromotionSevenDayHigherHeadroom() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        // 5h: utilization 88 → headroom 12% → .warning
        // 7d: utilization 82 → headroom 18% → .warning
        state.updateWindows(
            fiveHour: WindowState(utilization: 88.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 82.0, resetsAt: nil)
        )
        #expect(state.menuBarHeadroomState == .warning)
        #expect(state.displayedWindow == .fiveHour)
    }

    @Test("5h 72%, 7d nil → stays on 5h")
    @MainActor
    func noPromotionSevenDayNil() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(
            fiveHour: WindowState(utilization: 28.0, resetsAt: nil),
            sevenDay: nil
        )
        #expect(state.displayedWindow == .fiveHour)
    }

    @Test("7d recovers → reverts to 5h display")
    @MainActor
    func promotionRevertsOnRecovery() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        // Initially 7d is warning with lower headroom
        state.updateWindows(
            fiveHour: WindowState(utilization: 28.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 82.0, resetsAt: nil)
        )
        #expect(state.displayedWindow == .sevenDay)

        // 7d recovers to 50% headroom (utilization 50)
        state.updateWindows(
            fiveHour: WindowState(utilization: 28.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 50.0, resetsAt: nil)
        )
        #expect(state.displayedWindow == .fiveHour)
    }

    @Test("both 5h and 7d exhausted → stays on 5h (countdown more useful)")
    @MainActor
    func bothExhausted() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        let resetsAt5h = Date().addingTimeInterval(20 * 60)
        let resetsAt7d = Date().addingTimeInterval(3 * 3600)
        state.updateWindows(
            fiveHour: WindowState(utilization: 100.0, resetsAt: resetsAt5h),
            sevenDay: WindowState(utilization: 100.0, resetsAt: resetsAt7d)
        )
        // Both exhausted, headroom both 0% — 7d headroom (0) is NOT < 5h headroom (0), so no promotion
        #expect(state.displayedWindow == .fiveHour)
        #expect(state.menuBarHeadroomState == .exhausted)
        #expect(state.menuBarText.contains("\u{21BB}"), "Should show countdown for 5h")
    }

    @Test("5h exhausted, 7d warning → stays on 5h (exhausted countdown takes priority)")
    @MainActor
    func fiveHourExhaustedSevenDayWarning() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        let resetsAt = Date().addingTimeInterval(30 * 60)
        // 5h: utilization 100 → headroom 0% → .exhausted
        // 7d: utilization 85 → headroom 15% → .warning
        state.updateWindows(
            fiveHour: WindowState(utilization: 100.0, resetsAt: resetsAt),
            sevenDay: WindowState(utilization: 85.0, resetsAt: nil)
        )
        // 7d headroom (15%) > 5h headroom (0%) → 7d headroom is NOT lower, no promotion
        #expect(state.displayedWindow == .fiveHour)
        #expect(state.menuBarHeadroomState == .exhausted)
        #expect(state.menuBarText.contains("\u{21BB}"), "Should show 5h countdown, not 7d percentage")
    }

    // MARK: - Countdown Tick Tests (Story 3.2)

    @Test("tickCountdown increments countdownTick")
    @MainActor
    func tickCountdownIncrements() {
        let state = AppState()
        #expect(state.countdownTick == 0)
        state.tickCountdown()
        #expect(state.countdownTick == 1)
        state.tickCountdown()
        #expect(state.countdownTick == 2)
    }
}
