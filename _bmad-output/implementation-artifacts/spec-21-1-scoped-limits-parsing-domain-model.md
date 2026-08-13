---
title: 'Story 21.1: Scoped Limits Parsing & Domain Model'
type: 'feature'
created: '2026-08-12'
status: 'done'
review_loop_iteration: 0
baseline_revision: '5840dff81f4b2daabb65ecea37e77099a5815eb2'
followup_review_recommended: true
context: []
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** The usage API now reports model-scoped weekly caps (e.g. Claude Fable 5 at 50% of the weekly limit) in a new `limits` array that the app cannot see — a user can hit the Fable wall while the app shows healthy overall headroom. The legacy `seven_day_sonnet` field is dead (API returns `null`).

**Approach:** Decode the `limits` array generically in the API response model, surface `weekly_scoped` entries through `AppState` as a list of scoped-limit window states labeled by the API's `scope.model.display_name`, and remove the dead `sevenDaySonnet` field. No UI in this story — display is Story 21.2.

## Boundaries & Constraints

**Always:**
- Generic parsing — no hardcoded model names anywhere; the label comes from `scope.model.display_name`.
- All new response fields optional; unknown JSON keys and unknown `kind` values ignored (decode `kind` as `String`, not an enum).
- Additive only: new optional fields and one new `AppState` property + update method. Services write state via `AppState` methods only.
- Follow existing precedents: response structs in `cc-hdrm/Models/UsageResponse.swift`, domain window structs beside `WindowState` in `cc-hdrm/State/AppState.swift`, mapping in `PollingEngine.fetchUsageData`.

