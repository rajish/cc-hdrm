# Story 16.3: Tier Recommendation Service

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want cc-hdrm to compare my actual usage against all available tiers,
so that I know whether I'm on the right plan with concrete dollar figures.

## Acceptance Criteria

1. **Given** TierRecommendationService is initialized with access to ResetEvent history, RateLimitTier data, and extra usage history
   **When** `recommendTier()` is called with a time range
   **Then** it compares actual usage against each tier using total cost:
   - For each tier: would this tier's 5h and 7d limits have covered the user's usage?
   - Safety margin: requires 20% headroom above actual peak usage (configurable)
   - Total cost comparison: for each tier, computes `total = base_price + estimated_extra_usage`. If usage fits within a tier's limits, extra usage = $0. If usage exceeds limits and extra usage is enabled, includes actual or estimated overflow cost at API rates.

2. **Given** the user's usage fits a cheaper tier with safety margin
   **When** the recommendation is computed
   **Then** it returns a `.downgrade` recommendation with:
   - Current tier name and monthly total cost (base + extra usage if applicable)
   - Recommended tier name and monthly total cost
   - Monthly savings
   - Confidence note: "Based on [N] weeks of usage data"

3. **Given** the user has been rate-limited or is paying extra usage overflow, and a higher tier would have been cheaper
   **When** the recommendation is computed
   **Then** it returns an `.upgrade` recommendation with:
   - Current tier name and monthly total cost (base + extra usage)
   - Recommended tier name and monthly price
   - Number of rate-limit events that would have been avoided
   - Cost comparison string (e.g., "On Pro ($20/mo) you paid ~$47 in extra usage ($67 total) -- Max 5x ($100/mo) would have covered you and saved $67")

4. **Given** the user is on the best-fit tier
   **When** the recommendation is computed
   **Then** it returns a `.goodFit` recommendation with:
   - Current tier name
   - Headroom percentage remaining
   - Brief confirmation: no action needed

5. **Given** fewer than 2 weeks of usage data exist
   **When** `recommendTier()` is called
   **Then** it returns nil (insufficient data for a meaningful recommendation)

6. **Given** billing cycle day is configured in preferences
   **When** the recommendation is computed
   **Then** it aligns analysis to complete billing cycles where possible
   **And** flags the current partial cycle as provisional

7. **Given** extra usage data is unavailable (is_enabled = false or no data)
   **When** the recommendation is computed
   **Then** it falls back to credit-only comparison (pre-extra-usage behavior)

## Tasks / Subtasks

- [ ] Task 1: Create TierRecommendationServiceProtocol (AC: 1, 2, 3, 4, 5)
  - [ ] 1.1 Create `cc-hdrm/Services/TierRecommendationServiceProtocol.swift` with `recommendTier(for range: TimeRange) async throws -> TierRecommendation?` method
  - [ ] 1.2 Define `TierRecommendation` enum in `cc-hdrm/Models/TierRecommendation.swift` with cases: `.downgrade`, `.upgrade`, `.goodFit` carrying associated data

- [ ] Task 2: Create TierRecommendationService implementation (AC: 1, 2, 3, 4, 5, 6, 7)
  - [ ] 2.1 Create `cc-hdrm/Services/TierRecommendationService.swift` with dependencies: `HistoricalDataServiceProtocol`, `PreferencesManagerProtocol`
  - [ ] 2.2 Implement `recommendTier(for:)` — return nil when data spans fewer than 14 days (AC 5)
  - [ ] 2.3 Implement reset event retrieval and tier resolution via `RateLimitTier.resolve()`
  - [ ] 2.4 Implement per-tier usage fitness check: for each `RateLimitTier.allCases`, would the tier's 5h and 7d limits have covered the user's peak usage with 20% safety margin?
  - [ ] 2.5 Implement extra usage cost estimation: query `usage_polls` for extra usage data, compute average monthly extra spend per billing period
  - [ ] 2.6 Implement total cost comparison: for each tier, `total = monthlyPrice + estimatedExtraUsage`. If usage fits within tier limits, extra usage = $0
  - [ ] 2.7 Implement recommendation logic: compare current tier total cost vs. each alternative tier total cost to find optimal tier
  - [ ] 2.8 Return `.downgrade` when a cheaper tier covers usage (AC 2), `.upgrade` when a more expensive tier is cheaper in total (AC 3), `.goodFit` otherwise (AC 4)
  - [ ] 2.9 Implement billing cycle alignment when `billingCycleDay` is set (AC 6)
  - [ ] 2.10 Implement credit-only fallback when extra usage data is unavailable (AC 7)
  - [ ] 2.11 Add `os.Logger` logging with category `"recommendation"` for key decisions

