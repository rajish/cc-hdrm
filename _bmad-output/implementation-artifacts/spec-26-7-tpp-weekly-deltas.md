---
title: 'Story 26.7: Tokens-per-Percent on Weekly Deltas'
type: 'feature'
created: '2026-10-31'
status: 'done'
baseline_commit: 'd27bdfead334aca701950b14b07fcc8354754386'
review_loop_iteration: 0
context: ['{project-root}/_bmad-output/implementation-artifacts/epic-26-context.md']
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Since 2026-10-31 the usage API returns `five_hour: null`. The passive tokens-per-percent (TPP) engine and the historical backfill gate on 5h utilization, so they record nothing; the TPP chart reads `tppFiveHour` only, so it is empty for new data.

**Approach:** Drive passive measurement, backfill and charts from `seven_day` deltas, storing `tpp_seven_day`. Retune the accumulation cap and confidence threshold for 1% weekly steps. Charts prefer the weekly value; older rows that only have a 5h value stay visible, flagged and labelled "5h-based", and are never averaged with weekly values.

## Boundaries & Constraints

**Always:** weekly (`sevenDayUtil`) is the only trigger window; new records leave `five_hour_*` and `tpp_five_hour` NULL. 5h-based and weekly-based values are never mixed in one average, trend line or shift run. Existing 5h-based rows stay in the database.

**Ask First:** any schema migration; any `DELETE` that could remove 5h-based rows.

**Never:** touch `BenchmarkService` / `BenchmarkSectionView` (Story 26.8), `AppState`, `AppDelegate`, `GaugeIcon` (26.1), `HeadroomAnalysisService` / `HistoricalDataService` (26.5), `PollingEngine` (26.2), or `cc-hdrm/cc_hdrm.entitlements`. No DB migration.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Weekly-only step | prev 7d=28, curr 7d=29, 5h nil, tokens present | one passive row per model, `tppSevenDay = effective/1`, 5h fields nil | N/A |
| Accumulate then flush | tokens, no 7d change over several polls, then +1% | one row with merged tokens, delta from window start | N/A |
| Cap exceeded | window older than 6h, still no delta | window restarts at previous poll | log info |
| Weekly reset | curr 7d < prev 7d | window discarded, nothing stored | log info |
| Missing 7d | either poll lacks `sevenDayUtil` | skipped | log debug |
| Delta, no tokens | +1% 7d, zero tokens | delta-only row, model `unknown`, `tppSevenDay` nil | N/A |
| Confidence | single model, 7d delta ≥ 2 | `.medium`; else / multi-model `.low` | N/A |
| Old row in chart | `tppFiveHour` set, `tppSevenDay` nil | point shown, `isFiveHourBased = true` | N/A |

</frozen-after-approval>

## Code Map

- `cc-hdrm/Services/PassiveTPPEngine.swift` -- `processPoll` 5h guard (L46-50), 50% reset (L53), 30-min cap (L29), `minDelta`/`mediumConfidenceDelta` (L32,38), monotonic guard (L192), `AccumulationWindow.startFiveHourUtil`, store helpers (L276-381).
- `cc-hdrm/Services/HistoricalTPPBackfillService.swift` -- raw-poll loop 5h guard (L150-168), rollup loop `fiveHourPeak/Min` (L282); `UsageRollup.sevenDayPeak/sevenDayMin` exist.
- `cc-hdrm/Services/TPPChartDataService.swift` -- `toChartPoint` (L120), `computeAverages` (L149), trend + shifts (L66-70), insight (L286), weighting (L348) all read `tppFiveHour`.
- `cc-hdrm/Models/TPPChartData.swift` -- `TPPChartPoint`; add `var isFiveHourBased = false` (keeps memberwise init source-compatible).
- `cc-hdrm/Views/TPPTrendChartView.swift` -- marks, tooltip; label 5h-based points.
- `cc-hdrm/Services/TPPStorageService.swift` -- `deleteBackfillRecords` (L209) deletes all backfill rows on "Re-run TPP Backfill" (`cc-hdrm/Views/SettingsView.swift:349`); new backfill no longer recreates 5h rows.
- `cc-hdrm/Services/PollingEngine.swift:331-339` -- read-only: already passes `sevenDayUtil` to the engine.
- Tests: `cc-hdrmTests/Services/PassiveTPPEngineTests.swift`, `HistoricalTPPBackfillServiceTests.swift`, `TPPChartDataServiceTests.swift`, `TPPStorageServiceTests.swift`.

## Tasks & Acceptance

