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
        window.configure(appState: appState, historicalDataService: MockHistoricalDataService(), headroomAnalysisService: MockHeadroomAnalysisService())

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
        window.configure(appState: appState, historicalDataService: MockHistoricalDataService(), headroomAnalysisService: MockHeadroomAnalysisService())

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
        window.configure(appState: appState, historicalDataService: MockHistoricalDataService(), headroomAnalysisService: MockHeadroomAnalysisService())

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
        window.configure(appState: appState, historicalDataService: MockHistoricalDataService(), headroomAnalysisService: MockHeadroomAnalysisService())
        window.toggle()
        #expect(appState.isAnalyticsWindowOpen == true)
        window.close()
    }

    @Test("close when already closed is safe no-op")
    func closeWhenAlreadyClosed() {
        let appState = AppState()
        let window = AnalyticsWindow.shared
        window.configure(appState: appState, historicalDataService: MockHistoricalDataService(), headroomAnalysisService: MockHeadroomAnalysisService())

        // Close without opening - should not crash
        window.close()
        #expect(appState.isAnalyticsWindowOpen == false)
    }

    // MARK: - Story 4.6 — show(timeRange:) Tests

    @Test("show(timeRange: .day) opens window and sets requestedAnalyticsTimeRange")
    func showDayOpensWindow() {
        let appState = AppState()
        let window = AnalyticsWindow.shared
        window.configure(appState: appState, historicalDataService: MockHistoricalDataService(), headroomAnalysisService: MockHeadroomAnalysisService())

        #expect(appState.isAnalyticsWindowOpen == false)

        window.show(timeRange: .day)

        #expect(appState.isAnalyticsWindowOpen == true)
        #expect(appState.requestedAnalyticsTimeRange == .day)

        // Cleanup
        window.close()
    }

    @Test("show(timeRange: .week) opens window and sets requestedAnalyticsTimeRange")
    func showWeekOpensWindow() {
        let appState = AppState()
        let window = AnalyticsWindow.shared
        window.configure(appState: appState, historicalDataService: MockHistoricalDataService(), headroomAnalysisService: MockHeadroomAnalysisService())

        window.show(timeRange: .week)

        #expect(appState.isAnalyticsWindowOpen == true)
        #expect(appState.requestedAnalyticsTimeRange == .week)

        // Cleanup
        window.close()
    }

    @Test("show(timeRange:) when already open brings to front and switches range (no duplicate)")
    func showWhenOpenBringsToFront() {
        let appState = AppState()
        let window = AnalyticsWindow.shared
        window.configure(appState: appState, historicalDataService: MockHistoricalDataService(), headroomAnalysisService: MockHeadroomAnalysisService())

        // Open with .day
        window.show(timeRange: .day)
        #expect(appState.isAnalyticsWindowOpen == true)
        #expect(appState.requestedAnalyticsTimeRange == .day)

        // Show with .week while already open — should bring to front, not duplicate
        window.show(timeRange: .week)
        #expect(appState.isAnalyticsWindowOpen == true)
        #expect(appState.requestedAnalyticsTimeRange == .week)

        // Cleanup
        window.close()
    }

    @Test("multiple toggle cycles work correctly")
    func multipleToggleCycles() {
        let appState = AppState()
        let window = AnalyticsWindow.shared
        window.configure(appState: appState, historicalDataService: MockHistoricalDataService(), headroomAnalysisService: MockHeadroomAnalysisService())

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

    // MARK: - Fitting the frame to the screen

    private static let visible = NSRect(x: 0, y: 25, width: 3840, height: 2135)

    @Test("frame inside the visible screen is unchanged")
    func fittedLeavesFrameThatFits() {
        let frame = NSRect(x: 100, y: 200, width: 600, height: 500)
        #expect(AnalyticsWindow.fitted(frame, in: Self.visible) == frame)
    }

    @Test("frame taller than the visible screen is cut to the visible height and fully on screen")
    func fittedShrinksTooTallFrame() {
        let frame = NSRect(x: 730, y: -92, width: 1920, height: 2227)
        let expected = NSRect(x: 730, y: 25, width: 1920, height: 2135)
        #expect(AnalyticsWindow.fitted(frame, in: Self.visible) == expected)
    }

    @Test("frame wider than the visible screen is cut to the visible width and fully on screen")
    func fittedShrinksTooWideFrame() {
        let frame = NSRect(x: -50, y: 200, width: 4000, height: 500)
        let expected = NSRect(x: 0, y: 200, width: 3840, height: 500)
        #expect(AnalyticsWindow.fitted(frame, in: Self.visible) == expected)
    }

    @Test(
        "frame below or beside the screen moves inside with its size unchanged",
        arguments: [
            (NSPoint(x: 100, y: -300), NSPoint(x: 100, y: 25)),
            (NSPoint(x: -300, y: 200), NSPoint(x: 0, y: 200)),
            (NSPoint(x: 3700, y: 200), NSPoint(x: 3240, y: 200)),
        ]
    )
    func fittedMovesFrameOutsideScreen(origin: NSPoint, expectedOrigin: NSPoint) {
        let size = NSSize(width: 600, height: 500)
        let fitted = AnalyticsWindow.fitted(NSRect(origin: origin, size: size), in: Self.visible)
        #expect(fitted == NSRect(origin: expectedOrigin, size: size))
    }

    @Test("frame above the screen moves down so the title bar is reachable")
    func fittedMovesFrameAboveScreen() {
        let frame = NSRect(x: 100, y: 2000, width: 600, height: 500)
        #expect(AnalyticsWindow.fitted(frame, in: Self.visible).minY == 1660)
    }

    @Test("too-tall frame with a raised origin still ends fully on screen")
    func fittedShrinksRaisedTooTallFrame() {
        let frame = NSRect(x: 730, y: 100, width: 1920, height: 2227)
        let expected = NSRect(x: 730, y: 25, width: 1920, height: 2135)
        #expect(AnalyticsWindow.fitted(frame, in: Self.visible) == expected)
    }

    @Test("frame on a display left of the main one is unchanged")
    func fittedKeepsFrameOnLeftDisplay() {
        let leftDisplay = NSRect(x: -1920, y: 25, width: 1920, height: 1055)
        let frame = NSRect(x: -1500, y: 200, width: 600, height: 500)
        #expect(AnalyticsWindow.fitted(frame, in: leftDisplay) == frame)
    }

    @Test("with no known screen the frame is unchanged")
    func fittedLeavesFrameWithNoScreen() {
        let frame = NSRect(x: 730, y: -92, width: 1920, height: 2227)
        #expect(AnalyticsWindow.fitted(frame, in: nil) == frame)
    }

    @Test("opening with an oversized saved frame puts the window fully on screen")
    func openingRepairsOversizedSavedFrame() throws {
        let key = "NSWindow Frame AnalyticsWindow"
        let original = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(original, forKey: key) }
        guard let visible = NSScreen.main?.visibleFrame else { return }
        UserDefaults.standard.set(
            "\(visible.minX) \(visible.minY - 92) \(visible.width) \(visible.height + 92) "
                + "\(visible.minX) \(visible.minY) \(visible.width) \(visible.height) ",
            forKey: key
        )

        let appState = AppState()
        let window = AnalyticsWindow.shared
        window.configure(appState: appState, historicalDataService: MockHistoricalDataService(), headroomAnalysisService: MockHeadroomAnalysisService())
        window.toggle()
        defer { window.close() }

        let panel = try #require(window.panel)
        let screen = try #require(panel.screen ?? NSScreen.main)
        #expect(screen.visibleFrame.contains(panel.frame))
    }
}
