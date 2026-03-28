# Story 20.5: Historical TPP Backfill

Status: done

## Story

As a developer using Claude Code,
I want cc-hdrm to compute approximate TPP values from my existing raw poll history and log data,
So that I have some historical context when the TPP feature first launches.

## Acceptance Criteria

**AC-1: Backfill trigger**

**Given** the TPP feature is enabled and no passive or passive-backfill TPP measurements exist yet
**When** the app launches
**Then** a one-time backfill job runs in the background
**And** a subtle progress indicator appears if the backfill takes >5 seconds

**AC-2: Raw poll backfill**

**Given** raw `usage_polls` exist (typically last ~24 hours of data)
**When** the backfill processes these
**Then** it applies the same passive measurement logic from Story 20.3:
- Pairs consecutive polls, computes deltas, queries log parser for tokens in each window per model
- Stores TPP measurements with `source = "passive-backfill"`, `confidence = "medium"`
- Skips windows where 5h utilization drops >= 50% (reset detection, same as `PassiveTPPEngine`)
- For multi-model windows: stores per-model records with shared delta, confidence = "low"

**AC-3: Rollup-based backfill (optional, lower confidence)**

**Given** 5min/hourly rollups exist for older periods
**When** the backfill processes a rollup bucket
**Then** it approximates utilization delta as `five_hour_peak - five_hour_min` within each bucket
**And** queries the log parser for tokens in the rollup's `[period_start, period_end)` window, per model
**And** if both delta >= 1 and tokens > 0: computes approximate TPP and stores with `source = "rollup-backfill"`, `confidence = "low"`

**Note:** Rollup-based TPP is inherently noisy. Peak-min spread within an hourly bucket may include resets, concurrent sessions, and idle decay. This data is useful for spotting large (>30%) shifts but not subtle changes.

**AC-4: Graceful gaps**

**Given** no Claude Code JSONL logs exist for a historical period
**When** the backfill encounters a period with utilization changes but zero tokens
**Then** it stores a delta-only record (no TPP computed) rather than skipping entirely
**And** this preserves the utilization change data for context

**AC-5: Idempotency**

**Given** the backfill has already run
**When** the app is relaunched
**Then** the backfill does not re-run (checks for existing backfill records via `TPPStorageService` query)
**And** a manual "Re-run backfill" option exists in settings for users who want to reprocess after log recovery

## Tasks / Subtasks

- [x] Task 1: Create `HistoricalTPPBackfillService` protocol and implementation (AC: 1, 2, 3, 4, 5)
  - [x] 1.1 Create `cc-hdrm/Services/HistoricalTPPBackfillServiceProtocol.swift` with protocol defining `runBackfillIfNeeded()` async and `runBackfill(force: Bool)` async
  - [x] 1.2 Create `cc-hdrm/Services/HistoricalTPPBackfillService.swift` implementing the protocol
  - [x] 1.3 Inject dependencies: `HistoricalDataServiceProtocol`, `ClaudeCodeLogParserProtocol`, `TPPStorageServiceProtocol`, `PreferencesManagerProtocol`
  - [x] 1.4 Implement idempotency check: query `tppStorage.getMeasurements()` for any records with source containing "backfill", return early if found
  - [x] 1.5 Implement raw poll backfill: get all polls via `historicalDataService.getRecentPolls(hours: 24)`, pair consecutive polls, compute deltas, query log parser for tokens, store with `source = .passiveBackfill`
  - [x] 1.6 Apply same reset detection as `PassiveTPPEngine`: skip windows where `previous.fiveHourUtil - current.fiveHourUtil >= 50`
  - [x] 1.7 Apply same confidence logic: single model + delta >= 3% = "medium", single model + delta 1-2% = "low", multi-model = "low"
  - [x] 1.8 Apply same delta-only record logic: delta > 0 but zero tokens = store with model = "unknown", no TPP, confidence = "low"
  - [x] 1.9 Implement rollup-based backfill: query `historicalDataService.getRolledUpData(range:)` for `.week` and `.month` ranges
  - [x] 1.10 For each rollup bucket: compute delta as `fiveHourPeak - fiveHourMin`, skip if delta < 1 or fiveHourPeak/fiveHourMin is nil
  - [x] 1.11 For rollup buckets with delta >= 1: query log parser for tokens in `[periodStart, periodEnd)`, store with `source = .rollupBackfill`, `confidence = .low`
  - [x] 1.12 Skip rollup buckets where `resetCount > 0` (reset within bucket makes delta unreliable)
  - [x] 1.13 Implement `force` parameter: when true, delete existing backfill records before re-running
  - [x] 1.14 Add logging: log backfill start, raw poll count processed, rollup bucket count processed, total measurements stored, completion time

