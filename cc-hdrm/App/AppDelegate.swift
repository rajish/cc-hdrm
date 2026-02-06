import AppKit
import SwiftUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    internal var statusItem: NSStatusItem?
    internal var appState: AppState?
    internal var popover: NSPopover?
    private var pollingEngine: (any PollingEngineProtocol)?
    private var freshnessMonitor: (any FreshnessMonitorProtocol)?
    internal var preferencesManager: PreferencesManager?
    internal var launchAtLoginService: (any LaunchAtLoginServiceProtocol)?
    private var notificationService: (any NotificationServiceProtocol)?
    private var updateCheckService: (any UpdateCheckServiceProtocol)?
    private var slopeCalculationService: SlopeCalculationService?
    private var historicalDataServiceRef: HistoricalDataService?
    private var analyticsWindow: AnalyticsWindow?
    private var observationTask: Task<Void, Never>?
    private var eventMonitor: Any?
    private var previousAccessibilityValue: String?
    private var previousDisplayedWindow: DisplayedWindow?
    private var previousShowingCountdown: Bool = false

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "menubar"
    )

    private static let popoverLogger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "popover"
    )

    override init() {
        super.init()
    }

    /// Test-only initializer for injecting mock services.
    init(pollingEngine: any PollingEngineProtocol, freshnessMonitor: (any FreshnessMonitorProtocol)? = nil, notificationService: (any NotificationServiceProtocol)? = nil, launchAtLoginService: (any LaunchAtLoginServiceProtocol)? = nil) {
        self.pollingEngine = pollingEngine
        self.freshnessMonitor = freshnessMonitor
        self.notificationService = notificationService
        self.launchAtLoginService = launchAtLoginService
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.logger.info("Application launching — configuring menu bar status item")

        // Initialize database with graceful degradation (historical features disabled if fails)
        DatabaseManager.shared.initialize()

        let state = AppState()
        self.appState = state

        // Configure AnalyticsWindow singleton — deferred until HistoricalDataService is created below
        analyticsWindow = AnalyticsWindow.shared

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Initial render from current state (disconnected placeholder)
        updateMenuBarDisplay()

        // Create PreferencesManager — shared across services for hot-reconfigurable reads
        let preferences = PreferencesManager()
        self.preferencesManager = preferences

        // Configure NSPopover with SwiftUI content
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 220, height: 0) // width hint only; SwiftUI determines height
        pop.behavior = .transient
        // Task wrapper required: onThresholdChange is a synchronous closure (called from SwiftUI
        // .onChange), but reevaluateThresholds() is async — Task bridges sync→async context.
        if launchAtLoginService == nil {
            launchAtLoginService = LaunchAtLoginService()
        }

        pop.contentViewController = NSHostingController(rootView: PopoverView(appState: state, preferencesManager: preferences, launchAtLoginService: launchAtLoginService!, onThresholdChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.notificationService?.reevaluateThresholds()
            }
        }))
        pop.animates = true
        self.popover = pop

        // Wire status item button to toggle popover
        statusItem?.button?.action = #selector(togglePopover(_:))
        statusItem?.button?.target = self
        statusItem?.button?.sendAction(on: .leftMouseUp)

        // Close main popover when settings view dismisses
        NotificationCenter.default.addObserver(
            forName: .dismissPopover,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let popover = self.popover, popover.isShown else { return }
            Self.popoverLogger.info("Popover closing via settings dismiss")
            popover.performClose(nil)
            self.removeEventMonitor()
        }

        Self.logger.info("Menu bar status item configured")

        // Create NotificationService if not already injected (test path)
        if notificationService == nil {
            let ns = NotificationService(preferencesManager: preferences)
            ns.appState = state
            notificationService = ns
        }

        // Create PollingEngine with production services if not already injected (test path)
        if pollingEngine == nil {
            // Create HistoricalDataService for poll persistence
            let historicalDataService = HistoricalDataService(
                databaseManager: DatabaseManager.shared
            )
            self.historicalDataServiceRef = historicalDataService

            // Create SlopeCalculationService for burn rate tracking
            let slopeService = SlopeCalculationService()
            self.slopeCalculationService = slopeService

            pollingEngine = PollingEngine(
                keychainService: KeychainService(),
                tokenRefreshService: TokenRefreshService(),
                apiClient: APIClient(),
                appState: state,
                notificationService: notificationService,
                preferencesManager: preferences,
                historicalDataService: historicalDataService,
                slopeCalculationService: slopeService
            )
        }

        // Configure AnalyticsWindow with AppState and HistoricalDataService
        if let histService = historicalDataServiceRef {
            analyticsWindow?.configure(appState: state, historicalDataService: histService)
        }

        // Create FreshnessMonitor if not already injected (test path)
        if freshnessMonitor == nil {
            freshnessMonitor = FreshnessMonitor(appState: state)
        }

        startObservingAppState()

        // Create UpdateCheckService for app update detection
        if updateCheckService == nil {
            updateCheckService = UpdateCheckService(appState: state, preferencesManager: preferences)
        }

        // Start services with proper sequencing:
        // 1. Bootstrap slope buffer FIRST (before polling starts) to avoid race condition
        // 2. Then start polling engine
        // 3. Other services can start in parallel
        Task {
            // Bootstrap slope buffer from historical data OFF main thread (SQLite is blocking)
            // Must complete before polling starts to avoid losing early polls
            if let histService = self.historicalDataServiceRef,
               let slopeService = self.slopeCalculationService {
                do {
                    // Run SQLite query off MainActor to avoid UI stall during launch
                    let recentPolls = try await Task.detached {
                        try await histService.getRecentPolls(hours: 1)
                    }.value
                    slopeService.bootstrapFromHistory(recentPolls)
                    Self.logger.info("Slope buffer bootstrapped with \(recentPolls.count) historical polls")
                } catch {
                    // Continue without historical data - buffer will fill naturally
                    Self.logger.warning("Failed to bootstrap slope buffer: \(error.localizedDescription)")
                }
            }

            // NOW start polling (after bootstrap complete)
            await pollingEngine?.start()
            await freshnessMonitor?.start()
            await notificationService?.requestAuthorization()
        }

        // Fire-and-forget update check — do not block app launch
        Task {
            await updateCheckService?.checkForUpdate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingEngine?.stop()
        freshnessMonitor?.stop()
        observationTask?.cancel()
        observationTask = nil
        analyticsWindow?.close()
        removeEventMonitor()
    }

    // MARK: - Popover Toggle

    @objc func togglePopover(_ sender: Any?) {
        guard let popover else {
            Self.popoverLogger.warning("togglePopover called but popover is nil")
            return
        }
        if popover.isShown {
            Self.popoverLogger.info("Popover closing")
            popover.performClose(sender)
            removeEventMonitor()
        } else if let button = statusItem?.button {
            Self.popoverLogger.info("Popover opening")
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            installEventMonitor()
        } else {
            Self.popoverLogger.warning("togglePopover called but statusItem button is nil")
        }
    }

    // MARK: - Click-Outside Dismiss

    /// Installs a global event monitor that closes the popover when the user clicks outside it.
    /// NSPopover.transient does not reliably dismiss for status-bar popovers, so this provides
    /// the expected click-away-to-close behavior.
    private func installEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let popover = self.popover, popover.isShown else { return }
            Self.popoverLogger.info("Popover closing via click-outside")
            popover.performClose(nil)
            self.removeEventMonitor()
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }

    // MARK: - Menu Bar Display

    /// Starts an observation loop that re-renders the menu bar whenever AppState changes.
    /// Uses `withObservationTracking` + `AsyncStream` so the loop suspends until a
    /// tracked property actually changes, avoiding unnecessary CPU usage (NFR4).
    private func startObservingAppState() {
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                let stream = AsyncStream<Void> { continuation in
                    withObservationTracking {
                        self?.updateMenuBarDisplay()
                    } onChange: {
                        continuation.yield()
                        continuation.finish()
                    }
                }
                // Suspend here until onChange fires
                for await _ in stream { break }
                // Small yield to coalesce rapid successive changes
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// Updates the NSStatusItem's image, attributed title, color, weight, and accessibility
    /// based on the current AppState.
    internal func updateMenuBarDisplay() {
        guard let appState else { return }

        let state = appState.menuBarHeadroomState
        let text = appState.menuBarText

        // Generate gauge icon based on state
        let icon: NSImage
        if state == .disconnected {
            icon = makeDisconnectedIcon()
        } else {
            let window: WindowState? = appState.displayedWindow == .fiveHour ? appState.fiveHour : appState.sevenDay
            let headroom = min(100, max(0, 100.0 - (window?.utilization ?? 0)))

            // Determine 7d overlay: promoted label, colored dot, or none
            let sevenDayOverlay: GaugeIcon.SevenDayOverlay
            if appState.sevenDay == nil {
                sevenDayOverlay = .none
            } else if appState.displayedWindow == .sevenDay {
                sevenDayOverlay = .promoted
            } else if let sdState = appState.sevenDay?.headroomState,
                      sdState == .caution || sdState == .warning || sdState == .critical {
                sevenDayOverlay = .dot(sdState)
            } else {
                sevenDayOverlay = .none
            }

            icon = GaugeIcon.make(headroomPercentage: headroom, state: state, sevenDayOverlay: sevenDayOverlay)
        }
        statusItem?.button?.image = icon

        let color = NSColor.headroomColor(for: state)
        let font = NSFont.menuBarFont(for: state)

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: font
        ]
        statusItem?.button?.attributedTitle = NSAttributedString(string: text, attributes: attributes)

        // Accessibility (AC #6, #7)
        let accessibilityValue: String
        if state == .disconnected {
            accessibilityValue = "cc-hdrm: Claude headroom disconnected"
        } else if state == .exhausted {
            let window: WindowState? = appState.displayedWindow == .fiveHour ? appState.fiveHour : appState.sevenDay
            if let resetsAt = window?.resetsAt {
                let minutes = max(0, Int(resetsAt.timeIntervalSince(Date()) / 60))
                accessibilityValue = "cc-hdrm: Claude headroom exhausted, resets in \(minutes) minutes"
            } else {
                accessibilityValue = "cc-hdrm: Claude headroom exhausted"
            }
        } else {
            let window: WindowState? = appState.displayedWindow == .fiveHour ? appState.fiveHour : appState.sevenDay
            let headroom = max(0, Int(100.0 - (window?.utilization ?? 0)))
            let slope = appState.displayedSlope
            if slope.isActionable {
                accessibilityValue = "cc-hdrm: Claude headroom \(headroom) percent, \(state.rawValue), \(slope.accessibilityLabel)"
            } else {
                accessibilityValue = "cc-hdrm: Claude headroom \(headroom) percent, \(state.rawValue)"
            }
        }

        statusItem?.button?.setAccessibilityLabel(accessibilityValue)

        // Log display mode transitions (percentage↔countdown, 5h↔7d promotion)
        let currentWindow = appState.displayedWindow
        let currentShowingCountdown = text.contains("\u{21BB}")

        if previousDisplayedWindow != nil && previousDisplayedWindow != currentWindow {
            let from = previousDisplayedWindow == .fiveHour ? "5h" : "7d"
            let to = currentWindow == .fiveHour ? "5h" : "7d"
            Self.logger.info("Display window switched: \(from, privacy: .public) → \(to, privacy: .public)")
        }
        if previousShowingCountdown != currentShowingCountdown {
            let mode = currentShowingCountdown ? "countdown" : "percentage"
            Self.logger.info("Display mode switched to \(mode, privacy: .public)")
        }
        previousDisplayedWindow = currentWindow
        previousShowingCountdown = currentShowingCountdown

        if previousAccessibilityValue != accessibilityValue {
            statusItem?.button?.setAccessibilityValue(accessibilityValue)
            if let button = statusItem?.button {
                NSAccessibility.post(element: button, notification: .valueChanged)
            }
            previousAccessibilityValue = accessibilityValue
            Self.logger.debug("Menu bar updated: \(text, privacy: .public) state=\(state.rawValue, privacy: .public)")
        }
    }
}
