# Sprint Change Proposal — Fable Model Usage Tracking

**Date:** 2026-08-12
**Author:** Correct Course workflow (SM)
**Status:** Approved 2026-08-12
**Change scope classification:** Minor–Moderate (new epic, no rework of existing stories)

---

## 1. Issue Summary

**Anthropic released Claude Fable 5 and cc-hdrm cannot see it.** Fable usage is
tracked against a separate model-scoped weekly cap (50% of the weekly limit on
Max plans). cc-hdrm shows only the 5h and 7d overall windows, so a user can hit
the Fable wall with the app reporting healthy headroom.

**Discovery context:** User request, 2026-08-12. Not triggered by a story —
all epics (1–20) are done. Category: new requirement from a market change.

**Evidence (live `/api/oauth/usage` capture, 2026-08-12, this account):**

- The API response gained a new `limits` array. The Fable cap appears as:

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

- This account showed **Fable at 63%** while the overall weekly window was at
  67% — the two run independently. The gap is invisible in today's UI.
- The legacy model windows (`seven_day_sonnet`, `seven_day_opus`) are now
  `null` — model-scoped tracking has moved to the `limits` array. The
  `sevenDaySonnet` field parsed in `cc-hdrm/Models/UsageResponse.swift` is dead.
- The response also gained a `spend` object (usage credits) and extra fields on
  `extra_usage` (`daily`, `weekly`, `currency`). Out of scope here, but the PRD
  API documentation must record them.
- Plan structure (Anthropic help center): Max plans — Fable capped at 50% of
  the weekly allowance, shared pool. Pro plans — Fable runs on pay-as-you-go
  usage credits.

---

## 2. Impact Analysis

### Epic impact

- **No in-flight work.** Epics 1–20 are all `done` in sprint-status.yaml.
  Nothing is invalidated, blocked, or resequenced.
- **New epic needed: Epic 21 — Fable Model Usage Tracking (Phase 6).**
  Mirrors the shape of Epic 17 (Extra Usage): state → popover → analytics →
  alerts.
- **Epic 20 (TPP) needs no rework.** The TPP pipeline is model-agnostic —
  Fable tokens from Claude Code session logs already flow through
  `ClaudeCodeLogParser` → `PassiveTPPEngine` keyed by model string. Only the
  benchmark default model list needs a one-line update.

### Artifact conflicts

| Artifact | Impact |
|---|---|
| PRD (`prd.md`) | API response section is stale (no `limits`, no `spend`, legacy model windows now null). Phase 4 future item "Sonnet-specific usage breakdown" is superseded. |
| Epic list (`epics/epic-list.md`) | Needs Epic 21 entry. |
| Architecture (`architecture.md`) | Data model addition: `limits` parsing, one SQLite schema migration (2 columns). No component or pattern changes. |
| UX spec | Popover gains one Fable utilization row; analytics gains one series toggle. Follows existing patterns — no new interaction design. |
| sprint-status.yaml | Add epic-21 + 5 story entries as `backlog` after approval. |

### Technical impact

- `cc-hdrm/Models/UsageResponse.swift` — add `limits` array decoding; remove
  dead `sevenDaySonnet`.
- `cc-hdrm/Models/UsagePoll.swift`, `Services/DatabaseManager.swift`,
  `Services/HistoricalDataService.swift` — persist Fable weekly utilization +
  reset time (schema migration, additive columns only).
- `Views/` popover + analytics — display work, existing component patterns.
- `Services/NotificationService.swift` — threshold checks for the scoped
  window, same 20%/5% model as existing windows.
- `Views/BenchmarkSectionView.swift:33` — add `claude-fable-5` to
  `defaultModels`.

---

## 3. Recommended Approach

**Direct Adjustment — add Epic 21 with 5 stories.** (Option 1)

- **Rollback:** Not applicable — nothing to revert.
- **MVP review:** Not applicable — MVP shipped; this is post-MVP scope.

**Rationale:** The change is purely additive. The API already serves the data;
the app's window-display, persistence, notification, and benchmark patterns
all have precedents (Epics 3, 5, 10, 17, 20) to copy. Parsing the `limits`
array generically (keyed by `scope.model.display_name` from the API, no
hardcoded model names) means future model-scoped caps appear without code
changes.

- **Effort:** Low–Medium (5 small stories, one additive schema migration)
- **Risk:** Low (additive; every feature degrades to "not shown" when the
  scoped limit is absent from the response)
- **Timeline impact:** None on existing work.

---

## 4. Detailed Change Proposals

### 4.1 PRD — API response documentation

**Section:** Claude API response example + field notes

**OLD:** JSON example with `five_hour`, `seven_day`, `seven_day_sonnet`,
`extra_usage`; note listing `seven_day_oauth_apps`, `seven_day_opus`,
`seven_day_cowork` as additional nullable fields.

