# Deferred Work

## Deferred from: code review of 20-3-tpp-data-model-passive-measurement-engine (2026-03-27)

- `Int32` truncation for token counts in `TPPStorageService` — `sqlite3_bind_int(Int32(...))` used for `input_tokens`, `output_tokens`, `cache_create_tokens`, `cache_read_tokens`, `total_raw_tokens`, `message_count` columns. SQLite INTEGER is 64-bit but bind is 32-bit, risking silent data corruption for very large token counts. Pre-existing pattern from `storeBenchmarkResult` in Story 20.1 — fix should apply to all `sqlite3_bind_int` token columns in `TPPStorageService` at the same time.

## Deferred from: code review of 20-5-historical-tpp-backfill (2026-03-27)

- AC-1 progress indicator for app-launch backfill path not implemented — the spec says "a subtle progress indicator appears if the backfill takes >5 seconds" on first launch. The SettingsView button state ("Running...") only covers the manual re-run path, not the automatic fire-and-forget launch-path. Requires UI plumbing in AppDelegate/PopoverView to surface a progress state. Deferred to Story 20.4 or a dedicated polish story.

## Deferred from: code review of spec-21-4-fable-threshold-notifications (2026-08-13)

- Threshold-notification dedup state survives sign-out — `performSignOut` (cc-hdrm/App/AppDelegate.swift:373) clears windows and scoped limits in AppState but never resets `NotificationService`'s `fiveHourThresholdState` / `sevenDayThresholdState` / `scopedThresholdState`. A different account signing in inherits the previous account's warned20/warned5 state, suppressing its first threshold notification until a recovery re-arms the machine. Pre-existing for 5h/7d since Story 5.2; Story 21.4 adds a third machine with the same behavior. Fix would reset all three states on sign-out in one pass.

## Deferred from: code review of spec-26-1-weekly-allowance-menu-bar (2026-11-01) — SUPERSEDED, code reverted

- `PollingEngine` plan-exhausted rule still counts the 5-hour window — `cc-hdrm/Services/PollingEngine.swift:275` sets `planExhausted` when the 5h window is exhausted, while `AppState.isExtraUsageActive` is now weekly-only. The two rules disagree if a 5-hour value ever returns: extra-usage alerts would fire while the menu bar shows normal headroom. Belongs with the 5h notification cleanup in Story 26.9.

## Deferred from: code review of spec-26-7-tpp-weekly-deltas (2026-11-01) — SUPERSEDED, re-check when rebuilding Story 26.7

- source_spec: `_bmad-output/implementation-artifacts/spec-26-7-tpp-weekly-deltas.md`
  summary: Existing users get no automatic weekly TPP backfill after upgrade; `runBackfillIfNeeded` skips because `tppBackfillCompleted` is already true or old backfill rows exist.
  evidence: `cc-hdrm/Services/HistoricalTPPBackfillService.swift` `runBackfillIfNeeded` fast/slow paths; weekly backfill only runs via Settings "Re-run TPP Backfill".
- source_spec: `_bmad-output/implementation-artifacts/spec-26-7-tpp-weekly-deltas.md`
  summary: Weekly reset detection in passive TPP relies on a utilization drop; a reset followed by a rise within one poll interval goes unnoticed.
  evidence: `cc-hdrm/Services/PollingEngine.swift` builds the current `UsagePoll` with `sevenDayResetsAt: nil`, so the engine cannot compare reset timestamps; fixing it touches PollingEngine (Story 26.2 territory).

## Deferred from: code review 2 of spec-26-7-tpp-weekly-deltas (2026-11-01) — SUPERSEDED, re-check when rebuilding Story 26.7

