# Story 16.1: Slow-Burn Pattern Detection Service

Status: review

## Story

As a developer using Claude Code,
I want cc-hdrm to detect slow-burn subscription patterns from my usage history,
so that costly patterns are caught before they become expensive surprises.

## Acceptance Criteria

1. **Given** SubscriptionPatternDetector is initialized with access to ResetEvent history and extra usage history
   **When** analyzePatterns() is called (triggered after each reset event detection)
   **Then** it evaluates the following pattern rules against historical data

2. **Pattern: Forgotten Subscription**
   **Given** utilization is below 5% for 2+ consecutive weeks (14+ days)
   **When** the pattern is detected
   **Then** it returns a .forgottenSubscription finding with:
   - Duration of low usage (in weeks)
   - Average utilization during the period
   - Monthly cost being incurred

3. **Pattern: Chronic Overpaying**
   **Given** total cost (base subscription + extra usage charges) fits within a cheaper tier for 3+ consecutive months
   **When** the pattern is detected
   **Then** it returns a .chronicOverpaying finding with:
   - Current tier and monthly cost (base + extra usage)
   - Recommended tier and monthly cost
   - Potential monthly savings

4. **Pattern: Chronic Underpowering**
   **Given** the user has been rate-limited (hit 100% on either window) more than N times per billing cycle for 2+ consecutive cycles
   **When** the pattern is detected
   **Then** it returns a .chronicUnderpowering finding with:
   - Rate-limit frequency
   - Current tier
   - Suggested higher tier
   - If extra usage is enabled and absorbing overflows: pattern triggers on cost (base + extra usage exceeds higher tier's base price), not rate-limits alone

5. **Pattern: Usage Decay**
   **Given** monthly utilization has declined for 3+ consecutive months
   **When** the pattern is detected
   **Then** it returns a .usageDecay finding with:
   - Trend direction and magnitude
   - Current vs. 3-month-ago utilization

6. **Pattern: Extra Usage Overflow**
   **Given** extra_usage.is_enabled == true and extra_usage.used_credits > 0 for 2+ consecutive billing periods
   **When** the pattern is detected
   **Then** it returns a .extraUsageOverflow finding with:
   - Overflow frequency and average extra spend per period
   - Higher tier that would have covered usage without overflow
   - Estimated savings (higher tier base price vs. current base + extra usage)

7. **Pattern: Persistent Extra Usage**
   **Given** extra_usage spending exceeds 50% of base subscription price for 2+ consecutive months
   **When** the pattern is detected
   **Then** it returns a .persistentExtraUsage finding with:
   - Average monthly extra usage spend
   - Base subscription price
   - Recommended tier and total cost comparison

8. **Given** no patterns are detected
   **When** analyzePatterns() completes
   **Then** it returns an empty findings array

9. **Given** insufficient history to evaluate a pattern (e.g., less than 2 weeks of data)
   **When** that pattern is evaluated
   **Then** it is skipped (not reported as negative finding)

10. **Given** extra usage patterns are evaluated but extra_usage.is_enabled == false or used_credits data is nil
    **When** extra usage patterns are checked
    **Then** they are skipped (insufficient data)

## Tasks / Subtasks

- [x] Task 1: Create PatternFinding model (AC: 1, 2-7)
  - [x] 1.1 Create `cc-hdrm/Models/PatternFinding.swift` with an enum defining all 6 pattern cases with associated values
  - [x] 1.2 Add `Sendable` and `Equatable` conformance
  - [x] 1.3 Add `var title: String` computed property for display text (used by 16.2 notifications)
  - [x] 1.4 Add `var summary: String` computed property for natural language finding description

- [x] Task 2: Create SubscriptionPatternDetectorProtocol (AC: 1)
  - [x] 2.1 Create `cc-hdrm/Services/SubscriptionPatternDetectorProtocol.swift`
  - [x] 2.2 Define `func analyzePatterns() async throws -> [PatternFinding]`
  - [x] 2.3 Add `Sendable` conformance

- [x] Task 3: Implement SubscriptionPatternDetector service (AC: 1-10)
  - [x] 3.1 Create `cc-hdrm/Services/SubscriptionPatternDetector.swift` conforming to protocol
  - [x] 3.2 Constructor takes `HistoricalDataServiceProtocol` and `PreferencesManagerProtocol` dependencies
  - [x] 3.3 Add `os.Logger` with category `"patterns"`
  - [x] 3.4 Implement `analyzePatterns()` that calls each pattern detector, collecting results
  - [x] 3.5 Implement `detectForgottenSubscription()` (AC: 2, 9)
  - [x] 3.6 Implement `detectChronicOverpaying()` (AC: 3, 9)
  - [x] 3.7 Implement `detectChronicUnderpowering()` (AC: 4, 9)
  - [x] 3.8 Implement `detectUsageDecay()` (AC: 5, 9)
  - [x] 3.9 Implement `detectExtraUsageOverflow()` (AC: 6, 10)
  - [x] 3.10 Implement `detectPersistentExtraUsage()` (AC: 7, 10)

- [x] Task 4: Create MockSubscriptionPatternDetector (AC: 1)
  - [x] 4.1 Create `cc-hdrmTests/Mocks/MockSubscriptionPatternDetector.swift`
  - [x] 4.2 Add `findingsToReturn: [PatternFinding]` and `analyzeCallCount` tracking
  - [x] 4.3 Add `shouldThrow` flag for error simulation

- [x] Task 5: Write unit tests for PatternFinding model (AC: 2-7)
  - [x] 5.1 Create `cc-hdrmTests/Models/PatternFindingTests.swift`
  - [x] 5.2 Test each case's title returns expected display text
  - [x] 5.3 Test each case's summary returns expected natural language description
  - [x] 5.4 Test Equatable conformance for all cases

- [x] Task 6: Write unit tests for SubscriptionPatternDetector (AC: 1-10)
  - [x] 6.1 Create `cc-hdrmTests/Services/SubscriptionPatternDetectorTests.swift`
  - [x] 6.2 Test forgottenSubscription: detected when avg utilization < 5% for 14+ days (AC: 2)
  - [x] 6.3 Test forgottenSubscription: NOT detected when utilization is above 5% (AC: 2)
  - [x] 6.4 Test forgottenSubscription: skipped with insufficient data (< 14 days) (AC: 9)
  - [x] 6.5 Test chronicOverpaying: detected when total cost fits cheaper tier for 3+ months (AC: 3)
  - [x] 6.6 Test chronicOverpaying: NOT detected when on cheapest tier (AC: 3)
  - [x] 6.7 Test chronicOverpaying: skipped with insufficient data (< 3 months) (AC: 9)
  - [x] 6.8 Test chronicUnderpowering: detected when rate-limited N+ times for 2+ cycles (AC: 4)
  - [x] 6.9 Test chronicUnderpowering: cost-based trigger when extra usage enabled (AC: 4)
  - [x] 6.10 Test usageDecay: detected when utilization declines 3+ consecutive months (AC: 5)
  - [x] 6.11 Test usageDecay: NOT detected when utilization increases (AC: 5)
  - [x] 6.12 Test extraUsageOverflow: detected with 2+ consecutive periods of overflow (AC: 6)
  - [x] 6.13 Test extraUsageOverflow: skipped when extra_usage disabled (AC: 10)
  - [x] 6.14 Test persistentExtraUsage: detected when extra > 50% of base for 2+ months (AC: 7)
  - [x] 6.15 Test persistentExtraUsage: skipped when extra usage data nil (AC: 10)
  - [x] 6.16 Test analyzePatterns: returns empty array when no patterns detected (AC: 8)
  - [x] 6.17 Test analyzePatterns: returns multiple findings when multiple patterns match

- [x] Task 7: Run `xcodegen generate` and verify compilation + tests pass

## Dev Notes

### Architecture Context

This story creates a new service following the established protocol-based pattern. The architecture document defines `SubscriptionPatternDetector` and `PatternFinding` in the Phase 4 section (`_bmad-output/planning-artifacts/architecture.md:967-993`).

**Key design decisions:**
- `SubscriptionPatternDetector` is a pure analysis service -- it queries data from `HistoricalDataService` and returns `PatternFinding` results
- The service does NOT send notifications or update UI (that is Story 16.2)
- Trigger point: called after each reset event detection (wired in 16.2, not here)
- All pattern detectors must gracefully handle insufficient data by skipping (not returning negative findings)

### Data Sources Available

The service queries existing data that is already persisted:

1. **ResetEvent history** via `HistoricalDataServiceProtocol.getResetEvents(fromTimestamp:toTimestamp:)` -- contains `timestamp`, `fiveHourPeak`, `sevenDayUtil`, `tier` fields
2. **Extra usage poll data** via `HistoricalDataServiceProtocol.getRecentPolls(hours:)` -- `UsagePoll` contains `extraUsageEnabled`, `extraUsageMonthlyLimit`, `extraUsageUsedCredits`, `extraUsageUtilization` fields (persisted by PR 43)
3. **Rolled-up data** via `HistoricalDataServiceProtocol.getRolledUpData(range:)` -- `UsageRollup` has `fiveHourAvg`, `sevenDayAvg`, `resetCount` per period
4. **Tier credit limits and pricing** via `RateLimitTier` enum and `RateLimitTier.resolve(tierString:preferencesManager:)` -- provides `fiveHourCredits`, `sevenDayCredits`, `monthlyPrice`

### PatternFinding Enum Design

Architecture specifies these cases (`_bmad-output/planning-artifacts/architecture.md:976-983`):

```swift
enum PatternFinding: Sendable, Equatable {
    case forgottenSubscription(weeks: Int, avgUtilization: Double, monthlyCost: Double)
    case chronicOverpaying(currentTier: String, recommendedTier: String, monthlySavings: Double)
    case chronicUnderpowering(rateLimitCount: Int, currentTier: String, suggestedTier: String)
    case usageDecay(currentUtil: Double, threeMonthAgoUtil: Double)
    case extraUsageOverflow(avgExtraSpend: Double, recommendedTier: String, estimatedSavings: Double)
    case persistentExtraUsage(avgMonthlyExtra: Double, basePrice: Double, recommendedTier: String)
}
```

**Important:** Use `String` for tier names in associated values (not `RateLimitTier` enum), because:
- The finding is a display-ready data transfer object
- Tier names need to be human-readable: "Pro", "Max 5x", "Max 20x"
- Avoids coupling the model to the enum

Add a computed `displayName` extension on `RateLimitTier` for human-readable tier names:
```swift
extension RateLimitTier {
    var displayName: String {
        switch self {
        case .pro: return "Pro"
        case .max5x: return "Max 5x"
        case .max20x: return "Max 20x"
        }
    }
}
```

### Pattern Detection Implementation Details

**Forgotten Subscription (AC: 2):**
- Query: `getRecentPolls(hours: 720)` for ~30 days of data, or use `getRolledUpData(range: .all)` daily rollups for longer history
- Group polls by calendar week, compute average `fiveHourUtil` per week
- If average utilization < 5% for 2+ consecutive weeks, fire finding
- `monthlyCost` comes from `RateLimitTier.resolve()?.monthlyPrice`
- Consider using rollup data for longer-term analysis (daily rollups go back months)

**Chronic Overpaying (AC: 3):**
- Requires 3+ months of data -- use `getRolledUpData(range: .all)` with daily resolution
- For each month: `totalCost = tier.monthlyPrice + extraUsageSpend`
- Check each cheaper tier: would `tier.monthlyPrice` alone cover the usage?
- Cheaper tier covers usage if the user's peak 5h utilization stays within the cheaper tier's 5h credit limit AND 7d within 7d credit limit
- `monthlySavings = currentTotalCost - recommendedTier.monthlyPrice`

**Chronic Underpowering (AC: 4):**
- Rate-limit events = polls where `fiveHourUtil >= 100` or `sevenDayUtil >= 100`
- Count per billing cycle (use calendar months if `billingCycleDay` not set)
- Threshold N: suggest 3+ rate-limit events per cycle as meaningful
- When extra usage enabled: compare `currentTier.monthlyPrice + avgExtraUsage` against `higherTier.monthlyPrice`

**Usage Decay (AC: 5):**
- Use daily rollups, compute monthly average `fiveHourAvg`
- 3+ consecutive months of decline = decay pattern
- Report magnitude as percentage points dropped

**Extra Usage Overflow (AC: 6):**
- Query polls with `extraUsageEnabled == true` and `extraUsageUsedCredits > 0`
- Group by billing period (calendar month or `billingCycleDay`)
- 2+ consecutive periods with overflow = pattern
- Find covering tier: iterate `RateLimitTier.allCases` sorted by price ascending, find first where credit limits would have covered usage
- `estimatedSavings = (currentBase + avgExtra) - recommendedTier.monthlyPrice`

**Persistent Extra Usage (AC: 7):**
- Similar to overflow but threshold is extra > 50% of base price
- `avgMonthlyExtra > (tier.monthlyPrice * 0.5)` for 2+ months

### Billing Period Calculation

When `billingCycleDay` is set in `PreferencesManager`, use it for monthly boundaries. Otherwise, use calendar months (1st-to-1st).

```swift
private func billingPeriodBoundaries(for date: Date) -> (start: Date, end: Date) {
    let calendar = Calendar.current
    if let cycleDay = preferencesManager.billingCycleDay {
        // ... align to billing cycle day
    } else {
        // Calendar month boundaries
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return (start, end)
    }
}
```

**Note:** `billingCycleDay` property is added to PreferencesManager in Story 16.4. For 16.1, use calendar months only. The billing cycle alignment will be added when 16.4 is implemented.

### Key Integration Points

**Files consumed (read-only):**
- `cc-hdrm/Services/HistoricalDataServiceProtocol.swift` -- data queries
- `cc-hdrm/Services/PreferencesManagerProtocol.swift` -- custom credit limits, billing cycle day
- `cc-hdrm/Models/RateLimitTier.swift` -- tier resolution, credit limits, monthly pricing
- `cc-hdrm/Models/ResetEvent.swift` -- reset event data model
- `cc-hdrm/Models/UsagePoll.swift` -- poll data with extra usage fields
- `cc-hdrm/Models/UsageRollup.swift` -- aggregated historical data

**Existing mock available:**
- `cc-hdrmTests/Mocks/MockHistoricalDataService.swift` -- already has `mockResetEvents`, `recentPollsToReturn`, `rolledUpDataToReturn`
- `cc-hdrmTests/Mocks/MockPreferencesManager.swift` -- already has `customFiveHourCredits`, `customSevenDayCredits`, `customMonthlyPrice`

### Potential Pitfalls

1. **Data scarcity at start:** Most users will have less than 3 months of data initially. Every pattern detector MUST check for sufficient data and skip silently. Never report "no pattern detected" as a finding.

2. **Extra usage data may be nil:** The `extra_usage` fields in `UsagePoll` are all optional. Extra usage patterns (AC: 6, 7) must check `extraUsageEnabled == true` AND `extraUsageUsedCredits != nil` before proceeding.

3. **Tier comparison direction:** Chronic overpaying checks downward (cheaper tiers). Chronic underpowering and extra usage overflow check upward (more expensive tiers). Do NOT confuse the direction.

4. **Rate-limit detection:** "Rate-limited" means utilization hit 100%. Use `fiveHourUtil >= 100.0 || sevenDayUtil >= 100.0` as the threshold. Do NOT use `fiveHourPeak` from reset events (that's the peak before a reset, not necessarily 100%).

5. **Avoid querying too much data:** Use `getRolledUpData(range: .all)` for multi-month analysis rather than `getRecentPolls(hours:)` with a huge hour count. Rollup data is already aggregated and much smaller.

6. **Calendar month math:** Use `Calendar.current` with `DateComponents` for month arithmetic. Do NOT use fixed 30-day periods for "month" calculations.

7. **Thread safety:** The service is `@unchecked Sendable` and uses `async throws` methods. Internal state should be method-local; no mutable stored properties beyond injected dependencies.

### Testing Strategy

- Use `MockHistoricalDataService` to inject specific `mockResetEvents`, `recentPollsToReturn`, and `rolledUpDataToReturn`
- Use `MockPreferencesManager` to set tier and custom limits
- Create helper functions to generate realistic test data (e.g., `makeWeeksOfLowUsage()`, `makeMonthsOfOverpaying()`)
- Test each pattern independently, then test combined scenarios
- Test edge cases: exactly at threshold, one day short of required period, empty data

### Project Structure Notes

New files to create:
```
cc-hdrm/Models/PatternFinding.swift              # NEW
cc-hdrm/Services/SubscriptionPatternDetectorProtocol.swift  # NEW
cc-hdrm/Services/SubscriptionPatternDetector.swift          # NEW
cc-hdrmTests/Mocks/MockSubscriptionPatternDetector.swift    # NEW
cc-hdrmTests/Models/PatternFindingTests.swift               # NEW
cc-hdrmTests/Services/SubscriptionPatternDetectorTests.swift # NEW
```

After adding files, run `xcodegen generate` to regenerate the Xcode project.

### References

- [Source: _bmad-output/planning-artifacts/architecture.md:967-993] - SubscriptionPatternDetector architecture definition
- [Source: _bmad-output/planning-artifacts/architecture.md:1036-1068] - RateLimitTier with monthlyPrice
- [Source: _bmad-output/planning-artifacts/architecture.md:1543-1634] - Phase 4 architectural additions and data flow
- [Source: _bmad-output/planning-artifacts/epics/epic-16-subscription-intelligence-phase-4.md:17-93] - Story 16.1 acceptance criteria
- [Source: cc-hdrm/Models/RateLimitTier.swift:6-106] - RateLimitTier enum, CreditLimits struct, resolve() method
- [Source: cc-hdrm/Models/ResetEvent.swift:1-23] - ResetEvent model with all fields
- [Source: cc-hdrm/Models/UsagePoll.swift:1-25] - UsagePoll with extra usage fields
- [Source: cc-hdrm/Models/UsageRollup.swift:1-40] - UsageRollup aggregated data model
- [Source: cc-hdrm/Models/UsageResponse.swift:31-43] - ExtraUsage Codable model
- [Source: cc-hdrm/Services/HistoricalDataServiceProtocol.swift:1-73] - Data query API surface
- [Source: cc-hdrm/Services/HistoricalDataService.swift:46-188] - Poll persistence with extra usage columns
- [Source: cc-hdrm/Services/PreferencesManagerProtocol.swift:1-32] - Preferences protocol with custom credit limits
- [Source: cc-hdrmTests/Mocks/MockHistoricalDataService.swift:1-115] - Mock with all needed properties
- [Source: cc-hdrmTests/Mocks/MockPreferencesManager.swift] - Mock with custom credit properties
- [Source: _bmad-output/implementation-artifacts/15-2-custom-credit-limit-override.md] - Previous story with RateLimitTier.resolve() patterns

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (claude-opus-4-6)

### Debug Log References

N/A

### Completion Notes List

- All 6 pattern detectors implemented: forgottenSubscription, chronicOverpaying, chronicUnderpowering, usageDecay, extraUsageOverflow, persistentExtraUsage
- Each detector gracefully handles insufficient data by returning nil (AC: 9)
- Extra usage patterns skip when extraUsageEnabled is false or data is nil (AC: 10)
- Added `displayName` computed property to `RateLimitTier` for human-readable tier names
- Calendar-month grouping used for billing period boundaries (year*100+month key pattern)
- All 947 tests pass including 16 new SubscriptionPatternDetector tests and 16 new PatternFinding tests
- `@unchecked Sendable` on SubscriptionPatternDetector with method-local state only

### File List

New files:
- `cc-hdrm/Models/PatternFinding.swift` -- PatternFinding enum with 6 cases, title/summary computed properties
- `cc-hdrm/Services/SubscriptionPatternDetectorProtocol.swift` -- Protocol with analyzePatterns() async throws
- `cc-hdrm/Services/SubscriptionPatternDetector.swift` -- Full implementation with 6 pattern detectors
- `cc-hdrmTests/Mocks/MockSubscriptionPatternDetector.swift` -- Mock for testing consumers
- `cc-hdrmTests/Models/PatternFindingTests.swift` -- 16 tests for model titles, summaries, equatable
- `cc-hdrmTests/Services/SubscriptionPatternDetectorTests.swift` -- 16 tests covering all ACs

Modified files:
- `cc-hdrm/Models/RateLimitTier.swift` -- Added displayName computed property
