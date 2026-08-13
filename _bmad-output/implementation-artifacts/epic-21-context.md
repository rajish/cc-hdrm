# Epic 21 Context: Fable Model Usage Tracking (Phase 6)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Claude Fable 5 has a model-scoped weekly cap (50% of the weekly limit on Max plans) that runs independently of the overall 5h/7d windows the app already tracks. A user can hit the Fable wall while the app reports healthy overall headroom (observed live: Fable 63% vs weekly 67%). This epic parses the usage API's new `limits` array, surfaces the Fable window everywhere the existing windows appear (popover, persistence, analytics, notifications, benchmark), and stays invisible for accounts without Fable access.

## Stories

- Story 21.1: Scoped limits parsing & domain model
- Story 21.2: Popover Fable utilization display
- Story 21.3: Persistence & analytics series
- Story 21.4: Fable threshold notifications
- Story 21.5: Benchmark default model update

## Requirements & Constraints

- The `/api/oauth/usage` response now includes a `limits` array. Entry shape: `kind` (`session`, `weekly_all`, `weekly_scoped`), `group`, `percent` (0–100), `severity`, `resets_at` (ISO 8601 or null), `is_active`, and `scope` (null for unscoped; `scope.model.display_name` names the model for scoped caps, `scope.model.id` may be null).
- The `limits` array is the source of truth for model-scoped caps. Legacy `seven_day_sonnet` / `seven_day_opus` fields now return `null` and are dead — the `sevenDaySonnet` parsing should be removed.
- Absent `limits` array, or no `weekly_scoped` entries, must decode cleanly to nil: no crash, nothing displayed, zero behavior change for accounts without Fable access.
- On Pro plans Fable runs on pay-as-you-go usage credits, so a scoped weekly limit may simply not appear — the absent case is normal, not an error.
- Success criteria:
  - Popover shows Fable utilization plus reset countdown when the API reports a scoped weekly limit; shows nothing when it doesn't.
  - Fable history appears in analytics after at least one poll cycle post-migration.
  - Notifications fire at 20% and 5% Fable headroom, once per crossing.
  - Benchmark can measure `claude-fable-5` end to end.

## Technical Decisions

- **Generic parsing, no hardcoded model names.** Decode `weekly_scoped` entries generically and label UI with the API's `scope.model.display_name`. Future model-scoped caps must appear without code changes.
- **Additive only.** New optional fields on the response model, new nullable DB columns. No destructive migrations, no reworking existing windows.
- **Copy existing precedents rather than inventing patterns:** window display follows the existing 5h/7d window rows, persistence follows the Epic 17 extra-usage column precedent (additive columns on `usage_snapshots` plus rollup aggregates, schema-version bump), notifications follow the existing threshold state machines, benchmark follows the existing opt-in Measure flow.
- Persistence columns: `fable_weekly_util REAL` and `fable_weekly_resets_at INTEGER` on `usage_snapshots`, with matching rollup aggregates.
- Notification model: 20% headroom (warning) and 5% headroom (critical), fire once per threshold crossing, re-arm on recovery, independent dedup state per window, respecting existing threshold preferences. Threshold state machines live in the notification service, not app state.
- Key touch points: `cc-hdrm/Models/UsageResponse.swift`, `cc-hdrm/Models/UsagePoll.swift`, `cc-hdrm/Services/DatabaseManager.swift`, `cc-hdrm/Services/HistoricalDataService.swift`, `cc-hdrm/Services/NotificationService.swift`, `cc-hdrm/Views/BenchmarkSectionView.swift`, `cc-hdrm/Services/BenchmarkService.swift`.
- No new services, no new architectural patterns. The response also gained a `spend` object and extended `extra_usage` fields (`daily`, `weekly`, `currency`) — out of scope for this epic, do not parse them.

## UX & Interaction Patterns

- The Fable row/gauge sits in the detailed usage panel alongside the existing windows, labeled with the API-provided display name (currently "Fable"), hidden entirely when no scoped limit is reported.
- Reset times use the established dual time display: relative countdown ("resets in 47m") plus absolute time ("at 4:52 PM"), matching the existing window rows.
- Notifications are self-contained: percentage, threshold, and reset countdown with absolute time, so the user needs no further clicks.
- Analytics gains one Fable series toggle following the existing series-toggle pattern (toggle state persisted per time range).
- Benchmark UI copy must note that Fable benchmarks consume the Fable cap; the benchmark stays behind the opt-in Measure button.

## Cross-Story Dependencies

- 21.1 → 21.2 → 21.3 → 21.4 are sequential; each builds on the parsed domain data from 21.1.
- 21.5 is independent of 21.1–21.4 and can run at any time.
- Epics 22–25 (concurrent Codex proposal) are independent of this epic — no shared scope beyond planning artifacts.
- `sprint-status.yaml` is a shared resource: update only this epic's own story entries.
