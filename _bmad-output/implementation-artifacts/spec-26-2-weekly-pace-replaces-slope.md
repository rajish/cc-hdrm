---
title: 'Weekly Pace Replaces Slope (Story 26.2)'
type: 'feature'
created: '2026-11-01'
status: 'done'
baseline_commit: 'd64f6966fda625b7d26121539364811822f60123'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-26-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The menu bar arrow still comes from the 4-level slope (`SlopeCalculationService`, credit-normalised to 5h). On 1%-step weekly data it flips between flat and rising, and it answers the wrong question.

**Approach:** Replace slope with weekly pace computed from `seven_day.utilization` and `resets_at` only. Menu bar shows `↗` only when run-out is projected before the weekly reset. The weekly popover gauge gets a pace line. Delete slope end to end.

## Boundaries & Constraints

**Always:** Formulas exactly as the epic: `weekStart = resetsAt − 7d`; `elapsed = clamp((now − weekStart)/7d, 0…1)`; `paceDelta = utilization − elapsed×100`; `rate = utilization/(now − weekStart)`; `runOut = now + (100 − utilization)/rate`, shown only when `runOut < resetsAt` and ≥ 4h of the week have passed. Pace recalculates on every poll (no buffer, no history, no tier credits). Pace is never colour-only. Arrow never shows when exhausted or disconnected.

**Ask First:** Any change to notification, analytics series, or settings behaviour.

**Never:** Remove the 5h ring or add the sparkline (26.3); change analytics defaults (26.4); remove `fiveHourCredits` (26.9); touch HeadroomAnalysis/value services (26.5) or TPP services (26.7); delete data; modify `cc-hdrm/cc_hdrm.entitlements`; add a "will run out" notification.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Start of week | util 0, 1h elapsed | paceDelta ≈ −0.6, no run-out | N/A |
| Mid-week on pace | util 50, 3.5d elapsed | paceDelta 0, no run-out, "On pace" | N/A |
| Ahead of pace | util 60, 3d elapsed | paceDelta ≈ 17.1, run-out now+2d, `40% ↗`, "Ahead of pace — runs out ~…" | N/A |
| Behind pace | util 20, 5d elapsed | paceDelta < 0, no run-out, no arrow | N/A |
| Missing resets_at | resetsAt nil | no pace, no arrow, no pace line | N/A |
| 0% utilization | util 0, 3d elapsed | paceDelta ≈ −42.9, no run-out | rate 0 → no division |
| < 4h elapsed | util 10, 2h elapsed | paceDelta computed, no run-out | N/A |
| Exhausted | util ≥ 100 | no pace (menu bar countdown applies) | N/A |

</frozen-after-approval>

## Code Map

