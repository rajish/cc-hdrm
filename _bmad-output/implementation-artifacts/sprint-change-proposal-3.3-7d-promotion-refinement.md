# Sprint Change Proposal: Refined 7d Promotion Rule & Related Enhancements

**Date:** 2026-02-05
**Triggered by:** Story 3.2 (Context-Adaptive Display & Tighter Constraint Promotion)
**Category:** Misunderstanding of original requirements — promotion rule works technically but doesn't match real-world usage patterns
**Status:** APPROVED

---

## Issue Summary

Story 3.2's 7d promotion rule (`7d headroom < 5h headroom AND 7d in warning/critical`) fires too aggressively in practice. When 7d is promoted, it hides the 5h limit and slope indicator, which are the user's primary working context. The user reports repeatedly clicking the menu bar to reveal hidden 5h data — the promotion trades away essential session-level info for weekly-level info too eagerly.

## Evidence

- Direct user observation: frequent tapping to reveal 5h info hidden by 7d promotion
- Slope indicator (Epic 11, fully implemented) becomes invisible when 7d is promoted
- 7d slope calculation produces "flat" readings almost always due to the ~12.6x larger credit pool, making promoted 7d slope useless

## Root Cause

The percentage-comparison promotion rule doesn't reflect whether 7d is actually the binding constraint in practical terms. A better rule uses credit math: promote 7d only when the remaining 7d budget can't sustain one more full 5h cycle.

## Approved Changes

### New Story: 3.3 — Refined 7d Promotion Rule, Credit-Math Slope Normalization & Popover Quotas Display

Single story implementing all corrections:

1. **RateLimitTier credit limits** (absorbed from Story 14.1) — enum with per-tier credit values
2. **New promotion rule** — `remaining_7d_credits / 5h_credit_limit < 1`
3. **7d colored dot on gauge icon** — caution/warning/critical only
4. **"7d" label on gauge icon** — when 7d is promoted
5. **5h limit + slope always visible** when 7d is not promoted
6. **"X full 5h quotas left"** in popover 7d section — always visible, verbose
7. **Credit-normalized slope calculation** — `raw_7d_rate × (7d_limit / 5h_limit)` so same thresholds work for both windows

### Implementation Impact

| Component                      | Change                                                  |
| ------------------------------ | ------------------------------------------------------- |
| `RateLimitTier` (new file)       | Credit limit enum per architecture spec                 |
| `AppState.displayedWindow`       | Credit-math promotion rule                              |
| `GaugeIcon`                      | Corner dot (7d color) + "7d" label when promoted        |
| `SlopeCalculationService`        | Credit-normalized rate for 7d window                    |
| `SevenDayGaugeSection`           | "X full 5h quotas left" line                            |
| `AppDelegate`                    | Pass 7d state to GaugeIcon                              |
| `AppStateTests`                  | Rewrite promotion tests                                 |
| `SlopeCalculationServiceTests`   | Add normalization tests                                 |

### Effort & Risk

- **Effort:** Low-Medium — story-level changes to existing components, one new data enum
- **Risk:** Low — isolated changes, clear boundaries, no architectural shifts
- **Timeline impact:** Minimal — refinement, not rearchitect

## Artifact Updates Applied

| Artifact                        | Sections Updated                                                    |
| ------------------------------- | ------------------------------------------------------------------- |
| `ux-design-specification.md`      | Journey 4, State Communication table, GaugeIcon spec, Tighter Constraint Pattern, Transition Feedback |
| `ux-design-specification-phase3.md` | Slope calculation section, popover 7d section display               |
| `epics.md`                        | Story 3.3 added, Epic 3 description updated, Story 14.1 marked absorbed |
| `architecture.md`                 | Dual-window logic description, SlopeCalculationService calculation  |
| `sprint-status.yaml`             | Epic 3 reopened, Story 3.3 added as ready-for-dev                   |

## PRD MVP Impact

None — all changes are Phase 3 territory.

## Handoff Plan

| Role          | Responsibility                                              |
| ------------- | ----------------------------------------------------------- |
| PM            | Proposal complete, story written, artifacts updated (DONE)  |
| Architect     | Verify `AppState` dependency on `RateLimitTier` is clean      |
| SM            | Create dev-ready story tasks if needed                      |
| Dev           | Implement Story 3.3                                         |

## Story File

`_bmad-output/implementation-artifacts/3-3-refined-7d-promotion-credit-math-slope-normalization.md`
