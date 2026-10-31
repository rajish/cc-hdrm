---
title: 'Value and Headroom Analysis per Weekly Cycle (Story 26.5)'
type: 'feature'
created: '2026-10-31'
status: 'done'
baseline_commit: 'd27bdfead334aca701950b14b07fcc8354754386'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-26-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Since the 5-hour limit was retired (2026-10-31 08:03 UTC), reset events arrive about weekly with `fiveHourPeak` nil. `HeadroomAnalysisService.aggregateBreakdown` skips them and `SubscriptionValueCalculator.periodDays` treats one weekly event as a 1-day span, so headroom breakdown, value $, cycle utilisation and insights show 0% / $0 or nonsense.

**Approach:** Classify each `ResetEvent` as a weekly cycle (post-cutover, no 5h peak, has `sevenDayUtil`) or a legacy 5h event. Weekly cycles get a two-band breakdown from `sevenDayUtil` × weekly credits and count as 7 days of capacity each. Legacy events use their stored credits (no recomputation, no `fiveHourCredits`).

## Boundaries & Constraints

**Always:** Legacy 5h events keep their stored breakdown, including stored constrained credits, in aggregates. Weekly breakdown clamps the peak to 0–100. Log skipped events at info level.

**Ask First:** Any schema change or write to existing `reset_events` rows.

**Never:** `DELETE`/`DROP` on historical tables; touch tier recommendation or pattern detection (26.6); remove `fiveHourCredits` (26.9); edit `AppState`, `AppDelegate`, `GaugeIcon` (26.1) or TPP services (26.7); change reset detection.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Weekly cycle | post-cutover event, peak nil, 7d 70%, Pro | used 70% / unused 30%; used credits 3.5M; `.week` value $ > 0 at 70% | N/A |
| Legacy event | peak 72, stored used/constrained/unused | aggregate uses stored credits unchanged | N/A |
| Legacy, no stored credits | peak set, credits nil, known tier | breakdown rebuilt from the historical 5h limit | unknown tier: skipped, info log |
| Pre-cutover peak-nil event | 5h reset after sleep, ts < cutover | not a weekly cycle; skipped | info log |
| Mixed range | legacy + weekly events | days = legacy span (capped) + 7 × weekly count | N/A |
| Over 100% | 7d util 104 | used 100 / unused 0 | N/A |

</frozen-after-approval>

## Code Map

- `cc-hdrm/Models/ResetEvent.swift` -- add cutover constant and `isWeeklyCycle`.
- `cc-hdrm/Models/HeadroomBreakdown.swift` -- single-event breakdown loses constrained fields; `PeriodSummary` keeps them for legacy aggregates.
- `cc-hdrm/Services/HeadroomAnalysisService.swift` + `HeadroomAnalysisServiceProtocol.swift` -- `analyzeResetEvent(sevenDayPeak:creditLimits:)`; `aggregateBreakdown` weekly vs legacy branches.
- `cc-hdrm/Services/SubscriptionValueCalculator.swift:75-89` -- `periodDays` adds 7 days per weekly cycle; used by `HeadroomBreakdownBar.percentageOnlyUtilization` and `CycleUtilizationCalculator` unchanged.
- `cc-hdrm/Services/ValueInsightEngine.swift:79-110` -- 24h copy says "today"; rebase to "this cycle".
- `cc-hdrm/Services/HistoricalDataService.swift:610-705` -- `recordResetEvent` stores weekly used/unused credits for peak-nil events; constrained NULL.
- Preview mocks in `cc-hdrm/Views/HeadroomBreakdownBar.swift:~308` and `cc-hdrm/Views/AnalyticsView.swift:~589`; `cc-hdrmTests/Mocks/MockHeadroomAnalysisService.swift`.
- Tests building legacy events with nil stored credits: `HeadroomAnalysisServiceTests`, `SubscriptionValueCalculatorTests`, `ValueInsightEngineTests`, `CycleUtilizationCalculatorTests`, `HeadroomBreakdownBarTests`, `AnalyticsViewTests`, `HistoricalDataServiceTests` (credit population).

## Tasks & Acceptance

**Execution:**
- [x] `cc-hdrm/Models/ResetEvent.swift` -- add `fiveHourLimitRetiredAtMs` (1793433780000) and `isWeeklyCycle` -- single classification rule.
- [x] `cc-hdrm/Models/HeadroomBreakdown.swift` -- two-band `HeadroomBreakdown`.
- [x] `cc-hdrm/Services/HeadroomAnalysisService*.swift` -- weekly analysis + aggregation per matrix.
- [x] `cc-hdrm/Services/SubscriptionValueCalculator.swift` -- weekly-aware `periodDays`.
- [x] `cc-hdrm/Services/ValueInsightEngine.swift` -- 24h copy names the weekly cycle; fix stale 5h comment.
- [x] `cc-hdrm/Services/HistoricalDataService.swift` -- record weekly credits.
- [x] Mocks/previews -- new protocol signature.
- [x] Tests -- legacy fixtures carry stored credits; add weekly-cycle tests for each matrix row, value $, cycle utilisation and recording.

