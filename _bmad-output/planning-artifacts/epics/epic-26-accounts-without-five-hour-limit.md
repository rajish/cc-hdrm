# Epic 26: Support Accounts Without a 5-Hour Limit

**Origin:** Sprint change proposal 2026-11-01 (`_bmad-output/planning-artifacts/sprint-change-proposal-2026-11-01.md`), which supersedes the 2026-10-31 proposal.
**Releases:** `[patch]` 1.6.1 (Story 26.1, published), then `[minor]` 1.7.0 (Story 26.9).
**Functional requirements:** FR61–FR66.

## Goal

Anthropic removed the 5-hour limit only for verified Ultra accounts. Free, Pro and Max keep it. Unverified Ultra accounts have a temporary limit. The app must follow what each account reports, not assume one rule for everyone.

## Design Rules

- **Number present:** the usage response has a 5-hour number. Behave exactly as 1.6.0, including slope, promotion and benchmark.
- **Number missing while connected:** weekly is primary, with pace.
- **Re-evaluate on every poll.** An account can change state when it verifies, so nothing is decided once and stored.
- **Never use a cutover date or plan name to decide this.** Accounts verify at different times.
- **No data loss.** No `DELETE` or `DROP` on historical tables. `five_hour_*` columns stay in active use.
- **Every story keeps or adds a test proving that accounts with a 5-hour number are unchanged.**

**Evidence limit:** only one Ultra account has been observed. No real Pro, Max or unverified Ultra response has been seen.

## Stories

### Story 26.1: Show Weekly When There Is No 5-Hour Number

Released in 1.6.1. `AppState.displayedWindow` returns `.sevenDay` when connected and `fiveHour` is nil. The popover hides the 5-hour ring and the "N full 5h quotas left" line. Files: `cc-hdrm/State/AppState.swift`, `cc-hdrm/App/AppDelegate.swift`, `cc-hdrm/Views/PopoverView.swift`.

### Story 26.2: Weekly Pace When There Is No 5-Hour Number

Reuse `cc-hdrm/Models/WeeklyPace.swift` and its tests from branch `feature/story-26.2-weekly-pace`. Slope remains for accounts with a number, and nothing is deleted.

- Menu bar `↗` only when run-out is projected before the weekly reset.
- Popover line: "On pace" or "Ahead of pace — runs out ~Thu 2:00 PM".

**AC:** with no 5-hour number, pace and run-out match hand-calculated values, and a single 1% step no longer shows "rising". With a number, slope display is unchanged.

### Story 26.3: Weekly-First Popover and Sparkline When There Is No 5-Hour Number

The weekly ring becomes the large primary gauge. The sparkline shows the current weekly cycle with an even-pace line. It replaces the "Open analytics" button shipped in 1.6.1. Files: `cc-hdrm/Views/PopoverView.swift`, `cc-hdrm/Views/SevenDayGaugeSection.swift`, `cc-hdrm/Views/Sparkline.swift`.

**AC:** with no 5-hour number, the popover leads with the weekly gauge. With a number, the rings and the 24-hour sparkline are unchanged.

### Story 26.4: Analytics Charts Adapt to the Data

The 5-hour series is off and hidden when the selected range has no 5-hour data, and works as today otherwise. Per-point slope colouring and reset markers keep working where 5-hour data exists. Files: `cc-hdrm/Views/AnalyticsView.swift`, `cc-hdrm/Views/StepAreaChartView.swift`, `cc-hdrm/Views/BarChartView.swift`, `cc-hdrm/Views/UsageChart.swift`.

**AC:** a 3-month range spanning a state change can still show old 5-hour data. A 24-hour range without 5-hour data shows no 5-hour toggle.

### Story 26.5: Value and Headroom per Weekly Cycle When There Is No 5-Hour Number

A weekly cycle is identified from what was seen when it was recorded: a weekly reset **and** no 5-hour number on the polls around it. An additive nullable column is allowed if needed. Old 5-hour events keep their breakdown. The overlap rule applies only to an account that actually changed state.

Reusable from reverted commit `5993153`: the two-band breakdown and 7-day capacity code. Carried findings are in `_bmad-output/implementation-artifacts/deferred-work.md`.

**AC:** a sleep gap of over 5 hours on an account with a number creates no weekly cycle and drops no real event. A weekly cycle with a 70% peak reports 70% used, 30% unused and a non-zero value.

### Story 26.6: Tier Advice, Patterns and Plan Names

Weekly peak and weekly exhaustion drive advice for accounts without a number. Accounts with a number are unchanged. Show "Max" and "Ultra" names in `cc-hdrm/Models/RateLimitTier.swift`. Advice accounts for Ultra having no 5-hour limit once verified. Confirm the tier string real Ultra accounts report, and keep unknown strings safe.

**Credit table:** do not change values on ratio alone, because credits are unpublished. Show the evidence and ask the maintainer. Max (41.7M) and Ultra (83.3M) weekly match the published 5x and 10x to each other. Pro (5M) does not; those ratios imply about 8.3M. The 5-hour values give Max 6x Pro where 5x is published.

**AC:** with weekly-only history, advice and patterns use non-zero inputs, with no downgrade bias from missing 5-hour peaks.

### Story 26.7: Tokens-per-Percent From Weekly Steps When There Is No 5-Hour Number

Polls with a number keep today's measurement. Polls without one use weekly steps with the 6-hour window. Bases are never averaged together. Backfill follows the same rule per poll.

Reusable from reverted commit `df950ab`: the weekly code and review fixes. Carried findings are in `_bmad-output/implementation-artifacts/deferred-work.md`.

**AC:** the passive engine records measurements from polls without a number. Results from polls with a number match 1.6.0.

### Story 26.8: Hide the Benchmark When There Is No 5-Hour Number

Measure is hidden with a short explanation. Past results stay visible. `cc-hdrm/Services/BenchmarkService.swift` measurement is unchanged for accounts with a number. A weekly benchmark was rejected: the API reports whole percents, so a usable run costs about 8% of the weekly allowance (minimum 2–4%).

**AC:** with no number, a run cannot be started. With a number, the benchmark works as today.

### Story 26.9: Documentation and Minor Release

Update `README.md` and `docs/images/demo.gif` to describe both account states. **This story's PR title carries `[minor]`.**

## Sequencing

26.1 first and released. Then 26.2 → 26.3; 26.4; 26.5 → 26.6; 26.7; 26.8; 26.9 last.

## Success Criteria

- With `five_hour: null` while connected, the menu bar shows weekly headroom and colour, not "—".
- With a 5-hour number, all 1.6.0 behaviour is unchanged, and tests prove it in each story.
- An account that changes state adapts at the next poll without a restart.
- A sleep gap on an account with the limit creates no weekly cycle.
- Accounts without a number get non-zero value, tier and tokens-per-percent results from weekly data.
- No `DELETE` or `DROP` on historical tables.
- 1.7.0 published from Story 26.9.
