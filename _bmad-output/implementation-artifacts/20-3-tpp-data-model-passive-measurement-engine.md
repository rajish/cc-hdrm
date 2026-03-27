# Story 20.3: TPP Data Model & Passive Measurement Engine

Status: ready-for-dev

## Story

As a developer using Claude Code,
I want cc-hdrm to automatically compute per-model TPP by correlating my token consumption with utilization changes,
So that I get continuous directional signal between calibrated benchmark measurements.

## Acceptance Criteria

**AC-1: Database schema (already exists)**

The `tpp_measurements` table was created in Story 20.1 (migration v6->v7) with all required columns. **No schema changes are needed.** The passive engine writes to the same table using `source = "passive"` and the existing column set: `timestamp`, `window_start`, `model`, `five_hour_delta`, `seven_day_delta`, `input_tokens`, `output_tokens`, `cache_create_tokens`, `cache_read_tokens`, `total_raw_tokens`, `tpp_five_hour`, `tpp_seven_day`, `source`, `confidence`, `message_count`.

**AC-2: Passive measurement trigger**

**Given** a new usage poll is received with valid 5h utilization
**When** the previous poll is available for comparison
**Then** the TPP engine:
1. Computes `five_hour_delta = current.fiveHourUtil - previous.fiveHourUtil`
2. Computes `seven_day_delta = current.sevenDayUtil - previous.sevenDayUtil`
3. Queries the log parser for tokens in `[previous.timestamp, current.timestamp)`, grouped by model
4. For each model with tokens > 0:
   a. If `five_hour_delta >= 1` OR `seven_day_delta >= 1`: stores a TPP measurement per model
   b. If both deltas are 0: accumulates tokens into the current accumulation window (see AC-4)
5. If total tokens across all models == 0 AND any delta > 0: stores a delta-only record (indicates non-Claude-Code usage) with model = "unknown"

**AC-3: Reset handling**

**Given** a 5h utilization reset is detected (utilization drops by >=50%)
**When** the TPP engine processes this poll
**Then** it discards any in-progress accumulation window
**And** skips TPP computation for this poll
**And** the next measurement starts fresh from the post-reset poll

**AC-4: Capped accumulation with monotonic guard**

**Given** utilization hasn't changed by >=1% between consecutive polls but tokens are being consumed
**When** multiple polls pass with 0% delta but non-zero tokens
**Then** the engine accumulates tokens across polls until a >=1% delta occurs
**And** the accumulation window is capped at 30 minutes -- if no >=1% delta within 30 minutes, the accumulated tokens are discarded and the window restarts
**And** if utilization *decreases* during accumulation (sliding window decay), the window is discarded and restarted from the current poll
**And** this addresses both the integer precision limitation and sliding-window contamination

**AC-5: Multi-model attribution within a window**

**Given** tokens from multiple models were consumed within a single measurement window
**When** the TPP engine stores the measurement
**Then** it creates separate TPP records per model, each with that model's token counts
**And** the utilization delta is shared across all model records (we cannot attribute % change to specific models)
**And** each record is marked `confidence = "low"` (mixed-model windows cannot isolate per-model TPP)

**AC-6: Coverage health metric**

**Given** the passive engine has been running
**When** the health status is queried
**Then** it returns:
- `totalUtilizationChanges: Int` -- number of poll-to-poll windows with >=1% delta
- `windowsWithTokenData: Int` -- how many of those had matching Claude Code token data
- `coveragePercent: Double` -- windowsWithTokenData / totalUtilizationChanges * 100

**Given** coverage drops below 70% over the last 7 days
**When** the health is evaluated
**Then** a suggestion surfaces: "Only X% of utilization changes had matching token data. Use the Measure button for more reliable readings."

**AC-7: TPP query API**

**Given** TPP measurements exist in the database
**When** a caller requests TPP data for a time range
**Then** the service returns `[TPPMeasurement]` sorted by timestamp
**And** supports filtering by source ("passive", "benchmark", or "all")
**And** supports filtering by model
**And** supports filtering by confidence level
**And** supports aggregation (average TPP per model over a time range)

## Tasks / Subtasks

