# Epic 26: Weekly-First Monitoring

**Origin:** Sprint change proposal 2026-10-31 (`_bmad-output/planning-artifacts/sprint-change-proposal-2026-10-31.md`)
**Release:** `[minor]` — one release for the whole epic (1.5.1 → 1.6.0)

## Goal

Anthropic retired the Claude 5-hour limit. Since 2026-10-31 08:03 UTC the
`/api/oauth/usage` response returns `five_hour: null`. The weekly allowance
(`seven_day`) is now the only plan-wide limit; model-scoped weekly caps
(Fable, `limits[]` kind `weekly_scoped`) remain. The app was built around
the 5-hour window: the menu bar shows "—" while connected, and most
analytics report nothing or wrong numbers. Make the weekly allowance the
primary monitored value everywhere.

## Design Principles

- **Weekly is the single plan-wide window.** No dual-window logic, no
  promotion rule.
- **No data loss.** `five_hour_*` columns stay nullable. No `DELETE` or
  `DROP` on historical tables. Old 5h data stays viewable.
- **Remove, don't hide.** 5h-only code paths are deleted, not kept dormant.
  Decoding stays tolerant of `five_hour` in either form.
- **Pace over slope.** Weekly data moves in 1% steps; the trend signal
  compares usage with the share of the week elapsed.

## Stories

### Story 26.1: Weekly Allowance in the Menu Bar

Menu bar text, colour and gauge icon always use `seven_day`. Remove
`DisplayedWindow`, the promotion rule, `quotasRemaining` and the "7d"
promoted label (`cc-hdrm/State/AppState.swift`,
`cc-hdrm/App/AppDelegate.swift`, `cc-hdrm/Views/GaugeIcon.swift`). The
gauge-icon corner dot shows the Fable weekly cap at caution, warning,
critical or exhausted. The pace arrow glyph is `↗`. VoiceOver speaks weekly headroom.
**AC:** with `five_hour: null` and a connection, the menu bar shows weekly
headroom % and colour (not "—"); exhausted shows the weekly reset countdown
(`↻ 3d 4h`); extra-usage $ text shows when weekly is exhausted and extra
usage is enabled.

### Story 26.2: Weekly Pace (Replaces Slope)

Pace from `seven_day.utilization` and `resets_at` only:
`weekStart = resetsAt − 7 days`;
`elapsed = clamp((now − weekStart) / 7 days, 0…1)`;
`paceDelta = utilization − elapsed × 100`.
Projected run-out: `rate = utilization / (now − weekStart)`,
`runOut = now + (100 − utilization) / rate`, shown only when
`runOut < resetsAt` and ≥ ~4 hours of the week have passed. Menu bar
appends the actionable arrow only when run-out is before reset. Delete
`cc-hdrm/Services/SlopeCalculationService.swift`, its protocol,
`cc-hdrm/Models/SlopeLevel.swift`, `cc-hdrm/Views/SlopeIndicator.swift`, the
slope wiring in `cc-hdrm/Services/PollingEngine.swift`, and per-point slope
colouring in `cc-hdrm/Views/StepAreaChartView.swift`.
**AC:** pace and run-out values match hand-calculated test cases, including
start of week, mid-week on pace, ahead of pace, missing `resets_at`, and
0% utilization.

### Story 26.3: Weekly-First Popover

Remove the 5h ring (`cc-hdrm/Views/FiveHourGaugeSection.swift`). The weekly
ring becomes the large primary gauge with countdown and pace line. Remove
"N full 5h quotas left" (`cc-hdrm/Views/SevenDayGaugeSection.swift`). Fable
section stays below. Sparkline (`cc-hdrm/Views/Sparkline.swift`) shows the
current weekly cycle with an even-pace diagonal. VoiceOver order starts
with weekly.
**AC:** no empty 5h gauge or 5h copy in the popover; sparkline renders
from weekly polls since the last weekly reset.

### Story 26.4: Analytics Charts Weekly-First

Default series weekly + Fable. 5h series off by default and hidden when
the selected range has no 5h data. Reset markers from weekly resets.
Files: `cc-hdrm/Views/AnalyticsView.swift`,
`cc-hdrm/Views/StepAreaChartView.swift`, `cc-hdrm/Views/BarChartView.swift`,
`cc-hdrm/Views/UsageChart.swift`.
**AC:** a 3-month range spanning 2026-10-31 can still show old 5h data when
toggled on; a 24h range after the cutover shows no 5h toggle.

