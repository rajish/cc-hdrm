# Sprint Change Proposal: Weekly-First Monitoring (5-Hour Limit Retired)

**Date:** 2026-10-31
**Triggered by:** External platform change — Anthropic removed the 5-hour usage limit
**Category:** Strategic pivot / platform change
**Status:** APPROVED 2026-10-31 (Boss)
**Release:** `[minor]` (1.6.0 → 1.7.0)
**Review mode:** Batch

---

## 1. Issue Summary

Anthropic removed the 5-hour rolling limit. The weekly allowance is now the only plan-wide limit. The app was built with the 5-hour window as its primary value, so its core display and most analytics now fail.

### Evidence

- **API:** since 2026-10-31 08:03 UTC, `/api/oauth/usage` returns `five_hour: null`. Last non-null `five_hour_util` in `usage.db` was 07:02 UTC. 381 of 410 polls today have no 5-hour value.
- **Still present:** `seven_day` (28% at time of writing) and the Fable `limits[]` entry with `kind: "weekly_scoped"` (31%).
- **Live breakage:** `cc-hdrm/State/AppState.swift:144-147` — `displayedWindow` returns `.fiveHour` when `fiveHour == nil`. `menuBarHeadroomState` then becomes `.disconnected`. The menu bar shows "—" and a grey icon while connected.

### Behaviour of each feature with no 5-hour data (code audit)

| Feature | Files | State today |
|---|---|---|
| Menu bar text, gauge icon, VoiceOver label | `cc-hdrm/State/AppState.swift:144-183,234`, `cc-hdrm/App/AppDelegate.swift:528-580` | **Broken** — shows disconnected |
| Extra-usage $ in menu bar | `cc-hdrm/State/AppState.swift:197-240` | **Broken** — hidden behind the disconnected check |
| Popover 5h ring | `cc-hdrm/Views/PopoverView.swift:128`, `cc-hdrm/Views/FiveHourGaugeSection.swift` | Empty grey ring, always shown |
| "N full 5h quotas left" | `cc-hdrm/Views/SevenDayGaugeSection.swift:33,65-67` | Refers to a limit that no longer exists |
| Slope arrows | `cc-hdrm/Services/SlopeCalculationService.swift:46-148` | 5h always flat. 7d normalised to 5h credits, flips between flat and rising |
| Popover sparkline | `cc-hdrm/Views/Sparkline.swift:40-46,217-231` | Blank canvas (charts 5h only) |
| Analytics charts | `cc-hdrm/Views/StepAreaChartView.swift`, `cc-hdrm/Views/BarChartView.swift`, `cc-hdrm/Views/AnalyticsView.swift:26,39-57` | 5h series on by default, empty. Per-point slope colours gone |
| Headroom breakdown, value $, cycle % | `cc-hdrm/Services/HeadroomAnalysisService.swift:19-80`, `cc-hdrm/Services/SubscriptionValueCalculator.swift:48-53`, `cc-hdrm/Services/ValueInsightEngine.swift`, `cc-hdrm/Services/CycleUtilizationCalculator.swift:50-63` | **Silently wrong** — 0% used, $0 value |
| Tier recommendation | `cc-hdrm/Services/TierRecommendationService.swift:65-78,191,318` | **Silently wrong** as old events age out — leans to downgrade |
| Subscription patterns | `cc-hdrm/Services/SubscriptionPatternDetector.swift:96,191-198,317` | Forgotten-subscription and usage-decay stop seeing data |
| Passive tokens-per-percent (TPP) | `cc-hdrm/Services/PassiveTPPEngine.swift:46-50` | **Broken** — returns early, records nothing |
| TPP backfill | `cc-hdrm/Services/HistoricalTPPBackfillService.swift:150,282` | **Broken** |
| Benchmark | `cc-hdrm/Services/BenchmarkService.swift:143-287` | **Broken** — retries with doubling real API spend, then "inconclusive" |
| TPP charts | `cc-hdrm/Services/TPPChartDataService.swift:121-366` | Empty (reads `tppFiveHour` only) |
| Threshold notifications | `cc-hdrm/Services/NotificationService.swift:63-126` | Degrades fine — 7d and Fable still fire |
| Reset-event detection | `cc-hdrm/Services/HistoricalDataService.swift:498-579` | Works via 7d `resets_at`, now ~weekly. `five_hour_peak` = NULL |
| Polling, decoding, DB schema | `cc-hdrm/Services/PollingEngine.swift`, `cc-hdrm/Models/UsageResponse.swift`, `cc-hdrm/Services/DatabaseManager.swift` | Fine — all 5h fields optional / nullable |
| Custom tier settings | `cc-hdrm/Views/SettingsView.swift:375-399`, `cc-hdrm/Models/RateLimitTier.swift` | Requires an obsolete 5h credit value |

