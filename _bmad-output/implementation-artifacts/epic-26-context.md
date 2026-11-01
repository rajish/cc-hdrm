# Epic 26 Context: Weekly-First Monitoring

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Anthropic retired Claude's 5-hour limit on 2026-10-31. Since 08:03 UTC that day the usage API returns `five_hour: null`. The weekly allowance (`seven_day`) is now the only plan-wide limit. Model-scoped weekly caps (Fable, `limits[]` entries with `kind: "weekly_scoped"`) remain. The app was built around the 5-hour window. Today the menu bar shows "—" and a grey icon while connected. Most analytics show nothing, or silently wrong values (0% used, $0 value, a bias toward downgrade advice). This epic makes the weekly allowance the primary monitored value everywhere: menu bar, popover, pace signal, analytics, value and tier analysis, tokens-per-percent, benchmark, notifications and settings. The whole epic ships as one `[minor]` release (1.6.0 → 1.7.0).

## Stories

- Story 26.1: Weekly Allowance in the Menu Bar
- Story 26.2: Weekly Pace (Replaces Slope)
- Story 26.3: Weekly-First Popover
- Story 26.4: Analytics Charts Weekly-First
- Story 26.5: Value and Headroom Analysis per Weekly Cycle
- Story 26.6: Tier Advice and Subscription Patterns on Weekly Data
- Story 26.7: Tokens-per-Percent on Weekly Deltas
- Story 26.8: Benchmark on Weekly Deltas
- Story 26.9: Notifications, Tier Credits and Settings Cleanup + Release

## Requirements & Constraints

- While connected, the menu bar always shows weekly headroom % and colour, even with `five_hour: null`.
- No UI element may show an empty 5h gauge, 5h copy, or "N full 5h quotas left".
- **No data loss.** No `DELETE` or `DROP` on historical tables, and no schema migration. `five_hour_*` columns stay nullable. Old 5h data stays queryable and viewable.
- **Remove, don't hide.** Delete 5h-only code paths; do not keep them dormant for a returning 5h limit. Decoding must still accept `five_hour` as either null or an object.
- Weekly is the single plan-wide window. No dual-window logic, no promotion rule, and no "effective headroom = min(5h, 7d)".
- Pace and run-out values must match hand-calculated test cases. Cover start of week, mid-week on pace, ahead of pace, missing `resets_at`, and 0% utilization.
- Headroom breakdown, value $, tier advice and tokens-per-percent must give non-zero results from weekly-only data.
- Out of scope: a "will run out before reset" notification.
- Benchmark costs real quota. 1% of the weekly allowance is roughly 8–13× one 5h percent. The run needs a hard spend cap and an up-front estimate the user confirms. If one run would exceed a set share of the weekly allowance, stop and ask the maintainer whether to retire the benchmark instead.
- All tests must pass. Release 1.6.0 is published from the final `[minor]` PR.

## Technical Decisions

- **Weekly pace replaces slope.** It uses only `seven_day.utilization` and `resets_at`. It needs no poll buffer, no history bootstrap and no tier credits. It is recalculated every poll.
  - `weekStart = resetsAt − 7 days`; `elapsed = clamp((now − weekStart) / 7 days, 0…1)`
  - `paceDelta = utilization − elapsed × 100` (positive means spending faster than an even pace)
  - `rate = utilization / (now − weekStart)`; `runOut = now + (100 − utilization) / rate`
  - Run-out is shown only when `runOut < resetsAt` and at least ~4 hours of the week have passed.
  - Known limit: the projection is pessimistic after a heavy first day. Possible upgrade: blend in a recent-window rate.
