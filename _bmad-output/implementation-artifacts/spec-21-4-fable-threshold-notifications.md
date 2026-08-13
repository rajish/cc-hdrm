---
title: 'Story 21.4: Fable Threshold Notifications'
type: 'feature'
created: '2026-08-13'
status: 'done'
review_loop_iteration: 0
baseline_revision: 'd70abb9362472174780b0037c1e2699b93618703'
followup_review_recommended: false
context: []
warnings: [oversized]
deferred:
  - summary: >-
      Scoped threshold machine is keyed to array position, not model identity;
      a model swap in the first weekly_scoped slot carries dedup state across
      models
    evidence: |-
      NotificationService keeps one scopedThresholdState fed with
      scopedLimitStates.first. If the API ever reports multiple scoped caps
      or reorders them, a warned20 state earned by one model suppresses the
      first warning for the model that replaces it in slot 0, and the shared
      "headroom-warning-scoped" identifier replaces the prior model's
      undismissed notification. Singular-slot design is decreed by the epic
      (one scoped cap today); consequence is zero until the API changes
      shape. Raised independently by three reviewers.
    location: >-
      cc-hdrm/Services/NotificationService.swift:127
    severity: low
---

<intent-contract>

## Intent

**Problem:** Model-scoped weekly caps (Claude Fable 5) are parsed (21.1), shown live (21.2), and persisted (21.3), but never alerted — a user can hit the Fable wall silently while 5h/7d notifications stay quiet.

**Approach:** Add a third threshold state machine to `NotificationService` for the first scoped limit, reusing the existing `evaluateWindow` transition logic, warning/critical preference values, and delivery format. Fires once per crossing, re-arms on recovery, fully independent of the 5h/7d machines. No-op for accounts without a scoped limit.

## Boundaries & Constraints

**Always:**
- Extend `evaluateThresholds(fiveHour:sevenDay:)` to `evaluateThresholds(fiveHour:sevenDay:scoped:)` with `scoped: ScopedLimitState?` — the **first** entry only (singular-scoped-cap precedent from 21.2/21.3). Update the protocol, `NotificationService`, `MockNotificationService`, and the `PollingEngine` call site (pass `scopedLimitStates.first`).
- `reevaluateThresholds()` passes `appState.scopedLimits.first` so preference changes re-evaluate the scoped window too.
- New state: `private(set) var scopedThresholdState: ThresholdState = .aboveWarning`, exposed read-only on the protocol beside the existing two. Reuse `evaluateWindow(currentState:headroom:warningThreshold:criticalThreshold:)` unchanged — do not fork the transition logic.
- The threshold-change re-arm block (NotificationService.swift:59-79) must also re-arm the scoped state, same condition as 5h/7d.
- Headroom = `100.0 - scoped.utilization`; thresholds come from `preferencesManager.warningThreshold` / `criticalThreshold` (user-configurable, defaults 20/5). No new preference key.
- Notification identifiers use the fixed window token `"scoped"` (`headroom-warning-scoped` / `headroom-critical-scoped`) — never the display name, which can be nil/blank/changing.
- Notification body labels the window with the API display name, trimmed, falling back to `ScopedLimitGaugeSection.fallbackLabel` ("Model") when nil/blank — same derivation as 21.2/21.3. Body format mirrors the existing one: `"Claude Fable headroom at 18% — resets in 2h 13m (at 4:52 PM)"`; reset clause omitted when `resetsAt` is nil.
- Warning notification silent, critical carries `.default` sound — existing precedent.
- `scoped == nil` → skip evaluation, state untouched (same as nil `WindowState`).

**Block If:**
- Supporting the scoped machine requires changing the observable notification behavior of the existing 5h/7d machines (bodies, identifiers, transition semantics).