---

## 2. Impact Analysis

### Checklist record

| Item | Status | Note |
|---|---|---|
| 1.1 Trigger | [x] | External API change, no triggering story |
| 1.2 Problem | [x] | Strategic pivot / platform change |
| 1.3 Evidence | [x] | `usage.db` polls + code audit above |
| 2.1 Current epic (21) | [x] | 21.1–21.5 done and unaffected (21.5 released in 1.6.0) |
| 2.2 Epic-level change | [!] | New Epic 26 |
| 2.3 Remaining epics | [!] | Codex epics 22–25 assume Claude's 5h-primary layout as a template |
| 2.4 Obsolete / new epics | [x] | None obsolete. One new epic |
| 2.5 Resequencing | [!] | Epic 26 before Codex (22–25) |
| 3.1 PRD | [!] | 15 FRs to rewrite or retire (section 4.2) |
| 3.2 Architecture | [!] | Dual-window, promotion, slope, credit math, headroom sections |
| 3.3 UX | [!] | Both UX specs: information hierarchy, gauges, promotion, sparkline, slope |
| 3.4 Other | [!] | `README.md`, `docs/images/demo.gif` |
| 4.1 Direct adjustment | Viable | New epic, existing structure kept |
| 4.2 Rollback | Not viable | Nothing to revert; the platform changed |
| 4.3 MVP review | [x] | MVP goal holds ("know your headroom"); its primary window changes |
| 4.4 Path | [x] | Option 1, Direct Adjustment |

### Epic impact

- **Epics 3, 4, 5, 10, 11, 12, 13, 14, 15, 16, 17, 20** — done; their 5h-based behaviour gets replaced by Epic 26. Completed story files stay as historical record.
- **Epic 21 (Fable)** — 21.1–21.5 done and unaffected. 21.5 (Fable benchmark default) merged and released in 1.6.0 on 2026-10-31; 26.8 must keep it working on weekly deltas.
- **Epics 22–25 (Codex, backlog)** — Codex still has its own 5-hour window. But stories 23.1, 23.2, 23.4, 24.1, 25.1–25.3 planned to reuse Claude's 5h components. After Epic 26 those components become weekly-only. Codex stories must be re-validated when Epic 22 starts. No edits to them now.

### Data

- **No database migration and no data deletion.** `five_hour_*` columns stay nullable. Historical 5h data stays queryable.
- New polls simply store NULL in those columns, which already happens.

---

## 3. Recommended Approach

**Option 1 — Direct Adjustment: one new epic, nine stories, shipped as one `[minor]` release.**

- Rollback makes no sense: the platform changed, not our code.
- The product goal ("glance at the menu bar, know your headroom") still holds. Only the window changes.
- **Effort:** High — ~40 production files, most test suites touching 5h.
- **Risk:** Medium. Main risks:
  - Weekly data moves in coarse 1% steps. Pace and TPP must cope with that.
  - Benchmark on weekly data costs real quota (1% of weekly ≈ 8–13× a 5h percent).
- **Timeline:** the menu bar stays broken until release (your choice: bundle, no separate patch).

### Decisions taken

| Decision | Choice | Source |
|---|---|---|
| Urgent menu bar fix | Bundled into the `[minor]` release (story 26.1) | User |
| Trend signal | **Weekly pace** replaces the slope arrow | User |
| Analytics features | **All rebased on weekly** data and weekly resets | User |
| Historical 5h data | Kept. 5h chart series off by default, hidden when the range has no 5h data | Default |
| Fable weekly cap in menu bar | Reuse the existing gauge-icon corner dot for the Fable cap at caution or worse. Menu bar number stays the overall weekly | Default — say if you want "tighter of the two" instead |
| Code for a returning 5h limit | Removed, not kept dormant (YAGNI). Decoding stays tolerant | Default |
| New pace notification ("will run out before reset") | **Not included.** Add later if wanted | Default |

---

## 4. Detailed Change Proposals

### 4.1 New Epic 26 — Weekly-First Monitoring

Stories in build order. 26.1 fixes the live breakage first.