**Execution:**
- [x] `cc-hdrm/Services/PassiveTPPEngine.swift` -- gate, delta, window start and stored values on 7d; any 7d decrease = reset (replaces 50% drop and monotonic guard); cap 6h; medium at ≥ 2.0; 5h fields nil -- weekly-only polls must produce rows.
- [x] `cc-hdrm/Services/HistoricalTPPBackfillService.swift` -- raw polls on 7d deltas; rollups on `sevenDayPeak − sevenDayMin`; same thresholds -- backfill must work on weekly-only history.
- [x] `cc-hdrm/Models/TPPChartData.swift` -- add `isFiveHourBased` to `TPPChartPoint`.
- [x] `cc-hdrm/Services/TPPChartDataService.swift` -- value = `tppSevenDay ?? tppFiveHour` with flag; bucket averages, trend and shifts per basis; insight and weighting compare same-basis values, weekly preferred.
- [x] `cc-hdrm/Views/TPPTrendChartView.swift` -- 5h-based points as triangles, separate dashed trend series, tooltip "(5h-based)", caption when any shown.
- [x] `cc-hdrm/Services/TPPStorageService.swift` (+ protocol doc) -- force re-run deletes only backfill rows with `five_hour_delta IS NULL`.
- [x] Tests for every I/O matrix row, per-basis chart averaging, and the delete predicate; update 5h-based tests to weekly.

**Acceptance Criteria:**
- Given polls with `fiveHourUtil = nil` and a 1% weekly rise with Claude Code tokens, when the passive engine processes them, then a measurement with non-nil `tppSevenDay` is stored.
- Given a range holding old 5h-only rows and new weekly rows, when chart data loads, then both appear, 5h ones flagged, and no average/trend point mixes them.
- Given old 5h-based backfill rows, when the user re-runs backfill, then those rows remain.

## Spec Change Log

## Design Notes

- `minDelta` stays 1.0: it is the smallest observable weekly step. Medium confidence drops from 3.0 to 2.0: a 2% weekly step carries ~5–9× the token volume of the old 3% 5h step (2% weekly ≈ 16–26% of 5h) and halves quantization error versus one step.
- 6h cap ≈ 30 min × the 8–13× token ratio (4–6.5h); 6h is a tuning knob, not a derived limit.
- A row is 5h-based iff `five_hour_delta` is set (5h-era engine); the chart and the re-run delete predicate share this rule.
- Backfill accumulates tokens from the last weekly step, like the live engine; poll-to-poll pairing undercounts by the number of flat polls per step.
- Weekly utilization only falls at a reset, so any drop discards the window.

## Verification

**Commands:**
- `xcodegen generate && xcodebuild -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test` -- expected: all tests pass.

## Suggested Review Order

**Passive engine on weekly deltas**

- Entry point: weekly-only gate; 5h no longer required.
  [`PassiveTPPEngine.swift:42`](../../cc-hdrm/Services/PassiveTPPEngine.swift#L42)

- Any weekly drop is a reset; replaces 50% drop and monotonic guard.
  [`PassiveTPPEngine.swift:51`](../../cc-hdrm/Services/PassiveTPPEngine.swift#L51)

- Retuned knobs: 6h accumulation cap, medium confidence at 2% weekly.
  [`PassiveTPPEngine.swift:29`](../../cc-hdrm/Services/PassiveTPPEngine.swift#L29)

**Backfill on weekly deltas**

- Window from last weekly step so each 1% step gets all its tokens.
  [`HistoricalTPPBackfillService.swift:148`](../../cc-hdrm/Services/HistoricalTPPBackfillService.swift#L148)

- Rollups use weekly peak minus min.
  [`HistoricalTPPBackfillService.swift:282`](../../cc-hdrm/Services/HistoricalTPPBackfillService.swift#L282)

**Chart: weekly first, 5h-based kept apart**

- One rule for basis: `fiveHourDelta` set means 5h-era row.
  [`TPPChartDataService.swift:120`](../../cc-hdrm/Services/TPPChartDataService.swift#L120)

- Averages bucket per basis; never mix 5h and weekly values.
  [`TPPChartDataService.swift:164`](../../cc-hdrm/Services/TPPChartDataService.swift#L164)

- Shifts detected per basis; weekly shifts win the top-3 cap.
  [`TPPChartDataService.swift:233`](../../cc-hdrm/Services/TPPChartDataService.swift#L233)

- Weighting ratios only between same-basis benchmark values.
  [`TPPChartDataService.swift:422`](../../cc-hdrm/Services/TPPChartDataService.swift#L422)

- Triangles, dashed trend and caption label old 5h-based readings.
  [`TPPTrendChartView.swift:77`](../../cc-hdrm/Views/TPPTrendChartView.swift#L77)

**No loss of old 5h rows**

- Re-run backfill deletes only weekly-basis backfill rows.
  [`TPPStorageService.swift:219`](../../cc-hdrm/Services/TPPStorageService.swift#L219)

**Peripherals**

- Flag on chart points; defaults to weekly.
  [`TPPChartData.swift:19`](../../cc-hdrm/Models/TPPChartData.swift#L19)

- Engine I/O matrix tests.
  [`PassiveTPPEngineTests.swift:103`](../../cc-hdrmTests/Services/PassiveTPPEngineTests.swift#L103)

- Backfill accumulation test across flat polls.
  [`HistoricalTPPBackfillServiceTests.swift:565`](../../cc-hdrmTests/Services/HistoricalTPPBackfillServiceTests.swift#L565)

- Chart same-basis insight tests.
  [`TPPChartDataServiceTests.swift:437`](../../cc-hdrmTests/Services/TPPChartDataServiceTests.swift#L437)
