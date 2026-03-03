import Foundation
import Testing
@testable import cc_hdrm

@Suite("OutagePeriod Model Tests")
struct OutagePeriodTests {

    @Test("isOngoing returns true when endedAt is nil")
    func isOngoingWhenEndedAtNil() {
        let outage = OutagePeriod(id: 1, startedAt: 1000, endedAt: nil, failureReason: "networkUnreachable")
        #expect(outage.isOngoing == true)
    }

    @Test("isOngoing returns false when endedAt is set")
    func isNotOngoingWhenEndedAtSet() {
        let outage = OutagePeriod(id: 1, startedAt: 1000, endedAt: 2000, failureReason: "networkUnreachable")
        #expect(outage.isOngoing == false)
    }

    @Test("startDate converts Unix ms to Date correctly")
    func startDateConversion() {
        let timestampMs: Int64 = 1_704_067_200_000 // 2024-01-01 00:00:00 UTC
        let outage = OutagePeriod(id: 1, startedAt: timestampMs, endedAt: nil, failureReason: "test")
        let expected = Date(timeIntervalSince1970: 1_704_067_200)
        #expect(outage.startDate == expected)
    }

    @Test("endDate returns nil when endedAt is nil")
    func endDateNilWhenOngoing() {
        let outage = OutagePeriod(id: 1, startedAt: 1000, endedAt: nil, failureReason: "test")
        #expect(outage.endDate == nil)
    }

    @Test("endDate converts Unix ms to Date correctly when set")
    func endDateConversion() {
        let endMs: Int64 = 1_704_153_600_000 // 2024-01-02 00:00:00 UTC
        let outage = OutagePeriod(id: 1, startedAt: 1000, endedAt: endMs, failureReason: "test")
        let expected = Date(timeIntervalSince1970: 1_704_153_600)
        #expect(outage.endDate == expected)
    }

    @Test("Equatable conformance works correctly")
    func equatableConformance() {
        let a = OutagePeriod(id: 1, startedAt: 1000, endedAt: 2000, failureReason: "networkUnreachable")
        let b = OutagePeriod(id: 1, startedAt: 1000, endedAt: 2000, failureReason: "networkUnreachable")
        let c = OutagePeriod(id: 2, startedAt: 1000, endedAt: 2000, failureReason: "networkUnreachable")
        #expect(a == b)
        #expect(a != c)
    }
}
