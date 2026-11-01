---
title: 'Weekly-First Popover and Sparkline When There Is No 5-Hour Number (Story 26.3)'
type: 'feature'
created: '2026-11-01'
status: 'done'
baseline_commit: '803c43d6a065d644f1ab0ed08f6c69b602934acb'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-26-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** With no 5-hour number, the popover still draws weekly as a small secondary ring, and an "Open analytics" link sits where the chart belongs. Nothing shows how the week is going over time.

**Approach:** With no 5-hour number, draw the weekly ring large and show the current weekly cycle in the sparkline slot, with an even-pace line. Clicking the chart opens analytics. If the chart cannot be drawn, keep the link.

## Boundaries & Constraints

**Always:** With a 5-hour number, rings, sizes, order, the 24-hour sparkline, labels, VoiceOver and the data refresh stay as they are. Re-evaluate on every poll. Sleep gaps render as gaps.

**Ask First:** Nothing open. This runs unattended, so defaults are recorded in Design Notes.

**Never:** `DELETE`, `DROP` or schema changes. Change `SparklinePathBuilder.buildSegments`. Run rollups from the poll path. Modify `cc-hdrm/cc_hdrm.entitlements`. Change other status lines in `sprint-status.yaml`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Weekly chart | no number, reset known, at least 1 hour of data | large ring, chart with even-pace line, no link | N/A |
| No reset time | no number, reset nil or passed | large ring, "Open analytics" link, no chart | no crash |
| Too little data | no number, under 1 hour of unbroken data | large ring, link, no chart | N/A |
| Not rolled up yet | raw polls older than 24 hours | still on the chart, no duplicates | N/A |
| Already rolled up | 5-minute rollups for days 2–7 | on the chart, no duplicates | N/A |
| Sleep gap | over 60 minutes without data | gap band; the flat line reaches the gap | N/A |
| Ordinary poll | same cycle, data loaded | new point added in memory, no database read | N/A |
| New cycle | reset moves over 60 seconds | old points cleared, new cycle loaded | N/A |
| Reset jitter | reset moves under 60 seconds | no reload | N/A |
| Load fails | database error | link stays, retried next poll | error logged |
| Number returns | none → number | small ring and 24-hour sparkline, weekly data cleared | N/A |
| Number goes | number → none | large ring and weekly chart at that poll | N/A |
| Number present | any | ring 56, 24-hour fetch every poll, no rollup read | N/A |

</frozen-after-approval>

## Code Map

- `cc-hdrm/Services/PollingEngine.swift:362` -- sparkline refresh after each successful poll.
- `cc-hdrm/Services/HistoricalDataService.swift:240,819,1670` -- `getRecentPolls` reads raw polls at any age. `getRolledUpData(.week)` reads raw polls under 24 hours plus 5-minute rollups.
- `cc-hdrm/Views/AnalyticsView.swift:401` -- the only caller of `ensureRollupsUpToDate`, so raw polls stay raw until analytics opens.
- `cc-hdrm/State/AppState.swift:134,140` -- `hasNoFiveHourNumber`; `weeklyPace` shows the tick pattern.
- `cc-hdrm/Views/Sparkline.swift:35,249` -- `buildSegments` stays untouched; `mergeShortSegments` is reused.
- `cc-hdrm/Views/PopoverView.swift:168` -- sparkline slot. `cc-hdrm/Views/SevenDayGaugeSection.swift:67` -- ring.
- `cc-hdrm/App/AppDelegate.swift:221,387` -- clear history and sign out empty the sparkline.
- `cc-hdrm/Models/WeeklyPace.swift:5` -- `weekDuration`.

## Tasks & Acceptance

**Execution:**
- [x] `cc-hdrm/Models/WeeklySparklineData.swift` -- add cycle range, raw and rollup merge, and 5-minute thinning -- pure and testable.
- [x] `cc-hdrm/State/AppState.swift` -- add `weeklySparklineData`, `weeklyCycle` and an update method -- kept apart from the 24-hour data.
- [x] `cc-hdrm/Services/PollingEngine.swift` -- branch the refresh on `hasNoFiveHourNumber`; load once per cycle, then append -- the number path keeps its query.
- [x] `cc-hdrm/Views/Sparkline.swift` -- add weekly segments, the even-pace line, the label and a VoiceOver action -- only when `weeklyCycle` is set.
- [x] `cc-hdrm/Views/SevenDayGaugeSection.swift` -- ring 96/7 with no number, 56/4 otherwise.
- [x] `cc-hdrm/Views/PopoverView.swift` -- chart, else link.
- [x] `cc-hdrm/App/AppDelegate.swift` -- empty the weekly data on clear history and sign out.
- [x] `cc-hdrmTests/Models/WeeklySparklineDataTests.swift`, `cc-hdrmTests/Views/SparklineTests.swift`, `cc-hdrmTests/Views/PopoverViewTests.swift`, `cc-hdrmTests/Views/SevenDayGaugeSectionTests.swift`, `cc-hdrmTests/Services/PollingEngineTests.swift` -- cover every matrix row, including a real database.
- [x] `_bmad-output/implementation-artifacts/sprint-status.yaml` -- set `26-3-weekly-first-popover-no-five-hour: review` only.

