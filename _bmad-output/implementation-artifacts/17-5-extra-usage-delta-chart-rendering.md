# Story 17.5: Extra Usage Delta Chart Rendering

Status: done

## Story

As a developer using Claude Code with extra usage enabled,
I want the analytics charts to show when extra usage credits were actively being consumed (delta between polls) as a prominent layer, with a faint cumulative backdrop,
so that I can see exactly which time periods drained my extra budget — regardless of whether plan utilization was at 100%.

## Acceptance Criteria

1. **Given** two consecutive polls where `extraUsageUsedCredits` increased (delta > 0)
   **When** `persistPoll()` stores the new poll
   **Then** the computed delta (`max(0, current.usedCredits - previous.usedCredits)`) is persisted in a new `extra_usage_delta` column on `usage_polls`.

2. **Given** a billing cycle reset causes `extraUsageUsedCredits` to drop (delta < 0)
   **When** `persistPoll()` computes the delta
   **Then** the delta is clamped to 0 (no negative drain recorded).

3. **Given** raw polls with `extra_usage_delta` values are rolled up into 5-min/hourly/daily aggregates
   **When** the rollup pipeline processes each tier
   **Then** a new `extra_usage_delta` column on `usage_rollups` stores the SUM of deltas per period (total credits drained in that period).

4. **Given** the 24h step-area chart renders and extra usage data exists
   **When** `extraUsageUtilization > 0` for any points in the visible range
   **Then** two visual layers appear:
   - **Faint background**: cumulative `extraUsageUtilization` rendered as a subtle shaded band spanning the full chart width at the top (above the data area), showing overall budget consumption level. Visible across ALL time periods where `extraUsageUtilization > 0`, regardless of 5h/7d utilization.
   - **Prominent foreground**: spike markers at specific time periods where `extra_usage_delta > 0`, rendered at the actual time position on the chart. These appear at ANY utilization level (not gated on 100%) — a premium model drain at 30% 5h utilization still shows a spike.

5. **Given** the 7d/30d/All bar chart renders and extra usage data exists
   **When** `extraUsageUtilization > 0` for any bars in the visible range
   **Then** the same two-layer approach applies:
   - **Faint background**: subtle overlay spanning all bars where `extraUsageUtilization > 0` (cumulative budget level), regardless of bar height
   - **Prominent foreground**: stronger overlay on bars where `extra_usage_delta > 0` (active drain periods), regardless of 5h/7d utilization level
   - The current gate (`extraUsageUtilization > 0`) is replaced by `extra_usage_delta > 0` for the prominent layer only

6. **Given** a premium model (e.g., opus-1-million-token-window) drains extra usage while 5h/7d utilization is below 100%
   **When** the chart renders that period
   **Then** the prominent delta layer appears at the correct time period, proving delta-based detection works independently of plan utilization.

7. **Given** existing polls in `usage_polls` that predate this story (no `extra_usage_delta` column)
   **When** the schema migration adds the new column
   **Then** a one-time backfill computes deltas from consecutive existing polls' `extraUsageUsedCredits` values and populates the column. Old rollups without delta data render with faint background only (NULL delta = no prominent layer).

8. **Given** all existing tests for the rollup pipeline and chart rendering
   **When** this story is implemented
   **Then** all existing tests continue to pass AND new tests verify delta computation, rollup aggregation (SUM), backfill logic, and both chart layers.

## Tasks / Subtasks

- [x] Task 1: Schema migration — add `extra_usage_delta` column (AC: 1, 3, 7)
  - [x] 1.1 In `cc-hdrm/Services/DatabaseManager.swift`, bump `currentSchemaVersion` from 4 to 5. Add a v4→v5 migration that adds `extra_usage_delta REAL` to `usage_polls` and `extra_usage_delta REAL` to `usage_rollups`. Follow the existing migration pattern at `cc-hdrm/Services/DatabaseManager.swift:131-175` (ALTER TABLE ADD COLUMN).
  - [x] 1.2 Add a one-time backfill step in the migration: query all polls ordered by timestamp, compute `max(0, poll[N].extra_usage_used_credits - poll[N-1].extra_usage_used_credits)` for consecutive polls, UPDATE each poll's `extra_usage_delta`. Handle NULL `extra_usage_used_credits` (treat as 0 delta). Handle billing cycle resets (negative delta → 0).

