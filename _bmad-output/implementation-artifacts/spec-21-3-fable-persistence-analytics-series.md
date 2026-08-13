---
title: 'Story 21.3: Fable Persistence & Analytics Series'
type: 'feature'
created: '2026-08-13'
status: 'done'
review_loop_iteration: 0
baseline_revision: 'a19b9ea5870216fac792093fddf3fd08073d9cbc'
followup_review_recommended: true
context: []
warnings: [oversized]
deferred:
  - summary: >-
      Multi-statement schema migrations run outside a transaction; a crash
      mid-block can wedge the database permanently on retry
    evidence: |-
      runMigrations() executes each version block's statements without
      BEGIN/COMMIT and writes user_version once at the end. A crash between
      ALTERs (e.g. after 2 of the 5 v8 statements) leaves the version
      unbumped; the next launch re-runs the block, the first duplicate
      ADD COLUMN throws, ensureSchema fails, and historical features stay
      disabled forever. Pre-existing pattern affecting every multi-statement
      migration since v2->v3; surfaced by review of story 21.3, not caused
      by it.
    location: >-
      cc-hdrm/Services/DatabaseManager.swift:141
    severity: medium
---

<intent-contract>

## Intent

**Problem:** Model-scoped weekly caps (e.g. Claude Fable 5) are parsed (21.1) and shown live in the popover (21.2), but never persisted — analytics has no Fable history, so a user cannot see how their Fable window evolved.

**Approach:** Additive schema migration (v7→v8) adding nullable Fable columns to `usage_polls` and rollup aggregates to `usage_rollups`; persist the first `weekly_scoped` entry each poll; analytics window gains a Fable series (step-area line + bars) behind a toggle chip that follows the 5h/7d pattern and is hidden entirely when no Fable data exists.

## Boundaries & Constraints

**Always:**
- The snapshot table is **`usage_polls`** — the epic's `usage_snapshots` name does not exist in this codebase.
- Poll columns: `fable_weekly_util REAL` (0–100, as reported), `fable_weekly_resets_at INTEGER` (Unix **milliseconds**, via `Date.fromISO8601` → `Int64(t*1000)`, same as existing `*_resets_at`). Rollup columns: `fable_weekly_avg REAL`, `fable_weekly_peak REAL`, `fable_weekly_min REAL` (avg/peak/min triple, mirroring 5h/7d — not the extra-usage MAX/SUM pair). `resets_at` is not rolled up (no 5h/7d precedent).
- Additive only: new columns appended at the **end** of both CREATE TABLE literals *and* as a new final `if existingVersion < 8` block in `runMigrations()` — fresh and migrated DBs must have identical `PRAGMA table_info` ordering (rows are read positionally).
- Persist from the raw `UsageResponse` inside `persistPoll` (the persistence Task is off-MainActor; never read `AppState`). Extract the **first** `kind == "weekly_scoped"` entry via a shared helper on `UsageResponse` also adopted by `PollingEngine`'s existing filter, so the two extractions cannot drift.
- Nil-safe end to end: response without `limits` or without a `weekly_scoped` entry → NULL columns, and every aggregation uses `compactMap` (NULL never becomes 0).
- Toggle chip labeled from live `appState.scopedLimits.first?.displayName`, fallback `"Model"` (21.2 precedent); chip rendered only when the loaded chart data contains at least one non-nil Fable value. Toggle state session-only per time range (13-4 precedent — no UserDefaults), toggling must not reload data.
- Fable series color: one new `static let fableColor` (system `.indigo`) beside `sevenDayColor`, re-exported on `BarChartView` — no reuse of extra-usage tokens.
- Accessibility parity with existing chips/tooltips; `xcodegen generate` after adding files.

**Block If:**
- Rendering the Fable bars requires changing the existing 5h/7d bar layout *when the Fable series is hidden or absent* — existing two-series output must stay pixel-identical in that case.
- The migration cannot be expressed as pure `ADD COLUMN` statements.