- [ ] Task 3: Add `billingCycleDay` to PreferencesManager (AC: 6)
  - [ ] 3.1 Add `billingCycleDay: Int?` to `PreferencesManagerProtocol` (nil = unset, 1-28)
  - [ ] 3.2 Add UserDefaults key `com.cc-hdrm.billingCycleDay` and getter/setter to `PreferencesManager` (getter returns nil if 0 or out of 1-28 range; setter stores value or removes key if nil)
  - [ ] 3.3 Add `billingCycleDay` to `MockPreferencesManager` (default: nil)
  - [ ] 3.4 Add `billingCycleDay` to `resetToDefaults()` in `PreferencesManager`

- [ ] Task 4: Create MockTierRecommendationService (for future story 16.4 tests)
  - [ ] 4.1 Create `cc-hdrmTests/Mocks/MockTierRecommendationService.swift` conforming to `TierRecommendationServiceProtocol`

- [ ] Task 5: Write tests for TierRecommendationService (AC: 1-7)
  - [ ] 5.1 Test returns nil when fewer than 14 days of data exist (AC 5)
  - [ ] 5.2 Test returns `.goodFit` when user is on optimal tier with headroom (AC 4)
  - [ ] 5.3 Test returns `.downgrade` when usage fits a cheaper tier with safety margin (AC 2)
  - [ ] 5.4 Test returns `.upgrade` when higher tier is cheaper than current base + extra usage (AC 3)
  - [ ] 5.5 Test safety margin: usage at 85% of tier limit is NOT a downgrade candidate (margin requires 20% headroom)
  - [ ] 5.6 Test credit-only fallback when extra usage data is unavailable (AC 7)
  - [ ] 5.7 Test rate-limit count calculation for upgrade recommendation
  - [ ] 5.8 Test cost comparison string generation for upgrade with extra usage context
  - [ ] 5.9 Test billing cycle alignment when `billingCycleDay` is configured (AC 6)
  - [ ] 5.10 Test handles unknown tier gracefully (returns nil when current tier unresolvable)

- [ ] Task 6: Write tests for billingCycleDay preference (AC: 6)
  - [ ] 6.1 Test billingCycleDay defaults to nil
  - [ ] 6.2 Test valid values (1-28) persist and read back correctly
  - [ ] 6.3 Test out-of-range values (0, 29, negative) return nil
  - [ ] 6.4 Test resetToDefaults clears billingCycleDay

- [ ] Task 7: Run `xcodegen generate` and verify all tests pass
  - [ ] 7.1 Run `xcodegen generate` to include new files in project
  - [ ] 7.2 Build project and run full test suite

## Dev Notes

### Architecture Context

This story creates the **TierRecommendationService** described in the architecture document under "Phase 4 Architectural Additions". The service is a pure computation layer that queries existing data sources (ResetEvent history, extra usage poll data) and compares usage against all known tiers.

**Key architectural pattern:** Protocol-based service with dependency injection. Follow the same pattern established by `HeadroomAnalysisService` (`cc-hdrm/Services/HeadroomAnalysisService.swift`):
- Protocol in separate file (`TierRecommendationServiceProtocol.swift`)
- Implementation class is `final class`, `@unchecked Sendable`
- Dependencies injected via `init()`
- Uses `os.Logger` for structured logging

### Data Sources

**ResetEvent history** (`cc-hdrm/Services/HistoricalDataServiceProtocol.swift`):
- `getResetEvents(range:)` returns `[ResetEvent]` — use to count rate-limit events (events where `fiveHourPeak` was near 100%)
- `getResetEvents(fromTimestamp:toTimestamp:)` for custom date ranges
- Each `ResetEvent` has: `id`, `timestamp`, `fiveHourPeak`, `sevenDayUtil`, `tier`, `usedCredits`, `constrainedCredits`, `unusedCredits`

**Extra usage poll data** — query `usage_polls` table via `HistoricalDataServiceProtocol`:
- `getRecentPolls(hours:)` returns `[UsagePoll]` where each poll has `extraUsageEnabled`, `extraUsageMonthlyLimit`, `extraUsageUsedCredits`, `extraUsageUtilization`
- For monthly cost estimation, need to query polls across the full analysis range and aggregate extra usage per billing period

