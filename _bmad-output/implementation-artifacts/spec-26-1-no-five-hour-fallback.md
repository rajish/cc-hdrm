---
title: 'Show Weekly When There Is No 5-Hour Number (Story 26.1)'
type: 'bugfix'
created: '2026-11-01'
status: 'done'
baseline_commit: '38a3ce26826d692e369776555e7f61e778f8fcd0'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/planning-artifacts/sprint-change-proposal-2026-11-01.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Verified Ultra accounts get `five_hour: null` from the usage API while `seven_day` still arrives. `AppState.displayedWindow` stays on `.fiveHour`, so the menu bar shows "—" while connected and the popover shows an empty 5h ring.

**Approach:** Follow the data on every poll. When there is no 5-hour number but a weekly one exists, the menu bar reads weekly and the popover drops the 5-hour parts. Everything else stays as in 1.6.0.

## Boundaries & Constraints

**Always:** With a 5-hour number, display, promotion, slope, notifications and analytics stay exactly as in 1.6.0. Both windows nil keeps today's "—". The account can change state at any poll, with no restart.

**Ask First:** Nothing open. This runs unattended, so defaults are recorded in Design Notes.

**Never:** Delete 5-hour code, slope, promotion, benchmark or data paths. Add pace, a weekly sparkline, analytics, value, tier or tokens-per-percent changes; later stories own those. Modify `cc-hdrm/cc_hdrm.entitlements`, `sprint-status.yaml` or planning docs. Add `[patch]` to the commit message.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| No 5-hour number | connected, fiveHour nil, sevenDay 17% | window `.sevenDay`, text `83%`, state `.normal` | N/A |
| Both nil | connected, both nil | window `.fiveHour`, text `—`, state `.disconnected` | N/A |
| Disconnected, weekly retained | disconnected, fiveHour nil, sevenDay 17% | text `—`; popover still has no 5h ring | N/A |
| 5-hour present | connected, both present | promotion rules unchanged | N/A |
| Flip | present → null → present at next updates | window follows the data each time | N/A |
| Weekly exhausted | fiveHour nil, sevenDay 100%, reset in 3d 4h | text `↻ 3d 4h`, label says weekly | no reset → `0%` |
| Extra usage | fiveHour nil, sevenDay 100%, enabled | `$` text and extra-usage icon | N/A |
| Slope | fiveHour nil, sevenDaySlope `.rising` | arrow from weekly slope | none when exhausted |

</frozen-after-approval>

## Code Map

- `cc-hdrm/State/AppState.swift:131-168` -- `quotasRemaining`, `displayedWindow`; the single check lives here.
- `cc-hdrm/App/AppDelegate.swift:545-556` -- gauge overlay; `.promoted` draws the "7d" label.
- `cc-hdrm/App/AppDelegate.swift:590-606` -- VoiceOver label; exhausted path speaks minutes.
- `cc-hdrm/App/AppDelegate.swift:611-631` -- existing display-transition logging pattern.
- `cc-hdrm/Views/PopoverView.swift:127-172` -- 5h section, divider, sparkline.
- `cc-hdrm/Views/SevenDayGaugeSection.swift:33,65` -- quotas text and VoiceOver, both read `quotasRemaining`.
- `cc-hdrm/Views/Sparkline.swift:40-42` -- draws `fiveHourUtil` only, so it is blank with no 5-hour number.
- `cc-hdrm/Services/PollingEngine.swift:269,288` -- windows are set before `.connected`; errors keep old windows.
- `cc-hdrm/Extensions/Date+Formatting.swift:42` -- `countdownString()` already handles days. No change.
- `cc-hdrm/Services/SlopeCalculationService.swift` -- 7d slope is independent of 5h. No change.

## Tasks & Acceptance

**Execution:**
- [x] `cc-hdrm/State/AppState.swift` -- add `hasNoFiveHourNumber`; use it in `displayedWindow`; `quotasRemaining` returns nil without a 5-hour number.
- [x] `cc-hdrm/App/AppDelegate.swift` -- no `.promoted` overlay without a 5-hour number; name "weekly" in VoiceOver; log state changes once.
- [x] `cc-hdrm/Views/PopoverView.swift` -- hide the 5h section and its divider; replace the sparkline with an analytics button, shown only when analytics is available.
- [x] `cc-hdrmTests/State/AppStateTests.swift` -- update the nil-fiveHour test; add matrix cases.
- [x] `cc-hdrmTests/App/AppDelegateTests.swift` -- icon, VoiceOver and 5-hour-unchanged cases.
- [x] `cc-hdrmTests/Views/PopoverViewTests.swift`, `cc-hdrmTests/Views/SevenDayGaugeSectionTests.swift` -- hidden ring, launcher and quotas line.

