import Testing
@testable import cc_hdrm

/// Tests for TimeRange displayLabel and accessibilityDescription properties
/// added in Story 13.1. Core enum tests (CaseIterable, Sendable, startTimestamp)
/// live in UsageRollupTests.swift from Story 10.4.
@Suite("TimeRange Display Tests")
struct TimeRangeDisplayTests {

    // MARK: - Display Label Tests

    @Test("day displayLabel is '24h'")
    func dayDisplayLabel() {
        #expect(TimeRange.day.displayLabel == "24h")
    }

    @Test("week displayLabel is '7d'")
    func weekDisplayLabel() {
        #expect(TimeRange.week.displayLabel == "7d")
    }

    @Test("month displayLabel is '30d'")
    func monthDisplayLabel() {
        #expect(TimeRange.month.displayLabel == "30d")
    }

    @Test("all displayLabel is 'All'")
    func allDisplayLabel() {
        #expect(TimeRange.all.displayLabel == "All")
    }

    // MARK: - Accessibility Description Tests

    @Test("day accessibilityDescription is 'Last 24 hours'")
    func dayAccessibility() {
        #expect(TimeRange.day.accessibilityDescription == "Last 24 hours")
    }

    @Test("week accessibilityDescription is 'Last 7 days'")
    func weekAccessibility() {
        #expect(TimeRange.week.accessibilityDescription == "Last 7 days")
    }

    @Test("month accessibilityDescription is 'Last 30 days'")
    func monthAccessibility() {
        #expect(TimeRange.month.accessibilityDescription == "Last 30 days")
    }

    @Test("all accessibilityDescription is 'All time'")
    func allAccessibility() {
        #expect(TimeRange.all.accessibilityDescription == "All time")
    }

    // MARK: - Uniqueness Tests

    @Test("all displayLabels are unique")
    func uniqueDisplayLabels() {
        let labels = TimeRange.allCases.map { $0.displayLabel }
        let uniqueLabels = Set(labels)
        #expect(labels.count == uniqueLabels.count)
    }

    @Test("all accessibilityDescriptions are unique")
    func uniqueAccessibilityDescriptions() {
        let descriptions = TimeRange.allCases.map { $0.accessibilityDescription }
        let uniqueDescriptions = Set(descriptions)
        #expect(descriptions.count == uniqueDescriptions.count)
    }

    // MARK: - Ordering Tests

    @Test("displayLabels match expected order for UI rendering")
    func displayLabelsOrder() {
        let expectedLabels = ["24h", "7d", "30d", "All"]
        let actualLabels = TimeRange.allCases.map { $0.displayLabel }
        #expect(actualLabels == expectedLabels)
    }
}
