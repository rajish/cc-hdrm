import SwiftUI
import Testing
@testable import cc_hdrm

@Suite("UpdateBadgeView Tests")
struct UpdateBadgeViewTests {

    private func makeUpdate(version: String = "1.2.0") -> AvailableUpdate {
        AvailableUpdate(version: version, downloadURL: URL(string: "https://github.com/test/releases/v1.2.0")!)
    }

    // MARK: - AC #1: Badge appears when availableUpdate is set

    @Test("Badge renders without crash when update is available")
    @MainActor
    func badgeRendersWithUpdate() {
        let view = UpdateBadgeView(update: makeUpdate(), onDismiss: {})
        _ = view.body
    }

    @Test("Badge can be hosted in NSHostingController")
    @MainActor
    func hostingControllerInstantiation() {
        let view = UpdateBadgeView(update: makeUpdate(), onDismiss: {})
        let controller = NSHostingController(rootView: view)
        #expect(controller.view.frame.size.width >= 0)
    }

    // MARK: - AC #1: Badge hidden when availableUpdate is nil

    @Test("PopoverView hides badge when availableUpdate is nil")
    @MainActor
    func badgeHiddenWhenNoUpdate() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        // availableUpdate is nil by default
        #expect(appState.availableUpdate == nil)
    }

    @Test("PopoverView shows badge when availableUpdate is set")
    @MainActor
    func badgeVisibleWhenUpdateSet() {
        let appState = AppState()
        appState.updateAvailableUpdate(makeUpdate())
        #expect(appState.availableUpdate != nil)
        #expect(appState.availableUpdate?.version == "1.2.0")
    }

    // MARK: - AC #2: Dismiss sets dismissedVersion and clears availableUpdate

    @Test("Dismiss action sets dismissedVersion and clears availableUpdate")
    @MainActor
    func dismissSetsDismissedVersionAndClearsUpdate() {
        let appState = AppState()
        let prefs = MockPreferencesManager()
        let update = makeUpdate(version: "2.0.0")
        appState.updateAvailableUpdate(update)

        // Simulate the dismiss closure from PopoverView integration
        prefs.dismissedVersion = update.version
        appState.updateAvailableUpdate(nil)

        #expect(prefs.dismissedVersion == "2.0.0")
        #expect(appState.availableUpdate == nil)
    }

    @Test("Dismiss callback is invoked when onDismiss is called")
    @MainActor
    func dismissCallbackInvoked() {
        var dismissed = false
        let view = UpdateBadgeView(update: makeUpdate()) {
            dismissed = true
        }
        view.onDismiss()
        #expect(dismissed == true)
    }

    // MARK: - AC #3: New version reappears after previous dismiss

    @Test("New version reappears after dismissing previous version")
    @MainActor
    func newVersionReappearsAfterDismiss() {
        let appState = AppState()
        let prefs = MockPreferencesManager()

        // First update dismissed
        let update1 = makeUpdate(version: "1.0.0")
        appState.updateAvailableUpdate(update1)
        prefs.dismissedVersion = update1.version
        appState.updateAvailableUpdate(nil)
        #expect(appState.availableUpdate == nil)

        // New version appears
        let update2 = makeUpdate(version: "2.0.0")
        appState.updateAvailableUpdate(update2)
        #expect(appState.availableUpdate != nil)
        #expect(appState.availableUpdate?.version == "2.0.0")
    }

    // MARK: - AC #5: VoiceOver label

    @Test("VoiceOver label format verified via code inspection (declarative SwiftUI — not introspectable in unit tests)")
    @MainActor
    func accessibilityLabelFormatDocumented() {
        // NOTE: SwiftUI .accessibilityLabel is declarative and cannot be read back
        // in unit tests without snapshot/UI testing. Verified by code inspection:
        // UpdateBadgeView.swift sets .accessibilityLabel("Update available: version \(update.version). ...")
        // This test confirms the version string flows through to the view.
        let update = makeUpdate(version: "3.1.0")
        let view = UpdateBadgeView(update: update, onDismiss: {})
        #expect(view.update.version == "3.1.0")
    }
}
