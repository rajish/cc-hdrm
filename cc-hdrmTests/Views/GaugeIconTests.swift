import AppKit
import Testing
@testable import cc_hdrm

@Suite("GaugeIcon Tests")
struct GaugeIconTests {

    // MARK: - Gauge Size Tests (AC1, AC2, AC3)

    @Test("Gauge at 100% returns 18x18pt image with needle angle 0 (right)")
    func gaugeAt100Percent() {
        let image = makeGaugeIcon(headroomPercentage: 100, state: .normal)
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)

        let angle = gaugeAngle(for: 100)
        #expect(abs(angle - 0) < 0.001, "Angle should be 0 (pointing right)")
    }

    @Test("Gauge at 0% returns 18x18pt image with needle angle π (left)")
    func gaugeAt0Percent() {
        let image = makeGaugeIcon(headroomPercentage: 0, state: .exhausted)
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)

        let angle = gaugeAngle(for: 0)
        #expect(abs(angle - Double.pi) < 0.001, "Angle should be π (pointing left)")
    }

    @Test("Gauge at 50% returns image with needle angle π/2 (up)")
    func gaugeAt50Percent() {
        let image = makeGaugeIcon(headroomPercentage: 50, state: .caution)
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)

        let angle = gaugeAngle(for: 50)
        #expect(abs(angle - Double.pi / 2) < 0.001, "Angle should be π/2 (pointing up)")
    }

    // MARK: - State Color Tests (AC4)

    @Test("Gauge for each HeadroomState produces valid image")
    func gaugeForAllStates() {
        let states: [(HeadroomState, Double)] = [
            (.normal, 67),
            (.caution, 30),
            (.warning, 15),
            (.critical, 3),
            (.exhausted, 0)
        ]

        for (state, headroom) in states {
            let image = makeGaugeIcon(headroomPercentage: headroom, state: state)
            #expect(image.size.width == 18, "Width should be 18 for state \(state)")
            #expect(image.size.height == 18, "Height should be 18 for state \(state)")
        }
    }

    // MARK: - Template Mode Tests (AC5)

    @Test("Gauge image has isTemplate = false")
    func gaugeNotTemplate() {
        let image = makeGaugeIcon(headroomPercentage: 67, state: .normal)
        #expect(image.isTemplate == false, "Gauge should not be a template image")
    }

    // MARK: - Disconnected Icon Tests (AC6, AC7)

    @Test("Disconnected icon returns 18x18pt image with isTemplate = false")
    func disconnectedIconSize() {
        let image = makeDisconnectedIcon()
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
        #expect(image.isTemplate == false, "Disconnected icon should not be a template image")
    }

    // MARK: - Angle Calculation Tests

    @Test("Angle calculation: boundary values")
    func angleCalculationBoundaries() {
        // 0% headroom → angle = π (left)
        #expect(abs(gaugeAngle(for: 0) - Double.pi) < 0.001)

        // 100% headroom → angle = 0 (right)
        #expect(abs(gaugeAngle(for: 100) - 0) < 0.001)

        // 50% headroom → angle = π/2 (up)
        #expect(abs(gaugeAngle(for: 50) - Double.pi / 2) < 0.001)

        // 25% headroom → angle = 3π/4
        #expect(abs(gaugeAngle(for: 25) - 3 * Double.pi / 4) < 0.001)

        // 75% headroom → angle = π/4
        #expect(abs(gaugeAngle(for: 75) - Double.pi / 4) < 0.001)
    }

    @Test("Angle calculation: clamping values outside 0-100")
    func angleCalculationClamping() {
        // Negative values should clamp to 0 (angle = π)
        #expect(abs(gaugeAngle(for: -10) - Double.pi) < 0.001)

        // Values > 100 should clamp to 100 (angle = 0)
        #expect(abs(gaugeAngle(for: 150) - 0) < 0.001)
    }

    // MARK: - Edge Cases

    @Test("Gauge with negative headroom clamps to 0% without crash")
    func negativeHeadroomClamps() {
        let image = makeGaugeIcon(headroomPercentage: -5, state: .exhausted)
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
    }

    @Test("Gauge with headroom > 100% clamps to 100% without crash")
    func overflowHeadroomClamps() {
        let image = makeGaugeIcon(headroomPercentage: 150, state: .normal)
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
    }
}
