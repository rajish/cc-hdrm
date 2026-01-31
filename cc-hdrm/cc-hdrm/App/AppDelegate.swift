import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "AppDelegate"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.logger.info("Application launching — configuring menu bar status item")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = "\u{2733} --"
            button.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.contentTintColor = .systemGray
        }

        Self.logger.info("Menu bar status item configured with placeholder")
    }
}