**Acceptance Criteria:**
- Given `five_hour: null` while connected, when the menu bar updates, then it shows weekly % and colour, not "—".
- Given a 5-hour number, when any window state applies, then 1.6.0 display and promotion are unchanged.
- Given no 5-hour number, when the popover opens, then no 5h ring, leading divider, quotas line or blank sparkline appears, and analytics stays reachable.
- Given no 5-hour number, when VoiceOver reads a headroom label, then it says "weekly" and gives the reset in days and hours. The extra-usage and disconnected labels describe no window, so they stay as they are.
- Given the state flips, when the next update arrives, then one log line records it and repeated polls add none.

## Spec Change Log

- Review finding: the VoiceOver criterion read as covering the extra-usage and disconnected labels, which name no window. Amended the criterion to headroom labels. Known-bad state avoided: forcing "weekly" into text about prepaid dollars. KEEP: "weekly" on every headroom label.

## Design Notes

Defaults chosen, since no human is available:
- **Icon:** the "7d" label shows without a 5-hour number, so sighted users can tell the number is weekly. No dot: weekly is the displayed window.
- **VoiceOver:** "weekly" is added whenever weekly is displayed, including a promoted window on a 5-hour account (the allowed one-word change). The 5-hour wording stays. Spoken days and hours replace minutes only without a 5-hour number.
- **Sparkline:** hidden without a 5-hour number, because it only draws 5-hour data. A small toggle keeps analytics reachable. Story 26.3 adds the weekly chart.
- **Popover check ignores connection:** old windows survive errors, so the ring would otherwise flash back during a network blip. `displayedWindow` still requires `.connected`.
- **Log:** in the existing transition block in `updateMenuBarDisplay`. Both nil is neither state, so it does not count as a change. Tests read the tracker behind the log, because the logger itself cannot be observed.
- **Epic context:** not compiled. Epic 26 docs on master are superseded, so the 2026-11-01 proposal is the context.

## Verification

**Commands:**
- `/usr/bin/lockf -k /tmp/cchdrm-xcodebuild.lock nice -n 15 xcodebuild -jobs 4 -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test` -- expected: all tests pass.

**Manual checks (if no CLI):**
- Not run in this story: no app launches on this machine. On a verified Ultra account, confirm the popover has no line directly under the version label; automated tests cannot see that 1pt divider.

## Suggested Review Order

**The one check**

- Single definition; ignores connection so an outage cannot bring the ring back.
  [`AppState.swift:134`](../../cc-hdrm/State/AppState.swift#L134)

- Weekly only when connected with no 5-hour number; promotion below is untouched.
  [`AppState.swift:159`](../../cc-hdrm/State/AppState.swift#L159)

- Hides the quotas line and its VoiceOver text in one place.
  [`AppState.swift:144`](../../cc-hdrm/State/AppState.swift#L144)

**Menu bar**

- Weekly keeps the "7d" label; only the dot logic is untouched.
  [`AppDelegate.swift:548`](../../cc-hdrm/App/AppDelegate.swift#L548)

- VoiceOver names weekly whenever weekly is displayed.
  [`AppDelegate.swift:581`](../../cc-hdrm/App/AppDelegate.swift#L581)

- Days and hours replace minutes only without a 5-hour number.
  [`AppDelegate.swift:596`](../../cc-hdrm/App/AppDelegate.swift#L596)

- One log line per change; both nil does not count.
  [`AppDelegate.swift:633`](../../cc-hdrm/App/AppDelegate.swift#L633)

**Popover**

- Ring and leading divider follow the data.
  [`PopoverView.swift:128`](../../cc-hdrm/Views/PopoverView.swift#L128)

- Blank 5-hour sparkline becomes an analytics button, only when analytics exists.
  [`PopoverView.swift:178`](../../cc-hdrm/Views/PopoverView.swift#L178)

**Tests**

- Real API JSON through the poll path, flipping both ways.
  [`PollingEngineTests.swift:349`](../../cc-hdrmTests/Services/PollingEngineTests.swift#L349)

- Unchanged-behaviour proof for accounts with a 5-hour number.
  [`AppDelegateTests.swift:577`](../../cc-hdrmTests/App/AppDelegateTests.swift#L577)

- Drawn heights tie the flags to the rendered popover.
  [`PopoverViewTests.swift:576`](../../cc-hdrmTests/Views/PopoverViewTests.swift#L576)
