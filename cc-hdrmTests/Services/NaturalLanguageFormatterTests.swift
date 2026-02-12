import Foundation
import Testing
@testable import cc_hdrm

@Suite("NaturalLanguageFormatter Tests")
struct NaturalLanguageFormatterTests {

    // MARK: - formatPercentNatural

    @Test("Low percentage (0-10%) returns 'a small fraction'")
    func lowPercentage() {
        #expect(NaturalLanguageFormatter.formatPercentNatural(5) == "a small fraction")
        #expect(NaturalLanguageFormatter.formatPercentNatural(0) == "a small fraction")
        #expect(NaturalLanguageFormatter.formatPercentNatural(9.9) == "a small fraction")
    }

    @Test("Quarter range (20-30%) returns 'about a quarter'")
    func quarterPercentage() {
        #expect(NaturalLanguageFormatter.formatPercentNatural(20) == "about a quarter")
        #expect(NaturalLanguageFormatter.formatPercentNatural(25) == "about a quarter")
    }

    @Test("Half range (45-55%) returns 'roughly half'")
    func halfPercentage() {
        #expect(NaturalLanguageFormatter.formatPercentNatural(50) == "roughly half")
        #expect(NaturalLanguageFormatter.formatPercentNatural(45) == "roughly half")
        #expect(NaturalLanguageFormatter.formatPercentNatural(54) == "roughly half")
    }

    @Test("Three-quarters range (70-80%) returns 'about three-quarters'")
    func threeQuartersPercentage() {
        #expect(NaturalLanguageFormatter.formatPercentNatural(72) == "about three-quarters")
        #expect(NaturalLanguageFormatter.formatPercentNatural(75) == "about three-quarters")
    }

    @Test("High percentage (90-100%) returns 'nearly all'")
    func highPercentage() {
        #expect(NaturalLanguageFormatter.formatPercentNatural(95) == "nearly all")
        #expect(NaturalLanguageFormatter.formatPercentNatural(100) == "nearly all")
    }

    @Test("Most range (85-95%) returns 'most'")
    func mostPercentage() {
        #expect(NaturalLanguageFormatter.formatPercentNatural(88) == "most")
    }

    @Test("Boundary values produce correct results at range edges")
    func boundaryValues() {
        // 10% boundary
        #expect(NaturalLanguageFormatter.formatPercentNatural(9.9) == "a small fraction")
        #expect(NaturalLanguageFormatter.formatPercentNatural(10) == "about a tenth")
        // 20% boundary
        #expect(NaturalLanguageFormatter.formatPercentNatural(19.9) == "about a tenth")
        #expect(NaturalLanguageFormatter.formatPercentNatural(20) == "about a quarter")
        // 60% boundary
        #expect(NaturalLanguageFormatter.formatPercentNatural(59.9) == "roughly half")
        #expect(NaturalLanguageFormatter.formatPercentNatural(60) == "about two-thirds")
        // 90% boundary
        #expect(NaturalLanguageFormatter.formatPercentNatural(89.9) == "most")
        #expect(NaturalLanguageFormatter.formatPercentNatural(90) == "nearly all")
    }

    // MARK: - formatComparisonNatural

    @Test("Roughly double (ratio > 1.8)")
    func roughlyDouble() {
        #expect(NaturalLanguageFormatter.formatComparisonNatural(current: 180, baseline: 90) == "roughly double your usual")
    }

    @Test("Noticeably more (ratio 1.3-1.8)")
    func noticeablyMore() {
        #expect(NaturalLanguageFormatter.formatComparisonNatural(current: 150, baseline: 100) == "noticeably more than typical")
    }

    @Test("Close to average (ratio 0.7-1.3)")
    func closeToAverage() {
        #expect(NaturalLanguageFormatter.formatComparisonNatural(current: 100, baseline: 100) == "close to your average")
        #expect(NaturalLanguageFormatter.formatComparisonNatural(current: 80, baseline: 100) == "close to your average")
    }

    @Test("About half (ratio 0.4-0.7)")
    func aboutHalf() {
        #expect(NaturalLanguageFormatter.formatComparisonNatural(current: 50, baseline: 100) == "about half your usual")
    }

    @Test("Well below (ratio < 0.4)")
    func wellBelow() {
        #expect(NaturalLanguageFormatter.formatComparisonNatural(current: 20, baseline: 100) == "well below your usual")
    }

    @Test("Zero baseline returns fallback")
    func zeroBaseline() {
        #expect(NaturalLanguageFormatter.formatComparisonNatural(current: 50, baseline: 0) == "no baseline available")
    }

    // MARK: - formatRelativeTimeNatural

    @Test("Same year omits year")
    func sameYear() {
        let currentYear = Calendar.current.component(.year, from: Date())
        let result = NaturalLanguageFormatter.formatRelativeTimeNatural(monthName: "March", year: currentYear)
        #expect(result == "since March")
    }

    @Test("Different year includes year")
    func differentYear() {
        let result = NaturalLanguageFormatter.formatRelativeTimeNatural(monthName: "November", year: 2024)
        #expect(result == "since November 2024")
    }

    @Test("Nil year omits year")
    func nilYear() {
        let result = NaturalLanguageFormatter.formatRelativeTimeNatural(monthName: "July")
        #expect(result == "since July")
    }

    // MARK: - monthName

    @Test("monthName returns correct names")
    func monthNameCorrectness() {
        #expect(NaturalLanguageFormatter.monthName(for: 1) == "January")
        #expect(NaturalLanguageFormatter.monthName(for: 6) == "June")
        #expect(NaturalLanguageFormatter.monthName(for: 12) == "December")
    }
}
