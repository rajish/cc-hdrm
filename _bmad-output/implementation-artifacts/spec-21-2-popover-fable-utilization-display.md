---
title: 'Story 21.2: Popover Fable Utilization Display'
type: 'feature'
created: '2026-08-12'
status: 'done'
review_loop_iteration: 0
baseline_revision: 'fff4a4e0d4162cefdea7db5dcae74bdc98007f07'
followup_review_recommended: false
context: []
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 21.1 surfaces model-scoped weekly caps (e.g. Claude Fable 5) in `AppState.scopedLimits`, but the popover shows nothing — a user can hit the Fable wall while the panel shows only healthy 5h/7d gauges.

**Approach:** Add a scoped-limit gauge section to the popover's authenticated view, one gauge per `scopedLimits` entry, labeled with the API's `display_name`, with reset countdown (relative + absolute) — visually matching the existing 7d section. Hidden entirely when no scoped limit is reported.

## Boundaries & Constraints

**Always:**
- Label each gauge with the entry's `displayName`; when nil, fall back to the generic label `"Model"` (21.1 deliberately keeps nil-label entries).
- Match the 7d section's visual pattern exactly: caption label above, `HeadroomRingGauge` (56px ring, 4px stroke), `CountdownLabel` below (relative + absolute).
- When `scopedLimits` is empty, render nothing — no section, no divider; popover output identical to today.
- Render all entries in API order (the array order from `AppState`).
- Custom views carry `.accessibilityLabel()`/`.accessibilityValue()`; state is triple-encoded (number + color + weight) via the existing components.
- New Swift files require `xcodegen generate` afterward.

**Block If:**
- Displaying scoped limits would require modifying `HeadroomRingGauge` or `CountdownLabel` in a way that changes existing 5h/7d rendering.

**Never:**
- No slope indicator and no quotas line for scoped entries — no data source exists for them.
- No tap-to-analytics wiring, persistence, notifications, or benchmark changes (Stories 21.3–21.5). No menu bar changes.
- No hardcoded model names anywhere.
- Do not touch `cc-hdrm/cc_hdrm.entitlements`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Fable cap present | `scopedLimits = [displayName "Fable", utilization 63, resetsAt set]` | Section shows "Fable" label, ring at 37% headroom in caution color, "resets in …" + absolute time | No error expected |
| No scoped limits | `scopedLimits = []` | No section, no divider — popover unchanged | No crash |
| Nil display name | Entry with `displayName: nil` | Gauge shown with fallback label "Model" | No crash |
| Nil reset date | Entry with `resetsAt: nil` | Gauge shown, countdown omitted (CountdownLabel renders nothing) | No crash |
| Multiple entries | Two scoped entries | One gauge block per entry, in array order | No crash |
| Exhausted | `utilization: 100` | Ring at 0%, exhausted color/weight via derived `headroomState` | No crash |

</intent-contract>

## Code Map

- `cc-hdrm/Views/SevenDayGaugeSection.swift` — the pattern to copy: label + `HeadroomRingGauge(56, 4)` + `CountdownLabel`, combined accessibility label, renders nothing when data absent. Omit its slope, quotas, hover, and onTap pieces.
- `cc-hdrm/Views/PopoverView.swift:109-136` — `authenticatedView`; insert `Divider()` + new section between the 7d block (ends line 128) and the extra-usage card block (line 131), guarded by `!appState.scopedLimits.isEmpty`.
- `cc-hdrm/Views/HeadroomRingGauge.swift` — reusable ring; `slopeLevel` already defaults to nil. Takes headroom percentage (100 − utilization).
- `cc-hdrm/Views/CountdownLabel.swift` — relative + absolute reset display; renders nothing for nil `resetTime`; takes `countdownTick` for 60s refresh.
- `cc-hdrm/State/AppState.swift:26-35,76,115` — `ScopedLimitState` (displayName?, utilization 0–100, resetsAt?, derived `headroomState`), `scopedLimits: [ScopedLimitState]`, `countdownTick`. No AppState changes needed.
- `cc-hdrmTests/Views/SevenDayGaugeSectionTests.swift` — test style to mirror (render via `_ = section.body` and `NSHostingController`, accessibility-label string checks).
- `cc-hdrmTests/Views/PopoverViewTests.swift` — existing popover render tests; extend for the scoped section.
- Iterate entries with `ForEach(appState.scopedLimits.indices, id: \.self)` — the array is replaced wholesale each poll and is tiny; index identity suffices (21.1 review deferred identity choice to this story).

## Tasks & Acceptance

**Execution:**
- `cc-hdrm/Views/ScopedLimitGaugeSection.swift` — new view taking `appState`; renders one label + ring + countdown block per `scopedLimits` entry (dividers between entries), nothing when empty; per-entry combined accessibility label "{label} headroom: X percent, resets in …, at …" — surfaces the scoped cap in the popover.
- `cc-hdrm/Views/PopoverView.swift` — insert the section with its `Divider()` into `authenticatedView` after the 7d block, guarded on non-empty `scopedLimits` — placement mirrors the existing window ordering (5h → 7d → scoped).
- `cc-hdrmTests/Views/ScopedLimitGaugeSectionTests.swift` — new suite covering the I/O matrix rows plus headroom-state derivation and hosting-controller render — locks in hidden-when-absent and fallback-label behavior.
- `cc-hdrmTests/Views/PopoverViewTests.swift` — add render tests: authenticated popover with scoped limits present and absent — guards the integration point.
- Run `xcodegen generate` after adding the new files — regenerates the project so both targets compile.

