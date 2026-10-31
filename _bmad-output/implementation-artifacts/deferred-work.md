# Deferred Work

## Deferred from: code review of 20-3-tpp-data-model-passive-measurement-engine (2026-03-27)

- `Int32` truncation for token counts in `TPPStorageService` — `sqlite3_bind_int(Int32(...))` used for `input_tokens`, `output_tokens`, `cache_create_tokens`, `cache_read_tokens`, `total_raw_tokens`, `message_count` columns. SQLite INTEGER is 64-bit but bind is 32-bit, risking silent data corruption for very large token counts. Pre-existing pattern from `storeBenchmarkResult` in Story 20.1 — fix should apply to all `sqlite3_bind_int` token columns in `TPPStorageService` at the same time.

## Deferred from: code review of 20-5-historical-tpp-backfill (2026-03-27)

- AC-1 progress indicator for app-launch backfill path not implemented — the spec says "a subtle progress indicator appears if the backfill takes >5 seconds" on first launch. The SettingsView button state ("Running...") only covers the manual re-run path, not the automatic fire-and-forget launch-path. Requires UI plumbing in AppDelegate/PopoverView to surface a progress state. Deferred to Story 20.4 or a dedicated polish story.

## Deferred from: code review of spec-21-4-fable-threshold-notifications (2026-08-13)

- Threshold-notification dedup state survives sign-out — `performSignOut` (cc-hdrm/App/AppDelegate.swift:373) clears windows and scoped limits in AppState but never resets `NotificationService`'s `fiveHourThresholdState` / `sevenDayThresholdState` / `scopedThresholdState`. A different account signing in inherits the previous account's warned20/warned5 state, suppressing its first threshold notification until a recovery re-arms the machine. Pre-existing for 5h/7d since Story 5.2; Story 21.4 adds a third machine with the same behavior. Fix would reset all three states on sign-out in one pass.

## Deferred from: code review of spec-26-5-value-headroom-per-weekly-cycle (2026-11-01)

- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-per-weekly-cycle.md`
  summary: `CycleUtilizationCalculator` groups events by calendar month or billing cycle before aggregating, so legacy events and the first weekly cycle that land in different groups are not de-duplicated, and a weekly cycle is assigned wholly to the month of its reset.
  evidence: overlap exclusion (`ResetEvent` array `excludingWeeklyOverlap`) runs per call on the events it is given; the cycle chart passes per-month groups.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-per-weekly-cycle.md`
  summary: A weekly cycle whose event tier does not resolve is skipped by `aggregateBreakdown` but still counted in `periodDays`, understating utilisation. A `.month` range can hold 5 weekly cycles (35 days of capacity and price); the weekly count is not capped by the range.
  evidence: `periodDays` has no tier information; `SubscriptionValueCalculator.calculate` divides summed used credits by `periodDays`. Needs a tier-aware capacity input or a single shared "countable events" rule.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-per-weekly-cycle.md`
  summary: 5h reset detection branches and `getRecentPeakUtilization` in `cc-hdrm/Services/HistoricalDataService.swift` are dead since `five_hour` is null; remove per the "remove, don't hide" principle.
  evidence: Detection still checks `fiveHourResetsAt`/`fiveHourUtil` and queries `MAX(five_hour_util)`; many `HistoricalDataServiceTests` cover them, so removal belongs in a cleanup story (26.9 or follow-up).