- [ ] Task 1: Create `PassiveTPPEngine` protocol and implementation (AC: 2, 3, 4, 5)
  - [ ] 1.1 Create `cc-hdrm/Services/PassiveTPPEngineProtocol.swift` with protocol defining `processPoll(current:previous:)` and `getHealth()` and `resetAccumulation()`
  - [ ] 1.2 Create `cc-hdrm/Services/PassiveTPPEngine.swift` implementing the protocol
  - [ ] 1.3 Inject `ClaudeCodeLogParserProtocol` and `TPPStorageServiceProtocol` as dependencies
  - [ ] 1.4 Implement poll-pair processing: compute deltas, query log parser for tokens in window, store per-model TPP
  - [ ] 1.5 Implement accumulation window state: track window start timestamp, accumulated per-model tokens, starting utilization
  - [ ] 1.6 Implement 30-minute cap: discard accumulated tokens and restart window when cap exceeded
  - [ ] 1.7 Implement monotonic guard: discard window if utilization decreases during accumulation
  - [ ] 1.8 Implement reset detection: drop >= 50% in 5h utilization discards accumulation, skips TPP for that poll
  - [ ] 1.9 Implement multi-model attribution: separate records per model, shared delta, confidence = "low" when >1 model
  - [ ] 1.10 Implement delta-only record: store with model = "unknown" when delta > 0 but zero tokens found
  - [ ] 1.11 Implement confidence assignment: "medium" for single-model with >=3% delta, "low" for 1% delta or multi-model

- [ ] Task 2: Create `PassiveTPPHealth` model (AC: 6)
  - [ ] 2.1 Create `cc-hdrm/Models/PassiveTPPHealth.swift` struct with fields: `totalUtilizationChanges`, `windowsWithTokenData`, `coveragePercent`, `isDegraded`, `degradationSuggestion`
  - [ ] 2.2 Set degradation threshold at 70% coverage

- [ ] Task 3: Extend `TPPStorageService` with passive write and query methods (AC: 1, 7)
  - [ ] 3.1 Add `storePassiveResult(_ measurement: TPPMeasurement)` to `TPPStorageServiceProtocol`
  - [ ] 3.2 Implement `storePassiveResult` in `TPPStorageService` -- same INSERT logic as `storeBenchmarkResult`, reuse the private helpers
  - [ ] 3.3 Add `getMeasurements(from:to:source:model:confidence:)` -> `[TPPMeasurement]` to protocol
  - [ ] 3.4 Implement query with optional WHERE clauses for source, model, confidence filters, ORDER BY timestamp ASC
  - [ ] 3.5 Add `getAverageTPP(from:to:model:source:)` -> `(fiveHour: Double?, sevenDay: Double?)` to protocol
  - [ ] 3.6 Implement aggregation query using AVG() on tpp_five_hour and tpp_seven_day columns

- [ ] Task 4: Integrate passive engine into PollingEngine (AC: 2)
  - [ ] 4.1 Add `passiveTPPEngine: (any PassiveTPPEngineProtocol)?` parameter to `PollingEngine.init()`
  - [ ] 4.2 After successful poll persistence in `fetchUsageData()`, invoke passive engine processing
  - [ ] 4.3 Create the current and previous `UsagePoll` objects and pass to `passiveTPPEngine.processPoll(current:previous:)`
  - [ ] 4.4 Trigger a log parser incremental scan before passive processing: `await logParser?.scan()`
  - [ ] 4.5 Processing is fire-and-forget inside existing Task block -- failure must not affect other services

- [ ] Task 5: Wire into AppDelegate (AC: all)
  - [ ] 5.1 Create `PassiveTPPEngine` instance in `AppDelegate.applicationDidFinishLaunching()` after log parser and TPP storage
  - [ ] 5.2 Pass `passiveTPPEngine` to `PollingEngine` constructor
  - [ ] 5.3 Pass `claudeCodeLogParser` to `PollingEngine` constructor (new optional parameter)

