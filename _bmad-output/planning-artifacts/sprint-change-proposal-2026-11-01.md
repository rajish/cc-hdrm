# Sprint Change Proposal: Follow Each Account's Limits (Supersedes 2026-10-31)

**Date:** 2026-11-01
**Supersedes:** `_bmad-output/planning-artifacts/sprint-change-proposal-2026-10-31.md`
**Category:** Misunderstanding of a platform change
**Status:** APPROVED 2026-11-01 (maintainer)
**Releases:** `[patch]` 1.6.0 → 1.6.1 (Story 26.1), then `[minor]` 1.6.1 → 1.7.0 (Story 26.9)
**Review mode:** Batch

---

## 1. Issue Summary

The 2026-10-31 proposal assumed Anthropic removed the 5-hour limit for every account. **It removed the limit only for verified Ultra accounts.** The evidence was one Ultra account's `usage.db`, and the official pages were not checked.

### Current rules (official pages, read 2026-11-01)

| Plan | Price/month | 5-hour limit | Weekly vs Pro | Fable |
|---|---|---|---|---|
| Free | $0 | Yes ("limited") | "Limited" | Not included |
| Pro | $20 ($17 annual) | Yes | 1x | Usage credits only |
| Max | $100 | Yes, 5x Pro | 5x | Up to 50% of weekly limit |
| Ultra (was Max 20x) | $200 | None once verified; temporary limit before that | 10x | Up to 50% of weekly limit |

