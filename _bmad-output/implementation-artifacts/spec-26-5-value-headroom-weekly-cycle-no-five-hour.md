---
title: 'Value and Headroom per Weekly Cycle With No 5-Hour Number (Story 26.5)'
type: 'feature'
created: '2026-11-01'
status: 'done'
baseline_commit: '2bd3e381d0f7c6854e8fd72014980a8843bcc291'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-26-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Reset events are keyed on the 5-hour window, so an account with no 5-hour number sees 0% used and $0. The earlier fix guessed weekly cycles from a cutover date and an empty peak, which gave Pro and Max accounts false cycles after a Mac slept and dropped their real events.

**Approach:** Decide when the reset is recorded, from what the polls showed, and store the answer in an additive column. Weekly cycles use two bands from weekly credits. Every other event follows its 1.6.0 path.

## Boundaries & Constraints

**Always:** A weekly cycle is a weekly reset with no 5-hour number on the polls around it. Weekly cycles keep their stored credits. A 5-hour event with a resolvable tier is recomputed as in 1.6.0, and uses stored credits only when the tier no longer resolves. Old rows are never rewritten. Accounts with a number match 1.6.0, proven by tests.

**Ask First:** Nothing open. This runs unattended, so defaults are recorded in Design Notes.

**Never:** Decide from a cutover date, a plan name or an empty peak alone. Run `DELETE` or `DROP` on historical tables, or touch `~/Library/Application Support/cc-hdrm/usage.db`. Modify `cc-hdrm/cc_hdrm.entitlements`. Change tier advice (Story 26.6). Change other status lines in `sprint-status.yaml`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Sleep over 5 hours, number | polls with a number, 6-hour gap | peak-empty event, not a weekly cycle; real events all counted | info log |
| Sleep across weekly reset, number | number on both polls, both windows shift | not a weekly cycle | N/A |
| Weekly cycle | no number around a weekly reset, 70% | 70% used, 30% unused, non-zero value | N/A |
| Number seen in last 5 hours | number, then missing, then weekly reset | not a weekly cycle | N/A |
| One side has a number | state flips on the reset poll | not a weekly cycle | N/A |
| State change mid-history | 5-hour events, then weekly cycles | old breakdown kept; events inside a cycle's 7 days not counted twice | N/A |
| Stored credits, tier now unknown | 5-hour event with credits | stored credits counted | N/A |
| Over 100% | weekly or 7-day value 104 | clamped to 100, no negative unused | N/A |
| Weekly cycle, no credits, tier unknown | flagged, nothing stored | skipped, and its 7 days are not counted | info log |
| Old rows after migration | column NULL | not weekly cycles, unchanged | N/A |

</frozen-after-approval>

## Code Map

- `cc-hdrm/Services/HistoricalDataService.swift` (`detectAndRecordResetIfNeeded`, `recordResetEvent`, `getResetEvents`) -- the only place a weekly cycle is decided and stored.
- `cc-hdrm/Services/DatabaseManager.swift` -- schema version 9, additive `reset_events.is_weekly_cycle`.
- `cc-hdrm/Models/ResetEvent.swift` -- stored flag, `excludingWeeklyOverlap()`.
- `cc-hdrm/Models/HeadroomBreakdown.swift` -- `weeklyCycle(sevenDayPeak:creditLimits:)`, `PeriodSummary.weeklyCycleCount`.
- `cc-hdrm/Services/HeadroomAnalysisService.swift` -- carried findings at the 1.6.0 lines for skipped weekly resets, stored credits and clamping.
- `cc-hdrm/Services/SubscriptionValueCalculator.swift` -- capacity and price days.
- `cc-hdrm/Services/ValueInsightEngine.swift`, `cc-hdrm/Services/CycleUtilizationCalculator.swift` -- copy, and overlap applied before grouping by month.
- `cc-hdrm/Views/HeadroomBreakdownBar.swift`, `cc-hdrm/Views/AnalyticsView.swift` -- VoiceOver label, data span, bar visibility.
- Reused from `5993153`: the two-band formula and capacity sum. Not its `isWeeklyCycle` rule.

## Tasks & Acceptance

