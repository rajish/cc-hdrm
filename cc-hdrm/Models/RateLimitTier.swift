import Foundation
import os

/// Known Anthropic subscription tiers with hardcoded credit limits.
/// Raw values match the `rateLimitTier` strings stored in Keychain.
enum RateLimitTier: String, CaseIterable, Sendable {
    case pro = "default_claude_pro"
    case max5x = "default_claude_max_5x"
    case max20x = "default_claude_max_20x"

    /// Credit limit for the 5-hour window.
    var fiveHourCredits: Int {
        switch self {
        case .pro: return 550_000
        case .max5x: return 3_300_000
        case .max20x: return 11_000_000
        }
    }

    /// Credit limit for the 7-day window.
    var sevenDayCredits: Int {
        switch self {
        case .pro: return 5_000_000
        case .max5x: return 41_666_700
        case .max20x: return 83_333_300
        }
    }

    /// Monthly subscription price in USD.
    var monthlyPrice: Double {
        switch self {
        case .pro: return 20.0
        case .max5x: return 100.0
        case .max20x: return 200.0
        }
    }

    /// Convenience to produce a `CreditLimits` value from this tier.
    var creditLimits: CreditLimits {
        CreditLimits(fiveHourCredits: fiveHourCredits, sevenDayCredits: sevenDayCredits, monthlyPrice: monthlyPrice)
    }

    // MARK: - Resolution

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "tier"
    )

    /// Resolves credit limits from a Keychain tier string, falling back to user-configured
    /// custom limits in PreferencesManager, or nil if neither is available.
    static func resolve(
        tierString: String?,
        preferencesManager: PreferencesManagerProtocol?
    ) -> CreditLimits? {
        // Try known tier first
        if let tier = RateLimitTier(rawValue: tierString ?? "") {
            return tier.creditLimits
        }

        // Try user-configured custom limits
        if let prefs = preferencesManager,
           let custom5h = prefs.customFiveHourCredits,
           let custom7d = prefs.customSevenDayCredits {
            let limits = CreditLimits(fiveHourCredits: custom5h, sevenDayCredits: custom7d, monthlyPrice: prefs.customMonthlyPrice)
            validateCustomLimits(limits)
            return limits
        }

        // No match — log and return nil
        logger.warning("Unknown rate limit tier: \(tierString ?? "nil", privacy: .public)")
        return nil
    }

    /// Validates that custom credit limits produce a sensible normalization factor.
    /// Logs a warning if the factor is extreme (< 0.1 or > 200), which would cause
    /// misleading slope readings. Called after resolving custom limits.
    private static func validateCustomLimits(_ limits: CreditLimits) {
        let factor = limits.normalizationFactor
        if factor < 0.1 || factor > 200 {
            logger.warning("Custom credit limits produce extreme normalization factor (\(String(format: "%.2f", factor), privacy: .public)). 5h=\(limits.fiveHourCredits), 7d=\(limits.sevenDayCredits). Slope readings may be misleading.")
        }
    }
}

/// Credit limits for a subscription tier. Supports both known tiers and user-configured custom limits.
struct CreditLimits: Sendable, Equatable {
    let fiveHourCredits: Int
    let sevenDayCredits: Int
    /// Monthly subscription price in USD. Nil for custom limits where price is unknown.
    let monthlyPrice: Double?

    init(fiveHourCredits: Int, sevenDayCredits: Int, monthlyPrice: Double? = nil) {
        self.fiveHourCredits = fiveHourCredits
        self.sevenDayCredits = sevenDayCredits
        self.monthlyPrice = monthlyPrice
    }

    /// 7d_limit / 5h_limit — used for slope normalization.
    /// ~9.09 for Pro, ~12.63 for Max 5x, ~7.58 for Max 20x.
    /// Returns 0 if `fiveHourCredits` is zero (defensive guard — prevents inf propagation).
    var normalizationFactor: Double {
        guard fiveHourCredits > 0 else { return 0 }
        return Double(sevenDayCredits) / Double(fiveHourCredits)
    }
}