- AppState holds the weekly window, `scopedLimits` and the pace state. It drops the 5h window, the 5h slope and the displayed-window logic. Popover sparkline data is the set of polls since the last weekly reset. The polling engine refreshes it each poll so the popover opens instantly.
- The slope service, its protocol, the slope level type, the slope indicator view, the slope buffer wiring in the polling engine, and their tests are all deleted.
- **Reset events come from weekly resets.** Primary signal: `seven_day.resets_at` shifts between polls. Fallback: a large utilization drop. On weekly events `five_hour_peak` is NULL. `constrained_credits` is historical only.
- **Two-band headroom per weekly cycle.** Used = weekly peak % (the stored `sevenDayUtil`). Unused = 100% − peak. The "7d-constrained" band is retired. Pre-2026-10-31 events (5h-based) keep their stored breakdown and are never recomputed.
- Value $, cycle utilisation, insight copy, tier fit and subscription-pattern detectors all use weekly cycles and weekly utilisation. Tier fit uses the weekly peak per cycle plus the count of weekly exhaustions. Its extra-usage cost input is unchanged.
- Credit limits are weekly only: Pro 5,000,000; Max 5× 41,666,700; Max 20× 83,333,300. `fiveHourCredits` is removed. A custom tier needs only a weekly value. An old stored 5h preference is ignored, not migrated. An unknown tier falls back to percentage-only display.
- Tokens-per-percent switches to `seven_day` deltas. The `tpp_seven_day` column already exists. Accumulation windows get longer for coarse 1% steps, and confidence thresholds are retuned. Older 5h-based points stay visible, labelled as 5h-based.
- Threshold notifications track the weekly window and each scoped cap independently. The 5h state machine is removed.

## UX & Interaction Patterns

- **Menu bar:** `✳ 83%` normally. It becomes `✳ 58% ↗` only when run-out is projected before reset. When exhausted it shows the weekly countdown `✳ ↻ 3d 4h`, or the extra-usage $ amount when extra usage is enabled. Disconnected shows `✳ —`. The arrow never appears when exhausted or disconnected. The pace glyph is `↗`; the old steep `⬆` is retired. The "7d" promoted label is gone.
- **Gauge-icon corner dot:** shows the Fable weekly cap in its own state colour at caution, warning, critical or exhausted. It is empty when Fable is normal, absent or disconnected. The menu bar number always stays the overall weekly value.
- **Popover order:** large weekly ring (~96px) → "resets in 2d 1h" → "at Thu 9:00 AM" → pace line → hairline → small Fable ring (~56px) → weekly sparkline → footer. The pace line is always visible: "On pace" or "Ahead of pace — runs out ~Thu 14:00".
- **Sparkline:** covers the current weekly cycle, from the last weekly reset to now. It draws an even-pace diagonal from 0% at cycle start to 100% at reset. Clicking it opens analytics.
- **Analytics:** default series are weekly and Fable. The 5h toggle is off by default and hidden when the selected range has no 5h data. Reset markers are dashed vertical lines at weekly resets. No per-point slope or pace colouring. The breakdown bar has two bands: Used (solid) and Unused (light).
- **Notification copy** always names the window, e.g. "Claude headroom at 17% — weekly allowance resets in 2d 1h (Thu 09:00)". A scoped cap uses the model name: "Claude Fable headroom at 18% — …".
- **VoiceOver:** menu bar reads "Claude weekly headroom: 83 percent, normal". The gauge reads "Weekly headroom: 42 percent, ahead of pace, runs out around Thursday 14:00". Popover reading order starts with weekly. Pace is never conveyed by colour alone.
- Benchmark copy: "per 1% of your weekly allowance".

## Cross-Story Dependencies

- Build order: 26.1 first, because it fixes the live menu bar. Then 26.2 → 26.3, because the popover uses pace. Then 26.4–26.8 in order. 26.9 comes last.
- 26.9 depends on 26.5 and 26.6 no longer using 5h credits. It is the only PR whose title carries `[minor]`; earlier story PRs carry no release keyword.
- 26.8 needs the maintainer to approve its spend gate. It unblocks Story 21.5 (Fable), which runs through the benchmark path.
- Codex epics 22–25 planned to reuse Claude's 5h components. Those components become weekly-only after this epic, so the Codex stories must be re-validated before they start. Do not edit them in this epic.
- 26.9 also updates `README.md` and re-records `docs/images/demo.gif`.