**26.1 — Weekly allowance in the menu bar**
- Menu bar text, colour and gauge icon always use `seven_day`.
- Remove `DisplayedWindow`, the promotion rule, `quotasRemaining`, and the "7d" promoted label.
- Extra-usage $ text shows again when the weekly window is exhausted.
- Exhausted state shows the weekly reset countdown (`countdownString()` already formats days: "↻ 3d 4h").
- Gauge icon corner dot shows the Fable weekly cap state when caution, warning or critical.
- VoiceOver label speaks weekly headroom.
- Files: `cc-hdrm/State/AppState.swift`, `cc-hdrm/App/AppDelegate.swift`, `cc-hdrm/Views/GaugeIcon.swift`.

**26.2 — Weekly pace (replaces slope)**
- Pace model, from `seven_day.utilization` and `resets_at` only:
  - `weekStart = resetsAt − 7 days`, `elapsed = clamp((now − weekStart) / 7 days, 0…1)`.
  - `paceDelta = utilization − elapsed × 100` (positive = ahead of even spending).
  - Projected run-out: `rate = utilization / (now − weekStart)`; `runOut = now + (100 − utilization) / rate`. Shown only when `runOut < resetsAt` and at least ~4 hours of the week have passed.
- Menu bar appends the existing actionable arrow only when run-out is projected before reset.
- Popover line: "On pace" / "Ahead of pace — runs out ~Thu 14:00".
- Delete `SlopeCalculationService`, its protocol, `SlopeLevel`, `SlopeIndicator`, slope buffer wiring in `cc-hdrm/Services/PollingEngine.swift:343-359`, and per-point slope colouring in `cc-hdrm/Views/StepAreaChartView.swift`.
- Known ceiling: average-since-reset projection is pessimistic after a heavy first day. Upgrade path: blend with a recent-window rate.

**26.3 — Weekly-first popover**
- Remove the 5h ring (`cc-hdrm/Views/FiveHourGaugeSection.swift`). Weekly ring becomes the large primary gauge with countdown and pace line.
- Remove "N full 5h quotas left".
- Fable section stays below the weekly ring.
- Sparkline shows the current weekly cycle (since last weekly reset) with an even-pace diagonal, instead of 24h of 5h data.
- VoiceOver reading order starts with weekly.

**26.4 — Analytics charts weekly-first**
- Default series: weekly + Fable. 5h series off by default, hidden when the selected range has no 5h data.
- Reset markers from weekly resets.
- Files: `cc-hdrm/Views/AnalyticsView.swift`, `cc-hdrm/Views/StepAreaChartView.swift`, `cc-hdrm/Views/BarChartView.swift`, `cc-hdrm/Views/UsageChart.swift`.

**26.5 — Value and headroom analysis per weekly cycle**
- `ResetEvent` analysis keyed on weekly resets, using the stored `sevenDayUtil` peak.
- Breakdown becomes two bands: used vs unused weekly capacity. The "7d-constrained" band is retired.
- Value $, cycle utilisation and insight copy rebased on weekly cycles.
- Old 5h-based events: still displayed for their period; no recomputation.
- Files: `cc-hdrm/Services/HeadroomAnalysisService.swift`, `cc-hdrm/Models/HeadroomBreakdown.swift`, `cc-hdrm/Views/HeadroomBreakdownBar.swift`, `cc-hdrm/Services/SubscriptionValueCalculator.swift`, `cc-hdrm/Services/ValueInsightEngine.swift`, `cc-hdrm/Services/CycleUtilizationCalculator.swift`, `cc-hdrm/Services/HistoricalDataService.swift`.

**26.6 — Tier advice and subscription patterns on weekly data**
- Tier fit uses weekly peak per cycle and count of weekly exhaustions (plus extra usage, unchanged).
- Usage-decay and forgotten-subscription detectors use weekly utilisation.
- Files: `cc-hdrm/Services/TierRecommendationService.swift`, `cc-hdrm/Services/SubscriptionPatternDetector.swift`.

**26.7 — Tokens-per-percent on weekly deltas**
- Passive engine, backfill and charts switch to `seven_day` deltas (`tpp_seven_day` already exists in storage).
- Accumulation window lengthened to fit 1% weekly steps. Confidence thresholds retuned.
- Charts read `tppSevenDay`. Older 5h-based TPP points stay visible, labelled as 5h-based.
- Files: `cc-hdrm/Services/PassiveTPPEngine.swift`, `cc-hdrm/Services/HistoricalTPPBackfillService.swift`, `cc-hdrm/Services/TPPChartDataService.swift`, `cc-hdrm/Services/TPPStorageService.swift`.

