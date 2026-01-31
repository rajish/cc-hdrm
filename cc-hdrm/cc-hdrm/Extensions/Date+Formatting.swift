import Foundation

extension Date {
    private nonisolated(unsafe) static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Returns a human-readable relative time string (e.g. "5s ago", "2m ago", "1h 30m ago").
    func relativeTimeAgo() -> String {
        let elapsed = max(0, Date().timeIntervalSince(self))
        switch elapsed {
        case ..<1:
            return "just now"
        case ..<60:
            return "\(Int(elapsed))s ago"
        case ..<3600:
            return "\(Int(elapsed / 60))m ago"
        case ..<86400:
            let hours = Int(elapsed / 3600)
            let minutes = Int((elapsed.truncatingRemainder(dividingBy: 3600)) / 60)
            return minutes > 0 ? "\(hours)h \(minutes)m ago" : "\(hours)h ago"
        default:
            let days = Int(elapsed / 86400)
            let hours = Int((elapsed.truncatingRemainder(dividingBy: 86400)) / 3600)
            return hours > 0 ? "\(days)d \(hours)h ago" : "\(days)d ago"
        }
    }

    /// Parses an ISO 8601 date string with fractional seconds support.
    /// Returns `nil` on parse failure — never crashes.
    static func fromISO8601(_ string: String) -> Date? {
        if let date = iso8601FractionalFormatter.date(from: string) {
            return date
        }

        // Fallback: try without fractional seconds
        return iso8601Formatter.date(from: string)
    }
}
