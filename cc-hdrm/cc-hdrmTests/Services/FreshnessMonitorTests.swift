import Foundation
import Testing
@testable import cc_hdrm

@Suite("FreshnessMonitor Tests")
struct FreshnessMonitorTests {

    @Test("checkFreshness sets status message when veryStale and connected")
    @MainActor
    func setsStatusMessageWhenVeryStale() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.setLastUpdated(Date().addingTimeInterval(-600))

        let monitor = FreshnessMonitor(appState: state)
        monitor.checkFreshness()

        #expect(state.statusMessage?.title == FreshnessMonitor.staleMessageTitle)
        #expect(state.statusMessage?.detail.contains("ago") == true)
    }

    @Test("checkFreshness does not set status message when fresh")
    @MainActor
    func noStatusMessageWhenFresh() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.setLastUpdated(Date())

        let monitor = FreshnessMonitor(appState: state)
        monitor.checkFreshness()

        #expect(state.statusMessage == nil)
    }

    @Test("checkFreshness does not set status message when stale")
    @MainActor
    func noStatusMessageWhenStale() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.setLastUpdated(Date().addingTimeInterval(-120))

        let monitor = FreshnessMonitor(appState: state)
        monitor.checkFreshness()

        #expect(state.statusMessage == nil)
    }

    @Test("checkFreshness does not set stale message when disconnected")
    @MainActor
    func noStaleMessageWhenDisconnected() {
        let state = AppState()
        state.updateConnectionStatus(.disconnected)
        state.setLastUpdated(Date().addingTimeInterval(-600))

        let monitor = FreshnessMonitor(appState: state)
        monitor.checkFreshness()

        #expect(state.statusMessage == nil)
    }

    @Test("checkFreshness clears own message when freshness recovers")
    @MainActor
    func clearsOwnMessageOnRecovery() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.setLastUpdated(Date().addingTimeInterval(-600))

        let monitor = FreshnessMonitor(appState: state)
        monitor.checkFreshness()
        #expect(state.statusMessage?.title == FreshnessMonitor.staleMessageTitle)

        // Simulate recovery — new data arrived
        state.setLastUpdated(Date())
        monitor.checkFreshness()
        #expect(state.statusMessage == nil)
    }

    @Test("checkFreshness does not clear non-freshness status messages")
    @MainActor
    func doesNotClearOtherMessages() {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.setLastUpdated(Date())
        state.updateStatusMessage(StatusMessage(title: "Token expired", detail: "Run Claude Code"))

        let monitor = FreshnessMonitor(appState: state)
        monitor.checkFreshness()

        // Should NOT clear a message it didn't set
        #expect(state.statusMessage?.title == "Token expired")
    }

    @Test("stop cancels the monitor task and prevents further checks")
    @MainActor
    func stopCancelsTask() async {
        let state = AppState()
        state.updateConnectionStatus(.connected)
        state.setLastUpdated(Date().addingTimeInterval(-600))

        // Use a very short interval so the loop would fire quickly if not cancelled
        let monitor = FreshnessMonitor(appState: state, checkInterval: 0.05)

        await monitor.start()
        monitor.stop()

        // Clear any message that may have been set before stop
        state.updateStatusMessage(nil)

        // Wait longer than the check interval — if stop didn't cancel, a check would fire
        try? await Task.sleep(for: .milliseconds(200))

        // If the task was properly cancelled, no new status message should appear
        #expect(state.statusMessage == nil, "Monitor should not set messages after stop()")
    }
}