**26.8 — Benchmark on weekly deltas**
- Measures the weekly delta. UI copy: "per 1% of your weekly allowance".
- **Hard spend cap** and an up-front estimate of how much weekly allowance the run will use, confirmed by the user.
- **Gate:** if one run would cost more than a set share of the weekly allowance, stop and ask whether to retire the benchmark instead.
- Keeps the 21.5 Fable default model working.

**26.9 — Notifications, tier credits and settings cleanup**
- Remove the 5h threshold state machine and its notifications. Weekly and Fable thresholds unchanged.
- Notification copy names the weekly window ("weekly allowance resets Thu 09:00").
- `RateLimitTier`: drop `fiveHourCredits`. Custom tier needs only the weekly credit value.
- Settings: remove the "5-hour credit limit" field. Old stored preference ignored, not migrated.
- Lands last: 26.5 and 26.6 must stop using 5h credits first.
- Docs: `README.md` lines 21, 28, 31, 42, 104. Re-record `docs/images/demo.gif`.
- **This story's PR title carries `[minor]`.** Earlier story PRs carry no keyword.

### 4.2 PRD (`_bmad-output/planning-artifacts/prd.md`)

FR numbers stay stable. Each rewritten FR gets "(revised 2026-10-31)".

| FR | OLD | NEW |
|---|---|---|
| FR6 | User can see current 5-hour usage percentage in the menu bar at all times | User can see current weekly allowance headroom in the menu bar at all times |
| FR9 | User can see 5-hour usage bar with percentage in the expanded panel | **Retired** — Anthropic removed the 5-hour limit (2026-10-31) |
| FR10 | User can see 7-day usage bar with percentage in the expanded panel | User can see the weekly usage gauge as the primary gauge in the expanded panel |
| FR11 | User can see time remaining until 5-hour window resets | **Retired** |
| FR17 | …when 5-hour usage crosses 80% | User can receive a macOS notification when weekly usage crosses the warning threshold |
| FR18 | …when 5-hour usage crosses 95% | User can receive a macOS notification when weekly usage crosses the critical threshold |
| FR33 | …(timestamp, 5h utilization, 5h resets_at, 7d utilization, 7d resets_at)… | …(timestamp, 7d utilization, 7d resets_at, scoped caps, extra usage). Historical 5h columns retained, nullable |
| FR35 | …compact 24-hour usage trend of 5h utilization… | User can view the current weekly cycle's usage trend against an even-pace line in the popover |
| FR39 | Effective headroom = min(5h, 7d) | **Retired** — weekly headroom is the effective headroom |
| FR40 | Detects 5h resets; three-way classification | App detects weekly resets and classifies each cycle's capacity as used or unused |
| FR41 | Breakdown of used, 7d-constrained and true unused | Breakdown of used and unused weekly capacity per cycle |
| FR42 | Computes usage rate of change from recent poll history | App computes weekly pace: usage versus share of the week elapsed |
| FR43 | Maps rate to 4-level slope | App projects run-out time from average usage since the weekly reset |
| FR44 | Slope indicator next to the percentage in the menu bar | Menu bar shows an indicator when run-out is projected before the weekly reset |
| FR45 | Per-window slope indicators for 5h and 7d gauges | Popover shows pace status and projected run-out time |

Also: prose sections "API Response Format" (L71–107), Phase 1 MVP (L161–162), data per poll (L208), Subscription Value & Headroom Analysis (L212–226), slope display (L243), Journeys 1–3 (L286–312), journey table (L323) — rewrite to weekly; add a dated note that the 5h window was retired. FR46–FR47 wording unchanged; their implementation moves to weekly (26.6). FR51–FR60 (Codex) unchanged.

### 4.3 Architecture (`_bmad-output/planning-artifacts/architecture.md`)