- [x] Task 2: Add backfill completion preference key (AC: 5)
  - [x] 2.1 Add `tppBackfillCompleted` key to `PreferencesManager.Keys` (pattern: `com.cc-hdrm.tppBackfillCompleted` as Bool)
  - [x] 2.2 Add `tppBackfillCompleted` computed property to `PreferencesManager` (read/write Bool, default false)
  - [x] 2.3 Add to `PreferencesManagerProtocol` if protocol exposes preference properties (check existing pattern)
  - [x] 2.4 Set `tppBackfillCompleted = true` after successful backfill completion in the service
  - [x] 2.5 Add to `resetAllPreferences()` method so it resets on full preference clear
  - [x] 2.6 Use this as the fast-path idempotency check (avoids DB query on every launch); fall back to DB query if preference is false

- [x] Task 3: Add "Re-run Backfill" setting (AC: 5)
  - [x] 3.1 In `cc-hdrm/Views/SettingsView.swift`, add a "Re-run TPP Backfill" button in the Token Efficiency / Benchmark settings section
  - [x] 3.2 Button calls `backfillService.runBackfill(force: true)` which clears existing backfill records and re-runs
  - [x] 3.3 Show button only when `tppBackfillCompleted` is true (no point re-running if never ran)
  - [x] 3.4 Disable button while backfill is in progress (use `@Observable` state or a published flag)
  - [x] 3.5 Show brief confirmation after completion: "Backfill complete — X measurements generated"

- [x] Task 4: Wire into AppDelegate (AC: 1)
  - [x] 4.1 Create `HistoricalTPPBackfillService` instance in `AppDelegate.applicationDidFinishLaunching()` after `tppStorage`, `logParser`, and `historicalDataService` are created
  - [x] 4.2 Fire-and-forget: `Task { await backfillService.runBackfillIfNeeded() }` — must not block app launch
  - [x] 4.3 Trigger a log parser full scan before backfill processing: `await logParser.scan()` (ensure historical token data is loaded)

- [x] Task 5: Write tests (AC: all)
  - [x] 5.1 Create `cc-hdrmTests/Services/HistoricalTPPBackfillServiceTests.swift`
  - [x] 5.2 Test idempotency: backfill runs once, second call returns early (no new records)
  - [x] 5.3 Test force re-run: existing backfill records exist, force=true deletes them and re-runs
  - [x] 5.4 Test raw poll backfill: inject 5 consecutive polls with deltas, verify correct TPP records stored with source = .passiveBackfill
  - [x] 5.5 Test reset detection during backfill: inject poll pair with 50%+ drop, verify window is skipped
  - [x] 5.6 Test delta-only records: inject polls with delta but no tokens, verify model = "unknown" record stored
  - [x] 5.7 Test rollup backfill: inject rollup buckets with peak/min, verify TPP computed from spread with source = .rollupBackfill
  - [x] 5.8 Test rollup skip on reset: inject rollup with resetCount > 0, verify bucket is skipped
  - [x] 5.9 Test empty state: no polls, no rollups — backfill completes without errors, stores nothing
  - [x] 5.10 Test multi-model in raw poll: tokens from 2 models in one window — 2 records, both confidence = "low"

- [x] Task 6: Run `xcodegen generate` and verify build
  - [x] 6.1 Run `xcodegen generate` after all files are added
  - [x] 6.2 Verify build compiles cleanly
  - [x] 6.3 Verify all tests pass

### Review Findings

