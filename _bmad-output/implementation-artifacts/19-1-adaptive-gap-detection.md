# Story 19.1: Adaptive Gap Detection

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want gap detection in charts and sparkline to adapt to the actual data timestamps,
so that changing the polling interval doesn't cause all historical data to appear as missing.

## Acceptance Criteria

1. **Given** historical data collected at any supported interval **When** the user changes the polling interval to any other supported value **Then** the sparkline and 24h chart render all historical data as continuous segments (not gaps).

2. **Given** historical data contains a mix of intervals (e.g., 12h at 30s then 12h at 600s) **When** the chart renders **Then** both segments display as continuous data with no false gaps.

3. **Given** the app was genuinely offline for longer than the gap threshold **When** the chart renders after any interval change **Then** the offline period still renders as a gap with grey background.

4. **Given** the `pollInterval` parameter is removed from gap threshold calculation **When** the sparkline, StepAreaChartView, and their callers are reviewed **Then** no code path passes the current polling interval to gap detection logic.

5. **Given** all existing gap-related tests pass **When** new adaptive threshold tests are added **Then** the full test suite passes with no regressions.

6. **Given** the gap threshold is a fixed constant derived from the max supported poll interval **When** the threshold is reviewed **Then** it equals `max(sparklineGapThresholdMs, maxSupportedIntervalSeconds * 1000 * 2)` and `maxSupportedIntervalSeconds` matches the longest option in the poll interval picker.

7. **Given** BarChartView uses period-based gap detection (missing hours/days) **When** the fix is applied **Then** BarChartView is NOT modified (it is unaffected by this bug).

## Tasks / Subtasks

- [x] Task 1: Replace dynamic gap threshold with fixed constant (AC: 4, 6)
  - [x] 1.1 In `cc-hdrm/Views/Sparkline.swift`: define `private static let maxSupportedPollInterval: Double = 1800` with a comment referencing `SettingsView.pollIntervalOptions.last` as its source. Replace `gapThresholdMs(pollInterval:)` with `static let gapThresholdMs: Int64 = max(sparklineGapThresholdMs, Int64(maxSupportedPollInterval * 1000 * 2))` = 3,600,000 ms (60 min). If the value drifts from `SettingsView.pollIntervalOptions.last`, a future reviewer can catch it via the comment
  - [x] 1.2 Remove the `pollInterval` parameter from `SparklinePathBuilder.gapThresholdMs(pollInterval:)` — make it a static constant or a no-arg computed property
  - [x] 1.3 Update `buildSegments(from:size:gapThresholdMs:)` call in `Sparkline.chartView` (line 368-369) to use the new constant instead of the computed value

- [x] Task 2: Remove `pollInterval` from Sparkline view (AC: 4)
  - [x] 2.1 Remove `let pollInterval: TimeInterval` property from `Sparkline` struct (line 327)
  - [x] 2.2 In `cc-hdrm/Views/PopoverView.swift` (line 141): remove `pollInterval: preferencesManager.pollInterval` from `Sparkline(...)` initializer
  - [x] 2.3 Check for any `#Preview` or `PreviewProvider` that passes `pollInterval` to `Sparkline` — update or remove the argument

- [x] Task 3: Remove `pollInterval` from StepAreaChartView (AC: 4)
  - [x] 3.1 In `cc-hdrm/Views/StepAreaChartView.swift`: remove `pollInterval` parameter from `makeChartPoints(from:pollInterval:)` (line 316)
  - [x] 3.2 Update `makeChartPoints` to use the new fixed constant from `SparklinePathBuilder` instead of `gapThresholdMs(pollInterval:)` (line 320)
  - [x] 3.3 Remove `pollInterval` from `StepAreaChartView.init(...)` (line 154) and its usage at line 158

- [x] Task 4: Remove `pollInterval` from UsageChart and AnalyticsView (AC: 4)
  - [x] 4.1 In `cc-hdrm/Views/UsageChart.swift`: remove `var pollInterval: TimeInterval = 30` property (line 21) and its forwarding at line 59
  - [x] 4.2 In `cc-hdrm/Views/AnalyticsView.swift`: remove `pollInterval: preferencesManager?.pollInterval ?? 30` from `UsageChart(...)` call (line 95)