- `cc-hdrm/State/AppState.swift` -- `fiveHourSlope`/`sevenDaySlope` (L64-65), `menuBarText` arrow (L186-193), `updateSlopes` (L246-250). Add computed `weeklyPace` from `sevenDay` + `Date()`.
- `cc-hdrm/Services/PollingEngine.swift` -- `slopeCalculationService` property/init (L16, L44, L59), slope block (L343-360). Reset detection lives elsewhere; deferred 26.7 reset-miss item is not touched.
- `cc-hdrm/App/AppDelegate.swift` -- slope service (L20, L106-108, L162), bootstrap (L276-304), VoiceOver slope clause (L587-592).
- `cc-hdrm/Views/HeadroomRingGauge.swift` -- `slopeLevel` + custom init (L15-31), `SlopeIndicator` (L94-97).
- `cc-hdrm/Views/SevenDayGaugeSection.swift` -- slope in a11y (L29) and gauge (L51); pace line goes under `CountdownLabel`.
- `cc-hdrm/Views/FiveHourGaugeSection.swift` -- slope in a11y (L28) and gauge (L48); remove only the slope.
- `cc-hdrm/Views/StepAreaChartView.swift` -- `ChartPoint.slopeLevel` (L319, L277, L361, L543), `computeSlopeAtEachPoint` (L416-446), tooltip slope text (L987, L1027).
- `cc-hdrm/Models/RateLimitTier.swift` -- `normalizationFactor` + `validateCustomLimits` exist only for slope; orphaned.
- `cc-hdrm/Models/UsageWindow.swift` -- only used by slope service; orphaned.
- `cc-hdrm/Extensions/Date+Formatting.swift` -- `absoluteTimeString()` formatters reused for run-out time.
- Delete: `cc-hdrm/Services/SlopeCalculationService.swift`, `cc-hdrm/Services/SlopeCalculationServiceProtocol.swift`, `cc-hdrm/Models/SlopeLevel.swift`, `cc-hdrm/Views/SlopeIndicator.swift`.
- Tests: delete `cc-hdrmTests/Models/SlopeLevelTests.swift`, `cc-hdrmTests/Models/UsageWindowTests.swift`, `cc-hdrmTests/Services/SlopeCalculationServiceTests.swift`, `cc-hdrmTests/Views/SlopeIndicatorTests.swift`, `cc-hdrmTests/State/AppStateSlopeTests.swift`; edit `cc-hdrmTests/App/AppDelegateTests.swift` (L441-511), `cc-hdrmTests/Views/UsageChartTests.swift` (L413-457, L497-503), `cc-hdrmTests/Models/RateLimitTierTests.swift` (L129-166).

## Tasks & Acceptance

**Execution:**
- [x] `cc-hdrm/Models/WeeklyPace.swift` -- new value type: `paceDelta`, `runOut?`, failable init `(utilization:resetsAt:now:)` returning nil for missing resetsAt or util ≥ 100 -- pure, testable pace model.
- [x] `cc-hdrm/State/AppState.swift` -- drop slope state/method; add `weeklyPace`; arrow when `weeklyPace?.runOut != nil` and not exhausted -- menu bar pace.
- [x] `cc-hdrm/Services/PollingEngine.swift`, `cc-hdrm/App/AppDelegate.swift` -- remove slope wiring and bootstrap; VoiceOver says "ahead of pace, runs out around …" when projected -- slope removal.
- [x] `cc-hdrm/Views/HeadroomRingGauge.swift`, `cc-hdrm/Views/FiveHourGaugeSection.swift`, `cc-hdrm/Views/StepAreaChartView.swift` -- remove slope params, indicator, per-point slope and tooltip text -- slope removal.
- [x] `cc-hdrm/Views/SevenDayGaugeSection.swift` -- pace line "On pace" / "Ahead of pace — runs out ~<day time>" below countdown; a11y reads pace -- popover pace.
- [x] `cc-hdrm/Extensions/Date+Formatting.swift` -- `dayTimeString()` shared by `absoluteTimeString()` and the run-out text -- one formatting source.
- [x] `cc-hdrm/Models/RateLimitTier.swift`, `cc-hdrm/Models/UsageWindow.swift` -- remove orphans.
- [x] Delete the four slope source files and their tests; `xcodegen generate`.
- [x] `cc-hdrmTests/Models/WeeklyPaceTests.swift` -- every matrix row, hand-calculated; menu bar arrow, VoiceOver and pace line tests replace slope tests.

**Acceptance Criteria:**
- Given weekly usage ahead of an even pace with ≥ 4h elapsed, when the menu bar renders, then it shows `N% ↗` and the popover shows "Ahead of pace — runs out ~<day time>".
- Given usage at or behind pace, when the popover renders, then the pace line reads "On pace" and no arrow shows.
- Given the codebase, when searched, then `SlopeLevel`, `SlopeIndicator`, `SlopeCalculationService`, `updateSlopes`, `computeSlopeAtEachPoint` and `normalizationFactor` no longer exist.

## Spec Change Log

## Design Notes