**Never:**
- No notifications (21.4), no benchmark changes (21.5), no menu bar or popover changes, no tap-to-analytics wiring.
- No parsing of `spend` / extended `extra_usage` fields; no backfill (pre-migration rows stay NULL — no source data exists).
- No persistence of display names; no hardcoded model names in UI labels (DB column names `fable_*` are fixed by the epic).
- Do not touch `cc-hdrm/cc_hdrm.entitlements`, `Sparkline.swift` constants, or retention/prune/outage logic (all column-agnostic).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Poll with Fable cap | `limits` has `weekly_scoped` entry, percent 63, resets_at set | Row stores `fable_weekly_util=63.0`, `fable_weekly_resets_at` in ms | No error |
| Poll without scoped limit | `limits` nil or no `weekly_scoped` entry | Both columns NULL; poll otherwise identical to today | No crash |
| Scoped entry, nil resets_at | percent set, `resets_at` null | util stored, resets_at NULL | No crash |
| v7 DB migrates | Existing DB with data, `user_version=7` | v8: new columns exist, old rows intact with NULL fable values, version=8 | Migration failure leaves version unbumped |
| Fresh install | No DB | v8 schema; column order matches migrated DB | No error |
| Rollup aggregation | Raw polls with fable utils in a 5min/hourly/daily bucket | avg/peak/min computed; bucket with all-NULL fable → NULL aggregates | No crash |
| Reset inside bucket | Rollup bucket split by reset event | Reconstructed `UsageRollup` retains fable fields (the `pollsToRollupsWithResets` trap) | No silent drop |
| Analytics, Fable data present | ≥1 poll/rollup row with non-nil fable util | "Fable" (display-name) chip appears; series renders in step-area + bar modes; tooltip row shown | No error |
| Analytics, no Fable data | All fable columns NULL in range | No chip, no series, charts identical to today | No crash |
| Pre-migration boundary | NULLs before migration date, values after | Series line starts partway through window; gap logic pens up (fable has its own filtered array) | No crash |
| Toggle off | Chip clicked | Series hidden without data reload; state kept per time range for the session | No error |

</intent-contract>

## Code Map

**Persistence:**
- `cc-hdrm/Services/DatabaseManager.swift` — `currentSchemaVersion=7` at :6 → bump to 8; `runMigrations()` :141 (append `< 8` block after :172-style v-blocks; pattern at :150-157); CREATE literals `createUsagePollsTable` :260-282, `createUsageRollupsTable` :284-313 (append columns at end); `executeSQL` :246 is the ALTER helper. No backfill (contrast :473).
- `cc-hdrm/Models/UsagePoll.swift` :18-27 — Epic 17 fields are `var … = nil`; add `fableWeeklyUtil: Double?`, `fableWeeklyResetsAt: Int64?` the same way (keeps ~50 existing constructions compiling).
- `cc-hdrm/Models/UsageRollup.swift` :32-38 — add `fableWeeklyAvg/Peak/Min: Double? = nil` with aggregation doc comments.
- `cc-hdrm/Models/UsageResponse.swift` — add the shared `weekly_scoped` extraction helper (e.g. computed `weeklyScopedEntries`).
- `cc-hdrm/Services/PollingEngine.swift` :240-247 — existing `weekly_scoped` filter; refactor onto the shared helper. Persistence dispatch at :296-340 passes the raw response — no change needed there.
- `cc-hdrm/Services/HistoricalDataService.swift` — `persistPoll` extraction :76-100, INSERT :104-117 + binds :134-188 (add placeholders 11-12, `sqlite3_bind_null` on nil); positional reads: `readPollRow` :422-457 (indices 11-12) and its four SELECT sites :230-237, :290-297, :939-946; rollup tiers `performRawTo5MinRollup` :898-906, `perform5MinToHourlyRollup` :1186-1194, `performHourlyToDailyRollup` :1252-1290 (fable avg/peak/min via `compactMap`, 5h/7d style :890-896); `insertRollup` :1023-1107 (+3 params/SQL/binds); `queryRollupsForRollup` :1318-1404 (SQL + positional 15-17 + `UsageRollup(...)`); `pollToRollup` :1478 (map fable util into avg/peak/min — else last-24h chart shows nothing); **`pollsToRollupsWithResets` :1520-1536 re-constructs `UsageRollup` field-by-field — add fable fields or they're silently dropped in reset buckets**.

