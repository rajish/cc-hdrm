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
