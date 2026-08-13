import SwiftUI
import Testing
@testable import cc_hdrm

@Suite("ScopedLimitGaugeSection Tests")
struct ScopedLimitGaugeSectionTests {

    @Test("Section renders with a scoped limit entry without crash")
    @MainActor
    func scopedLimitPresent() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateScopedLimits([
            ScopedLimitState(displayName: "Fable", utilization: 63.0, resetsAt: Date().addingTimeInterval(3 * 86400))
        ])
        let section = ScopedLimitGaugeSection(appState: appState)
        _ = section.body
        #expect(appState.scopedLimits.count == 1)
    }

    @Test("Section renders as empty when scopedLimits is empty")
    @MainActor
    func emptyScopedLimitsHidesSection() {
        let appState = AppState()
        let section = ScopedLimitGaugeSection(appState: appState)
        _ = section.body
        #expect(section.entries.isEmpty)
    }

    @Test("Nil display name falls back to generic label")
    @MainActor
    func nilDisplayNameFallbackLabel() {
        let appState = AppState()
        appState.updateScopedLimits([
            ScopedLimitState(displayName: nil, utilization: 40.0, resetsAt: Date().addingTimeInterval(86400))
        ])
        let section = ScopedLimitGaugeSection(appState: appState)
        _ = section.body
        let entry = appState.scopedLimits[0]
        #expect(section.label(for: entry) == ScopedLimitGaugeSection.fallbackLabel)
        #expect(section.combinedAccessibilityLabel(for: entry).hasPrefix("Model headroom: 60 percent"))
    }

    @Test("Empty display name falls back to generic label")
    @MainActor
    func emptyDisplayNameFallbackLabel() {
        let appState = AppState()
        appState.updateScopedLimits([
            ScopedLimitState(displayName: "", utilization: 40.0, resetsAt: Date().addingTimeInterval(86400))
        ])
        let section = ScopedLimitGaugeSection(appState: appState)
        _ = section.body
        let entry = appState.scopedLimits[0]
        #expect(section.label(for: entry) == ScopedLimitGaugeSection.fallbackLabel)
        #expect(section.combinedAccessibilityLabel(for: entry).hasPrefix("Model headroom: 60 percent"))
    }

    @Test("Whitespace-only display name falls back to generic label")
    @MainActor
    func whitespaceDisplayNameFallbackLabel() {
        let appState = AppState()
        appState.updateScopedLimits([
            ScopedLimitState(displayName: " \n ", utilization: 40.0, resetsAt: nil)
        ])
        let section = ScopedLimitGaugeSection(appState: appState)
        #expect(section.label(for: appState.scopedLimits[0]) == ScopedLimitGaugeSection.fallbackLabel)
    }

    @Test("Display name from API is used as the gauge label")
    @MainActor
    func displayNameUsedAsLabel() {
        let appState = AppState()
        appState.updateScopedLimits([
            ScopedLimitState(displayName: "Fable", utilization: 63.0, resetsAt: nil)
        ])
        let section = ScopedLimitGaugeSection(appState: appState)
        let entry = appState.scopedLimits[0]
        #expect(section.label(for: entry) == "Fable")
        #expect(section.combinedAccessibilityLabel(for: entry).hasPrefix("Fable headroom: 37 percent"))
    }

    @Test("Nil reset date renders gauge without countdown text")
    @MainActor
    func nilResetDateOmitsCountdown() {
        let appState = AppState()
        appState.updateScopedLimits([
            ScopedLimitState(displayName: "Fable", utilization: 50.0, resetsAt: nil)
        ])
        let section = ScopedLimitGaugeSection(appState: appState)
        _ = section.body
        let label = section.combinedAccessibilityLabel(for: appState.scopedLimits[0])
        #expect(!label.contains("resets in"))
    }

    @Test("Reset date is announced with relative and absolute times")
    @MainActor
    func resetDateInAccessibilityLabel() {
        let appState = AppState()
        appState.updateScopedLimits([
            ScopedLimitState(displayName: "Fable", utilization: 63.0, resetsAt: Date().addingTimeInterval(2 * 86400))
        ])
        let section = ScopedLimitGaugeSection(appState: appState)
        let label = section.combinedAccessibilityLabel(for: appState.scopedLimits[0])
        #expect(label.contains("resets in"))
    }

    @Test("Multiple entries render one block per entry in array order")
    @MainActor
    func multipleEntriesRenderInOrder() {
        let appState = AppState()
        appState.updateScopedLimits([
            ScopedLimitState(displayName: "First", utilization: 20.0, resetsAt: Date().addingTimeInterval(86400)),
            ScopedLimitState(displayName: "Second", utilization: 80.0, resetsAt: nil)
        ])
        let section = ScopedLimitGaugeSection(appState: appState)
        _ = section.body
        #expect(section.entries.count == 2)
        #expect(section.label(for: section.entries[0]) == "First")
        #expect(section.label(for: section.entries[1]) == "Second")
    }

    @Test("Exhausted entry renders with 0 percent headroom without crash")
    @MainActor
    func exhaustedEntry() {
        let appState = AppState()
        appState.updateScopedLimits([
            ScopedLimitState(displayName: "Fable", utilization: 100.0, resetsAt: Date().addingTimeInterval(86400))
        ])
        let section = ScopedLimitGaugeSection(appState: appState)
        _ = section.body
        let entry = appState.scopedLimits[0]
        #expect(entry.headroomState == .exhausted)
        #expect(section.combinedAccessibilityLabel(for: entry).contains("0 percent"))
    }

    @Test("HeadroomState derivation is correct for scoped entries")
    @MainActor
    func headroomStateDerivation() {
        #expect(ScopedLimitState(displayName: nil, utilization: 30.0, resetsAt: nil).headroomState == .normal)
        #expect(ScopedLimitState(displayName: nil, utilization: 70.0, resetsAt: nil).headroomState == .caution)
        #expect(ScopedLimitState(displayName: nil, utilization: 88.0, resetsAt: nil).headroomState == .warning)
        #expect(ScopedLimitState(displayName: nil, utilization: 97.0, resetsAt: nil).headroomState == .critical)
        #expect(ScopedLimitState(displayName: nil, utilization: 100.0, resetsAt: nil).headroomState == .exhausted)
    }

    @Test("Section renders via NSHostingController without crash")
    @MainActor
    func rendersViaHostingController() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateScopedLimits([
            ScopedLimitState(displayName: "Fable", utilization: 63.0, resetsAt: Date().addingTimeInterval(3 * 86400)),
            ScopedLimitState(displayName: nil, utilization: 100.0, resetsAt: nil)
        ])
        let section = ScopedLimitGaugeSection(appState: appState)
        let hosting = NSHostingController(rootView: section)
        _ = hosting.view
    }
}
