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

    // MARK: - Menu Bar Headroom State Tests (weekly window)

    @Test("disconnected connectionStatus → menuBarHeadroomState == .disconnected and menuBarText == em dash")
    @MainActor
    func menuBarDisconnected() {
        let state = AppState()
        // Default connectionStatus is .disconnected
        #expect(state.menuBarHeadroomState == .disconnected)
        #expect(state.menuBarText == "\u{2014}")
    }

    @Test("connected with nil sevenDay → .disconnected and em dash, even when fiveHour is present")
    @MainActor
    func menuBarConnectedNilSevenDay() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: WindowState(utilization: 17.0, resetsAt: nil), sevenDay: nil)
        #expect(state.menuBarHeadroomState == .disconnected)
        #expect(state.menuBarText == "\u{2014}")
    }

    @Test("weekly only: fiveHour nil, sevenDay 17% → 83% and .normal")
    @MainActor
    func menuBarWeeklyOnly() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 17.0, resetsAt: nil))
        #expect(state.menuBarHeadroomState == .normal)
        #expect(state.menuBarText == "83%")
    }

    @Test("5h present is ignored: fiveHour 90%, sevenDay 30% → 70%")
    @MainActor
    func menuBarIgnoresFiveHour() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(
            fiveHour: WindowState(utilization: 90.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 30.0, resetsAt: nil)
        )
        #expect(state.menuBarHeadroomState == .normal)
        #expect(state.menuBarText == "70%")
    }

    @Test("5h exhausted is ignored: weekly 40% → 60%, no countdown")
    @MainActor
    func menuBarIgnoresFiveHourExhausted() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(
            fiveHour: WindowState(utilization: 100.0, resetsAt: Date().addingTimeInterval(30 * 60)),
            sevenDay: WindowState(utilization: 40.0, resetsAt: nil)
        )
        #expect(state.menuBarHeadroomState == .normal)
        #expect(state.menuBarText == "60%")
    }

    @Test("5h and weekly both exhausted → weekly countdown, not the 5h one")
    @MainActor
    func menuBarBothExhaustedShowsWeeklyCountdown() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(
            fiveHour: WindowState(utilization: 100.0, resetsAt: Date().addingTimeInterval(20 * 60 + 30)),
            sevenDay: WindowState(utilization: 100.0, resetsAt: Date().addingTimeInterval(3 * 86400 + 4 * 3600 + 30))
        )
        #expect(state.menuBarHeadroomState == .exhausted)
        #expect(state.menuBarText == "\u{21BB} 3d 4h")
    }

    @Test("weekly utilization 65.0 → headroom 35% → .caution")
    @MainActor
    func menuBarCaution35() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 65.0, resetsAt: nil))
        #expect(state.menuBarHeadroomState == .caution)
        #expect(state.menuBarText == "35%")
    }

    @Test("weekly utilization 85.0 → headroom 15% → .warning")
    @MainActor
    func menuBarWarning15() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 85.0, resetsAt: nil))
        #expect(state.menuBarHeadroomState == .warning)
        #expect(state.menuBarText == "15%")
    }

    @Test("weekly utilization 97.0 → headroom 3% → .critical")
    @MainActor
    func menuBarCritical3() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 97.0, resetsAt: nil))
        #expect(state.menuBarHeadroomState == .critical)
        #expect(state.menuBarText == "3%")
    }

    @Test("weekly exhausted without resetsAt → 0% and .exhausted")
    @MainActor
    func menuBarExhausted0() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 100.0, resetsAt: nil))
        #expect(state.menuBarHeadroomState == .exhausted)
        #expect(state.menuBarText == "0%")
    }

    @Test("tokenExpired → .disconnected")
    @MainActor
    func menuBarTokenExpired() {
        let state = AppState()
        state.updateConnectionStatus(.tokenExpired)
        state.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 17.0, resetsAt: nil))
        #expect(state.menuBarHeadroomState == .disconnected)
        #expect(state.menuBarText == "\u{2014}")
    }

    @Test("noCredentials → .disconnected")
    @MainActor
    func menuBarNoCredentials() {
        let state = AppState()
        state.updateConnectionStatus(.noCredentials)
        #expect(state.menuBarHeadroomState == .disconnected)
        #expect(state.menuBarText == "\u{2014}")
    }

    @Test("weekly utilization > 100 clamps headroom to 0%")
    @MainActor
    func menuBarUtilizationOver100() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 110.0, resetsAt: nil))
        #expect(state.menuBarText == "0%")
    }

    // MARK: - Headroom Percentage Edge Cases

    @Test("weekly utilization 0.0 → headroom 100%")
    @MainActor
    func menuBarHeadroom100() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 0.0, resetsAt: nil))
        #expect(state.menuBarText == "100%")
    }

    @Test("weekly utilization 50.5 → headroom 49% (Int truncation)")
    @MainActor
    func menuBarHeadroomTruncation() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 50.5, resetsAt: nil))
        // Int(100 - 50.5) = Int(49.5) = 49
        #expect(state.menuBarText == "49%")
    }

    @Test("weekly utilization 99.9 → headroom 0% display (Int truncation) but .critical state (0.1% actual headroom)")
    @MainActor
    func menuBarHeadroom99_9() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 99.9, resetsAt: nil))
        // HeadroomState uses actual 0.1% headroom → 0<0.1<5 → .critical
        #expect(state.menuBarText == "0%")
        #expect(state.menuBarHeadroomState == .critical)
    }

    // MARK: - Weekly Countdown Tests

    @Test("weekly exhausted with resetsAt +3d4h → countdown ↻ 3d 4h")
    @MainActor
    func menuBarWeeklyExhaustedCountdownDays() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        let resetsAt = Date().addingTimeInterval(3 * 86400 + 4 * 3600 + 30)
        state.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 100.0, resetsAt: resetsAt))
        #expect(state.menuBarText == "\u{21BB} 3d 4h")
        #expect(state.menuBarHeadroomState == .exhausted)
    }

    @Test("weekly exhausted with resetsAt 47m → countdown ↻ 47m")
    @MainActor
    func menuBarWeeklyExhaustedCountdownMinutes() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        let resetsAt = Date().addingTimeInterval(47 * 60 + 10)
        state.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 100.0, resetsAt: resetsAt))
        #expect(state.menuBarText == "\u{21BB} 47m")
    }

    @Test("weekly recovers from exhausted → switches back to percentage")
    @MainActor
    func menuBarRecoveryFromExhausted() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        let resetsAt = Date().addingTimeInterval(2 * 86400)
        state.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 100.0, resetsAt: resetsAt))
        #expect(state.menuBarText.contains("\u{21BB}"))

        // Weekly reset: utilization drops to 5%
        state.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 5.0, resetsAt: nil))
        #expect(state.menuBarText == "95%")
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

    // MARK: - Sparkline Data Tests (Story 12.1)

    @Test("sparklineData starts empty")
    @MainActor
    func sparklineDataInitiallyEmpty() {
        let state = AppState()
        #expect(state.sparklineData.isEmpty)
    }

    @Test("hasSparklineData returns false when empty")
    @MainActor
    func hasSparklineDataFalseWhenEmpty() {
        let state = AppState()
        #expect(state.hasSparklineData == false)
    }

    @Test("hasSparklineData returns false with 1 data point")
    @MainActor
    func hasSparklineDataFalseWithOne() {
        let state = AppState()
        let poll = UsagePoll(
            id: 1,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            fiveHourUtil: 50.0,
            fiveHourResetsAt: nil,
            sevenDayUtil: 30.0,
            sevenDayResetsAt: nil
        )
        state.updateSparklineData([poll])
        #expect(state.hasSparklineData == false)
    }

    @Test("hasSparklineData returns true with 2+ data points")
    @MainActor
    func hasSparklineDataTrueWithTwo() {
        let state = AppState()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let polls = [
            UsagePoll(id: 1, timestamp: now - 60000, fiveHourUtil: 50.0, fiveHourResetsAt: nil, sevenDayUtil: 30.0, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: now, fiveHourUtil: 52.0, fiveHourResetsAt: nil, sevenDayUtil: 31.0, sevenDayResetsAt: nil)
        ]
        state.updateSparklineData(polls)
        #expect(state.hasSparklineData == true)
    }

    @Test("updateSparklineData replaces existing data")
    @MainActor
    func updateSparklineDataReplaces() {
        let state = AppState()
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        let initialPolls = [
            UsagePoll(id: 1, timestamp: now - 60000, fiveHourUtil: 50.0, fiveHourResetsAt: nil, sevenDayUtil: 30.0, sevenDayResetsAt: nil)
        ]
        state.updateSparklineData(initialPolls)
        #expect(state.sparklineData.count == 1)

        let newPolls = [
            UsagePoll(id: 2, timestamp: now - 30000, fiveHourUtil: 55.0, fiveHourResetsAt: nil, sevenDayUtil: 32.0, sevenDayResetsAt: nil),
            UsagePoll(id: 3, timestamp: now, fiveHourUtil: 60.0, fiveHourResetsAt: nil, sevenDayUtil: 35.0, sevenDayResetsAt: nil)
        ]
        state.updateSparklineData(newPolls)
        #expect(state.sparklineData.count == 2)
        #expect(state.sparklineData[0].id == 2)
    }

    @Test("sparklineData preserves timestamp ordering")
    @MainActor
    func sparklineDataPreservesOrdering() {
        let state = AppState()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let polls = [
            UsagePoll(id: 1, timestamp: now - 120000, fiveHourUtil: 50.0, fiveHourResetsAt: nil, sevenDayUtil: 30.0, sevenDayResetsAt: nil),
            UsagePoll(id: 2, timestamp: now - 60000, fiveHourUtil: 55.0, fiveHourResetsAt: nil, sevenDayUtil: 32.0, sevenDayResetsAt: nil),
            UsagePoll(id: 3, timestamp: now, fiveHourUtil: 60.0, fiveHourResetsAt: nil, sevenDayUtil: 35.0, sevenDayResetsAt: nil)
        ]
        state.updateSparklineData(polls)

        // Verify ascending order
        for i in 1..<state.sparklineData.count {
            #expect(state.sparklineData[i].timestamp > state.sparklineData[i-1].timestamp)
        }
    }

    @Test("sparklineMinDataPoints constant is 2")
    @MainActor
    func sparklineMinDataPointsConstant() {
        #expect(AppState.sparklineMinDataPoints == 2)
    }

    // MARK: - Last Poll Timestamp Tests (Story 13.9)

    @Test("lastPollTimestamp starts as nil")
    @MainActor
    func lastPollTimestampInitiallyNil() {
        let state = AppState()
        #expect(state.lastPollTimestamp == nil)
    }

    @Test("lastPollTimestamp is set on successful poll (updateWindows)")
    @MainActor
    func lastPollTimestampSetOnSuccess() {
        let state = AppState()
        #expect(state.lastPollTimestamp == nil)

        state.updateWindows(
            fiveHour: WindowState(utilization: 50.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 30.0, resetsAt: nil)
        )

        #expect(state.lastPollTimestamp != nil)
    }

    @Test("lastPollTimestamp equals lastUpdated after updateWindows")
    @MainActor
    func lastPollTimestampMatchesLastUpdated() {
        let state = AppState()
        state.updateWindows(
            fiveHour: WindowState(utilization: 50.0, resetsAt: nil),
            sevenDay: nil
        )
        #expect(state.lastPollTimestamp == state.lastUpdated)
    }

    @Test("lastPollTimestamp is NOT set by connection status changes (failed polls)")
    @MainActor
    func lastPollTimestampNotSetOnFailure() {
        let state = AppState()

        // Simulate failed poll — only connection status and status message change
        state.updateConnectionStatus(.disconnected)
        state.updateStatusMessage(StatusMessage(title: "Error", detail: "Network"))
        state.updateLastAttempted()

        #expect(state.lastPollTimestamp == nil, "Failed polls must not set lastPollTimestamp")
    }

    @Test("lastPollTimestamp advances on each successful poll")
    @MainActor
    func lastPollTimestampAdvancesOnEachPoll() {
        let state = AppState()

        state.updateWindows(
            fiveHour: WindowState(utilization: 50.0, resetsAt: nil),
            sevenDay: nil
        )
        let firstTimestamp = state.lastPollTimestamp

        let fiveHour = WindowState(utilization: 55.0, resetsAt: nil)
        state.updateWindows(fiveHour: fiveHour, sevenDay: nil)
        let secondTimestamp = state.lastPollTimestamp

        #expect(firstTimestamp != nil)
        #expect(secondTimestamp != nil)
        #expect(secondTimestamp! >= firstTimestamp!)
    }

    // MARK: - Analytics Window State Tests (Story 12.3)

    @Test("isAnalyticsWindowOpen starts as false")
    @MainActor
    func analyticsWindowInitiallyFalse() {
        let state = AppState()
        #expect(state.isAnalyticsWindowOpen == false)
    }

    @Test("setAnalyticsWindowOpen(true) sets property to true")
    @MainActor
    func setAnalyticsWindowOpenTrue() {
        let state = AppState()
        state.setAnalyticsWindowOpen(true)
        #expect(state.isAnalyticsWindowOpen == true)
    }

    @Test("setAnalyticsWindowOpen(false) sets property to false")
    @MainActor
    func setAnalyticsWindowOpenFalse() {
        let state = AppState()
        state.setAnalyticsWindowOpen(true)
        state.setAnalyticsWindowOpen(false)
        #expect(state.isAnalyticsWindowOpen == false)
    }

    // MARK: - Extra Usage State Tests (Story 17.1)

    @Test("isExtraUsageActive returns false when enabled and only 5h exhausted (weekly drives the menu bar)")
    @MainActor
    func extraUsageInactiveWhenOnly5hExhausted() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateExtraUsage(enabled: true, monthlyLimit: 100.0, usedCredits: 15.0, utilization: 0.15)
        state.updateWindows(
            fiveHour: WindowState(utilization: 100.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 70.0, resetsAt: nil)
        )
        #expect(state.isExtraUsageActive == false)
        #expect(state.menuBarText == "30%")
    }

    @Test("isExtraUsageActive returns true when enabled AND weekly exhausted")
    @MainActor
    func extraUsageActiveWhenWeeklyExhausted() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateExtraUsage(enabled: true, monthlyLimit: 100.0, usedCredits: 15.0, utilization: 0.15)
        state.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 100.0, resetsAt: Date().addingTimeInterval(3 * 86400))
        )
        #expect(state.isExtraUsageActive == true)
        #expect(state.menuBarText == "$0.85")
    }

    @Test("isExtraUsageActive returns false when enabled but no window exhausted")
    @MainActor
    func extraUsageInactiveWhenNoExhausted() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateExtraUsage(enabled: true, monthlyLimit: 10000.0, usedCredits: 1500.0, utilization: 0.15)
        state.updateWindows(
            fiveHour: WindowState(utilization: 50.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 70.0, resetsAt: nil)
        )
        #expect(state.isExtraUsageActive == false)
    }

    @Test("isExtraUsageActive returns false when disabled even if exhausted")
    @MainActor
    func extraUsageInactiveWhenDisabled() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateExtraUsage(enabled: false, monthlyLimit: nil, usedCredits: nil, utilization: nil)
        state.updateWindows(
            fiveHour: WindowState(utilization: 100.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 100.0, resetsAt: nil)
        )
        #expect(state.isExtraUsageActive == false)
    }

    @Test("extraUsageRemainingBalanceCents computes correctly")
    @MainActor
    func extraUsageRemainingBalanceComputation() {
        let state = AppState()
        state.updateExtraUsage(enabled: true, monthlyLimit: 10000.0, usedCredits: 2739.0, utilization: 0.2739)
        #expect(state.extraUsageRemainingBalanceCents == 7261)
    }

    @Test("extraUsageRemainingBalanceCents returns nil when limit is nil")
    @MainActor
    func extraUsageRemainingBalanceNilWithoutLimit() {
        let state = AppState()
        state.updateExtraUsage(enabled: true, monthlyLimit: nil, usedCredits: 1500.0, utilization: nil)
        #expect(state.extraUsageRemainingBalanceCents == nil)
    }

    @Test("menuBarText returns currency format when extra usage active with known limit")
    @MainActor
    func menuBarTextExtraUsageCurrency() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateExtraUsage(enabled: true, monthlyLimit: 10000.0, usedCredits: 7261.0, utilization: 0.7261)
        state.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 100.0, resetsAt: nil)
        )
        #expect(state.menuBarText == "$27.39")
    }

    @Test("menuBarText returns spent format when extra usage active with no limit")
    @MainActor
    func menuBarTextExtraUsageSpent() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateExtraUsage(enabled: true, monthlyLimit: nil, usedCredits: 1561.0, utilization: nil)
        state.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 100.0, resetsAt: nil)
        )
        #expect(state.menuBarText == "$15.61 spent")
    }

    @Test("menuBarText returns normal headroom when extra usage inactive")
    @MainActor
    func menuBarTextNormalWhenExtraUsageInactive() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateExtraUsage(enabled: true, monthlyLimit: 10000.0, usedCredits: 1500.0, utilization: 0.15)
        state.updateWindows(
            fiveHour: WindowState(utilization: 50.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 70.0, resetsAt: nil)
        )
        #expect(state.menuBarText == "30%")
    }

    @Test("updateExtraUsage clears previous values when called with nil")
    @MainActor
    func updateExtraUsageClearsValues() {
        let state = AppState()
        state.updateExtraUsage(enabled: true, monthlyLimit: 10000.0, usedCredits: 5000.0, utilization: 0.5)
        #expect(state.extraUsageEnabled == true)
        #expect(state.extraUsageMonthlyLimitCents == 10000)

        state.updateExtraUsage(enabled: false, monthlyLimit: nil, usedCredits: nil, utilization: nil)
        #expect(state.extraUsageEnabled == false)
        #expect(state.extraUsageMonthlyLimitCents == nil)
        #expect(state.extraUsageUsedCreditsCents == nil)
        #expect(state.extraUsageUtilization == nil)
    }

    @Test("menuBarText formats negative remaining balance with leading minus sign")
    @MainActor
    func menuBarTextNegativeRemainingBalance() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        // usedCredits exceeds monthlyLimit (in cents)
        state.updateExtraUsage(enabled: true, monthlyLimit: 10000.0, usedCredits: 10523.0, utilization: 1.0523)
        state.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 100.0, resetsAt: nil)
        )
        #expect(state.menuBarText == "-$5.23")
    }

    @Test("menuBarExtraUsageText returns fallback when active but no credits data")
    @MainActor
    func menuBarExtraUsageTextFallbackWhenNilCredits() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.updateExtraUsage(enabled: true, monthlyLimit: nil, usedCredits: nil, utilization: nil)
        state.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 100.0, resetsAt: nil)
        )
        #expect(state.menuBarExtraUsageText == "$0.00")
        #expect(state.menuBarText == "$0.00")
    }
}