**Execution:**
- [x] `cc-hdrm/Services/DatabaseManager.swift` -- add the column through the migration path.
- [x] `cc-hdrm/Services/HistoricalDataService.swift` -- classify and record weekly cycles.
- [x] `cc-hdrm/Models/ResetEvent.swift`, `cc-hdrm/Models/HeadroomBreakdown.swift` -- flag, overlap rule, two bands.
- [x] `cc-hdrm/Services/HeadroomAnalysisService.swift`, `cc-hdrm/Services/HeadroomAnalysisServiceProtocol.swift` -- weekly branch, stored credits, clamp.
- [x] `cc-hdrm/Services/SubscriptionValueCalculator.swift`, `cc-hdrm/Services/ValueInsightEngine.swift`, `cc-hdrm/Services/CycleUtilizationCalculator.swift` -- value, insight, cycles.
- [x] `cc-hdrm/Views/HeadroomBreakdownBar.swift`, `cc-hdrm/Views/AnalyticsView.swift` -- label, span, visibility.
- [x] `cc-hdrmTests/Services/WeeklyCycleTests.swift` -- real detection through `persistPoll` on a temporary database, plus the matrix.
- [x] `cc-hdrmTests/Services/DatabaseManagerTests.swift`, `cc-hdrmTests/Services/OutageTrackingTests.swift` -- schema version 9, migration keeps old rows.
- [x] `_bmad-output/implementation-artifacts/sprint-status.yaml` -- set `26-5-value-headroom-weekly-cycle-no-five-hour: done` only.

**Acceptance Criteria:**
- Given a sleep gap over 5 hours on an account with a number, when polls run through real detection, then no weekly cycle is created and no real event is dropped.
- Given a weekly cycle with a 70% peak, when value is computed, then it reports 70% used, 30% unused and a non-zero value, and VoiceOver says "Headroom breakdown: 70% used, 30% unused capacity."
- Given an account that changes state mid-history, when value is computed, then 5-hour events keep their breakdown, weekly cycles begin after the change, and overlapping capacity is not counted twice.
- Given an account with a number, when value, insight and cycles are computed, then results match 1.6.0.

## Spec Change Log

## Design Notes

Defaults chosen, since no human is available:
- **"Polls around it":** the poll before, the poll that saw the reset, and every poll in the 5 hours before it. Any number there means no weekly cycle. The window comes from the existing peak query, so a flagged row always has an empty peak. The cost: an account that verifies under 5 hours before its weekly reset, or across the reset poll, gets its first cycle one week later.
- **"No number":** the 5-hour value and its reset time are both empty. `{utilization: null, resets_at: X}` is not treated as missing.
- **Peak of a cycle:** the weekly value on the last poll before the reset, as 1.6.0 records it. A Mac asleep at the end of a cycle can understate it.
- **Existing rows are not reclassified:** an old row stays unflagged, including a real weekly reset recorded by 1.6.1. Weekly figures start at the first reset after upgrade.
- **Credits on weekly rows:** used and unused are stored, and constrained stays NULL, so a later change to the tier table leaves old cycles alone.
- **Old rows without stored credits:** computed from the tier table as 1.6.0 does, in memory only.
- **A real weekly reset:** the reset time moved forward by 6 days or more, or weekly usage dropped. A smaller move with no drop still records an event as in 1.6.0, but not a weekly cycle.
- **Known 1.6.0 differences, from the carried findings:** stored credits count when a 5-hour event's tier no longer resolves. A value over 100 is clamped. A 5-hour event whose tier resolves is still recomputed from current limits, so editing custom limits changes past events as in 1.6.0. Only weekly cycles keep their stored credits over recomputing.
- **Overlap:** a 5-hour event in the 7 days before any weekly cycle is left out of value and capacity, because the weekly value already contains its usage. So is an unflagged empty-peak row, which adds days but no usage. Rows are untouched. With no weekly cycle in the list, the input is returned as is.
- **Capacity:** first-to-last span of other events, without the weeks weekly cycles stand for, capped by the range as in 1.6.0, plus 7 days per weekly cycle that could be analysed.
- **Price:** capacity days capped at the range, with a 7-day floor. A 30-day range holding 5 cycles is priced at 30 days, while utilisation keeps all 35.
- **Month grouping:** a weekly cycle belongs wholly to the month of its reset.
- **Copy:** "last cycle" replaces "today" and "this week" only when every event in the range is a weekly cycle.
- **VoiceOver:** the same rule. With a known price, the dollar amounts follow the required sentence, so nothing is lost.
- **Test host and the real database:** `xcodebuild test` runs the app's startup, which opens the real database and applies any new migration. The column reached it that way. It is additive and rewrote no rows. See `deferred-work.md`.
- **Bar visibility:** a weekly-only range always shows the bar. The existing rule hides it for 20–80%, which would hide the 70% example.