**Analytics:**
- `cc-hdrm/Views/AnalyticsView.swift` — `SeriesVisibility` :25-28 (+`fable: Bool = true`), dict :35, accessors/bindings :38-60, `seriesToggles` :475-495 (+chip after 7d, conditional on data presence), `seriesToggleButton` :497 (reuse as-is); `fetchData` :352-424 and `DataLoadResult` :334-340 need no new queries — fable rides the same rows; derive `hasFableData` from loaded polls/rollups. Label via `appState.scopedLimits.first?.displayName ?? "Model"`.
- `cc-hdrm/Views/UsageChart.swift` :8-30 — add `fableVisible` param; `anySeriesVisible` :27; thread into both chart views.
- `cc-hdrm/Views/StepAreaChartView.swift` — `sevenDayColor` :145 (+`fableColor`); filtered arrays :169-172 (+fable points array); `ChartPoint` :293-305 + `makeChartPoints` :316-348 (+fableUtil); gap filter :186 must include fable; **both explicit `ChartPoint(...)` re-constructions :255-267 and :494-506 must carry fable**; `enforceMonotonicWithinSegments` :434-511 (mirror 7d running-max for fable); series namespace `"fable-\(segment)"` (cf. :674/:684); marks in `StaticChartContent`; params threaded through `ChartWithHoverOverlay` :519-534, `StaticChartContent` :626-636, `HoverOverlayContent` :789-798; tooltip row (cf. :928).
- `cc-hdrm/Views/BarChartView.swift` — re-export color :22; `BarPoint` :33-52 (+fable avg/peak/min); `makeBarPoints` :92-173 (fable arm via `compactMap`, style :137-144); **`barBounds(for:series:)` :353-375 + `bothVisible` :341 currently split the period for exactly 2 series — generalize to N visible series**; render marks (cf. :436-464); params :235-241, :332-338, :579-589; tooltip row (cf. :681).

**Tests (patterns):**
- `cc-hdrmTests/Services/DatabaseManagerTests.swift` — migration template :295-381; version literals to bump at :54, :62, :205, :292, :380, :606, :769; column-list tests :385-451.
- `cc-hdrmTests/Services/HistoricalDataServiceTests.swift` — Epic 17 persistence/rollup precedents :1236-1310, :1653-1700; `UsageResponse(...)` built positionally with `limits:` param.
- `cc-hdrmTests/Views/UsageChartTests.swift` — `makeChart` helper :11-31 (add defaulted `fableVisible`), 17.5 data-test template :1125-1262.
- `cc-hdrmTests/Views/AnalyticsViewTests.swift` — toggle suite :269-492 to extend for `fable` field.
- `cc-hdrmTests/Services/PollingEngineTests.swift` :347 — existing `weekly_scoped` test guards the refactored helper.

## Tasks & Acceptance

**Execution:**
- `cc-hdrm/Models/UsageResponse.swift` — add shared `weeklyScopedEntries` helper — single source for the `weekly_scoped` filter.
- `cc-hdrm/Services/PollingEngine.swift` — refactor :240-247 onto the helper — prevents drift with persistence.
- `cc-hdrm/Models/UsagePoll.swift` + `cc-hdrm/Models/UsageRollup.swift` — add optional fable fields with `= nil` defaults — source-compatible model extension.
- `cc-hdrm/Services/DatabaseManager.swift` — bump schema to 8, add migration block + CREATE-literal columns — additive migration for both upgrade and fresh-install paths.
- `cc-hdrm/Services/HistoricalDataService.swift` — extend INSERT/binds, all four positional SELECT sites + `readPollRow`, three rollup tiers, `insertRollup`, `queryRollupsForRollup`, `pollToRollup`, `pollsToRollupsWithResets` — full write/read/aggregate path for the new columns.
- `cc-hdrm/Views/AnalyticsView.swift` — `fable` visibility flag + conditional chip labeled from `scopedLimits` — toggle UX per 13-4 pattern.
- `cc-hdrm/Views/UsageChart.swift`, `cc-hdrm/Views/StepAreaChartView.swift`, `cc-hdrm/Views/BarChartView.swift` — thread `fableVisible`, add fable series (points array, gap filter, monotonic clamp, marks, generalized bar bounds, tooltip rows, `fableColor`) — renders the series in both chart modes.
- `cc-hdrmTests/Services/DatabaseManagerTests.swift` — v7→v8 migration test (template :295-381), column-list updates, version-literal bumps — locks the migration.
- `cc-hdrmTests/Services/HistoricalDataServiceTests.swift` — persist present/nil, round-trip via `getLastPoll`, tier aggregation avg/peak/min, `pollToRollup` passthrough, reset-bucket reconstruction — covers the I/O matrix persistence rows.
- `cc-hdrmTests/Views/UsageChartTests.swift` + `cc-hdrmTests/Views/AnalyticsViewTests.swift` — fable series rendering/visibility/gap tests; toggle-state tests incl. chip hidden when no data — covers the analytics matrix rows.
- Run `xcodegen generate` if any new file is added — project regeneration.

