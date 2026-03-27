# Story 20.1: Active Benchmark Measurement ("Measure" Button)

Status: ready-for-dev

## Story

As a developer using Claude Code,
I want to send controlled test requests per model and measure exactly how much utilization each consumes,
So that I get calibrated TPP readings that reveal Anthropic's actual rate limit weighting per model and token type.

## Acceptance Criteria

**AC-1: Measure button placement**

**Given** the analytics window is open
**When** the TPP section is visible (or a dedicated "Token Efficiency" tab/section)
**Then** a "Measure" button appears near the chart area
**And** a tooltip explains: "Send test requests to measure token efficiency per model. Uses real tokens from your quota."

**AC-2: Pre-measurement validation**

**Given** the user clicks "Measure"
**When** the pre-checks run
**Then** the app validates:
1. OAuth token is valid (not expired)
2. Current 5h utilization is <=90% (enough headroom for multiple test requests across models and variants)
3. Utilization has been stable (same value) for 3+ consecutive polls (~6 minutes of no change -- stronger quiet signal than 2 polls)

**If** any check fails:
- Token expired: "Sign in to Anthropic first"
- Utilization too high: "Not enough headroom for a reliable measurement. Wait for a reset."
- Recent activity detected: "Recent usage detected -- measurement may be noisy. Proceed anyway?" with Proceed / Cancel

**AC-3: Per-model benchmark execution**

**Given** pre-checks pass (or user overrides the activity warning)
**When** the benchmark executes
**Then** the app runs a measurement sequence for each selected model:

