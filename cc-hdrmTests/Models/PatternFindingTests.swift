import Foundation
import Testing
@testable import cc_hdrm

@Suite("PatternFinding Tests")
struct PatternFindingTests {

    // MARK: - Title Tests

    @Test("forgottenSubscription title")
    func forgottenSubscriptionTitle() {
        let finding = PatternFinding.forgottenSubscription(weeks: 3, avgUtilization: 2.5, monthlyCost: 20.0)
        #expect(finding.title == "Subscription check-in")
    }

    @Test("chronicOverpaying title")
    func chronicOverpayingTitle() {
        let finding = PatternFinding.chronicOverpaying(currentTier: "Max 5x", recommendedTier: "Pro", monthlySavings: 80.0)
        #expect(finding.title == "Tier recommendation")
    }

    @Test("chronicUnderpowering title")
    func chronicUnderpoweringTitle() {
        let finding = PatternFinding.chronicUnderpowering(rateLimitCount: 5, currentTier: "Pro", suggestedTier: "Max 5x")
        #expect(finding.title == "Tier recommendation")
    }

    @Test("usageDecay title")
    func usageDecayTitle() {
        let finding = PatternFinding.usageDecay(currentUtil: 30.0, threeMonthAgoUtil: 70.0)
        #expect(finding.title == "Usage trend")
    }

    @Test("extraUsageOverflow title")
    func extraUsageOverflowTitle() {
        let finding = PatternFinding.extraUsageOverflow(avgExtraSpend: 47.0, recommendedTier: "Max 5x", estimatedSavings: 67.0)
        #expect(finding.title == "Extra usage alert")
    }

    @Test("persistentExtraUsage title")
    func persistentExtraUsageTitle() {
        let finding = PatternFinding.persistentExtraUsage(avgMonthlyExtra: 15.0, basePrice: 20.0, recommendedTier: "Max 5x")
        #expect(finding.title == "Extra usage alert")
    }

    // MARK: - Summary Tests

    @Test("forgottenSubscription summary includes weeks and cost")
    func forgottenSubscriptionSummary() {
        let finding = PatternFinding.forgottenSubscription(weeks: 3, avgUtilization: 2.5, monthlyCost: 20.0)
        let summary = finding.summary
        #expect(summary.contains("3 weeks"))
        #expect(summary.contains("$20/mo"))
    }

    @Test("chronicOverpaying summary includes recommended tier and savings")
    func chronicOverpayingSummary() {
        let finding = PatternFinding.chronicOverpaying(currentTier: "Max 5x", recommendedTier: "Pro", monthlySavings: 80.0)
        let summary = finding.summary
        #expect(summary.contains("Pro"))
        #expect(summary.contains("$80/mo"))
    }

    @Test("chronicUnderpowering summary includes rate-limit count and suggested tier")
    func chronicUnderpoweringSummary() {
        let finding = PatternFinding.chronicUnderpowering(rateLimitCount: 5, currentTier: "Pro", suggestedTier: "Max 5x")
        let summary = finding.summary
        #expect(summary.contains("5 times"))
        #expect(summary.contains("Max 5x"))
    }

    @Test("usageDecay summary includes utilization change")
    func usageDecaySummary() {
        let finding = PatternFinding.usageDecay(currentUtil: 30.0, threeMonthAgoUtil: 70.0)
        let summary = finding.summary
        #expect(summary.contains("70%"))
        #expect(summary.contains("30%"))
        #expect(summary.contains("40 points"))
    }

    @Test("extraUsageOverflow summary includes spend and savings")
    func extraUsageOverflowSummary() {
        let finding = PatternFinding.extraUsageOverflow(avgExtraSpend: 47.0, recommendedTier: "Max 5x", estimatedSavings: 67.0)
        let summary = finding.summary
        #expect(summary.contains("$47/mo"))
        #expect(summary.contains("Max 5x"))
        #expect(summary.contains("$67/mo"))
    }

    @Test("persistentExtraUsage summary includes percentage of base")
    func persistentExtraUsageSummary() {
        let finding = PatternFinding.persistentExtraUsage(avgMonthlyExtra: 15.0, basePrice: 20.0, recommendedTier: "Max 5x")
        let summary = finding.summary
        #expect(summary.contains("75%"))
        #expect(summary.contains("$15"))
        #expect(summary.contains("$20"))
    }

    // MARK: - Equatable Tests

    @Test("forgottenSubscription equatable")
    func forgottenSubscriptionEquatable() {
        let a = PatternFinding.forgottenSubscription(weeks: 3, avgUtilization: 2.5, monthlyCost: 20.0)
        let b = PatternFinding.forgottenSubscription(weeks: 3, avgUtilization: 2.5, monthlyCost: 20.0)
        let c = PatternFinding.forgottenSubscription(weeks: 4, avgUtilization: 2.5, monthlyCost: 20.0)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("different cases are not equal")
    func differentCasesNotEqual() {
        let a = PatternFinding.forgottenSubscription(weeks: 3, avgUtilization: 2.5, monthlyCost: 20.0)
        let b = PatternFinding.usageDecay(currentUtil: 30.0, threeMonthAgoUtil: 70.0)
        #expect(a != b)
    }
}
