---
title: 'Analytics Charts Adapt to the Data (Story 26.4)'
type: 'feature'
created: '2026-11-01'
status: 'done'
baseline_commit: '635ae6bf2e6238fd3490778fb390369931575987'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-26-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Analytics always offers a 5-hour toggle. For a range with no 5-hour data, that toggle does nothing, and a choice of only 5-hour draws an empty chart.

**Approach:** Decide from the data loaded for the selected range. With no 5-hour data there, hide the toggle and turn the series off for drawing, without touching the stored choice. If 5-hour was the only series switched on, show weekly instead.

## Boundaries & Constraints

**Always:** A range with 5-hour data behaves as today: defaults, colours, toggles, slope colouring, markers and VoiceOver. The stored 5-hour and 7-day choices survive a visit to a range without 5-hour data. Every series toggle still responds when pressed.

**Ask First:** Nothing open. This runs unattended, so defaults are recorded in Design Notes.

**Never:** Decide from a cutover date, a plan name or the account's current state. Run `DELETE` or `DROP`, or change the schema. Modify `cc-hdrm/cc_hdrm.entitlements`. Change other status lines in `sprint-status.yaml`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 24-hour range, weekly only | polls with no 5-hour value | no 5-hour toggle, series off | N/A |
| Long range across a state change | old rollups with 5-hour, new ones without | toggle shown; old bars drawn, none for new periods | N/A |
| Range with 5-hour data | any stored choice | drawn exactly as stored; Fable still needs data | N/A |
| One 5-hour value only | one poll or rollup field set | counts as having 5-hour data | N/A |
| Only 5-hour on | 5-hour on, others off, no 5-hour data | weekly shows, chip reads on | N/A |
| Only 5-hour on, Fable available | 5-hour and Fable on, 7-day off, no 5-hour data | Fable shows, weekly stays off | N/A |
| User had everything off | 5-hour and 7-day off, no 5-hour data | "Select a series" as today | N/A |
| Press weekly chip with 5-hour hidden | chip on | chip turns off; press again turns on; stored 7-day unchanged | N/A |
| Leave and return | range without 5-hour data, then back to one with it | stored choices as before; that weekly press is not applied | N/A |
| Empty range | no data at all | controls as today | N/A |
| Mixed 24-hour range | number then no number | slope on points with a number, nil on others; reset markers kept | N/A |

</frozen-after-approval>

## Code Map

- `cc-hdrm/Views/AnalyticsView.swift` (`SeriesVisibility`) -- per-range and session-only.
- `cc-hdrm/Views/AnalyticsView.swift` (`hasFableData`) --, the same gate pattern to follow.
- `cc-hdrm/Views/AnalyticsView.swift` (`body`) -- passes visibility to `UsageChart`.
- `cc-hdrm/Views/AnalyticsView.swift` (`seriesToggles`) -- chips.
- `cc-hdrm/Views/UsageChart.swift:32` -- `anySeriesVisible` gives the "Select a series" state. Already takes effective flags, so no change.
- `cc-hdrm/Views/StepAreaChartView.swift:185,395,422` -- points, resets and slope already skip nil 5-hour values. No change.
- `cc-hdrm/Views/BarChartView.swift:489,593` -- bars skip a nil peak; reset dots ignore series flags. No change.
- `cc-hdrm/Services/HistoricalDataService.swift:76,914` -- a missing 5-hour value stays nil through persistence and rollups.

## Tasks & Acceptance

**Execution:**
- [x] `cc-hdrm/Views/AnalyticsView.swift` -- add `isFiveHourHidden`, `SeriesVisibility.effective` and `setSevenDay`; use them for the chart and chips; log when the decision flips.
- [x] `cc-hdrmTests/Views/AnalyticsViewTests.swift` -- cover the matrix, including a real database.
- [x] `_bmad-output/implementation-artifacts/sprint-status.yaml` -- set `26-4-analytics-adapt-to-data: done` only.

