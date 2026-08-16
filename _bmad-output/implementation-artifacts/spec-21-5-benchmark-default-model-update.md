---
title: 'Story 21.5: Benchmark Default Model Update'
type: 'feature'
created: '2026-08-16'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: true
baseline_revision: '01cf8c76f906e32f8846d6eabb543f5ebb1875d8'
context: []
warnings: [oversized]
deferred:
  - summary: >-
      Benchmark conflates an API-rejected model with a below-detection-threshold
      result; the inconclusive card's copy misleads accounts without Fable access
    evidence: |-
      BenchmarkService.runVariant returns inconclusive: true on any request
      error (the same value used when the utilization delta stays 0 after all
      retries), and BenchmarkSectionView.resultCard renders "This model may
      have a very high token allowance on your tier" for every inconclusive
      result. With claude-fable-5 now in defaultModels, an account whose
      Messages API call for Fable is rejected (4xx) sees that message, which
      states the opposite of what happened. Pre-existing since 20.1; surfaced
      by making Fable a default.
    location: >-
      cc-hdrm/Services/BenchmarkService.swift:255-258; cc-hdrm/Views/BenchmarkSectionView.swift:169-172
    severity: low
---

<intent-contract>

## Intent

**Problem:** The Token Efficiency benchmark only measures `claude-sonnet-4-6` by default, so users cannot see how many tokens one percent of budget buys on Claude Fable 5 — the model with its own weekly cap (Epic 21). Users also get no warning that a Fable benchmark request draws down that separate Fable cap.

**Approach:** Add `claude-fable-5` to the benchmark's default model list, confirm the existing Messages API request path forwards the Fable model ID unchanged, and extend the benchmark UI copy to say Fable requests consume the Fable weekly cap. The benchmark stays behind the opt-in Measure button and Settings toggle.

## Boundaries & Constraints

**Always:**
- Keep the change additive: existing `claude-sonnet-4-6` stays first in the default list; stored `benchmarkModels` preferences still take precedence when non-empty.
- Model IDs and copy strings are the only production edits; no new services, protocols, preferences, or files under `cc-hdrm/`.
- Copy must state that Fable benchmark requests count against the Fable weekly cap.
- Follow the project's zero-dependency, `os.Logger`, and no-`print` rules.

**Block If:**
- Live verification against `api.anthropic.com` would be required to complete an AC (it costs the user real quota and needs their credentials) — verify the request path with the injected `dataLoader` in tests only.
- Any change to `cc-hdrm/cc_hdrm.entitlements` appears necessary.

**Never:**
- Do not add a model-selection UI, model auto-detection, or per-model variant settings.
- Do not change the benchmark measurement math, retry logic, endpoint, headers, or `anthropic-version`.
- Do not parse the usage response's `spend` / extended `extra_usage` fields.
- Do not touch stories 21.1–21.4 code paths (scoped-limit parsing, gauge, persistence, notifications).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Default models | `preferencesManager.benchmarkModels` empty, Measure clicked | Benchmark runs `claude-sonnet-4-6` then `claude-fable-5`, each variant sequentially | No error expected |
| Stored models win | `benchmarkModels == ["claude-opus-4-6"]` | Only `claude-opus-4-6` benchmarked; defaults ignored | No error expected |
| Fable request path | `runBenchmark(models: ["claude-fable-5"], ...)` with injected `dataLoader` | POST body JSON `"model": "claude-fable-5"`; progress emits `.sendingRequest(model: "claude-fable-5", ...)`; result `.model == "claude-fable-5"` | Non-200 or thrown error → variant result `inconclusive: true`, benchmark continues (existing behavior) |
| Fable model rejected by API | Messages API returns 4xx for `claude-fable-5` (no Fable access) | That model's variants marked inconclusive; sonnet results unaffected; benchmark completes | Logged via `Self.logger.error`, no crash |
| Copy visible | Measure button hovered / Settings benchmark section shown | Text mentions Fable requests consume the Fable weekly cap | No error expected |

</intent-contract>

## Code Map