- [x] Task 2: Compute delta at persist time (AC: 1, 2)
  - [x] 2.1 In `cc-hdrm/Services/HistoricalDataService.swift` `persistPoll()` (line ~46-188), after inserting the new poll, compute delta from previous poll's `extraUsageUsedCredits` (already fetched at line ~60 for reset detection). Write: `UPDATE usage_polls SET extra_usage_delta = ? WHERE id = ?` using the newly inserted row's ID.
  - [x] 2.2 Edge cases: if previous poll is nil (first poll), delta = 0. If current or previous `extraUsageUsedCredits` is nil, delta = 0. If delta < 0 (billing reset), clamp to 0.

- [x] Task 3: Update rollup aggregation to SUM deltas (AC: 3)
  - [x] 3.1 In `performRawTo5MinRollup()` (`cc-hdrm/Services/HistoricalDataService.swift:~898`), add: `let deltaValues = bucketPolls.compactMap { $0.extraUsageDelta }; let extraUsageDelta = deltaValues.isEmpty ? nil : deltaValues.reduce(0, +)`. Pass to `insertRollup()`.
  - [x] 3.2 Same pattern in `perform5MinToHourlyRollup()` and `performHourlyToDailyRollup()` — SUM the `extra_usage_delta` across sub-rollups.
  - [x] 3.3 Update `insertRollup()` to accept and bind the new `extra_usage_delta` parameter at the next bind position.
  - [x] 3.4 Update `queryRollupsForRollup()` and `queryRolledUpData()` to read the new column.
  - [x] 3.5 Add `extraUsageDelta` field to `UsageRollup` struct (`cc-hdrm/Models/UsageRollup.swift`).
  - [x] 3.6 Add `extraUsageDelta` field to `UsagePoll` struct (`cc-hdrm/Models/UsagePoll.swift`) and update `readPollRow()` to read it.
  - [x] 3.7 Update `pollToRollup()` (`cc-hdrm/Services/HistoricalDataService.swift:1418`) to pass through `poll.extraUsageDelta` to the `UsageRollup`. Without this, the 7d bar chart's last-24h data (raw polls converted to pseudo-rollups) would have NULL delta.

- [x] Task 4: Update 24h step-area chart rendering (AC: 4, 6)
  - [x] 4.1 In `cc-hdrm/Views/StepAreaChartView.swift`, change `isExtraUsageActive` (line ~203) from the 99.5% utilization gate to: `poll.extraUsageDelta != nil && poll.extraUsageDelta! > 0`. This is the prominent layer trigger — fires at any utilization level.
  - [x] 4.2 Add a faint cumulative background layer: render `extraUsageUtilization` as a subtle band (opacity ~0.15) spanning the full chart width at the top of the chart area for ALL points where `extraUsageUtilization > 0`, regardless of delta or 5h/7d utilization. The prominent delta layer renders spike markers on top at higher opacity (~0.6) only where `extra_usage_delta > 0`.
  - [x] 4.3 Update `ChartPoint` to include `extraUsageDelta: Double?` field, populated from poll data.

