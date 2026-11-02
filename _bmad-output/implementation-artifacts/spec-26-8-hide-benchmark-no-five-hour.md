---
title: 'Hide the Benchmark When There Is No 5-Hour Number (Story 26.8)'
type: 'feature'
created: '2026-11-02'
status: 'done'
baseline_commit: '6698156cfd6c8f2a26d552ed55946ec711506ca5'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-26-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** On an account with no 5-hour number, the benchmark sends real requests, retries, and ends "inconclusive". It spends quota for nothing, and the analytics text still tells these users to run it.

**Approach:** Block a run in `BenchmarkService`, the only place a run can start. Hide Measure and explain why. Stop a run in progress as soon as the number is gone. Accounts with a number keep today's behaviour.

## Boundaries & Constraints

**Always:**
- The service guard is the real block. The view guards only keep the display right.
- The state is read live on every check, never stored. A state change takes effect at the next poll, in both directions.
- Past results stay: result cards, chart points on the 5-hour basis, and the weighting card.
- User wording stays in plain words.

**Ask First:** a weekly benchmark, a schema change, a change to measurement for accounts with a number.

**Never:** a `DELETE` or `DROP`, a change to `cc-hdrm/cc_hdrm.entitlements`, a change to the stored Measure preference.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Number present | `fiveHour` set | Validation and run as in 1.6.0, including 3 retries on zero change | N/A |
| No number, connected | `fiveHour` nil, `sevenDay` set | Validation returns `.noFiveHourNumber` | Log info |
| Run called with no number | Any caller | No credentials read, no request, no poll, no row, `[]` returned | `.failed` progress, log info |
| No number, disconnected | `fiveHour` nil, not connected | Validation still returns `.tokenExpired`; the run is still blocked | As above |
| Neither window | Connected, both nil | Blocked as no number, because there is nothing to measure against | Measure stays visible; validation stops it |
| Number gone before a request | Before a send or retry | That request is not sent; finished results are kept and returned | `.failed` progress, log warning |
| Number gone after a request | Forced poll leaves `fiveHour` nil | No retry, no row, no further model or variant | `.failed` progress, log warning |
| Alert open when number goes | "Proceed" tapped | Nothing starts, and results on screen stay | Log info |
| Number returns | `fiveHour` set again | Measure returns; a run works at the next poll | N/A |
| Measure preference off | No number, preference off | Section stays hidden as today, with no explanation | N/A |

</frozen-after-approval>

## Code Map

- `cc-hdrm/Services/BenchmarkService.swift` -- `validatePreconditions`, `runBenchmark`, `runVariant`. The only caller of `performForcedPoll` and the only sender of test requests.
- `cc-hdrm/Services/BenchmarkServiceProtocol.swift` -- `BenchmarkValidation`.
- `cc-hdrm/Views/BenchmarkSectionView.swift` -- Measure button, two alert "Proceed" buttons, `executeBenchmark` (the only caller of `runBenchmark`).
- `cc-hdrm/Views/SettingsView.swift:311` -- the "Enable Measure button" toggle. It only sets a preference and starts nothing.
- `cc-hdrm/Views/TPPSectionView.swift:128` -- empty state that points at the Measure button.
- `cc-hdrm/Services/TPPChartDataService.swift` `computeInsightText` -- 5-hour text that says "Run a benchmark". A no-number account sees it on the 5-hour basis picker option.
- `cc-hdrm/Views/AnalyticsView.swift:184` -- builds `TPPSectionView`.
- Read only: `cc-hdrm/State/AppState.swift:141` `hasNoFiveHourNumber`.

**Entry points searched:** Measure button; "Recent Measurement" Proceed; "Recent Activity Detected" Proceed. All three reach `runBenchmark` through `executeBenchmark`. There is no benchmark path in Settings (toggle and variants only), onboarding, notifications (no actions), keyboard shortcuts (only Settings Done and onboarding default), URL handlers, app intents or automatic triggers. `cc-hdrm/App/AppDelegate.swift` only constructs the service.

## Tasks & Acceptance

**Execution:**
- [x] `cc-hdrm/Services/BenchmarkServiceProtocol.swift` -- add `.noFiveHourNumber` -- validation result.
- [x] `cc-hdrm/Services/BenchmarkService.swift` -- guard validation and run; `runVariant` returns nil when the number is gone before a send or after a poll; the run then stops -- block all paths and stop retries.
- [x] `cc-hdrm/Views/BenchmarkSectionView.swift` -- hide Measure, show `noFiveHourNote`, guard `executeBenchmark` before results clear -- explanation and past results.
- [x] `cc-hdrm/Views/SettingsView.swift` -- show the note under the toggle with no number -- honest wording.
- [x] `cc-hdrm/Services/TPPChartDataService.swift`, `cc-hdrm/Services/TPPChartDataServiceProtocol.swift`, `cc-hdrm/Views/TPPSectionView.swift`, `cc-hdrm/Views/AnalyticsView.swift` -- drop "Run a benchmark" and Measure wording with no number; reload on a state change -- no advice the user cannot follow.
- [x] `cc-hdrmTests/Services/BenchmarkServiceTests.swift`, `cc-hdrmTests/Services/TPPChartDataServiceTests.swift`, `cc-hdrmTests/Views/BenchmarkSectionViewTests.swift` -- cover the matrix.
- [x] `_bmad-output/implementation-artifacts/sprint-status.yaml` -- set this story `done`.

