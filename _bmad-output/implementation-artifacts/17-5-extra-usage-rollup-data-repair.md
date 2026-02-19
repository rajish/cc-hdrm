# Story 17.5: Extra Usage Rollup Data Repair

Status: done

## Story

As a developer using Claude Code with extra usage enabled,
I want tainted historical rollup data purged on upgrade so that the analytics chart rebuilds cleanly with accurate extra usage bars going forward, instead of showing misleading NULL gaps from pre-fix rollups.

## Acceptance Criteria

1. **Given** the app launches after updating from a version where rollups were created without extra usage columns populated
   **When** `ensureRollupsUpToDate()` runs for the first time after update
   **Then** a one-time migration deletes ALL rows from `usage_rollups` and resets `last_rollup_timestamp` in `rollup_metadata`, so the rollup pipeline starts fresh from whatever raw polls survive.

2. **Given** the one-time migration has purged old rollups
   **When** `ensureRollupsUpToDate()` continues its normal pipeline
   **Then** surviving raw polls (last ~24h) are rolled up correctly with extra usage data, and the analytics chart shows accurate data from that point forward.

3. **Given** the migration has completed successfully
   **When** `ensureRollupsUpToDate()` runs on subsequent app launches
   **Then** the migration does NOT run again (tracked via a flag in `rollup_metadata`).

4. **Given** existing tests for the rollup pipeline
   **When** this story is implemented
   **Then** all existing tests continue to pass AND new tests verify the migration logic (rollups purged, metadata reset, runs only once, forward pipeline produces correct extra usage).

## Tasks / Subtasks

- [x] Task 1: Add one-time purge migration to HistoricalDataService (AC: 1, 2, 3)
  - [x] 1.1 In `cc-hdrm/Services/HistoricalDataService.swift`, add a new private method:
    ```swift
    private func migrateExtraUsagePurge(connection: OpaquePointer) throws
    ```
    This method:
    - Checks `rollup_metadata` for key `extra_usage_purge_completed` — if value is `1`, return early (already done)
    - Executes `DELETE FROM usage_rollups` — purges all tainted rollup data
    - Resets `last_rollup_timestamp` to `0` (or deletes the key) so the pipeline reprocesses from scratch
    - Writes `extra_usage_purge_completed` = `1` to `rollup_metadata`
    - Logs at `.info` level: "Migration: purged tainted rollups for extra usage rebuild"
  - [x] 1.2 Follow the existing metadata pattern for the flag: read via `SELECT value FROM rollup_metadata WHERE key = ?` (see `getLastRollupTimestamp()` at `cc-hdrm/Services/HistoricalDataService.swift:651-676`), write via `INSERT OR REPLACE INTO rollup_metadata (key, value) VALUES (?, ?)` (see `setLastRollupTimestamp()` at `cc-hdrm/Services/HistoricalDataService.swift:682-707`).
  - [x] 1.3 In `ensureRollupsUpToDate()` (lines 709-755), call `migrateExtraUsagePurge(connection:)` **before** the rollup pipeline stages (before `performRawTo5MinRollup` at line 731). This way, the purge clears tainted data first, then the normal pipeline immediately rebuilds from surviving raw polls in the same call.

- [x] Task 2: Write unit tests for the purge migration (AC: 1, 2, 3, 4)
  - [x] 2.1 In `cc-hdrmTests/Services/HistoricalDataServiceTests.swift`, add test: purge deletes all existing rollups. Insert several rollups with NULL extra_usage. Call `ensureRollupsUpToDate()`. Verify `usage_rollups` table has no rows from before the call (old rows deleted), and any new rows were created by the pipeline from raw polls.
  - [x] 2.2 Add test: purge resets `last_rollup_timestamp`. Insert a rollup_metadata entry with `last_rollup_timestamp` = some value. Call `ensureRollupsUpToDate()`. Verify `last_rollup_timestamp` was reset (either to 0 or re-written by the pipeline after reprocessing).
  - [x] 2.3 Add test: purge runs only once. Insert rollups, call `ensureRollupsUpToDate()` (purges + rebuilds), then insert more rollups manually, call `ensureRollupsUpToDate()` again. Verify the second call does NOT purge the manually-inserted rollups (flag prevents re-run).
  - [x] 2.4 Add test: after purge, surviving raw polls are correctly rolled up with extra usage. Insert raw polls with non-NULL extra usage data in the 24h-7d window. Call `ensureRollupsUpToDate()`. Verify the resulting 5-min rollups have correct extra_usage_used_credits and extra_usage_utilization values (MAX aggregation).

