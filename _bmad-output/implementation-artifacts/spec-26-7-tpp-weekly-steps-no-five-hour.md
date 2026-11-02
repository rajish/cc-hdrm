---
title: 'Tokens-per-Percent From Weekly Steps When There Is No 5-Hour Number (Story 26.7)'
type: 'feature'
created: '2026-11-02'
status: 'done'
baseline_commit: 'ef35c2cbcf298bab76d515dfc0ca45f186115231'
review_loop_iteration: 1
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-26-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Accounts with no 5-hour number record no new tokens-per-percent (TPP) measurements, because the passive engine and the backfill both gate on the 5-hour value. The chart reads only the 5-hour value, so it would stay empty for those accounts.

**Approach:** Choose the measurement per poll. Polls with a number keep the 1.6.0 code path untouched. Polls without one measure weekly steps with a 6-hour window. The chart shows one basis at a time. Its points, trend, shifts, averages and insight are computed from that basis alone.

## Boundaries & Constraints

**Always:**
- A row's basis comes from the row: `five_hour_delta` set means 5-hour, unset means weekly. 1.6.0 never wrote a row without it, so old rows classify correctly with no migration.
- Weekly rows leave every `five_hour_*` column and `tpp_five_hour` NULL.
- A weekly TPP value exists only for a window that starts at an observed weekly step. A partial window never becomes a number.
- A single 1% step is low confidence.

**Ask First:** a change to the credit table, a schema migration.

**Never:** a `DELETE` wider than today's, a rewrite of old rows, a change to `cc-hdrm/cc_hdrm.entitlements`, a change to benchmark measurement (Story 26.8).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Number present | Both polls have a 5-hour number | Rows identical to 1.6.0 | N/A |
| Weekly step, anchored | Earlier step seen, 7d 29→30, tokens | One row per model, `tppSevenDay = effective / delta`, 5-hour fields nil | N/A |
| First step | No earlier step seen, 7d 28→29, tokens | No row; this step becomes the anchor | Log info |
| Step, no tokens | 7d +1, no tokens | Delta-only row, model `unknown`, TPP nil | N/A |
| Over the cap | Window older than 6 hours, with or without a step | Window dropped, no row from it; next step only anchors | Log info |
| Weekly reset | 7d falls, or `resets_at` moves forward 6 days or more | Window dropped, no row, next step only anchors. A smaller move with no fall is drift, as in `cc-hdrm/Services/HistoricalDataService.swift:532`, and changes nothing | Log info |
| State change | One poll of the pair has a number, the other does not | No row from that pair; both windows dropped | Log info |
| Missing weekly | Either poll has no 7d value | No row; window dropped | Log debug |
| Confidence | Single model, delta 3 or more | Medium; otherwise low | N/A |
| Both bases in range | 5-hour and weekly rows | Picker shows one basis; default is the newest passive row's basis | N/A |
| 5-hour rows only | Accounts with a number | No picker, no caption, axis stays `tokens/%` | N/A |
| Force re-run, 5-hour rows | Rows older than the rebuild can recreate | Those rows stay | Log info |
| Force re-run, weekly rows | Any weekly row | Never deleted; the rebuild adds only rows that do not overlap one | Log debug |
| Rollup with no number | Bucket has no 5-hour peak | No row, as in 1.6.0 | N/A |

</frozen-after-approval>

## Code Map

- `cc-hdrm/Services/WeeklyStepTracker.swift` -- new. The weekly state machine, shared by engine and backfill so the two cannot drift.
- `cc-hdrm/Services/PassiveTPPEngine.swift` -- `processPoll` dispatches on `current.fiveHourUtil`; the rest of the method stays as 1.6.0.
- `cc-hdrm/Services/HistoricalTPPBackfillService.swift` -- the raw loop keeps the 5-hour branch and feeds other pairs to the tracker. `processRollups` is unchanged. Adds the post-upgrade weekly pass, overlap skip and scoped force delete.
- `cc-hdrm/Services/TPPStorageService.swift` -- `deleteBackfillRecords(passiveFrom:rollupFrom:)`; `getAverageTPP` returns one average per basis.
- `cc-hdrm/Services/TPPChartDataService.swift`, `cc-hdrm/Services/TPPChartDataServiceProtocol.swift` -- `loadTPPData(timeRange:model:basis:)` filters to one basis before any averaging.
- `cc-hdrm/Models/TPPMeasurement.swift` -- `TPPBasis`, `basis`, `chartTPP`.
- `cc-hdrm/Models/TPPChartData.swift` -- `basis`, `availableBases`, `yAxisLabel`, `basisCaption`.
- `cc-hdrm/Views/TPPSectionView.swift`, `cc-hdrm/Views/TPPTrendChartView.swift` -- basis picker, caption, axis label.
- `cc-hdrm/Services/PollingEngine.swift:336-343` -- passes the weekly `resets_at` into the engine's current poll.
- `cc-hdrm/Services/PreferencesManager.swift`, `cc-hdrm/Services/PreferencesManagerProtocol.swift`, `cc-hdrmTests/Mocks/MockPreferencesManager.swift` -- `tppWeeklyBackfillCompleted`.

