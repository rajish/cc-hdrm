# Deferred Work

## Deferred from: code review of 20-3-tpp-data-model-passive-measurement-engine (2026-03-27)

- `Int32` truncation for token counts in `TPPStorageService` — `sqlite3_bind_int(Int32(...))` used for `input_tokens`, `output_tokens`, `cache_create_tokens`, `cache_read_tokens`, `total_raw_tokens`, `message_count` columns. SQLite INTEGER is 64-bit but bind is 32-bit, risking silent data corruption for very large token counts. Pre-existing pattern from `storeBenchmarkResult` in Story 20.1 — fix should apply to all `sqlite3_bind_int` token columns in `TPPStorageService` at the same time.

## Deferred from: code review of 20-5-historical-tpp-backfill (2026-03-27)

- AC-1 progress indicator for app-launch backfill path not implemented — the spec says "a subtle progress indicator appears if the backfill takes >5 seconds" on first launch. The SettingsView button state ("Running...") only covers the manual re-run path, not the automatic fire-and-forget launch-path. Requires UI plumbing in AppDelegate/PopoverView to surface a progress state. Deferred to Story 20.4 or a dedicated polish story.

## Deferred from: code review of spec-21-4-fable-threshold-notifications (2026-08-13)

- Threshold-notification dedup state survives sign-out — `performSignOut` (cc-hdrm/App/AppDelegate.swift:373) clears windows and scoped limits in AppState but never resets `NotificationService`'s `fiveHourThresholdState` / `sevenDayThresholdState` / `scopedThresholdState`. A different account signing in inherits the previous account's warned20/warned5 state, suppressing its first threshold notification until a recovery re-arms the machine. Pre-existing for 5h/7d since Story 5.2; Story 21.4 adds a third machine with the same behavior. Fix would reset all three states on sign-out in one pass.

## Deferred from: code review of spec-26-1-weekly-allowance-menu-bar (2026-11-01)

- `PollingEngine` plan-exhausted rule still counts the 5-hour window — `cc-hdrm/Services/PollingEngine.swift:275` sets `planExhausted` when the 5h window is exhausted, while `AppState.isExtraUsageActive` is now weekly-only. The two rules disagree if a 5-hour value ever returns: extra-usage alerts would fire while the menu bar shows normal headroom. Belongs with the 5h notification cleanup in Story 26.9.

## Deferred from: code review of spec-26-7-tpp-weekly-deltas (2026-11-01)

- source_spec: `_bmad-output/implementation-artifacts/spec-26-7-tpp-weekly-deltas.md`
  summary: Existing users get no automatic weekly TPP backfill after upgrade; `runBackfillIfNeeded` skips because `tppBackfillCompleted` is already true or old backfill rows exist.
  evidence: `cc-hdrm/Services/HistoricalTPPBackfillService.swift` `runBackfillIfNeeded` fast/slow paths; weekly backfill only runs via Settings "Re-run TPP Backfill".
- source_spec: `_bmad-output/implementation-artifacts/spec-26-7-tpp-weekly-deltas.md`
  summary: Weekly reset detection in passive TPP relies on a utilization drop; a reset followed by a rise within one poll interval goes unnoticed.
  evidence: `cc-hdrm/Services/PollingEngine.swift` builds the current `UsagePoll` with `sevenDayResetsAt: nil`, so the engine cannot compare reset timestamps; fixing it touches PollingEngine (Story 26.2 territory).

## Deferred from: code review 2 of spec-26-7-tpp-weekly-deltas (2026-11-01)

- Benchmark insight text and weighting ratios (`cc-hdrm/Services/TPPChartDataService.swift` `computeInsightText`, `sameBasisRatio`) prefer `tppSevenDay` without checking `fiveHourDelta`, and the 30-day average comes from `TPPStorageService.getAverageTPP`, which averages all rows. Harmless today (all benchmark rows are 5h-era, so both sides are the same quantity), but once Story 26.8 stores weekly-era benchmark rows, the average will mix eras. Fix with 26.8: average only rows where `fiveHourDelta == nil` (same rule as `chartValue`).
- First backfill row of each 24-hour run starts at the first poll, not at a weekly step, so its token window is partial and TPP is understated. Row is `low` confidence unless delta is 2% or more. Fix would skip the first unanchored step.
- Integer weekly percents: a single 1% step carries up to ±100% quantisation error and a 2% step ±50%. Daily and weekly chart averages smooth this; the day view shows raw points. If medium confidence at 2% proves too optimistic, raise `mediumConfidenceDelta` to 3 in `PassiveTPPEngine` and `HistoricalTPPBackfillService`.
- Chart plots 5h-based and weekly values on one Y axis although their magnitudes differ about 10x; old 5h-based points sit near the bottom. Separate axis or a toggle is a UX decision.
