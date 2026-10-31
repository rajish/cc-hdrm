import AppKit
import Foundation
import SwiftUI
import Testing
@testable import cc_hdrm

// MARK: - Mock Polling Engine

private final class MockPollingEngine: PollingEngineProtocol {
    var startCallCount = 0
    var stopCallCount = 0
    var restartPollingCallCount = 0

    func start() async {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func restartPolling() {
        restartPollingCallCount += 1
    }

    var performForcedPollCallCount = 0
    func performForcedPoll() async {
        performForcedPollCallCount += 1
    }
}

// MARK: - Mock Freshness Monitor

private final class MockFreshnessMonitor: FreshnessMonitorProtocol {
    var startCallCount = 0
    var stopCallCount = 0
    var checkFreshnessCallCount = 0

    func start() async {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func checkFreshness() {
        checkFreshnessCallCount += 1
    }
}

// MARK: - AppDelegate Tests

@Suite("AppDelegate Lifecycle Tests")
struct AppDelegateTests {

    @Test("AppDelegate creates with injected polling engine")
    @MainActor
    func initWithPollingEngine() async {
        let mockEngine = MockPollingEngine()
        _ = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        // Verify delegate was created — polling engine not started yet (only starts in applicationDidFinishLaunching)
        #expect(mockEngine.startCallCount == 0)
    }

    @Test("applicationWillTerminate stops the polling engine")
    @MainActor
    func terminateStopsPollingEngine() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        // Give the Task a moment to call start()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(mockEngine.startCallCount == 1, "Polling engine should be started on launch")

        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(mockEngine.stopCallCount == 1, "Polling engine should be stopped on terminate")
    }

    @Test("applicationDidFinishLaunching creates AppState")
    @MainActor
    func launchCreatesAppState() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        #expect(delegate.appState == nil)

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        #expect(delegate.appState != nil, "AppState should be created on launch")
    }

    @Test("applicationDidFinishLaunching starts FreshnessMonitor")
    @MainActor
    func launchStartsFreshnessMonitor() async {
        let mockEngine = MockPollingEngine()
        let mockMonitor = MockFreshnessMonitor()
        let delegate = AppDelegate(pollingEngine: mockEngine, freshnessMonitor: mockMonitor, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        // Give Tasks a moment to execute
        try? await Task.sleep(for: .milliseconds(50))
        #expect(mockMonitor.startCallCount == 1, "FreshnessMonitor should be started on launch")
    }

    @Test("applicationWillTerminate stops FreshnessMonitor")
    @MainActor
    func terminateStopsFreshnessMonitor() async {
        let mockEngine = MockPollingEngine()
        let mockMonitor = MockFreshnessMonitor()
        let delegate = AppDelegate(pollingEngine: mockEngine, freshnessMonitor: mockMonitor, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try? await Task.sleep(for: .milliseconds(50))

        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(mockMonitor.stopCallCount == 1, "FreshnessMonitor should be stopped on terminate")
    }
}

// MARK: - Popover Tests (Story 4.1)

@Suite("AppDelegate Popover Tests")
struct AppDelegatePopoverTests {

    @Test("After launch, popover is non-nil")
    @MainActor
    func popoverCreatedOnLaunch() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        #expect(delegate.popover != nil, "Popover should be created during launch")
    }

    @Test("After launch, button action is set to togglePopover: selector")
    @MainActor
    func buttonActionWiredToToggle() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        let action = delegate.statusItem?.button?.action
        #expect(action == #selector(AppDelegate.togglePopover(_:)), "Button action should be togglePopover:")
    }

    @Test("Popover behavior is transient (AC #4)")
    @MainActor
    func popoverBehaviorIsTransient() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        #expect(delegate.popover?.behavior == .transient, "Popover behavior should be .transient for auto-dismiss")
    }

    @Test("Popover contentViewController is set with NSHostingController")
    @MainActor
    func popoverHasHostingController() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        #expect(delegate.popover?.contentViewController != nil, "Popover should have a content view controller")
        #expect(delegate.popover?.contentViewController is NSHostingController<PopoverView>,
                "Content view controller should be NSHostingController<PopoverView>")
    }

    @Test("togglePopover does not crash when popover is not shown (headless CI)")
    @MainActor
    func togglePopoverCallDoesNotCrash() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        // Popover starts not shown
        #expect(delegate.popover?.isShown == false, "Popover should start closed")

        // Call togglePopover — in headless CI, show() may silently fail (no status bar),
        // but the method must not crash and the popover object must remain valid.
        delegate.togglePopover(nil)
        #expect(delegate.popover != nil, "Popover should still be valid after toggle attempt")

        // Call again to exercise the close path
        delegate.togglePopover(nil)
        #expect(delegate.popover != nil, "Popover should still be valid after second toggle")
    }
}

