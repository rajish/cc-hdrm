# Epic 21 Context: Fable Model Usage Tracking (Phase 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Claude Fable 5 has its own model-scoped weekly cap (50% of the weekly limit on Max plans) that the app cannot see today. A user can hit the Fable wall while the app reports healthy overall headroom (observed live: Fable 63% vs weekly 67% — the two run independently). This epic parses the usage API's new `limits` array, surfaces the Fable window everywhere existing windows appear (popover, history, analytics, notifications, benchmark), and stays completely invisible for accounts without Fable access.

## Stories

- Story 21.1: Scoped Limits Parsing & Domain Model
- Story 21.2: Popover Fable Utilization Display
- Story 21.3: Persistence & Analytics Series
- Story 21.4: Fable Threshold Notifications
- Story 21.5: Benchmark Default Model Update

## Requirements & Constraints

- The `/api/oauth/usage` response now includes a `limits` array (source of truth for model-scoped caps). Entry fields: `kind` (`session`, `weekly_all`, `weekly_scoped`), `group`, `percent` (0–100), `severity`, `resets_at` (ISO 8601 or null), `is_active`, and `scope` — null for unscoped entries; for scoped entries `scope.model.display_name` carries the label (e.g. "Fable") and `scope.model.id` may be null. `scope.surface` exists and may be null.
- Legacy per-model windows (`seven_day_sonnet`, `seven_day_opus`) now return `null` and are superseded — the `sevenDaySonnet` parsing is dead code to remove.
- The response also gained a `spend` object and extended `extra_usage` fields (`daily`, `weekly`, `currency`) — explicitly out of scope for this epic; ignore them.
- Absent `limits` array, or no `weekly_scoped` entries, must decode cleanly to nil: no crash, nothing displayed, no behavior change. Every feature in this epic degrades to "not shown".
- Benchmark model list gains `claude-fable-5`; the benchmark request path must work end to end with that model ID.

Success criteria:

- Popover shows Fable utilization + reset countdown when the API reports a scoped weekly limit; shows nothing when it doesn't.
- Fable history appears in analytics after at least one poll cycle post-migration.
- Notifications fire at 20% and 5% Fable headroom, once per threshold crossing.
- Benchmark can measure `claude-fable-5` end to end.
- Zero behavior change for accounts without Fable access.

## Technical Decisions

- **Generic parsing, no hardcoded model names.** Decode `weekly_scoped` entries into a generic scoped-limit struct and label UI with the API's `scope.model.display_name`. Future model-scoped caps must appear without code changes.
- **Additive only.** New optional fields in the response model; new nullable SQLite columns (`fable_weekly_util REAL`, `fable_weekly_resets_at INTEGER` on `usage_snapshots`, plus matching rollup aggregates). Schema migration bumps the tracked schema version. No new services, no new patterns.
- **Copy existing precedents rather than inventing:** window display follows the existing 5h/7d window components; persistence follows the Epic 17 extra-usage column migration precedent (`cc-hdrm/Services/DatabaseManager.swift`, `cc-hdrm/Services/HistoricalDataService.swift`, `cc-hdrm/Models/UsagePoll.swift`); notifications follow the existing 20%/5% headroom model in `cc-hdrm/Services/NotificationService.swift`; benchmark follows Epic 20 (`cc-hdrm/Views/BenchmarkSectionView.swift`, `cc-hdrm/Services/BenchmarkService.swift`).
- Rollups are lazy (computed on analytics open); the new columns must flow through the existing snapshot → rollup aggregation path.
- The token-throughput pipeline (Epic 20) is already model-agnostic — Fable tokens flow through the existing log parser keyed by model string. Only the benchmark default model list changes.

## UX & Interaction Patterns

- Popover detailed panel: one additional row/gauge for the scoped limit, labeled with the API-provided display name, with reset countdown in both relative and absolute form — matching the existing windows exactly. Hidden entirely when no scoped limit is reported.
- Analytics window: one additional series toggle for Fable utilization, following the existing series-toggle pattern. No new interaction design anywhere in this epic.
- Benchmark UI copy must note that Fable benchmarks consume the Fable cap; the benchmark stays behind the existing opt-in Measure button.

## Cross-Story Dependencies

- 21.1 → 21.2 → 21.3 → 21.4 are sequential; each builds on the parsed domain data from 21.1.
- 21.5 (benchmark) is independent of 21.1–21.4 and can run at any time.
- 21.3 depends on the Epic 17 migration precedent already in the codebase; 21.4 dedup state must be independent per window so Fable alerts don't suppress or duplicate existing window alerts.
- `sprint-status.yaml` is a shared resource — each story branch updates only its own entry.
