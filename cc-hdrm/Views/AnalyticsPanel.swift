import AppKit

/// NSPanel subclass for the analytics window.
///
/// Overrides:
/// - `cancelOperation(_:)`: closes on Escape key press (standard utility-panel behavior).
/// - `canBecomeKey`: returns `true` so the panel accepts keyboard focus and processes
///   button clicks on the first click. Without this, `.nonactivatingPanel` style requires
///   two clicks — one to focus the panel, one to trigger the button action.
final class AnalyticsPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
