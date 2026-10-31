# Epic 26 Context: Weekly-First Monitoring

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Anthropic retired the Claude 5-hour limit. Since 2026-10-31 08:03 UTC the usage API returns `five_hour: null`; the weekly allowance (`seven_day`) is the only plan-wide limit, and model-scoped weekly caps (Fable) remain. The app was built around the 5-hour window, so the menu bar shows "—" while connected and most analytics report nothing or wrong numbers. This epic makes the weekly allowance the primary monitored value everywhere, shipped as one `[minor]` release (1.5.1 → 1.6.0).

## Stories

- Story 26.1: Weekly allowance in the menu bar
- Story 26.2: Weekly pace (replaces slope)
- Story 26.3: Weekly-first popover
- Story 26.4: Analytics charts weekly-first
- Story 26.5: Value and headroom analysis per weekly cycle
- Story 26.6: Tier advice and subscription patterns on weekly data
- Story 26.7: Tokens-per-percent on weekly deltas
- Story 26.8: Benchmark on weekly deltas
- Story 26.9: Notifications, tier credits and settings cleanup + release

## Requirements & Constraints

- Weekly is the single plan-wide window. No dual-window logic, no promotion rule.
- No data loss: `five_hour_*` columns stay nullable; no `DELETE` or `DROP` on historical tables; old 5h data stays viewable.
- Remove, don't hide: 5h-only code paths are deleted, not kept dormant. Decoding stays tolerant of `five_hour` in either form.
- Pace over slope: weekly data moves in 1% steps; the trend signal compares usage with the share of the week elapsed.
- Success: menu bar shows weekly headroom while `five_hour: null`; no empty 5h gauge or 5h copy; pace/run-out match hand-calculated tests; headroom breakdown, value $, tier advice and TPP are non-zero from weekly data; all tests pass.

## Technical Decisions

- Reset events now arrive about weekly (detected via `seven_day.resets_at` shift) with `five_hour_peak` NULL; `seven_day_util` holds the pre-reset weekly value.
- Headroom analysis per weekly cycle: `used = 7d_peak% × weekly credits`, `unused = rest`. The "7d-constrained" band is retired. Pre-cutover 5h-based events still display for their period and are not recomputed.
- Weekly credits per tier: Pro 5,000,000; Max 5× 41,666,700; Max 20× 83,333,300. `fiveHourCredits` is dropped in 26.9, so 26.5 and 26.6 must stop using it first.
- Pace: `weekStart = resetsAt − 7d`, `elapsed = clamp((now − weekStart)/7d, 0…1)`, `paceDelta = util − elapsed × 100`; run-out projected from average rate since reset, shown only when before reset and ≥ ~4h into the week.
- TPP and benchmark measure `seven_day` deltas (`tpp_seven_day` already stored); benchmark has a hard spend cap and user-confirmed estimate.

## UX & Interaction Patterns

- Popover: weekly ring is the large primary gauge with countdown and pace line; Fable section below; sparkline shows the current weekly cycle with an even-pace diagonal.
- Analytics: default series weekly + Fable; 5h series off by default and hidden when the range has no 5h data.
- Headroom breakdown bar: two bands (used, unused weekly capacity). "No reset events in this period" when empty. 24h/7d views usually show at most one weekly reset.

## Cross-Story Dependencies

- 26.1 first; 26.2 → 26.3; 26.4–26.8 in order; 26.9 last and carries `[minor]`.
- Story 21.5 waits for 26.8. Codex epics 22–25 are re-validated before they start.