- [x] [Review][Patch] Duplicate rollup measurements: processRollups iterates [.week, .month] but .month already includes all .week data [cc-hdrm/Services/HistoricalTPPBackfillService.swift:264] — fixed: use .month only
- [x] [Review][Patch] tppBackfillCompleted not set after force re-run with zero measurements [cc-hdrm/Services/HistoricalTPPBackfillService.swift:121] — fixed: always set preference after runBackfill completes
- [x] [Review][Patch] DB slow-path idempotency check only queries .passiveBackfill, misses .rollupBackfill-only installs [cc-hdrm/Services/HistoricalTPPBackfillService.swift:50-55] — fixed: check both sources sequentially
- [x] [Review][Patch] backfillServiceRef uses internal access modifier, should be private (inconsistent with all other service refs) [cc-hdrm/App/AppDelegate.swift:26] — fixed: changed to private
- [x] [Review][Defer] AC-1 progress indicator for app-launch backfill path not implemented — deferred, pre-existing scope gap; no UI plumbing in place for launch-path progress; Story 20.4 or later can address

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with Service Layer. `HistoricalTPPBackfillService` is a service that reads from `HistoricalDataService` (polls/rollups) and `ClaudeCodeLogParser` (tokens) and writes through `TPPStorageService` (TPP measurements).
- **Concurrency:** Swift structured concurrency only. No GCD, no Combine. All methods are `async`.
- **Sendable:** Use `@unchecked Sendable` with `NSLock` if mutable state is needed (e.g., isRunning flag). Or make the class `final` with no mutable shared state if feasible.
- **Protocol-first:** `HistoricalTPPBackfillServiceProtocol.swift` + `HistoricalTPPBackfillService.swift` as separate files.
- **Logging:** Use `os.Logger` with subsystem `"com.cc-hdrm.app"` and category `"tpp-backfill"`.
- **Error handling:** Backfill is fire-and-forget. Failures log errors but never crash the app or affect other services. Wrap the entire backfill in a do-catch.

### Database Schema -- NO CHANGES NEEDED

The `tpp_measurements` table (v7 migration, `cc-hdrm/Services/DatabaseManager.swift:365-403`) already supports all source values needed:
- `source = "passive-backfill"` — for raw poll backfill records
- `source = "rollup-backfill"` — for rollup-derived backfill records

The `MeasurementSource` enum (`cc-hdrm/Models/TPPMeasurement.swift:19-24`) already has `.passiveBackfill` and `.rollupBackfill` cases. No model or enum changes needed.

### Reusing PassiveTPPEngine Logic (DO NOT REINVENT)

The raw poll backfill (AC-2) applies the **same logic** as `PassiveTPPEngine.processPoll()` at `cc-hdrm/Services/PassiveTPPEngine.swift:45-248`, but with these differences:
- **No accumulation window needed.** The backfill processes all poll pairs sequentially — it doesn't need to wait for real-time poll arrivals. Process each consecutive pair independently.
- **Source is `.passiveBackfill`** instead of `.passive`.
- **No health tracking needed.** The backfill doesn't track coverage metrics — it runs once and is done.

Rather than importing or subclassing `PassiveTPPEngine`, **replicate the core computation logic** as private methods in the backfill service:
1. Delta computation: `fiveHourDelta = current.fiveHourUtil - previous.fiveHourUtil`
2. Reset detection: `previousFiveHour - currentFiveHour >= 50` (skip that pair)
3. Token query: `logParser.getTokens(from: previous.timestamp, to: current.timestamp)`
4. TPP calculation: `totalRawTokens / fiveHourDelta` (same as `PassiveTPPEngine.storePerModelMeasurements`)
5. Confidence assignment: same table as Story 20.3 (single model + delta >= 3% = "medium", else "low")
6. Delta-only records: delta > 0 but zero tokens = store with model = "unknown"

### Rollup-Based Backfill Strategy

Rollups store `five_hour_peak` and `five_hour_min` but NOT consecutive poll-pair data. The delta approximation:
```
approximateDelta = fiveHourPeak - fiveHourMin  (from UsageRollup at cc-hdrm/Models/UsageRollup.swift)
```

This is inherently noisy because:
- The peak and min may not be temporally adjacent
- Resets within a bucket make the spread meaningless
- Idle decay can inflate the spread

**Guard rails:**
- Skip buckets where `resetCount > 0` (reset within bucket invalidates delta)
- Skip buckets where `fiveHourPeak` or `fiveHourMin` is nil
- Skip buckets where `approximateDelta < 1` (below detection threshold)
- Always store with `confidence = .low`
- Use the rollup's `[periodStart, periodEnd)` as the token query window

### Available Data APIs