- Cross-cutting concerns (L51–57): replace "dual-window logic" and the credit-math promotion rule with "single weekly window + scoped caps".
- AppState (L143–157): remove `fiveHour`, `fiveHourSlope`, `displayedWindow`; add pace state.
- API integration (L179), CodingKeys example (L322–336): `five_hour` decoded but ignored.
- SQLite schema (L803–844): mark `five_hour_*` columns as historical; reset events from weekly resets.
- SlopeCalculationService (L894–929): replace with weekly pace calculation.
- HeadroomAnalysisService (L931–964), SubscriptionPatternDetector / TierRecommendationService (L967, L992), credit limit handling (L1032): rebase on weekly cycles and weekly credits.
- Component modifications, sparkline, analytics, settings, data flow, requirements mapping (L1141–1519): update to weekly-first.
- Naming example `fiveHourUtilization` (L253) and `project-context.md` L92: swap for a weekly example.
- Out of scope, noted: architecture has no Fable, TPP or Codex sections.

### 4.4 UX (`ux-design-specification.md`, `ux-design-specification-phase3.md`)

- Phase 1 spec: information hierarchy (L306), gauge layout (L383–413), design direction (L426–490), Journey 4 (promotion — retire), journey patterns (L639), MenuBarTextRenderer (L712), state communication (L832–858), transition feedback (L879), notification copy (L133, L900–944), screen reader order (L998), accessibility (L416).
- Phase 3 spec: slope sections (L63–99, L590) → pace; sparkline (L143–184, L697) → weekly cycle with pace line; series toggles (L282–312); Feature 4 headroom analysis (L320–411) → two-band weekly; credit lookup (L662).

### 4.5 Other artifacts

- `_bmad-output/planning-artifacts/epics/epic-list.md`: add Epic 26. New file `epic-26-weekly-first-monitoring.md`.
- `_bmad-output/planning-artifacts/epics/requirements-inventory.md`: stale (stops at FR45). Update FR rows listed in 4.2 only.
- `_bmad-output/implementation-artifacts/sprint-status.yaml`: add `epic-26` and stories 26-1 … 26-9 as `backlog`.
- `README.md`, `docs/images/demo.gif`: updated in the docs step.

---

## 5. Implementation Handoff

**Scope: Moderate** — new epic and backlog reorganisation; no architectural rewrite.

| Role | Responsibility |
|---|---|
| Developer (this session, after approval) | Apply PRD, architecture, UX, epic and sprint-status edits from section 4 |
| Developer (`bmad-build`, one story at a time) | Implement 26.1 → 26.9 in order; `bmad-code-review` before each PR |
| Maintainer (Boss) | Approve the benchmark spend gate in 26.8; put `[minor]` on the final PR title |

### Success criteria

- Menu bar shows weekly headroom and colour while connected with `five_hour: null`.
- No UI element shows an empty 5h gauge, 5h copy or "5h quotas left".
- Pace line and run-out projection match hand-calculated values in tests.
- Headroom breakdown, value $, tier advice and TPP produce non-zero results from weekly data.
- No `DELETE` or `DROP` on historical tables.
- All tests pass; release 1.7.0 published from the `[minor]` PR.

---

## Artifact Updates Applied (2026-10-31)

| Artifact | Change |
|---|---|
| `_bmad-output/planning-artifacts/prd.md` | Edit history; 2026-10-31 API note; FR6, FR10, FR17, FR18, FR33, FR35, FR40–FR45 revised; FR9, FR11, FR39 retired; headroom analysis → two bands; slope section → Weekly Pace Indicator; Journeys 1–3 rewritten |
| `_bmad-output/planning-artifacts/architecture.md` | Dated note; single weekly window; pace calculation replaces slope; two-band headroom; weekly-only credits; `five_hour_*` columns historical |
| `_bmad-output/planning-artifacts/ux-design-specification.md` | Weekly-first menu bar, popover, notifications, VoiceOver; Journey 4 and promotion transition retired |
| `_bmad-output/planning-artifacts/ux-design-specification-phase3.md` | Slope → pace; weekly-cycle sparkline; series defaults; two-band breakdown |
| `_bmad-output/planning-artifacts/project-context.md` | Naming example `sevenDayUtilization` |
| `_bmad-output/planning-artifacts/epics/epic-26-weekly-first-monitoring.md` | New |
| `_bmad-output/planning-artifacts/epics/epic-list.md`, `epics/index.md` | Epic 26 added |
| `_bmad-output/planning-artifacts/epics/requirements-inventory.md` | Revised / retired FR rows synced with PRD |
| `_bmad-output/implementation-artifacts/sprint-status.yaml` | `epic-26` + stories 26-1 … 26-9 as backlog |

**Decisions made while applying:**
- Fable corner dot also shows when the Fable cap is exhausted.
- Pace arrow glyph is `↗`; the old steep arrow `⬆` is retired.