**Acceptance Criteria:**
- Given no number, when `runBenchmark` is called directly, then no request, poll, credential read or stored row happens.
- Given a number, when the benchmark runs, then requests, retries and stored rows match today, proven by tests.
- Given the number goes and later returns, when each next poll lands, then validation and the run follow the current state.
- Given no number and past 5-hour benchmark rows, when the 5-hour basis is chosen, then the rows are charted.

## Design Notes

**Run in progress:** stop at the next check. A request already sent cannot be recalled, so the most a run can spend after the number goes is that one request. Finished measurements are valid and stay stored and shown. The run reports `.failed` rather than `.completed`.

**Why `fiveHour == nil` in the service, not `hasNoFiveHourNumber`:** with neither window the run has nothing to measure against either. Before this change it treated the missing "before" value as 0, so a number appearing mid-run would be stored as a false large change. The explanation uses `hasNoFiveHourNumber`, because it must not claim an account has no limit when nothing has loaded yet.

**Earlier cards:** starting a run clears them, as today. If the number goes and the run finished nothing, they come back. If it finished something, the new cards replace them, like any run.

**Insight text:** with no number, 5-hour rows are history, so the 5-hour basis gets one fixed line. No trend, comparison or benchmark prompt. The weekly basis and accounts with a number are unchanged. The no-rows text is never shown, because the empty state replaces it.

**Not touched:** `degradationSuggestion` in `cc-hdrm/Services/PassiveTPPEngine.swift` mentions the Measure button, but no production code reads it. The Settings toggle stays enabled so the preference survives a state change.

**Weekly benchmark:** not built. The API reports whole percents, so a usable run costs about 8% of the weekly allowance.

## Verification

**Commands:**
- `xcodegen generate`, then the locked `xcodebuild ... test` form with `-only-testing:` for `cc-hdrmTests/BenchmarkServiceNoFiveHourTests`, `cc-hdrmTests/BenchmarkServiceTests`, `cc-hdrmTests/BenchmarkSectionViewTests`, `cc-hdrmTests/TPPChartDataServiceBasisTests` and `cc-hdrmTests/TPPChartDataServiceTests` -- expected: new tests ran and passed.
- The same form with no `-only-testing`, once at the end -- expected: no new failures.

## Suggested Review Order

**The block**

- The real block: every run passes here, before any credential read or request.
  [`BenchmarkService.swift:179`](../../cc-hdrm/Services/BenchmarkService.swift#L179)

- Stops before each send and retry, so no further quota is spent.
  [`BenchmarkService.swift:260`](../../cc-hdrm/Services/BenchmarkService.swift#L260)

- Stops after a poll, replacing the old `?? 0` that caused retries.
  [`BenchmarkService.swift:287`](../../cc-hdrm/Services/BenchmarkService.swift#L287)

- Keeps finished results and reports failure instead of completed.
  [`BenchmarkService.swift:210`](../../cc-hdrm/Services/BenchmarkService.swift#L210)

- Validation refuses after the sign-in check, so disconnected accounts see sign-in first.
  [`BenchmarkService.swift:145`](../../cc-hdrm/Services/BenchmarkService.swift#L145)

**What the user sees**

- Measure hidden; read live, so it adapts at the next poll.
  [`BenchmarkSectionView.swift:71`](../../cc-hdrm/Views/BenchmarkSectionView.swift#L71)

- The explanation, also shown in Settings.
  [`BenchmarkSectionView.swift:39`](../../cc-hdrm/Views/BenchmarkSectionView.swift#L39)

- An open alert cannot start a run or clear results.
  [`BenchmarkSectionView.swift:277`](../../cc-hdrm/Views/BenchmarkSectionView.swift#L277)

- Earlier cards return when a stopped run finished nothing.
  [`BenchmarkSectionView.swift:42`](../../cc-hdrm/Views/BenchmarkSectionView.swift#L42)

- Settings says the same; the preference is untouched.
  [`SettingsView.swift:317`](../../cc-hdrm/Views/SettingsView.swift#L317)

**Analytics wording**

- One fixed line for history; no benchmark prompt or stale trend.
  [`TPPChartDataService.swift:323`](../../cc-hdrm/Services/TPPChartDataService.swift#L323)

- Empty state stops pointing at Measure with no number.
  [`TPPSectionView.swift:37`](../../cc-hdrm/Views/TPPSectionView.swift#L37)

- Reloads the text when the account changes state.
  [`TPPSectionView.swift:61`](../../cc-hdrm/Views/TPPSectionView.swift#L61)

**Tests**

- Service guards, mid-run stops, both state directions, retries unchanged with a number.
  [`BenchmarkServiceTests.swift:594`](../../cc-hdrmTests/Services/BenchmarkServiceTests.swift#L594)

- Past benchmarks stay charted with no number.
  [`TPPChartDataServiceTests.swift:442`](../../cc-hdrmTests/Services/TPPChartDataServiceTests.swift#L442)

- When earlier cards come back.
  [`BenchmarkSectionViewTests.swift:35`](../../cc-hdrmTests/Views/BenchmarkSectionViewTests.swift#L35)