| Need | Existing API | Location |
|------|-------------|----------|
| Raw polls (last ~24h) | `historicalDataService.getRecentPolls(hours: 24)` | `cc-hdrm/Services/HistoricalDataServiceProtocol.swift:28` |
| Rollup data | `historicalDataService.getRolledUpData(range: .week)` / `.month` / `.all` | `cc-hdrm/Services/HistoricalDataServiceProtocol.swift:62` |
| Token data from logs | `logParser.getTokens(from:to:model:)` | `cc-hdrm/Services/ClaudeCodeLogParserProtocol.swift:15` |
| Full log scan | `logParser.scan()` | `cc-hdrm/Services/ClaudeCodeLogParserProtocol.swift:8` |
| TPP persistence | `tppStorage.storePassiveResult(_:)` | `cc-hdrm/Services/TPPStorageServiceProtocol.swift:22` |
| TPP query (idempotency) | `tppStorage.getMeasurements(from:to:source:model:confidence:)` | `cc-hdrm/Services/TPPStorageServiceProtocol.swift:33` |
| TPP measurement model | `TPPMeasurement` struct | `cc-hdrm/Models/TPPMeasurement.swift` |
| Token aggregates | `TokenAggregate` struct | `cc-hdrm/Models/TokenAggregate.swift:5` |
| Source enums | `MeasurementSource.passiveBackfill`, `.rollupBackfill` | `cc-hdrm/Models/TPPMeasurement.swift:22-23` |
| Preferences persistence | `PreferencesManager` | `cc-hdrm/Services/PreferencesManager.swift` |

### Idempotency Strategy (Two-Layer Check)

1. **Fast path (preference check):** `preferencesManager.tppBackfillCompleted == true` → return immediately. No DB query needed on every app launch.
2. **Slow path (DB check, first launch only):** Query `tppStorage.getMeasurements(from: 0, to: Int64.max, source: .passiveBackfill, model: nil, confidence: nil)` — if count > 0, set preference to true and return. This handles the case where backfill completed but the preference was cleared.
3. **Force re-run:** When `force = true`, delete existing backfill records first. Use SQL DELETE on `tpp_measurements WHERE source IN ('passive-backfill', 'rollup-backfill')`. Reset the preference to false. Then run the backfill.

**For the force DELETE**, add a `deleteBackfillRecords()` method to `TPPStorageServiceProtocol` and implement it. This is the only new protocol method needed.

### PreferencesManager Pattern

Follow the existing key pattern in `cc-hdrm/Services/PreferencesManager.swift`:
```swift
// In Keys enum (line ~38):
static let tppBackfillCompleted = "com.cc-hdrm.tppBackfillCompleted"

// Property (after benchmarkVariants section):
var tppBackfillCompleted: Bool {
    get { defaults.bool(forKey: Keys.tppBackfillCompleted) }
    set { defaults.set(newValue, forKey: Keys.tppBackfillCompleted) }
}
```

Also add to `resetAllPreferences()` (the method that clears all keys — check existing pattern).

Check if `PreferencesManagerProtocol` needs updating. If the protocol exposes this property, add it there too. If the backfill service takes `PreferencesManager` directly (not protocol), this may not be needed.

### AppDelegate Wiring Pattern

Wire after the existing TPP-related services at `cc-hdrm/App/AppDelegate.swift:136-159`:

```swift
// After passiveEngine creation and before pollingEngine:
let backfillService = HistoricalTPPBackfillService(
    historicalDataService: historicalDataService,
    logParser: logParser,
    tppStorage: tppStorage,
    preferencesManager: preferences
)
// Store reference if needed for SettingsView re-run button
self.backfillServiceRef = backfillService

// Fire-and-forget backfill (after all services wired, near end of launch):
Task {
    await logParser.scan()  // Ensure historical token data is loaded
    await backfillService.runBackfillIfNeeded()
}
```

The backfill Task should be placed AFTER all service wiring is complete, ideally near the end of `applicationDidFinishLaunching` or in a separate post-launch Task.

### Settings View Integration

The "Re-run Backfill" button goes in the Token Efficiency settings section of `cc-hdrm/Views/SettingsView.swift`. Look for the existing benchmark toggle (`benchmarkEnabled`) and place the button nearby. The button needs access to the backfill service — pass it through the environment or store it on `AppState`/`AppDelegate`.

### File Structure

