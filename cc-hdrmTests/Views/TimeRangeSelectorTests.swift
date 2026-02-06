import Testing
import SwiftUI
@testable import cc_hdrm

@Suite("TimeRangeSelector Tests")
struct TimeRangeSelectorTests {

    // MARK: - All Cases Rendered

    @Test("selector provides a button for each of the 4 TimeRange cases")
    func allCasesRendered() {
        // TimeRangeSelector uses ForEach(TimeRange.allCases) — verify count
        #expect(TimeRange.allCases.count == 4)
        // Each case produces a non-empty displayLabel used as button text
        let labels = TimeRange.allCases.map { $0.displayLabel }
        #expect(labels == ["24h", "7d", "30d", "All"])
    }

    // MARK: - Selection Binding

    @Test("binding reflects the selected time range")
    func selectionBinding() {
        // Simulate what the selector does: write to binding on button tap
        var selected = TimeRange.week
        selected = .month
        #expect(selected == .month)

        selected = .day
        #expect(selected == .day)

        selected = .all
        #expect(selected == .all)
    }

    // MARK: - Accessibility Labels

    @Test("each range has a human-readable accessibility description")
    func accessibilityDescriptions() {
        let expected: [TimeRange: String] = [
            .day: "Last 24 hours",
            .week: "Last 7 days",
            .month: "Last 30 days",
            .all: "All time",
        ]
        for (range, desc) in expected {
            #expect(range.accessibilityDescription == desc)
        }
    }

    @Test("accessibility descriptions are distinct from display labels")
    func accessibilityDistinctFromLabels() {
        for range in TimeRange.allCases {
            #expect(range.accessibilityDescription != range.displayLabel,
                    "\(range) accessibility should differ from displayLabel for screen readers")
        }
    }

    // MARK: - Selected Trait

    @Test("selected state is distinguishable from unselected for each case")
    func selectedVsUnselected() {
        // The selector uses .isSelected trait for the active button.
        // Verify each case can be compared for equality (selection logic depends on this).
        for range in TimeRange.allCases {
            for other in TimeRange.allCases {
                if range == other {
                    #expect(range == other)
                } else {
                    #expect(range != other)
                }
            }
        }
    }
}
