import Testing
@testable import cc_hdrm

@Suite("HeadroomState Tests")
struct HeadroomStateTests {

    // MARK: - Threshold Boundary Tests

    @Test("nil utilization returns .disconnected")
    func nilUtilizationIsDisconnected() {
        #expect(HeadroomState(from: nil) == .disconnected)
    }

    @Test("utilization 0 (headroom 100%) returns .normal")
    func zeroUtilizationIsNormal() {
        #expect(HeadroomState(from: 0) == .normal)
    }

    @Test("utilization 60 (headroom 40%) returns .normal")
    func headroom40IsNormal() {
        #expect(HeadroomState(from: 60) == .normal)
    }

    @Test("utilization 60.0 (headroom exactly 40%) is .normal boundary")
    func headroomExactly40IsNormal() {
        // headroom = 40, which is >= 40 → .normal
        #expect(HeadroomState(from: 60.0) == .normal)
    }

    @Test("utilization 60.01 (headroom 39.99%) returns .caution")
    func headroomJustBelow40IsCaution() {
        #expect(HeadroomState(from: 60.01) == .caution)
    }

    @Test("utilization 80 (headroom 20%) returns .caution")
    func headroom20IsCaution() {
        // headroom = 20, which is >= 20 and < 40 → .caution
        #expect(HeadroomState(from: 80) == .caution)
    }

    @Test("utilization 80.01 (headroom 19.99%) returns .warning")
    func headroomJustBelow20IsWarning() {
        #expect(HeadroomState(from: 80.01) == .warning)
    }

    @Test("utilization 83 (headroom 17%) returns .warning")
    func utilization83IsWarning() {
        // From dev notes: utilization 83 → headroom 17 → .warning
        #expect(HeadroomState(from: 83) == .warning)
    }

    @Test("utilization 95 (headroom 5%) returns .warning")
    func headroom5IsWarning() {
        // headroom = 5, which is >= 5 and < 20 → .warning
        #expect(HeadroomState(from: 95) == .warning)
    }

    @Test("utilization 95.01 (headroom 4.99%) returns .critical")
    func headroomJustBelow5IsCritical() {
        #expect(HeadroomState(from: 95.01) == .critical)
    }

    @Test("utilization 100 (headroom 0%) returns .exhausted")
    func headroom0IsExhausted() {
        #expect(HeadroomState(from: 100) == .exhausted)
    }

    @Test("utilization > 100 (negative headroom) returns .exhausted")
    func overUtilizationIsExhausted() {
        #expect(HeadroomState(from: 105) == .exhausted)
    }

    @Test("utilization 5 (headroom 95%) returns .normal")
    func lowUtilizationIsNormal() {
        #expect(HeadroomState(from: 5) == .normal)
    }

    // MARK: - Color Token Name Tests

    @Test("each state has correct color token name")
    func colorTokenNames() {
        #expect(HeadroomState.normal.colorTokenName == "HeadroomNormal")
        #expect(HeadroomState.caution.colorTokenName == "HeadroomCaution")
        #expect(HeadroomState.warning.colorTokenName == "HeadroomWarning")
        #expect(HeadroomState.critical.colorTokenName == "HeadroomCritical")
        #expect(HeadroomState.exhausted.colorTokenName == "HeadroomExhausted")
        #expect(HeadroomState.disconnected.colorTokenName == "Disconnected")
    }

    // MARK: - Font Weight Tests

    @Test("each state has correct font weight")
    func fontWeights() {
        #expect(HeadroomState.normal.fontWeight == "regular")
        #expect(HeadroomState.caution.fontWeight == "medium")
        #expect(HeadroomState.warning.fontWeight == "semibold")
        #expect(HeadroomState.critical.fontWeight == "bold")
        #expect(HeadroomState.exhausted.fontWeight == "heavy")
        #expect(HeadroomState.disconnected.fontWeight == "regular")
    }
}
