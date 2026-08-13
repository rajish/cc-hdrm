# Epic 21 Context: Fable Model Usage Tracking

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Claude Fable 5 has its own model-scoped weekly cap (50% of the weekly limit on Max plans) that the app cannot currently see. A user can hit the Fable wall while the app reports healthy overall headroom (observed live: Fable 63% vs weekly 67%). This epic parses the usage API's new `limits` array, surfaces the Fable window everywhere the existing 5h/7d windows appear (popover, history, analytics, notifications, benchmark), and stays completely invisible for accounts without Fable access.

## Stories

- Story 21.1: Scoped limits parsing & domain model
- Story 21.2: Popover Fable utilization display
- Story 21.3: Persistence & analytics series
- Story 21.4: Fable threshold notifications
- Story 21.5: Benchmark default model update

## Requirements & Constraints

- The `/api/oauth/usage` response now includes a `limits` array. Entries carry `kind` (`session`, `weekly_all`, `weekly_scoped`), `group`, `percent` (0-100), `severity`, `resets_at` (ISO 8601 or null), `is_active`, and an optional `scope` object; model-scoped entries carry `scope.model.display_name` (e.g. "Fable") while `scope.model.id` may be null.
- The `limits` array is the source of truth for model-scoped caps. Legacy `seven_day_sonnet` / `seven_day_opus` fields now return `null`; the `sevenDaySonnet` parsing is dead code and must be removed.
- Responses without a `limits` array, or without any `weekly_scoped` entry, must decode cleanly to nil — no crash, no display, no behavior change of any kind for accounts without Fable access.
- The response also gained a `spend` object and extended `extra_usage` fields (`daily`, `weekly`, `currency`) — explicitly out of scope for this epic; leave unparsed.
- Success criteria: popover shows Fable utilization + reset countdown only when the API reports a scoped weekly limit; Fable history appears in analytics after at least one poll cycle post-migration; notifications fire at 20% and 5% Fable headroom, once per crossing; benchmark can measure `claude-fable-5` end to end.

## Technical Decisions

- **Generic parsing, no hardcoded model names.** Decode `weekly_scoped` entries generically and label the UI with the API's `scope.model.display_name`. Future model-scoped caps must appear without code changes.
- **Additive only.** New optional fields on the response/domain models; new nullable DB columns via an additive schema migration (bump SQLite `user_version`, no destructive changes). Every feature degrades to "not shown" when the scoped limit is absent.
- **Copy existing precedents, no new patterns or services:**
  - Window display: existing 5h/7d bar + countdown components (Epics 3/4).
  - Persistence: Epic 17 extra-usage column precedent — nullable columns on the snapshot table plus rollup aggregates (`cc-hdrm/Services/DatabaseManager.swift`, `cc-hdrm/Services/HistoricalDataService.swift`, `cc-hdrm/Models/UsagePoll.swift`). New columns: `fable_weekly_util REAL`, `fable_weekly_resets_at INTEGER`.
  - Notifications: existing threshold state machines in `cc-hdrm/Services/NotificationService.swift` — fire once per crossing, re-arm on recovery, independent state machine per window, thresholds read hot from `PreferencesManager` (defaults: 20% headroom warning, 5% critical).
  - Benchmark: Epic 20 pipeline is model-agnostic; only add `claude-fable-5` to `defaultModels` in `cc-hdrm/Views/BenchmarkSectionView.swift` and verify the `cc-hdrm/Services/BenchmarkService.swift` request path.
- Parsing entry point: `cc-hdrm/Models/UsageResponse.swift`; scoped-limit data flows through the domain layer to views the same way the existing windows do.

## UX & Interaction Patterns

- Popover: one additional row/gauge in the detailed usage panel, labeled with the API-provided display name, showing utilization plus reset countdown in both relative and absolute form, matching the existing 5h/7d rows. Hidden entirely when no scoped limit is reported.
- Analytics window: one additional series toggle following the existing 5h/7d toggle pattern (toggleable overlay, legend entry, toggle state persisted per time range).
- Notifications must be self-contained: percentage, threshold, and reset countdown in the alert itself, consistent with existing threshold notifications.
- Benchmark UI copy must note that Fable benchmarks consume the Fable cap; the benchmark stays behind the existing opt-in Measure button.
- No new interaction design anywhere — quiet degradation, no placeholder or empty state when Fable is absent.

## Cross-Story Dependencies

- 21.1 → 21.2 → 21.3 → 21.4 are sequential; each builds on the parsed domain data from 21.1.
- 21.5 is fully independent of 21.1–21.4 and can run at any time.
- 21.1 and 21.2 are already merged to master (shipped together); remaining work starts at 21.3.
- Sprint status (`_bmad-output/implementation-artifacts/sprint-status.yaml`) is a shared resource — each story branch updates only its own entry.
