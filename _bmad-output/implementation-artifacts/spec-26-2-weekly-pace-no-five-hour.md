---
title: 'Weekly Pace When There Is No 5-Hour Number (Story 26.2)'
type: 'feature'
created: '2026-11-01'
status: 'done'
baseline_commit: 'f3bdc4ecee0df487b53129783f8f0af4e6a32b42'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-26-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Accounts with no 5-hour number get weekly slope, whose arrow can show "rising" for up to 15 minutes after a single 1% step. That says nothing about whether the weekly allowance will last.

**Approach:** When connected with no 5-hour number, replace weekly slope with pace worked out from weekly utilization and reset time. The menu bar shows `↗` only when run-out is projected before the reset. The popover gauge shows a pace line that VoiceOver speaks.

## Boundaries & Constraints

**Always:** With a 5-hour number, slope, promotion, labels and VoiceOver stay exactly as 1.6.0. Re-evaluate on every poll. Pace is never colour alone.

**Ask First:** Nothing open. This runs unattended, so defaults are recorded in Design Notes.

**Never:** Delete or weaken slope code. `DELETE`, `DROP` or schema changes. Modify `cc-hdrm/cc_hdrm.entitlements`. Decide from a date or plan name. Merge the old branch whole. Change other status lines in `sprint-status.yaml`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Ahead | no number, 60%, 3 days in | `40% ↗`; run-out now + 2 days; "Ahead of pace — runs out ~…" | N/A |
| On pace | no number, 50%, 3.5 days in | `50%`; "On pace" | N/A |
| 1% step | no number, on pace, weekly slope `.rising` | no arrow; VoiceOver does not say rising | N/A |
| First hours | no number, 10%, 2 hours in | no arrow; "On pace" | N/A |
| No reset time | no number, 60%, reset nil | `40%`; no pace line | no crash |
| Exhausted | no number, 100% | `↻ …`, or `0%` with no reset; no arrow or line | no crash |
| Disconnected | no number, old weekly data | `—`; no pace line, no slope | N/A |
| Promoted weekly | number present, weekly promoted | slope arrow and slope VoiceOver; no pace line | N/A |
| Flip | number → none → number | follows the data at each poll | N/A |

</frozen-after-approval>

## Code Map

- `cc-hdrm/State/AppState.swift:134` -- `hasNoFiveHourNumber`, the single check. `:250` `menuBarText` draws the arrow.
- `cc-hdrm/App/AppDelegate.swift:616` -- menu bar VoiceOver slope text. `:645` existing transition logging.
- `cc-hdrm/Views/SevenDayGaugeSection.swift:29,54` -- VoiceOver slope text and the ring's `slopeLevel`.
- `cc-hdrm/Views/HeadroomRingGauge.swift:95` -- `slopeLevel: nil` already hides the indicator. No change.
- `cc-hdrm/Extensions/Date+Formatting.swift` -- single home for date text; `absoluteTimeString()` output stays the same.
- `origin/feature/story-26.2-weekly-pace` -- source of `WeeklyPace` and its tests. Its slope deletions are not taken.
- `cc-hdrmTests/State/AppStateTests.swift:275`, `cc-hdrmTests/App/AppDelegateTests.swift:615` -- 1.6.1 tests of slope on these accounts; this story replaces that behaviour.

## Tasks & Acceptance

**Execution:**
- [x] `cc-hdrm/Models/WeeklyPace.swift` -- add from the branch -- pure pace model.
- [x] `cc-hdrm/Extensions/Date+Formatting.swift` -- add `dayTimeString()`; `absoluteTimeString()` reuses it -- the line needs the time without "at".
- [x] `cc-hdrm/State/AppState.swift` -- add `weeklyPace`; use it for the arrow when there is no number -- slope path untouched.
- [x] `cc-hdrm/App/AppDelegate.swift` -- VoiceOver says "ahead of pace" with the arrow; log arrow changes once.
- [x] `cc-hdrm/Views/SevenDayGaugeSection.swift` -- pace line, VoiceOver text, no slope when there is no number.
- [x] `cc-hdrmTests/Models/WeeklyPaceTests.swift`, `cc-hdrmTests/Extensions/DateFormattingTests.swift` -- hand-calculated values and date text.
- [x] `cc-hdrmTests/State/AppStateWeeklyPaceTests.swift`, `cc-hdrmTests/Views/SevenDayGaugeSectionTests.swift`, `cc-hdrmTests/Views/PopoverViewTests.swift`, `cc-hdrmTests/App/AppDelegateTests.swift`, `cc-hdrmTests/Services/PollingEngineTests.swift` -- every matrix row, including the flip through the poll path.
- [x] `cc-hdrmTests/State/AppStateTests.swift` -- replace the 1.6.1 slope test for these accounts.
- [x] `_bmad-output/implementation-artifacts/sprint-status.yaml` -- set `26-2-weekly-pace-no-five-hour: review` only.