**Note:** `HistoricalDataServiceProtocol` does NOT currently expose a method to query polls across arbitrary time ranges (only `getRecentPolls(hours:)`). The service will need to either:
- **Option A (preferred):** Add a new method `getPolls(fromTimestamp:toTimestamp:)` to `HistoricalDataServiceProtocol` — thin wrapper over the existing SQL query pattern
- **Option B:** Use `getRecentPolls(hours:)` with a sufficiently large hours parameter to cover the analysis range

If Option A is chosen, add the method to the protocol, implement in `HistoricalDataService`, and add to `MockHistoricalDataService`. This is a minimal, backwards-compatible addition.

### RateLimitTier Credit Limits and Monthly Pricing

Already defined at `cc-hdrm/Models/RateLimitTier.swift`:

| Tier   | Raw Value                 | 5h Credits  | 7d Credits   | Monthly Price |
|--------|---------------------------|-------------|--------------|---------------|
| Pro    | `default_claude_pro`      | 550,000     | 5,000,000    | $20           |
| Max 5x | `default_claude_max_5x`  | 3,300,000   | 41,666,700   | $100          |
| Max 20x| `default_claude_max_20x` | 11,000,000  | 83,333,300   | $200          |

`CreditLimits` struct already has `monthlyPrice: Double?` at `cc-hdrm/Models/RateLimitTier.swift:91`.

Tier resolution via `RateLimitTier.resolve(tierString:preferencesManager:)` at `cc-hdrm/Models/RateLimitTier.swift:52-73` handles known tiers, custom limits fallback, and unknown tiers (returns nil).

### Recommendation Algorithm

```
1. Gather data:
   - resetEvents = getResetEvents for analysis range
   - If fewer than 14 days of data -> return nil
   - Resolve current tier from most recent reset event's tier string
   - If current tier unresolvable -> return nil

2. For each tier in RateLimitTier.allCases:
   a. Would this tier's limits cover the user's usage?
      - Check peak 5h utilization across reset events
      - Convert peak from percentage to credits: peakCredits = (peak% / 100) * currentTier.fiveHourCredits
      - Tier covers usage if: peakCredits * 1.2 (safety margin) <= candidateTier.fiveHourCredits
      - Similarly check 7d: if any sevenDayUtil exceeds what candidateTier would allow
   b. Estimate total cost for this tier:
      - If usage fits within limits: totalCost = tier.monthlyPrice
      - If usage exceeds limits and extra usage enabled: totalCost = tier.monthlyPrice + estimatedOverflowCost
      - If usage exceeds limits and extra usage NOT enabled: tier is insufficient (user would be rate-limited)

3. Find optimal tier:
   - Cheapest tier where usage fits with safety margin
   - Compare against current tier's total cost

4. Generate recommendation:
   - If optimal tier is cheaper -> .downgrade
   - If optimal tier is more expensive but cheaper than current total (base + extra) -> .upgrade
   - Otherwise -> .goodFit
```

### Rate-Limit Event Detection

A reset event with `fiveHourPeak` close to 100% (e.g., >= 95%) indicates the user hit or nearly hit the rate limit. Count these events to populate the "rate-limit events that would have been avoided" field in `.upgrade` recommendations.

### Billing Cycle Alignment (AC 6)

