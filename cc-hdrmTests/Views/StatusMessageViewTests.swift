import SwiftUI
import Testing
@testable import cc_hdrm

@Suite("StatusMessageView Tests")
struct StatusMessageViewTests {

    @Test("StatusMessageView renders with title and detail without crash")
    @MainActor
    func instantiationDoesNotCrash() {
        let view = StatusMessageView(title: "Unable to reach Claude API", detail: "Last attempt: 30s ago")
        _ = view.body
    }

    @Test("StatusMessageView renders with long multi-line title without crash")
    @MainActor
    func longMultiLineTitleDoesNotCrash() {
        let longTitle = String(repeating: "This is a very long status message title. ", count: 10)
        let view = StatusMessageView(title: longTitle, detail: "Some detail text that is also quite long and might wrap to multiple lines")
        _ = view.body
    }

    @Test("StatusMessageView can be hosted in NSHostingController")
    @MainActor
    func hostingControllerInstantiation() {
        let view = StatusMessageView(title: "Token expired", detail: "Run any Claude Code command to refresh")
        let controller = NSHostingController(rootView: view)
        #expect(controller.view.frame.size.width >= 0, "Hosting controller should create a valid view")
    }
}