**Block If:**
- The live API contradicts the documented `limits` entry shape (fields listed in the epic's API evidence) in a way that changes the domain model.

**Never:**
- No UI, no persistence, no notifications, no benchmark changes (Stories 21.2–21.5).
- Do not parse the new `spend` object or extended `extra_usage` fields (`daily`, `weekly`, `currency`) — explicitly out of epic scope.
- Do not touch `cc-hdrm/cc_hdrm.entitlements`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Fable cap present | `limits` contains a `weekly_scoped` entry with `percent: 63`, `resets_at` ISO 8601, `scope.model.display_name: "Fable"` | `AppState.scopedLimits` has one entry: displayName "Fable", utilization 63, parsed reset Date | No error expected |
| No `limits` key | Response without `limits` (old API) | Decodes cleanly, `scopedLimits` empty | No crash, no display |
| Empty / no scoped entries | `limits: []` or only `session`/`weekly_all` kinds | `scopedLimits` empty | No crash |
| Null / missing subfields | `resets_at: null`, `scope.model.id: null`, missing `display_name` | Entry kept; nil reset date / nil label | No crash |
| Missing `percent` | Scoped entry without `percent` | Entry skipped (nothing displayable) | No crash |
| Unknown `kind` | `kind: "daily_scoped"` (future) | Decoded, not surfaced to `scopedLimits` | No crash |
| Fractional-seconds timestamp | `resets_at: "2026-08-12T22:00:00.059415+00:00"` | Parsed via existing `Date.fromISO8601` | Falls back to nil on parse failure |

</intent-contract>

## Code Map

- `cc-hdrm/Models/UsageResponse.swift` — response structs (`UsageResponse`, `WindowUsage`, `ExtraUsage`). Add `LimitEntry`/`LimitScope`/`ScopedModel` Codable structs here (response types live together in this file). Declare `limits: [LimitEntry]?` third, replacing `sevenDaySonnet` (lines 8, 14) so memberwise-init call sites stay positionally valid.
- `cc-hdrm/State/AppState.swift:14-22` — `WindowState` precedent (utilization 0–100, derived `headroomState`). Add `ScopedLimitState` beside it; add `private(set) var scopedLimits` + `updateScopedLimits(_:)` near `updateWindows` (line 253).
- `cc-hdrm/Services/PollingEngine.swift:225-260` — `fetchUsageData` maps response → `WindowState` and calls `appState.updateWindows`. Add the `limits` → `ScopedLimitState` mapping and `updateScopedLimits` call here. Utilization scale matches (`percent` is 0–100, same as existing windows).
- `cc-hdrm/Extensions/Date+Formatting.swift:92-99` — `Date.fromISO8601` handles fractional seconds; reuse for `resets_at`.
- `cc-hdrmTests/Models/UsageResponseTests.swift` — decoding tests; lines 14, 25-26, 45, 69, 87 reference `seven_day_sonnet`/`sevenDaySonnet` and need updating; add `limits` decode cases.
- `cc-hdrmTests/Services/{PollingEngineTests,HistoricalDataServiceTests,ConnectivityNotificationTests}.swift` — ~50 memberwise-init call sites pass `sevenDaySonnet: nil`; mechanical replace with `limits: nil`.

## Tasks & Acceptance

**Execution:**
- `cc-hdrm/Models/UsageResponse.swift` — Remove `sevenDaySonnet`; add `limits: [LimitEntry]?` plus `LimitEntry` (kind, group, percent, severity, resetsAt, isActive, scope — all optional, `kind` a String), `LimitScope` (model, surface), `ScopedModel` (id, displayName) with snake_case CodingKeys — source of truth for model-scoped caps.
- `cc-hdrm/State/AppState.swift` — Add `ScopedLimitState` (displayName: String?, utilization: Double, resetsAt: Date?, derived `headroomState`), `private(set) var scopedLimits: [ScopedLimitState] = []`, and `func updateScopedLimits(_:)` — surfaces scoped caps to views for 21.2.
- `cc-hdrm/Services/PollingEngine.swift` — In `fetchUsageData`, map `response.limits` (filter `kind == "weekly_scoped"`, require `percent`) to `[ScopedLimitState]` and call `appState.updateScopedLimits` alongside `updateWindows`; absent `limits` → empty array — keeps state fresh every poll cycle.
- `cc-hdrmTests/Models/UsageResponseTests.swift` — Update existing tests off `sevenDaySonnet`; add decode tests covering the I/O matrix rows — locks in defensive parsing (NFR12).
- `cc-hdrmTests/Services/PollingEngineTests.swift` — Replace `sevenDaySonnet: nil` call sites with `limits: nil`; add one test: poll with a scoped entry populates `appState.scopedLimits`, following poll without clears it.
- `cc-hdrmTests/Services/HistoricalDataServiceTests.swift`, `cc-hdrmTests/Services/ConnectivityNotificationTests.swift` — Mechanical `sevenDaySonnet: nil` → `limits: nil` at all call sites — compile fix only.

**Acceptance Criteria:**
- Given the API reports a `weekly_scoped` limit, when a poll completes, then views can read its percent, label, and reset Date from `AppState.scopedLimits`.
- Given a response without `limits` or without scoped entries, when decoded and applied, then nothing crashes, `scopedLimits` is empty, and all existing behavior is unchanged.
- Given the codebase after the change, when searching for `sevenDaySonnet`/`seven_day_sonnet`, then no references remain.

## Spec Change Log

## Review Triage Log

### 2026-08-12 — Review pass
- intent_gap: 0
- bad_spec: 0
- patch: 3: (high 0, medium 1, low 2)
- defer: 0
- reject: 13: (high 0, medium 0, low 13)
- addressed_findings:
  - `[medium]` `[patch]` `performSignOut()` cleared every poll-derived AppState field except the new `scopedLimits` — added `appState.updateScopedLimits([])` to the sign-out clears. (Companion sign-out unit test infeasible: `performSignOut` is private and `OAuthKeychainService` is a non-injectable concrete type; making it testable requires refactoring outside this story.)
  - `[low]` `[patch]` New AppState comments referenced story numbers, violating comment rules — story references removed, factual content kept.
  - `[low]` `[patch]` No test covered multiple `weekly_scoped` entries (epic's generic-parsing principle) — added PollingEngine test asserting two scoped entries surface in API order.

Rejected findings (noise, dropped): filter on `is_active` (live API capture shows the real Fable cap with `is_active: false`); carry `scope.model.id` (null in live data); extract "weekly_scoped" constant (single use); per-poll logging of normal filtering (log spam every 30s); unused `group`/`severity` (intent mandates decoding); percent clamping (existing windows don't clamp); `seven_day_sonnet` fallback (intent says remove, API returns null); scoped notifications/persistence (Stories 21.3/21.4); unparseable-date test (same `Date.fromISO8601` path as existing windows); `is_active` semantics test (tied to rejected filter); `Identifiable` conformance (Story 21.2 decides identity); test-fixture consolidation (out-of-scope refactor); dedup of duplicate model ids (speculative); stale state on error path (matches existing windows' contract by design).

## Verification

**Commands:**
- `xcodebuild -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= build` — expected: build succeeds
- `xcodebuild -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test` — expected: all tests pass, including new `limits` decode tests
- `grep -rn "sevenDaySonnet\|seven_day_sonnet" cc-hdrm cc-hdrmTests` — expected: no matches

## Auto Run Result

**Status:** done

**Summary:** The app now decodes the usage API's `limits` array generically (no hardcoded model names) and surfaces `weekly_scoped` entries — such as the Claude Fable 5 weekly cap — through `AppState.scopedLimits` for Story 21.2's UI. The dead `sevenDaySonnet` field is removed. Accounts without scoped limits see zero behavior change.

**Files changed:**
- `cc-hdrm/Models/UsageResponse.swift` — removed `sevenDaySonnet`; added `limits: [LimitEntry]?` plus `LimitEntry`/`LimitScope`/`ScopedModel` Codable structs, all-optional, `kind` as String.
- `cc-hdrm/State/AppState.swift` — added `ScopedLimitState` (displayName, utilization, resetsAt, derived `headroomState`), `scopedLimits` property, `updateScopedLimits(_:)`.
- `cc-hdrm/Services/PollingEngine.swift` — maps `weekly_scoped` entries with a percent to `ScopedLimitState` each poll; absent limits → empty array.
- `cc-hdrm/App/AppDelegate.swift` — `performSignOut()` clears `scopedLimits` (review patch).
- `cc-hdrmTests/Models/UsageResponseTests.swift` — 5 new decode tests covering the I/O matrix; existing tests moved off `sevenDaySonnet`.
- `cc-hdrmTests/Services/PollingEngineTests.swift` — 2 new tests (populate-then-clear; multi-entry ordering); mechanical `limits: nil` call-site updates.
- `cc-hdrmTests/Services/HistoricalDataServiceTests.swift`, `cc-hdrmTests/Services/ConnectivityNotificationTests.swift` — mechanical `limits: nil` call-site updates.

**Review findings:** 3 patched (1 medium, 2 low — see Review Triage Log), 0 deferred, 13 rejected as noise. No intent gaps, no spec repairs.

**Follow-up review recommendation:** true — patched severity score = 3×1 medium + 1×2 low = 5 (threshold 5). Patched counts: high 0, medium 1, low 2.

**Verification:**
- `xcodebuild ... build` — BUILD SUCCEEDED (run twice: post-implementation and post-patch).
- `xcodebuild ... test` — 1477 tests in 127 suites, all passed (post-patch; 1476 pre-patch, independently re-run by the orchestrator).
- `grep -rn "sevenDaySonnet\|seven_day_sonnet" cc-hdrm cc-hdrmTests` — no matches.
- Matrix test audit: every I/O matrix row covered by a test that ran and passed.

**Residual risks:**
- The `limits` shape follows the epic's live API capture; a one-poll sanity check against the real API before Story 21.2 builds UI on it is prudent.
- `performSignOut()` remains untestable without refactoring (private method, non-injectable concrete Keychain service); the `scopedLimits` clear there is unverified by unit test.
- `is_active` is decoded but deliberately not filtered on — the live capture shows the active Fable cap with `is_active: false`; revisit if the field's semantics become documented.
