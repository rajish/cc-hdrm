# Story 14.2: Headroom Analysis Service

Status: done

## Story

As a developer using Claude Code,
I want headroom analysis calculated at each reset event,
So that waste breakdown is accurate and meaningful.

## Acceptance Criteria

1. **Given** a reset event is detected (from Story 10.3)
   **When** HeadroomAnalysisService.analyzeResetEvent() is called
   **Then** it calculates:
   ```
   5h_remaining_credits = (100% - 5h_peak%) × 5h_limit
   7d_remaining_credits = (100% - 7d_util%) × 7d_limit
   effective_headroom_credits = min(5h_remaining, 7d_remaining)

   If 5h_remaining <= 7d_remaining:
       true_waste_credits = 5h_remaining
       constrained_credits = 0
   Else:
       true_waste_credits = 7d_remaining
       constrained_credits = 5h_remaining - 7d_remaining
   ```
   **And** returns a HeadroomBreakdown struct with: usedPercent, constrainedPercent, wastePercent, usedCredits, constrainedCredits, wasteCredits

2. **Given** credit limits are unknown (tier not recognized, no user override)
   **When** analyzeResetEvent() is called
   **Then** it returns nil (analysis cannot be performed)
   **And** the analytics view shows: "Headroom breakdown unavailable -- unknown subscription tier"

3. **Given** multiple reset events in a time range
   **When** HeadroomAnalysisService.aggregateBreakdown() is called
   **Then** it sums used_credits, constrained_credits, and waste_credits across all events
   **And** returns aggregate percentages and totals

## Tasks / Subtasks

- [x] Task 1: Create HeadroomBreakdown model (AC: 1)
  - [x] 1.1 Create `cc-hdrm/Models/HeadroomBreakdown.swift` with `struct HeadroomBreakdown: Sendable, Equatable`
  - [x] 1.2 Properties: `usedPercent: Double`, `constrainedPercent: Double`, `wastePercent: Double`, `usedCredits: Double`, `constrainedCredits: Double`, `wasteCredits: Double`
  - [x] 1.3 Create `struct PeriodSummary: Sendable, Equatable` in the same file for aggregated multi-event results (add `resetCount: Int`, `avgPeakUtilization: Double`)

- [x] Task 2: Create HeadroomAnalysisServiceProtocol (AC: 1, 2, 3)
  - [x] 2.1 Create `cc-hdrm/Services/HeadroomAnalysisServiceProtocol.swift`
  - [x] 2.2 Method: `func analyzeResetEvent(fiveHourPeak: Double, sevenDayUtil: Double, creditLimits: CreditLimits) -> HeadroomBreakdown`
  - [x] 2.3 Method: `func aggregateBreakdown(events: [ResetEvent], creditLimits: CreditLimits) -> PeriodSummary`

- [x] Task 3: Implement HeadroomAnalysisService (AC: 1, 2, 3)
  - [x] 3.1 Create `cc-hdrm/Services/HeadroomAnalysisService.swift`
  - [x] 3.2 Implement `analyzeResetEvent()` using the exact math from AC-1 -- see Dev Notes for formula breakdown
  - [x] 3.3 Implement `aggregateBreakdown()` -- iterate events, call `analyzeResetEvent` per event using event's own tier/limits, sum credits, derive aggregate percentages from totals
  - [x] 3.4 Handle edge cases: `fiveHourPeak` or `sevenDayUtil` nil on ResetEvent -> skip that event in aggregation
  - [x] 3.5 Add `os.Logger` with category `"headroom"` -- log analysis results at `.debug`, log nil returns at `.info`

