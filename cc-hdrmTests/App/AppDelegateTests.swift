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

// MARK: - Menu Bar Display Tests (Task 8)

@Suite("AppDelegate Menu Bar Display Tests")
struct AppDelegateMenuBarTests {

    @Test("updateMenuBarDisplay updates attributedTitle with correct text after state change")
    @MainActor
    func updateMenuBarDisplayReflectsState() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try? await Task.sleep(for: .milliseconds(50))

        guard let appState = delegate.appState else {
            #expect(Bool(false), "AppState should exist after launch")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: WindowState(utilization: 17.0, resetsAt: nil), sevenDay: nil)
        delegate.updateMenuBarDisplay()

        let title = delegate.statusItem?.button?.attributedTitle
        #expect(title != nil, "attributedTitle should be set")
        #expect(title?.string == "83%", "attributedTitle text should reflect 83% headroom")
    }

    @Test("status item button has accessibilityLabel set matching AC#6 format")
    @MainActor
    func statusItemHasAccessibilityLabel() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        delegate.updateMenuBarDisplay()

        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label != nil, "accessibilityLabel should be set")
        #expect(label?.contains("cc-hdrm:") == true, "accessibilityLabel should start with 'cc-hdrm:'")
    }

    @Test("status item accessibilityValue includes percent for connected states")
    @MainActor
    func accessibilityValueIncludesPercent() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try? await Task.sleep(for: .milliseconds(50))

        guard let appState = delegate.appState else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: WindowState(utilization: 50.0, resetsAt: nil), sevenDay: nil)
        delegate.updateMenuBarDisplay()

        let value = delegate.statusItem?.button?.accessibilityValue() as? String
        #expect(value != nil, "accessibilityValue should be set")
        #expect(value?.contains("percent") == true, "accessibilityValue should include 'percent' for connected states")
        #expect(value?.contains("50") == true, "accessibilityValue should include the headroom percentage")
    }

    // MARK: - Exhausted Accessibility Tests (Story 3.2, Task 10)

    @Test("exhausted state with resetsAt → accessibility contains 'exhausted' and 'resets in'")
    @MainActor
    func accessibilityExhaustedWithResetsAt() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try? await Task.sleep(for: .milliseconds(50))

        guard let appState = delegate.appState else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        let resetsAt = Date().addingTimeInterval(30 * 60)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: WindowState(utilization: 100.0, resetsAt: resetsAt), sevenDay: nil)
        delegate.updateMenuBarDisplay()

        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label?.contains("exhausted") == true, "Should contain 'exhausted'")
        #expect(label?.contains("resets in") == true, "Should contain 'resets in'")
    }

    @Test("exhausted state without resetsAt → accessibility contains 'exhausted' but not 'resets in'")
    @MainActor
    func accessibilityExhaustedWithoutResetsAt() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try? await Task.sleep(for: .milliseconds(50))

        guard let appState = delegate.appState else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: WindowState(utilization: 100.0, resetsAt: nil), sevenDay: nil)
        delegate.updateMenuBarDisplay()

        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label?.contains("exhausted") == true, "Should contain 'exhausted'")
        #expect(label?.contains("resets in") == false, "Should not contain 'resets in' without resetsAt")
    }

    @Test("attributedTitle uses correct font weight for state")
    @MainActor
    func attributedTitleUsesCorrectFontWeight() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try? await Task.sleep(for: .milliseconds(50))

        guard let appState = delegate.appState else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        // Set critical state (bold weight expected)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: WindowState(utilization: 97.0, resetsAt: nil), sevenDay: nil)
        delegate.updateMenuBarDisplay()

        let title = delegate.statusItem?.button?.attributedTitle
        #expect(title != nil, "attributedTitle should be set")

        let expectedFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        if let font = title?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            #expect(font.fontName == expectedFont.fontName, "Critical state should use bold weight")
        }
    }

    // MARK: - Slope Accessibility Tests (Story 11.3, AC #5)

    @Test("accessibility includes slope when rising (AC #5)")
    @MainActor
    func accessibilityIncludesSlopeWhenRising() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try? await Task.sleep(for: .milliseconds(50))

        guard let appState = delegate.appState else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: WindowState(utilization: 22.0, resetsAt: Date().addingTimeInterval(3600)), sevenDay: nil)
        appState.updateSlopes(fiveHour: .rising, sevenDay: .flat)
        delegate.updateMenuBarDisplay()

        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label?.contains("rising") == true, "Accessibility should include 'rising' slope label when actionable")
    }

    @Test("accessibility includes slope when steep (AC #5)")
    @MainActor
    func accessibilityIncludesSlopeWhenSteep() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try? await Task.sleep(for: .milliseconds(50))

        guard let appState = delegate.appState else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: WindowState(utilization: 35.0, resetsAt: Date().addingTimeInterval(3600)), sevenDay: nil)
        appState.updateSlopes(fiveHour: .steep, sevenDay: .flat)
        delegate.updateMenuBarDisplay()

        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label?.contains("steep") == true, "Accessibility should include 'steep' slope label when actionable")
    }

    @Test("accessibility excludes slope when flat (AC #5)")
    @MainActor
    func accessibilityExcludesSlopeWhenFlat() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try? await Task.sleep(for: .milliseconds(50))

        guard let appState = delegate.appState else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: WindowState(utilization: 17.0, resetsAt: Date().addingTimeInterval(3600)), sevenDay: nil)
        appState.updateSlopes(fiveHour: .flat, sevenDay: .flat)
        delegate.updateMenuBarDisplay()

        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label?.contains("flat") == false, "Accessibility should NOT include slope when flat (not actionable)")
        #expect(label?.contains("rising") == false, "Accessibility should NOT include rising when slope is flat")
        #expect(label?.contains("steep") == false, "Accessibility should NOT include steep when slope is flat")
    }

    @Test("accessibility excludes slope when exhausted even with actionable slope (AC #5)")
    @MainActor
    func accessibilityExcludesSlopeWhenExhausted() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine, notificationService: MockNotificationService())

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try? await Task.sleep(for: .milliseconds(50))

        guard let appState = delegate.appState else {
            #expect(Bool(false), "AppState should exist")
            return
        }

        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: WindowState(utilization: 100.0, resetsAt: Date().addingTimeInterval(720)), sevenDay: nil)
        appState.updateSlopes(fiveHour: .steep, sevenDay: .flat)
        delegate.updateMenuBarDisplay()

        let label = delegate.statusItem?.button?.accessibilityLabel() as? String
        #expect(label?.contains("exhausted") == true, "Accessibility should contain 'exhausted'")
        #expect(label?.contains("steep") == false, "Accessibility should NOT include slope when exhausted")
    }

    // MARK: - No 5-Hour Number

    @MainActor
    private func launchedDelegate() async -> (AppDelegate, AppState)? {
        let delegate = AppDelegate(pollingEngine: MockPollingEngine(), notificationService: MockNotificationService())
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try? await Task.sleep(for: .milliseconds(50))
        guard let appState = delegate.appState else {
            #expect(Bool(false), "AppState should exist")
            return nil
        }
        appState.updateConnectionStatus(.connected)
        return (delegate, appState)
    }

    @MainActor
    private func sameImage(_ lhs: NSImage?, _ rhs: NSImage) -> Bool {
        lhs?.tiffRepresentation == rhs.tiffRepresentation
    }

    @Test("no 5-hour number → weekly text, gauge with the 7d label, VoiceOver says weekly")
    @MainActor
    func noFiveHourShowsWeeklyWithPromotedLabel() async {
        guard let (delegate, appState) = await launchedDelegate() else { return }

        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 17.0, resetsAt: nil))
        delegate.updateMenuBarDisplay()

        let image = delegate.statusItem?.button?.image
        #expect(delegate.statusItem?.button?.attributedTitle.string == "83%")
        #expect(sameImage(image, GaugeIcon.make(headroomPercentage: 83, state: .normal, sevenDayOverlay: .promoted)))
        #expect(delegate.statusItem?.button?.accessibilityLabel() == "cc-hdrm: Claude weekly headroom 83 percent, normal")
    }

    @Test("no 5-hour number, weekly exhausted → VoiceOver says weekly and spoken days and hours, not minutes")
    @MainActor
    func noFiveHourExhaustedAccessibility() async {
        guard let (delegate, appState) = await launchedDelegate() else { return }

        let resetsAt = Date().addingTimeInterval(3 * 86400 + 4 * 3600 + 120)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 100.0, resetsAt: resetsAt))
        delegate.updateMenuBarDisplay()

        #expect(delegate.statusItem?.button?.attributedTitle.string == "\u{21BB} 3d 4h")
        #expect(delegate.statusItem?.button?.accessibilityLabel() == "cc-hdrm: Claude weekly headroom exhausted, resets in 3 days 4 hours")
    }

    @Test("no 5-hour number, extra usage active → dollar text and extra-usage icon")
    @MainActor
    func noFiveHourExtraUsage() async {
        guard let (delegate, appState) = await launchedDelegate() else { return }

        appState.updateExtraUsage(enabled: true, monthlyLimit: 1000, usedCredits: 439, utilization: 43.9)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 100.0, resetsAt: nil))
        delegate.updateMenuBarDisplay()

        #expect(delegate.statusItem?.button?.attributedTitle.string == "$5.61")
        #expect(sameImage(delegate.statusItem?.button?.image, GaugeIcon.makeExtraUsage(remainingFraction: 0.561, utilization: 43.9)))
    }

    @Test("both windows nil while connected → em dash and disconnected VoiceOver")
    @MainActor
    func bothNilStaysDisconnected() async {
        guard let (delegate, appState) = await launchedDelegate() else { return }

        appState.updateWindows(fiveHour: nil, sevenDay: nil)
        delegate.updateMenuBarDisplay()

        #expect(delegate.statusItem?.button?.attributedTitle.string == "\u{2014}")
        #expect(delegate.statusItem?.button?.accessibilityLabel() == "cc-hdrm: Claude headroom disconnected")
    }

    @Test("with a 5-hour number: 5-hour wording, dot and promoted label unchanged; promoted weekly is named")
    @MainActor
    func fiveHourPresentUnchanged() async {
        guard let (delegate, appState) = await launchedDelegate() else { return }

        appState.updateWindows(
            fiveHour: WindowState(utilization: 17.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 70.0, resetsAt: nil)
        )
        delegate.updateMenuBarDisplay()
        #expect(delegate.statusItem?.button?.accessibilityLabel() == "cc-hdrm: Claude headroom 83 percent, normal")
        #expect(sameImage(delegate.statusItem?.button?.image, GaugeIcon.make(headroomPercentage: 83, state: .normal, sevenDayOverlay: .dot(.caution))))

        let resetsAt = Date().addingTimeInterval(30 * 60)
        appState.updateWindows(fiveHour: WindowState(utilization: 100.0, resetsAt: resetsAt), sevenDay: nil)
        delegate.updateMenuBarDisplay()
        let label = delegate.statusItem?.button?.accessibilityLabel() ?? ""
        #expect(label.hasPrefix("cc-hdrm: Claude headroom exhausted, resets in "))
        #expect(label.hasSuffix(" minutes"))

        appState.updateCreditLimits(RateLimitTier.pro.creditLimits)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 28.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 95.0, resetsAt: nil)
        )
        delegate.updateMenuBarDisplay()
        #expect(appState.displayedWindow == .sevenDay)
        #expect(sameImage(delegate.statusItem?.button?.image, GaugeIcon.make(headroomPercentage: 5, state: .warning, sevenDayOverlay: .promoted)))
        #expect(delegate.statusItem?.button?.accessibilityLabel() == "cc-hdrm: Claude weekly headroom 5 percent, warning")

        let weeklyReset = Date().addingTimeInterval(3 * 86400)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 28.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 100.0, resetsAt: weeklyReset)
        )
        delegate.updateMenuBarDisplay()
        let promotedLabel = delegate.statusItem?.button?.accessibilityLabel() ?? ""
        #expect(promotedLabel.hasPrefix("cc-hdrm: Claude weekly headroom exhausted, resets in "))
        #expect(promotedLabel.hasSuffix(" minutes"))
    }

    @Test("no 5-hour number → VoiceOver names weekly, ignores a rising slope, and handles no reset time")
    @MainActor
    func noFiveHourAccessibilityBranches() async {
        guard let (delegate, appState) = await launchedDelegate() else { return }

        appState.updateSlopes(fiveHour: .flat, sevenDay: .rising)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 42.0, resetsAt: nil))
        delegate.updateMenuBarDisplay()
        #expect(delegate.statusItem?.button?.accessibilityLabel() == "cc-hdrm: Claude weekly headroom 58 percent, normal")

        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 100.0, resetsAt: nil))
        delegate.updateMenuBarDisplay()
        #expect(delegate.statusItem?.button?.accessibilityLabel() == "cc-hdrm: Claude weekly headroom exhausted")
    }

    @Test("no 5-hour number → menu bar VoiceOver says ahead of pace only with the arrow, without a clock time")
    @MainActor
    func noFiveHourPaceAccessibility() async {
        guard let (delegate, appState) = await launchedDelegate() else { return }

        appState.updateSlopes(fiveHour: .flat, sevenDay: .rising)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 60.0, resetsAt: Date().addingTimeInterval(4 * 86400)))
        delegate.updateMenuBarDisplay()
        #expect(delegate.statusItem?.button?.attributedTitle.string == "40% \u{2197}")
        #expect(delegate.statusItem?.button?.accessibilityLabel() == "cc-hdrm: Claude weekly headroom 40 percent, caution, ahead of pace")

        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(2 * 86400)))
        delegate.updateMenuBarDisplay()
        #expect(delegate.statusItem?.button?.attributedTitle.string == "80%")
        #expect(delegate.statusItem?.button?.accessibilityLabel() == "cc-hdrm: Claude weekly headroom 80 percent, normal")
    }

    @Test("promoted weekly with a 5-hour number → slope in text and VoiceOver, no pace wording")
    @MainActor
    func promotedWeeklyKeepsSlopeAccessibility() async {
        guard let (delegate, appState) = await launchedDelegate() else { return }

        appState.updateSlopes(fiveHour: .flat, sevenDay: .rising)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 85.0, resetsAt: Date().addingTimeInterval(4 * 86400))
        )
        delegate.updateMenuBarDisplay()

        #expect(appState.displayedWindow == .sevenDay)
        #expect(delegate.statusItem?.button?.attributedTitle.string == "15% \(SlopeLevel.rising.arrow)")
        #expect(delegate.statusItem?.button?.accessibilityLabel() == "cc-hdrm: Claude weekly headroom 15 percent, warning, \(SlopeLevel.rising.accessibilityLabel)")
        #expect(!delegate.previousShowingPaceArrow)
    }

    @Test("pace arrow tracker changes only with the pace arrow, never for a slope arrow")
    @MainActor
    func paceArrowChangeTracker() async {
        guard let (delegate, appState) = await launchedDelegate() else { return }
        let ahead = WindowState(utilization: 60.0, resetsAt: Date().addingTimeInterval(4 * 86400))
        let under = WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(2 * 86400))
        let fiveHour = WindowState(utilization: 20.0, resetsAt: nil)
        appState.updateSlopes(fiveHour: .rising, sevenDay: .rising)

        func update(_ five: WindowState?, _ seven: WindowState?) -> Bool {
            appState.updateWindows(fiveHour: five, sevenDay: seven)
            delegate.updateMenuBarDisplay()
            return delegate.previousShowingPaceArrow
        }

        #expect(update(fiveHour, ahead) == false)
        #expect(update(nil, under) == false)
        #expect(update(nil, ahead) == true)
        #expect(update(nil, ahead) == true)

        appState.updateConnectionStatus(.disconnected)
        delegate.updateMenuBarDisplay()
        #expect(delegate.previousShowingPaceArrow == false)

        appState.updateConnectionStatus(.connected)
        delegate.updateMenuBarDisplay()
        #expect(delegate.previousShowingPaceArrow == true)
        #expect(update(fiveHour, ahead) == false)
    }

    @Test("old weekly data while disconnected → em dash and disconnected icon")
    @MainActor
    func noFiveHourDisconnected() async {
        guard let (delegate, appState) = await launchedDelegate() else { return }

        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 17.0, resetsAt: nil))
        appState.updateConnectionStatus(.disconnected)
        delegate.updateMenuBarDisplay()

        #expect(delegate.statusItem?.button?.attributedTitle.string == "\u{2014}")
        #expect(sameImage(delegate.statusItem?.button?.image, GaugeIcon.makeDisconnected()))
        #expect(delegate.statusItem?.button?.accessibilityLabel() == "cc-hdrm: Claude headroom disconnected")
    }

    @Test("flip back to a 5-hour number → the weekly label gives way to the dot")
    @MainActor
    func flipBackRestoresOverlay() async {
        guard let (delegate, appState) = await launchedDelegate() else { return }
        let weekly = WindowState(utilization: 70.0, resetsAt: nil)

        appState.updateWindows(fiveHour: nil, sevenDay: weekly)
        delegate.updateMenuBarDisplay()
        #expect(sameImage(delegate.statusItem?.button?.image, GaugeIcon.make(headroomPercentage: 30, state: .caution, sevenDayOverlay: .promoted)))

        appState.updateWindows(fiveHour: WindowState(utilization: 17.0, resetsAt: nil), sevenDay: weekly)
        delegate.updateMenuBarDisplay()
        #expect(sameImage(delegate.statusItem?.button?.image, GaugeIcon.make(headroomPercentage: 83, state: .normal, sevenDayOverlay: .dot(.caution))))
    }

    @Test("change tracker behind the log line moves only on a real change; both nil is no change")
    @MainActor
    func fiveHourChangeTracker() async {
        guard let (delegate, appState) = await launchedDelegate() else { return }
        let weekly = WindowState(utilization: 50.0, resetsAt: nil)
        let fiveHour = WindowState(utilization: 20.0, resetsAt: nil)

        func update(_ five: WindowState?, _ seven: WindowState?) -> Bool {
            appState.updateWindows(fiveHour: five, sevenDay: seven)
            delegate.updateMenuBarDisplay()
            return delegate.previousHasNoFiveHourNumber
        }

        #expect(update(fiveHour, weekly) == false)
        #expect(update(nil, weekly) == true)
        #expect(update(nil, weekly) == true)
        #expect(update(nil, nil) == true)
        #expect(update(nil, weekly) == true)
        #expect(update(fiveHour, weekly) == false)
    }
}
