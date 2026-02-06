import AppKit

/// NSPanel subclass that closes on Escape key press.
///
/// Standard NSPanel does not automatically close on Escape.
/// This subclass overrides `cancelOperation(_:)` to close the panel
/// when the user presses Escape, matching expected utility-panel behavior.
final class AnalyticsPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