- [x] Task 4: Update HistoricalDataService to populate credit fields on reset events (AC: 1)
  - [x] 4.1 Add `HeadroomAnalysisServiceProtocol` dependency to `HistoricalDataService` (inject via init, optional -- graceful degradation if nil)
  - [x] 4.2 Add `PreferencesManagerProtocol` dependency to `HistoricalDataService` (inject via init, optional -- needed for `RateLimitTier.resolve()`)
  - [x] 4.3 In `recordResetEvent()` (line 461-528 of `cc-hdrm/Services/HistoricalDataService.swift`): replace the three `sqlite3_bind_null` calls (lines 517-520) with credit calculation logic
  - [x] 4.4 Logic: call `RateLimitTier.resolve(tierString: tier, preferencesManager: preferencesManager)` to get CreditLimits, then call `headroomAnalysisService.analyzeResetEvent()`, bind the three credit fields from the result (or NULL if limits unavailable)
  - [x] 4.5 Update `HistoricalDataServiceProtocol` if interface changes are needed (should not be -- internal method only)

- [x] Task 5: Wire HeadroomAnalysisService into AppDelegate (AC: all)
  - [x] 5.1 In `cc-hdrm/App/AppDelegate.swift`: create `HeadroomAnalysisService` instance
  - [x] 5.2 Pass it to `HistoricalDataService` init (add parameter)
  - [x] 5.3 Pass `preferencesManager` to `HistoricalDataService` init (add parameter)

- [x] Task 6: Update MockHistoricalDataService (AC: all)
  - [x] 6.1 Update `cc-hdrmTests/Mocks/MockHistoricalDataService.swift` if init signature changes

- [x] Task 7: Create MockHeadroomAnalysisService (AC: all)
  - [x] 7.1 Create `cc-hdrmTests/Mocks/MockHeadroomAnalysisService.swift` with configurable return values and call tracking

- [x] Task 8: Tests (AC: all)
  - [x] 8.1 Create `cc-hdrmTests/Services/HeadroomAnalysisServiceTests.swift`
  - [x] 8.2 Test: analyzeResetEvent with 5h_remaining <= 7d_remaining (true_waste = 5h_remaining, constrained = 0)
  - [x] 8.3 Test: analyzeResetEvent with 5h_remaining > 7d_remaining (true_waste = 7d_remaining, constrained = 5h_remaining - 7d_remaining)
  - [x] 8.4 Test: analyzeResetEvent percentages sum to 100%
  - [x] 8.5 Test: analyzeResetEvent with 0% peak (no usage = 100% waste)
  - [x] 8.6 Test: analyzeResetEvent with 100% peak (all used, 0 waste, 0 constrained)
  - [x] 8.7 Test: aggregateBreakdown sums credits across multiple events correctly
  - [x] 8.8 Test: aggregateBreakdown with zero events returns zeroed PeriodSummary
  - [x] 8.9 Test: aggregateBreakdown skips events with nil fiveHourPeak or sevenDayUtil
  - [x] 8.10 Test: HistoricalDataService.recordResetEvent now populates credit fields when tier is known
  - [x] 8.11 Test: HistoricalDataService.recordResetEvent leaves credit fields NULL when tier is unknown
  - [x] 8.12 Create `cc-hdrmTests/Models/HeadroomBreakdownTests.swift` -- test model struct init and equality

- [x] Task 9: Build verification (AC: all)
  - [x] 9.1 Run `xcodegen generate`
  - [x] 9.2 Run `xcodebuild -scheme cc-hdrm -destination 'platform=macOS' build`
  - [x] 9.3 Run full test suite -- all existing + new tests pass
  - [x] 9.4 Verify no regressions in existing reset event detection (Epic 10 tests still pass)

## Dev Notes

### Headroom Math -- Worked Example

For a Pro tier user (`5h_limit = 550,000`, `7d_limit = 5,000,000`) who hit 72% peak in 5h window while 7d was at 85%:

```
5h_remaining = (100% - 72%) × 550,000 = 154,000
7d_remaining = (100% - 85%) × 5,000,000 = 750,000

5h_remaining (154,000) <= 7d_remaining (750,000)
  -> true_waste = 154,000 (all unused 5h was genuinely available)
  -> constrained = 0 (7d was NOT the binding constraint)

used_credits = 72% × 550,000 = 396,000
used_percent = 72%
waste_percent = 28% (154,000 / 550,000)
constrained_percent = 0%
```