## Tasks & Acceptance

**Execution:**
- [x] `cc-hdrm/Models/TPPMeasurement.swift` -- add basis and chart value -- one rule for every reader.
- [x] `cc-hdrm/Services/WeeklyStepTracker.swift` -- steps, anchor, 6-hour cap, reset and state-change handling.
- [x] `cc-hdrm/Services/PassiveTPPEngine.swift` -- dispatch per poll, keep the 5-hour code.
- [x] `cc-hdrm/Services/PollingEngine.swift` -- pass `sevenDayResetsAt` so a reset followed by a rise is caught.
- [x] `cc-hdrm/Services/HistoricalTPPBackfillService.swift` -- same rule per poll; weekly pass after upgrade; skip overlap with weekly rows already stored.
- [x] `cc-hdrm/Services/TPPStorageService.swift`, `cc-hdrm/Services/TPPStorageServiceProtocol.swift` -- delete only what the rebuild can recreate; per-basis averages.
- [x] `cc-hdrm/Services/TPPChartDataService.swift`, `cc-hdrm/Models/TPPChartData.swift`, `cc-hdrm/Views/TPPSectionView.swift`, `cc-hdrm/Views/TPPTrendChartView.swift` -- one basis at a time, labelled.
- [x] `cc-hdrmTests/Services/PassiveTPPEngineTests.swift`, `cc-hdrmTests/Services/HistoricalTPPBackfillServiceTests.swift`, `cc-hdrmTests/Services/TPPChartDataServiceTests.swift`, `cc-hdrmTests/Services/TPPStorageServiceTests.swift`, `cc-hdrmTests/Services/PollingEngineTests.swift` -- cover the matrix, both state-change directions, and unchanged 5-hour results.

**Acceptance Criteria:**
- Given two real poll cycles with no 5-hour number after an anchoring step, when `PollingEngine.performPollCycle` runs, then a row with non-nil `tppSevenDay` reaches the database.
- Given polls with a number, when the engine and backfill process them, then every stored field matches the 1.6.0 result.
- Given an account changing state in either direction, in passive and backfill, then no row holds values from both bases.
- Given a range with both bases, when the chart loads, then points, trend, shifts, averages and insight all come from one basis.
- Given backfill rows older than the rebuild can recreate, when the user forces a re-run, then those rows remain.

## Spec Change Log

- Review loop 1. Findings: the 6-hour cap dropped the anchor on an empty overnight gap; force re-run could delete a weekly row it could not rebuild; the weekly flag was set after a failed pass; weekly delta-only rows could become the default model and empty the chart; weekly rollup rows were unread and not anchored to observed steps. Amended: cap skips an empty gap; force delete covers 5-hour rows only; flag set only after success; `availableModels` skips weekly rows with no value; weekly rollup branch removed. Applied as direct patches, because this run is unattended and the rest of the design held. KEEP: `WeeklyStepTracker` as the single rule, `five_hour_delta` as the basis, one-basis filtering in `loadTPPData`.

## Design Notes

**Why one basis at a time.** The two values differ about 10x. On a shared axis the 5-hour points would sit near the bottom. A picker removes the problem, and it also makes mixing impossible, because the service filters before it averages. Accounts with only 5-hour data see no change.

**Why anchored windows only.** Weekly percents are whole numbers. A window that opens mid-step holds only part of a step's tokens, so its TPP is understated by an unknown amount. One poll interval against a full 1% could read 100x low. Dropping the row is more honest than a low-confidence wrong number. A window opens at the first tokens after a step, so idle hours and an empty overnight gap do not break the anchor.

**Why no weekly rollup rows.** The chart excludes `rollup-backfill` rows and nothing else reads them, and a bucket edge is not an observed step. Storing them would write unread, approximate numbers. Weekly history therefore starts from the last 24 hours of raw polls plus live measurement.

**Defaults chosen.**
- Medium confidence at delta 3, the same constant as the 5-hour path. The superseded attempt used 2, which carries about 50% error.
- First step after launch, reset, state change or cap only anchors.
- No migration: `five_hour_delta` already records the basis.
- Weighting ratios stay on `tppFiveHour` only, so they are single-basis by construction.
- `getAverageTPP.sevenDay` now averages weekly-basis rows only. No production code reads it. Insight still reads `fiveHour`, and benchmark rows are always 5-hour.
- The weighting card stays visible on the weekly view: it holds a dimensionless ratio from past 5-hour benchmarks, and Story 26.8 keeps past results visible.

**Differences from 1.6.0 for accounts with a number.**
- Force re-run keeps 5-hour backfill rows it cannot rebuild: raw-poll rows older than the oldest raw poll, and rollup rows older than the oldest rollup. This fixes a data-loss bug. Before, it deleted them all and rebuilt only recent ones.
- A no-number poll now drops the open 5-hour window. This only happens when the response actually lacks the number.
- Everything else, including `resetDropThreshold`, the 30-minute cap and the flush without a cap check, is deliberately unchanged.