**Never:**
- No benchmark changes (21.5), no UI/popover/analytics/menu-bar changes, no persistence changes, no AppState changes.
- No per-model keyed state machines or multi-entry support — one machine for the first scoped entry.
- No new preference toggles or threshold values; no parsing changes; do not touch `cc-hdrm/cc_hdrm.entitlements`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Warning crossing | scoped headroom 25%→18%, state `aboveWarning` | State `warned20`; silent notification "Claude Fable headroom at 18% — resets in …" | No error |
| Critical crossing | headroom 18%→4%, state `warned20` | State `warned5`; critical notification with `.default` sound | No error |
| Direct-to-critical | headroom 30%→3%, state `aboveWarning` | State `warned5`; only critical fires | No error |
| No repeat | headroom stays 15%, state `warned20` | No notification, state unchanged | No error |
| Recovery re-arm | headroom 15%→22%, state `warned20` | State `aboveWarning`, no notification; next drop below 20% fires again | No error |
| Independence | 5h crosses warning, scoped at 80% headroom | Only 5h notification; `scopedThresholdState` stays `aboveWarning` | No error |
| No scoped limit | `scoped == nil` (account without Fable) | No evaluation, no state change, zero behavior change | No crash |
| Limit disappears then returns | scoped nil for N polls, then back at 50% headroom | State retained while nil; re-evaluated on return (recovery path re-arms if needed) | No crash |
| Blank display name | `displayName` nil or `"  "`, crossing occurs | Body uses "Model" fallback label | No error |
| nil resetsAt | crossing with `resetsAt == nil` | Body has percentage only, no reset clause | No crash |
| Threshold prefs changed | warning 20→30 while scoped `warned20` at 25% headroom | Scoped machine re-arms (headroom ≥ new warning); immediate re-evaluation fires warning at 25% < 30% | No error |
| Unauthorized | `isAuthorized == false`, crossing occurs | State still transitions, delivery skipped | No error |

</intent-contract>

## Code Map