- [x] Task 5: Update 7d/30d/All bar chart rendering (AC: 5, 6)
  - [x] 5.1 In `cc-hdrm/Views/BarChartView.swift`, change the extra usage overlay condition (line ~435) from `extraUsageUtilization > 0` to use delta-based detection. Add `extraUsageDelta` to `BarPoint` struct.
  - [x] 5.2 Faint background layer: render subtle overlay spanning all bars where `extraUsageUtilization > 0` (cumulative budget level), regardless of bar height or utilization.
  - [x] 5.3 Prominent foreground layer: render stronger overlay on bars where `extraUsageDelta > 0` (active drain periods), regardless of 5h/7d utilization level.
  - [x] 5.4 Update `BarChartView.init` aggregation (line ~132-138) to compute delta for bar points: SUM the `extraUsageDelta` across rollups in each visual period.

- [x] Task 6: Write tests (AC: 8)
  - [x] 6.1 Test delta computation in `persistPoll()`: normal delta, nil previous, nil usedCredits, billing reset (negative → 0).
  - [x] 6.2 Test rollup SUM aggregation: 5-min rollup with multiple polls having different deltas, verify SUM.
  - [x] 6.3 Test backfill migration: insert consecutive polls with known cumulative values, run migration, verify computed deltas.
  - [x] 6.4 Test chart data: verify `extraUsageDelta` is available in rollup query results and bar/chart point structs.

- [x] Task 7: Run all tests and verify (AC: 8)
  - [x] 7.1 Run `xcodebuild test` and verify all existing + new tests pass.
  - [x] 7.2 Run `xcodegen generate` after adding any new Swift files (if needed).

## Dev Notes

### Root Cause of Previous Story 17.5 Failure

The original story 17.5 proposed `DELETE FROM usage_rollups` (purging ALL rollup history) to fix NULL extra usage columns in old rollups. This was fundamentally wrong: it destroyed months of valid 5h/7d utilization data. The real issue is that the chart rendering logic is incorrect, not the data.

### Actual Problems (Two Bugs)

1. **24h chart (StepAreaChartView)**: Gates extra usage display on `fiveHourUtil >= 99.5 || sevenDayUtil >= 99.5` (line ~203). This misses extra usage drain from premium model selection (e.g., opus-1-million-token-window) which can drain at any utilization level.

2. **7d bar chart (BarChartView)**: Gates extra usage display on `extraUsageUtilization > 0` (line ~435). Since `extraUsageUtilization` is cumulative for the billing cycle, once it goes above zero it stays above zero for every subsequent poll — showing green overlay on ALL bars after the first drain, even at low utilization.

### Fix Strategy: Delta-Based Detection + Two-Layer Rendering

Instead of using the cumulative `extraUsageUtilization` as the sole signal, compute the DELTA between consecutive polls' `extraUsageUsedCredits`. A positive delta means credits were actively being consumed in that interval.

**Two chart layers:**
1. **Faint cumulative background** — `extraUsageUtilization` (existing data). Shows overall extra usage budget consumption. Subtle opacity.
2. **Prominent delta foreground** — `extra_usage_delta > 0` (new). Shows WHEN credits were actively draining. High visibility.

**Why deltas, not cumulative:**
- Cumulative `extraUsageUsedCredits` only goes up within a billing cycle — it tells you "how much total" but not "when"
- Delta between consecutive polls tells you "credits were being consumed RIGHT HERE"
- Premium model drain (opus-1M) happens at any utilization level — delta catches it; utilization gate misses it

### Key Code Locations