**Acceptance Criteria:**
- Given no 5-hour number, when pace is computed, then pace and run-out match hand-calculated values.
- Given no 5-hour number and a single 1% step, when slope reads rising, then no arrow appears unless run-out is before the reset.
- Given a 5-hour number, when any window is displayed, then slope arrow, ring slope and VoiceOver are unchanged and no pace line appears.
- Given an account changes state, when the next poll arrives, then the display follows with no restart.
- Given the arrow changes, when the menu bar updates, then one log line records it and repeated polls add none.

## Spec Change Log

## Design Notes

Defaults chosen, since no human is available:
- **Menu bar VoiceOver:** says "ahead of pace" without the time. Run-out moves with the clock, so including it would announce a change on nearly every poll. The popover label has the full time.
- **On pace in the menu bar:** nothing spoken, matching no arrow.
- **Under-spending and the first 4 hours:** both read "On pace". The plan has only two wordings, and run-out is unreliable that early.
- **Outage:** pace needs `.connected`, since old data gives a false projection. The ring still hides slope, using `hasNoFiveHourNumber`, so an outage cannot bring slope back.
- **`displayedSlope`:** left as is. Callers branch on the account state, so slope code stays untouched.
- **Long line:** it measures 197 points against 168 available, which widened the popover from 200 to 229. It now wraps to two lines, so the popover width stays the same.
- **Reset already passed:** no pace until the next poll, because the utilization belongs to a finished week. The old branch showed "On pace" here.
- **Connected with old data:** pace stays on. Gating on `dataFreshness` would flap, because the 5-minute very-stale limit equals the default poll interval.
- **Clock:** `weeklyPace` reads `countdownTick`, so the arrow can clear between polls. Only these accounts register that read.

## Open for the Maintainer

Both follow the plan's rules as written, so they were not changed.
- **Arrow near even pace:** the arrow means run-out is before the reset, so someone spending at an even pace sees it after a 1% step that crosses the line. The clock clears it about 1.7 hours later. A margin would stop this but changes the rule.
- **Heavy use in the first 4 hours:** 90% used after 3 hours reads "On pace", with no arrow, until hour 4. Hiding the line when already over even pace would be more honest, but the plan has only two wordings.

## Verification

**Commands:**
- `/usr/bin/lockf -k /tmp/cchdrm-xcodebuild.lock nice -n 15 xcodebuild -jobs 4 -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test` -- expected: all tests pass.

**Manual checks (if no CLI):**
- Not run: no app launches on this machine. A test proves the long line wraps without widening the popover; on a verified Ultra account, confirm the two lines look right.

## Suggested Review Order

**The pace rule**

- Pure model: run-out only before the reset and after 4 hours; none after the reset.
  [`WeeklyPace.swift:21`](../../cc-hdrm/Models/WeeklyPace.swift#L21)

- Only connected accounts with no 5-hour number get pace; everyone else gets nil.
  [`AppState.swift:140`](../../cc-hdrm/State/AppState.swift#L140)

**Menu bar**

- The arrow's source splits here; the slope path below is untouched.
  [`AppState.swift:281`](../../cc-hdrm/State/AppState.swift#L281)

- VoiceOver omits the clock time, which would re-announce on nearly every poll.
  [`AppDelegate.swift:620`](../../cc-hdrm/App/AppDelegate.swift#L620)

- One log line per arrow change, never for a slope arrow.
  [`AppDelegate.swift:658`](../../cc-hdrm/App/AppDelegate.swift#L658)

**Popover**

- Slope stays off during an outage too, so it cannot flash back.
  [`SevenDayGaugeSection.swift:30`](../../cc-hdrm/Views/SevenDayGaugeSection.swift#L30)

- Fixed width makes the long line wrap instead of widening the popover.
  [`SevenDayGaugeSection.swift:89`](../../cc-hdrm/Views/SevenDayGaugeSection.swift#L89)

**Tests**

- Promoted weekly with a number keeps slope and shows no pace.
  [`AppStateWeeklyPaceTests.swift:143`](../../cc-hdrmTests/State/AppStateWeeklyPaceTests.swift#L143)

- The minute tick redraws nothing for accounts with a number.
  [`AppStateWeeklyPaceTests.swift:196`](../../cc-hdrmTests/State/AppStateWeeklyPaceTests.swift#L196)

- Real API JSON through the poll path, flipping both ways.
  [`PollingEngineTests.swift:378`](../../cc-hdrmTests/Services/PollingEngineTests.swift#L378)

- Measured width and height tie the wrap to the drawn popover.
  [`PopoverViewTests.swift:589`](../../cc-hdrmTests/Views/PopoverViewTests.swift#L589)