**Acceptance Criteria:**
- Given the API reported a scoped weekly limit, when the authenticated popover renders, then a gauge labeled with the API's display name shows headroom percent and reset countdown (relative + absolute) styled like the 7d section.
- Given `scopedLimits` is empty, when the popover renders, then its view hierarchy is unchanged from today — no scoped section, no extra divider.
- Given a scoped entry, when VoiceOver focuses the section, then it announces label, headroom percent, and reset times in one combined element.

## Spec Change Log

## Review Triage Log

### 2026-08-13 — Review pass
- intent_gap: 0
- bad_spec: 0
- patch: 3: (high 0, medium 0, low 3)
- defer: 0
- reject: 18: (high 0, medium 0, low 18)
- addressed_findings:
  - `[low]` `[patch]` Show/hide polarity of the scoped section was untestable (inverting the PopoverView guard left all tests green) — extracted internal `showsScopedLimitSection` property used by the guard; both polarity cases now asserted directly.
  - `[low]` `[patch]` Per-entry rendering was untestable (ForEach rendering only the first entry would pass) — body now iterates internal `entries` projection; tests assert count/order/labels on it; overbroad "visually matching the 7-day section" doc comment corrected.
  - `[low]` `[patch]` Empty-string `displayName` rendered a blank caption — `label(for:)` falls back to the generic label for nil or empty; new test covers the empty-string case.

Rejected findings (noise, dropped): headroom clamping mismatch (`HeadroomRingGauge` already clamps internally at lines 44/55/63); truncation vs rounding in a11y percent (matches SevenDayGaugeSection exactly); doc-comment "at [absolute]" mismatch (false — `absoluteTimeString()` emits the "at" prefix); ForEach index identity (spec-directed; array replaced wholesale per poll on MainActor, no bindings); redundant double empty-check (mirrors the existing PopoverView + section guard precedent); past `resetsAt` countdown (shared path with existing windows by design); NaN/infinite utilization (JSONDecoder rejects non-finite numbers, unreachable); stale gauges while disconnected (matches 5h/7d stale-data contract; sign-out clears `scopedLimits`); hardcoded 56/4 (existing sections inline the same literals); indistinguishable duplicate fallback labels (speculative); unbounded section height for many entries (speculative); missing `OSAllocatedUnfairLock` import (false — suite compiles and passes); model-test placement (cosmetic); localization (no localization infrastructure exists); xcodegen not evidenced (was run and verified); in-place-mutation observation test (array is replaced, not mutated in place); "Model" fallback as un-asked-for extension (deliberate spec resolution from 21.1's kept-nil-label matrix row); omitted hover/slope/tap parity (spec Never; slope has no data source, tap-to-analytics arrives with the 21.3 series).

## Verification

**Commands:**
- `xcodegen generate` — expected: succeeds, project includes the new files
- `xcodebuild -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= build` — expected: build succeeds
- `xcodebuild -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test` — expected: all tests pass, including the new scoped-limit view suites

## Auto Run Result

**Status:** done

**Summary:** The popover's authenticated view now shows one gauge block per model-scoped weekly cap (e.g. Claude Fable 5): caption label from the API's `display_name` (generic "Model" fallback for nil/empty), 56px/4px `HeadroomRingGauge`, and `CountdownLabel` with relative + absolute reset time — matching the 7-day section's layout. The section (and its divider) is absent entirely when the API reports no scoped limits, so accounts without Fable access see zero change.

**Files changed:**
- `cc-hdrm/Views/ScopedLimitGaugeSection.swift` (new) — per-entry label + ring + countdown blocks with combined VoiceOver label; internal `entries` projection and `label(for:)` for testability.
- `cc-hdrm/Views/PopoverView.swift` — scoped section inserted between the 7d block and the extra-usage card, guarded by internal `showsScopedLimitSection`.
- `cc-hdrmTests/Views/ScopedLimitGaugeSectionTests.swift` (new) — 11 tests covering every I/O-matrix row plus fallback labels, ordering, and hosting-controller render.
- `cc-hdrmTests/Views/PopoverViewTests.swift` — new suite: guard polarity both ways plus observation-tracking proof that `body` reads `scopedLimits`.

**Review findings:** 3 patched (all low — see Review Triage Log), 0 deferred, 18 rejected as noise. No intent gaps, no spec repairs.

**Follow-up review recommendation:** false — patched counts: high 0, medium 0, low 3; score = 3×0 + 1×3 = 3 (threshold 5).

**Verification:**
- `xcodegen generate` — succeeded, new files picked up.
- `xcodebuild ... build` — BUILD SUCCEEDED (post-implementation and post-patch).
- `xcodebuild ... test` — 1491 tests in 129 suites, all passed post-patch (1490 pre-patch; the single earlier failure was the pre-existing `TPPChartDataServiceTests/dailyAverage()` midnight flake in Epic 20 code, untouched by this story and tracked separately).
- Matrix test audit: every I/O matrix row covered by a test that ran and passed.

**Residual risks:**
- `TPPChartDataServiceTests/dailyAverage()` fails when the suite runs within 4 hours of local midnight (fixture spans a day boundary) — pre-existing, unrelated, flagged as a separate task.
- Countdown formatting for a `resetsAt` in the past follows the same shared path as the existing 5h/7d windows; any oddity there is common to all three.
