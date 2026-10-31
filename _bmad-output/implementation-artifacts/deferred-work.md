# Deferred Work

## Deferred from: code review of 20-3-tpp-data-model-passive-measurement-engine (2026-03-27)

- `Int32` truncation for token counts in `TPPStorageService` — `sqlite3_bind_int(Int32(...))` used for `input_tokens`, `output_tokens`, `cache_create_tokens`, `cache_read_tokens`, `total_raw_tokens`, `message_count` columns. SQLite INTEGER is 64-bit but bind is 32-bit, risking silent data corruption for very large token counts. Pre-existing pattern from `storeBenchmarkResult` in Story 20.1 — fix should apply to all `sqlite3_bind_int` token columns in `TPPStorageService` at the same time.

## Deferred from: code review of 20-5-historical-tpp-backfill (2026-03-27)

- AC-1 progress indicator for app-launch backfill path not implemented — the spec says "a subtle progress indicator appears if the backfill takes >5 seconds" on first launch. The SettingsView button state ("Running...") only covers the manual re-run path, not the automatic fire-and-forget launch-path. Requires UI plumbing in AppDelegate/PopoverView to surface a progress state. Deferred to Story 20.4 or a dedicated polish story.

## Deferred from: code review of spec-21-4-fable-threshold-notifications (2026-08-13)

- Threshold-notification dedup state survives sign-out — `performSignOut` (cc-hdrm/App/AppDelegate.swift:373) clears windows and scoped limits in AppState but never resets `NotificationService`'s `fiveHourThresholdState` / `sevenDayThresholdState` / `scopedThresholdState`. A different account signing in inherits the previous account's warned20/warned5 state, suppressing its first threshold notification until a recovery re-arms the machine. Pre-existing for 5h/7d since Story 5.2; Story 21.4 adds a third machine with the same behavior. Fix would reset all three states on sign-out in one pass.

## Deferred from: code review of spec-26-1-weekly-allowance-menu-bar (2026-11-01)

- `PollingEngine` plan-exhausted rule still counts the 5-hour window — `cc-hdrm/Services/PollingEngine.swift:275` sets `planExhausted` when the 5h window is exhausted, while `AppState.isExtraUsageActive` is now weekly-only. The two rules disagree if a 5-hour value ever returns: extra-usage alerts would fire while the menu bar shows normal headroom. Belongs with the 5h notification cleanup in Story 26.9.

## Deferred from: code review of spec-26-2-weekly-pace-replaces-slope (2026-11-01)

- Run-out time can name today's weekday for next week — `Date.dayTimeString()` (`cc-hdrm/Extensions/Date+Formatting.swift`) shows only weekday and time. A run-out can be up to ~6d 20h away, so on a Monday "Ahead of pace — runs out ~Mon 8:00 AM" means next Monday but reads as today. The reset line ("at Mon 9:00 AM") has the same ambiguity, softened by its relative countdown. Fix: add a date qualifier when the target is 6+ days away, or show a relative run-out. Fits the popover redesign in Story 26.3.
