import Foundation

/// Represents the usage data returned by the Claude API `/api/oauth/usage` endpoint.
/// All fields are optional — missing windows result in `nil`, not crashes.
struct UsageResponse: Codable, Sendable, Equatable {
    let fiveHour: WindowUsage?
    let sevenDay: WindowUsage?
    let sevenDaySonnet: WindowUsage?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }
}

/// Usage data for a single time window (e.g., 5-hour or 7-day).
struct WindowUsage: Codable, Sendable, Equatable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

/// Extra usage billing information.
struct ExtraUsage: Codable, Sendable, Equatable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
    }
}
