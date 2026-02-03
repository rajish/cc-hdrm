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

// MARK: - SwiftUI Color Headroom Mapping

extension Color {
    static var headroomNormal: Color { Color("HeadroomColors/HeadroomNormal", bundle: .main) }
    static var headroomCaution: Color { Color("HeadroomColors/HeadroomCaution", bundle: .main) }
    static var headroomWarning: Color { Color("HeadroomColors/HeadroomWarning", bundle: .main) }
    static var headroomCritical: Color { Color("HeadroomColors/HeadroomCritical", bundle: .main) }
    static var headroomExhausted: Color { Color("HeadroomColors/HeadroomExhausted", bundle: .main) }
    static var disconnected: Color { Color("HeadroomColors/Disconnected", bundle: .main) }

    /// Returns the SwiftUI `Color` for the given headroom state.
    /// Uses the static color properties which reference the Asset Catalog.
    /// - Parameter state: The headroom state to get the color for.
    /// - Returns: The corresponding SwiftUI Color.
    static func headroomColor(for state: HeadroomState) -> Color {
        switch state {
        case .normal:
            return .headroomNormal
        case .caution:
            return .headroomCaution
        case .warning:
            return .headroomWarning
        case .critical:
            return .headroomCritical
        case .exhausted:
            return .headroomExhausted
        case .disconnected:
            return .disconnected
        }
    }
}