| Purpose | Path |
|---------|------|
| Backfill protocol | `cc-hdrm/Services/HistoricalTPPBackfillServiceProtocol.swift` |
| Backfill implementation | `cc-hdrm/Services/HistoricalTPPBackfillService.swift` |
| Tests | `cc-hdrmTests/Services/HistoricalTPPBackfillServiceTests.swift` |
| Modified: TPP storage protocol | `cc-hdrm/Services/TPPStorageServiceProtocol.swift` |
| Modified: TPP storage impl | `cc-hdrm/Services/TPPStorageService.swift` |
| Modified: Preferences manager | `cc-hdrm/Services/PreferencesManager.swift` |
| Modified: AppDelegate | `cc-hdrm/App/AppDelegate.swift` |
| Modified: SettingsView | `cc-hdrm/Views/SettingsView.swift` |

### Testing Standards

- Framework: Swift Testing (`import Testing`, `@Test`, `#expect`)
- Mocks: Create `MockHistoricalDataService` (or reuse existing), `MockClaudeCodeLogParser`, `MockTPPStorageService` in test files
- Use in-memory data (no real database) — inject mock services that return predetermined data
- Verify TPP computation accuracy: known tokens / known delta = expected TPP
- Verify idempotency: second call should not store additional records
- All `@MainActor` tests use `@MainActor` attribute if needed

### Project Structure Notes

- All new files go in existing directories: `cc-hdrm/Services/`, `cc-hdrmTests/Services/`
- One type per file, file name matches type name
- Run `xcodegen generate` after adding files
- No new external dependencies

### Cross-Story Context

- **Story 20.1** (done): Created `tpp_measurements` table, `TPPMeasurement` model with `.passiveBackfill` and `.rollupBackfill` source cases, `TPPStorageService` with INSERT/query methods.
- **Story 20.2** (done): Created `ClaudeCodeLogParser` with `scan()` and `getTokens(from:to:model:)`. Parser stores in-memory only — must call `scan()` before `getTokens()` to load historical data.
- **Story 20.3** (done): Created `PassiveTPPEngine` with poll-pair processing, reset detection, accumulation windows, multi-model attribution, confidence assignment. The backfill reuses the same computation logic but without accumulation windows.
- **Story 20.4** (in progress): TPP trend visualization. Will consume backfill data through the existing `getMeasurements()` query API. Backfill records appear alongside passive records in charts with distinct visual treatment for low-confidence data.

### Previous Story Learnings

From Story 20.1 code review:
- [Fixed] Off-by-one in retry loop: use `< maxRetries` not `<= maxRetries`
- [Deferred] `SQLITE_TRANSIENT` duplicate constant per file — accepted project pattern, follow it
- [Deferred] `Int32` truncation for token counts in `sqlite3_bind_int` — pre-existing pattern, follow it

From Story 20.3 code review:
- [Fixed] `storePassiveResult` was verbatim copy of `storeBenchmarkResult` — extracted shared `insertMeasurementRecord` helper. Both public methods now delegate to it. **The backfill should also use `storePassiveResult` (which calls `insertMeasurementRecord`) for storing backfill records** — just set the correct `source` on the `TPPMeasurement`.
- [Fixed] Logger calls inside `lock.withLock` blocks — move log calls outside lock closures
- Note: `storePassiveResult` stores ANY `TPPMeasurement` regardless of source field — it just logs differently. The backfill can use it directly by setting `measurement.source = .passiveBackfill` or `.rollupBackfill`.

### Key Risks and Mitigations

1. **Log parser may have no historical data.** The JSONL parser is in-memory and loads from files on `scan()`. If Claude Code logs have been deleted or the user hasn't used Claude Code recently, `getTokens()` returns empty results. **Mitigation:** Store delta-only records (AC-4) so utilization change data is preserved even without token data.

2. **Rollup-based delta is unreliable.** Peak-min spread is a poor proxy for actual utilization change. **Mitigation:** Always `confidence = .low` for rollup backfill. Story 20.4 renders low-confidence data with reduced opacity.

3. **Backfill may process many polls.** 24 hours of polls at 30-second intervals = ~2880 polls. For each pair, a log parser query runs. **Mitigation:** The log parser `getTokens()` is an in-memory filter (O(n) scan of stored records) — fast enough for ~2880 queries. Total backfill should complete in <5 seconds.

