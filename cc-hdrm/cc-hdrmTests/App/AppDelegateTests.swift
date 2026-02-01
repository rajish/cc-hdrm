import AppKit
import Foundation
import SwiftUI
import Testing
@testable import cc_hdrm

// MARK: - Mock Polling Engine

private final class MockPollingEngine: PollingEngineProtocol {
    var startCallCount = 0
    var stopCallCount = 0

    func start() async {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
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
        _ = AppDelegate(pollingEngine: mockEngine)

        // Verify delegate was created — polling engine not started yet (only starts in applicationDidFinishLaunching)
        #expect(mockEngine.startCallCount == 0)
    }

    @Test("applicationWillTerminate stops the polling engine")
    @MainActor
    func terminateStopsPollingEngine() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine)

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
        let delegate = AppDelegate(pollingEngine: mockEngine)

        #expect(delegate.appState == nil)

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        #expect(delegate.appState != nil, "AppState should be created on launch")
    }

    @Test("applicationDidFinishLaunching starts FreshnessMonitor")
    @MainActor
    func launchStartsFreshnessMonitor() async {
        let mockEngine = MockPollingEngine()
        let mockMonitor = MockFreshnessMonitor()
        let delegate = AppDelegate(pollingEngine: mockEngine, freshnessMonitor: mockMonitor)

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
        let delegate = AppDelegate(pollingEngine: mockEngine, freshnessMonitor: mockMonitor)

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
        let delegate = AppDelegate(pollingEngine: mockEngine)

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        #expect(delegate.popover != nil, "Popover should be created during launch")
    }

    @Test("After launch, button action is set to togglePopover: selector")
    @MainActor
    func buttonActionWiredToToggle() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine)

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        let action = delegate.statusItem?.button?.action
        #expect(action == #selector(AppDelegate.togglePopover(_:)), "Button action should be togglePopover:")
    }

    @Test("Popover behavior is transient (AC #4)")
    @MainActor
    func popoverBehaviorIsTransient() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine)

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        #expect(delegate.popover?.behavior == .transient, "Popover behavior should be .transient for auto-dismiss")
    }

    @Test("Popover contentViewController is set with NSHostingController")
    @MainActor
    func popoverHasHostingController() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine)

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        #expect(delegate.popover?.contentViewController != nil, "Popover should have a content view controller")
        #expect(delegate.popover?.contentViewController is NSHostingController<PopoverView>,
                "Content view controller should be NSHostingController<PopoverView>")
    }

    @Test("togglePopover does not crash when popover is not shown (headless CI)")
    @MainActor
    func togglePopoverCallDoesNotCrash() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine)

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

// MARK: - Menu Bar Display Tests (Task 8)

@Suite("AppDelegate Menu Bar Display Tests")
struct AppDelegateMenuBarTests {

    @Test("updateMenuBarDisplay updates attributedTitle with correct text after state change")
    @MainActor
    func updateMenuBarDisplayReflectsState() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine)

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
        #expect(title?.string == "\u{2733} 83%", "attributedTitle text should reflect 83% headroom")
    }

    @Test("status item button has accessibilityLabel set matching AC#6 format")
    @MainActor
    func statusItemHasAccessibilityLabel() async {
        let mockEngine = MockPollingEngine()
        let delegate = AppDelegate(pollingEngine: mockEngine)

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
        let delegate = AppDelegate(pollingEngine: mockEngine)

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
        let delegate = AppDelegate(pollingEngine: mockEngine)

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
        let delegate = AppDelegate(pollingEngine: mockEngine)

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
        let delegate = AppDelegate(pollingEngine: mockEngine)

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
}