- [x] Task 3: Verify forward pipeline end-to-end (AC: 2, 4)
  - [x] 3.1 Add an end-to-end test that:
    - Inserts raw polls with extra usage data spanning multiple 5-min buckets across several days
    - Calls `ensureRollupsUpToDate()`
    - Verifies 5-min rollups have correct extra usage (MAX per bucket)
    - Verifies hourly rollups have correct extra usage (MAX across constituent 5-min rollups)
    - Verifies daily rollups have correct extra usage (MAX across constituent hourly rollups)

- [x] Task 4: Run all tests and verify (AC: 4)
  - [x] 4.1 Run `xcodebuild test` and verify all existing + new tests pass (1209 tests, 100 suites, 0 failures).
  - [x] 4.2 No `xcodegen generate` needed — no new Swift files.

## Dev Notes

### Root Cause

PR 83 (commit ebdc3c5) correctly fixed the **forward pipeline** — new rollups now persist extra usage through all rollup stages (5min → hourly → daily). However, the fix did NOT address **historical rollups** created before the fix was deployed. These old rollups have NULL in `extra_usage_used_credits` and `extra_usage_utilization` because the old rollup code never extracted or stored those values.

The NULL propagates up the rollup chain: old 5-min rollups (NULL) → hourly rollups (NULL) → daily rollups (NULL). The "All" time view would show this gap for up to 365 days (retention period). The source raw polls were already deleted by `deleteRawPolls()` at `cc-hdrm/Services/HistoricalDataService.swift:892`, so backfill is not possible for most historical periods.

### Fix Strategy: Purge and Rebuild

Instead of attempting to repair individual rollups (which is limited by raw poll survival), we purge ALL existing rollups and let the pipeline rebuild from scratch:

1. **DELETE all rows from `usage_rollups`** — removes all tainted data
2. **Reset `last_rollup_timestamp`** — tells the pipeline to reprocess everything
3. **Normal pipeline runs immediately after** — rebuilds from surviving raw polls (~24h)

**Trade-off**: The user loses historical utilization data (5h/7d charts for older periods will be empty until new data accumulates). This is acceptable because the alternative — living with misleading NULL extra usage for up to a year — is worse.

**What survives the purge:**
- `usage_polls` (raw polls) — last ~24h of data, untouched
- `reset_events` — all reset detection history, untouched
- Schema and metadata — intact

**What is lost:**
- All rollup aggregates (5-min, hourly, daily) — chart history for periods older than ~24h
- This fills back in naturally: 7d view in ~1 week, 30d view in ~1 month

### Key Code Locations

- **ensureRollupsUpToDate()**: `cc-hdrm/Services/HistoricalDataService.swift:709-755` — orchestrates rollup pipeline, purge call goes before line 731 (performRawTo5MinRollup)
- **getLastRollupTimestamp()**: `cc-hdrm/Services/HistoricalDataService.swift:651-676` — metadata read pattern to follow
- **setLastRollupTimestamp()**: `cc-hdrm/Services/HistoricalDataService.swift:682-707` — metadata write pattern (INSERT OR REPLACE)
- **performRawTo5MinRollup()**: `cc-hdrm/Services/HistoricalDataService.swift:823-895` — first rollup stage, runs after purge
- **deleteRawPolls()**: `cc-hdrm/Services/HistoricalDataService.swift:1063-1082` — deletes raw polls after rollup (not affected by this story)
- **rollup_metadata table**: `cc-hdrm/Services/DatabaseManager.swift:312-322` — schema: `key TEXT PRIMARY KEY, value TEXT`
- **BarChartView extra usage overlay**: `cc-hdrm/Views/BarChartView.swift:435` — renders when `extraUsageUtilization != nil && > 0`

### Architecture Compliance

- **No new files** — all changes are in existing `HistoricalDataService.swift` and existing test file
- **No schema changes** — purge uses existing tables and the existing `rollup_metadata` table for the flag
- **Follows existing patterns**: metadata read/write follows `getLastRollupTimestamp`/`setLastRollupTimestamp` pattern exactly
- **Migration is idempotent**: flag check ensures it runs exactly once, even if interrupted mid-purge

### Previous Story Intelligence

From PR 83 (fix for issue 81):
- Schema v4 added `extra_usage_used_credits REAL` and `extra_usage_utilization REAL` to `usage_rollups`
- All rollup stages (raw→5min, 5min→hourly, hourly→daily) now propagate MAX extra usage
- `insertRollup()` binds extra usage at positions 12-13
- `queryRollupsForRollup()` reads extra usage at column indices 12-13

