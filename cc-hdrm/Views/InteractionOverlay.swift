import AppKit
import SwiftUI

/// AppKit overlay that provides reliable hand cursor and click handling.
///
/// Uses `cursorUpdate(with:)` via `.cursorUpdate` tracking area option. This fires
/// continuously while the cursor is inside the tracking area, regardless of key-window
/// status. Overriding without calling `super` bypasses the cursor rect system entirely,
/// which is critical because NSPopover windows are not key by default.
///
/// Previous approaches that failed in NSPopover context:
/// 1. `.onHover` + `NSCursor.push()`/`pop()` — cursor stack corrupted on window changes
/// 2. `.onHover` + `NSCursor.set()` — overridden by cursor rect system of key window
/// 3. `addCursorRect` + `window?.makeKey()` — makeKey doesn't stick for popover windows
struct InteractionOverlay: NSViewRepresentable {
    var onTap: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?

    func makeNSView(context: Context) -> InteractionNSView {
        let view = InteractionNSView()
        view.onTap = onTap
        view.onHoverChange = onHoverChange
        return view
    }

    func updateNSView(_ nsView: InteractionNSView, context: Context) {
        nsView.onTap = onTap
        nsView.onHoverChange = onHoverChange
    }

    final class InteractionNSView: NSView {
        var onTap: (() -> Void)?
        var onHoverChange: ((Bool) -> Void)?

        // --- Cursor ---
        // Two complementary mechanisms:
        // 1. addCursorRect: works when this window IS key (AppDelegate.togglePopover
        //    calls makeKey() after showing the popover).
        // 2. cursorUpdate(with:) without calling super: bypasses the cursor rect
        //    system for edge cases where the window loses key status.

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas {
                removeTrackingArea(area)
            }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
        }

        override func cursorUpdate(with event: NSEvent) {
            // Do NOT call super — that would invoke the cursor rect system,
            // which resets to arrow for non-key windows (i.e., NSPopover).
            NSCursor.pointingHand.set()
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChange?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChange?(false)
        }

        // --- Click ---

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseUp(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            if bounds.contains(location) {
                onTap?()
            }
        }
    }
}