- **persistPoll()**: `cc-hdrm/Services/HistoricalDataService.swift:46-188` — already fetches previous poll at line ~60 for reset detection; delta computation piggybacks on this
- **performRawTo5MinRollup()**: `cc-hdrm/Services/HistoricalDataService.swift:~898` — change MAX to SUM for delta column
- **perform5MinToHourlyRollup()**: `cc-hdrm/Services/HistoricalDataService.swift:~1168` — same SUM pattern
- **performHourlyToDailyRollup()**: `cc-hdrm/Services/HistoricalDataService.swift:~1249` — same SUM pattern
- **insertRollup()**: `cc-hdrm/Services/HistoricalDataService.swift:~1058` — add delta bind position
- **readPollRow()**: `cc-hdrm/Services/HistoricalDataService.swift:~390` — add delta column read
- **StepAreaChartView isExtraUsageActive**: `cc-hdrm/Views/StepAreaChartView.swift:203-204` — replace utilization gate with delta gate
- **BarChartView extra usage overlay**: `cc-hdrm/Views/BarChartView.swift:435` — replace cumulative gate with delta gate
- **UsageRollup struct**: `cc-hdrm/Models/UsageRollup.swift:30-35` — add `extraUsageDelta` field
- **UsagePoll struct**: `cc-hdrm/Models/UsagePoll.swift` — add `extraUsageDelta` field
- **DatabaseManager migrations**: `cc-hdrm/Services/DatabaseManager.swift:131-175` — existing migration pattern to follow
- **Schema version**: `cc-hdrm/Services/DatabaseManager.swift` — increment schema version for new migration

### Data Range Note

`UsagePoll.swift:24` documents `extraUsageUtilization` as "fraction (0-1)" but this is a stale doc comment. The actual values are 0-100 (percentage), consistent with:
- `UsageRollup.swift:33`: "percentage 0-100"
- `BarChartView.BarPoint:46`: "percentage 0-100"
- Both chart math expressions: `util / 100.0 * 5.0` (would be invisible if 0-1)

Do NOT change the scale. Fix the `UsagePoll` doc comment to say "percentage (0-100)" for consistency.

### Architecture Compliance

- **Schema migration follows existing pattern**: ALTER TABLE ADD COLUMN, same as v3→v4 migration in PR 83
- **No new files** — all changes in existing service, model, and view files
- **Rollup aggregation**: SUM for deltas (new), MAX for cumulative (unchanged) — both are valid SQL aggregations already used in the pipeline
- **Backward compatible**: NULL `extra_usage_delta` in old data = no prominent layer, faint background still works from existing cumulative data

### Previous Story Intelligence

From PR 83 (commit ebdc3c5, story 17.3):
- Schema v4 added `extra_usage_used_credits REAL` and `extra_usage_utilization REAL` to `usage_rollups`
- All rollup stages propagate MAX extra usage (cumulative)
- `insertRollup()` binds extra usage at positions 12-13
- `queryRollupsForRollup()` reads extra usage at column indices 12-13
- New delta column will be at the next position (14 in rollups, 10 in polls)

### References

- [Source: cc-hdrm/Services/HistoricalDataService.swift:46-188] — persistPoll() with previous poll fetch
- [Source: cc-hdrm/Services/HistoricalDataService.swift:~898-971] — performRawTo5MinRollup() with MAX extra usage
- [Source: cc-hdrm/Services/HistoricalDataService.swift:~1058-1137] — insertRollup() with extra usage bind positions
- [Source: cc-hdrm/Services/HistoricalDataService.swift:~390-422] — readPollRow() column indices
- [Source: cc-hdrm/Views/StepAreaChartView.swift:203-204] — isExtraUsageActive utilization gate (BUG)
- [Source: cc-hdrm/Views/BarChartView.swift:435] — extraUsageUtilization > 0 gate (BUG)
- [Source: cc-hdrm/Views/StepAreaChartView.swift:596-608] — extraUsageMarks rendering (faint layer base)
- [Source: cc-hdrm/Models/UsageRollup.swift:30-35] — existing extra usage fields
- [Source: cc-hdrm/Services/DatabaseManager.swift:131-175] — v3→v4 migration pattern
- [Source: PR 83 / commit ebdc3c5] — forward pipeline fix for extra usage propagation

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

No debug issues encountered.

### Completion Notes List

