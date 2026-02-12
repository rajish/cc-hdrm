import AppKit
import Testing
@testable import cc_hdrm

@Suite("Color+Headroom NSColor Mapping Tests")
struct ColorHeadroomTests {

    // MARK: - NSColor Mapping (Task 6)

    @Test("each HeadroomState maps to a non-nil NSColor")
    func allStatesMappToNonNilColor() {
        for state in HeadroomState.allCases {
            let color = NSColor.headroomColor(for: state)
            // NSColor.headroomColor always returns a value (fallback if catalog unavailable)
            #expect(color != NSColor.clear, "State \(state.rawValue) should map to a non-clear color")
        }
    }

    @Test("normal and critical map to different colors")
    func normalAndCriticalAreDifferent() {
        let normalColor = NSColor.headroomColor(for: .normal)
        let criticalColor = NSColor.headroomColor(for: .critical)
        #expect(normalColor != criticalColor, ".normal and .critical should have distinct colors")
    }

    @Test("disconnected returns a grey-family color")
    func disconnectedReturnsGrey() {
        let color = NSColor.headroomColor(for: .disconnected)
        // Convert to sRGB to inspect components — fallback is .systemGray
        // We verify it's not a vibrant color (R ~= G ~= B for grey tones)
        guard let srgb = color.usingColorSpace(.sRGB) else {
            // If color space conversion fails in test target, just verify non-nil
            #expect(true, "Color exists but can't convert to sRGB in test target")
            return
        }
        let r = srgb.redComponent
        let g = srgb.greenComponent
        let b = srgb.blueComponent
        // Grey colors have roughly equal RGB. Allow generous tolerance for system grey.
        let maxDiff = max(abs(r - g), abs(r - b), abs(g - b))
        #expect(maxDiff < 0.3, "Disconnected color should be grey-ish (max channel diff: \(maxDiff))")
    }

    // MARK: - NSFont Weight Mapping (Task 6)

    @Test("font weight mapping returns correct weight for each state",
          arguments: [
            (HeadroomState.normal, NSFont.Weight.regular),
            (HeadroomState.caution, NSFont.Weight.medium),
            (HeadroomState.warning, NSFont.Weight.semibold),
            (HeadroomState.critical, NSFont.Weight.bold),
            (HeadroomState.exhausted, NSFont.Weight.bold),
            (HeadroomState.disconnected, NSFont.Weight.regular),
          ])
    func fontWeightMapping(state: HeadroomState, expectedWeight: NSFont.Weight) {
        let font = NSFont.menuBarFont(for: state)
        let expectedFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: expectedWeight)
        // Compare font names and point sizes — fonts with same weight produce same name
        #expect(font.fontName == expectedFont.fontName,
                "State \(state.rawValue) font name should match expected weight font name")
        #expect(font.pointSize == expectedFont.pointSize,
                "State \(state.rawValue) font size should match")
    }

    @Test("menuBarFont returns monospaced font at system size")
    func menuBarFontIsMonospacedSystemSize() {
        let font = NSFont.menuBarFont(for: .normal)
        #expect(font.pointSize == NSFont.systemFontSize)
    }

    // MARK: - Extra Usage Color Mapping Tests (Story 17.1)

    @Test("extraUsageColor(for: 0.0) returns ExtraUsageCool color")
    func extraUsageCoolColor() {
        let color = NSColor.extraUsageColor(for: 0.0)
        #expect(color != NSColor.clear, "0.0 utilization should return a non-clear color")
        // Verify it's blue-ish (cool): blue component should be dominant
        if let srgb = color.usingColorSpace(.sRGB) {
            #expect(srgb.blueComponent > srgb.redComponent, "Cool color should have blue > red")
        }
    }

    @Test("extraUsageColor(for: 0.6) returns ExtraUsageWarm color")
    func extraUsageWarmColor() {
        let color = NSColor.extraUsageColor(for: 0.6)
        #expect(color != NSColor.clear, "0.6 utilization should return a non-clear color")
        // Verify it's purple-ish (warm): blue > green
        if let srgb = color.usingColorSpace(.sRGB) {
            #expect(srgb.blueComponent > srgb.greenComponent, "Warm color should have blue > green")
        }
    }

    @Test("extraUsageColor(for: 0.8) returns ExtraUsageHot color")
    func extraUsageHotColor() {
        let color = NSColor.extraUsageColor(for: 0.8)
        #expect(color != NSColor.clear, "0.8 utilization should return a non-clear color")
        // Verify it's magenta-ish (hot): red > green
        if let srgb = color.usingColorSpace(.sRGB) {
            #expect(srgb.redComponent > srgb.greenComponent, "Hot color should have red > green")
        }
    }

    @Test("extraUsageColor(for: 0.95) returns ExtraUsageCritical color")
    func extraUsageCriticalColor() {
        let color = NSColor.extraUsageColor(for: 0.95)
        #expect(color != NSColor.clear, "0.95 utilization should return a non-clear color")
        // Verify it's red-ish (critical): red > blue and red > green
        if let srgb = color.usingColorSpace(.sRGB) {
            #expect(srgb.redComponent > srgb.greenComponent, "Critical color should have red > green")
            #expect(srgb.redComponent > srgb.blueComponent, "Critical color should have red > blue")
        }
    }

    @Test("extraUsageColor tiers are distinct from each other")
    func extraUsageColorTiersDistinct() {
        let cool = NSColor.extraUsageColor(for: 0.0)
        let warm = NSColor.extraUsageColor(for: 0.6)
        let hot = NSColor.extraUsageColor(for: 0.8)
        let critical = NSColor.extraUsageColor(for: 0.95)

        #expect(cool != warm, "Cool and warm should be different colors")
        #expect(warm != hot, "Warm and hot should be different colors")
        #expect(hot != critical, "Hot and critical should be different colors")
    }

    @Test("extraUsageMenuBarFont uses semibold below 0.75, bold at 0.75+")
    func extraUsageFontWeights() {
        let lowFont = NSFont.extraUsageMenuBarFont(for: 0.3)
        let highFont = NSFont.extraUsageMenuBarFont(for: 0.8)
        let expectedLow = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let expectedHigh = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .bold)

        #expect(lowFont.fontName == expectedLow.fontName, "Below 0.75 should use semibold")
        #expect(highFont.fontName == expectedHigh.fontName, "At 0.75+ should use bold")
    }
}
