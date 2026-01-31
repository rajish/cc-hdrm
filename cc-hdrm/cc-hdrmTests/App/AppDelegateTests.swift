import AppKit
import Foundation
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
}
