import Foundation
import Testing
import UserNotifications
@testable import cc_hdrm

@Suite("PatternNotificationService Tests")
@MainActor
struct PatternNotificationServiceTests {
    let spy = SpyNotificationCenter()
    let prefs = MockPreferencesManager()
    let mockNotificationService = MockNotificationService()

    func makeSUT() -> PatternNotificationService {
        mockNotificationService.isAuthorized = true
        return PatternNotificationService(
            notificationCenter: spy,
            preferencesManager: prefs,
            notificationService: mockNotificationService
        )
    }

    // MARK: - Notification Text (AC: 1-3)

    @Test("forgottenSubscription delivers notification with correct text")
    func forgottenSubscriptionNotification() async {
        let sut = makeSUT()
        let finding = PatternFinding.forgottenSubscription(weeks: 4, avgUtilization: 2.0, monthlyCost: 20.0)

        await sut.processFindings([finding])

        #expect(spy.addedRequests.count == 1)
        let content = spy.addedRequests[0].content
        #expect(content.title == "Subscription check-in")
        #expect(content.body.contains("4 weeks"))
        #expect(content.body.contains("less than 5%"))
    }

    @Test("chronicOverpaying delivers notification with correct text")
    func chronicOverpayingNotification() async {
        let sut = makeSUT()
        let finding = PatternFinding.chronicOverpaying(currentTier: "Max 5x", recommendedTier: "Pro", monthlySavings: 80.0)

        await sut.processFindings([finding])

        #expect(spy.addedRequests.count == 1)
        let content = spy.addedRequests[0].content
        #expect(content.title == "Tier recommendation")
        #expect(content.body.contains("Pro"))
        #expect(content.body.contains("$80/mo"))
    }

    @Test("chronicUnderpowering delivers notification with correct text")
    func chronicUnderpoweringNotification() async {
        let sut = makeSUT()
        let finding = PatternFinding.chronicUnderpowering(rateLimitCount: 8, currentTier: "Pro", suggestedTier: "Max 5x")

        await sut.processFindings([finding])

        #expect(spy.addedRequests.count == 1)
        let content = spy.addedRequests[0].content
        #expect(content.title == "Tier recommendation")
        #expect(content.body.contains("8 times"))
        #expect(content.body.contains("Max 5x"))
    }

    // MARK: - Cooldown (AC: 4)

    @Test("cooldown prevents duplicate notification within 30 days")
    func cooldownPreventsDuplicate() async {
        let sut = makeSUT()
        let finding = PatternFinding.forgottenSubscription(weeks: 3, avgUtilization: 2.0, monthlyCost: 20.0)

        // First call should deliver
        await sut.processFindings([finding])
        #expect(spy.addedRequests.count == 1)

        // Second call within cooldown should not deliver
        await sut.processFindings([finding])
        #expect(spy.addedRequests.count == 1)
    }

    @Test("cooldown expired allows re-notification")
    func cooldownExpiredAllowsReNotification() async {
        let sut = makeSUT()
        let finding = PatternFinding.forgottenSubscription(weeks: 3, avgUtilization: 2.0, monthlyCost: 20.0)

        // Set cooldown to 31 days ago
        let expiredDate = Date().addingTimeInterval(-31 * 24 * 60 * 60)
        prefs.patternNotificationCooldowns = [finding.cooldownKey: expiredDate]

        await sut.processFindings([finding])
        #expect(spy.addedRequests.count == 1)
    }

    @Test("cooldown timestamp updated after notification")
    func cooldownUpdatedAfterNotification() async {
        let sut = makeSUT()
        let finding = PatternFinding.chronicOverpaying(currentTier: "Max 5x", recommendedTier: "Pro", monthlySavings: 80.0)

        await sut.processFindings([finding])

        let cooldown = prefs.patternNotificationCooldowns[finding.cooldownKey]
        #expect(cooldown != nil)
        // Cooldown should be within the last few seconds
        if let cd = cooldown {
            #expect(abs(cd.timeIntervalSinceNow) < 5.0)
        }
    }

    // MARK: - Authorization (AC: 6)

    @Test("notifications skipped when not authorized")
    func skippedWhenNotAuthorized() async {
        let sut = PatternNotificationService(
            notificationCenter: spy,
            preferencesManager: prefs,
            notificationService: mockNotificationService
        )
        mockNotificationService.isAuthorized = false

        let finding = PatternFinding.forgottenSubscription(weeks: 3, avgUtilization: 2.0, monthlyCost: 20.0)
        await sut.processFindings([finding])

        #expect(spy.addedRequests.isEmpty)
    }

    // MARK: - Non-notifiable Types

    @Test("usageDecay does not trigger notification")
    func usageDecayNoNotification() async {
        let sut = makeSUT()
        let finding = PatternFinding.usageDecay(currentUtil: 30.0, threeMonthAgoUtil: 70.0)

        await sut.processFindings([finding])
        #expect(spy.addedRequests.isEmpty)
    }

    @Test("extraUsageOverflow triggers notification with correct text")
    func extraUsageOverflowNotification() async {
        let sut = makeSUT()
        let finding = PatternFinding.extraUsageOverflow(avgExtraSpend: 50.0, recommendedTier: "Max 5x", estimatedSavings: 30.0)

        await sut.processFindings([finding])
        #expect(spy.addedRequests.count == 1)
        let content = spy.addedRequests[0].content
        #expect(content.title == "Extra usage alert")
        #expect(content.body.contains("$50"))
        #expect(content.body.contains("Max 5x"))
    }

    @Test("persistentExtraUsage triggers notification with correct text")
    func persistentExtraUsageNotification() async {
        let sut = makeSUT()
        let finding = PatternFinding.persistentExtraUsage(avgMonthlyExtra: 40.0, basePrice: 100.0, recommendedTier: "Max 5x")

        await sut.processFindings([finding])
        #expect(spy.addedRequests.count == 1)
        let content = spy.addedRequests[0].content
        #expect(content.title == "Extra usage alert")
        #expect(content.body.contains("40%"))
        #expect(content.body.contains("Max 5x"))
    }

    @Test("extraUsageOverflow cooldown prevents duplicate within 30 days")
    func extraUsageOverflowCooldown() async {
        let sut = makeSUT()
        let finding = PatternFinding.extraUsageOverflow(avgExtraSpend: 50.0, recommendedTier: "Max 5x", estimatedSavings: 30.0)

        await sut.processFindings([finding])
        #expect(spy.addedRequests.count == 1)

        await sut.processFindings([finding])
        #expect(spy.addedRequests.count == 1)
    }

    // MARK: - Empty Findings

    @Test("empty findings array produces no notifications")
    func emptyFindings() async {
        let sut = makeSUT()

        await sut.processFindings([])
        #expect(spy.addedRequests.isEmpty)
    }
}