- Benchmark insight text and weighting ratios (`cc-hdrm/Services/TPPChartDataService.swift` `computeInsightText`, `sameBasisRatio`) prefer `tppSevenDay` without checking `fiveHourDelta`, and the 30-day average comes from `TPPStorageService.getAverageTPP`, which averages all rows. Harmless today (all benchmark rows are 5h-era, so both sides are the same quantity), but once Story 26.8 stores weekly-era benchmark rows, the average will mix eras. Fix with 26.8: average only rows where `fiveHourDelta == nil` (same rule as `chartValue`).
- First backfill row of each 24-hour run starts at the first poll, not at a weekly step, so its token window is partial and TPP is understated. Row is `low` confidence unless delta is 2% or more. Fix would skip the first unanchored step.
- Integer weekly percents: a single 1% step carries up to ±100% quantisation error and a 2% step ±50%. Daily and weekly chart averages smooth this; the day view shows raw points. If medium confidence at 2% proves too optimistic, raise `mediumConfidenceDelta` to 3 in `PassiveTPPEngine` and `HistoricalTPPBackfillService`.
- Chart plots 5h-based and weekly values on one Y axis although their magnitudes differ about 10x; old 5h-based points sit near the bottom. Separate axis or a toggle is a UX decision.

## Deferred from: code review of spec-26-5-value-headroom-per-weekly-cycle (2026-11-01) — SUPERSEDED, re-check when rebuilding Story 26.5

- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-per-weekly-cycle.md`
  summary: `CycleUtilizationCalculator` groups events by calendar month or billing cycle before aggregating, so legacy events and the first weekly cycle that land in different groups are not de-duplicated, and a weekly cycle is assigned wholly to the month of its reset.
  evidence: overlap exclusion (`ResetEvent` array `excludingWeeklyOverlap`) runs per call on the events it is given; the cycle chart passes per-month groups.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-per-weekly-cycle.md`
  summary: A weekly cycle whose event tier does not resolve is skipped by `aggregateBreakdown` but still counted in `periodDays`, understating utilisation. A `.month` range can hold 5 weekly cycles (35 days of capacity and price); the weekly count is not capped by the range.
  evidence: `periodDays` has no tier information; `SubscriptionValueCalculator.calculate` divides summed used credits by `periodDays`. Needs a tier-aware capacity input or a single shared "countable events" rule.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-per-weekly-cycle.md`
  summary: 5h reset detection branches and `getRecentPeakUtilization` in `cc-hdrm/Services/HistoricalDataService.swift` are dead since `five_hour` is null; remove per the "remove, don't hide" principle.
  evidence: Detection still checks `fiveHourResetsAt`/`fiveHourUtil` and queries `MAX(five_hour_util)`; many `HistoricalDataServiceTests` cover them, so removal belongs in a cleanup story (26.9 or follow-up).
## Deferred from: code review of spec-26-1-no-five-hour-fallback (2026-11-01)

- source_spec: `_bmad-output/implementation-artifacts/spec-26-1-no-five-hour-fallback.md`
  summary: A window object with null utilization, such as `"five_hour": {"utilization": null}`, becomes 0% used, so the app shows a false 100% headroom instead of treating it as no number.
  evidence: `cc-hdrm/Services/PollingEngine.swift:229,235` map with `utilization ?? 0.0`. This shape has not been observed; the proposal lists unobserved Pro, Max and unverified Ultra responses as its main risk. Changing it would alter 1.6.0 behaviour, so it needs its own decision.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-1-no-five-hour-fallback.md`
  summary: A 5-hour account with a promoted, exhausted weekly window hears the reset in thousands of minutes on VoiceOver, while the menu bar shows days and hours.
  evidence: `cc-hdrm/App/AppDelegate.swift` keeps the minutes wording for accounts with a 5-hour number under the unchanged-behaviour rule; it is existing 1.6.0 wording.

## Carried from: review of the Epic 26 revert (2026-11-01)

These findings came from the reverted code. Apply them when the stories are rebuilt.

- Story 26.5: `cc-hdrm/Services/HeadroomAnalysisService.swift:79` skipped weekly-only resets, `:89` should keep stored credits when the tier is unresolved, and `:29` should clamp utilization.
- Story 26.7: `cc-hdrm/Services/HistoricalTPPBackfillService.swift:217` overlaps with passive measurements. `cc-hdrm/Services/PassiveTPPEngine.swift:49` and `:86` can use stale windows.
- Story 26.7, also in released 1.6.0: `cc-hdrm/Services/TPPStorageService.swift:217` force re-run deletes all backfill rows but rebuilds only recent ones.
- Not tied to a story: `cc-hdrm/Services/ValueInsightEngine.swift:92` says "today" on a rolling 24 hours. `cc-hdrm/State/AppState.swift:138` treats a missing weekly value as 0%.

