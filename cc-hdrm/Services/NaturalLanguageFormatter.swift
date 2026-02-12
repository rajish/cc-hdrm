import Foundation

/// Pure computation of natural language text for usage insights.
/// All methods are static — no side effects or stored state.
enum NaturalLanguageFormatter {

    /// Converts a utilization percentage to a natural language approximation.
    /// Precise value is available separately for tooltips/VoiceOver.
    static func formatPercentNatural(_ value: Double) -> String {
        switch value {
        case ..<10:
            return "a small fraction"
        case 10..<20:
            return "about a tenth"
        case 20..<30:
            return "about a quarter"
        case 30..<40:
            return "about a third"
        case 40..<60:
            return "roughly half"
        case 60..<70:
            return "about two-thirds"
        case 70..<80:
            return "about three-quarters"
        case 80..<90:
            return "most"
        default:
            return "nearly all"
        }
    }

    /// Compares current value against a baseline and returns a natural language description.
    static func formatComparisonNatural(current: Double, baseline: Double) -> String {
        guard baseline > 0 else { return "no baseline available" }
        let ratio = current / baseline

        switch ratio {
        case ..<0.4:
            return "well below your usual"
        case 0.4..<0.7:
            return "about half your usual"
        case 0.7..<1.3:
            return "close to your average"
        case 1.3..<1.8:
            return "noticeably more than typical"
        default:
            return "roughly double your usual"
        }
    }

    /// Formats a month reference for natural language anchoring (e.g., "since November").
    static func formatRelativeTimeNatural(monthName: String, year: Int? = nil) -> String {
        let currentYear = Calendar.current.component(.year, from: Date())
        if let year, year != currentYear {
            return "since \(monthName) \(year)"
        }
        return "since \(monthName)"
    }

    /// Returns a bare month reference without preposition (e.g., "November" or "November 2025").
    /// Use when the caller supplies its own preposition (e.g., "in", "from").
    static func formatMonthReference(monthName: String, year: Int? = nil) -> String {
        let currentYear = Calendar.current.component(.year, from: Date())
        if let year, year != currentYear {
            return "\(monthName) \(year)"
        }
        return monthName
    }

    /// Returns the month name for a given month number (1-12).
    static func monthName(for month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter.monthSymbols[max(0, min(11, month - 1))]
    }
}
