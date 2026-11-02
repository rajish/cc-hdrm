---
title: 'Document Accounts With and Without a 5-Hour Number (Story 26.9)'
type: 'chore'
created: '2026-11-02'
status: 'done'
route: 'one-shot'
baseline_commit: '13f2b5c12d5edd259419908204bed1e14aecb534'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-26-context.md'
---

## Intent

**Problem:** The README speaks only of Pro and Max accounts with a 5-hour gauge. Accounts with no 5-hour number now get a weekly-first app, and the README does not say so.

**Approach:** Describe both account states briefly in `README.md`. Word the Ultra fact as the app following what the usage data reports. Release 1.7.0 comes from the `[minor]` keyword in this story's PR title, added when the PR is opened.

## Decisions Taken Unattended

- **Demo GIF not re-recorded.** Recording needs the app launched, which this run forbade. `docs/images/demo.gif` still correctly shows an account with a 5-hour number. The caption gains one sentence pointing to the new section. A weekly-first recording is left to the maintainer.
- **No credit figures, and nothing on Team, Enterprise or Free plans.** The official pages do not say them.
- **Plan naming:** Pro, Max and Ultra, as in `cc-hdrm/Models/RateLimitTier.swift:44`.
- **Version:** `cc-hdrm/Info.plist` is untouched. The release workflow bumps it from the PR title.
- **Sprint status:** `26-9-docs-minor-release` and `epic-26` set to `done`. No other line touched.
- **Review:** one blind review ran. Patches: none. Deferred: the Notifications line (see `deferred-work.md`). Rejected: the rest, as out of scope or already settled by this brief.

## README Claims and Sources

| Claim | Source |
|---|---|
| Verified Ultra accounts have no 5-hour limit; the app follows the usage data, not the plan name | Epic Goal and Design Rules in `_bmad-output/planning-artifacts/epics/epic-26-accounts-without-five-hour-limit.md`; `cc-hdrm/State/AppState.swift:141` (`fiveHour == nil && sevenDay != nil`) |
| Checked on every poll; no restart, no setting | Epic Design Rules ("Re-evaluate on every poll"); computed property in `cc-hdrm/State/AppState.swift:141` |
| Menu bar shows weekly headroom and colour | `cc-hdrm/State/AppState.swift:184` (`displayedWindow` returns `.sevenDay`) |
| ↗ only when run-out is before reset | `cc-hdrm/State/AppState.swift:297`; `cc-hdrm/Models/WeeklyPace.swift:36` |
| Popover: large weekly ring, reset time, pace line "On pace" / "Ahead of pace — runs out ~Thu 2:00 PM" | `cc-hdrm/Views/PopoverView.swift:128-157`; `cc-hdrm/Models/WeeklyPace.swift:39-42`; `cc-hdrm/Views/SevenDayGaugeSection.swift:36` |
| Weekly sparkline of the current cycle with an even-pace line | `cc-hdrm/Views/PopoverView.swift:178-181`; `cc-hdrm/State/AppState.swift:156`; epic context UX section |
| 5-hour series hidden for ranges with no 5-hour data | Story 26.4 spec Intent |
| Value, tier advice, tokens-per-percent from weekly data | Story 26.5, 26.6, 26.7 spec Intents |
| Benchmark unavailable, with explanation, because a weekly test would use too much weekly allowance | `cc-hdrm/Views/BenchmarkSectionView.swift:39` (`noFiveHourNote`), `:71`, `:82` |
| Ring gauges: 5-hour "when your account has one" | `cc-hdrm/Views/PopoverView.swift:217` (`showsFiveHourSection`) |
| Diagram: "5h if reported" | Epic Design Rules ("Number present" / "Number missing") |

## Suggested Review Order

- New section describing both states.
  [`README.md`](../../README.md)

- One caption sentence about the weekly-first popover.
  [`README.md:8`](../../README.md#L8)

- Sprint status closes the story and the epic.
  [`sprint-status.yaml:223`](sprint-status.yaml#L223)
