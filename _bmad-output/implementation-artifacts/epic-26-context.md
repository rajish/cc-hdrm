# Epic 26 Context: Support Accounts Without a 5-Hour Limit

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Anthropic removed the 5-hour limit only for verified Ultra accounts. Free, Pro and Max keep it. The usage API's `five_hour` value is present or null per account, and it can change when an account verifies. Version 1.6.1 already shows weekly headroom in the menu bar when the number is missing. This epic completes the experience for those accounts and must not change anything for accounts with a number.

Source of stories and acceptance criteria: `_bmad-output/planning-artifacts/epics/epic-26-accounts-without-five-hour-limit.md`.

## Requirements & Constraints

- **Number present:** behave exactly as 1.6.0. Every story keeps or adds a test proving it.
- **Number missing while connected:** weekly is primary, with pace.
- Re-evaluate on every poll. Never decide from a cutover date, an empty peak alone, or a plan name.
- No `DELETE` or `DROP` on historical tables. Additive nullable columns are allowed.
- Only one Ultra account has been observed. No real Pro, Max or unverified Ultra response has been seen, so parsing must tolerate either form.
- Earlier story PRs carry no release keyword. Only Story 26.9's title carries `[minor]`.

## Technical Decisions

- **Pace:** `cc-hdrm/Models/WeeklyPace.swift`, reused from branch `feature/story-26.2-weekly-pace`. It needs only weekly utilization and reset time.
  - `weekStart = resetsAt − 7 days`; `elapsed = clamp((now − weekStart) / 7 days, 0…1)`
  - `paceDelta = utilization − elapsed × 100`
  - `rate = utilization / (now − weekStart)`; `runOut = now + (100 − utilization) / rate`
  - Run-out shows only when it falls before the reset and at least 4 hours of the week have passed.
- **Weekly cycle:** a weekly reset **and** no 5-hour number on the polls around it. A sleep gap on an account with the limit must not create one.
- **Tokens-per-percent:** chosen per poll. Bases are never averaged together.
- **Benchmark:** Measure hidden with no number. Measurement code unchanged.
- **Slope:** stays for accounts with a number. Nothing is deleted.

## UX & Interaction Patterns (no 5-hour number only)

- **Menu bar:** weekly percent with its colour and the "7d" label. `↗` only when run-out is before the reset. Exhausted shows `↻ 3d 4h`, or the extra-usage amount when enabled.
- **Popover order:** large weekly ring, reset time, pace line, Fable ring, weekly sparkline, footer.
- **Pace line:** "On pace" or "Ahead of pace — runs out ~Thu 2:00 PM". Never colour alone.
- **Sparkline:** the current weekly cycle, with an even-pace line from 0% at the cycle start to 100% at reset.
- **Analytics:** the 5-hour series is off and hidden when the range has no 5-hour data.

## Cross-Story Dependencies

- Order: 26.2 → 26.3; 26.4; 26.5 → 26.6; 26.7; 26.8; 26.9 last.
- Reverted code is reusable from git history: Story 26.5 in `5993153`, Story 26.7 in `df950ab`.
- Carried review findings are in `_bmad-output/implementation-artifacts/deferred-work.md`.
- Codex epics 22–25 can still reuse the 5-hour components.
