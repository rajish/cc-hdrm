import AppKit
import Foundation
import Testing
@testable import cc_hdrm

@Suite("OnboardingView Tests")
struct OnboardingViewTests {

    // Note: These tests verify closure properties, not actual button taps.
    // True SwiftUI button interaction testing requires XCUITest.

    @Test("Sign In callback fires when invoked")
    @MainActor
    func signInCallbackFires() {
        var signInCalled = false
        let view = OnboardingView(
            onSignIn: { signInCalled = true },
            onLater: {}
        )
        view.onSignIn()
        #expect(signInCalled)
    }

    @Test("Later callback fires when invoked")
    @MainActor
    func laterCallbackFires() {
        var laterCalled = false
        let view = OnboardingView(
            onSignIn: {},
            onLater: { laterCalled = true }
        )
        view.onLater()
        #expect(laterCalled)
    }
}

@Suite("Onboarding Trigger Logic Tests")
struct OnboardingTriggerLogicTests {

    /// Evaluates the same condition used in AppDelegate to decide whether to show onboarding.
    /// Two gates: the flag must be false AND no credentials in keychain.
    private func shouldShowOnboarding(hasCompletedOnboarding: Bool, hasCredentials: Bool) -> Bool {
        !hasCompletedOnboarding && !hasCredentials
    }

    @Test("First launch — flag false, no credentials → should show onboarding")
    func firstLaunchShowsOnboarding() {
        #expect(shouldShowOnboarding(hasCompletedOnboarding: false, hasCredentials: false) == true)
    }

    @Test("Subsequent launch — flag true → should NOT show onboarding")
    func completedOnboardingHidesOnboarding() {
        #expect(shouldShowOnboarding(hasCompletedOnboarding: true, hasCredentials: false) == false)
    }

    @Test("Existing user upgrading — flag false but credentials exist → should NOT show onboarding")
    func existingUserUpgradeHidesOnboarding() {
        #expect(shouldShowOnboarding(hasCompletedOnboarding: false, hasCredentials: true) == false)
    }

    @Test("MockPreferencesManager hasCompletedOnboarding defaults to false")
    func mockDefaultsFalse() {
        let mock = MockPreferencesManager()
        #expect(mock.hasCompletedOnboarding == false)
    }

    @Test("MockPreferencesManager resetToDefaults resets hasCompletedOnboarding")
    func mockResetResetsOnboarding() {
        let mock = MockPreferencesManager()
        mock.hasCompletedOnboarding = true
        mock.resetToDefaults()
        #expect(mock.hasCompletedOnboarding == false)
    }
}

@Suite("OnboardingWindowController Tests")
struct OnboardingWindowControllerTests {

    @MainActor
    private func makeController() -> OnboardingWindowController {
        let view = OnboardingView(onSignIn: {}, onLater: {})
        return OnboardingWindowController(contentView: view)
    }

    // windowShouldClose is defensive: .closable is removed and cancelOperation blocks Escape,
    // so this delegate method is unlikely to fire — but validates the safety net if styleMask changes.

    @Test("windowShouldClose returns false to enforce modal behavior")
    @MainActor
    func windowShouldCloseReturnsFalse() {
        let controller = makeController()
        #expect(controller.windowShouldClose(NSWindow()) == false)
    }

    @Test("Panel is non-resizable with fixed size 420x400")
    @MainActor
    func panelIsNonResizable() {
        let controller = makeController()
        let panel = controller.panel
        #expect(panel != nil)
        #expect(panel?.minSize == NSSize(width: 420, height: 400))
        #expect(panel?.maxSize == NSSize(width: 420, height: 400))
    }

    @Test("Panel level is modalPanel")
    @MainActor
    func panelLevelIsModal() {
        let controller = makeController()
        #expect(controller.panel?.level == .modalPanel)
    }

    @Test("dismiss() closes and nils the panel")
    @MainActor
    func dismissClosesPanel() {
        let controller = makeController()
        #expect(controller.panel != nil)
        controller.dismiss()
        #expect(controller.panel == nil)
    }
}