- [x] Task 5: Update tests (AC: 5)
  - [x] 5.1 Rewrite 3 tests that call `gapThresholdMs(pollInterval:)` to use the new constant: `gapThresholdUsesMinimum()` (SparklineTests:12-24), `gapThresholdFallsBackForLongIntervals()` (SparklineTests:26-33), `continuousPollingWithJitterProducesOneSegment()` (SparklineTests:474-497)
  - [x] 5.2 Remove `pollInterval` argument from all `Sparkline(...)` constructor calls in `cc-hdrmTests/Views/SparklineTests.swift` (~10 tests: `rendersWithValidData`, `rendersPlaceholderWithEmptyData`, `rendersPlaceholderWithSinglePoint`, `acceptsOnTapCallback`, `acceptsIsAnalyticsOpen`, `suppressesPowerNapSpikes`, `handlesDataWithGaps`, `handlesDataWithResets`, `handlesMixedValidInvalidData`, `accessibilityLabel`)
  - [x] 5.3 Verify `UsageChartTests.gapSegmentation()` (line 504) assertions still hold with the new 60-min threshold — the test data may have been calibrated to the old default-30s threshold
  - [x] 5.4 Add test: data with 30s spacing is NOT treated as gaps (threshold = 60 min >> 30s)
  - [x] 5.5 Add test: data with 1800s spacing is NOT treated as gaps (threshold = 60 min > 30 min)
  - [x] 5.6 Add test: data with 90-minute gap IS treated as a gap (90 min > 60 min threshold)
  - [x] 5.7 Add test: mixed-interval data — create 100 points at 30s spacing followed by 10 points at 600s spacing. Assert `makeChartPoints` assigns all points to the same segment (zero gap transitions)
  - [x] 5.8 Add test: boundary condition — delta exactly equal to `gapThresholdMs` is NOT treated as a gap (strict `>` comparison)
  - [x] 5.9 Run full test suite — all existing + new tests pass

- [x] Task 6: Build verification (AC: all)
  - [x] 6.1 Run `xcodegen generate`
  - [x] 6.2 Run `xcodebuild -scheme cc-hdrm -destination 'platform=macOS' build`
  - [x] 6.3 Grep `cc-hdrm/Views/` (excluding SettingsView.swift and GearMenuView.swift) for any remaining `pollInterval` references — confirm none exist in gap detection paths (AC 4)

## Dev Notes

### Root Cause

`SparklinePathBuilder.gapThresholdMs(pollInterval:)` at `cc-hdrm/Views/Sparkline.swift:314-316` computes gap threshold as `max(sparklineGapThresholdMs, pollInterval * 1000 * 1.5)`. All call sites pass the **current** `preferencesManager.pollInterval`, but historical data was collected at a **different** interval. When the user decreases the interval (e.g., 600s → 30s), the threshold drops from 15 min to 5 min, and all old 600s-spaced data is classified as gaps.

### Fix Approach: Fixed Generous Threshold

Replace the dynamic `pollInterval`-dependent threshold with a fixed constant:

```swift
// Before (dynamic — breaks on interval change):
static func gapThresholdMs(pollInterval: TimeInterval) -> Int64 {
    max(sparklineGapThresholdMs, Int64(pollInterval * 1000 * 1.5))
}

// After (fixed — works for all intervals):
static let gapThresholdMs: Int64 = max(
    sparklineGapThresholdMs,
    Int64(maxSupportedPollInterval * 1000 * 2)
)
private static let maxSupportedPollInterval: Double = 1800 // seconds (30 min)
```

**Why fixed instead of adaptive?** Five-method elicitation analysis concluded:
- Global statistics (median, P95) fail for mixed-interval data because the shorter interval dominates by count
- Local/neighbor approaches add complexity and still produce false gaps at interval transitions
- A fixed threshold derived from the max supported interval (1800s from `SettingsView.pollIntervalOptions`) is simple, deterministic, and correct for all cases

**Threshold value:** `max(300_000, 1800 * 1000 * 2)` = **3,600,000 ms (60 minutes)**

**Tradeoff:** Users with short poll intervals (30s) lose detection of genuine outages shorter than 60 minutes. Previously, 5+ minute outages were detected. This is acceptable because:
- Brief outages (5-60 min) are minor visual noise in a 24h sparkline
- The user's primary complaint — ALL data appearing as missing — is fully resolved
- Genuine extended outages (60+ min) are still rendered as gaps

### Why Not Adaptive/Statistical Approaches

| Approach | Problem |
|----------|---------|
| Median of all deltas | Dominated by most-frequent interval; 2400 polls at 30s swamp 24 at 600s |
| P95/P99 of deltas | Same count-domination problem at boundary |
| Per-pair sliding window | Complex, edge cases at data boundaries, 1-5 false gaps at interval transitions |
| Store interval per-poll in DB | Existing data has no interval info; unnecessary complexity |

### Files to Modify (complete list)

