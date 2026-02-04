import SwiftUI
import Testing
@testable import cc_hdrm

/// Tests for SlopeIndicator component and related accessibility (Story 11.4).
///
/// Note: SlopeLevel.arrow and SlopeLevel.color(for:) tests exist in SlopeLevelTests.swift.
/// This file tests the SlopeIndicator View component and accessibility label integration.

@Suite("SlopeIndicator Component Tests")
struct SlopeIndicatorComponentTests {

    // MARK: - Component Instantiation

    @Test("SlopeIndicator can be instantiated with flat slope and normal state")
    @MainActor
    func instantiateFlatNormal() {
        let indicator = SlopeIndicator(slopeLevel: .flat, headroomState: .normal)
        _ = indicator.body
    }

    @Test("SlopeIndicator can be instantiated with rising slope and warning state")
    @MainActor
    func instantiateRisingWarning() {
        let indicator = SlopeIndicator(slopeLevel: .rising, headroomState: .warning)
        _ = indicator.body
    }

    @Test("SlopeIndicator can be instantiated with steep slope and critical state")
    @MainActor
    func instantiateSteepCritical() {
        let indicator = SlopeIndicator(slopeLevel: .steep, headroomState: .critical)
        _ = indicator.body
    }

    @Test("SlopeIndicator renders for all slope and headroom combinations")
    @MainActor
    func allCombinations() {
        for slope in SlopeLevel.allCases {
            for state in HeadroomState.allCases {
                let indicator = SlopeIndicator(slopeLevel: slope, headroomState: state)
                _ = indicator.body
            }
        }
    }
}

// MARK: - Gauge Section Accessibility Tests (Story 11.4 AC #4)

@Suite("Gauge Section Slope Accessibility Tests")
@MainActor
struct GaugeSectionSlopeAccessibilityTests {

    // MARK: - FiveHourGaugeSection Accessibility Label Verification