### Project Structure Notes

No new files needed. All changes are within:
```
cc-hdrm/Services/HistoricalDataService.swift            # MODIFY — add purge migration + call site
cc-hdrmTests/Services/HistoricalDataServiceTests.swift   # MODIFY — add purge + pipeline tests
```

### References

- [Source: cc-hdrm/Services/HistoricalDataService.swift:709-755] — ensureRollupsUpToDate() orchestration
- [Source: cc-hdrm/Services/HistoricalDataService.swift:651-676] — getLastRollupTimestamp() metadata read pattern
- [Source: cc-hdrm/Services/HistoricalDataService.swift:682-707] — setLastRollupTimestamp() metadata write pattern (INSERT OR REPLACE)
- [Source: cc-hdrm/Services/HistoricalDataService.swift:823-895] — performRawTo5MinRollup() with extra usage (PR 83)
- [Source: cc-hdrm/Services/HistoricalDataService.swift:892] — deleteRawPolls() call
- [Source: cc-hdrm/Services/HistoricalDataService.swift:1063-1082] — deleteRawPolls() method
- [Source: cc-hdrm/Services/DatabaseManager.swift:312-322] — rollup_metadata table schema
- [Source: cc-hdrm/Services/DatabaseManager.swift:157-162] — v3→v4 migration adding rollup columns
- [Source: cc-hdrm/Views/BarChartView.swift:435] — extra usage overlay rendering condition
- [Source: cc-hdrm/Models/UsageRollup.swift:30-35] — extra usage fields documentation
- [Source: GitHub Issue 81] — original bug report with data flow analysis
- [Source: PR 83 / commit ebdc3c5] — forward pipeline fix

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (1M context)

### Debug Log References

- Initial e2e test failed: daily rollups require hourly data 30d+ old. Fixed by pre-positioning data at each rollup tier's time window with purge flag pre-set.

### Completion Notes List

- Added `migrateExtraUsagePurge(connection:)` private method to HistoricalDataService — one-time migration that purges all tainted rollups, resets `last_rollup_timestamp`, and sets `extra_usage_purge_completed` flag
- Migration is called at the start of `ensureRollupsUpToDate()` inside the existing transaction, before the rollup pipeline stages
- Follows existing metadata read/write patterns (`SELECT value FROM rollup_metadata WHERE key = ?` / `INSERT OR REPLACE`)
- Uses prepared statements with proper finalize for all SQL operations
- 5 new tests added: purge deletes rollups, purge resets timestamp, purge runs once only, purge rebuilds with extra usage, end-to-end pipeline verification across all 3 tiers (5-min, hourly, daily)
- Full regression suite: 1209 tests, 100 suites, 0 failures

### Code Review Fixes Applied

- **HIGH fix**: Added NULL check (`sqlite3_column_type != SQLITE_NULL`) before `sqlite3_column_text` in `migrateExtraUsagePurge()` — prevents potential null pointer crash if metadata value is NULL
- **MEDIUM fix**: Converted 3 SQL statement blocks (delete/reset/flag) to use scoped `do { }` blocks with `defer { sqlite3_finalize }` — matches the codebase-wide statement cleanup pattern
- **MEDIUM fix**: Strengthened `purgeMigrationResetsLastRollupTimestamp` test assertion — now captures `nowBefore` timestamp and verifies `tsAfter >= nowBefore` instead of weak `!= oldValue` check
- **LOW fix**: Added comment in `clearAllData()` documenting that deleting `rollup_metadata` clears the purge flag (harmless — migration is idempotent)
- **LOW fix**: Added `purgeFollowedByFullPipelineRebuildsOnlyTier1` integration test — verifies purge + all 3 pipeline stages in a single call: tainted rollups purged, only tier 1 rebuilt from surviving raw polls, no orphaned hourly/daily rollups
- Post-fix regression: 1211 tests, 101 suites, 0 failures

### File List

- `cc-hdrm/Services/HistoricalDataService.swift` — MODIFIED: added `migrateExtraUsagePurge()` method and call site in `ensureRollupsUpToDate()`
- `cc-hdrmTests/Services/HistoricalDataServiceTests.swift` — MODIFIED: added 5 new tests for purge migration and forward pipeline
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — MODIFIED: story status updated
- `_bmad-output/implementation-artifacts/17-5-extra-usage-rollup-data-repair.md` — MODIFIED: task checkboxes, dev agent record, status