- `cc-hdrm/Views/BenchmarkSectionView.swift` — `defaultModels` :33 (`private static let defaultModels = ["claude-sonnet-4-6"]`, doc comment "Known Claude models for auto-detection fallback") — the one-line model addition; drop `private` so a test can read it. Fallback selection :251-257 (`storedModels.isEmpty → Self.defaultModels`) — read-only, already correct. Measure button `.help(...)` :57 — tooltip copy to extend with the Fable cap note. `resultCard` :151-180 and progress text :118-123 already print `result.model` / `model` generically — no change.
- `cc-hdrm/Views/SettingsView.swift` :337 — benchmark explanatory paragraph ("Benchmark sends test requests per model ... Each variant uses ~2K-5K tokens ...") — append one sentence noting Fable requests also draw down the Fable weekly cap. Benchmark toggles :311-335 unchanged.
- `cc-hdrm/Services/BenchmarkService.swift` — `sendBenchmarkRequest` :309-354 builds body `["model": model, "max_tokens": ..., "messages": [...]]` and posts to `messagesEndpoint` :38 with `anthropic-version: 2023-06-01`; `runBenchmark` :167-217 iterates models sequentially; `runVariant` :226-306 marks a variant `inconclusive: true` on request error :255-258. **Read-only** — the model string is passed through verbatim, so no code change is needed; verification is by test.
- `cc-hdrm/Services/BenchmarkServiceProtocol.swift` :12-15 — `BenchmarkProgress.sendingRequest(model:variant:)` is `Equatable`; use it in the request-path assertion.
- `cc-hdrm/Services/PreferencesManager.swift` :364-367 — `benchmarkModels` defaults to `[]`; there is no Settings UI to set it, so `defaultModels` is the effective production list. Read-only.
- `cc-hdrmTests/Services/BenchmarkServiceTests.swift` — home for the request-path test. Reuse `runBenchmarkSendsRequest` :157-234 as the template (AppState setup :159-165, `MockBenchmarkPollingEngine`, `MockTPPStorageService`, `MockBenchmarkKeychainService`, `MockHistoricalDataService`, `ProgressCollector` :212). Capture the `URLRequest` inside the `dataLoader` closure and decode `httpBody` to assert the model.
- `cc-hdrmTests/Views/BenchmarkSectionViewTests.swift` — **new file** (mirrors `cc-hdrmTests/Views/AnalyticsViewTests.swift` header: `import Testing`, `@testable import cc_hdrm`, `@MainActor`). Pins `defaultModels`. Requires `xcodegen generate` afterwards.
- `cc-hdrmTests/Mocks/MockPreferencesManager.swift` :30 — `benchmarkModels: [String] = []` — read-only, already matches production default.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` :198 — `21-5-benchmark-default-model-update: backlog` → own entry only, per shared-resource rule.

## Tasks & Acceptance

**Execution:**
- `cc-hdrm/Views/BenchmarkSectionView.swift` — append `"claude-fable-5"` to `defaultModels`, make it internal (`static let`); hoist the stored-vs-default choice into `static func resolveModels(stored:)` and the Fable-cap sentence into `static let fableCapNote` (both so the matrix rows are testable); extend the Measure `.help` tooltip with `fableCapNote` — the feature.
- `cc-hdrm/Views/SettingsView.swift` — append `BenchmarkSectionView.fableCapNote` to the benchmark description paragraph — copy where users opt in.
- `cc-hdrmTests/Services/BenchmarkServiceTests.swift` — add a test that runs `runBenchmark(models: ["claude-fable-5"], ...)`, captures the request, and asserts body `model == "claude-fable-5"`, `.sendingRequest(model: "claude-fable-5", ...)` progress, and result `.model`; add a rejected-model isolation test (404 for fable, 200 for sonnet) — verifies the request path and error row.
- `cc-hdrmTests/Views/BenchmarkSectionViewTests.swift` — new file: pins `defaultModels`, both `resolveModels` branches, and `fableCapNote` content — covers matrix rows 1, 2, 5; run `xcodegen generate`.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — set own entry to `done` at finalization.

**Acceptance Criteria:**
- Given no stored benchmark models, when the user clicks Measure and passes validation, then the benchmark runs `claude-sonnet-4-6` and `claude-fable-5` in that order with the configured variants.
- Given a benchmark for `claude-fable-5`, when the request is sent, then the Messages API body carries `"model": "claude-fable-5"` with the unchanged endpoint, headers, and payload shape.
- Given the Measure button tooltip and the Settings benchmark description, when read, then both state that Fable benchmark requests count against the Fable weekly cap.
- Given the API rejects `claude-fable-5`, when the benchmark runs, then that model's variants report inconclusive and other models' results are unaffected.

## Spec Change Log

## Review Triage Log

### 2026-08-16 — Review pass
- intent_gap: 0
- bad_spec: 0
- patch: 6: (high 0, medium 0, low 6)
- defer: 1: (high 0, medium 0, low 1)
- reject: 16: (high 0, medium 0, low 16)
- addressed_findings:
  - `[low]` `[patch]` `defaultModels` doc comment claimed "auto-detection fallback" — no auto-detection exists; reworded to "Models benchmarked when no models are stored in preferences."
  - `[low]` `[patch]` `sprint-status.yaml` entry lacked the sibling `# bmad-build-auto <date>` annotation; added `# bmad-build-auto 2026-08-16`.
  - `[low]` `[patch]` `runBenchmarkRejectedModelIsolated` carried a narrative comment and hard-coded the private `maxRetries` (`retryCount == 3`); comment removed, assertion loosened to `>= 1`.
  - `[low]` `[patch]` `runBenchmarkForwardsFableModel` asserted only `max_tokens != nil` and skipped `Content-Type`/`Authorization`; now asserts `2048`, `application/json`, and a `Bearer ` prefix.
  - `[low]` `[patch]` Test name `defaultModelsIncludeFable` did not match its ordering claim; renamed `defaultModelsAreSonnetThenFable`.
  - `[low]` `[patch]` Epic success criterion "benchmark can measure `claude-fable-5` end to end" was only pinned at the request-serialization surface; added `runBenchmarkProducesFableMeasurement` — the mock poll bumps 5h utilization so the full `runVariant` path yields a stored `TPPMeasurement` for `claude-fable-5`.