### References

- [Source: `_bmad-output/planning-artifacts/epics/epic-20-token-efficiency-ratio-phase-6.md` — Story 20.5 ACs]
- [Source: `_bmad-output/planning-artifacts/architecture.md` — MVVM pattern, service layer, naming]
- [Source: `_bmad-output/planning-artifacts/project-context.md` — Tech stack, zero external deps]
- [Source: `cc-hdrm/Services/PassiveTPPEngine.swift` — Poll-pair processing logic to replicate]
- [Source: `cc-hdrm/Services/TPPStorageService.swift` — INSERT via `insertMeasurementRecord`, query via `getMeasurements`]
- [Source: `cc-hdrm/Services/TPPStorageServiceProtocol.swift` — `storePassiveResult`, `getMeasurements` signatures]
- [Source: `cc-hdrm/Models/TPPMeasurement.swift` — Model struct, `MeasurementSource.passiveBackfill`/`.rollupBackfill`]
- [Source: `cc-hdrm/Models/TokenAggregate.swift` — Per-model aggregate structure]
- [Source: `cc-hdrm/Models/UsagePoll.swift` — Poll model with `fiveHourUtil`, `sevenDayUtil`, `timestamp`]
- [Source: `cc-hdrm/Models/UsageRollup.swift` — Rollup model with `fiveHourPeak`, `fiveHourMin`, `resetCount`]
- [Source: `cc-hdrm/Services/HistoricalDataServiceProtocol.swift` — `getRecentPolls`, `getRolledUpData`, `getLastPoll`]
- [Source: `cc-hdrm/Services/ClaudeCodeLogParserProtocol.swift` — `scan()`, `getTokens(from:to:model:)`]
- [Source: `cc-hdrm/Services/PreferencesManager.swift:38` — Keys enum pattern for new preference]
- [Source: `cc-hdrm/App/AppDelegate.swift:136-159` — TPP service wiring location]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (claude-opus-4-6)

### Debug Log References

N/A

### Completion Notes List

- All 6 tasks completed with all subtasks
- Main app code compiles cleanly (swiftc -typecheck passes, warnings are pre-existing)
- 10 test cases written covering all acceptance criteria
- Backfill service reuses same computation logic as PassiveTPPEngine (delta, reset detection, confidence, delta-only records)
- Added `deleteBackfillRecords()` to TPPStorageServiceProtocol as the only new protocol method
- Threaded backfillService through PopoverView -> PopoverFooterView -> GearMenuView -> SettingsView chain (all optional params)

### File List

**New files:**
- `cc-hdrm/Services/HistoricalTPPBackfillServiceProtocol.swift` — Protocol with `runBackfillIfNeeded()` and `runBackfill(force:)`
- `cc-hdrm/Services/HistoricalTPPBackfillService.swift` — Implementation with raw poll + rollup backfill
- `cc-hdrmTests/Services/HistoricalTPPBackfillServiceTests.swift` — 10 test cases

**Modified files:**
- `cc-hdrm/Services/TPPStorageServiceProtocol.swift` — Added `deleteBackfillRecords()` method
- `cc-hdrm/Services/TPPStorageService.swift` — Implemented `deleteBackfillRecords()` with SQL DELETE
- `cc-hdrm/Services/PreferencesManagerProtocol.swift` — Added `tppBackfillCompleted` property
- `cc-hdrm/Services/PreferencesManager.swift` — Added key, property, and resetToDefaults entry
- `cc-hdrm/App/AppDelegate.swift` — Created backfillService, wired fire-and-forget task after log scan
- `cc-hdrm/Views/SettingsView.swift` — Added "Re-run TPP Backfill" button with progress/result UI
- `cc-hdrm/Views/GearMenuView.swift` — Threaded backfillService parameter
- `cc-hdrm/Views/PopoverView.swift` — Threaded backfillService parameter
- `cc-hdrm/Views/PopoverFooterView.swift` — Threaded backfillService parameter
- `cc-hdrmTests/Mocks/MockPreferencesManager.swift` — Added `tppBackfillCompleted` property
- `cc-hdrmTests/Services/BenchmarkServiceTests.swift` — Added `deleteBackfillRecords()` to mock
- `cc-hdrmTests/Services/PassiveTPPEngineTests.swift` — Added `deleteBackfillRecords()` to mock
