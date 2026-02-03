import AppKit
import SwiftUI
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

// MARK: - Color Tests (Story 11.2)

@Suite("SlopeLevel Color Tests")
struct SlopeLevelColorTests {

    // MARK: - SwiftUI Color Tests

    @Test("flat returns secondary color for all headroom states")
    func flatColorIsSecondary() {
        for state in HeadroomState.allCases {
            let color = SlopeLevel.flat.color(for: state)
            #expect(color == .secondary)
        }
    }

    @Test("rising returns headroom color for each state")
    func risingColorMatchesHeadroomState() {
        for state in HeadroomState.allCases {
            let slopeColor = SlopeLevel.rising.color(for: state)
            let expectedColor = Color.headroomColor(for: state)
            #expect(slopeColor == expectedColor)
        }
    }

    @Test("steep returns headroom color for each state")
    func steepColorMatchesHeadroomState() {
        for state in HeadroomState.allCases {
            let slopeColor = SlopeLevel.steep.color(for: state)
            let expectedColor = Color.headroomColor(for: state)
            #expect(slopeColor == expectedColor)
        }
    }

    @Test("rising color varies by headroom state")
    func risingColorVariesByState() {
        // Colors for different states should be visually distinct
        let normalColor = SlopeLevel.rising.color(for: .normal)
        let criticalColor = SlopeLevel.rising.color(for: .critical)
        // SwiftUI Colors from different asset catalog entries are not equal
        #expect(normalColor != criticalColor)
    }

    @Test("steep color varies by headroom state")
    func steepColorVariesByState() {
        let normalColor = SlopeLevel.steep.color(for: .normal)
        let criticalColor = SlopeLevel.steep.color(for: .critical)
        #expect(normalColor != criticalColor)
    }

    // MARK: - NSColor Tests

    @Test("flat returns secondaryLabelColor for all headroom states")
    func flatNSColorIsSecondary() {
        for state in HeadroomState.allCases {
            let color = SlopeLevel.flat.nsColor(for: state)
            #expect(color == .secondaryLabelColor)
        }
    }

    @Test("rising returns headroom NSColor for each state")
    func risingNSColorMatchesHeadroomState() {
        for state in HeadroomState.allCases {
            let slopeColor = SlopeLevel.rising.nsColor(for: state)
            let expectedColor = NSColor.headroomColor(for: state)
            #expect(slopeColor == expectedColor)
        }
    }

    @Test("steep returns headroom NSColor for each state")
    func steepNSColorMatchesHeadroomState() {
        for state in HeadroomState.allCases {
            let slopeColor = SlopeLevel.steep.nsColor(for: state)
            let expectedColor = NSColor.headroomColor(for: state)
            #expect(slopeColor == expectedColor)
        }
    }

    @Test("rising NSColor varies by headroom state")
    func risingNSColorVariesByState() {
        let normalColor = SlopeLevel.rising.nsColor(for: .normal)
        let criticalColor = SlopeLevel.rising.nsColor(for: .critical)
        // Normal (green) and critical (red) should be different
        #expect(normalColor != criticalColor)
    }

    @Test("steep NSColor varies by headroom state")
    func steepNSColorVariesByState() {
        let normalColor = SlopeLevel.steep.nsColor(for: .normal)
        let criticalColor = SlopeLevel.steep.nsColor(for: .critical)
        #expect(normalColor != criticalColor)
    }
}

// MARK: - Actionability Tests (Story 11.2)

@Suite("SlopeLevel Actionability Tests")
struct SlopeLevelActionabilityTests {

    @Test("flat is not actionable")
    func flatNotActionable() {
        #expect(SlopeLevel.flat.isActionable == false)
    }

    @Test("rising is actionable")
    func risingIsActionable() {
        #expect(SlopeLevel.rising.isActionable == true)
    }

    @Test("steep is actionable")
    func steepIsActionable() {
        #expect(SlopeLevel.steep.isActionable == true)
    }

    @Test("only flat is not actionable")
    func onlyFlatNotActionable() {
        let nonActionable = SlopeLevel.allCases.filter { !$0.isActionable }
        #expect(nonActionable.count == 1)
        #expect(nonActionable.contains(.flat))
    }

    @Test("rising and steep are the only actionable levels")
    func actionableLevelsAreRisingAndSteep() {
        let actionable = SlopeLevel.allCases.filter { $0.isActionable }
        #expect(actionable.count == 2)
        #expect(actionable.contains(.rising))
        #expect(actionable.contains(.steep))
    }
}
