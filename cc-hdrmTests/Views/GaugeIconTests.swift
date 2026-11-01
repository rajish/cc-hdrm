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

    // MARK: - 7d Overlay Tests (Story 3.3)

    @Test("Gauge with warning dot overlay produces valid 18x18 image")
    func overlayDotWarning() {
        let image = GaugeIcon.make(headroomPercentage: 83, state: .normal, sevenDayOverlay: .dot(.warning))
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
        #expect(image.isTemplate == false)
    }

    @Test("Gauge with caution dot overlay produces valid 18x18 image")
    func overlayDotCaution() {
        let image = GaugeIcon.make(headroomPercentage: 83, state: .normal, sevenDayOverlay: .dot(.caution))
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
    }

    @Test("Gauge with critical dot overlay produces valid 18x18 image")
    func overlayDotCritical() {
        let image = GaugeIcon.make(headroomPercentage: 83, state: .normal, sevenDayOverlay: .dot(.critical))
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
    }

    @Test("Gauge with promoted overlay produces valid 18x18 image (7d label)")
    func overlayPromoted() {
        let image = GaugeIcon.make(headroomPercentage: 18, state: .warning, sevenDayOverlay: .promoted)
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
    }

    @Test("Gauge with .none overlay produces valid image (backward compat)")
    func overlayNone() {
        let image = GaugeIcon.make(headroomPercentage: 83, state: .normal, sevenDayOverlay: .none)
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
    }

    @Test("Legacy makeGaugeIcon still works (no regression)")
    func legacyMakeGaugeIconStillWorks() {
        let image = makeGaugeIcon(headroomPercentage: 83, state: .normal)
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
        #expect(image.isTemplate == false)
    }

    @Test("Overlay .dot produces image with different pixel data than .none (structural verification)")
    func overlayDotChangesImageData() {
        let baseImage = GaugeIcon.make(headroomPercentage: 83, state: .normal, sevenDayOverlay: .none)
        let dotImage = GaugeIcon.make(headroomPercentage: 83, state: .normal, sevenDayOverlay: .dot(.warning))

        let baseData = baseImage.tiffRepresentation
        let dotData = dotImage.tiffRepresentation

        #expect(baseData != nil)
        #expect(dotData != nil)
        #expect(baseData != dotData, "Dot overlay should produce different pixel data than no overlay")
    }

    @Test("Overlay .promoted produces image with different pixel data than .none (structural verification)")
    func overlayPromotedChangesImageData() {
        let baseImage = GaugeIcon.make(headroomPercentage: 18, state: .warning, sevenDayOverlay: .none)
        let promotedImage = GaugeIcon.make(headroomPercentage: 18, state: .warning, sevenDayOverlay: .promoted)

        let baseData = baseImage.tiffRepresentation
        let promotedData = promotedImage.tiffRepresentation

        #expect(baseData != nil)
        #expect(promotedData != nil)
        #expect(baseData != promotedData, "Promoted overlay should produce different pixel data than no overlay")
    }

    // MARK: - Extra Usage Gauge Tests (Story 17.1)

    @Test("makeExtraUsage returns non-nil 18x18 NSImage")
    func extraUsageGaugeReturnsValidImage() {
        let image = GaugeIcon.makeExtraUsage(remainingFraction: 0.7, utilization: 0.3)
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
        #expect(image.isTemplate == false)
    }

    @Test("extraUsageAngle: remainingFraction=1.0 produces angle at pi (left)")
    func extraUsageAngleFullBalance() {
        let angle = GaugeIcon.extraUsageAngle(for: 1.0)
        #expect(abs(angle - Double.pi) < 0.001, "Full balance should be at pi (left)")
    }

    @Test("extraUsageAngle: remainingFraction=0.0 produces angle at 0 (right)")
    func extraUsageAngleDepleted() {
        let angle = GaugeIcon.extraUsageAngle(for: 0.0)
        #expect(abs(angle - 0) < 0.001, "Depleted should be at 0 (right)")
    }

    @Test("extraUsageAngle: remainingFraction=0.5 produces angle at pi/2 (up)")
    func extraUsageAngleHalfBalance() {
        let angle = GaugeIcon.extraUsageAngle(for: 0.5)
        #expect(abs(angle - Double.pi / 2) < 0.001, "Half balance should be at pi/2 (up)")
    }

    @Test("makeExtraUsageNoLimit returns non-nil 18x18 NSImage")
    func extraUsageNoLimitReturnsValidImage() {
        let image = GaugeIcon.makeExtraUsageNoLimit(utilization: 0.5)
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
        #expect(image.isTemplate == false)
    }

    @Test("makeExtraUsage at remainingFraction=0.0 (fully depleted) renders fill arc")
    func extraUsageFullyDepletedRendersFill() {
        let depleted = GaugeIcon.makeExtraUsage(remainingFraction: 0.0, utilization: 1.0)
        let trackOnly = GaugeIcon.makeExtraUsage(remainingFraction: 1.0, utilization: 0.0)

        let depletedData = depleted.tiffRepresentation
        let trackData = trackOnly.tiffRepresentation

        #expect(depletedData != nil)
        #expect(trackData != nil)
        #expect(depletedData != trackData, "Fully depleted gauge should differ from full balance (fill arc should render)")
    }

    @Test("Extra usage gauge produces different pixel data than headroom gauge")
    func extraUsageGaugeDiffersFromHeadroom() {
        let headroomImage = GaugeIcon.make(headroomPercentage: 50, state: .caution, sevenDayOverlay: .none)
        let extraImage = GaugeIcon.makeExtraUsage(remainingFraction: 0.5, utilization: 0.5)

        let headroomData = headroomImage.tiffRepresentation
        let extraData = extraImage.tiffRepresentation

        #expect(headroomData != nil)
        #expect(extraData != nil)
        #expect(headroomData != extraData, "Extra usage gauge should differ from headroom gauge")
    }
}