// MARK: - PreferencesManager Wiring Tests (Story 6.2)

@Suite("AppDelegate PreferencesManager Wiring Tests")
struct AppDelegatePreferencesManagerTests {

    @Test("applicationDidFinishLaunching creates PreferencesManager instance")
    @MainActor
    func launchCreatesPreferencesManager() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        #expect(delegate.preferencesManager == nil, "PreferencesManager should be nil before launch")

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        #expect(delegate.preferencesManager != nil, "PreferencesManager should be created during launch")
    }

    @Test("Popover contentViewController hosts PopoverView wired with PreferencesManager")
    @MainActor
    func popoverReceivesPreferencesManager() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        // Verify popover hosts a PopoverView (which requires preferencesManager in its init)
        let hostingController = delegate.popover?.contentViewController as? NSHostingController<PopoverView>
        #expect(hostingController != nil, "Popover should host PopoverView (which requires preferencesManager)")
    }
}

// MARK: - LaunchAtLoginService Wiring Tests (Story 6.4)

@Suite("AppDelegate LaunchAtLoginService Wiring Tests")
struct AppDelegateLaunchAtLoginTests {

    @Test("applicationDidFinishLaunching creates LaunchAtLoginService when not injected")
    @MainActor
    func launchCreatesLaunchAtLoginService() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        #expect(delegate.launchAtLoginService == nil, "launchAtLoginService should be nil before launch")

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        #expect(delegate.launchAtLoginService != nil, "launchAtLoginService should be created during launch")
    }

    @Test("applicationDidFinishLaunching uses injected LaunchAtLoginService")
    @MainActor
    func launchUsesInjectedService() async {
        let mockEngine = MockPollingEngine()
        let mockLaunch = MockLaunchAtLoginService()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService(), launchAtLoginService: mockLaunch)

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        #expect(delegate.launchAtLoginService === mockLaunch, "Should use the injected mock, not create a new one")
    }
}

// MARK: - Menu Bar Display Tests (weekly window)

@Suite("AppDelegate Menu Bar Display Tests")
struct AppDelegateMenuBarTests {

    /// Launches a delegate with mocks and returns it with its AppState.
    @MainActor
    private func launchedDelegate() async -> (AppDelegate, AppState)? {
        let delegate = AppDelegate(pollingEngine: MockPollingEngine(), notificationService: MockNotificationService())
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try? await Task.sleep(for: .milliseconds(50))
        guard let appState = delegate.appState else { return nil }
        return (delegate, appState)
    }

    @Test("five_hour null with weekly data → title shows weekly headroom, not em dash")
    @MainActor
    func updateMenuBarDisplayShowsWeeklyWhenFiveHourNull() async {
        guard let (delegate, appState) = await launchedDelegate() else {
            #expect(Bool(false), "AppState should exist after launch")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 17.0, resetsAt: nil))
        delegate.updateMenuBarDisplay()

        let title = delegate.statusItem?.button?.attributedTitle
        #expect(title?.string == "83%", "attributedTitle text should reflect 83% weekly headroom")
        let color = title?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.headroomColor(for: .normal))
    }

    @Test("5h present is ignored in the title")
    @MainActor
    func updateMenuBarDisplayIgnoresFiveHour() async {
        guard let (delegate, appState) = await launchedDelegate() else {
            #expect(Bool(false), "AppState should exist after launch")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 90.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 30.0, resetsAt: nil)
        )
        delegate.updateMenuBarDisplay()

        #expect(delegate.statusItem?.button?.attributedTitle.string == "70%")
    }

