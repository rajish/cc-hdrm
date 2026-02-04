import Testing
import AppKit
@testable import cc_hdrm

@Suite("AnalyticsWindow Tests")
@MainActor
struct AnalyticsWindowTests {

    // CRITICAL: Reset singleton state before each test for isolation
    init() {
        AnalyticsWindow.shared.reset()
    }

    @Test("shared returns singleton instance")
    func sharedReturnsSingleton() {
        let instance1 = AnalyticsWindow.shared
        let instance2 = AnalyticsWindow.shared
        #expect(instance1 === instance2)
    }

    @Test("toggle opens window when closed")
    func toggleOpensWindow() {
        let appState = AppState()
        let window = AnalyticsWindow.shared
        window.configure(appState: appState)

        // Window should not be open initially
        #expect(appState.isAnalyticsWindowOpen == false)

        window.toggle()

        #expect(appState.isAnalyticsWindowOpen == true)

        // Cleanup
        window.close()
    }

    @Test("toggle brings to front when already open")
    func toggleBringsToFront() {
        let appState = AppState()
        let window = AnalyticsWindow.shared
        window.configure(appState: appState)

        window.toggle()  // Open
        let firstToggleOpen = appState.isAnalyticsWindowOpen

        window.toggle()  // Should bring to front, not create duplicate
        let secondToggleOpen = appState.isAnalyticsWindowOpen

        #expect(firstToggleOpen == true)
        #expect(secondToggleOpen == true)

        // Cleanup
        window.close()
    }

    @Test("close sets isAnalyticsWindowOpen to false")
    func closeSetsStateFalse() {
        let appState = AppState()
        let window = AnalyticsWindow.shared
        window.configure(appState: appState)

        window.toggle()  // Open
        #expect(appState.isAnalyticsWindowOpen == true)

        window.close()
        #expect(appState.isAnalyticsWindowOpen == false)
    }

    @Test("configure can be called and window can be used")
    func configureAndToggle() {
        // This test verifies window can be configured after fresh reset
        let appState = AppState()
        let window = AnalyticsWindow.shared
        window.configure(appState: appState)
        window.toggle()
        #expect(appState.isAnalyticsWindowOpen == true)
        window.close()
    }

    @Test("close when already closed is safe no-op")
    func closeWhenAlreadyClosed() {
        let appState = AppState()
        let window = AnalyticsWindow.shared
        window.configure(appState: appState)

        // Close without opening - should not crash
        window.close()
        #expect(appState.isAnalyticsWindowOpen == false)
    }

    @Test("multiple toggle cycles work correctly")
    func multipleToggleCycles() {
        let appState = AppState()
        let window = AnalyticsWindow.shared
        window.configure(appState: appState)

        // Cycle 1
        window.toggle()
        #expect(appState.isAnalyticsWindowOpen == true)
        window.close()
        #expect(appState.isAnalyticsWindowOpen == false)

        // Cycle 2
        window.toggle()
        #expect(appState.isAnalyticsWindowOpen == true)
        window.close()
        #expect(appState.isAnalyticsWindowOpen == false)
    }
}
