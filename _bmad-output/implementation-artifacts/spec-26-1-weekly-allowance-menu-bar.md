---
title: 'Weekly Allowance in the Menu Bar (Story 26.1)'
type: 'bugfix'
created: '2026-10-31'
status: 'done'
baseline_commit: 'd27bdfead334aca701950b14b07fcc8354754386'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-26-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Since 2026-10-31 the usage API returns `five_hour: null`. `AppState.displayedWindow` then falls back to `.fiveHour`, so the menu bar shows "—" and a grey icon while connected, and extra-usage $ text never appears.

**Approach:** The menu bar (text, colour, gauge icon, VoiceOver) always reads the weekly window (`sevenDay`). Delete the 5h/7d promotion machinery (`DisplayedWindow`, `displayedWindow`, `quotasRemaining`, "7d" promoted label). The gauge-icon corner dot shows the first scoped cap (Fable) at caution or worse.

## Boundaries & Constraints

**Always:** Weekly is the single plan-wide window for the menu bar. Arrow glyph is `↗`, shown only when the weekly slope is actionable and not exhausted. Decoding of `five_hour` stays untouched. Keep the "cc-hdrm:" accessibility prefix.

**Ask First:** Any change to pace maths, popover layout, notifications, settings or tier credits.

**Never:** Implement pace (26.2), redesign the popover (26.3), touch `fiveHourCredits`/settings (26.9), delete slope services, or modify `cc-hdrm/cc_hdrm.entitlements`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Weekly only | connected, fiveHour nil, sevenDay 17% | text `83%`, state `.normal`, gauge at 83 | N/A |
| 5h present | connected, fiveHour 90%, sevenDay 30% | text `70%` (5h ignored) | N/A |
| Weekly exhausted | sevenDay 100%, resetsAt +3d4h | text `↻ 3d 4h`, state `.exhausted` | no resetsAt → `0%` |
| Extra usage | sevenDay 100%, extra usage enabled | `$` text, extra-usage icon | N/A |
| Slope actionable | sevenDaySlope `.rising` or `.steep` | text `58% ↗` | none when exhausted |
| No weekly data | connected, sevenDay nil | `—`, disconnected icon | N/A |
| Fable dot | scopedLimits.first state caution/warning/critical/exhausted | dot in that state's colour | normal/absent → no dot |

</frozen-after-approval>

## Code Map

- `cc-hdrm/State/AppState.swift` -- `DisplayedWindow` enum (L43-47), `quotasRemaining` (L131-139), `displayedWindow` (L144-168, the bug), `menuBarHeadroomState` (L172-183), `displayedSlope` (L187-194), `isExtraUsageActive` (L197-202), `menuBarText` (L234-261). `countdownString()` in `cc-hdrm/Extensions/Date+Formatting.swift` already formats days.
- `cc-hdrm/App/AppDelegate.swift` -- `updateMenuBarDisplay()` (L521-641): icon overlay selection (L541-558), accessibility (L580-606), `previousDisplayedWindow` logging (L32, L612-629).
- `cc-hdrm/Views/GaugeIcon.swift` -- `SevenDayOverlay` (L21-28), `make(...sevenDayOverlay:)` (L74-90), `drawSevenDayDot` guard (L267-283), `drawSevenDayLabel` (L285-302), legacy wrapper (L385-387).
- `cc-hdrm/Views/SevenDayGaugeSection.swift` -- only consumer of `quotasRemaining` outside AppState (L33-35, L64-70).
- `cc-hdrm/Models/SlopeLevel.swift` -- `isActionable`, `accessibilityLabel`; read-only (deleted in 26.2).
- Tests: `cc-hdrmTests/State/AppStateTests.swift` (L171-560 menu bar, promotion, quotas; L759-808 extra usage), `cc-hdrmTests/State/AppStateSlopeTests.swift`, `cc-hdrmTests/App/AppDelegateTests.swift` (L267-500), `cc-hdrmTests/Views/GaugeIconTests.swift` (L120-190, L245), `cc-hdrmTests/Views/SevenDayGaugeSectionTests.swift` (L101-160).

## Tasks & Acceptance