**NEW:** Updated 2026-08 example including the `limits` array (kinds:
`session`, `weekly_all`, `weekly_scoped` with `scope.model.display_name`),
the `spend` object, and extended `extra_usage` fields. Note that legacy
`seven_day_<model>` windows now return `null` and are superseded by
`weekly_scoped` limits entries.

**Rationale:** PRD is the API reference for future stories; it currently
documents a response shape the API no longer returns.

### 4.2 PRD — Phase 4 future list

**OLD:** `- Sonnet-specific usage breakdown (API returns seven_day_sonnet data)`

**NEW:** `- ~~Sonnet-specific usage breakdown~~ — Superseded by Epic 21
model-scoped limit tracking (API moved per-model windows to the limits array)`

### 4.3 Epic list — new Epic 21 entry

**NEW (append to `epics/epic-list.md`):**

> ## Epic 21: Fable Model Usage Tracking (Phase 6)
>
> Alex uses Fable 5 for the hard problems — and it has its own weekly cap,
> invisible until now. cc-hdrm parses the API's model-scoped limits, shows a
> Fable utilization row in the popover, persists the history, charts it in
> analytics, and fires the same 20%/5% headroom alerts Alex already trusts.
> The TPP benchmark learns Fable's token economics too.
> **Stories:** 21.1 Scoped-limits parsing, 21.2 Popover display, 21.3
> Persistence + analytics series, 21.4 Threshold notifications, 21.5
> Benchmark default model update

### 4.4 New epic document — `epics/epic-21-fable-model-usage-tracking.md`

Created via `/bmad-bmm-create-story` per story; epic doc summarizes:

- **Story 21.1 — Scoped limits parsing & domain model.**
  Decode the `limits` array in `cc-hdrm/Models/UsageResponse.swift`
  (generic: `kind`, `group`, `percent`, `severity`, `resets_at`,
  `scope.model.display_name`, `is_active`). Surface `weekly_scoped` entries
  in the domain layer. Remove dead `sevenDaySonnet`. AC: Fable percent +
  reset time available to views; absent limits → nil, no crash.
- **Story 21.2 — Popover Fable utilization display.**
  Row/gauge in the detailed panel showing scoped-limit utilization, labeled
  with the API's `display_name`, with reset countdown. Hidden when absent.
- **Story 21.3 — Persistence & analytics series.**
  Additive migration: `fable_weekly_util REAL`, `fable_weekly_resets_at
  INTEGER` on `usage_snapshots` (+ rollup aggregates), following the Epic 17
  extra-usage column precedent. Analytics window gains a Fable series toggle.
- **Story 21.4 — Fable threshold notifications.**
  20%/5% headroom notifications for the scoped window via
  `Services/NotificationService.swift`, independent dedup per window,
  respecting existing threshold preferences.
- **Story 21.5 — Benchmark default model update.**
  Add `claude-fable-5` to `defaultModels` in
  `Views/BenchmarkSectionView.swift`. Verify `BenchmarkService` request path
  works with the Fable model ID. Note in UI copy that Fable benchmarks burn
  the Fable cap (user opted in knowingly — benchmark remains opt-in Measure
  button).

### 4.5 Architecture — data model note

Add to the data model section: `limits` array parsing (generic scoped-limit
struct), schema migration bumping user_version, additive columns only.
No new services, no new patterns.

### 4.6 sprint-status.yaml

**NEW (after approval):**

```yaml
  epic-21: backlog  # Fable Model Usage Tracking (Phase 6) — Sprint change proposal 2026-08-12
  21-1-scoped-limits-parsing-domain-model: backlog
  21-2-popover-fable-utilization-display: backlog
  21-3-fable-persistence-analytics-series: backlog
  21-4-fable-threshold-notifications: backlog
  21-5-benchmark-default-model-update: backlog
```

---

## 5. Implementation Handoff

- **Scope classification: Minor** — direct implementation by the dev team via
  the standard BMAD story lifecycle. No backlog reorganization, no replan.
- **Handoff:** SM runs `/bmad-bmm-create-story` for 21.1 → dev-story →
  code-review → PR → merge, then repeats. Stories 21.1 → 21.2 → 21.3 → 21.4
  are sequential (each builds on the parsed domain data); 21.5 is independent
  and can run any time.
- **Success criteria:**
  - Popover shows Fable utilization + reset countdown when the API reports a
    scoped weekly limit; shows nothing when it doesn't.
  - Fable history appears in analytics after ≥1 poll cycle post-migration.
  - Notifications fire at 20% and 5% Fable headroom, once per crossing.
  - Benchmark can measure `claude-fable-5` end to end.
  - No behavior change for accounts without Fable access.