- Verification is automatic. Its duration and the temporary limit's size are not published.
- Team and Enterprise 5-hour limits are not stated on the pages read.
- Sources: [pricing](https://claude.com/pricing), [Ultra](https://support.claude.com/en/articles/17728952-what-is-the-ultra-plan), [Max](https://support.claude.com/en/articles/11049741-what-is-the-max-plan), [Pro](https://support.claude.com/en/articles/8325606-what-is-the-pro-plan), [Fable](https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan).

### Evidence for the design rule (one Ultra account only)

- Before the change: 0 missing 5-hour values in 2,627 polls and 2,636 rollups.
- `five_hour` went null at 2026-10-31 08:03 UTC and has stayed null since.
- **Not observed:** a real Pro, Max or unverified Ultra response.

### Effect on released software

Released 1.6.0 works for accounts with a 5-hour number. Verified Ultra accounts see "—" in the menu bar, an empty 5h ring, a blank sparkline, 0% / $0 value figures, no new tokens-per-percent measurements, and a benchmark that spends quota and ends "inconclusive".

---

## 2. Impact Analysis

### Checklist record

| Item | Status | Note |
|---|---|---|
| 1.1 Trigger | [x] | User-reported; confirmed on official pages |
| 1.2 Problem | [x] | Misunderstanding of a platform change |
| 1.3 Evidence | [x] | Official pages + `usage.db` |
| 2.1 Current epic | [!] | Epic 26 rescoped; its numbering is kept |
| 2.2 Epic-level change | [!] | Redefined: adapt per account instead of removing 5-hour support |
| 2.3 Remaining epics | [x] | Codex epics 22–25 no longer at risk: 5-hour components stay |
| 2.4 Obsolete / new epics | [x] | None |
| 2.5 Resequencing | [x] | Epic 26 stays ahead of Codex |
| 3.1 PRD | [!] | Restore; add FR61–FR66 |
| 3.2 Architecture | [!] | Restore; add one section |
| 3.3 UX | [!] | Restore; add one section to each spec |
| 3.4 Other | [!] | `README.md`, `docs/images/demo.gif`, plan table |
| 4.1 Direct adjustment | Viable | Rescoped stories |
| 4.2 Rollback | Viable, needed | Three merged stories reverted; 26.2 and 26.8 work not merged |
| 4.3 MVP review | [x] | MVP unchanged |
| 4.4 Path | [x] | Hybrid: rollback + direct adjustment |

### Story impact

| Story | State | Action |
|---|---|---|
| 26.1 weekly-only menu bar | Merged, unreleased | Reverted. Replaced by a small fallback |
| 26.5 weekly value analysis | Merged, unreleased | Reverted. Rebuilt with safe classification; reverted code is reusable |
| 26.7 weekly tokens-per-percent | Merged, unreleased | Reverted. Rebuilt alongside 5-hour measurement; reverted code is reusable |
| 26.2 weekly pace | Pushed, not merged | Keep `WeeklyPace` model and its tests. Slope deletion dropped |
| 26.8 benchmark retirement | Stopped, nothing committed | Replaced by hiding Measure when no 5-hour number |
| 21.5 Fable benchmark default | Released | Stays |

The revert is merged as "revert: remove weekly-only code from Stories 26.1, 26.5 and 26.7".

### Why 26.5 could not stay

`ResetEvent.isWeeklyCycle` means "after the cutover date, empty 5-hour peak, has a weekly value". An empty peak also occurs when a Mac sleeps over 5 hours. A Pro or Max account would gain false 7-day cycles, and `excludingWeeklyOverlap()` would drop real events from the week before. A global cutover date cannot work, because accounts verify at different times.

### Data

No `DELETE` or `DROP` on historical tables. `five_hour_*` columns remain in active use for accounts that have the limit.

---

## 3. Recommended Approach

**Follow each account's data, not its plan name.**

- **5-hour number present:** behave exactly as 1.6.0, including slope, promotion and benchmark.
- **5-hour number missing while connected:** weekly is primary, with pace.

An account can change state when it verifies, so the app re-evaluates on every poll. If a number were ever briefly missing on an account with the limit, the app shows weekly until the next poll, which is safe.

- **Effort:** Medium, well below the 2026-10-31 plan. Existing 5-hour logic stays, and reverted code is reusable.
- **Risk:** Low to medium. The main risk is the unobserved Pro, Max and unverified Ultra responses.

### Decisions

| Decision | Choice | Source |
|---|---|---|
| Follow data per account | Yes | User |
| Benchmark | Kept for accounts with a 5-hour number; Measure hidden when none | User |
| Menu bar fix | Ships first as `[patch]` | User |
| Fable on the menu bar | Keep the existing corner-dot pattern | Default |
| Pace on accounts with a 5-hour number | Not shown; slope stays | Default |
| Weekly run-out notification | Not included | Default |

---

## 4. Detailed Change Proposals

### 4.1 Epic 26 — Support Accounts Without a 5-Hour Limit

Replaces `epics/epic-26-weekly-first-monitoring.md`. New file: `epics/epic-26-accounts-without-five-hour-limit.md`.

**Rule for every story:** behaviour for an account with a 5-hour number must not change. Each story keeps or adds a test proving it.

**26.1 — Show weekly when there is no 5-hour number (`[patch]` 1.6.1)**
- `AppState.displayedWindow` returns `.sevenDay` when connected and `fiveHour` is nil. Both nil keeps today's state (`cc-hdrm/State/AppState.swift:144-147`).
- Menu bar text, colour, gauge icon, VoiceOver and extra-usage $ then work from the weekly window.
- The popover hides the 5-hour ring when there is no number (`cc-hdrm/Views/PopoverView.swift:128`).
- Hide "N full 5h quotas left" when there is no number (`cc-hdrm/Views/SevenDayGaugeSection.swift`).
- **AC:** `five_hour: null` while connected shows weekly headroom and colour, not "—". With a 5-hour number, display and promotion are unchanged.

**26.2 — Weekly pace when there is no 5-hour number**
- Reuse `cc-hdrm/Models/WeeklyPace.swift` and its tests from branch `feature/story-26.2-weekly-pace`.
- Menu bar `↗` only when run-out is projected before the weekly reset. Popover line: "On pace" / "Ahead of pace — runs out ~Thu 2:00 PM".
- Slope remains for accounts with a 5-hour number. Nothing is deleted.

**26.3 — Weekly-first popover and sparkline when there is no 5-hour number**
- Weekly ring becomes the large primary gauge.
- Sparkline shows the current weekly cycle with an even-pace line.
- The 24-hour 5-hour sparkline stays for accounts with a number.

**26.4 — Analytics charts adapt to the data**
- The 5-hour series is off and hidden when the selected range has no 5-hour data, and works as today otherwise.
- Per-point slope colouring and reset markers keep working where 5-hour data exists.

**26.5 — Value and headroom analysis per weekly cycle when there is no 5-hour number**
- A weekly cycle is identified from what was seen when it was recorded: a weekly reset **and** no 5-hour number on the polls around it. Never from a cutover date or an empty peak alone. An additive nullable column is allowed if needed.
- A sleep gap on an account with the limit must not create a weekly cycle.
- Old 5-hour events keep their breakdown.
- The overlap rule applies only to an account that actually changed state.
- Reusable: the two-band breakdown and 7-day capacity code from the reverted story.

**26.6 — Tier advice and patterns for accounts without a 5-hour number; plan facts**
- Weekly peak and weekly exhaustion drive advice for those accounts. Accounts with a number are unchanged.
- Show Max 20x as "Ultra" and Max 5x as "Max" (`cc-hdrm/Models/RateLimitTier.swift`). Advice accounts for Ultra having no 5-hour limit once verified.
- Confirm the tier string real Ultra accounts report, and keep unknown strings safe.
- **Credit table:** Max (41.7M) and Ultra (83.3M) weekly match the published 5x / 10x ratio to each other. Pro (5M) does not; 5x / 10x implies about 8.3M. The 5-hour values give Max 6x Pro where 5x is published. **Credits are unpublished, so do not change them on ratio alone:** show the evidence and ask the maintainer.

**26.7 — Tokens-per-percent from weekly steps when there is no 5-hour number**
- Polls with a 5-hour number keep today's measurement. Polls without one use weekly steps with the 6-hour window.
- Bases are never averaged together. Backfill follows the same rule per poll.
- Reusable: the weekly code and review fixes from the reverted story.

**26.8 — Hide the benchmark when there is no 5-hour number**
- Measure is hidden with a short explanation. Past results stay visible.
- `cc-hdrm/Services/BenchmarkService.swift` measurement is unchanged for accounts with a number.
- **Why not weekly:** the API reports whole percents, so a usable weekly run costs about 8% of the weekly allowance (minimum 2–4%).

**26.9 — Documentation and `[minor]` release**
- Update `README.md` and `docs/images/demo.gif` to describe both account states.
- **This story's PR title carries `[minor]`.**

**Sequence:** 26.1 first and released. Then 26.2 → 26.3; 26.4; 26.5 → 26.6; 26.7; 26.8; 26.9 last.

### 4.2 PRD (`prd.md`)

Restore the pre-2026-10-31 text, then add a dated note and these requirements. **FR6–FR45 return to their original wording.** Each original 5-hour requirement applies to accounts that report a 5-hour number.

- **FR61:** App detects on each poll whether the account reports a 5-hour number, and adapts without configuration or restart.
- **FR62:** With no 5-hour number, the menu bar and notifications use weekly headroom.
- **FR63:** With no 5-hour number, the user sees weekly pace and projected run-out time, with an indicator in the menu bar when run-out is projected before the weekly reset.
- **FR64:** With no 5-hour number, the popover leads with the weekly gauge and shows the current weekly cycle against an even-pace line.
- **FR65:** With no 5-hour number, value analysis, tier advice and tokens-per-percent use weekly data. Benchmarking is unavailable.
- **FR66:** App shows the current plan names: Pro, Max and Ultra.

### 4.3 Architecture and UX

Restore `architecture.md`, `ux-design-specification.md`, `ux-design-specification-phase3.md`, `project-context.md` and `epics/requirements-inventory.md` to their pre-2026-10-31 text. Then add:
- **Architecture:** one section, "Accounts Without a 5-Hour Limit": the detection rule, the pace formulas, weekly-cycle identification, the "unchanged with a number" rule.
- **UX specs:** one section each, describing the no-5-hour display. Existing 5-hour design stays valid.
- **Inventory:** add FR61–FR66.

### 4.4 Tracking

- `sprint-status.yaml`: replace the 26-x entries with keys matching the stories in 4.1: 26.1 `done` (released in 1.6.1), the rest `backlog`.
- `epics/epic-list.md`, `epics/index.md`: update the Epic 26 entries.
- `sprint-change-proposal-2026-10-31.md`: mark SUPERSEDED.
- `spec-26-1-…`, `spec-26-5-…`, `spec-26-7-…`: mark superseded by reverted scope, kept as records.
- `deferred-work.md`: mark the 26.1, 26.5 and 26.7 entries as superseded; re-check any still relevant in the rebuilt stories.

---

## 5. Implementation Handoff

**Scope: Moderate** — backlog reorganisation and correction of planning documents.

| Role | Responsibility |
|---|---|
| Lead (this session) | Merge the revert; apply section 4 edits after approval; run stories one at a time |
| Developer (`bmad-build`) | One story at a time, under the shared build lock |
| Reviewer (`bmad-code-review`) | Separate review per story |
| Maintainer | Approve this proposal; decide credit-table changes from 26.6 |

**Mac limits:** one worker building at a time, shared lock, 4 compile jobs, low priority.
**Review:** CodeRabbit is not required before merge, by maintainer decision. Findings that arrive before a merge are still read.

### Success criteria

- With `five_hour: null` while connected, the menu bar shows weekly headroom and colour, not "—".
- With a 5-hour number, all 1.6.0 behaviour is unchanged, and tests prove it in each story.
- An account that changes state adapts at the next poll without a restart.
- A sleep gap on an account with the limit creates no weekly cycle.
- Accounts without a number get non-zero value, tier and tokens-per-percent results from weekly data.
- No `DELETE` or `DROP` on historical tables.
- 1.6.1 published from Story 26.1; 1.7.0 published from Story 26.9.
