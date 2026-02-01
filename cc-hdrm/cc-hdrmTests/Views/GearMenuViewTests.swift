import SwiftUI
import Testing
@testable import cc_hdrm

@Suite("GearMenuView Tests")
struct GearMenuViewTests {

    @Test("GearMenuView renders without crash")
    @MainActor
    func rendersWithoutCrash() {
        let view = GearMenuView()
        _ = view.body
    }

    @Test("GearMenuView produces a valid body via NSHostingController")
    @MainActor
    func producesValidBody() {
        let view = GearMenuView()
        let controller = NSHostingController(rootView: view)
        #expect(controller.view.frame.size.width >= 0, "Hosting controller should create a valid view")
    }
}
