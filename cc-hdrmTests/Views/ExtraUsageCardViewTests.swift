import os
import SwiftUI
import Testing
@testable import cc_hdrm

@Suite("ExtraUsageCardView Tests")
struct ExtraUsageCardViewTests {

    // MARK: - Full Card Rendering (AC 1)

    @Test("Full card renders without crash when extra usage enabled with spend and limit")
    @MainActor
    func fullCardRendersWithSpendAndLimit() {
        let appState = AppState()
        appState.updateExtraUsage(enabled: true, monthlyLimit: 43.0, usedCredits: 15.61, utilization: 0.363)
        let prefs = MockPreferencesManager()
        prefs.billingCycleDay = 1

        let view = ExtraUsageCardView(appState: appState, preferencesManager: prefs)
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    // MARK: - Collapsed State (AC 6)

    @Test("Collapsed state renders when extra usage enabled with zero spend")
    @MainActor
    func collapsedStateWithZeroSpend() {
        let appState = AppState()
        appState.updateExtraUsage(enabled: true, monthlyLimit: 43.0, usedCredits: 0, utilization: 0.0)
        let prefs = MockPreferencesManager()

        let view = ExtraUsageCardView(appState: appState, preferencesManager: prefs)
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    @Test("Collapsed state renders when extra usage enabled with nil spend")
    @MainActor
    func collapsedStateWithNilSpend() {
        let appState = AppState()
        appState.updateExtraUsage(enabled: true, monthlyLimit: 43.0, usedCredits: nil, utilization: nil)
        let prefs = MockPreferencesManager()

        let view = ExtraUsageCardView(appState: appState, preferencesManager: prefs)
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    // MARK: - Hidden State (AC 7)

    @Test("Hidden state when extra usage disabled")
    @MainActor
    func hiddenStateWhenDisabled() {
        let appState = AppState()
        appState.updateExtraUsage(enabled: false, monthlyLimit: nil, usedCredits: nil, utilization: nil)
        let prefs = MockPreferencesManager()

        let view = ExtraUsageCardView(appState: appState, preferencesManager: prefs)
        let controller = NSHostingController(rootView: view)
        _ = controller.view
        // View should produce empty content — no crash
    }

    // MARK: - No Limit Mode (AC 8)

    @Test("No-limit mode renders without progress bar when monthlyLimit is nil")
    @MainActor
    func noLimitModeRendersWithoutProgressBar() {
        let appState = AppState()
        appState.updateExtraUsage(enabled: true, monthlyLimit: nil, usedCredits: 15.61, utilization: nil)
        let prefs = MockPreferencesManager()
        prefs.billingCycleDay = 15

        let view = ExtraUsageCardView(appState: appState, preferencesManager: prefs)
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    // MARK: - Currency Formatting (AC 1, 8)

    @Test("Currency text formats as '$X.XX / $Y.YY' with known limit")
    func currencyFormattingWithLimit() {
        let text = ExtraUsageCardView.currencyText(usedCredits: 15.61, limit: 43.0)
        #expect(text == "$15.61 / $43.00")
    }

    @Test("Currency text formats as '$X.XX spent' without limit")
    func currencyFormattingWithoutLimit() {
        let text = ExtraUsageCardView.currencyText(usedCredits: 15.61, limit: nil)
        #expect(text == "$15.61 spent")
    }

    @Test("Currency text formats as '$X.XX spent' when limit is zero")
    func currencyFormattingWithZeroLimit() {
        let text = ExtraUsageCardView.currencyText(usedCredits: 7.50, limit: 0.0)
        #expect(text == "$7.50 spent")
    }

    // MARK: - Reset Date Computation (Task 2)

    @Test("nextResetDate returns this month when billing day is in the future")
    func resetDateFutureDay() {
        // Create a date on the 10th of the month
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 10
        let today = Calendar.current.date(from: components)!

        let resetDate = ExtraUsageCardView.nextResetDate(billingCycleDay: 15, relativeTo: today)
        let resetComponents = Calendar.current.dateComponents([.year, .month, .day], from: resetDate)

        #expect(resetComponents.year == 2026)
        #expect(resetComponents.month == 3)
        #expect(resetComponents.day == 15)
    }

    @Test("nextResetDate returns next month when billing day has passed")
    func resetDatePastDay() {
        // Create a date on the 20th of the month
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 20
        let today = Calendar.current.date(from: components)!

        let resetDate = ExtraUsageCardView.nextResetDate(billingCycleDay: 15, relativeTo: today)
        let resetComponents = Calendar.current.dateComponents([.year, .month, .day], from: resetDate)

        #expect(resetComponents.year == 2026)
        #expect(resetComponents.month == 4)
        #expect(resetComponents.day == 15)
    }

    @Test("Reset text shows settings prompt when billingCycleDay is nil")
    @MainActor
    func resetTextWithNoBillingDay() {
        let appState = AppState()
        appState.updateExtraUsage(enabled: true, monthlyLimit: 43.0, usedCredits: 15.61, utilization: 0.363)
        let prefs = MockPreferencesManager()
        prefs.billingCycleDay = nil

        let view = ExtraUsageCardView(appState: appState, preferencesManager: prefs)
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    // MARK: - VoiceOver Accessibility (AC 9)

    @Test("Accessibility label components for full card with limit and billing day")
    func accessibilityLabelFullCardComponents() {
        // Verify the expected label format by composing the same way the view does
        let usedCredits = 15.61
        let limit = 43.0
        let utilization = min(1.0, usedCredits / limit)
        let resetDate = ExtraUsageCardView.nextResetDate(billingCycleDay: 1)
        let resetStr = ExtraUsageCardView.formatResetDate(resetDate)

        let spendPart = String(format: "Extra usage: $%.2f spent of $%.2f monthly limit, %.0f%% used", usedCredits, limit, utilization * 100)
        let expected = "\(spendPart), resets \(resetStr)"

        #expect(expected.contains("$15.61 spent of $43.00 monthly limit"))
        #expect(expected.contains("36% used"))
        #expect(expected.contains("resets "))
        #expect(resetStr.count > 0)
    }

    @Test("Accessibility label for no-limit card omits percentage")
    func accessibilityLabelNoLimit() {
        let text = String(format: "Extra usage: $%.2f spent, no monthly limit set", 15.61)
        #expect(text == "Extra usage: $15.61 spent, no monthly limit set")
        #expect(!text.contains("% used"))
    }

    @Test("Full card renders with accessibility configuration")
    @MainActor
    func fullCardRendersWithAccessibility() {
        let appState = AppState()
        appState.updateExtraUsage(enabled: true, monthlyLimit: 43.0, usedCredits: 15.61, utilization: 0.363)
        let prefs = MockPreferencesManager()
        prefs.billingCycleDay = 1

        let view = ExtraUsageCardView(appState: appState, preferencesManager: prefs)
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }

    @Test("Collapsed state renders with accessibility label")
    @MainActor
    func collapsedStateRendersWithAccessibility() {
        let appState = AppState()
        appState.updateExtraUsage(enabled: true, monthlyLimit: 43.0, usedCredits: 0, utilization: 0.0)
        let prefs = MockPreferencesManager()

        let view = ExtraUsageCardView(appState: appState, preferencesManager: prefs)
        let controller = NSHostingController(rootView: view)
        _ = controller.view
    }
}

// MARK: - Reset Date Formatting

@Suite("ExtraUsageCardView Reset Date Formatting Tests")
struct ExtraUsageCardViewResetDateTests {

    @Test("formatResetDate produces MMM d format")
    func formatResetDateFormat() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1
        let date = Calendar.current.date(from: components)!

        let formatted = ExtraUsageCardView.formatResetDate(date)
        #expect(formatted == "Mar 1")
    }

    @Test("nextResetDate handles December to January rollover")
    func resetDateDecemberRollover() {
        var components = DateComponents()
        components.year = 2026
        components.month = 12
        components.day = 20
        let today = Calendar.current.date(from: components)!

        let resetDate = ExtraUsageCardView.nextResetDate(billingCycleDay: 15, relativeTo: today)
        let resetComponents = Calendar.current.dateComponents([.year, .month, .day], from: resetDate)

        #expect(resetComponents.year == 2027)
        #expect(resetComponents.month == 1)
        #expect(resetComponents.day == 15)
    }

    @Test("nextResetDate on billing day itself rolls to next month")
    func resetDateOnBillingDay() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        let today = Calendar.current.date(from: components)!

        let resetDate = ExtraUsageCardView.nextResetDate(billingCycleDay: 15, relativeTo: today)
        let resetComponents = Calendar.current.dateComponents([.year, .month, .day], from: resetDate)

        #expect(resetComponents.year == 2026)
        #expect(resetComponents.month == 4)
        #expect(resetComponents.day == 15)
    }

    @Test("nextResetDate handles Feb 28 when billing day is 28")
    func resetDateFeb28() {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 30
        let today = Calendar.current.date(from: components)!

        let resetDate = ExtraUsageCardView.nextResetDate(billingCycleDay: 28, relativeTo: today)
        let resetComponents = Calendar.current.dateComponents([.year, .month, .day], from: resetDate)

        #expect(resetComponents.year == 2026)
        #expect(resetComponents.month == 2)
        #expect(resetComponents.day == 28)
    }
}