    @Test("connected without weekly data → em dash and disconnected icon")
    @MainActor
    func noWeeklyDataShowsDisconnected() async {
        guard let (delegate, appState) = await launchedDelegate() else {
            #expect(Bool(false), "AppState should exist after launch")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: WindowState(utilization: 17.0, resetsAt: nil), sevenDay: nil)
        delegate.updateMenuBarDisplay()

        #expect(delegate.statusItem?.button?.attributedTitle.string == "\u{2014}")
        #expect(delegate.statusItem?.button?.image?.tiffRepresentation == makeDisconnectedIcon().tiffRepresentation)
    }

    @Test("status item button has accessibilityLabel set with 'cc-hdrm:' prefix")
    @MainActor
    func statusItemHasAccessibilityLabel() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        delegate.updateMenuBarDisplay()

        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label != nil, "accessibilityLabel should be set")
        #expect(label?.hasPrefix("cc-hdrm:") == true, "accessibilityLabel should start with 'cc-hdrm:'")
    }

    @Test("VoiceOver speaks weekly headroom")
    @MainActor
    func accessibilityValueSpeaksWeeklyHeadroom() async {
        guard let (delegate, appState) = await launchedDelegate() else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 17.0, resetsAt: nil))
        delegate.updateMenuBarDisplay()

        let value = delegate.statusItem?.button?.accessibilityValue() as? String
        #expect(value == "cc-hdrm: Claude weekly headroom: 83 percent, normal")
        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label == "cc-hdrm: Claude weekly headroom: 83 percent, normal")
    }

    // MARK: - Exhausted

    @Test("weekly exhausted with resetsAt → title ↻ 3d 4h and VoiceOver names the weekly countdown")
    @MainActor
    func weeklyExhaustedWithResetsAt() async {
        guard let (delegate, appState) = await launchedDelegate() else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        let resetsAt = Date().addingTimeInterval(3 * 86400 + 4 * 3600 + 30)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 100.0, resetsAt: resetsAt))
        delegate.updateMenuBarDisplay()

        #expect(delegate.statusItem?.button?.attributedTitle.string == "\u{21BB} 3d 4h")
        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label == "cc-hdrm: Claude weekly allowance exhausted, resets in 3 days 4 hours")
    }

    @Test("weekly exhausted without resetsAt → accessibility says exhausted without 'resets in'")
    @MainActor
    func weeklyExhaustedWithoutResetsAt() async {
        guard let (delegate, appState) = await launchedDelegate() else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 100.0, resetsAt: nil))
        delegate.updateMenuBarDisplay()

        #expect(delegate.statusItem?.button?.attributedTitle.string == "0%")
        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label == "cc-hdrm: Claude weekly allowance exhausted")
    }

    @Test("weekly exhausted with extra usage enabled → $ text and extra-usage icon")
    @MainActor
    func weeklyExhaustedExtraUsage() async {
        guard let (delegate, appState) = await launchedDelegate() else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateExtraUsage(enabled: true, monthlyLimit: 10000.0, usedCredits: 2739.0, utilization: 0.2739)
        appState.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 100.0, resetsAt: Date().addingTimeInterval(3 * 86400))
        )
        delegate.updateMenuBarDisplay()

        #expect(delegate.statusItem?.button?.attributedTitle.string == "$72.61")
        let expectedIcon = GaugeIcon.makeExtraUsage(remainingFraction: 0.7261, utilization: 0.2739)
        #expect(delegate.statusItem?.button?.image?.tiffRepresentation == expectedIcon.tiffRepresentation)
    }

    @Test("attributedTitle uses correct font weight for weekly state")
    @MainActor
    func attributedTitleUsesCorrectFontWeight() async {
        guard let (delegate, appState) = await launchedDelegate() else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        // Critical state (bold weight expected)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 97.0, resetsAt: nil))
        delegate.updateMenuBarDisplay()

        let title = delegate.statusItem?.button?.attributedTitle
        #expect(title != nil, "attributedTitle should be set")

        let expectedFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        if let font = title?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            #expect(font.fontName == expectedFont.fontName, "Critical state should use bold weight")
        }
    }

    // MARK: - Weekly Pace

    @Test("ahead of weekly pace → title shows ↗ and VoiceOver says ahead of pace, without a run-out time")
    @MainActor
    func paceAheadShowsArrowAndSpokenPace() async {
        guard let (delegate, appState) = await launchedDelegate() else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        // 60% used with 3 of 7 days elapsed → run-out in ~2 days, before the reset in 4 days
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 60.0, resetsAt: Date().addingTimeInterval(4 * 86400)))
        delegate.updateMenuBarDisplay()

        #expect(delegate.statusItem?.button?.attributedTitle.string == "40% \u{2197}")
        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label == "cc-hdrm: Claude weekly headroom: 40 percent, caution, ahead of pace")
        #expect(label?.contains("runs out") == false)
        let value = delegate.statusItem?.button?.accessibilityValue() as? String
        #expect(value == label)
    }

    @Test("behind weekly pace → no arrow and no pace clause")
    @MainActor
    func paceBehindHasNoArrow() async {
        guard let (delegate, appState) = await launchedDelegate() else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        // 17% used with 4 of 7 days elapsed → well behind an even pace
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 17.0, resetsAt: Date().addingTimeInterval(3 * 86400)))
        delegate.updateMenuBarDisplay()

        #expect(delegate.statusItem?.button?.attributedTitle.string == "83%")
        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label == "cc-hdrm: Claude weekly headroom: 83 percent, normal")
        #expect(label?.contains("ahead of pace") == false)
        #expect(label?.contains("runs out") == false)
    }

    @Test("exhausted → VoiceOver says exhausted, never pace")
    @MainActor
    func paceAbsentWhenExhausted() async {
        guard let (delegate, appState) = await launchedDelegate() else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 100.0, resetsAt: Date().addingTimeInterval(2 * 86400)))
        delegate.updateMenuBarDisplay()

        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label?.contains("exhausted") == true)
        #expect(label?.contains("pace") == false)
        #expect(label?.contains("runs out") == false)
        #expect(delegate.statusItem?.button?.attributedTitle.string.contains("\u{2197}") == false)
    }

    // MARK: - Fable Cap Dot

    @Test("Fable cap at caution/warning/critical/exhausted → gauge icon carries a dot in that state",
          arguments: [(65.0, HeadroomState.caution), (85.0, .warning), (97.0, .critical), (100.0, .exhausted)])
    @MainActor
    func fableCapDotDrawn(fableUtilization: Double, expectedDot: HeadroomState) async {
        guard let (delegate, appState) = await launchedDelegate() else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 17.0, resetsAt: nil))
        appState.updateScopedLimits([
            ScopedLimitState(displayName: "Fable", utilization: fableUtilization, resetsAt: nil)
        ])
        // Sanity: fixture maps to the intended state
        #expect(appState.scopedLimits.first?.headroomState == expectedDot)
        delegate.updateMenuBarDisplay()

        let actual = delegate.statusItem?.button?.image?.tiffRepresentation
        let withDot = GaugeIcon.make(headroomPercentage: 83, state: .normal, capDot: expectedDot).tiffRepresentation
        let withoutDot = GaugeIcon.make(headroomPercentage: 83, state: .normal).tiffRepresentation
        #expect(actual == withDot)
        #expect(actual != withoutDot)
        // Menu bar number stays the overall weekly value
        #expect(delegate.statusItem?.button?.attributedTitle.string == "83%")
        // Dot is not colour-only: VoiceOver names the cap state
        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label == "cc-hdrm: Claude weekly headroom: 83 percent, normal, Fable cap \(expectedDot.rawValue)")
    }

    @Test("Fable cap dot also shows on the extra-usage icon")
    @MainActor
    func fableCapDotInExtraUsageMode() async {
        guard let (delegate, appState) = await launchedDelegate() else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateExtraUsage(enabled: true, monthlyLimit: 10000.0, usedCredits: 2739.0, utilization: 0.2739)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 100.0, resetsAt: nil))
        appState.updateScopedLimits([ScopedLimitState(displayName: "Fable", utilization: 85.0, resetsAt: nil)])
        delegate.updateMenuBarDisplay()

        let expected = GaugeIcon.makeExtraUsage(remainingFraction: 0.7261, utilization: 0.2739, capDot: .warning)
        #expect(delegate.statusItem?.button?.image?.tiffRepresentation == expected.tiffRepresentation)
        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label?.hasSuffix(", Fable cap warning") == true)
    }

    @Test("Fable cap normal or absent → no dot")
    @MainActor
    func fableCapDotAbsent() async {
        guard let (delegate, appState) = await launchedDelegate() else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        let withoutDot = GaugeIcon.make(headroomPercentage: 83, state: .normal).tiffRepresentation
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 17.0, resetsAt: nil))

        delegate.updateMenuBarDisplay()
        #expect(delegate.statusItem?.button?.image?.tiffRepresentation == withoutDot, "No scoped limits → no dot")

        appState.updateScopedLimits([ScopedLimitState(displayName: "Fable", utilization: 10.0, resetsAt: nil)])
        delegate.updateMenuBarDisplay()
        #expect(delegate.statusItem?.button?.image?.tiffRepresentation == withoutDot, "Fable normal → no dot")
        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label?.contains(" cap ") == false, "No dot → no cap clause")
    }
}