**Acceptance Criteria:**
- Given a weekly cycle with 70% peak, when the breakdown is computed, then it reports 70% used / 30% unused and a non-zero value $.
- Given only weekly-cycle events, when value, cycle utilisation or insights are computed, then no result is 0% or $0 unless the peak was 0.
- Given legacy events with stored credits, when aggregated, then results equal their stored breakdown.

## Spec Change Log

- 2026-11-01 (code review): matrix row "Legacy, no stored credits" changed from "skipped" to "rebuilt from the historical 5h limit". 15 real Feb 2026 events have a peak but no stored credits; skipping them dropped old 5h history that the epic says is kept ("Old 5h-based events keep their breakdown", "No data loss"). The rebuild uses a private constant table, not `RateLimitTier.fiveHourCredits`.
- 2026-11-01 (code review): legacy events inside the 7 days before the first weekly cycle are excluded from value, capacity and data span, since the weekly cycle already contains their usage.

## Design Notes

Cutover timestamp is needed because pre-cutover 5h resets after a long sleep also have `fiveHourPeak` nil (16 such rows in a real DB); without it they would each add 7 phantom days. A weekly reset event represents its whole 7-day cycle, so in 24h/7d views the value shown is the full cycle that ended.

## Verification

**Commands:**
- `xcodebuild -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test` -- expected: all tests pass.

## Suggested Review Order

**Classifying events**

- Single rule: post-cutover, no 5h peak, has weekly value; cutover timestamp avoids sleep false positives.
  [`ResetEvent.swift:29`](../../cc-hdrm/Models/ResetEvent.swift#L29)

**Breakdown and aggregation**

- Weekly cycles recomputed from weekly credits; legacy events use stored credits, never `fiveHourCredits`.
  [`HeadroomAnalysisService.swift:36`](../../cc-hdrm/Services/HeadroomAnalysisService.swift#L36)

- Two-band single-cycle breakdown, peak clamped to 0–100.
  [`HeadroomAnalysisService.swift:20`](../../cc-hdrm/Services/HeadroomAnalysisService.swift#L20)

- Two-band model; period summary keeps constrained only for legacy aggregates.
  [`HeadroomBreakdown.swift:1`](../../cc-hdrm/Models/HeadroomBreakdown.swift#L1)

**Value, capacity and insight**

- Each weekly cycle adds 7 days of capacity; legacy span logic unchanged.
  [`SubscriptionValueCalculator.swift:74`](../../cc-hdrm/Services/SubscriptionValueCalculator.swift#L74)

- Data span counts 168h per weekly cycle so 24h/7d views show the dollar bar.
  [`AnalyticsView.swift:234`](../../cc-hdrm/Views/AnalyticsView.swift#L234)

- 7d deviation insight measures history in capacity days.
  [`ValueInsightEngine.swift:125`](../../cc-hdrm/Services/ValueInsightEngine.swift#L125)

- 24h copy names the cycle that just ended.
  [`ValueInsightEngine.swift:92`](../../cc-hdrm/Services/ValueInsightEngine.swift#L92)

**Recording**

- New weekly resets store used/unused weekly credits; constrained stays NULL.
  [`HistoricalDataService.swift:666`](../../cc-hdrm/Services/HistoricalDataService.swift#L666)

**Tests**

- Legacy fixtures derive stored credits from their peak.
  [`ResetEventFixtures.swift:10`](../../cc-hdrmTests/Mocks/ResetEventFixtures.swift#L10)

- Weekly analysis and matrix rows.
  [`HeadroomAnalysisServiceTests.swift:63`](../../cc-hdrmTests/Services/HeadroomAnalysisServiceTests.swift#L63)

### Review Findings

- [x] [Review][Patch] Legacy 5h events without stored credits were skipped, dropping Feb 2026 history — rebuilt from historical 5h limits [cc-hdrm/Services/HeadroomAnalysisService.swift]
- [x] [Review][Patch] Legacy events inside the first weekly cycle were counted twice (usage, capacity, data span) — excluded [cc-hdrm/Models/ResetEvent.swift]
- [x] [Review][Patch] Weekly credits were written for pre-cutover peak-nil rows — gated on the cutover timestamp [cc-hdrm/Services/HistoricalDataService.swift]
- [x] [Review][Patch] Non-finite weekly peak propagated NaN — treated as 0 [cc-hdrm/Services/HeadroomAnalysisService.swift]
- [x] [Review][Defer] Cycle chart groups by month before de-duplicating; unresolvable-tier weekly cycle still counted in capacity; month range can count 5 cycles — see deferred-work.md