```
cc-hdrm/Views/Sparkline.swift              # Replace gapThresholdMs(pollInterval:) with constant; remove pollInterval property
cc-hdrm/Views/StepAreaChartView.swift      # Remove pollInterval from init and makeChartPoints
cc-hdrm/Views/UsageChart.swift             # Remove pollInterval property and forwarding
cc-hdrm/Views/AnalyticsView.swift          # Remove pollInterval from UsageChart call
cc-hdrm/Views/PopoverView.swift            # Remove pollInterval from Sparkline call
cc-hdrmTests/                              # Update existing gap tests; add new threshold tests
```

### Files NOT Modified (confirm in review)

```
cc-hdrm/Views/BarChartView.swift           # Period-based gap detection — unaffected (AC 7)
cc-hdrm/Services/DatabaseManager.swift     # No schema changes needed
cc-hdrm/Services/HistoricalDataService.swift # Query logic unchanged
cc-hdrm/Services/PollingEngine.swift       # Polling behavior unchanged
```

### Call Sites to Update (complete chain)

| File | Line | Current Code | Change |
|------|------|-------------|--------|
| `Sparkline.swift` | 314-316 | `static func gapThresholdMs(pollInterval:) -> Int64` | Replace with `static let gapThresholdMs: Int64` |
| `Sparkline.swift` | 327 | `let pollInterval: TimeInterval` | Remove property |
| `Sparkline.swift` | 368 | `SparklinePathBuilder.gapThresholdMs(pollInterval: pollInterval)` | `SparklinePathBuilder.gapThresholdMs` |
| `StepAreaChartView.swift` | 154 | `pollInterval: TimeInterval = 30` in init | Remove parameter |
| `StepAreaChartView.swift` | 158 | `makeChartPoints(from: polls, pollInterval: pollInterval)` | `makeChartPoints(from: polls)` |
| `StepAreaChartView.swift` | 316 | `makeChartPoints(from:pollInterval:)` | `makeChartPoints(from:)` |
| `StepAreaChartView.swift` | 320 | `gapThresholdMs(pollInterval: pollInterval)` | `SparklinePathBuilder.gapThresholdMs` |
| `UsageChart.swift` | 21 | `var pollInterval: TimeInterval = 30` | Remove property |
| `UsageChart.swift` | 59 | `pollInterval: pollInterval` | Remove argument |
| `AnalyticsView.swift` | 95 | `pollInterval: preferencesManager?.pollInterval ?? 30` | Remove argument |
| `PopoverView.swift` | 141 | `pollInterval: preferencesManager.pollInterval` | Remove argument |

### Edge Cases

| Condition | Expected Behavior |
|-----------|-------------------|
| All data at same interval (any supported value) | Continuous segments, no false gaps |
| Mixed intervals (30s + 600s + 1800s) | All data renders as continuous, no false gaps |
| Genuine 90-minute outage | Rendered as gap (90 min > 60 min threshold) |
| Genuine 45-minute outage | NOT rendered as gap (45 min < 60 min threshold) — acceptable tradeoff |
| Only 1-2 data points | Handled by existing `data.count < 2` guard in Sparkline (shows placeholder) |
| Interval changed while chart is visible | Chart re-renders; data remains continuous (no `pollInterval` dependency) |

### Project Structure Notes

- No new files. All changes are modifications to existing files.
- No schema changes. No database migration needed.
- Run `xcodegen generate` after changes.

### Previous Story Intelligence

**From Story 13.7 (gap rendering in charts):**
- `SparklinePathBuilder` defines `sparklineGapThresholdMs = 5 * 60 * 1000` (5 min) — this stays as the floor constant
- StepAreaChartView uses `findGapRanges()` (line 57-76) which depends on `makeChartPoints()` segment assignments — changing the threshold affects these
- BarChartView uses **period-based** gap detection (missing hours/days) — completely separate, unaffected
- Gap backgrounds use `RectangleMark` with `Color.secondary.opacity(0.08)` — rendering logic unchanged

**From Story 2.5 (poll interval hot reload):**
- `restartPolling()` cancels in-flight sleep and restarts with new interval
- The `onPollIntervalChange` callback threads through AppDelegate → PopoverView → GearMenuView → SettingsView
- This callback triggers chart re-renders (via AppState observation), which is when the bug manifests

**From Story 12.2 (sparkline component):**
- `mergeShortSegments()` absorbs isolated segments shorter than `minimumSegmentDurationMs` into gaps — this operates downstream of gap detection and needs no changes
- `buildSegments()` receives `gapThresholdMs` as a parameter — changing the value is sufficient, no structural change needed

