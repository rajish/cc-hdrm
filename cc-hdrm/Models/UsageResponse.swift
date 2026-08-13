import Foundation

/// Represents the usage data returned by the Claude API `/api/oauth/usage` endpoint.
/// All fields are optional — missing windows result in `nil`, not crashes.
struct UsageResponse: Codable, Sendable, Equatable {
    let fiveHour: WindowUsage?
    let sevenDay: WindowUsage?
    let limits: [LimitEntry]?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case limits
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

/// A single entry in the API's `limits` array — source of truth for model-scoped caps.
/// `kind` is decoded as a plain String so unknown future kinds never fail decoding.
struct LimitEntry: Codable, Sendable, Equatable {
    let kind: String?
    let group: String?
    let percent: Double?
    let severity: String?
    let resetsAt: String?
    let isActive: Bool?
    let scope: LimitScope?

    enum CodingKeys: String, CodingKey {
        case kind
        case group
        case percent
        case severity
        case resetsAt = "resets_at"
        case isActive = "is_active"
        case scope
    }
}

/// The scope of a limit entry — identifies which model or surface the cap applies to.
struct LimitScope: Codable, Sendable, Equatable {
    let model: ScopedModel?
    let surface: String?
}

/// The model a scoped limit applies to. `displayName` is the user-facing label.
struct ScopedModel: Codable, Sendable, Equatable {
    let id: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

/// Extra usage billing information.
/// Note: `monthlyLimit` and `usedCredits` are returned by the API in **cents**
/// (smallest currency unit). Divide by 100 before displaying as currency.
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
