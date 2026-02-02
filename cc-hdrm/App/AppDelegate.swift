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

        let state = AppState()
        self.appState = state

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
            pollingEngine = PollingEngine(
                keychainService: KeychainService(),
                tokenRefreshService: TokenRefreshService(),
                apiClient: APIClient(),
                appState: state,
                notificationService: notificationService,
                preferencesManager: preferences
            )
        }

        // Create FreshnessMonitor if not already injected (test path)
        if freshnessMonitor == nil {
            freshnessMonitor = FreshnessMonitor(appState: state)
        }

        startObservingAppState()

        Task {
            await pollingEngine?.start()
            await freshnessMonitor?.start()
            await notificationService?.requestAuthorization()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingEngine?.stop()
        freshnessMonitor?.stop()
        observationTask?.cancel()
        observationTask = nil
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

    /// Updates the NSStatusItem's attributed title, color, weight, and accessibility
    /// based on the current AppState.
    internal func updateMenuBarDisplay() {
        guard let appState else { return }

        let state = appState.menuBarHeadroomState
        let text = appState.menuBarText

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
            accessibilityValue = "cc-hdrm: Claude headroom \(headroom) percent, \(state.rawValue)"
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
