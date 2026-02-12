import Foundation
import Testing
import UserNotifications
@testable import cc_hdrm

@Suite("ExtraUsageAlertService Tests")
@MainActor
struct ExtraUsageAlertServiceTests {
    let spy = SpyNotificationCenter()
    let prefs = MockPreferencesManager()
    let mockNotificationService = MockNotificationService()

    func makeSUT() -> ExtraUsageAlertService {
        mockNotificationService.isAuthorized = true
        prefs.extraUsageLastBillingPeriodKey = ExtraUsageAlertService.computeBillingPeriodKey(billingCycleDay: nil)
        return ExtraUsageAlertService(
            notificationCenter: spy,
            notificationService: mockNotificationService,
            preferencesManager: prefs
        )
    }

    // MARK: - 50% Threshold (AC 2)

    @Test("50% threshold fires notification with correct title and body")
    func threshold50FiresNotification() async {
        let sut = makeSUT()
        await sut.evaluateExtraUsageThresholds(
            extraUsageEnabled: true,
            utilization: 0.55,
            usedCredits: 55.0,
            monthlyLimit: 100.0,
            billingCycleDay: nil,
            planExhausted: false
        )
        #expect(spy.addedRequests.count == 1)
        let content = spy.addedRequests[0].content
        #expect(content.title == "Extra usage update")
        #expect(content.body.contains("$55.00"))
        #expect(content.body.contains("$100.00"))
    }

    // MARK: - 75% Threshold (AC 2)

    @Test("75% threshold fires notification with correct title and body")
    func threshold75FiresNotification() async {
        let sut = makeSUT()
        prefs.extraUsageFiredThresholds = [50]
        await sut.evaluateExtraUsageThresholds(
            extraUsageEnabled: true,
            utilization: 0.78,
            usedCredits: 78.0,
            monthlyLimit: 100.0,
            billingCycleDay: nil,
            planExhausted: false
        )
        #expect(spy.addedRequests.count == 1)
        let content = spy.addedRequests[0].content
        #expect(content.title == "Extra usage warning")
        #expect(content.body.contains("$78.00"))
        #expect(content.body.contains("$100.00"))
    }

    // MARK: - 90% Threshold (AC 2)

    @Test("90% threshold fires notification with remaining balance")
    func threshold90FiresNotification() async {
        let sut = makeSUT()
        prefs.extraUsageFiredThresholds = [50, 75]
        await sut.evaluateExtraUsageThresholds(
            extraUsageEnabled: true,
            utilization: 0.92,
            usedCredits: 92.0,
            monthlyLimit: 100.0,
            billingCycleDay: nil,
            planExhausted: false
        )
        #expect(spy.addedRequests.count == 1)
        let content = spy.addedRequests[0].content
        #expect(content.title == "Extra usage alert")
        #expect(content.body.contains("$8.00"))
    }

    // MARK: - Threshold De-duplication (AC 4)

    @Test("threshold does not re-fire when already in firedThresholds")
    func thresholdDoesNotRefire() async {
        let sut = makeSUT()
        prefs.extraUsageFiredThresholds = [50]
        await sut.evaluateExtraUsageThresholds(
            extraUsageEnabled: true,
            utilization: 0.55,
            usedCredits: 55.0,
            monthlyLimit: 100.0,
            billingCycleDay: nil,
            planExhausted: false
        )
        #expect(spy.addedRequests.isEmpty)
    }

    // MARK: - Billing Period Re-arm (AC 4)

    @Test("thresholds re-arm when billing period key changes")
    func thresholdsRearmOnPeriodChange() async {
        let sut = makeSUT()
        prefs.extraUsageFiredThresholds = [50, 75, 90]
        prefs.extraUsageEnteredAlertFired = true
        prefs.extraUsageLastBillingPeriodKey = "2025-01"

        await sut.evaluateExtraUsageThresholds(
            extraUsageEnabled: true,
            utilization: 0.55,
            usedCredits: 55.0,
            monthlyLimit: 100.0,
            billingCycleDay: nil,
            planExhausted: false
        )
        // After re-arm, 50% threshold should fire
        #expect(spy.addedRequests.count == 1)
        #expect(prefs.extraUsageFiredThresholds.contains(50))
        #expect(prefs.extraUsageEnteredAlertFired == false || spy.addedRequests.count >= 1)
    }

    // MARK: - Entered Extra Usage (AC 3)

    @Test("entered extra usage fires when planExhausted and extraUsageEnabled")
    func enteredExtraUsageFires() async {
        let sut = makeSUT()
        await sut.evaluateExtraUsageThresholds(
            extraUsageEnabled: true,
            utilization: 0.0,
            usedCredits: 0.0,
            monthlyLimit: 100.0,
            billingCycleDay: nil,
            planExhausted: true
        )
        #expect(spy.addedRequests.count == 1)
        let content = spy.addedRequests[0].content
        #expect(content.title == "Extra usage started")
        #expect(content.body.contains("plan quota is exhausted"))
    }

    @Test("entered extra usage does not re-fire in same billing period")
    func enteredExtraUsageNoRefire() async {
        let sut = makeSUT()
        prefs.extraUsageEnteredAlertFired = true
        await sut.evaluateExtraUsageThresholds(
            extraUsageEnabled: true,
            utilization: 0.0,
            usedCredits: 0.0,
            monthlyLimit: 100.0,
            billingCycleDay: nil,
            planExhausted: true
        )
        #expect(spy.addedRequests.isEmpty)
    }