**Acceptance Criteria:**
- Given a poll whose API response reports a `weekly_scoped` limit, when the analytics window opens after that poll persists, then the chart offers a series chip labeled with the API display name and renders the Fable series in both `.day` (step-area) and rollup (bar) modes.
- Given an account whose polls never report a scoped limit, when analytics opens on any time range, then no Fable chip or series appears and the window is visually unchanged from today.
- Given a database created at schema v7 with existing history, when the app launches with this change, then `user_version` becomes 8, prior rows survive with NULL fable columns, and new polls populate them.
- Given the Fable chip is toggled off and the time range is switched away and back, when the session continues, then the off state is remembered per range without any data reload.

## Spec Change Log

## Review Triage Log

### 2026-08-13 — Review pass
- intent_gap: 0
- bad_spec: 0
- patch: 9: (high 0, medium 3, low 6)
- defer: 1: (high 0, medium 1, low 0)
- reject: 14: (high 0, medium 0, low 14)
- addressed_findings:
  - `[medium]` `[patch]` Fable aggregation in 5min→hourly and hourly→daily rollup tiers had zero test coverage (deleting the arms passed the suite) — added `fableAggregationAcrossHigherRollupTiers` driving 8-day and 31-day-old data through consolidation, asserting avg/peak/min and NULL passthrough at both tiers.
  - `[medium]` `[patch]` Generalized N-slot `barBounds` math was covered only by a no-assertion render smoke test despite the Block-If pixel-parity requirement — extracted static `slotBounds(index:count:duration:)` and added tests asserting exact equality with the legacy 1- and 2-series formulas plus 3-series non-overlap.
  - `[medium]` `[patch]` Epic success criterion "Fable history appears in analytics after ≥1 poll cycle" was covered only as disconnected units — added `fableHistoryAppearsAfterOnePollCycle`: real service + temp DB, `persistPoll` → `AnalyticsView.fetchData` → fable util present and `hasFableData` true.
  - `[low]` `[patch]` Dead `guard let percent` in PollingEngine compactMap (helper already filters nil percent) — simplified via `entry.percent.map`.
  - `[low]` `[patch]` Whitespace-only hunk in `createIndex` SQL literal — restored original trailing space; unrelated hunk removed from diff.
  - `[low]` `[patch]` Circular test assertion (expected resets-at computed with the same `Date.fromISO8601` as production) — hard-coded epoch-ms constants for the fixed ISO fixtures.
  - `[low]` `[patch]` Empty-string `displayName` rendered a blank chip/tooltip label — `fableLabel(from:)` now falls back for nil/empty/blank, reusing 21.2's `ScopedLimitGaugeSection.fallbackLabel`; test covers all cases.
  - `[low]` `[patch]` Fable clause in `findGapRanges` was unpinned (reverting it failed no test) — added `fableOnlyPollsDriveGapDetection` with fable-only polls asserting no-gap and one-gap cases.
  - `[low]` `[patch]` `sprint-status.yaml` not updated for this story — own entry set to done at finalization per shared-resource convention.

Deferred (pre-existing, not this story): multi-statement migrations run outside a transaction — a crash mid-block wedges the DB permanently on retry (duplicate ADD COLUMN); affects every migration since v2→v3.