## Verification

**Commands:**
- `/usr/bin/lockf -k /tmp/cchdrm-xcodebuild.lock nice -n 15 xcodebuild -jobs 4 -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test` -- expected: all tests pass.

**Manual checks (if no CLI):**
- Not run: no app launches on this machine. On a verified Ultra account, check the bar and VoiceOver after the first weekly reset that follows the upgrade. Tests cover the label, visibility rule and value helpers, not the view wiring.

## Suggested Review Order

**The decision**

- Entry point: a weekly cycle needs a real weekly reset and no 5-hour number around it.
  [`HistoricalDataService.swift:565`](../../cc-hdrm/Services/HistoricalDataService.swift#L565)

- A drifting reset time with no drop in usage is not a new cycle.
  [`HistoricalDataService.swift:533`](../../cc-hdrm/Services/HistoricalDataService.swift#L533)

- Additive column; safe to repeat if an earlier run stopped midway.
  [`DatabaseManager.swift:196`](../../cc-hdrm/Services/DatabaseManager.swift#L196)

**Breakdown**

- Weekly cycles keep stored credits; 5-hour events are recomputed as in 1.6.0 and fall back to stored credits only when the tier is unknown.
  [`HeadroomAnalysisService.swift:121`](../../cc-hdrm/Services/HeadroomAnalysisService.swift#L121)

- Two bands from weekly credits, clamped.
  [`HeadroomBreakdown.swift:21`](../../cc-hdrm/Models/HeadroomBreakdown.swift#L21)

**Overlap and capacity**

- Applies only when a flagged cycle exists, so accounts with a number pass through.
  [`ResetEvent.swift:35`](../../cc-hdrm/Models/ResetEvent.swift#L35)

- A week between 5-hour events is counted once.
  [`ResetEvent.swift:48`](../../cc-hdrm/Models/ResetEvent.swift#L48)

- 7 days per analysed cycle.
  [`SubscriptionValueCalculator.swift:80`](../../cc-hdrm/Services/SubscriptionValueCalculator.swift#L80)

- Utilisation keeps all cycles; price stops at the range.
  [`SubscriptionValueCalculator.swift:58`](../../cc-hdrm/Services/SubscriptionValueCalculator.swift#L58)

- Overlap applied before splitting into months.
  [`CycleUtilizationCalculator.swift:32`](../../cc-hdrm/Services/CycleUtilizationCalculator.swift#L32)

**Wording and display**

- One rule decides weekly wording everywhere.
  [`ResetEvent.swift:61`](../../cc-hdrm/Models/ResetEvent.swift#L61)

- "Last cycle" copy.
  [`ValueInsightEngine.swift:372`](../../cc-hdrm/Services/ValueInsightEngine.swift#L372)

- Required VoiceOver sentence; old wording otherwise.
  [`HeadroomBreakdownBar.swift:204`](../../cc-hdrm/Views/HeadroomBreakdownBar.swift#L204)

- Without this, a 70% cycle would hide its own bar.
  [`AnalyticsView.swift:271`](../../cc-hdrm/Views/AnalyticsView.swift#L271)

**Tests**

- Sleep gap through real detection, moving stored times back to simulate elapsed time.
  [`WeeklyCycleTests.swift:94`](../../cc-hdrmTests/Services/WeeklyCycleTests.swift#L94)

- State change mid-history.
  [`WeeklyCycleTests.swift:319`](../../cc-hdrmTests/Services/WeeklyCycleTests.swift#L319)

- Hand-worked 1.6.0 results.
  [`WeeklyCycleTests.swift:661`](../../cc-hdrmTests/Services/WeeklyCycleTests.swift#L661)
