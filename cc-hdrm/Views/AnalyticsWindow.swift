import AppKit
import SwiftUI
import os

/// Singleton controller for the analytics window.
/// Opens/closes the analytics panel and tracks window state in AppState.
@MainActor
final class AnalyticsWindow: NSObject, NSWindowDelegate {

    static let shared = AnalyticsWindow()

    private var panel: NSPanel?
    private weak var appState: AppState?
    private var historicalDataService: (any HistoricalDataServiceProtocol)?

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "analytics"
    )

    private override init() {
        super.init()
    }

    /// Configure with AppState and HistoricalDataService references.
    /// Must be called during app initialization.
    func configure(appState: AppState, historicalDataService: any HistoricalDataServiceProtocol) {
        self.appState = appState
        self.historicalDataService = historicalDataService
    }

    /// Toggles the analytics window: opens if closed, brings to front if open.
    func toggle() {
        guard appState != nil else {
            assertionFailure("AnalyticsWindow.toggle() called before configure(appState:historicalDataService:)")
            Self.logger.error("toggle() called before configure() - ignoring")
            return
        }

        if let panel, panel.isVisible {
            Self.logger.info("Analytics window bringing to front")
            panel.orderFront(nil)
        } else {
            Self.logger.info("Analytics window opening")
            openWindow()
        }
    }

    /// Closes the analytics window if open.
    func close() {
        Self.logger.info("Analytics window closing")
        panel?.close()
    }

    private func openWindow() {
        if panel == nil {
            createPanel()
        }

        // Use orderFront to avoid stealing focus from other apps (.nonactivatingPanel behavior)
        panel?.orderFront(nil)
        appState?.setAnalyticsWindowOpen(true)
    }

    private func createPanel() {
        guard let appState, let historicalDataService else {
            Self.logger.error("createPanel() called before configure() - missing dependencies")
            return
        }

        let panel = AnalyticsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Usage Analytics"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace]  // NOT .canJoinAllSpaces
        panel.minSize = NSSize(width: 400, height: 350)
        panel.delegate = self
        panel.center()

        // Restore previous position if saved
        panel.setFrameAutosaveName("AnalyticsWindow")

        let contentView = AnalyticsView(
            onClose: { [weak self] in
                self?.close()
            },
            historicalDataService: historicalDataService,
            appState: appState
        )
        panel.contentView = NSHostingView(rootView: contentView)

        self.panel = panel
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        Self.logger.info("Analytics window closed via delegate")
        appState?.setAnalyticsWindowOpen(false)
    }

    // MARK: - Test Support

    #if DEBUG
    /// Resets singleton state for test isolation. Test use only.
    func reset() {
        panel?.close()
        panel = nil
        appState = nil
        historicalDataService = nil
    }
    #endif
}