- `cc-hdrm/Services/NotificationService.swift` — the whole change surface: state vars :7-8 (+`scopedThresholdState`), re-arm block :59-79 (+scoped clause), per-window evaluation :81-119 (+scoped block passing label + resetsAt), `evaluateWindow` :124-154 (reuse as-is), `deliverNotification` :162-196 (`windowPrefix` derivation :177 needs a label for the scoped window — pass an explicit body label/prefix from callers rather than switching on the window token), `sendNotification`/`sendCriticalNotification` :198-218 (thread label through), `reevaluateThresholds` :45-52 (+`appState.scopedLimits.first`).
- `cc-hdrm/Services/NotificationServiceProtocol.swift` — `evaluateThresholds` :23 signature + `scopedThresholdState` accessor beside :31-33. `ThresholdState` enum :3-10 unchanged.
- `cc-hdrm/Services/PollingEngine.swift` :240-271 — `scopedLimitStates` already built; pass `.first` at the `evaluateThresholds` call :271.
- `cc-hdrm/Views/ScopedLimitGaugeSection.swift` :11 — `fallbackLabel` ("Model") + trim-fallback derivation :22-25 to mirror (21.3's `AnalyticsView.fableLabel(from:)` :92-98 is the same pattern; a small shared static on the service is fine, no new file).
- `cc-hdrm/State/AppState.swift` :26-35, :76 — `ScopedLimitState` (displayName/utilization/resetsAt) and `scopedLimits`; read-only here.
- `cc-hdrmTests/Services/ThresholdStateMachineTests.swift` — the test home; `windowState` helper :11, crossing/no-repeat/re-arm/independence/nil/unauthorized templates throughout; body-content template :229-252; identifier template :493-508.
- `cc-hdrmTests/Mocks/MockNotificationService.swift` — protocol conformance: tuple in `evaluateThresholdsCalls` :9 gains `scoped`, add `scopedThresholdState`.
- `cc-hdrmTests/Services/PollingEngineTests.swift` :347-452 — scoped-limit fixtures with `limits:` arrays to reuse; add assertion that the first scoped state reaches the notification service.
- `cc-hdrm/App/AppDelegate.swift` :209-215 — `onThresholdChange` → `reevaluateThresholds()`; no change needed, scoped rides along. Sign-out clears `scopedLimits` :384 → subsequent re-evaluations see nil.

## Tasks & Acceptance

**Execution:**
- `cc-hdrm/Services/NotificationServiceProtocol.swift` — add `scoped:` parameter and `scopedThresholdState` accessor — protocol surface for the third machine.
- `cc-hdrm/Services/NotificationService.swift` — scoped state var, re-arm clause, evaluation block reusing `evaluateWindow`, label-aware delivery (fallback "Model"), `reevaluateThresholds` passes `appState.scopedLimits.first` — the feature.
- `cc-hdrm/Services/PollingEngine.swift` — pass `scopedLimitStates.first` at the call site — wires live polls into the machine.
- `cc-hdrmTests/Mocks/MockNotificationService.swift` — conform to the new signature, record scoped values — keeps suite compiling and assertable.
- `cc-hdrmTests/Services/ThresholdStateMachineTests.swift` — cover every I/O matrix row for the scoped machine (crossings, dedup, re-arm, independence both directions, nil handling, label fallback, identifier suffix, threshold-change re-arm, unauthorized) — locks the state machine.
- `cc-hdrmTests/Services/PollingEngineTests.swift` — assert the poll cycle forwards the first scoped entry (and nil when absent) to `evaluateThresholds` — guards the wiring.

**Acceptance Criteria:**
- Given an account whose polls report a Fable scoped limit, when headroom crosses below the configured warning then critical thresholds across poll cycles, then exactly one warning and one critical notification fire, labeled with the API display name and carrying countdown + absolute reset time.
- Given an account with no scoped limit in any poll, when polling and preference changes occur, then no scoped notification ever fires and existing 5h/7d notification behavior is byte-for-byte unchanged.
- Given the user changes warning/critical thresholds in Settings, when `reevaluateThresholds` runs, then the scoped machine re-arms/fires against the new values exactly like the 5h/7d machines.

## Spec Change Log

## Review Triage Log

### 2026-08-13 — Review pass
- intent_gap: 0
- bad_spec: 0
- patch: 3: (high 0, medium 0, low 3)
- defer: 1: (high 0, medium 0, low 1)
- reject: 13: (high 0, medium 0, low 13)
- addressed_findings:
  - `[low]` `[patch]` Vacuous assertion in `scopedWarningCrossing` — `body.contains("at ")` always passed because the body contains "headroom at 18%"; now asserts the parenthesized absolute-time clause `body.contains("(at ")`, which fails when the absolute time is dropped.
  - `[low]` `[patch]` Scoped machine lacked 5h/7d-parity coverage for critical dedup and warned5 recovery — added `scopedNoRepeatCritical` (exactly one critical while headroom stays below critical) and `scopedRecoveryFromWarned5` (silent re-arm from warned5, later drop fires warning not critical).
  - `[low]` `[patch]` `sprint-status.yaml` entry for this story still `backlog` — own entry set to done per shared-resource convention (21.3 precedent).

Deferred (latent by design, not reachable with today's API shape): scoped machine keyed to slot position, no identity reset on model change — see frontmatter `deferred`.

Rejected findings (noise, dropped): second-and-later scoped entries get no notifications (intent scopes to "the scoped window" singular — epic title, goal, and success criteria all name the one Fable cap; multi-entry support is a future story); `= nil` default on concrete `evaluateThresholds` while the protocol has none (deliberate source-compat for ~40 existing test call sites; production callers are protocol-typed and compiler-forced); label derivation duplicated across `ScopedLimitGaugeSection`/`AnalyticsView`/`NotificationService` (spec-directed reuse of the 21.2 fallback constant; consolidating onto `ScopedLimitState` would violate the spec's no-AppState-changes rule; 21.3 precedent accepted the same duplication); notification identifiers not model-qualified (spec-decreed fixed `"scoped"` token, justified in Design Notes); delivery log lacks the model label (format parity with 5h/7d token-only logging; the label is in the body); `bodyPrefix` stringly-typed trailing-space contract (private API with three documented call sites, per spec Code Map); protocol doc says "the first model-scoped limit" (accurately documents intended usage per spec); `mockTracksScopedThresholds` placement (exact parity with the existing mock-tracking test in the same file); spec file untracked in the reviewed diff (committed at finalization by the workflow); threshold-change re-arm leaves warned5 stale when headroom lands between new critical and new warning (matches designed, user-approved 5h/7d semantics pinned by existing tests; changing it is a product decision and would break the Block-If parity rule); negative headroom display for utilization > 100 (API documents percent 0–100; unclamped math is exact parity with 5h/7d, same rejection as 21.3); spec rationale citing "singular-scoped-cap precedent from 21.2" while 21.2's gauge renders all entries (rationale nit; the normative choice stands on the epic decree and 21.3, no behavior impact); intent-contract matrix row "Threshold prefs changed" contains a self-contradictory illustrative outcome (its own stated condition, headroom ≥ new warning, is false at 25% vs 30%; the Always clause and AC-3 select exactly one reading — 5h/7d parity — which is implemented and pinned by `scopedThresholdChangeRearms`/`scopedThresholdChangeFires` plus the existing 5h precedent test).

## Design Notes

- **Why a parameter, not a separate method:** the scoped machine must participate in the same threshold-change re-arm pass and the same re-evaluation entry point; a second method would duplicate that sequencing.
- **Why singular `ScopedLimitState?`:** epic and 21.2/21.3 treat the scoped cap as singular (first entry); per-model keyed machines are a future story if the API ever reports two.
- **Why identifier token `"scoped"`:** identifiers must be stable across polls for the replace-not-stack behavior; display names are not stable (nil/blank possible).

## Verification

**Commands:**
- `xcodebuild -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= build` — expected: BUILD SUCCEEDED
- `xcodebuild -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test` — expected: all tests pass (known flake: `TPPChartDataServiceTests/dailyAverage()` within 4h of local midnight — pre-existing, unrelated)

## Auto Run Result

**Status:** done

**Summary:** The model-scoped weekly cap (Claude Fable 5) now has threshold notifications. `NotificationService` runs a third state machine beside 5h/7d, fed the first `weekly_scoped` entry each poll cycle and on preference-change re-evaluation. It fires a silent warning when headroom crosses below the configured warning threshold and a sounded critical below the critical threshold (defaults 20%/5%), once per crossing, re-arming on recovery, fully independent of the other windows. Notifications are labeled with the API display name ("Fable", generic "Model" fallback) and carry the countdown plus absolute reset time. Accounts without a scoped limit see zero change.

**Files changed:**
- `cc-hdrm/Services/NotificationServiceProtocol.swift` — `scoped: ScopedLimitState?` parameter on `evaluateThresholds`; `scopedThresholdState` accessor.
- `cc-hdrm/Services/NotificationService.swift` — scoped state var, scoped clause in the threshold-change re-arm block, scoped evaluation reusing `evaluateWindow` unchanged, `scopedWindowLabel(from:)` (trim + "Model" fallback), delivery refactored to caller-supplied `bodyPrefix` (5h/7d bodies unchanged), fixed `headroom-warning-scoped`/`headroom-critical-scoped` identifiers, `reevaluateThresholds` feeds `appState.scopedLimits.first`.
- `cc-hdrm/Services/PollingEngine.swift` — passes `scopedLimitStates.first` at the notification call site.
- `cc-hdrmTests/Mocks/MockNotificationService.swift` — new signature conformance, records scoped values, exposes `scopedThresholdState`.
- `cc-hdrmTests/Services/ThresholdStateMachineTests.swift` — 21 scoped tests: all I/O matrix rows plus review-added critical dedup and warned5 recovery.
- `cc-hdrmTests/Services/PollingEngineTests.swift` — poll cycle forwards first scoped entry; nil when absent.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — own story entry set to done.

**Review findings:** 3 patched (all low — see Review Triage Log), 1 deferred (positional keying of the scoped machine — latent until the API reports multiple/reordered scoped caps), 13 rejected as noise. No intent gaps, no spec repairs.

**Follow-up review recommendation:** false — patched counts: high 0, medium 0, low 3; score = 3×0 + 1×3 = 3 (threshold 5).

**Verification:**
- `xcodebuild ... build` — BUILD SUCCEEDED (via test pipeline; project regenerated with `xcodegen generate` once because the worktree's gitignored xcodeproj was stale, unrelated to this change).
- `xcodebuild ... test` — TEST SUCCEEDED: 1542 tests in 129 suites, 0 failures (1520 at baseline; 20 tests added by implementation, 2 by review patches). Run twice: post-implementation and post-patch.
- Matrix test audit: every I/O matrix row covered by a test that ran and passed; the "Threshold prefs changed" row's illustrative numbers are self-contradictory, its normative condition (re-arm when headroom ≥ new warning, 5h/7d parity) is what is implemented and tested.
- No new source files — `xcodegen generate` not required for the change itself.

**Residual risks:**
- The scoped machine tracks whatever entry is first in the API's `limits` array with no model-identity memory (deferred finding) — inert while the API reports the single Fable cap.
- Historical note: notification label falls back to "Model" if the API ever omits the display name; identifier stays stable either way.