Now for a user who hit 50% peak in 5h window while 7d was at 98%:

```
5h_remaining = (100% - 50%) × 550,000 = 275,000
7d_remaining = (100% - 98%) × 5,000,000 = 100,000

5h_remaining (275,000) > 7d_remaining (100,000)
  -> true_waste = 100,000 (7d was the binding constraint)
  -> constrained = 275,000 - 100,000 = 175,000 (blocked by weekly limit, NOT waste!)

used_credits = 50% × 550,000 = 275,000
used_percent = 50%
waste_percent = 18.18% (100,000 / 550,000)
constrained_percent = 31.82% (175,000 / 550,000)
```

### Critical: Percentage Denominator

All percentages are relative to the **5h credit limit** (not 7d), because each reset event represents one 5h window cycle. The three percentages (used + constrained + waste) should sum to 100% of the 5h window capacity.

### Integration Point: HistoricalDataService.recordResetEvent()

The exact lines to modify are in `cc-hdrm/Services/HistoricalDataService.swift:517-520`:

```swift
// CURRENT (Epic 10 placeholder):
sqlite3_bind_null(statement, 5)  // used_credits
sqlite3_bind_null(statement, 6)  // constrained_credits
sqlite3_bind_null(statement, 7)  // waste_credits

// REPLACE WITH:
if let peak = fiveHourPeak,
   let util7d = sevenDayUtil,
   let limits = RateLimitTier.resolve(tierString: tier, preferencesManager: preferencesManager) {
    let breakdown = headroomAnalysisService.analyzeResetEvent(
        fiveHourPeak: peak,
        sevenDayUtil: util7d,
        creditLimits: limits
    )
    sqlite3_bind_double(statement, 5, breakdown.usedCredits)
    sqlite3_bind_double(statement, 6, breakdown.constrainedCredits)
    sqlite3_bind_double(statement, 7, breakdown.wasteCredits)
} else {
    sqlite3_bind_null(statement, 5)
    sqlite3_bind_null(statement, 6)
    sqlite3_bind_null(statement, 7)
}
```

### Existing Code to Reuse -- DO NOT Recreate

| Component | File | What It Provides |
|-----------|------|-----------------|
| `RateLimitTier` | `cc-hdrm/Models/RateLimitTier.swift` | Tier enum, credit limits, `resolve()` method |
| `CreditLimits` | `cc-hdrm/Models/RateLimitTier.swift` | Struct with `fiveHourCredits`, `sevenDayCredits`, `normalizationFactor` |
| `ResetEvent` | `cc-hdrm/Models/ResetEvent.swift` | Model with `usedCredits`, `constrainedCredits`, `wasteCredits` fields (currently NULL) |
| `HistoricalDataService` | `cc-hdrm/Services/HistoricalDataService.swift` | `recordResetEvent()` at line 461, `getResetEvents()` for querying |
| `HeadroomBreakdownBar` | `cc-hdrm/Views/HeadroomBreakdownBar.swift` | Typed stub -- DO NOT modify (Stories 14.3-14.5 will implement the visualization) |
| `AnalyticsView` | `cc-hdrm/Views/AnalyticsView.swift` | Already wires HeadroomBreakdownBar with `resetEvents` and `appState.creditLimits` |
| `PreferencesManager` | `cc-hdrm/Services/PreferencesManager.swift` | `customFiveHourCredits`, `customSevenDayCredits` for unknown tier fallback |
| `MockHistoricalDataService` | `cc-hdrmTests/Mocks/MockHistoricalDataService.swift` | Full mock -- update init if signature changes |

### What This Story Does NOT Touch