### Story 26.5: Value and Headroom Analysis per Weekly Cycle

`ResetEvent` analysis keyed on weekly resets, using the stored
`sevenDayUtil` peak. Breakdown becomes two bands: used vs unused weekly
capacity; "7d-constrained" retired. Value $, cycle utilisation and insight
copy rebased on weekly cycles. Old 5h-based events keep their breakdown.
Files: `cc-hdrm/Services/HeadroomAnalysisService.swift`,
`cc-hdrm/Models/HeadroomBreakdown.swift`,
`cc-hdrm/Views/HeadroomBreakdownBar.swift`,
`cc-hdrm/Services/SubscriptionValueCalculator.swift`,
`cc-hdrm/Services/ValueInsightEngine.swift`,
`cc-hdrm/Services/CycleUtilizationCalculator.swift`,
`cc-hdrm/Services/HistoricalDataService.swift`.
**AC:** a weekly cycle with 70% peak reports 70% used / 30% unused and a
non-zero value $; no 0%/$0 results from weekly-only data.

### Story 26.6: Tier Advice and Subscription Patterns on Weekly Data

Tier fit uses weekly peak per cycle and count of weekly exhaustions (extra
usage cost unchanged). Usage-decay and forgotten-subscription detectors use
weekly utilisation. Files:
`cc-hdrm/Services/TierRecommendationService.swift`,
`cc-hdrm/Services/SubscriptionPatternDetector.swift`.
**AC:** with weekly-only history, recommendations and patterns use
non-zero weekly inputs; no downgrade bias from missing 5h peaks.

### Story 26.7: Tokens-per-Percent on Weekly Deltas

Passive engine, backfill and charts switch to `seven_day` deltas
(`tpp_seven_day` already stored). Longer accumulation window for 1% weekly
steps; confidence thresholds retuned. Charts read `tppSevenDay`; older
5h-based points stay visible, labelled as 5h-based. Files:
`cc-hdrm/Services/PassiveTPPEngine.swift`,
`cc-hdrm/Services/HistoricalTPPBackfillService.swift`,
`cc-hdrm/Services/TPPChartDataService.swift`,
`cc-hdrm/Services/TPPStorageService.swift`.
**AC:** passive engine records measurements from weekly-only polls.

### Story 26.8: Benchmark on Weekly Deltas

`cc-hdrm/Services/BenchmarkService.swift` measures the weekly delta. UI
copy in `cc-hdrm/Views/BenchmarkSectionView.swift`: "per 1% of your weekly
allowance". Hard spend cap; up-front estimate of weekly allowance used,
confirmed by the user before the run.
**Gate:** if one run would exceed a set share of the weekly allowance,
stop and ask the maintainer whether to retire the benchmark instead.
Unblocks 21.5.

### Story 26.9: Notifications, Tier Credits and Settings Cleanup + Release

Remove the 5h threshold state machine and notifications
(`cc-hdrm/Services/NotificationService.swift`); copy names the weekly
window. Drop `fiveHourCredits` from `cc-hdrm/Models/RateLimitTier.swift`;
custom tier needs only the weekly credit value. Remove the "5-hour credit
limit" field from `cc-hdrm/Views/SettingsView.swift` and
`cc-hdrm/Services/PreferencesManager.swift` (old stored value ignored).
Update `README.md` (lines 21, 28, 31, 42, 104) and re-record
`docs/images/demo.gif`.
**This story's PR title carries `[minor]`.**

## Sequencing

26.1 first (fixes the live menu bar). 26.2 → 26.3 (popover uses pace).
26.4–26.8 in order. 26.9 last: 26.5 and 26.6 must stop using 5h credits
first, and it carries the release keyword. Story 21.5 waits for 26.8.
Codex epics 22–25 are re-validated before they start: shared components
are weekly-only after this epic.

## Success Criteria

- Menu bar shows weekly headroom and colour while connected with
  `five_hour: null`.
- No UI element shows an empty 5h gauge, 5h copy or "5h quotas left".
- Pace and run-out projection match hand-calculated values in tests.
- Headroom breakdown, value $, tier advice and TPP produce non-zero results
  from weekly data.
- No `DELETE` or `DROP` on historical tables.
- All tests pass; release 1.6.0 published from the `[minor]` PR.