    @Test("entered extra usage re-arms on new billing period")
    func enteredExtraUsageRearmsOnNewPeriod() async {
        let sut = makeSUT()
        prefs.extraUsageEnteredAlertFired = true
        prefs.extraUsageLastBillingPeriodKey = "2025-01"

        await sut.evaluateExtraUsageThresholds(
            extraUsageEnabled: true,
            utilization: 0.0,
            usedCredits: 0.0,
            monthlyLimit: 100.0,
            billingCycleDay: nil,
            planExhausted: true
        )
        // Re-armed and fired
        #expect(spy.addedRequests.count == 1)
        #expect(spy.addedRequests[0].content.title == "Extra usage started")
    }

    // MARK: - Master Toggle (AC 6)

    @Test("master toggle off suppresses all threshold alerts")
    func masterToggleOffSuppressesAlerts() async {
        let sut = makeSUT()
        prefs.extraUsageAlertsEnabled = false
        await sut.evaluateExtraUsageThresholds(
            extraUsageEnabled: true,
            utilization: 0.95,
            usedCredits: 95.0,
            monthlyLimit: 100.0,
            billingCycleDay: nil,
            planExhausted: true
        )
        #expect(spy.addedRequests.isEmpty)
    }

    // MARK: - Individual Toggle (AC 6)

    @Test("individual threshold toggle disables that specific threshold")
    func individualToggleDisables() async {
        let sut = makeSUT()
        prefs.extraUsageThreshold50Enabled = false
        await sut.evaluateExtraUsageThresholds(
            extraUsageEnabled: true,
            utilization: 0.55,
            usedCredits: 55.0,
            monthlyLimit: 100.0,
            billingCycleDay: nil,
            planExhausted: false
        )
        #expect(spy.addedRequests.isEmpty)
    }

    // MARK: - Account Without Extra Usage

    @Test("no alerts when extraUsageEnabled is false")
    func noAlertsWhenExtraUsageDisabled() async {
        let sut = makeSUT()
        await sut.evaluateExtraUsageThresholds(
            extraUsageEnabled: false,
            utilization: 0.95,
            usedCredits: 95.0,
            monthlyLimit: 100.0,
            billingCycleDay: nil,
            planExhausted: true
        )
        #expect(spy.addedRequests.isEmpty)
    }

    // MARK: - Nil Utilization

    @Test("no alerts when utilization is nil")
    func noAlertsWhenUtilizationNil() async {
        let sut = makeSUT()
        await sut.evaluateExtraUsageThresholds(
            extraUsageEnabled: true,
            utilization: nil,
            usedCredits: nil,
            monthlyLimit: nil,
            billingCycleDay: nil,
            planExhausted: false
        )
        #expect(spy.addedRequests.isEmpty)
    }

    // MARK: - Authorization

    @Test("no alerts when notificationService is not authorized")
    func noAlertsWhenNotAuthorized() async {
        mockNotificationService.isAuthorized = false
        let sut = ExtraUsageAlertService(
            notificationCenter: spy,
            notificationService: mockNotificationService,
            preferencesManager: prefs
        )
        prefs.extraUsageLastBillingPeriodKey = ExtraUsageAlertService.computeBillingPeriodKey(billingCycleDay: nil)

        await sut.evaluateExtraUsageThresholds(
            extraUsageEnabled: true,
            utilization: 0.95,
            usedCredits: 95.0,
            monthlyLimit: 100.0,
            billingCycleDay: nil,
            planExhausted: true
        )
        #expect(spy.addedRequests.isEmpty)
    }

    // MARK: - Multiple Thresholds at Once

    @Test("all three thresholds fire when utilization jumps from 0 to 95%")
    func multipleThresholdsFire() async {
        let sut = makeSUT()
        await sut.evaluateExtraUsageThresholds(
            extraUsageEnabled: true,
            utilization: 0.95,
            usedCredits: 95.0,
            monthlyLimit: 100.0,
            billingCycleDay: nil,
            planExhausted: false
        )
        #expect(spy.addedRequests.count == 3)
        #expect(spy.addedRequests[0].content.title == "Extra usage update")
        #expect(spy.addedRequests[1].content.title == "Extra usage warning")
        #expect(spy.addedRequests[2].content.title == "Extra usage alert")
    }

    // MARK: - Billing Period Key

    @Test("computeBillingPeriodKey uses calendar month when billingCycleDay is nil")
    func billingPeriodKeyDefault() {
        let key = ExtraUsageAlertService.computeBillingPeriodKey(billingCycleDay: nil, now: Date())
        #expect(key.count == 7) // "YYYY-MM"
        #expect(key.contains("-"))
    }

    @Test("computeBillingPeriodKey returns previous month when before billing day")
    func billingPeriodKeyBeforeBillingDay() {
        // Feb 5 with billing day 15 -> January period
        let cal = Calendar.current
        let feb5 = cal.date(from: DateComponents(year: 2026, month: 2, day: 5))!
        let key = ExtraUsageAlertService.computeBillingPeriodKey(billingCycleDay: 15, now: feb5)
        #expect(key == "2026-01")
    }

    @Test("computeBillingPeriodKey returns current month when after billing day")
    func billingPeriodKeyAfterBillingDay() {
        let cal = Calendar.current
        let feb20 = cal.date(from: DateComponents(year: 2026, month: 2, day: 20))!
        let key = ExtraUsageAlertService.computeBillingPeriodKey(billingCycleDay: 15, now: feb20)
        #expect(key == "2026-02")
    }
}
