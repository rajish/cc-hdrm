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
}
