import AppKit
import SwiftUI
import os

/// Controls the first-run onboarding NSPanel.
/// Modal panel that forces the user to choose Sign In or Later.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {

    private(set) var panel: NSPanel?

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "onboarding"
    )

    /// Creates the onboarding panel hosting the given SwiftUI view.
    init(contentView: OnboardingView) {
        super.init()

        let panel = OnboardingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        panel.title = "Welcome"
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.moveToActiveSpace]

        // Fixed size — non-resizable
        panel.minSize = NSSize(width: 420, height: 400)
        panel.maxSize = NSSize(width: 420, height: 400)
        panel.isReleasedWhenClosed = false

        panel.delegate = self
        panel.center()

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        self.panel = panel
    }

    /// Shows the onboarding panel and activates the app to bring it to front.
    func show() {
        Self.logger.info("Showing onboarding panel")
        NSApp.activate()
        panel?.makeKeyAndOrderFront(nil)
    }

    /// Dismisses the onboarding panel.
    func dismiss() {
        Self.logger.info("Dismissing onboarding panel")
        panel?.close()
        panel = nil
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Block close button and Escape — user must choose Sign In or Later
        false
    }
}

// MARK: - OnboardingPanel

/// NSPanel subclass that prevents Escape key from closing the window.
private final class OnboardingPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        // No-op: prevent Escape from closing the panel
    }
}