**Acceptance Criteria:**
- Given no 5-hour number, when the popover opens, then the order is large weekly ring, reset time, pace line, Fable ring, chart, footer.
- Given the weekly chart, when VoiceOver reads it, then it says "Weekly usage chart. Double-tap to open analytics."
- Given the even-pace line, when drawn, then it runs from 0% at the cycle start to 100% at the reset.
- Given a 5-hour number, when any poll arrives, then the 24-hour query runs and the rollup query does not.

## Spec Change Log

## Design Notes

Defaults chosen, since no human is available:
- **Refresh cost:** one full read per cycle, on entering the state or when the reset moves. Every other poll adds one point in memory. A full read can touch 60,000 rows at 10-second polling when analytics has never opened. Clear history and sign out empty the data, which triggers a reload.
- **Refresh safety:** a poll during a load leaves the load running. A clear during a load discards its result. The merge runs off the main thread.
- **Query:** no new service method. `getRolledUpData(.week)` alone misses raw polls older than 24 hours that were not rolled up, so raw polls from `getRecentPolls` are the base, and only rollups older than the first raw poll are added.
- **Horizontal axis:** the whole cycle, start to reset, so the even-pace line can reach 100% and the data stops at now.
- **Enough data:** at least 1 hour of unbroken data. One point of chart width is about 56 minutes, so less draws nothing readable.
- **Thinning:** one point per 5 minutes, matching rollups, which caps the array near 2,016 points.
- **Separate weekly segments:** `buildSegments` skips a flat run before a gap, which is rare for 5-hour data but normal for weekly. Fixing it there would change charts for accounts with a number.
- **Mid-cycle drop:** drawn as an ordinary step down.
- **Start of the week:** over 60 minutes with no data after the cycle start draws a gap band, like any other sleep gap. No band is drawn from the last poll to now.
- **Extra usage card:** stays between the Fable ring and the chart, as in the layout with a number.
- **24-hour data with no number:** emptied, so a returning number never flashes old points.

## Verification

**Commands:**
- `/usr/bin/lockf -k /tmp/cchdrm-xcodebuild.lock nice -n 15 xcodebuild -jobs 4 -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test` -- expected: all tests pass.

**Manual checks (if no CLI):**
- Not run: no app launches on this machine. On a verified Ultra account, check the chart's look, the section order and VoiceOver's double-tap. Tests cannot read the drawn order: the accessibility tree is empty without a window. The order is in `cc-hdrm/Views/PopoverView.swift`, in `authenticatedView`.

## Suggested Review Order

**The refresh rule**

- Entry point: one full read per cycle, then appends in memory.
  [`PollingEngine.swift:411`](../../cc-hdrm/Services/PollingEngine.swift#L411)

- A running load is left alone; restarting would discard slow reads every time.
  [`PollingEngine.swift:438`](../../cc-hdrm/Services/PollingEngine.swift#L438)

- A clear during a load must not restore deleted points.
  [`PollingEngine.swift:465`](../../cc-hdrm/Services/PollingEngine.swift#L465)

**The data**

- Raw polls are the base, because the week query misses raw polls not yet rolled up.
  [`WeeklySparklineData.swift:26`](../../cc-hdrm/Models/WeeklySparklineData.swift#L26)

- Unknown or passed reset means no cycle, which means the link.
  [`WeeklySparklineData.swift:11`](../../cc-hdrm/Models/WeeklySparklineData.swift#L11)

**The chart**

- Separate from `buildSegments`, so 5-hour charts stay untouched and flat runs reach gaps.
  [`Sparkline.swift:328`](../../cc-hdrm/Views/Sparkline.swift#L328)

- Even-pace endpoints are pure, so a test can pin them.
  [`Sparkline.swift:397`](../../cc-hdrm/Views/Sparkline.swift#L397)

- One unbroken hour decides between chart and link.
  [`Sparkline.swift:402`](../../cc-hdrm/Views/Sparkline.swift#L402)

- The label and action appear only on the weekly chart.
  [`Sparkline.swift:446`](../../cc-hdrm/Views/Sparkline.swift#L446)

**The popover**

- Chart, else link; the branch with a number comes first and is unchanged.
  [`PopoverView.swift:178`](../../cc-hdrm/Views/PopoverView.swift#L178)

- The chart's data and cycle are built here, where tests can read them.
  [`PopoverView.swift:223`](../../cc-hdrm/Views/PopoverView.swift#L223)

- Ring size follows the account state at every poll.
  [`SevenDayGaugeSection.swift:24`](../../cc-hdrm/Views/SevenDayGaugeSection.swift#L24)

**State**

- The minute tick registers only for accounts with no number.
  [`AppState.swift:156`](../../cc-hdrm/State/AppState.swift#L156)

- Clear history and sign out use this, so a running load can see the clear.
  [`AppState.swift:388`](../../cc-hdrm/State/AppState.swift#L388)

**Tests**

- Sparkline data switches both ways through the real poll path.
  [`PollingEngineTests.swift:2301`](../../cc-hdrmTests/Services/PollingEngineTests.swift#L2301)

- With a number: 24-hour query every poll, rollup query never.
  [`PollingEngineTests.swift:2338`](../../cc-hdrmTests/Services/PollingEngineTests.swift#L2338)

- Real database, before and after rollups run, with no duplicates.
  [`WeeklySparklineDataTests.swift:145`](../../cc-hdrmTests/Models/WeeklySparklineDataTests.swift#L145)

- Flat stretches reach the gap.
  [`SparklineTests.swift:946`](../../cc-hdrmTests/Views/SparklineTests.swift#L946)