`runOut < resetsAt` is algebraically `paceDelta > 0` (util·T > 100·t), so "ahead of pace" and the arrow agree except during the first 4h. Pace is a computed property, not stored state: it uses inputs already in `AppState.sevenDay`, refreshes on every poll, and needs no PollingEngine wiring. Run-out time reuses the app's existing day/time format ("~Thu 2:00 PM"), matching the countdown's "at Thu 9:00 AM" directly above it.

## Verification

**Commands:**
- `xcodegen generate && xcodebuild ... test` (resource-limited command from the brief) -- expected: all tests pass.
- `grep -rn "SlopeLevel\|SlopeIndicator\|SlopeCalculation\|updateSlopes\|computeSlopeAtEachPoint\|normalizationFactor\|UsageWindow\b" cc-hdrm cc-hdrmTests` -- expected: no matches.

## Suggested Review Order

**Pace model**

- Entry point: epic formulas, nil for missing reset or exhausted, 4h gate before projecting.
  [`WeeklyPace.swift:20`](../../cc-hdrm/Models/WeeklyPace.swift#L20)

- Strict `runOut < resetsAt`; equivalent to `paceDelta > 0` after the first 4h.
  [`WeeklyPace.swift:34`](../../cc-hdrm/Models/WeeklyPace.swift#L34)

- Visual and spoken copy live together so they cannot drift.
  [`WeeklyPace.swift:38`](../../cc-hdrm/Models/WeeklyPace.swift#L38)

**Menu bar**

- Pace computed on read from `sevenDay`; no stored state, no polling wiring.
  [`AppState.swift:134`](../../cc-hdrm/State/AppState.swift#L134)

- Arrow only when run-out is projected before reset.
  [`AppState.swift:195`](../../cc-hdrm/State/AppState.swift#L195)

- VoiceOver mirrors the arrow with no time, so it does not re-announce every poll.
  [`AppDelegate.swift:546`](../../cc-hdrm/App/AppDelegate.swift#L546)

- Arrow transitions logged once per change.
  [`AppDelegate.swift:598`](../../cc-hdrm/App/AppDelegate.swift#L598)

**Popover**

- Pace line under the weekly countdown; VoiceOver reads the same pace.
  [`SevenDayGaugeSection.swift:24`](../../cc-hdrm/Views/SevenDayGaugeSection.swift#L24)

- One day/time formatter shared by reset and run-out text.
  [`Date+Formatting.swift:97`](../../cc-hdrm/Extensions/Date+Formatting.swift#L97)

**Slope removal**

- Polling starts right after outage restore; slope bootstrap gone.
  [`AppDelegate.swift:271`](../../cc-hdrm/App/AppDelegate.swift#L271)

- Chart points lose per-point slope; tooltip loses slope text.
  [`StepAreaChartView.swift:336`](../../cc-hdrm/Views/StepAreaChartView.swift#L336)

- Normalisation factor and its validator removed with their only consumer.
  [`RateLimitTier.swift:84`](../../cc-hdrm/Models/RateLimitTier.swift#L84)

- Ring gauge without slope parameter.
  [`HeadroomRingGauge.swift:16`](../../cc-hdrm/Views/HeadroomRingGauge.swift#L16)

**Tests**

- Hand-calculated matrix rows with fixed `now`.
  [`WeeklyPaceTests.swift:17`](../../cc-hdrmTests/Models/WeeklyPaceTests.swift#L17)

- Menu bar arrow cases incl. critical band and first 4h.
  [`AppStateWeeklyPaceTests.swift:19`](../../cc-hdrmTests/State/AppStateWeeklyPaceTests.swift#L19)

- Menu bar VoiceOver pace clause.
  [`AppDelegateTests.swift:443`](../../cc-hdrmTests/App/AppDelegateTests.swift#L443)

- Popover pace line and unavailable labels.
  [`SevenDayGaugeSectionTests.swift:212`](../../cc-hdrmTests/Views/SevenDayGaugeSectionTests.swift#L212)
  [`FiveHourGaugeSectionTests.swift:43`](../../cc-hdrmTests/Views/FiveHourGaugeSectionTests.swift#L43)