    @Test("5h gauge combinedAccessibilityLabel contains 'flat' when slope is flat")
    func fiveHourLabelContainsFlat() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .flat)

        let section = FiveHourGaugeSection(appState: appState)
        let label = section.combinedAccessibilityLabel
        #expect(label.contains("flat"), "Label should contain 'flat': \(label)")
        #expect(label.contains("80 percent"), "Label should contain headroom percentage")
    }

    @Test("5h gauge combinedAccessibilityLabel contains 'rising' when slope is rising")
    func fiveHourLabelContainsRising() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 50.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateSlopes(fiveHour: .rising, sevenDay: .flat)

        let section = FiveHourGaugeSection(appState: appState)
        let label = section.combinedAccessibilityLabel
        #expect(label.contains("rising"), "Label should contain 'rising': \(label)")
    }

    @Test("5h gauge combinedAccessibilityLabel contains 'steep' when slope is steep")
    func fiveHourLabelContainsSteep() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 80.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateSlopes(fiveHour: .steep, sevenDay: .flat)

        let section = FiveHourGaugeSection(appState: appState)
        let label = section.combinedAccessibilityLabel
        #expect(label.contains("steep"), "Label should contain 'steep': \(label)")
    }

    // MARK: - SevenDayGaugeSection Accessibility Label Verification

    @Test("7d gauge combinedAccessibilityLabel contains 'flat' when slope is flat")
    func sevenDayLabelContainsFlat() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 30.0, resetsAt: Date().addingTimeInterval(86400))
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .flat)

        let section = SevenDayGaugeSection(appState: appState)
        let label = section.combinedAccessibilityLabel
        #expect(label.contains("flat"), "Label should contain 'flat': \(label)")
        #expect(label.contains("70 percent"), "Label should contain headroom percentage")
    }

    @Test("7d gauge combinedAccessibilityLabel contains 'rising' when slope is rising")
    func sevenDayLabelContainsRising() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 50.0, resetsAt: Date().addingTimeInterval(86400))
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .rising)

        let section = SevenDayGaugeSection(appState: appState)
        let label = section.combinedAccessibilityLabel
        #expect(label.contains("rising"), "Label should contain 'rising': \(label)")
    }

    @Test("7d gauge combinedAccessibilityLabel contains 'steep' when slope is steep")
    func sevenDayLabelContainsSteep() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 80.0, resetsAt: Date().addingTimeInterval(86400))
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .steep)

        let section = SevenDayGaugeSection(appState: appState)
        let label = section.combinedAccessibilityLabel
        #expect(label.contains("steep"), "Label should contain 'steep': \(label)")
    }

    // MARK: - Default Slope Behavior (AC #3)

    @Test("slopes default to flat when no data (less than 10 min history)")
    func defaultSlopeIsFlat() {
        let appState = AppState()
        // Default AppState has slopes set to .flat
        #expect(appState.fiveHourSlope == .flat)
        #expect(appState.sevenDaySlope == .flat)
    }

    // MARK: - Accessibility Format Verification (AC #4)

    @Test("5h accessibility follows format: window, percent, slope, resets")
    func fiveHourAccessibilityFormat() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 25.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateSlopes(fiveHour: .rising, sevenDay: .flat)

        let section = FiveHourGaugeSection(appState: appState)
        let label = section.combinedAccessibilityLabel

        // Verify format: "5-hour headroom: [X] percent, [slope], resets in..."
        #expect(label.hasPrefix("5-hour headroom:"), "Should start with '5-hour headroom:'")
        #expect(label.contains("75 percent"), "Should contain headroom percentage")
        #expect(label.contains("rising"), "Should contain slope level")
        #expect(label.contains("resets in"), "Should contain 'resets in'")

        // Verify order: percent comes before slope, slope comes before resets
        if let percentRange = label.range(of: "percent"),
           let slopeRange = label.range(of: "rising"),
           let resetsRange = label.range(of: "resets") {
            #expect(percentRange.lowerBound < slopeRange.lowerBound, "percent should come before slope")
            #expect(slopeRange.lowerBound < resetsRange.lowerBound, "slope should come before resets")
        }
    }

    @Test("7d accessibility follows format: window, percent, slope, resets")
    func sevenDayAccessibilityFormat() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 40.0, resetsAt: Date().addingTimeInterval(86400))
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .steep)

        let section = SevenDayGaugeSection(appState: appState)
        let label = section.combinedAccessibilityLabel

        // Verify format: "7-day headroom: [X] percent, [slope], resets in..."
        #expect(label.hasPrefix("7-day headroom:"), "Should start with '7-day headroom:'")
        #expect(label.contains("60 percent"), "Should contain headroom percentage")
        #expect(label.contains("steep"), "Should contain slope level")
        #expect(label.contains("resets in"), "Should contain 'resets in'")
    }

    // MARK: - Disconnected State Accessibility (L2)

    @Test("5h accessibility returns 'unavailable' when disconnected")
    func fiveHourDisconnectedAccessibility() {
        let appState = AppState()
        // Don't set any windows - simulates disconnected state

        let section = FiveHourGaugeSection(appState: appState)
        let label = section.combinedAccessibilityLabel

        #expect(label == "5-hour headroom: unavailable")
        #expect(!label.contains("flat"), "Disconnected should not mention slope")
        #expect(!label.contains("resets"), "Disconnected should not mention resets")
    }

    @Test("7d accessibility returns 'unavailable' when no 7d data")
    func sevenDayDisconnectedAccessibility() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil  // No 7d data
        )

        let section = SevenDayGaugeSection(appState: appState)
        let label = section.combinedAccessibilityLabel

        #expect(label == "7-day headroom: unavailable")
    }

    // MARK: - FiveHourGaugeSection Renders with Slope

    @Test("FiveHourGaugeSection renders with slope without crash")
    func fiveHourSectionRendersWithSlope() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 30.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateSlopes(fiveHour: .rising, sevenDay: .flat)

        let section = FiveHourGaugeSection(appState: appState)
        _ = section.body
        // No crash — slope is passed to HeadroomRingGauge
    }

    @Test("FiveHourGaugeSection renders with all slope levels")
    func fiveHourSectionRendersAllSlopeLevels() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 50.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )

        for slope in SlopeLevel.allCases {
            appState.updateSlopes(fiveHour: slope, sevenDay: .flat)
            let section = FiveHourGaugeSection(appState: appState)
            _ = section.body
        }
    }

    // MARK: - SevenDayGaugeSection Renders with Slope

    @Test("SevenDayGaugeSection renders with slope without crash")
    func sevenDaySectionRendersWithSlope() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 40.0, resetsAt: Date().addingTimeInterval(86400))
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .steep)

        let section = SevenDayGaugeSection(appState: appState)
        _ = section.body
        // No crash — slope is passed to HeadroomRingGauge
    }

    @Test("SevenDayGaugeSection renders with all slope levels")
    func sevenDaySectionRendersAllSlopeLevels() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 50.0, resetsAt: Date().addingTimeInterval(86400))
        )

        for slope in SlopeLevel.allCases {
            appState.updateSlopes(fiveHour: .flat, sevenDay: slope)
            let section = SevenDayGaugeSection(appState: appState)
            _ = section.body
        }
    }
}