1. Records the current 5h and 7d utilization
2. Sends a POST to the Messages API (`https://api.anthropic.com/v1/messages`) using the OAuth Bearer token
3. Records the response's `usage` field (exact input_tokens, output_tokens)
4. Forces an immediate usage poll (don't wait for the regular schedule -- reduces noise window and wait time)
5. Records the new 5h and 7d utilization
6. Computes TPP from the known token counts and observed delta

The benchmark runs for each model the user selects (configurable in settings, default: auto-detect from recent Claude Code usage). Models are benchmarked sequentially with a poll between each to isolate their individual impact.

**AC-4: Benchmark variants for token type weighting discovery**

**Given** a model is being benchmarked
**When** the benchmark runs
**Then** it executes up to three variant requests (user can select which):

- **Output-heavy:** Short prompt ("Write exactly 500 words of varied placeholder text. No meta-commentary."), `max_tokens: 2048` -- produces ~2K-3K output tokens with minimal input
- **Input-heavy:** Long prompt (~3K tokens of provided text + "Summarize in one sentence"), `max_tokens: 100` -- produces heavy input with minimal output
- **Cache-heavy:** Repeat the output-heavy prompt immediately (second call hits prompt cache) -- isolates cache read cost

Each variant records its token breakdown separately. The *ratios* between variant TPPs reveal the actual rate limit cost per token type for that model.

**AC-5: Adaptive token count**

**Given** a benchmark variant completes but the utilization delta is 0% (below detection threshold)
**When** the result is computed
**Then** the app offers: "Measurement inconclusive -- not enough tokens to cause a detectable change. Send a larger request? (Uses ~X more tokens)" with Proceed / Cancel
**And** the retry doubles the token target (e.g., "Write exactly 1000 words" -> "Write exactly 2000 words")
**And** maximum 3 retries before giving up: "Unable to measure -- your tier may have a very high token-per-percent ratio. Try the output-heavy variant."

**AC-6: Measurement result display**

**Given** the benchmark completes successfully for a model
**When** the result is available
**Then** the app displays a result card per model:
- Model name, variant type
- "X tokens -> Y% utilization change -> TPP = Z"
- Comparison to previous benchmark for same model (if exists): "vs. last measurement: +/-N%"
- Plain-English conclusion: "Opus currently gives you ~X tokens per 1% of your 5h budget"

**Given** multiple variants completed for a model
**When** the results are compared
**Then** the app shows discovered weighting: "For [model]: output tokens cost ~X times more than input tokens in rate limit budget. Cache reads cost ~Y times input."

**Given** the utilization delta after all retries is still 0%
**When** the result is computed
**Then** the app reports: "Measurement inconclusive for [model]. This model may have a very high token allowance on your tier."
**And** no TPP measurement is stored

**AC-7: Progress indication**

**Given** the benchmark is in progress
**When** the user sees the Measure button area
**Then** it shows a progress state:
1. "Benchmarking [model]... sending [variant] request" (during API call)
2. "Polling for utilization update..." (during forced poll)
3. "Result: [model] [variant] -> TPP = X" (per-variant result as it completes)
4. "Computing summary..." (after all variants/models)
**And** a Cancel button is available at any stage (cancels remaining, keeps completed results)

**AC-8: Rate limiting**

**Given** a benchmark was completed in the last hour
**When** the user clicks "Measure" again
**Then** the app shows: "Last measurement was X minutes ago. Measure again?" with Proceed / Cancel
**And** no hard block -- the user can always proceed (it's their tokens)

**AC-9: Settings**

**Given** the settings view is open
**When** the benchmark section renders
**Then** it includes:
- Toggle: "Enable Measure button" (default: off -- opt-in)
- Model selector: which models to benchmark (checkboxes, default: auto-detect from recent usage)
- Variant selector: which variants to run (checkboxes, default: output-heavy only for simplicity)
- Info text: "Benchmark sends test requests per model to measure how many tokens equal 1% of your usage budget. Each variant uses ~2K-5K tokens. Running all variants for all models uses the most tokens but reveals the most about rate limit weighting."

**AC-10: Data persistence**

**Given** a benchmark measurement completes
**When** the result is stored
**Then** it is saved to `tpp_measurements` with:
- `source = "benchmark"`
- `model` = the specific model benchmarked
- `variant` = "output-heavy" | "input-heavy" | "cache-heavy"
- Full raw token breakdown (input, output, cache_create, cache_read)
- The computed TPP value
- Timestamp of measurement

## Tasks / Subtasks

- [ ] Task 1: Create `tpp_measurements` database table (AC: 10)
  - [ ] 1.1 Add `createTppMeasurementsTable` method to `cc-hdrm/Services/DatabaseManager.swift` — follows pattern of `createApiOutagesTable` at line ~341
  - [ ] 1.2 Add migration v6->v7 in `runMigrations()` (increment `currentSchemaVersion` to 7) — follows pattern at `cc-hdrm/Services/DatabaseManager.swift:140`
  - [ ] 1.3 Schema: `id INTEGER PRIMARY KEY AUTOINCREMENT`, `timestamp INTEGER NOT NULL`, `window_start INTEGER`, `model TEXT NOT NULL`, `variant TEXT`, `source TEXT NOT NULL`, `five_hour_before REAL`, `five_hour_after REAL`, `five_hour_delta REAL`, `seven_day_before REAL`, `seven_day_after REAL`, `seven_day_delta REAL`, `input_tokens INTEGER NOT NULL`, `output_tokens INTEGER NOT NULL`, `cache_create_tokens INTEGER NOT NULL DEFAULT 0`, `cache_read_tokens INTEGER NOT NULL DEFAULT 0`, `total_raw_tokens INTEGER NOT NULL`, `tpp_five_hour REAL`, `tpp_seven_day REAL`, `confidence TEXT NOT NULL DEFAULT 'high'`, `message_count INTEGER DEFAULT 1`
  - [ ] 1.4 Create indexes: `idx_tpp_timestamp` on `(timestamp)`, `idx_tpp_model_source` on `(model, source)`
  - [ ] 1.5 Write tests in `cc-hdrmTests/Services/DatabaseManagerTests.swift` for migration and table creation

- [ ] Task 2: Create `BenchmarkService` protocol and implementation (AC: 3, 4, 5)
  - [ ] 2.1 Create `cc-hdrm/Services/BenchmarkServiceProtocol.swift` defining the protocol
  - [ ] 2.2 Create `cc-hdrm/Services/BenchmarkService.swift` implementation
  - [ ] 2.3 Implement Messages API POST via `DataLoader` injection (same pattern as `cc-hdrm/Services/APIClient.swift:26`) — endpoint: `https://api.anthropic.com/v1/messages`, headers: `Authorization: Bearer <token>`, `anthropic-version: 2023-06-01`, `content-type: application/json`
  - [ ] 2.4 Implement three benchmark variants: output-heavy, input-heavy, cache-heavy — each constructs the appropriate Messages API request body with `model`, `max_tokens`, and `messages` array
  - [ ] 2.5 Implement adaptive retry logic: if utilization delta is 0% after a variant, double the token target and retry up to 3 times
  - [ ] 2.6 Parse response `usage` field: `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`
  - [ ] 2.7 Implement TPP computation: `total_raw_tokens / five_hour_delta` (and seven_day_delta if >= 1)
  - [ ] 2.8 Write comprehensive tests in `cc-hdrmTests/Services/BenchmarkServiceTests.swift`

- [ ] Task 3: Create `TPPStorageService` for persistence (AC: 10)
  - [ ] 3.1 Create `cc-hdrm/Services/TPPStorageServiceProtocol.swift`
  - [ ] 3.2 Create `cc-hdrm/Services/TPPStorageService.swift` — follows pattern of `cc-hdrm/Services/HistoricalDataService.swift` (uses `DatabaseManagerProtocol`, raw SQLite3 bindings, graceful degradation)
  - [ ] 3.3 Implement `storeBenchmarkResult(_:)` — INSERT into `tpp_measurements`
  - [ ] 3.4 Implement `latestBenchmark(model:variant:)` — for comparison display in AC-6
  - [ ] 3.5 Implement `lastBenchmarkTimestamp()` — for rate limiting check in AC-8
  - [ ] 3.6 Write tests in `cc-hdrmTests/Services/TPPStorageServiceTests.swift`

- [ ] Task 4: Create `TPPMeasurement` model (AC: 10)
  - [ ] 4.1 Create `cc-hdrm/Models/TPPMeasurement.swift` — struct with all fields matching the database schema
  - [ ] 4.2 Include computed properties: `tppFiveHour` (totalRawTokens / fiveHourDelta when delta > 0), `tppSevenDay`
  - [ ] 4.3 Include `BenchmarkVariant` enum: `.outputHeavy`, `.inputHeavy`, `.cacheHeavy`
  - [ ] 4.4 Include `MeasurementSource` enum: `.benchmark`, `.passive`, `.passiveBackfill`, `.rollupBackfill`
  - [ ] 4.5 Write tests in `cc-hdrmTests/Models/TPPMeasurementTests.swift`

- [ ] Task 5: Pre-measurement validation (AC: 2)
  - [ ] 5.1 Add validation logic to `BenchmarkService`: check OAuth state via `AppState.connectionStatus` and `AppState.oauthState`
  - [ ] 5.2 Check 5h utilization <= 90% via `AppState.fiveHour?.utilization`
  - [ ] 5.3 Implement utilization stability check: track last 3+ poll values (same integer value = stable). Store recent poll values in the service or read from `usage_polls` table via `HistoricalDataServiceProtocol`
  - [ ] 5.4 Return validation result enum: `.ready`, `.tokenExpired`, `.utilizationTooHigh`, `.recentActivity`

- [ ] Task 6: Forced usage poll integration (AC: 3)
  - [ ] 6.1 Add `performForcedPoll() async` method to `PollingEngineProtocol` in `cc-hdrm/Services/PollingEngineProtocol.swift`
  - [ ] 6.2 Implement in `cc-hdrm/Services/PollingEngine.swift` — calls `performPollCycle()` directly, bypassing the sleep loop. `performPollCycle()` is already `func` (internal), just need a public wrapper
  - [ ] 6.3 BenchmarkService calls forced poll after each API request to get immediate utilization update
  - [ ] 6.4 Write tests for forced poll in `cc-hdrmTests/Services/PollingEngineTests.swift`

- [ ] Task 7: Benchmark settings preferences (AC: 9)
  - [ ] 7.1 Add keys to `cc-hdrm/Services/PreferencesManager.swift` `Keys` enum: `benchmarkEnabled`, `benchmarkModels`, `benchmarkVariants`
  - [ ] 7.2 Add properties to `PreferencesManagerProtocol`: `isBenchmarkEnabled: Bool` (default: false), `benchmarkModels: [String]` (default: empty = auto-detect), `benchmarkVariants: [String]` (default: ["output-heavy"])
  - [ ] 7.3 Implement getters/setters following existing pattern (e.g., `extraUsageAlertsEnabled` at `cc-hdrm/Services/PreferencesManager.swift:28`)
  - [ ] 7.4 Write tests in `cc-hdrmTests/Services/PreferencesManagerTests.swift`

- [ ] Task 8: Settings UI for benchmark configuration (AC: 9)
  - [ ] 8.1 Add "Token Efficiency" section to `cc-hdrm/Views/SettingsView.swift` — follows existing section pattern (toggle + pickers + info text)
  - [ ] 8.2 Toggle for "Enable Measure button" bound to `preferencesManager.isBenchmarkEnabled`
  - [ ] 8.3 Model checkboxes (dynamic list from `AppState` or hardcoded known models: claude-opus-4-6, claude-sonnet-4-6, claude-haiku-4-5-20251001)
  - [ ] 8.4 Variant checkboxes: Output-heavy, Input-heavy, Cache-heavy
  - [ ] 8.5 Info text explaining token cost
  - [ ] 8.6 Write tests in `cc-hdrmTests/Views/SettingsViewTests.swift`

- [ ] Task 9: Benchmark orchestration and result display UI (AC: 1, 6, 7, 8)
  - [ ] 9.1 Create `cc-hdrm/Views/BenchmarkSectionView.swift` — the "Token Efficiency" section in analytics with the Measure button, progress, and results
  - [ ] 9.2 Implement Measure button with tooltip (AC-1)
  - [ ] 9.3 Implement progress display: step-by-step status text with Cancel button (AC-7)
  - [ ] 9.4 Implement result cards per model showing TPP, delta, comparison to previous (AC-6)
  - [ ] 9.5 Implement weighting discovery display when multiple variants complete (AC-6)
  - [ ] 9.6 Implement rate-limiting soft warning for recent measurements (AC-8)
  - [ ] 9.7 Write tests in `cc-hdrmTests/Views/BenchmarkSectionViewTests.swift`

- [ ] Task 10: Analytics view integration (AC: 1)
  - [ ] 10.1 Add `BenchmarkSectionView` to `cc-hdrm/Views/AnalyticsView.swift` — conditionally shown when `preferencesManager.isBenchmarkEnabled` is true
  - [ ] 10.2 Wire BenchmarkService and TPPStorageService through from `cc-hdrm/App/AppDelegate.swift` — follows pattern of `historicalDataServiceRef` (lines 95-100)
  - [ ] 10.3 Pass services through `AnalyticsWindow` to `AnalyticsView` to `BenchmarkSectionView`
  - [ ] 10.4 Update `cc-hdrm/Views/AnalyticsWindow.swift` to accept and pass through benchmark dependencies

- [ ] Task 11: Run `xcodegen generate` and verify build
  - [ ] 11.1 Run `xcodegen generate` to pick up all new Swift files
  - [ ] 11.2 Verify `swift build` or `xcodebuild` succeeds
  - [ ] 11.3 Run all tests and fix any failures

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with Service Layer. BenchmarkService is a service that writes results through TPPStorageService (not directly to AppState). The UI observes BenchmarkService state for progress/results.
- **Concurrency:** Swift structured concurrency only. No GCD, no Combine. BenchmarkService methods are `async throws`.
- **State flow:** BenchmarkService -> TPPStorageService -> DatabaseManager for persistence. BenchmarkSectionView observes a `@Observable` BenchmarkState object for progress/results.
- **Protocol-first:** Every new service gets a Protocol file. Use `any ServiceProtocol` in consumers (same pattern as `any HistoricalDataServiceProtocol`).
- **Sendable:** Follow `@unchecked Sendable` + `NSLock` pattern if mutable state is needed (like `cc-hdrm/Services/DatabaseManager.swift`), otherwise `struct` services are inherently `Sendable`.

### Messages API Integration

- **Endpoint:** `POST https://api.anthropic.com/v1/messages`
- **Auth:** `Authorization: Bearer <oauth_token>` (same token from `KeychainService`)
- **Required headers:**
  - `anthropic-version: 2023-06-01` (latest stable)
  - `content-type: application/json`
- **Request body structure:**
  ```json
  {
    "model": "claude-sonnet-4-6",
    "max_tokens": 2048,
    "messages": [{"role": "user", "content": "Write exactly 500 words..."}]
  }
  ```
- **Response `usage` field:**
  ```json
  {
    "usage": {
      "input_tokens": 15,
      "output_tokens": 532,
      "cache_creation_input_tokens": 0,
      "cache_read_input_tokens": 0
    }
  }
  ```
- **Do NOT use the `anthropic-beta: oauth-2025-04-20` header** for Messages API calls. That header is specific to the usage/profile OAuth endpoints. The Messages API uses the standard `anthropic-version` header.
- **OAuth scope:** The existing OAuth flow requests `user:inference` scope (see `cc-hdrm/Services/OAuthService.swift:14`), which should authorize Messages API calls.

### Forced Poll Design

- `PollingEngine.performPollCycle()` is already `func` (internal visibility, not `private`). The forced poll wrapper just needs to call it directly.
- The forced poll must go through the full pipeline: keychain read -> token check -> API fetch -> state update -> historical persistence. This ensures the benchmark sees the accurate post-request utilization.
- After the forced poll, BenchmarkService reads `AppState.fiveHour?.utilization` and `AppState.sevenDay?.utilization` for the "after" values.

### Utilization Stability Check

- Read the last 3 entries from `usage_polls` table ordered by timestamp DESC.
- Cast `five_hour_util` to integer (API returns whole numbers). If all 3 are the same integer, utilization is stable.
- Alternative: BenchmarkService maintains a small in-memory ring buffer of recent utilization values updated on each poll (avoids DB query, but requires service to be long-lived and subscribed to poll events).
- Preferred approach: DB query via HistoricalDataService — simpler, no new subscription mechanism needed.

### Token Count for Input-Heavy Variant

The input-heavy variant needs ~3K tokens of input text. Options:
- Hardcode a block of Lorem Ipsum-style text in the source (simplest, deterministic)
- Generate text dynamically (unnecessary complexity)
- **Recommended:** Hardcode a ~3K-token block of generic English text as a static constant in BenchmarkService. This ensures deterministic measurements.

### Rate Limit Headers Bonus

The Messages API response includes rate limit headers (`anthropic-ratelimit-*`). While not required for this story, BenchmarkService should log these values at `.debug` level for future use (Story 20.3 passive engine may benefit from RPM/ITPM visibility).

### Database Schema Notes

The `tpp_measurements` table schema is designed to serve both Story 20.1 (benchmark) and Story 20.3 (passive measurements). Story 20.1 only writes `source = "benchmark"` records. The `window_start`, `message_count`, and `confidence` columns exist for Story 20.3 compatibility but Story 20.1 can use sensible defaults (`window_start = timestamp`, `message_count = 1`, `confidence = "high"`).

### Project Structure Notes

- All new files go in existing directories: `cc-hdrm/Services/`, `cc-hdrm/Models/`, `cc-hdrm/Views/`, `cc-hdrmTests/Services/`, etc.
- One type per file. File name matches type name.
- Protocol files: `BenchmarkServiceProtocol.swift`, `TPPStorageServiceProtocol.swift`
- Test files mirror source: `cc-hdrmTests/Services/BenchmarkServiceTests.swift`, etc.
- Run `xcodegen generate` after adding files (project uses XcodeGen with `project.yml`).

### Existing Services to Reuse (DO NOT REINVENT)

| Need | Existing Service | Location |
|------|-----------------|----------|
| OAuth token | `KeychainService` | `cc-hdrm/Services/KeychainService.swift` |
| Token validation | `AppState.connectionStatus` / `AppState.oauthState` | `cc-hdrm/State/AppState.swift` |
| Usage poll data | `AppState.fiveHour?.utilization` | `cc-hdrm/State/AppState.swift` |
| Historical polls | `HistoricalDataService` | `cc-hdrm/Services/HistoricalDataService.swift` |
| Database access | `DatabaseManager.shared` | `cc-hdrm/Services/DatabaseManager.swift` |
| Preferences | `PreferencesManager` | `cc-hdrm/Services/PreferencesManager.swift` |
| HTTP requests | `DataLoader` pattern from `APIClient` | `cc-hdrm/Services/APIClient.swift:20-22` |
| Forced poll | `PollingEngine.performPollCycle()` | `cc-hdrm/Services/PollingEngine.swift:129` |
| Service wiring | `AppDelegate.applicationDidFinishLaunching` | `cc-hdrm/App/AppDelegate.swift:55` |

### Testing Standards

- Framework: Swift Testing (`import Testing`, `@Test`, `#expect`)
- Mocks: Protocol-based injection. New mock files in `cc-hdrmTests/Mocks/` if needed.
- BenchmarkService tests: Inject mock `DataLoader` that returns predetermined Messages API responses. Inject mock `PollingEngineProtocol` for forced poll verification.
- TPPStorageService tests: Use in-memory SQLite database (same pattern as `cc-hdrmTests/Services/DatabaseManagerTests.swift`).
- All `@MainActor` tests use `@MainActor` attribute.

### References

- [Source: `_bmad-output/planning-artifacts/epics/epic-20-token-efficiency-ratio-phase-6.md` -- Story 20.1 ACs]
- [Source: `_bmad-output/planning-artifacts/architecture.md` -- MVVM pattern, service layer]
- [Source: `_bmad-output/planning-artifacts/project-context.md` -- Tech stack, naming conventions, anti-patterns]
- [Source: `_bmad-output/planning-artifacts/research/technical-anthropic-api-surface-research-2026-02-24.md` -- Messages API endpoint, headers, rate limits]
- [Source: `cc-hdrm/Services/DatabaseManager.swift` -- Schema version 6, migration chain pattern]
- [Source: `cc-hdrm/Services/APIClient.swift` -- DataLoader injection pattern, header conventions]
- [Source: `cc-hdrm/Services/PollingEngine.swift:129` -- performPollCycle() internal visibility]
- [Source: `cc-hdrm/Services/OAuthService.swift:14` -- OAuth scope includes user:inference]
- [Source: `cc-hdrm/Services/PreferencesManager.swift` -- Keys enum pattern, property pattern]
- [Source: `cc-hdrm/Services/HistoricalDataService.swift` -- SQLite service pattern with DatabaseManagerProtocol]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