- [ ] Task 6: Write tests (AC: all)
  - [ ] 6.1 Create `cc-hdrmTests/Services/PassiveTPPEngineTests.swift`
  - [ ] 6.2 Test basic passive measurement: 1 model, 5h delta >=1%, tokens found -> TPP stored
  - [ ] 6.3 Test zero delta accumulation: 0% delta with tokens -> tokens accumulated, not stored
  - [ ] 6.4 Test accumulation flush: accumulated tokens + subsequent poll with delta >=1% -> TPP stored with full window
  - [ ] 6.5 Test 30-minute cap: accumulation exceeds 30min -> tokens discarded, window restarts
  - [ ] 6.6 Test monotonic guard: utilization decreases during accumulation -> window discarded
  - [ ] 6.7 Test reset handling: 50%+ drop -> accumulation discarded, no TPP stored
  - [ ] 6.8 Test multi-model: 2 models in window -> 2 records, shared delta, confidence = "low"
  - [ ] 6.9 Test single model confidence: delta >=3% -> "medium", delta 1% -> "low"
  - [ ] 6.10 Test delta-only record: delta > 0 but zero tokens -> record with model = "unknown"
  - [ ] 6.11 Test coverage health: verify totalUtilizationChanges, windowsWithTokenData, coveragePercent calculation
  - [ ] 6.12 Create `cc-hdrmTests/Services/TPPStorageServiceQueryTests.swift` for new query methods
  - [ ] 6.13 Test getMeasurements with source/model/confidence filters
  - [ ] 6.14 Test getAverageTPP aggregation

- [ ] Task 7: Run `xcodegen generate` and verify build
  - [ ] 7.1 Run `xcodegen generate` after all files are added
  - [ ] 7.2 Verify build compiles cleanly
  - [ ] 7.3 Verify all tests pass

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with Service Layer. `PassiveTPPEngine` is a service that reads from `ClaudeCodeLogParser` and writes through `TPPStorageService`. It does NOT interact with AppState directly.
- **Concurrency:** Swift structured concurrency only. No GCD, no Combine. `PassiveTPPEngine` methods are `async`.
- **Sendable:** Use `@unchecked Sendable` with `NSLock` to protect mutable accumulation window state (same pattern as `DatabaseManager` at `cc-hdrm/Services/DatabaseManager.swift`).
- **Protocol-first:** `PassiveTPPEngineProtocol.swift` + `PassiveTPPEngine.swift` as separate files.
- **Logging:** Use `os.Logger` with subsystem `"com.cc-hdrm.app"` and category `"passive-tpp"`.
- **Error handling:** Passive engine is fire-and-forget. Failures log errors but never crash the app or affect polling.

### Database Schema -- NO CHANGES NEEDED

The `tpp_measurements` table was created in Story 20.1 (migration v6->v7 in `cc-hdrm/Services/DatabaseManager.swift:365-403`). The schema already includes all columns needed for passive measurements:
- `window_start` for accumulation window start
- `source` for "passive" value
- `confidence` for "medium"/"low"
- `message_count` for accumulated message counts
- `five_hour_before`, `five_hour_after`, `five_hour_delta` for utilization tracking
- `seven_day_before`, `seven_day_after`, `seven_day_delta`

Current schema version is 7. Do NOT create a new migration. Do NOT modify the existing table.

### Accumulation Window State

The accumulation window is in-memory state on `PassiveTPPEngine`:

```swift
struct AccumulationWindow {
    let startTimestamp: Int64          // Unix ms when window opened
    let startFiveHourUtil: Double      // 5h utilization at window start
    let startSevenDayUtil: Double?     // 7d utilization at window start
    var tokensByModel: [String: TokenAggregate]  // accumulated per-model tokens
    var lastPollTimestamp: Int64        // most recent poll in this window
}
```

- Window starts when a poll has tokens but 0% delta
- Window flushes when a subsequent poll has >=1% delta (TPP computed from window start to current poll)
- Window discards on: 30-min cap exceeded, utilization decrease, reset detection
- Window resets: new window starts from the current poll after discard

### Integration Point: PollingEngine

The passive engine hooks into `PollingEngine.fetchUsageData()` at `cc-hdrm/Services/PollingEngine.swift:276-298` -- inside the existing fire-and-forget `Task` block after `persistPoll()`. The integration should:

1. Trigger incremental log parser scan: `await logParser?.scan()`
2. Get previous and current poll data
3. Call `passiveTPPEngine?.processPoll(current:previous:)`

The previous poll is already fetched inside `persistPoll()` (line 70), but it's not returned. Two approaches:
- **Option A (preferred):** Query `getLastPoll()` BEFORE the new poll is inserted. Since `persistPoll` already does this internally, the engine can do the same query before calling persistPoll.
- **Option B:** Get the two most recent polls from DB after persist and use the older one as "previous."

