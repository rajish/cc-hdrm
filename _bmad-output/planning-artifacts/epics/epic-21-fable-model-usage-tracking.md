# Epic 21: Fable Model Usage Tracking (Phase 6)

**Origin:** Sprint change proposal 2026-08-12 (`_bmad-output/planning-artifacts/sprint-change-proposal-2026-08-12-fable.md`)

## Goal

Claude Fable 5 has a model-scoped weekly cap (50% of the weekly limit on Max
plans) that cc-hdrm cannot see. A user can hit the Fable wall while the app
reports healthy overall headroom (observed live: Fable 63% vs weekly 67%).
Parse the usage API's new `limits` array, surface the Fable window everywhere
the existing windows appear, and keep it out of the way for accounts without
Fable access.

## API Evidence (live capture 2026-08-12)

The `/api/oauth/usage` response gained a `limits` array. The Fable cap:

```json
{
  "kind": "weekly_scoped",
  "group": "weekly",
  "percent": 63,
  "severity": "normal",
  "resets_at": "2026-08-12T22:00:00.059415+00:00",
  "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
  "is_active": false
}
```

Legacy `seven_day_sonnet` / `seven_day_opus` fields now return `null` —
the `limits` array is the source of truth for model-scoped caps.

## Design Principles

- **Generic parsing, no hardcoded model names.** Decode `weekly_scoped`
  entries and label the UI with the API's `scope.model.display_name`. Future
  model-scoped caps appear without code changes.
- **Additive only.** New optional fields, new nullable DB columns. Absent
  scoped limit → nothing shown, no behavior change.
- **Copy existing patterns.** Window display (Epic 3/4), persistence
  (Epic 10/17), notifications (Epic 5), benchmark (Epic 20).

## Stories

### Story 21.1: Scoped Limits Parsing & Domain Model

Decode the `limits` array in `cc-hdrm/Models/UsageResponse.swift` (`kind`,
`group`, `percent`, `severity`, `resets_at`, `is_active`,
`scope.model.display_name`). Surface `weekly_scoped` entries through the
domain layer to consumers. Remove the dead `sevenDaySonnet` field.
**AC:** Fable percent + reset time available to views; response without
`limits` (or without scoped entries) decodes cleanly to nil — no crash, no
display.

### Story 21.2: Popover Fable Utilization Display

Add a scoped-limit row/gauge to the detailed usage panel, labeled with the
API's `display_name`, with reset countdown (relative + absolute, matching
existing windows). Hidden when no scoped limit is reported.

### Story 21.3: Persistence & Analytics Series

Additive schema migration: `fable_weekly_util REAL`,
`fable_weekly_resets_at INTEGER` on `usage_snapshots` plus rollup
aggregates, following the Epic 17 extra-usage column precedent
(`cc-hdrm/Services/DatabaseManager.swift`,
`cc-hdrm/Services/HistoricalDataService.swift`,
`cc-hdrm/Models/UsagePoll.swift`). Analytics window gains a Fable series
toggle.

### Story 21.4: Fable Threshold Notifications

20%/5% headroom notifications for the scoped window via
`cc-hdrm/Services/NotificationService.swift`. Independent dedup per window
(fire once per crossing), respecting existing threshold preferences.

### Story 21.5: Benchmark Default Model Update

Add `claude-fable-5` to `defaultModels` in
`cc-hdrm/Views/BenchmarkSectionView.swift`. Verify the
`cc-hdrm/Services/BenchmarkService.swift` request path works with the Fable
model ID. UI copy notes that Fable benchmarks consume the Fable cap
(benchmark stays behind the opt-in Measure button). Independent of 21.1–21.4.

## Sequencing

21.1 → 21.2 → 21.3 → 21.4 (each builds on the parsed domain data).
21.5 is independent, can run any time.

## Success Criteria

- Popover shows Fable utilization + reset countdown when the API reports a
  scoped weekly limit; shows nothing when it doesn't.
- Fable history appears in analytics after ≥1 poll cycle post-migration.
- Notifications fire at 20% and 5% Fable headroom, once per crossing.
- Benchmark can measure `claude-fable-5` end to end.
- No behavior change for accounts without Fable access.