## Deferred from: review of the Epic 26 plan correction (2026-11-01)

Both are older drift in text restored unchanged. Neither blocks Epic 26.

- `_bmad-output/planning-artifacts/architecture.md` API Response Mapping example lists `sevenDaySonnet` and omits `limits`. `cc-hdrm/Models/UsageResponse.swift` is the source of truth.
- `_bmad-output/planning-artifacts/ux-design-specification.md` "Popover structure" says the gauges sit side by side, while the chosen direction in the same file stacks them vertically.

## Deferred from: build of Story 26.2 (2026-11-01)

- source_spec: `_bmad-output/implementation-artifacts/spec-26-2-weekly-pace-no-five-hour.md`
  summary: Decide whether the weekly arrow needs a margin around even pace.
  evidence: After hour 4 the arrow shows exactly when usage is over even pace, so an even spender sees it after each 1% step and it clears about 1.7 hours later.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-2-weekly-pace-no-five-hour.md`
  summary: Decide what the pace line says for heavy use in the first 4 hours of the week.
  evidence: `cc-hdrm/Models/WeeklyPace.swift` gives no run-out before hour 4, so 90% used after 3 hours reads "On pace".

## Deferred from: code review of spec-26-2-weekly-pace-no-five-hour (2026-11-01)

- source_spec: `_bmad-output/implementation-artifacts/spec-26-2-weekly-pace-no-five-hour.md`
  summary: Confirm that only a missing `five_hour` object means "no 5-hour number", on a real Pro, Max or unverified Ultra response.
  evidence: `cc-hdrm/Services/PollingEngine.swift` turns `five_hour: {"utilization": null}` into a 0% window, so the account counts as having a number. An idle account that reports `five_hour: null` would flip to weekly pace until its next 5-hour window opens. Only one real response has been seen.

## Deferred from: build of Story 26.3 (2026-11-01)

- source_spec: `_bmad-output/implementation-artifacts/spec-26-3-weekly-first-popover-no-five-hour.md`
  summary: Check that VoiceOver's double-tap opens analytics from the 24-hour sparkline.
  evidence: `cc-hdrm/Views/Sparkline.swift` marks that chart as a button with no accessibility action, and its tap handling lives in `cc-hdrm/Views/InteractionOverlay.swift`. The weekly chart got an explicit action, while the 24-hour chart was left unchanged by rule. It has not been tried with VoiceOver.

## Deferred from: code review of Story 26.3 (2026-11-01)

- source_spec: `_bmad-output/implementation-artifacts/spec-26-3-weekly-first-popover-no-five-hour.md`
  summary: Decide whether the weekly chart should need one unbroken hour of data, or one hour of data in total.
  evidence: `SparklinePathBuilder.hasDrawableWeeklyData` in `cc-hdrm/Views/Sparkline.swift` checks one unbroken run of at least 60 minutes. A laptop used in short sessions, each under an hour with sleep between, shows the "Open analytics" link all week despite days of history. This is what the spec asks for; the maintainer should confirm it suits real use.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-3-weekly-first-popover-no-five-hour.md`
  summary: Decide whether an unavailable database should count as a failed weekly chart load.
  evidence: `HistoricalDataService.getRecentPolls` and `getRolledUpData` return empty lists, not errors, when the database is unavailable. The engine then marks the cycle as loaded with only the current poll and builds the chart in memory. The database is only made available at launch, so it never recovers within a session.

## Deferred from: CodeRabbit review of Story 26.3 (2026-11-01)

- `usage_polls` and `usage_rollups` have no account key. After signing in to another account, history from the previous account can appear in the weekly chart. The 24-hour sparkline and analytics already share this limit, so a fix means a schema change across all history.
- A poll finishing during a weekly history load is not added to the chart until the next poll. A run just over an hour can be measured slightly short after 5-minute thinning. Both correct themselves.

## Deferred from: build of Story 26.4 (2026-11-01)

