import AppKit
import SwiftUI
import os

/// Singleton controller for the analytics window.
/// Opens/closes the analytics panel and tracks window state in AppState.
@MainActor
final class AnalyticsWindow: NSObject, NSWindowDelegate {

    static let shared = AnalyticsWindow()

    private(set) var panel: NSPanel?
    private weak var appState: AppState?
    private var historicalDataService: (any HistoricalDataServiceProtocol)?
    private var headroomAnalysisService: (any HeadroomAnalysisServiceProtocol)?
    private var patternDetector: (any SubscriptionPatternDetectorProtocol)?
    private var tierRecommendationService: (any TierRecommendationServiceProtocol)?
    private var preferencesManager: (any PreferencesManagerProtocol)?
    private var benchmarkService: (any BenchmarkServiceProtocol)?
    private var tppStorageService: (any TPPStorageServiceProtocol)?

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "analytics"
    )

    private override init() {
        super.init()
    }

    /// Configure with AppState and service references.
    /// Must be called during app initialization.
    func configure(
        appState: AppState,
        historicalDataService: any HistoricalDataServiceProtocol,
        headroomAnalysisService: any HeadroomAnalysisServiceProtocol,
        patternDetector: (any SubscriptionPatternDetectorProtocol)? = nil,
        tierRecommendationService: (any TierRecommendationServiceProtocol)? = nil,
        preferencesManager: (any PreferencesManagerProtocol)? = nil,
        benchmarkService: (any BenchmarkServiceProtocol)? = nil,
        tppStorageService: (any TPPStorageServiceProtocol)? = nil
    ) {
        self.appState = appState
        self.historicalDataService = historicalDataService
        self.headroomAnalysisService = headroomAnalysisService
        self.patternDetector = patternDetector
        self.tierRecommendationService = tierRecommendationService
        self.preferencesManager = preferencesManager
        self.benchmarkService = benchmarkService
        self.tppStorageService = tppStorageService
    }

    /// Toggles the analytics window: opens if closed, brings to front if open.
    func toggle() {
        guard appState != nil else {
            assertionFailure("AnalyticsWindow.toggle() called before configure(appState:historicalDataService:headroomAnalysisService:)")
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

    /// Opens the analytics window at a specific time range, or switches range if already open.
    /// Used by ring gauge click handlers to drill into the relevant time window.
    func show(timeRange: TimeRange) {
        guard appState != nil else {
            assertionFailure("show(timeRange:) called before configure()")
            Self.logger.error("show(timeRange:) called before configure() - ignoring")
            return
        }
        appState?.setRequestedAnalyticsTimeRange(timeRange)
        if let panel, panel.isVisible {
            Self.logger.info("Analytics window switching to \(timeRange.displayLabel) and bringing to front")
            panel.orderFront(nil)
        } else {
            Self.logger.info("Analytics window opening at \(timeRange.displayLabel)")
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
        guard let appState, let historicalDataService, let headroomAnalysisService else {
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
        panel.delegate = self
        panel.center()

        // Restore previous position if saved
        panel.setFrameAutosaveName("AnalyticsWindow")

        let contentView = AnalyticsView(
            onClose: { [weak self] in
                self?.close()
            },
            historicalDataService: historicalDataService,
            appState: appState,
            headroomAnalysisService: headroomAnalysisService,
            patternDetector: patternDetector,
            tierRecommendationService: tierRecommendationService,
            preferencesManager: preferencesManager,
            benchmarkService: benchmarkService,
            tppStorageService: tppStorageService
        )
        .frame(minWidth: 400, minHeight: 350)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.sizingOptions = [.minSize]
        panel.contentView = hostingView

        fitToScreen(panel)

        self.panel = panel
    }

    private func fitToScreen(_ panel: NSPanel) {
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame
        let restored = panel.frame
        let fitted = Self.fitted(restored, in: visible)
        guard fitted != restored else { return }
        Self.logger.info("Analytics window fitted to the screen: restored=\(NSStringFromRect(restored), privacy: .public) fitted=\(NSStringFromRect(fitted), privacy: .public)")
        panel.setFrame(fitted, display: false)
    }

    /// Returns `frame` shrunk to fit `visible` if needed, then moved fully inside it.
    /// With no known screen, returns `frame` unchanged.
    static func fitted(_ frame: NSRect, in visible: NSRect?) -> NSRect {
        guard let visible else { return frame }
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        return NSRect(
            x: min(max(frame.minX, visible.minX), visible.maxX - width),
            y: min(max(frame.minY, visible.minY), visible.maxY - height),
            width: width,
            height: height
        )
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        Self.logger.info("Analytics window closed via delegate")
        appState?.setAnalyticsWindowOpen(false)
        // Reset requested time range so toggle() (Sparkline path) opens at default .week.
        // Without this, a previous show(timeRange: .day) would persist and toggle()
        // would open at .day instead of .week via AnalyticsView's .onAppear handler.
        appState?.setRequestedAnalyticsTimeRange(.week)
        // Nil out the panel so a fresh AnalyticsView (with reset @State)
        // is created on next open. This ensures session-only state
        // (series visibility, selected time range, chart data) resets
        // when the window is closed and reopened.
        panel = nil
    }

    // MARK: - Test Support

    #if DEBUG
    /// Resets singleton state for test isolation. Test use only.
    func reset() {
        panel?.close()
        panel = nil
        appState = nil
        historicalDataService = nil
        headroomAnalysisService = nil
        patternDetector = nil
        tierRecommendationService = nil
        preferencesManager = nil
        benchmarkService = nil
        tppStorageService = nil
    }
    #endif
}