Deferred (pre-existing, surfaced by making Fable a default): a Messages API rejection (4xx) and a zero utilization delta both surface as `inconclusive`, and the result card then says "may have a very high token allowance" — misleading for accounts without Fable access. See frontmatter `deferred`.

Rejected findings (noise or out of scope on the story's own authority): gate `claude-fable-5` on `appState.scopedLimits` / add a Fable-cap precondition check (the story text adds it to `defaultModels` unconditionally and declares 21.5 independent of 21.1–21.4; hardcoding a model-name guard also contradicts the epic's generic-parsing principle); Fable requests might not move the 5h window so the retry ladder would burn Fable cap (speculative — the scoped cap is additive to overall usage; measurement math is outside the story); blank/duplicate entries in stored `benchmarkModels` (no UI writes that preference; pre-existing branch behavior); `SettingsView` referencing `BenchmarkSectionView.fableCapNote` (cosmetic dependency direction; the alternative is a new file); spec "Always: model IDs and copy strings only" vs. the `resolveModels`/`fableCapNote` hoists (artifact nit — the Tasks section documents both hoists, they add no behavior, and the intent-contract is read-only after planning); "no evidence verification ran" (recorded in Auto Run Result); isolation test should produce a real sonnet measurement (covered now by the end-to-end Fable test using the same hook); `RequestCapture` duplicates `ProgressCollector` (test-local, two distinct element types); view-level wiring of `resolveModels` into `runBenchmark` untested (one-line call site; would require a new `MockBenchmarkService` and a mock TPP storage in `Mocks/` — cost outweighs the guard; noted as residual); tooltip/Settings paragraph not asserted to contain the note (no view-text inspection pattern in the project; hoisting whole paragraphs to statics is a tautology one level up); result cards show `claude-fable-5` while copy says "Fable" (model IDs on cards are the 20.x design); retry ladder can exceed "~2K-5K tokens" (pre-existing copy nuance for all models).

## Verification

**Commands:**
- `xcodegen generate` — expected: project regenerated with the new test file.
- `xcodebuild -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= build` — expected: BUILD SUCCEEDED
- `xcodebuild -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test` — expected: all tests pass (known flake: `TPPChartDataServiceTests/dailyAverage()` within 4h of local midnight — pre-existing, unrelated)

## Auto Run Result

**Status:** done