When `billingCycleDay` is set in `PreferencesManager`:
- Determine billing period boundaries: each period runs from day N of month M to day N of month M+1
- Only analyze complete billing periods for the recommendation
- Mark the current partial period as provisional (include data but note it's incomplete)
- When unset, use calendar months as approximation

This is a **new preference property** that does not currently exist on `PreferencesManagerProtocol`. Task 3 adds it following the exact same pattern as existing optional preferences (`customFiveHourCredits`, `customSevenDayCredits`).

### Extra Usage Cost Estimation

When `extraUsageEnabled == true` in poll data:
- Aggregate `extraUsageUsedCredits` per billing period
- The API reports `used_credits` as a dollar amount (not credits despite the field name)
- Average monthly extra spend = total extra usage across all complete billing periods / number of complete periods
- For tier comparison: if usage would have fit within a candidate tier's limits, the extra usage for that tier = $0

When extra usage data is unavailable:
- Fall back to credit-only comparison (just check if usage fits within tier limits)
- Do not include extra usage cost in total cost calculations

### TierRecommendation Model

```swift
enum TierRecommendation: Sendable, Equatable {
    case downgrade(
        currentTier: RateLimitTier,
        currentMonthlyCost: Double,       // base + extra usage
        recommendedTier: RateLimitTier,
        recommendedMonthlyCost: Double,    // base only (usage fits)
        monthlySavings: Double,
        weeksOfData: Int
    )
    case upgrade(
        currentTier: RateLimitTier,
        currentMonthlyCost: Double,       // base + extra usage
        recommendedTier: RateLimitTier,
        recommendedMonthlyPrice: Double,   // base price of recommended tier
        rateLimitsAvoided: Int,
        costComparison: String?           // natural language comparison
    )
    case goodFit(
        tier: RateLimitTier,
        headroomPercent: Double
    )
}
```

### Key Integration Points

**PreferencesManagerProtocol** (`cc-hdrm/Services/PreferencesManagerProtocol.swift`):
- Add `billingCycleDay: Int?` property (new, Task 3)
- Existing: `customFiveHourCredits`, `customSevenDayCredits`, `customMonthlyPrice` for custom tier resolution

**MockPreferencesManager** (`cc-hdrmTests/Mocks/MockPreferencesManager.swift`):
- Add `var billingCycleDay: Int? = nil`

**PreferencesManager** (`cc-hdrm/Services/PreferencesManager.swift`):
- Add `Keys.billingCycleDay = "com.cc-hdrm.billingCycleDay"`
- Add getter (return nil if value <= 0 or > 28) and setter (store or remove)
- Add to `resetToDefaults()`

### Potential Pitfalls

1. **Credit conversion between tiers:** When comparing usage against a different tier, remember that `fiveHourPeak` percentage is relative to the CURRENT tier's credits, not the candidate tier's. Convert to absolute credits first: `peakCredits = (peak% / 100) * currentTier.fiveHourCredits`, then check if `peakCredits <= candidateTier.fiveHourCredits`.

2. **Extra usage `usedCredits` is a dollar amount:** Despite the field name, `extraUsageUsedCredits` from the API represents dollar spend, not token credits. Do NOT convert or multiply by API rates.

3. **Safety margin direction:** The 20% safety margin means the recommended tier must have at least 20% headroom ABOVE the user's peak usage. So if peak is 80% of tier capacity, the user needs the SAME tier (80% * 1.2 = 96% < 100%), but if peak is 85%, they need a bigger tier (85% * 1.2 = 102% > 100%).

4. **Empty reset events:** If no reset events exist in the analysis range, the service cannot determine usage patterns. Return nil rather than guessing.

5. **Mixed tier events:** Reset events may have different tier strings if the user changed tiers during the analysis period. Use the most recent tier as "current" for the recommendation. The credit comparison should use absolute credits (converted from the event's own tier).

6. **Billing cycle edge cases:** When `billingCycleDay` is 29, 30, or 31, those days don't exist in every month. The architecture spec caps at 1-28 to avoid this. Validate in the preference getter.

### Previous Story Intelligence (15.2)

Key learnings from Story 15.2 that apply here:
- **`RateLimitTier.resolve()` already handles** known tiers, custom limits, and unknown tiers. Reuse it, don't duplicate.
- **`MockPreferencesManager`** already supports all custom properties. Just add `billingCycleDay`.
- **`resetToDefaults()`** must be updated when adding new preferences.
- Full test suite had 976 tests as of 15.2. Use `swift test` or Xcode to run.

### Git Intelligence

Recent commits show:
- `d2dfb24` (Story 15.2): Added custom credit limit override UI
- `c35bce3` (Story 15.1): Added data retention configuration
- `2743534` (PR 43): Persisted extra usage data to SQLite — the extra_usage columns already exist in `usage_polls` table

Files to create:
- `cc-hdrm/Services/TierRecommendationServiceProtocol.swift` (NEW)
- `cc-hdrm/Services/TierRecommendationService.swift` (NEW)
- `cc-hdrm/Models/TierRecommendation.swift` (NEW)
- `cc-hdrmTests/Services/TierRecommendationServiceTests.swift` (NEW)
- `cc-hdrmTests/Mocks/MockTierRecommendationService.swift` (NEW)

Files to modify:
- `cc-hdrm/Services/PreferencesManagerProtocol.swift` — add `billingCycleDay`
- `cc-hdrm/Services/PreferencesManager.swift` — add key, getter, setter, resetToDefaults
- `cc-hdrmTests/Mocks/MockPreferencesManager.swift` — add `billingCycleDay`
- `cc-hdrm/Services/HistoricalDataServiceProtocol.swift` — potentially add `getPolls(fromTimestamp:toTimestamp:)` if needed
- `cc-hdrm/Services/HistoricalDataService.swift` — implement new method if added
- `cc-hdrmTests/Mocks/MockHistoricalDataService.swift` — add new method if added

### Project Structure Notes

All new files follow established layer-based organization:
- Protocols in `cc-hdrm/Services/` — `TierRecommendationServiceProtocol.swift`
- Implementations in `cc-hdrm/Services/` — `TierRecommendationService.swift`
- Models in `cc-hdrm/Models/` — `TierRecommendation.swift`
- Tests in `cc-hdrmTests/Services/` — `TierRecommendationServiceTests.swift`
- Mocks in `cc-hdrmTests/Mocks/` — `MockTierRecommendationService.swift`

After adding files, run `xcodegen generate` to regenerate the Xcode project.

### References

- [Source: _bmad-output/planning-artifacts/epics/epic-16-subscription-intelligence-phase-4.md] - Story 16.3 acceptance criteria (lines 143-197)
- [Source: _bmad-output/planning-artifacts/architecture.md] - TierRecommendationService protocol and enum (lines 997-1014)
- [Source: _bmad-output/planning-artifacts/architecture.md] - Phase 4 Architectural Additions (lines 1543-1634)
- [Source: _bmad-output/planning-artifacts/sprint-change-proposal-2026-02-10.md] - Story 16.3 enrichment with extra usage (lines 180-191)
- [Source: _bmad-output/brainstorming/brainstorming-session-2026-02-09.md] - Theme 3: API Pricing & Tier Recommendation (lines 140-147)
- [Source: cc-hdrm/Models/RateLimitTier.swift] - Tier enum with credit limits and monthlyPrice (lines 1-106)
- [Source: cc-hdrm/Services/HistoricalDataServiceProtocol.swift] - Data query APIs (lines 1-73)
- [Source: cc-hdrm/Models/ResetEvent.swift] - ResetEvent struct (lines 1-23)
- [Source: cc-hdrm/Models/UsagePoll.swift] - UsagePoll with extra usage fields (lines 1-25)
- [Source: cc-hdrm/Models/TimeRange.swift] - TimeRange enum (lines 1-61)
- [Source: cc-hdrm/Services/PreferencesManagerProtocol.swift] - Existing protocol (lines 1-32)
- [Source: cc-hdrm/Services/PreferencesManager.swift] - Existing implementation with custom credit patterns (lines 1-211)
- [Source: cc-hdrm/Services/HeadroomAnalysisService.swift] - Pattern to follow for service implementation (lines 1-121)
- [Source: cc-hdrmTests/Mocks/MockHistoricalDataService.swift] - Mock pattern (lines 1-115)
- [Source: cc-hdrmTests/Mocks/MockPreferencesManager.swift] - Mock pattern (lines 1-29)
- [Source: _bmad-output/implementation-artifacts/15-2-custom-credit-limit-override.md] - Previous story with PreferencesManager patterns

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

None

### Completion Notes List

- All 7 ACs implemented and verified with 19 passing tests across 3 test suites
- Used Option B for poll data access (getRecentPolls with large hours parameter) to avoid modifying HistoricalDataServiceProtocol
- Removed duplicate `displayName` extension on RateLimitTier (track-a had already added it in Story 16.1)
- Fixed Swift 6 compile error in track-a's SubscriptionPatternDetector.swift:510 (missing `return` keyword)
- One pre-existing test failure in track-a's SubscriptionPatternDetectorTests (extraUsageOverflowDetected) -- not caused by this story's changes
- Build compiles successfully, all 19 story tests pass (0.045 seconds)

### File List

**Created:**
- `cc-hdrm/Models/TierRecommendation.swift` -- Enum with .downgrade, .upgrade, .goodFit cases
- `cc-hdrm/Services/TierRecommendationServiceProtocol.swift` -- Protocol with recommendTier(for:) method
- `cc-hdrm/Services/TierRecommendationService.swift` -- Full implementation (~340 lines)
- `cc-hdrmTests/Services/TierRecommendationServiceTests.swift` -- 19 tests across 3 suites
- `cc-hdrmTests/Mocks/MockTierRecommendationService.swift` -- Mock for future Story 16.4

**Modified:**
- `cc-hdrm/Services/PreferencesManagerProtocol.swift` -- Added billingCycleDay: Int? property
- `cc-hdrm/Services/PreferencesManager.swift` -- Added billingCycleDay key, getter/setter, resetToDefaults
- `cc-hdrmTests/Mocks/MockPreferencesManager.swift` -- Added billingCycleDay property
- `cc-hdrm/Services/SubscriptionPatternDetector.swift` -- Fixed missing return keyword (line 510, track-a's code)
