import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private(set) var appState: AppState?
    private let keychainService: any KeychainServiceProtocol
    private var pollingTask: Task<Void, Never>?

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "AppDelegate"
    )

    override init() {
        self.keychainService = KeychainService()
        super.init()
    }

    /// Test-only initializer for injecting a mock keychain service.
    init(keychainService: any KeychainServiceProtocol) {
        self.keychainService = keychainService
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

        // Initial credential read and start polling
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.performCredentialRead()
            await self.startPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingTask?.cancel()
    }

    private func performCredentialRead() async {
        guard let appState else { return }
        do {
            let credentials = try await keychainService.readCredentials()
            appState.updateSubscriptionTier(credentials.subscriptionType)
            appState.updateConnectionStatus(.connected)
            appState.updateStatusMessage(nil)
            Self.logger.info("Credentials found — connection status set to connected")
        } catch {
            handleCredentialError(error, appState: appState)
        }
    }

    private func handleCredentialError(_ error: any Error, appState: AppState) {
        appState.updateConnectionStatus(.noCredentials)
        appState.updateStatusMessage(StatusMessage(
            title: "No Claude credentials found",
            detail: "Run Claude Code to create them"
        ))

        if let appError = error as? AppError {
            switch appError {
            case .keychainNotFound:
                Self.logger.info("No credentials in Keychain — waiting for user to run Claude Code")
            case .keychainAccessDenied:
                Self.logger.error("Keychain access denied")
            case .keychainInvalidFormat:
                Self.logger.error("Keychain contains malformed credential data")
            default:
                Self.logger.error("Unexpected error reading credentials: \(String(describing: appError))")
            }
        }
    }

    private func startPolling() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { break }
            await performCredentialRead()
        }
    }
}