- source_spec: `_bmad-output/implementation-artifacts/spec-26-4-analytics-adapt-to-data.md`
  summary: Tie analytics chart data to the range it was loaded for.
  evidence: `AnalyticsView` changes `selectedTimeRange` at once, but `chartData` and `rollupData` stay from the old range until a load finishes. `loadData` has no check after its fetch returns, so an older load finishing last can leave the old range's data on screen. Since Story 26.4, a weekly chip press in that window can also be stored against the wrong rule. It only affects accounts whose ranges differ, and the next successful load corrects the chart.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-4-analytics-adapt-to-data.md`
  summary: Decide whether the 24-hour 5-hour line should break where the number is missing.
  evidence: `StepAreaChartView` filters out nil 5-hour points without starting a new segment. If an account goes from number to none and back with no time gap, the line runs across the missing stretch. The project's design calls for honest breaks. This already applied before Story 26.4 and needs an account that changes state twice in 24 hours.

## Deferred from: code review of spec-26-4-analytics-adapt-to-data (2026-11-01)

- source_spec: `_bmad-output/implementation-artifacts/spec-26-4-analytics-adapt-to-data.md`
  summary: Clear the weekly press made while 5-hour was hidden when 5-hour data returns.
  evidence: `AnalyticsView.SeriesVisibility.sevenDayWhileFiveHourHidden` is cleared only by a weekly press in a range that has 5-hour data. If a range shows 5-hour data and later loses it again, the old press applies again. It needs an account that regains and then loses a number in the same open window, and the next weekly press fixes it.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-4-analytics-adapt-to-data.md`
  summary: A user with a number could see the 5-hour chip vanish if every poll in a range lacks it.
  evidence: The rule follows the data, as specified. If a 5-hour account's API ever returns no 5-hour value for a whole 24 hours (for example an idle window), the chip hides and returns on the first poll that has one. Stored choices are kept. Check against real Pro and Max responses when they are available.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-4-analytics-adapt-to-data.md`
  summary: The 5-hour chip shows for a moment on window open for accounts with no number.
  evidence: The empty first frame keeps today's controls by design, so the chip appears until the first load ends, then the row shifts. Fix by hiding the whole chip row until the first load completes, if the shift is judged distracting.

## Deferred from: build of Story 26.5 (2026-11-01)

- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-weekly-cycle-no-five-hour.md`
  summary: Test runs still launch the real app startup as their host, including the log scan. The database is now redirected to a temporary folder under test.
  evidence: `cc-hdrm/App/AppDelegate.swift` runs `ClaudeCodeLogParser` under test, which reads Claude Code logs and can write `log-scan-state.json` in the real Application Support folder. Before the database redirect, test runs applied schema version 9 to the maintainer's real `usage.db`; integrity check passed and no rows changed.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-weekly-cycle-no-five-hour.md`
  summary: Confirm the tier string verified Ultra accounts report before Story 26.6 maps it.
  evidence: `cc-hdrm/Models/RateLimitTier.swift` knows only Pro, Max 5x and Max 20x. If Ultra reports another string with no custom limits, its weekly rows are flagged with no credits, the aggregate skips them, and the bar says the tier is unknown. Mapping the string later makes those rows countable without rewriting them.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-weekly-cycle-no-five-hour.md`
  summary: A weekly cycle that cannot be analysed still removes the 5-hour events in its 7 days.
  evidence: `excludingWeeklyOverlap()` in `cc-hdrm/Models/ResetEvent.swift` has no tier information. A Max account that verifies onto an unmapped string loses that week from percentage figures until the string is mapped. Also, an all-unanalysable list shows 0% when current limits resolve, and the 14-day gate in `ValueInsightEngine.weekInsight` still counts such cycles.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-weekly-cycle-no-five-hour.md`
  summary: Decide what the 24-hour range and the wait for the first weekly reset should say on an account with no number.
  evidence: The 24-hour range reads "No reset events in this period" about 6 days in 7, because a cycle is only recorded when it ends. Every range reads the same until the first reset after upgrade, since rows from 1.6.1 stay unflagged.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-weekly-cycle-no-five-hour.md`
  summary: A light weekly cycle goes unrecorded if the weekly reset time becomes blank when usage returns to 0.
  evidence: The fallback in `HistoricalDataService.detectAndRecordResetIfNeeded` needs a drop of 50 points, so 30% to blank records nothing. The shape is unobserved, and changing it unguarded would alter 1.6.0 detection.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-weekly-cycle-no-five-hour.md`
  summary: Migrations before version 9 can fail forever if the app stops between an `ALTER` and the version write.
  evidence: `DatabaseManager.runMigrations` writes the version once at the end, with no transaction. The version 9 step checks for its column; earlier steps do not.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-weekly-cycle-no-five-hour.md`
  summary: Test cleanup helpers delete the whole system temporary directory, which can disturb other tests running at the same time.
  evidence: `cleanup` in `cc-hdrmTests/Services/HistoricalDataServiceTests.swift` removes `path.deletingLastPathComponent()`, and that path is `FileManager.default.temporaryDirectory`.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-weekly-cycle-no-five-hour.md`
  summary: Re-check of the deferred items from the reverted spec. Grouping before overlap and uncapped 5-cycle pricing are fixed, and unanalysable cycles no longer add capacity in value figures. A cycle still belongs wholly to the month of its reset, by choice. The 5-hour detection branches are live again, so that removal item no longer applies.
  evidence: See Design Notes in the source spec.