### References

- [Source: cc-hdrm/Views/Sparkline.swift:307] — `sparklineGapThresholdMs` constant (5 min floor)
- [Source: cc-hdrm/Views/Sparkline.swift:314-316] — `gapThresholdMs(pollInterval:)` — the function to replace
- [Source: cc-hdrm/Views/Sparkline.swift:327] — `pollInterval` property on Sparkline struct
- [Source: cc-hdrm/Views/Sparkline.swift:368-369] — gap threshold usage in chartView
- [Source: cc-hdrm/Views/Sparkline.swift:77] — gap detection in `buildSegments`
- [Source: cc-hdrm/Views/StepAreaChartView.swift:154] — pollInterval in init
- [Source: cc-hdrm/Views/StepAreaChartView.swift:316-320] — makeChartPoints with pollInterval
- [Source: cc-hdrm/Views/StepAreaChartView.swift:326] — timeDelta > gapThreshold comparison
- [Source: cc-hdrm/Views/UsageChart.swift:21,59] — pollInterval property and forwarding
- [Source: cc-hdrm/Views/AnalyticsView.swift:95] — pollInterval passed to UsageChart
- [Source: cc-hdrm/Views/PopoverView.swift:141] — pollInterval passed to Sparkline
- [Source: cc-hdrm/Views/SettingsView.swift:38] — `pollIntervalOptions: [10, 15, 30, 60, 120, 300, 600, 900, 1800]`
- [Source: _bmad-output/implementation-artifacts/13-7-gap-rendering-in-charts.md] — Gap rendering story with BarChartView period-based detection
- [Source: _bmad-output/implementation-artifacts/2-5-poll-interval-hot-reload.md] — Poll interval hot reload story

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Build: `xcodebuild -scheme cc-hdrm -destination 'platform=macOS' build` — BUILD SUCCEEDED
- Tests: 408 tests in 28 suites passed (after code review fixes). `TEST FAILED` status is from pre-existing code signing issue in test runner wrapper, not test assertion failures.

### Completion Notes List

- Replaced dynamic `gapThresholdMs(pollInterval:)` function with fixed `gapThresholdMs` static constant = 3,600,000 ms (60 min)
- Removed `pollInterval` parameter from entire gap detection chain: Sparkline → StepAreaChartView → UsageChart → AnalyticsView → PopoverView
- Updated 4 preview macros to remove `pollInterval` argument
- Rewrote 3 existing threshold tests, updated 2 existing gap tests (calibrated to 60-min threshold), removed `pollInterval` from ~10 Sparkline constructor calls in tests
- Added 5 new tests: short-interval (30s), long-interval (1800s), genuine outage (90min), mixed-interval (30s+600s), boundary condition (exact threshold)
- BarChartView confirmed unmodified (period-based gap detection, unaffected by this bug)
- Grep confirmed: no `pollInterval` references remain in gap detection code paths (only in SettingsView UI and a documentation comment)

### File List

**Modified:**
- `cc-hdrm/Views/Sparkline.swift` — replaced `gapThresholdMs(pollInterval:)` with fixed constant; removed `pollInterval` property; updated chartView call site; updated 4 preview macros
- `cc-hdrm/Views/StepAreaChartView.swift` — removed `pollInterval` from `init()` and `makeChartPoints()`
- `cc-hdrm/Views/UsageChart.swift` — removed `pollInterval` property and forwarding
- `cc-hdrm/Views/AnalyticsView.swift` — removed `pollInterval` from `UsageChart(...)` call
- `cc-hdrm/Views/PopoverView.swift` — removed `pollInterval` from `Sparkline(...)` call
- `cc-hdrmTests/Views/SparklineTests.swift` — rewrote threshold tests, removed `pollInterval` from constructors, added 5 new adaptive gap tests
- `cc-hdrmTests/Views/UsageChartTests.swift` — updated `gapSegmentation()` and 2 gap overlay tests to use 90-min gaps (exceeds new 60-min threshold)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — story status updated

## Change Log

- 2026-03-14: Implemented adaptive gap detection (Story 19.1) — replaced dynamic pollInterval-based gap threshold with fixed 60-minute constant derived from max supported poll interval
- 2026-03-15: Code review fixes — (M1) exposed `maxSupportedPollInterval` as internal, replaced redundant floor test with settings-coupling guard test; (L1) renamed misleading `handlesDataWithGaps` test; (L2) added `makeChartPoints` boundary test in UsageChartTests; (L3) removed trivially redundant `gapThresholdAtLeastFloor` test