**Use Option A:** In the PollingEngine fire-and-forget Task, query `getLastPoll()` before `persistPoll()`, then after persist, create the "current" poll from the response and pass both to the passive engine.

**IMPORTANT:** The passive engine must receive the poll timestamps, NOT `Date()` — use the same `Int64(Date().timeIntervalSince1970 * 1000)` pattern as `HistoricalDataService.persistPoll()`.

### Reset Detection in Passive Engine

The passive engine uses a SIMPLER reset detection than `HistoricalDataService`:
- Just check: `previous.fiveHourUtil - current.fiveHourUtil >= 50`
- No `resets_at` timestamp comparison needed -- the engine only cares about large utilization drops, not the exact reset mechanism
- This is consistent with the epic spec: "5h utilization reset is detected (utilization drops by >=50%)"

### Confidence Assignment Logic

| Condition | Confidence |
|-----------|-----------|
| Single model, 5h delta >= 3% | `medium` |
| Single model, 5h delta 1-2% | `low` |
| Multiple models in window | `low` (always) |
| Delta-only record (no tokens) | `low` |

### TPP Computation

```swift
let tppFiveHour: Double? = fiveHourDelta >= 1 ? Double(totalRawTokens) / fiveHourDelta : nil
let tppSevenDay: Double? = sevenDayDelta != nil && sevenDayDelta! >= 1 ? Double(totalRawTokens) / sevenDayDelta! : nil
```

`totalRawTokens = inputTokens + outputTokens + cacheCreateTokens + cacheReadTokens` (unweighted sum, same as `TPPMeasurement.fromBenchmark` at `cc-hdrm/Models/TPPMeasurement.swift:89`).

### Existing Services to Reuse (DO NOT REINVENT)

| Need | Existing Service | Location |
|------|-----------------|----------|
| Token data from logs | `ClaudeCodeLogParserProtocol.getTokens(from:to:model:)` | `cc-hdrm/Services/ClaudeCodeLogParserProtocol.swift:15` |
| Incremental log scan | `ClaudeCodeLogParserProtocol.scan()` | `cc-hdrm/Services/ClaudeCodeLogParserProtocol.swift:8` |
| TPP persistence | `TPPStorageServiceProtocol.storeBenchmarkResult(_:)` | `cc-hdrm/Services/TPPStorageServiceProtocol.swift:7` |
| TPP measurement model | `TPPMeasurement` struct | `cc-hdrm/Models/TPPMeasurement.swift` |
| Token aggregates | `TokenAggregate` struct | `cc-hdrm/Models/TokenAggregate.swift` |
| Measurement enums | `MeasurementSource`, `MeasurementConfidence` | `cc-hdrm/Models/TPPMeasurement.swift:19-31` |
| Previous poll query | `HistoricalDataServiceProtocol.getLastPoll()` | `cc-hdrm/Services/HistoricalDataServiceProtocol.swift:32` |
| Database access | `DatabaseManager.shared` | `cc-hdrm/Services/DatabaseManager.swift` |
| Service wiring | `AppDelegate.applicationDidFinishLaunching` | `cc-hdrm/App/AppDelegate.swift:58` |

### PollingEngine Dependency Injection

`PollingEngine` already accepts many optional service parameters. Add two new ones:

```swift
init(
    // ... existing params ...
    passiveTPPEngine: (any PassiveTPPEngineProtocol)? = nil,
    claudeCodeLogParser: (any ClaudeCodeLogParserProtocol)? = nil
)
```

Both default to `nil` for backward compatibility with existing tests.

### TPPStorageService Extension

The existing `storeBenchmarkResult` method can be reused for passive measurements since the INSERT SQL is identical. However, a dedicated `storePassiveResult` method improves clarity and allows different logging. Alternatively, rename to a generic `storeMeasurement` -- but to minimize churn, just add a new protocol method that delegates to the same internal INSERT.

The `readMeasurement(from:)` helper at `cc-hdrm/Services/TPPStorageService.swift:148` already handles all columns and can be reused for the query methods.

### File Structure

