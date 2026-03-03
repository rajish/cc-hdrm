import AppKit
import SwiftUI
import Testing
@testable import cc_hdrm

@Suite("InteractionOverlay Tests")
@MainActor
struct InteractionOverlayTests {

    @Test("InteractionOverlay renders via NSHostingView without crash")
    func instantiation() {
        let overlay = InteractionOverlay(onTap: {}, onHoverChange: { _ in })
        let hosting = NSHostingView(rootView: overlay.frame(width: 100, height: 100))
        #expect(hosting.frame.size.width >= 0, "Hosting view should have valid frame")
    }

    @Test("InteractionOverlay renders with nil callbacks without crash")
    func instantiationNilCallbacks() {
        let overlay = InteractionOverlay(onTap: nil, onHoverChange: nil)
        let hosting = NSHostingView(rootView: overlay.frame(width: 100, height: 100))
        #expect(hosting.frame.size.width >= 0, "Hosting view should have valid frame")
    }
}
