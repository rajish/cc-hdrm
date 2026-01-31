import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    internal var appState: AppState?
    private var pollingEngine: (any PollingEngineProtocol)?

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "AppDelegate"
    )

    override init() {
        super.init()
    }

    /// Test-only initializer for injecting a mock polling engine.
    init(pollingEngine: any PollingEngineProtocol) {
        self.pollingEngine = pollingEngine
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.logger.info("Application launching — configuring menu bar status item")

        let state = AppState()
        self.appState = state

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = "\u{2733} --"
            button.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.contentTintColor = .systemGray
        }

        Self.logger.info("Menu bar status item configured with placeholder")

        // Create PollingEngine with production services if not already injected (test path)
        if pollingEngine == nil {
            pollingEngine = PollingEngine(
                keychainService: KeychainService(),
                tokenRefreshService: TokenRefreshService(),
                apiClient: APIClient(),
                appState: state
            )
        }

        Task {
            await pollingEngine?.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingEngine?.stop()
    }
}