## Deferred from: code review of Story 26.5 (2026-11-01)

- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-weekly-cycle-no-five-hour.md`
  summary: Maintainer decision: how long without a 5-hour number makes a weekly reset a weekly cycle. Today it is the 5 hours before the reset plus the polls either side.
  evidence: `HistoricalDataService.detectAndRecordResetIfNeeded` flags a cycle when polls show no number for 5 hours. If a Pro or Max account's API answer drops `five_hour` while idle, an idle weekend flags a false cycle, and `excludingWeeklyOverlap()` then drops that week's real 5-hour events. No such response has been observed. Requiring no number for the whole cycle would close this and cost one week of delay for an account that verifies mid-week.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-weekly-cycle-no-five-hour.md`
  summary: `five_hour: {"utilization": null, "resets_at": null}` is stored as no number but the app treats it as a 0% number.
  evidence: `PollingEngine.fetchUsageData` maps it with `utilization ?? 0.0`, while `persistPoll` stores both columns empty and `hasNoFiveHourWindow` reads that as no number. The shape is unobserved. Fixing it needs a stored marker or a decision to store 0.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-weekly-cycle-no-five-hour.md`
  summary: Any fall in weekly usage with a reset time that moves by over 60 seconds counts as a real weekly reset.
  evidence: The second arm in `detectAndRecordResetIfNeeded` has no size threshold. Observed jitter is about 1 second, so it is unlikely, but a 1-point correction with a 2-minute shift would record a false cycle.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-weekly-cycle-no-five-hour.md`
  summary: Before releasing, check that the maintainer's own `usage.db` has `reset_events.is_weekly_cycle` as `INTEGER`. A test run already moved it to version 9.
  evidence: Version 9 databases skip the migration, so a column with another name or type would not be repaired. Read-only check: `PRAGMA table_info(reset_events)`.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-5-value-headroom-weekly-cycle-no-five-hour.md`
  summary: Each test run leaves a temporary folder from the database redirect.
  evidence: `DatabaseManager.init()` under test creates a new folder in the system temporary directory and nothing removes it.

## Deferred from: CodeRabbit review of Story 26.5 (2026-11-01)

All need a weekly cycle on an unmapped tier, or an account that changed state or plan. Re-check them once Story 26.6 confirms the real Ultra tier string.

- `ResetEvent.excludingWeeklyOverlap` removes 5-hour events before a weekly cycle that later cannot be analysed. The figures correct themselves once the tier maps.
- `AnalyticsView.showsFullBar` and `AnalyticsView.computeDataSpanHours` count weekly cycles that `aggregateBreakdown` skips, so a range of unanalysable cycles from an older unmapped tier can show a 0% bar.
- `ResetEvent.fiveHourSpanMs` subtracts weekly cycles under 7 days apart twice. This needs a reset that moved earlier on an account that changed state.
- `SubscriptionValueCalculator.calculate` divides stored weekly credits by the current tier's capacity, so a weekly cycle recorded before a plan change is scaled. 5-hour aggregation already uses the current tier's capacity.
- `HistoricalDataService` classification ignores a poll inside the 5-hour lookback that has a 5-hour reset time but no utilization. This shape has not been observed.


## Deferred from: Story 26.6 (2026-11-01)

The real tier string for verified Ultra accounts is still not confirmed, so the "Re-check" note on the Story 26.5 list above still stands.

- source_spec: `_bmad-output/implementation-artifacts/spec-26-6-tier-advice-patterns-plan-names.md`
  summary: A forgotten-subscription finding on an unknown tier with no custom price reads "That's $0/mo".
  evidence: `SubscriptionPatternDetector.detectForgottenSubscription` falls back to a cost of 0, and `PatternFinding.summary` prints it. It is 1.6.0 behaviour, but accounts with no 5-hour number can now reach it.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-6-tier-advice-patterns-plan-names.md`
  summary: An unknown `organization_type` is dropped without being logged.
  evidence: `ProfileResponse.Organization.subscriptionTypeDisplay` returns nil for anything other than pro, max, enterprise or team. The value Ultra accounts report is unconfirmed, and the footer falls back to the stored type.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-6-tier-advice-patterns-plan-names.md`
  summary: Advice and patterns scale old percentages by the current plan's credits, so a plan change distorts peaks and decay.
  evidence: `TierRecommendationService.calculatePeakCredits` and `SubscriptionPatternDetector.detectChronicOverpaying` use only the current tier. 1.6.0 does the same for 5-hour peaks. A Pro account at 90% that moves to Max reads as 90% of Max.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-6-tier-advice-patterns-plan-names.md`
  summary: Usage decay treats months with no weekly cycle as if they were not there.
  evidence: `SubscriptionPatternDetector.monthlyWeeklyCyclePeaks` averages recorded cycles only, and an idle account may record none. Months either side of a gap compare as adjacent. 1.6.0 rollups have the same gap behaviour.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-6-tier-advice-patterns-plan-names.md`
  summary: The week an account loses its number can read as low for the forgotten-subscription finding.
  evidence: `detectForgottenSubscription` uses the 5-hour average for any week holding a 5-hour value, which keeps 1.6.0 results when one poll is missing its number. A few low polls followed by heavy weekly use in that same week read as low, until the next week.
- source_spec: `_bmad-output/implementation-artifacts/spec-26-6-tier-advice-patterns-plan-names.md`
  summary: An Ultra account that still has a 5-hour number is compared against an 11M limit, which may not match its temporary limit.
  evidence: `RateLimitTier.max20x.fiveHourCredits` applies on the 1.6.0 path, which must not change. The size of the temporary limit is not published.

## Deferred from: code review of spec-26-6-tier-advice-patterns-plan-names (2026-11-01)

The `$0/mo` forgotten-subscription item above was fixed in this review: the summary now omits the price when it is unknown.

- **Maintainer decision.** The whole-week downgrade bound is safe but almost never lets a downgrade through. It compares one 7-day total with a single 5-hour limit, so only an Ultra account at about 3.3% of its weekly allowance (about 0.55% for Pro) earns "Consider Max". That is already the forgotten-subscription range. Accounts at 5% to 40% of Ultra's weekly allowance fit Max's weekly allowance and get "Ultra is a good fit", which asserts more than the data can show. Options: (1) take the largest rise in weekly use across any 5-hour stretch of stored polls and compare it with the cheaper plan's 5-hour credits; (2) judge by weekly use only and word the card as "Max's 5-hour limit cannot be checked"; (3) keep the strict bound. Option 1 uses data already stored.
- A numbered account whose history holds one weekly cycle (for example a short gap in the 5-hour number) has every cheaper plan blocked by that cycle for the whole selected range, even though 5-hour peaks now exist. 1.6.0 would have judged it from the 5-hour peaks. Safe, but stricter than 1.6.0 for that account.
- The footer shows the raw lowercase `max` for a consumer account whose tier string is unknown. That is likely the state of a verified Ultra account until its real string is confirmed.
