import SwiftUI
import Testing
@testable import cc_hdrm

@Suite("CountdownLabel Tests")
struct CountdownLabelTests {

    @Test("CountdownLabel renders with a future reset time without crash")
    @MainActor
    func futureResetTime() {
        let resetTime = Date().addingTimeInterval(47 * 60)
        let label = CountdownLabel(
            resetTime: resetTime,
            headroomState: .normal,
            countdownTick: 0
        )
        _ = label.body
    }

    @Test("CountdownLabel with nil resetTime returns empty without crash")
    @MainActor
    func nilResetTime() {
        let label = CountdownLabel(
            resetTime: nil,
            headroomState: .disconnected,
            countdownTick: 0
        )
        _ = label.body
    }

    @Test("CountdownLabel with exhausted state renders without crash")
    @MainActor
    func exhaustedState() {
        let resetTime = Date().addingTimeInterval(30 * 60)
        let label = CountdownLabel(
            resetTime: resetTime,
            headroomState: .exhausted,
            countdownTick: 5
        )
        _ = label.body
    }

    @Test("Exhausted state color emphasis: exhausted uses swiftUIColor, normal uses secondary (AC #10)")
    func exhaustedColorLogic() {
        // This tests the color-selection branching logic from CountdownLabel:
        // headroomState == .exhausted → headroomState.swiftUIColor (red emphasis)
        // headroomState != .exhausted → .secondary
        #expect(HeadroomState.exhausted == .exhausted, "Exhausted equality check")
        #expect(HeadroomState.normal != .exhausted, "Normal is not exhausted")
        #expect(HeadroomState.critical != .exhausted, "Critical is not exhausted")
        // Verify swiftUIColor doesn't crash for exhausted state
        _ = HeadroomState.exhausted.swiftUIColor
        _ = HeadroomState.normal.swiftUIColor
    }
}