**Execution:**
- [x] `cc-hdrm/State/AppState.swift` -- delete `DisplayedWindow`, `displayedWindow`, `quotasRemaining`, `displayedSlope`; `menuBarHeadroomState` = `sevenDay?.headroomState` when connected; `menuBarText` reads `sevenDay`, appends ` ↗` when `sevenDaySlope.isActionable`; `isExtraUsageActive` checks weekly only -- single weekly window.
- [x] `cc-hdrm/Views/GaugeIcon.swift` -- replace `SevenDayOverlay` with `capDot: HeadroomState? = nil`; dot draws for caution/warning/critical/exhausted; delete `drawSevenDayLabel` -- promotion label retired.
- [x] `cc-hdrm/App/AppDelegate.swift` -- gauge uses weekly headroom; `capDot` from `scopedLimits.first`; VoiceOver: `cc-hdrm: Claude weekly headroom: N percent, state[, slope]`, exhausted: `cc-hdrm: Claude weekly allowance exhausted, resets in <countdownString>`; remove `previousDisplayedWindow` -- weekly-first menu bar.
- [x] `cc-hdrm/Views/SevenDayGaugeSection.swift` -- remove quotas text and a11y clause -- orphaned by `quotasRemaining` removal.
- [ ] Tests listed in Code Map -- rewrite menu bar tests on `sevenDay`; delete promotion/quotas tests; add matrix cases (weekly-only, 5h ignored, `↻ 3d 4h`, extra usage on weekly, `↗` for steep, Fable dot incl. exhausted).

**Acceptance Criteria:**
- Given `five_hour: null` and a connection, when the menu bar renders, then it shows weekly headroom % and colour, not "—".
- Given the weekly window is exhausted with a reset 3 days 4 hours away, when the menu bar renders, then the text is `↻ 3d 4h`.
- Given weekly exhausted and extra usage enabled, when the menu bar renders, then the extra-usage $ text and icon show.
- Given VoiceOver, when focusing the status item, then it speaks weekly headroom.
- Given the codebase, when searched, then `DisplayedWindow`, `displayedWindow`, `quotasRemaining` and the "7d" promoted label no longer exist.

## Spec Change Log

## Design Notes

Fable cap is `scopedLimits.first`, matching `cc-hdrm/Services/NotificationService.swift` and `cc-hdrm/Views/AnalyticsView.swift`. Slope wiring stays until 26.2; the menu bar shows a fixed `↗` for any actionable slope, so `⬆` never reaches the menu bar. Removing quotas from the popover overlaps 26.3, but leaving it would keep a deleted API alive.

## Verification

**Commands:**
- `xcodegen generate && xcodebuild -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test` -- expected: all tests pass.
- `grep -rn "DisplayedWindow\|displayedWindow\|quotasRemaining\|displayedSlope\|SevenDayOverlay\|drawSevenDayLabel" cc-hdrm cc-hdrmTests` -- expected: no matches.

## Suggested Review Order

**Weekly-only menu bar state**

- Entry point: the bug fix — menu bar state reads `sevenDay` only, no promotion.
  [`AppState.swift:127`](../../cc-hdrm/State/AppState.swift#L127)

- Text: weekly countdown when exhausted, fixed `↗` for any actionable slope.
  [`AppState.swift:171`](../../cc-hdrm/State/AppState.swift#L171)

- Extra-usage mode now keys on weekly exhaustion only.
  [`AppState.swift:135`](../../cc-hdrm/State/AppState.swift#L135)

**Fable cap dot**

- Dot state computed once; reused for icon, VoiceOver and logging.
  [`AppDelegate.swift:527`](../../cc-hdrm/App/AppDelegate.swift#L527)

- Single rule for which cap states get a dot.
  [`GaugeIcon.swift:256`](../../cc-hdrm/Views/GaugeIcon.swift#L256)

- Gauge and extra-usage icons both accept the dot.
  [`GaugeIcon.swift:61`](../../cc-hdrm/Views/GaugeIcon.swift#L61)
  [`GaugeIcon.swift:119`](../../cc-hdrm/Views/GaugeIcon.swift#L119)

- Dot transitions logged only when the drawn dot changes.
  [`AppDelegate.swift:613`](../../cc-hdrm/App/AppDelegate.swift#L613)

**VoiceOver**

- Exhausted label speaks the weekly countdown in words.
  [`AppDelegate.swift:581`](../../cc-hdrm/App/AppDelegate.swift#L581)
  [`Date+Formatting.swift:69`](../../cc-hdrm/Extensions/Date+Formatting.swift#L69)

- Cap clause so the dot is never colour-only.
  [`AppDelegate.swift:596`](../../cc-hdrm/App/AppDelegate.swift#L596)

**Peripherals**

- Popover weekly section loses the "full 5h quotas left" line.
  [`SevenDayGaugeSection.swift:25`](../../cc-hdrm/Views/SevenDayGaugeSection.swift#L25)

- Tests: 5h ignored, Fable dot states, cap dot rendering.
  [`AppStateTests.swift:215`](../../cc-hdrmTests/State/AppStateTests.swift#L215)
  [`AppDelegateTests.swift:518`](../../cc-hdrmTests/App/AppDelegateTests.swift#L518)
  [`GaugeIconTests.swift:126`](../../cc-hdrmTests/Views/GaugeIconTests.swift#L126)