**Carried findings.**
- Backfill overlap: fixed for weekly rows. The 5-hour path keeps its overlap, because fixing it would change 1.6.0 results.
- No automatic weekly backfill: fixed with `tppWeeklyBackfillCompleted`.
- Stale windows: fixed for weekly. The 5-hour flush without a cap check stays, for the same reason.
- `sevenDayResetsAt: nil`: fixed; it took a few lines in `cc-hdrm/Services/PollingEngine.swift`.
- First-row partial window and 1% quantisation: fixed by anchoring and the confidence rule.

## Verification

**Commands:**
- `xcodegen generate` -- expected: project generated with the new file.
- `/usr/bin/lockf -k /tmp/cchdrm-xcodebuild.lock nice -n 15 xcodebuild -jobs 4 -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test 2>&1 | tail -40` -- expected: all tests pass.

## Suggested Review Order

**One weekly rule**

- Entry point: the weekly state machine that engine and backfill share.
  [`WeeklyStepTracker.swift:47`](../../cc-hdrm/Services/WeeklyStepTracker.swift#L47)

- An empty overnight gap keeps the anchor; anything else past 6 hours loses it.
  [`WeeklyStepTracker.swift:64`](../../cc-hdrm/Services/WeeklyStepTracker.swift#L64)

- A partial window anchors the next step and stores no number.
  [`WeeklyStepTracker.swift:123`](../../cc-hdrm/Services/WeeklyStepTracker.swift#L123)

- Drift in the reset time is not a reset.
  [`WeeklyStepTracker.swift:136`](../../cc-hdrm/Services/WeeklyStepTracker.swift#L136)

**Per-poll choice, with the 5-hour path untouched**

- Dispatch on the current poll; the 1.6.0 code below stays as it was.
  [`PassiveTPPEngine.swift:47`](../../cc-hdrm/Services/PassiveTPPEngine.swift#L47)

- Weekly path drops any open 5-hour window.
  [`PassiveTPPEngine.swift:286`](../../cc-hdrm/Services/PassiveTPPEngine.swift#L286)

- Weekly reset time now reaches the engine.
  [`PollingEngine.swift:342`](../../cc-hdrm/Services/PollingEngine.swift#L342)

**Basis on the row**

- `five_hour_delta` decides, so no migration and no rewrite of old rows.
  [`TPPMeasurement.swift:66`](../../cc-hdrm/Models/TPPMeasurement.swift#L66)

- Averages per basis.
  [`TPPStorageService.swift:186`](../../cc-hdrm/Services/TPPStorageService.swift#L186)

**Backfill**

- Pairs without a number on both sides feed the tracker.
  [`HistoricalTPPBackfillService.swift:218`](../../cc-hdrm/Services/HistoricalTPPBackfillService.swift#L218)

- Weekly pass runs once after upgrade.
  [`HistoricalTPPBackfillService.swift:44`](../../cc-hdrm/Services/HistoricalTPPBackfillService.swift#L44)

- Overlap skip; a row with no value cannot hide a real reading.
  [`HistoricalTPPBackfillService.swift:177`](../../cc-hdrm/Services/HistoricalTPPBackfillService.swift#L177)

- Flag set only after the pass really finished.
  [`HistoricalTPPBackfillService.swift:165`](../../cc-hdrm/Services/HistoricalTPPBackfillService.swift#L165)

**Force re-run data-loss fix**

- Delete limits come from what the rebuild can actually reach.
  [`HistoricalTPPBackfillService.swift:116`](../../cc-hdrm/Services/HistoricalTPPBackfillService.swift#L116)

- Only 5-hour backfill rows are deleted; weekly rows stay.
  [`TPPStorageService.swift:223`](../../cc-hdrm/Services/TPPStorageService.swift#L223)

**Chart: one basis at a time**

- Filter before any averaging, so mixing cannot happen downstream.
  [`TPPChartDataService.swift:52`](../../cc-hdrm/Services/TPPChartDataService.swift#L52)

- Default follows the newest passive reading, not old benchmarks.
  [`TPPChartDataService.swift:115`](../../cc-hdrm/Services/TPPChartDataService.swift#L115)

- Weekly rows with no value never become the default model.
  [`TPPChartDataService.swift:133`](../../cc-hdrm/Services/TPPChartDataService.swift#L133)

- Labels only when needed; 5-hour-only accounts see no change.
  [`TPPChartData.swift:51`](../../cc-hdrm/Models/TPPChartData.swift#L51)

- Picker appears only when the range holds both bases.
  [`TPPSectionView.swift:138`](../../cc-hdrm/Views/TPPSectionView.swift#L138)

**Proof**

- Real poll cycles against a real engine and a temporary database.
  [`PollingEngineTests.swift:2653`](../../cc-hdrmTests/Services/PollingEngineTests.swift#L2653)

- Field-by-field 1.6.0 results for polls with a number.
  [`PassiveTPPEngineTests.swift:704`](../../cc-hdrmTests/Services/PassiveTPPEngineTests.swift#L704)
