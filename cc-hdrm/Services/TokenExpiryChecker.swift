import Foundation

/// Token validity status derived from `expiresAt` timestamp.
enum TokenStatus: Sendable, Equatable {
    case valid
    case expiringSoon
    case expired
}

/// Pure function for checking token expiry status.
/// No cases enum — used as a namespace for the static method.
enum TokenExpiryChecker {
    /// Pre-emptive refresh threshold: 5 minutes (300 seconds).
    static let preEmptiveRefreshThreshold: TimeInterval = 300

    /// Determines token status from credentials' `expiresAt` field.
    ///
    /// - `expiresAt` is Unix milliseconds. Divide by 1000 for `Date(timeIntervalSince1970:)`.
    /// - If `expiresAt` is nil, treat as `.valid` (unknown expiry = optimistically try API).
    static func tokenStatus(for credentials: KeychainCredentials, now: Date = Date()) -> TokenStatus {
        guard let expiresAtMs = credentials.expiresAt else {
            return .valid
        }

        let expiresAtDate = Date(timeIntervalSince1970: expiresAtMs / 1000.0)
        let timeUntilExpiry = expiresAtDate.timeIntervalSince(now)

        if timeUntilExpiry <= 0 {
            return .expired
        } else if timeUntilExpiry <= preEmptiveRefreshThreshold {
            return .expiringSoon
        } else {
            return .valid
        }
    }
}