**Summary:** The Token Efficiency benchmark now measures Claude Fable 5 by default. `defaultModels` is `["claude-sonnet-4-6", "claude-fable-5"]` (sonnet still first; a non-empty stored `benchmarkModels` preference still wins). `BenchmarkService` needed no change — the model string is posted verbatim in the Messages API body, which is now pinned by tests including a full end-to-end unit measurement for `claude-fable-5`. Both places that explain benchmark cost — the Measure button tooltip and the Settings benchmark paragraph — now add "Fable requests also count against your Fable weekly cap." The benchmark stays behind the Settings toggle and the opt-in Measure button.

**Files changed:**
- `cc-hdrm/Views/BenchmarkSectionView.swift` — `defaultModels` gains `claude-fable-5` and becomes internal; new `static let fableCapNote` and `static func resolveModels(stored:)` (hoisted so the matrix rows are testable); `executeBenchmark` uses `resolveModels`; Measure tooltip appends `fableCapNote`; stale "auto-detection" doc comment corrected.
- `cc-hdrm/Views/SettingsView.swift` — benchmark description paragraph appends `BenchmarkSectionView.fableCapNote`.
- `cc-hdrmTests/Services/BenchmarkServiceTests.swift` — `MockBenchmarkPollingEngine.onForcedPoll` hook; three new tests: request-path forwarding for `claude-fable-5` (URL, method, headers, body shape, progress, result), rejected-model isolation (404 for Fable, 200 for sonnet), end-to-end Fable measurement (poll bumps 5h utilization → conclusive `TPPMeasurement` stored).
- `cc-hdrmTests/Views/BenchmarkSectionViewTests.swift` — new file: default list order, both `resolveModels` branches, `fableCapNote` content.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — own entry `21-5-benchmark-default-model-update: done  # bmad-build-auto 2026-08-16`.
- `_bmad-output/implementation-artifacts/spec-21-5-benchmark-default-model-update.md` — this spec.

**Review findings:** 6 patched (all low — see Review Triage Log), 1 deferred (pre-existing rejected-vs-inconclusive conflation in the result card), 16 rejected as noise or out of scope on the story's own text. No intent gaps, no spec repairs.

**Follow-up review recommendation:** true — patched counts: high 0, medium 0, low 6; score = 3×0 + 1×6 = 6 (threshold 5). All six are cosmetic/test-strengthening; none touched production behavior beyond a doc comment.

**Verification:**
- `xcodegen generate` — succeeded (new test file registered).
- `xcodebuild ... build` — BUILD SUCCEEDED (via the test pipeline).
- `xcodebuild ... test` — 1549 tests in 130 suites, 1 failure: `SubscriptionPatternDetectorTests/chronicUnderpoweringDetected`. Pre-existing and unrelated: the detector excludes the current partial month and needs two complete months from a 60-day fixture; on 2026-08-16 June holds only 2 rate-limit days, under the threshold. Neither file touched since 2026-03-03; not in this diff. Baseline count 1542 → 1549 (+7 tests). Run three times: post-implementation, post-matrix-audit additions, post-review-patches.
- Matrix test audit: all five I/O rows covered by tests that ran and passed (`emptyStoredModelsUseDefaults` + `defaultModelsAreSonnetThenFable`; `storedModelsWin`; `runBenchmarkForwardsFableModel`; `runBenchmarkRejectedModelIsolated`; `fableCapNoteMentionsCap`).
- No live call to `api.anthropic.com` was made (spec Block-If: costs real quota, needs credentials).

**Residual risks:**
- Accounts without Fable access now send Fable requests on every default Measure run; a rejection yields an inconclusive card with the misleading pre-existing copy (deferred). On Pro plans a Fable request may be billed to pay-as-you-go credits — the Measure flow was already opt-in with a "uses real tokens" warning, and the story directs an unconditional default.
- Preconditions check only 5h headroom (≤90%); no check against the Fable scoped cap — out of scope by the story's independence from 21.1–21.4.
- The one-line wiring `executeBenchmark → resolveModels → runBenchmark` is not exercised by a view-level test (would need a `MockBenchmarkService`); the helper itself is pinned.
- Fable's TPP is measured against the 5h window like every other model; if Fable requests ever stop moving the 5h window, runs would exhaust the retry ladder and report inconclusive.