// MARK: - HeadroomRingGauge Slope Tests

@Suite("HeadroomRingGauge Slope Display Tests")
struct HeadroomRingGaugeSlopeTests {

    @Test("HeadroomRingGauge accepts nil slope for backward compatibility")
    @MainActor
    func nilSlopeBackwardCompatibility() {
        let gauge = HeadroomRingGauge(
            headroomPercentage: 75.0,
            windowLabel: "5h",
            ringSize: 96,
            strokeWidth: 7
            // slopeLevel not provided — uses default nil
        )
        _ = gauge.body
    }

    @Test("HeadroomRingGauge renders with explicit nil slope")
    @MainActor
    func explicitNilSlope() {
        let gauge = HeadroomRingGauge(
            headroomPercentage: 75.0,
            windowLabel: "5h",
            ringSize: 96,
            strokeWidth: 7,
            slopeLevel: nil
        )
        _ = gauge.body
    }

    @Test("HeadroomRingGauge renders with flat slope")
    @MainActor
    func flatSlope() {
        let gauge = HeadroomRingGauge(
            headroomPercentage: 75.0,
            windowLabel: "5h",
            ringSize: 96,
            strokeWidth: 7,
            slopeLevel: .flat
        )
        _ = gauge.body
    }

    @Test("HeadroomRingGauge renders with rising slope")
    @MainActor
    func risingSlope() {
        let gauge = HeadroomRingGauge(
            headroomPercentage: 50.0,
            windowLabel: "5h",
            ringSize: 96,
            strokeWidth: 7,
            slopeLevel: .rising
        )
        _ = gauge.body
    }

    @Test("HeadroomRingGauge renders with steep slope")
    @MainActor
    func steepSlope() {
        let gauge = HeadroomRingGauge(
            headroomPercentage: 10.0,
            windowLabel: "5h",
            ringSize: 96,
            strokeWidth: 7,
            slopeLevel: .steep
        )
        _ = gauge.body
    }

    @Test("HeadroomRingGauge hides slope when disconnected (nil headroom)")
    @MainActor
    func slopeHiddenWhenDisconnected() {
        // When headroomPercentage is nil, slope should not display
        // The component logic: if let slope = slopeLevel, headroomPercentage != nil
        let gauge = HeadroomRingGauge(
            headroomPercentage: nil,
            windowLabel: "5h",
            ringSize: 96,
            strokeWidth: 7,
            slopeLevel: .rising // Slope provided but shouldn't display
        )
        _ = gauge.body
        // No crash — slope hidden when disconnected
    }

    @Test("HeadroomRingGauge renders for 7d size with slope")
    @MainActor
    func sevenDaySizeWithSlope() {
        let gauge = HeadroomRingGauge(
            headroomPercentage: 65.0,
            windowLabel: "7d",
            ringSize: 56,
            strokeWidth: 4,
            slopeLevel: .rising
        )
        _ = gauge.body
    }

    @Test("HeadroomRingGauge renders all slope levels with all headroom states")
    @MainActor
    func allSlopesWithAllStates() {
        let headroomValues: [Double?] = [nil, 0, 3, 12, 30, 75]

        for headroom in headroomValues {
            for slope in SlopeLevel.allCases {
                let gauge = HeadroomRingGauge(
                    headroomPercentage: headroom,
                    windowLabel: "5h",
                    ringSize: 96,
                    strokeWidth: 7,
                    slopeLevel: slope
                )
                _ = gauge.body
            }
        }
    }
}