**Acceptance Criteria:**
- Given a long range spanning a state change, when it loads, then old 5-hour data can still show.
- Given a 24-hour range without 5-hour data, when it loads, then no 5-hour toggle shows.
- Given a range with 5-hour data, when any stored choice is applied, then the result equals that choice.

## Spec Change Log

## Design Notes

Defaults chosen, since no human is available:
- **Empty range:** counts as "nothing to decide from", so the controls stay as today. An account with a number would otherwise lose its toggle on a fresh install, on the first frame of every window open, and in an empty range. The cost: an account with no number sees the 5-hour chip briefly on window open, or for as long as a range is wholly empty. The account's state cannot break this tie, by rule.
- **While a range loads:** the decision follows the data on screen until the new data arrives. A failed load keeps the old data, so the chips still match the chart.
- **Weekly chip with 5-hour hidden:** its press is stored in `sevenDayWhileFiveHourHidden`, not `sevenDay`. Writing to `sevenDay` would leave the chip stuck on while 5-hour is the only stored choice, and would change the stored choice.
- **Weekly fallback and Fable:** with 5-hour on and 7-day off, weekly shows only while nothing else does. Switching Fable on hides weekly again, and switching Fable off brings it back. A weekly press replaces this rule for that range until 5-hour data returns.
- **A newer choice wins:** a weekly press with 5-hour data clears any older press made while hidden.
- **"3-month range":** the app has no such range. The 3-month acceptance criterion is met by the All range, and 7-day and 30-day use the same decision.
- **Chart views unchanged:** they already skip nil values point by point, so this story only changes the flags they receive.

## Verification

**Commands:**
- `/usr/bin/lockf -k /tmp/cchdrm-xcodebuild.lock nice -n 15 xcodebuild -jobs 4 -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test` -- expected: all tests pass.

**Manual checks (if no CLI):**
- Not run: no app launches on this machine. On a verified Ultra account, check that the 24-hour range has no 5-hour chip and no stray separator, that the chart gets the effective flags, and that the weekly chip responds. Tests cover the rule, not this view wiring: the accessibility tree is empty without a window.

## Suggested Review Order

**The decision**

- Entry point: hide only when the range has data and none of it is 5-hour.
  [`AnalyticsView.swift:112`](../../cc-hdrm/Views/AnalyticsView.swift#L112)

- What to draw is computed, never stored, so choices survive hiding.
  [`AnalyticsView.swift:34`](../../cc-hdrm/Views/AnalyticsView.swift#L34)

**The controls**

- A press while hidden is kept apart, so the chip responds and the stored choice stays.
  [`AnalyticsView.swift:43`](../../cc-hdrm/Views/AnalyticsView.swift#L43)

- The chip reads what is drawn, including the weekly fallback.
  [`AnalyticsView.swift:77`](../../cc-hdrm/Views/AnalyticsView.swift#L77)

- The 5-hour chip and its separator go together.
  [`AnalyticsView.swift:551`](../../cc-hdrm/Views/AnalyticsView.swift#L551)

- The chart receives effective flags; the chart views needed no change.
  [`AnalyticsView.swift:159`](../../cc-hdrm/Views/AnalyticsView.swift#L159)

- Logged only when the decision flips, not on every poll.
  [`AnalyticsView.swift:366`](../../cc-hdrm/Views/AnalyticsView.swift#L366)

**Tests**

- With 5-hour data, every stored choice is drawn exactly as stored.
  [`AnalyticsViewTests.swift:885`](../../cc-hdrmTests/Views/AnalyticsViewTests.swift#L885)

- Slope stays on points with a number, in a mixed range.
  [`AnalyticsViewTests.swift:1014`](../../cc-hdrmTests/Views/AnalyticsViewTests.swift#L1014)

- Real database: All shows old 5-hour data; 24 hours hides the series.
  [`AnalyticsViewTests.swift:1050`](../../cc-hdrmTests/Views/AnalyticsViewTests.swift#L1050)
