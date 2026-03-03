import Foundation

/// Represents an API outage period tracked by HistoricalDataService.
/// An outage starts after 2 consecutive poll failures and ends on the first successful poll.
struct OutagePeriod: Sendable, Equatable {
    /// Database row ID
    let id: Int64
    /// Unix milliseconds when the outage was detected (2nd consecutive failure)
    let startedAt: Int64
    /// Unix milliseconds when the outage ended (first successful poll), nil if ongoing
    let endedAt: Int64?
    /// Reason for the outage (e.g., "networkUnreachable", "httpError:503")
    let failureReason: String

    /// Whether this outage is still ongoing (no recovery detected yet).
    var isOngoing: Bool {
        endedAt == nil
    }

    /// The outage start time as a Date.
    var startDate: Date {
        Date(timeIntervalSince1970: Double(startedAt) / 1000.0)
    }

    /// The outage end time as a Date, nil if ongoing.
    var endDate: Date? {
        endedAt.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
    }
}