- **HeadroomBreakdownBar view** -- remains a stub (Story 14.3)
- **BreakdownSummaryStatistics view** -- not yet created (Story 14.4)
- **AnalyticsView integration of breakdown display** -- already wired, view stays as-is (Story 14.5)
- **AppState** -- no changes needed; `creditLimits` already flows from PollingEngine via `updateCreditLimits()`
- **Database schema** -- `reset_events` table already has `used_credits`, `constrained_credits`, `waste_credits` columns

### HistoricalDataService Init Signature Change

The `HistoricalDataService` currently takes only `databaseManager` in its init. This story adds two optional dependencies:

```swift
// CURRENT:
init(databaseManager: DatabaseManagerProtocol)

// NEW:
init(
    databaseManager: DatabaseManagerProtocol,
    headroomAnalysisService: (any HeadroomAnalysisServiceProtocol)? = nil,
    preferencesManager: (any PreferencesManagerProtocol)? = nil
)
```

Default nil preserves backward compatibility for all existing tests and callers. Store as private properties.

### AppDelegate Wiring (cc-hdrm/App/AppDelegate.swift)

In `applicationDidFinishLaunching`, after creating `preferencesManager` (line 66) and before creating `HistoricalDataService` (line 117):

```swift
let headroomAnalysisService = HeadroomAnalysisService()

let historicalDataService = HistoricalDataService(
    databaseManager: DatabaseManager.shared,
    headroomAnalysisService: headroomAnalysisService,
    preferencesManager: preferences
)
```

### Project Structure Notes

New files follow existing layer-based organization:

```
cc-hdrm/
  Models/
    HeadroomBreakdown.swift          # NEW - HeadroomBreakdown + PeriodSummary structs
  Services/
    HeadroomAnalysisServiceProtocol.swift  # NEW - protocol
    HeadroomAnalysisService.swift          # NEW - implementation

cc-hdrmTests/
  Models/
    HeadroomBreakdownTests.swift     # NEW
  Services/
    HeadroomAnalysisServiceTests.swift  # NEW
  Mocks/
    MockHeadroomAnalysisService.swift   # NEW
```

After creating files, run `xcodegen generate` to regenerate the Xcode project.

### References

- [Source: `cc-hdrm/Models/RateLimitTier.swift`] -- RateLimitTier enum, CreditLimits struct, resolve() method
- [Source: `cc-hdrm/Models/ResetEvent.swift`] -- ResetEvent model with credit fields
- [Source: `cc-hdrm/Services/HistoricalDataService.swift:461-528`] -- recordResetEvent() with NULL credit placeholders
- [Source: `cc-hdrm/Services/HistoricalDataService.swift:368-418`] -- detectAndRecordResetIfNeeded() call chain
- [Source: `cc-hdrm/Services/HistoricalDataServiceProtocol.swift`] -- protocol (no changes needed)
- [Source: `cc-hdrm/App/AppDelegate.swift:117-120`] -- HistoricalDataService creation point
- [Source: `cc-hdrm/Views/HeadroomBreakdownBar.swift`] -- Typed stub, DO NOT modify
- [Source: `cc-hdrm/Views/AnalyticsView.swift:84-87`] -- Already wires HeadroomBreakdownBar
- [Source: `_bmad-output/planning-artifacts/architecture.md:927-961`] -- HeadroomAnalysisService architecture spec
- [Source: `_bmad-output/planning-artifacts/epics.md:1649-1683`] -- Story 14.2 acceptance criteria

## Dev Agent Record

### Agent Model Used

claude-opus-4-6

### Debug Log References

- Initial build: BUILD SUCCEEDED (zero warnings)
- First test run: 7 floating point precision failures in HeadroomAnalysisServiceTests (exact equality vs tolerance)
- Fix: replaced `==` comparisons with `isClose()` tolerance-based helper (0.01 tolerance)
- Final test run: 805 tests passed, 0 failures, 73 suites

### Completion Notes List