- Task 1: Bumped schema version 4→5. Added v4→v5 migration with ALTER TABLE ADD COLUMN for `extra_usage_delta` on both `usage_polls` and `usage_rollups`. Backfill computes deltas from consecutive polls' cumulative `extra_usage_used_credits` values. NULL and billing reset (negative) handled correctly.
- Task 2: Delta computation in `persistPoll()` — computed before INSERT and included directly in the INSERT statement (no separate UPDATE). Edge cases: first poll → 0, nil credits → nil, negative → clamped to 0.
- Task 3: All three rollup stages (raw→5min, 5min→hourly, hourly→daily) updated to SUM `extra_usage_delta`. `insertRollup()` accepts and binds at position 14. `queryRollupsForRollup()` reads at column index 14. `pollToRollup()` passes through `extraUsageDelta`. Both model structs updated.
- Task 4: StepAreaChartView — `isExtraUsageActive` now delta-based (`poll.extraUsageDelta != nil && poll.extraUsageDelta! > 0`). New `extraUsageBackgroundPoints` array for faint cumulative layer (opacity 0.15). Prominent delta layer at opacity 0.6.
- Task 5: BarChartView — two-layer overlay: faint background for `extraUsageUtilization > 0` (0.15 opacity), prominent foreground for `extraUsageDelta > 0` (0.6 opacity). `BarPoint.extraUsageDelta` added. `makeBarPoints()` SUMs delta across rollups.
- Task 6: 9 new tests: 2 migration tests (column existence, backfill correctness), 5 service tests (normal delta, billing reset clamp, nil delta, rollup SUM, query passthrough), 5 chart tests replaced (delta-based active flag). Updated 3 existing version-check tests (4→5).
- Task 7: Full regression suite — 1210 tests in 100 suites passed. No regressions. `xcodegen generate` run.
- Also fixed stale doc comment on `UsagePoll.extraUsageUtilization` from "fraction (0-1)" to "percentage (0-100)" per Dev Notes.

### Code Review Fixes (AI)

- **M1+L2**: Merged INSERT+UPDATE into single INSERT in `persistPoll()` — delta computed before INSERT and bound at position 10. Eliminates silent failure risk and second SQL roundtrip.
- **M2**: Backfill migration now wraps batch UPDATEs in `BEGIN/COMMIT` transaction and prepares statement once with `sqlite3_reset` per iteration. Eliminates per-row fsync and re-prepare overhead.
- **M3**: Added `barPointDeltaSumAggregation` test verifying `makeBarPoints` correctly SUMs `extraUsageDelta` across rollups (1211 tests total).
- **L1**: Added `extra_usage_used_credits`, `extra_usage_utilization`, `extra_usage_delta` to `usageRollupsTableHasCorrectColumns` test.
- **L3**: Removed redundant `util > 0` guard from bar chart prominent overlay (delta > 0 implies util > 0).

### File List

- cc-hdrm/Services/DatabaseManager.swift — schema v5 migration, backfill, CREATE TABLE updates
- cc-hdrm/Models/UsagePoll.swift — added `extraUsageDelta` field, fixed doc comment
- cc-hdrm/Models/UsageRollup.swift — added `extraUsageDelta` field
- cc-hdrm/Services/HistoricalDataService.swift — delta compute in persistPoll, SUM in rollups, readPollRow, insertRollup, queryRollupsForRollup, pollToRollup, pollsToRollupsWithResets
- cc-hdrm/Views/StepAreaChartView.swift — delta-based isExtraUsageActive, two-layer rendering (faint bg + prominent fg), ChartPoint.extraUsageDelta
- cc-hdrm/Views/BarChartView.swift — two-layer overlay, BarPoint.extraUsageDelta, SUM in makeBarPoints
- cc-hdrmTests/Services/DatabaseManagerTests.swift — v4→v5 migration tests, backfill test, version bumps
- cc-hdrmTests/Services/HistoricalDataServiceTests.swift — delta compute tests, rollup SUM test, query passthrough test
- cc-hdrmTests/Views/UsageChartTests.swift — updated extra usage chart point tests for delta-based detection