Rejected findings (noise, dropped): `hasFableData` recompute cost (body does not re-evaluate on hover; O(n) contains a few times per poll); no persisted model identity / historical-label provenance (intent decrees exactly two singular `fable_*` columns; future scoped model needs its own schema story — recorded in Design Notes); toggle-reload test for fable (mechanism shared with 5h/7d, already pinned by the 13-4 test); `weekly_scoped` entry with resetsAt but nil percent dropped (21.1's pre-existing semantics, unchanged by the helper); `createV7Schema` hand-duplication (matches the established migration-test template; drift is caught by the fresh-vs-migrated column-order parity test); `fable_weekly_resets_at` has no consumer/rollup (intent-decreed column; matches 5h/7d precedent of never rolling up resets_at, stated in spec); unweighted avg-of-avgs + helper consolidation (mirrors existing 5h/7d behavior by design; no new abstraction warranted); `?? 0` on pre-filtered fablePoints (exact parity with existing 7d pattern); percent clamping for negative/NaN/>100 (spec directs as-reported storage; NaN unreachable — JSONDecoder rejects non-finite; matches 5h/7d unclamped storage); weekly reset below 10-point drop threshold clamped away (spec-directed parity with the shared heuristic); toggle chip binding not exercised at UI surface (SwiftUI limitation; same dictionary-shape testing as the established 13-4 suite); Reading-B aggregate shape (avg/peak/min chosen and justified in Design Notes; Epic 17 reference governs migration mechanics); monotonic clamp and N-slot generalization as un-asked-for extras (both required for correct rendering parity of a third utilization series).

## Design Notes

- **Why avg/peak/min, not MAX/SUM:** Fable weekly util is the same shape as 5h/7d utilization; the extra-usage MAX/SUM pair exists for monotonic credit counters. Copy the util precedent.
- **Why first `weekly_scoped` entry:** columns are singular by epic decree; the API currently reports one scoped cap, and API order is already the display order (21.2). A future second scoped model needs its own schema story.
- **Why `.indigo`:** 7d uses plain `Color.blue` (no asset); a new asset for one hue is overhead, and both extra-usage purples carry spend-tier semantics.

## Verification

**Commands:**
- `xcodegen generate` — expected: succeeds (only needed if new files are added)
- `xcodebuild -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= build` — expected: BUILD SUCCEEDED
- `xcodebuild -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test` — expected: all tests pass (known flake: `TPPChartDataServiceTests/dailyAverage()` within 4h of local midnight — pre-existing, unrelated)

## Auto Run Result

**Status:** done

**Summary:** Fable model-scoped weekly cap data is now persisted and charted. Schema v7→v8 adds `fable_weekly_util`/`fable_weekly_resets_at` to `usage_polls` and `fable_weekly_avg/peak/min` to `usage_rollups` (pure additive `ADD COLUMN`, identical column order for fresh and migrated databases). Every poll stores the first `weekly_scoped` entry from the API response via a shared `weeklyScopedEntries` helper also used by the live popover path. The analytics window gains a Fable series — indigo line in the 24h step-area chart, indigo bars in rollup ranges — behind a toggle chip labeled with the API display name ("Model" fallback), shown only when loaded data contains Fable values. Accounts without Fable access see zero change anywhere.

**Files changed:**
- `cc-hdrm/Models/UsageResponse.swift` — shared `weeklyScopedEntries` filter helper.
- `cc-hdrm/Models/UsagePoll.swift` / `cc-hdrm/Models/UsageRollup.swift` — optional fable fields with `= nil` defaults.
- `cc-hdrm/Services/DatabaseManager.swift` — schema version 8, v7→v8 migration block, CREATE-literal columns.
- `cc-hdrm/Services/HistoricalDataService.swift` — INSERT/binds, four positional SELECT sites + `readPollRow`, three rollup tiers, `insertRollup`, `queryRollupsForRollup`, `pollToRollup`, reset-bucket reconstruction.
- `cc-hdrm/Services/PollingEngine.swift` — refactored onto the shared helper.
- `cc-hdrm/Views/AnalyticsView.swift` — `fable` visibility flag per time range, conditional chip, `hasFableData` / `fableLabel(from:)` statics.
- `cc-hdrm/Views/UsageChart.swift` / `StepAreaChartView.swift` / `BarChartView.swift` — `fableVisible`/`fableLabel` threading, fable points array + gap filter + independent monotonic clamp, `fableColor` (indigo), N-series `slotBounds` generalization, hover/tooltip rows.
- Tests: `DatabaseManagerTests` (v7→v8 migration, column order parity, version bumps), `HistoricalDataServiceTests` (persist/round-trip/tier aggregation incl. hourly+daily), `UsageChartTests` (chart points, gaps, monotonic, slot bounds, bar aggregation), `AnalyticsViewTests` (toggles, chip gating, label fallback, poll-to-chart integration), `OutageTrackingTests` (version literal bumps).

**Review findings:** 9 patched (3 medium, 6 low — see Review Triage Log), 1 deferred (pre-existing non-transactional migration risk), 14 rejected as noise. No intent gaps, no spec repairs.

**Follow-up review recommendation:** true — patched counts: high 0, medium 3, low 6; score = 3×3 + 1×6 = 15 (threshold 5).

**Verification:**
- `xcodebuild ... build` — BUILD SUCCEEDED (post-implementation and post-patch).
- `xcodebuild ... test` — TEST SUCCEEDED: 1520 tests in 129 suites, 0 failures (1514 pre-patch; 6 tests added by review patches).
- Matrix test audit: every I/O matrix row covered by a test that ran and passed.
- No new files added — `xcodegen generate` not required.

**Residual risks:**
- Migration blocks are non-transactional (deferred finding): a crash mid-v8-block would wedge historical features on retry — same exposure as every prior migration.
- Historical Fable data viewed with no live scoped limit is labeled with the generic "Model" fallback, since display names are deliberately not persisted.
- `fable_weekly_resets_at` currently has no consumer and is not rolled up; reset history ages out with raw-poll retention (7 days). Story 21.4 uses live data, so this matches the 5h/7d precedent.
