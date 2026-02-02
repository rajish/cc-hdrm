import SwiftUI
import Testing
@testable import cc_hdrm

@Suite("HeadroomRingGauge Tests")
struct HeadroomRingGaugeTests {

    @Test("Gauge instantiates with normal headroom percentage without crash")
    @MainActor
    func normalHeadroom() {
        let gauge = HeadroomRingGauge(
            headroomPercentage: 83,
            windowLabel: "5h",
            ringSize: 96,
            strokeWidth: 7
        )
        _ = gauge.body
    }

    @Test("Gauge instantiates with nil percentage (disconnected) without crash")
    @MainActor
    func disconnectedState() {
        let gauge = HeadroomRingGauge(
            headroomPercentage: nil,
            windowLabel: "5h",
            ringSize: 96,
            strokeWidth: 7
        )
        _ = gauge.body
    }

    @Test("Gauge instantiates with 0% headroom (exhausted) without crash")
    @MainActor
    func exhaustedState() {
        let gauge = HeadroomRingGauge(
            headroomPercentage: 0,
            windowLabel: "5h",
            ringSize: 96,
            strokeWidth: 7
        )
        _ = gauge.body
    }

    @Test("Gauge instantiates with 100% headroom (full capacity) without crash")
    @MainActor
    func fullCapacity() {
        let gauge = HeadroomRingGauge(
            headroomPercentage: 100,
            windowLabel: "5h",
            ringSize: 96,
            strokeWidth: 7
        )
        _ = gauge.body
    }

    @Test("HeadroomState derivation: various percentages map to correct states")
    func headroomStateDerivation() {
        // > 40% headroom = normal (utilization < 60)
        #expect(HeadroomState(from: 50.0) == .normal)
        // 20-40% headroom = caution (utilization 60-80)
        #expect(HeadroomState(from: 65.0) == .caution)
        // 5-20% headroom = warning (utilization 80-95)
        #expect(HeadroomState(from: 88.0) == .warning)
        // < 5% headroom = critical (utilization 95-100)
        #expect(HeadroomState(from: 97.0) == .critical)
        // 0% headroom = exhausted (utilization 100)
        #expect(HeadroomState(from: 100.0) == .exhausted)
        // nil = disconnected
        #expect(HeadroomState(from: nil) == .disconnected)
    }

    @Test("Gauge with negative headroom percentage clamps to 0% without crash")
    @MainActor
    func negativeHeadroom() {
        let gauge = HeadroomRingGauge(
            headroomPercentage: -5.0,
            windowLabel: "5h",
            ringSize: 96,
            strokeWidth: 7
        )
        _ = gauge.body
    }

    @Test("Gauge with 7d secondary size instantiates without crash")
    @MainActor
    func secondarySize() {
        let gauge = HeadroomRingGauge(
            headroomPercentage: 45,
            windowLabel: "7d",
            ringSize: 56,
            strokeWidth: 4
        )
        _ = gauge.body
    }
}