| Purpose | Path |
|---------|------|
| Passive engine protocol | `cc-hdrm/Services/PassiveTPPEngineProtocol.swift` |
| Passive engine impl | `cc-hdrm/Services/PassiveTPPEngine.swift` |
| Health model | `cc-hdrm/Models/PassiveTPPHealth.swift` |
| Engine tests | `cc-hdrmTests/Services/PassiveTPPEngineTests.swift` |
| Query tests | `cc-hdrmTests/Services/TPPStorageServiceQueryTests.swift` |
| Modified: TPP storage protocol | `cc-hdrm/Services/TPPStorageServiceProtocol.swift` |
| Modified: TPP storage impl | `cc-hdrm/Services/TPPStorageService.swift` |
| Modified: Polling engine | `cc-hdrm/Services/PollingEngine.swift` |
| Modified: AppDelegate | `cc-hdrm/App/AppDelegate.swift` |

### Testing Standards

- Framework: Swift Testing (`import Testing`, `@Test`, `#expect`)
- Mocks: Create `MockClaudeCodeLogParser` and `MockTPPStorageService` in test files (or use existing mocks if available)
- `PassiveTPPEngine` tests: inject mocks for log parser and storage, verify correct TPP computation and storage calls
- Use in-memory SQLite for `TPPStorageService` query tests (same pattern as `cc-hdrmTests/Services/TPPStorageServiceTests.swift`)
- All `@MainActor` tests use `@MainActor` attribute

### Project Structure Notes

- All new files go in existing directories: `cc-hdrm/Services/`, `cc-hdrm/Models/`, `cc-hdrmTests/Services/`
- One type per file, file name matches type name
- Run `xcodegen generate` after adding files

### Cross-Story Context

- **Story 20.1** (done): Created `tpp_measurements` table, `TPPMeasurement` model, `TPPStorageService`, `BenchmarkService`. All infrastructure this story builds on.
- **Story 20.2** (done): Created `ClaudeCodeLogParser` service with `getTokens(from:to:model:)` API. This is the token data source for the passive engine.
- **Story 20.4** (next): Will consume the query API from Task 3 to visualize TPP trends. The `getMeasurements()` and `getAverageTPP()` methods must return data suitable for charting.
- **Story 20.5** (future): Will use the passive engine logic for backfill. Keeping the engine stateless per-call (accumulation is in-memory, not persisted) makes it reusable.

### Previous Story Learnings

From Story 20.1 code review:
- [Fixed] Off-by-one in retry loop: use `< maxRetries` not `<= maxRetries`
- [Fixed] ForEach non-unique IDs when multiple variants per model -- use compound ID
- [Deferred] `SQLITE_TRANSIENT` duplicate constant per file -- accepted project pattern, follow it

From Story 20.2:
- Log parser stores data in-memory only (no DB dependency) -- scan must be triggered before querying
- `getTokens()` returns `[TokenAggregate]` with per-model separation -- exactly what the passive engine needs
- Parser is `@unchecked Sendable` with NSLock -- safe to call from any context

### References

- [Source: `_bmad-output/planning-artifacts/epics/epic-20-token-efficiency-ratio-phase-6.md` -- Story 20.3 ACs]
- [Source: `_bmad-output/planning-artifacts/architecture.md` -- MVVM pattern, service layer, naming]
- [Source: `_bmad-output/planning-artifacts/project-context.md` -- Tech stack, zero external deps]
- [Source: `cc-hdrm/Services/TPPStorageService.swift` -- INSERT pattern, readMeasurement helper]
- [Source: `cc-hdrm/Services/TPPStorageServiceProtocol.swift` -- Existing protocol methods]
- [Source: `cc-hdrm/Models/TPPMeasurement.swift` -- Model struct, MeasurementSource/Confidence enums]
- [Source: `cc-hdrm/Services/ClaudeCodeLogParserProtocol.swift` -- getTokens() and scan() API]
- [Source: `cc-hdrm/Models/TokenAggregate.swift` -- Per-model aggregate structure]
- [Source: `cc-hdrm/Services/PollingEngine.swift:276-298` -- Fire-and-forget Task integration point]
- [Source: `cc-hdrm/App/AppDelegate.swift:151-163` -- Service wiring for TPP storage and benchmark]
- [Source: `cc-hdrm/App/AppDelegate.swift:300-305` -- Log parser initialization pattern]
- [Source: `cc-hdrm/Services/DatabaseManager.swift:365-403` -- tpp_measurements table schema, v7]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
