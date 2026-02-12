import AppKit
import SwiftUI

// MARK: - NSColor Headroom Mapping

extension NSColor {
    /// Returns the `NSColor` from the Asset Catalog for the given headroom state.
    /// Falls back to programmatic colors if Asset Catalog resolution fails (e.g., in test targets).
    static func headroomColor(for state: HeadroomState) -> NSColor {
        // Asset Catalog uses namespaced folder: HeadroomColors/
        let catalogName = "HeadroomColors/\(state.colorTokenName)"

        if let color = NSColor(named: NSColor.Name(catalogName)) {
            return color
        }

        // Fallback programmatic colors matching Asset Catalog values
        return fallbackColor(for: state)
    }

    private static func fallbackColor(for state: HeadroomState) -> NSColor {
        switch state {
        case .normal:
            return NSColor(red: 0.40, green: 0.72, blue: 0.40, alpha: 1.0) // muted green
        case .caution:
            return NSColor.systemYellow
        case .warning:
            return NSColor.systemOrange
        case .critical:
            return NSColor.systemRed
        case .exhausted:
            return NSColor.systemRed
        case .disconnected:
            return NSColor.systemGray
        }
    }
}

// MARK: - NSColor Extra Usage Mapping

extension NSColor {
    /// Returns the extra usage color for the given utilization fraction (0-1).
    /// Uses a 4-tier color ramp distinct from the headroom palette.
    static func extraUsageColor(for utilization: Double) -> NSColor {
        let tokenName: String
        switch utilization {
        case ..<0.50:
            tokenName = "ExtraUsageCool"
        case 0.50..<0.75:
            tokenName = "ExtraUsageWarm"
        case 0.75..<0.90:
            tokenName = "ExtraUsageHot"
        default:
            tokenName = "ExtraUsageCritical"
        }

        let catalogName = "ExtraUsageColors/\(tokenName)"
        if let color = NSColor(named: NSColor.Name(catalogName)) {
            return color
        }

        return fallbackExtraUsageColor(for: utilization)
    }

    private static func fallbackExtraUsageColor(for utilization: Double) -> NSColor {
        switch utilization {
        case ..<0.50:
            return NSColor(red: 0.320, green: 0.640, blue: 0.800, alpha: 1.0)
        case 0.50..<0.75:
            return NSColor(red: 0.500, green: 0.300, blue: 0.750, alpha: 1.0)
        case 0.75..<0.90:
            return NSColor(red: 0.800, green: 0.240, blue: 0.600, alpha: 1.0)
        default:
            return NSColor(red: 0.850, green: 0.170, blue: 0.250, alpha: 1.0)
        }
    }
}

// MARK: - NSFont Headroom Mapping

extension NSFont {
    /// Returns a monospaced system font at the system font size with the weight
    /// appropriate for the given headroom state (per AC #2).
    static func menuBarFont(for state: HeadroomState) -> NSFont {
        let weight: NSFont.Weight = switch state {
        case .normal:       .regular
        case .caution:      .medium
        case .warning:      .semibold
        case .critical:     .bold
        case .exhausted:    .bold
        case .disconnected: .regular
        }
        return NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: weight)
    }
}

// MARK: - NSFont Extra Usage Mapping

extension NSFont {
    /// Returns menu bar font for extra usage mode.
    /// Uses `.semibold` for 0-0.75 utilization, `.bold` for 0.75+.
    static func extraUsageMenuBarFont(for utilization: Double) -> NSFont {
        let weight: NSFont.Weight = utilization >= 0.75 ? .bold : .semibold
        return NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: weight)
    }
}

// MARK: - SwiftUI Color Headroom Mapping

extension Color {
    static var headroomNormal: Color { Color("HeadroomColors/HeadroomNormal", bundle: .main) }
    static var headroomCaution: Color { Color("HeadroomColors/HeadroomCaution", bundle: .main) }
    static var headroomWarning: Color { Color("HeadroomColors/HeadroomWarning", bundle: .main) }
    static var headroomCritical: Color { Color("HeadroomColors/HeadroomCritical", bundle: .main) }
    static var headroomExhausted: Color { Color("HeadroomColors/HeadroomExhausted", bundle: .main) }
    static var disconnected: Color { Color("HeadroomColors/Disconnected", bundle: .main) }

    // Extra Usage Colors
    static var extraUsageCool: Color { Color("ExtraUsageColors/ExtraUsageCool", bundle: .main) }
    static var extraUsageWarm: Color { Color("ExtraUsageColors/ExtraUsageWarm", bundle: .main) }
    static var extraUsageHot: Color { Color("ExtraUsageColors/ExtraUsageHot", bundle: .main) }
    static var extraUsageCritical: Color { Color("ExtraUsageColors/ExtraUsageCritical", bundle: .main) }

    /// Returns the SwiftUI `Color` for the given headroom state.
    /// Delegates to `HeadroomState.swiftUIColor` to avoid duplication.
    /// - Parameter state: The headroom state to get the color for.
    /// - Returns: The corresponding SwiftUI Color.
    static func headroomColor(for state: HeadroomState) -> Color {
        state.swiftUIColor
    }
}
