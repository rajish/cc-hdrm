import Testing
@testable import cc_hdrm

@Suite("SlopeLevel Tests")
struct SlopeLevelTests {

    // MARK: - Arrow Symbol Tests

    @Test("flat level has right arrow →")
    func flatArrow() {
        #expect(SlopeLevel.flat.arrow == "→")
    }

    @Test("rising level has diagonal up arrow ↗")
    func risingArrow() {
        #expect(SlopeLevel.rising.arrow == "↗")
    }

    @Test("steep level has up arrow ⬆")
    func steepArrow() {
        #expect(SlopeLevel.steep.arrow == "⬆")
    }

    // MARK: - Accessibility Label Tests

    @Test("flat level accessibility label is 'flat'")
    func flatAccessibility() {
        #expect(SlopeLevel.flat.accessibilityLabel == "flat")
    }

    @Test("rising level accessibility label is 'rising'")
    func risingAccessibility() {
        #expect(SlopeLevel.rising.accessibilityLabel == "rising")
    }

    @Test("steep level accessibility label is 'steep'")
    func steepAccessibility() {
        #expect(SlopeLevel.steep.accessibilityLabel == "steep")
    }

    // MARK: - CaseIterable Tests

    @Test("SlopeLevel has exactly 3 cases — no cooling level")
    func exactlyThreeCases() {
        #expect(SlopeLevel.allCases.count == 3)
        #expect(SlopeLevel.allCases.contains(.flat))
        #expect(SlopeLevel.allCases.contains(.rising))
        #expect(SlopeLevel.allCases.contains(.steep))
    }

    // MARK: - Equatable Tests

    @Test("SlopeLevel conforms to Equatable")
    func equatable() {
        let level1 = SlopeLevel.flat
        let level2 = SlopeLevel.flat
        let level3 = SlopeLevel.rising
        #expect(level1 == level2)
        #expect(level1 != level3)
    }

    // MARK: - RawValue Tests

    @Test("rawValue is the enum case name")
    func rawValues() {
        #expect(SlopeLevel.flat.rawValue == "flat")
        #expect(SlopeLevel.rising.rawValue == "rising")
        #expect(SlopeLevel.steep.rawValue == "steep")
    }
}