- Created HeadroomBreakdown and PeriodSummary model structs with all specified properties
- Created HeadroomAnalysisServiceProtocol with analyzeResetEvent() and aggregateBreakdown() methods
- Implemented HeadroomAnalysisService with exact AC-1 math formulas; all percentages relative to 5h credit limit
- Updated HistoricalDataService init to accept optional headroomAnalysisService and preferencesManager (default nil preserves backward compat)
- Replaced NULL credit field bindings in recordResetEvent() with actual credit calculation via RateLimitTier.resolve() + HeadroomAnalysisService.analyzeResetEvent()
- Wired HeadroomAnalysisService into AppDelegate, passing it and preferencesManager to HistoricalDataService
- Task 6: MockHistoricalDataService required no changes -- default nil params preserve existing callers
- Created MockHeadroomAnalysisService with configurable return values and call tracking
- Comprehensive test coverage: 8 HeadroomAnalysisService tests, 6 HeadroomBreakdown model tests, 3 HistoricalDataService credit field integration tests
- All 805 tests pass with zero regressions; Epic 10 reset detection tests unaffected

### Senior Developer Review (AI)

**Reviewer:** Amelia (claude-opus-4-6) | **Date:** 2026-02-08

**Issues Found:** 1 High, 3 Medium, 2 Low | **All Fixed**

| ID | Severity | Description | Resolution |
|----|----------|-------------|------------|
| H1 | HIGH | `aggregateBreakdown()` used single `creditLimits` for all events; couldn't handle mixed-tier aggregation (contradicts Task 3.3 and architecture spec) | Removed `creditLimits` param; service now resolves per-event via `RateLimitTier.resolve(tierString: event.tier, ...)`. Added `preferencesManager` init dependency. Events with unresolvable tiers are skipped. |
| M1 | MEDIUM | `@unchecked Sendable` on `HeadroomAnalysisService` was unnecessary (pure computation, no mutable state) | After H1 fix added `preferencesManager` stored property, `@unchecked Sendable` is now justified (`PreferencesManagerProtocol` not Sendable, but property is `let`). No change needed. |
| M2 | MEDIUM | Architecture spec defines credit fields as `Int`; implementation uses `Double` | Intentional deviation: Double avoids rounding errors in intermediate calculations. Documented here. |
| M3 | MEDIUM | Protocol signature deviates from architecture: param names changed, `RateLimitTier` replaced with `CreditLimits`, `getCreditLimits()` dropped | Intentional refinements: `CreditLimits` decouples from enum (supports custom tiers), `getCreditLimits()` absorbed into `RateLimitTier.resolve()`. Documented here. |
| L1 | LOW | `HeadroomBreakdownTests` Sendable conformance tests were no-ops (compiler enforces at build time) | Removed 2 no-op tests. |
| L2 | LOW | `MockHeadroomAnalysisService` fell through to real implementation when unconfigured | Mock now `fatalError`s when called without setting `mockBreakdown`/`mockPeriodSummary`. |

**Post-fix verification:** 804 tests passed, 0 failures, 73 suites. BUILD SUCCEEDED.

### File List

| Action | File |
|--------|------|
| NEW | `cc-hdrm/Models/HeadroomBreakdown.swift` |
| NEW | `cc-hdrm/Services/HeadroomAnalysisServiceProtocol.swift` |
| NEW | `cc-hdrm/Services/HeadroomAnalysisService.swift` |
| MODIFIED | `cc-hdrm/Services/HistoricalDataService.swift` |
| MODIFIED | `cc-hdrm/App/AppDelegate.swift` |
| NEW | `cc-hdrmTests/Mocks/MockHeadroomAnalysisService.swift` |
| NEW | `cc-hdrmTests/Models/HeadroomBreakdownTests.swift` |
| NEW | `cc-hdrmTests/Services/HeadroomAnalysisServiceTests.swift` |
| MODIFIED | `cc-hdrmTests/Services/HistoricalDataServiceTests.swift` |
