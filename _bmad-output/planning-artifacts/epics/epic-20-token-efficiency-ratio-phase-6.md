# Epic 20: Token Efficiency Ratio (Phase 6)

Alex doesn't just know how much headroom he has — he knows what he's getting for it. An opt-in "Measure" button sends controlled test requests per model and measures exactly how many tokens burn 1% of the 5h budget, revealing Anthropic's actual rate limit weighting without guessing. Passive monitoring correlates Claude Code session logs with utilization changes for continuous directional signal between calibrated benchmarks. When Anthropic silently tightens the rate limits — as Reddit users have been reporting — Alex sees it.

## Origin

Brainstorming session (2026-03-27). Motivated by community reports on Reddit that Anthropic recently tightened usage limits — the same amount of work appears to consume the budget faster. The existing slope indicator (`SlopeCalculationService`) measures %/minute but cannot distinguish "burning fast because you're working hard" from "burning fast because the rate limit weighting changed." TPP isolates the system variable (tokens per %) from the user variable (tokens per minute).

### Core Metric: Tokens per Percent (TPP)

```
TPP = Σ tokens consumed / Δ utilization%
```

- **Higher TPP** → more tokens per %, user gets better value
- **Lower TPP** → fewer tokens per %, limits are tighter
- Tracked **per model** — blended cross-model TPP is meaningless (it shows workload changes, not limit changes)
- Two tiers of data: **benchmark** (calibrated ground truth) and **passive** (continuous directional signal)

### Current State

1. **Utilization data exists** — `usage_polls` table stores 5h/7d utilization at every poll interval, rollups aggregate to 5min/hourly/daily
2. **Utilization precision is integer only** — API returns whole percentages (0, 1, 2, ..., 100). TPP can only be computed for windows where utilization changes by ≥1%
3. **Claude Code session logs exist** — `~/.claude/projects/*/*.jsonl` contain per-API-call token breakdowns: `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `model`, `timestamp`
4. **OAuth token works for Messages API** — the same token used for `/api/oauth/usage` can call the Messages API for benchmark requests
5. **Poll rate limit** — usage API rate limit is ~60/hr; practical minimum poll interval is 2 minutes

### What's Missing

1. **No benchmark capability** — app cannot send its own API requests to measure the cost of known token counts
2. **No log parser** — cc-hdrm does not read Claude Code's JSONL session files
3. **No token-to-utilization correlation** — no service links token consumption to utilization % changes
4. **No TPP storage** — no database table for TPP measurements
5. **No TPP visualization** — analytics window has no TPP trend chart

### Key Design Decisions (from Advanced Elicitation 2026-03-27)

- **No assumed token weighting ratios.** The epic originally hardcoded output=5×, cache_read=0.1× based on API pricing. Elicitation revealed that API pricing ratios are not the same as rate limit credit ratios. Instead: track raw token types separately, let benchmarks empirically discover the actual ratios.
- **Benchmark first, parser second.** The benchmark is the highest-signal, most reliable feature. It validates the entire concept. The log parser is fragile (JSONL is an unstable internal format) and passive TPP is inherently noisy. Users should get ground truth before investing in continuous monitoring.
- **Passive ≠ benchmark.** Passive TPP is directional signal (trend indicator). Benchmark TPP is calibrated measurement (ground truth). They must be visually and conceptually distinct in the UI — never mixed into a single series.
- **Per-model measurement is mandatory.** Different models consume rate limit credits at different rates. A blended TPP across models shows "what model did the user run today," not "did Anthropic change the limits." All TPP — benchmark and passive — must be segmented by model.
- **Benchmark reveals token type weighting.** By running separate benchmark variants (input-heavy, output-heavy, cache-heavy) for each model, the actual rate limit cost per token type is empirically discovered.
- **JSONL parser is best-effort with health indicator.** Claude Code's JSONL format is not a stable API. The parser must surface its success rate to the user, not silently degrade.
- **Accumulation window is capped and guarded.** Passive measurement accumulates tokens across polls until ≥1% delta, but caps at 30 minutes and requires monotonically non-decreasing utilization (no sliding-window decay contamination).
- **Lead with conclusions, not numbers.** "Your token efficiency dropped 30% this week" is actionable. "TPP = 4,200" is not. The UI should present plain-English insights first, raw data second.

### Key Design Constraints

- **Token type weighting is unknown.** We do not know Anthropic's internal credit-to-token mapping. Benchmark variants are the only way to discover it empirically. Never assume pricing ratios = rate limit ratios.
- **Model attribution is critical.** Opus, Sonnet, and Haiku likely consume credits at very different rates. Per-model segmentation is not optional.
- **Cross-project scanning.** Users may use Claude Code across multiple projects simultaneously. The log parser must scan ALL project JSONL directories, not just the current one.
- **Non-Claude-Code usage is invisible.** Activity on claude.ai web or API direct calls won't appear in Claude Code logs. Passive TPP may be inflated. The benchmark avoids this noise.
- **JSONL format is fragile.** Claude Code could change the format anytime. The parser is a best-effort enrichment layer, not a required dependency.
- **Polling delay.** There's a lag between token consumption and utilization change appearing in the next poll. TPP windows should span poll-to-poll intervals, not try to attribute individual messages.
- **Sliding window complicates long measurements.** The 5h window is sliding — tokens consumed 4.5h ago are "falling off." Accumulation windows longer than ~30 minutes mix new usage with decay.

### Dependencies

- Epic 10 (Data Persistence) — database infrastructure, rollup engine
- Epic 2 (Live Usage Data Pipeline) — polling engine, API client
- Story 18.1 (OAuth) — OAuth token access for benchmark requests

---

## Story 20.1: Active Benchmark Measurement ("Measure" Button)

As a developer using Claude Code,
I want to send controlled test requests per model and measure exactly how much utilization each consumes,
So that I get calibrated TPP readings that reveal Anthropic's actual rate limit weighting per model and token type.

**Acceptance Criteria:**

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
2. Current 5h utilization is ≤90% (enough headroom for multiple test requests across models and variants)
3. Utilization has been stable (same value) for 3+ consecutive polls (~6 minutes of no change — stronger quiet signal than 2 polls)

**If** any check fails:
- Token expired: "Sign in to Anthropic first"
- Utilization too high: "Not enough headroom for a reliable measurement. Wait for a reset."
- Recent activity detected: "Recent usage detected — measurement may be noisy. Proceed anyway?" with Proceed / Cancel

**AC-3: Per-model benchmark execution**

**Given** pre-checks pass (or user overrides the activity warning)
**When** the benchmark executes
**Then** the app runs a measurement sequence for each selected model:

1. Records the current 5h and 7d utilization
2. Sends a POST to the Messages API (`https://api.anthropic.com/v1/messages`) using the OAuth Bearer token
3. Records the response's `usage` field (exact input_tokens, output_tokens)
4. Forces an immediate usage poll (don't wait for the regular schedule — reduces noise window and wait time)
5. Records the new 5h and 7d utilization
6. Computes TPP from the known token counts and observed delta

**The benchmark runs for each model the user selects** (configurable in settings, default: auto-detect from recent Claude Code usage). Models are benchmarked sequentially with a poll between each to isolate their individual impact.

**AC-4: Benchmark variants for token type weighting discovery**

**Given** a model is being benchmarked
**When** the benchmark runs
**Then** it executes up to three variant requests (user can select which):

- **Output-heavy:** Short prompt ("Write exactly 500 words of varied placeholder text. No meta-commentary."), `max_tokens: 2048` — produces ~2K-3K output tokens with minimal input
- **Input-heavy:** Long prompt (~3K tokens of provided text + "Summarize in one sentence"), `max_tokens: 100` — produces heavy input with minimal output
- **Cache-heavy:** Repeat the output-heavy prompt immediately (second call hits prompt cache) — isolates cache read cost

Each variant records its token breakdown separately. The *ratios* between variant TPPs reveal the actual rate limit cost per token type for that model.

**AC-5: Adaptive token count**

**Given** a benchmark variant completes but the utilization delta is 0% (below detection threshold)
**When** the result is computed
**Then** the app offers: "Measurement inconclusive — not enough tokens to cause a detectable change. Send a larger request? (Uses ~X more tokens)" with Proceed / Cancel
**And** the retry doubles the token target (e.g., "Write exactly 1000 words" → "Write exactly 2000 words")
**And** maximum 3 retries before giving up: "Unable to measure — your tier may have a very high token-per-percent ratio. Try the output-heavy variant."

**AC-6: Measurement result display**

**Given** the benchmark completes successfully for a model
**When** the result is available
**Then** the app displays a result card per model:
- Model name, variant type
- "X tokens → Y% utilization change → TPP = Z"
- Comparison to previous benchmark for same model (if exists): "vs. last measurement: ±N%"
- Plain-English conclusion: "Opus currently gives you ~X tokens per 1% of your 5h budget"

**Given** multiple variants completed for a model
**When** the results are compared
**Then** the app shows discovered weighting: "For [model]: output tokens cost ~X× more than input tokens in rate limit budget. Cache reads cost ~Y× input."

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
3. "Result: [model] [variant] → TPP = X" (per-variant result as it completes)
4. "Computing summary..." (after all variants/models)
**And** a Cancel button is available at any stage (cancels remaining, keeps completed results)

**AC-8: Rate limiting**

**Given** a benchmark was completed in the last hour
**When** the user clicks "Measure" again
**Then** the app shows: "Last measurement was X minutes ago. Measure again?" with Proceed / Cancel
**And** no hard block — the user can always proceed (it's their tokens)

**AC-9: Settings**

**Given** the settings view is open
**When** the benchmark section renders
**Then** it includes:
- Toggle: "Enable Measure button" (default: off — opt-in)
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

---

## Story 20.2: Claude Code Log Parser Service

As a developer using Claude Code,
I want cc-hdrm to read my Claude Code session logs and extract token consumption data,
So that passive token efficiency monitoring can run continuously between calibrated benchmarks.

**Acceptance Criteria:**

**AC-1: JSONL discovery and scanning**

**Given** Claude Code session logs exist at `~/.claude/projects/*/*.jsonl` and `~/.claude/projects/*/<session-id>/subagents/*.jsonl`
**When** the log parser scans for session data
**Then** it discovers all `.jsonl` files across all project directories (not just the current project)
**And** it filters to files modified within the configured data retention window

**AC-2: Token extraction from assistant messages**

**Given** a JSONL file contains assistant-type messages with a `message.usage` object
**When** the parser reads a message line
**Then** it extracts:
- `timestamp` (ISO 8601 string → Unix ms)
- `model` (e.g., "claude-opus-4-6", "claude-sonnet-4-6")
- `input_tokens` (direct input, excluding cache)
- `output_tokens`
- `cache_creation_input_tokens`
- `cache_read_input_tokens`

**And** it skips lines that are not assistant messages or have no usage data
**And** it handles malformed JSON lines gracefully (skip and increment error counter)

**AC-3: Request deduplication**

**Given** the JSONL format contains duplicate/streaming messages for the same `requestId`
**When** the parser processes a file
**Then** it deduplicates by `requestId`, keeping only the final message (the one with `stop_reason` set or the last occurrence if no `stop_reason` found)
**And** this prevents double-counting tokens from streaming progress messages

**AC-4: Incremental scanning**

**Given** the parser has previously scanned a JSONL file up to byte offset N
**When** the file has grown since the last scan (file size > N)
**Then** the parser reads only from offset N to end-of-file
**And** it persists the new offset for the next scan

**Given** a JSONL file has been deleted or truncated (file size < stored offset)
**When** the parser encounters this
**Then** it resets the offset to 0 and re-scans the file

**AC-5: Token aggregation by time window and model**

**Given** extracted token records with timestamps and model identifiers
**When** the caller requests tokens for a time range `[start, end)`
**Then** the parser returns per-model aggregates:
- `model: String`
- `inputTokens: Int` (direct input, excluding cache)
- `outputTokens: Int`
- `cacheCreateTokens: Int`
- `cacheReadTokens: Int`
- `messageCount: Int`

**And** no "weighted tokens" blending is applied — callers receive raw types only
**And** the caller can optionally filter by model

**AC-6: Parser health indicator**

**Given** the parser has processed files
**When** the health status is queried
**Then** it returns:
- `totalLinesProcessed: Int`
- `successfulExtractions: Int`
- `failedLines: Int` (malformed JSON, unexpected schema)
- `successRate: Double` (percentage)
- `lastScanTimestamp: Date`
- `filesScanned: Int`

**Given** the success rate drops below 80% over the last 24 hours
**When** the health status is evaluated
**Then** a warning is surfaced to the user: "Token data extraction degraded (X% success rate). Claude Code log format may have changed."

**AC-7: Performance**

**Given** thousands of JSONL files totaling hundreds of MB
**When** the initial full scan runs
**Then** it completes within 10 seconds on a modern Mac
**And** incremental scans (checking new data only) complete within 1 second

**AC-8: Persistence of scan state**

**Given** the app is relaunched
**When** the log parser initializes
**Then** it reads persisted file offsets from a scan state file (JSON in the app support directory)
**And** resumes incremental scanning from where it left off

**Dev Notes:**
- Claude Code subagent sessions are in nested `subagents/` directories with filenames like `agent-<hash>.jsonl` — include these in discovery.
- The JSONL format is NOT a stable API. Treat the parser as fragile by design. Use defensive parsing — extract only the fields we need, ignore unknown fields, never fail on unexpected structure.
- Do NOT compute weighted tokens in the parser. Return raw types. Weighting (if any) is the caller's responsibility using empirically-derived ratios from benchmarks.

---

## Story 20.3: TPP Data Model & Passive Measurement Engine

As a developer using Claude Code,
I want cc-hdrm to automatically compute per-model TPP by correlating my token consumption with utilization changes,
So that I get continuous directional signal between calibrated benchmark measurements.

**Acceptance Criteria:**

**AC-1: Database schema**

**Given** the app launches
**When** the database is initialized or migrated
**Then** a `tpp_measurements` table exists with columns:
- `id` INTEGER PRIMARY KEY
- `timestamp` INTEGER NOT NULL — end of measurement window (Unix ms)
- `window_start` INTEGER NOT NULL — start of measurement window (Unix ms)
- `model` TEXT NOT NULL — specific model (e.g., "claude-opus-4-6")
- `five_hour_delta` REAL — utilization % change in the 5h window
- `seven_day_delta` REAL — utilization % change in the 7d window
- `input_tokens` INTEGER NOT NULL
- `output_tokens` INTEGER NOT NULL
- `cache_create_tokens` INTEGER NOT NULL
- `cache_read_tokens` INTEGER NOT NULL
- `total_raw_tokens` INTEGER NOT NULL — sum of all token types (unweighted)
- `tpp_five_hour` REAL — total_raw_tokens / five_hour_delta (NULL if delta is 0)
- `tpp_seven_day` REAL — total_raw_tokens / seven_day_delta (NULL if delta is 0)
- `source` TEXT NOT NULL — "benchmark", "passive", "passive-backfill", "rollup-backfill"
- `variant` TEXT — "output-heavy", "input-heavy", "cache-heavy" (benchmark only, NULL for passive)
- `message_count` INTEGER
- `confidence` TEXT — "high" (benchmark), "medium" (passive with ≥3% delta), "low" (passive with 1% delta or rollup-based)

**Note:** TPP is computed from `total_raw_tokens` (unweighted sum) as the default. Per-token-type TPP can be derived by callers from the raw columns. Weighted TPP is only available after benchmark calibration establishes actual ratios — this is a display-layer concern, not a storage concern.

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

**Given** a 5h utilization reset is detected (utilization drops by ≥50%)
**When** the TPP engine processes this poll
**Then** it discards any in-progress accumulation window
**And** skips TPP computation for this poll
**And** the next measurement starts fresh from the post-reset poll

**AC-4: Capped accumulation with monotonic guard**

**Given** utilization hasn't changed by ≥1% between consecutive polls but tokens are being consumed
**When** multiple polls pass with 0% delta but non-zero tokens
**Then** the engine accumulates tokens across polls until a ≥1% delta occurs
**And** the accumulation window is capped at 30 minutes — if no ≥1% delta within 30 minutes, the accumulated tokens are discarded and the window restarts
**And** if utilization *decreases* during accumulation (sliding window decay), the window is discarded and restarted from the current poll
**And** this addresses both the integer precision limitation and sliding-window contamination

**AC-5: Multi-model attribution within a window**

**Given** tokens from multiple models were consumed within a single measurement window
**When** the TPP engine stores the measurement
**Then** it creates separate TPP records per model, each with that model's token counts
**And** the utilization delta is shared across all model records (we cannot attribute % change to specific models)
**And** each record is marked `confidence = "low"` (mixed-model windows cannot isolate per-model TPP)
**And** a note field or flag indicates "shared delta — multi-model window"

**AC-6: Coverage health metric**

**Given** the passive engine has been running
**When** the health status is queried
**Then** it returns:
- `totalUtilizationChanges: Int` — number of poll-to-poll windows with ≥1% delta
- `windowsWithTokenData: Int` — how many of those had matching Claude Code token data
- `coveragePercent: Double` — windowsWithTokenData / totalUtilizationChanges × 100

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

---

## Story 20.4: TPP Trend Visualization

As a developer using Claude Code,
I want to see how my token efficiency has changed over time, with plain-English conclusions and clear separation between calibrated and directional data,
So that I can identify if Anthropic has changed the rate limit weighting.

**Acceptance Criteria:**

**AC-1: TPP section in analytics**

**Given** the analytics window is open and TPP data exists
**When** the TPP section renders
**Then** a "Token Efficiency" section appears (below or as a tab alongside the existing usage chart):
- Title: "Token Efficiency"
- A plain-English insight banner at the top (see AC-7)
- Per-model chart(s) below

**AC-2: Per-model chart rendering**

**Given** TPP data exists for one or more models
**When** the chart renders
**Then** each model with data gets its own chart area (or selectable tabs if many models):
- X-axis: time (matching the selected time range)
- Y-axis: TPP value (raw tokens per 1% utilization change)
- Model name as chart subtitle

**AC-3: Two-tier data visualization**

**Given** both passive and benchmark TPP data exist for a model
**When** the chart renders
**Then** the two data tiers are visually distinct:
- **Benchmark points:** Prominent markers (e.g., diamond shape, solid color) with exact values. These are ground truth.
- **Passive band:** A shaded range or lighter connected dots showing the continuous directional signal. Reduced visual weight compared to benchmarks.
- **Low-confidence data** (rollup-backfill, multi-model shared delta): Reduced opacity or dashed rendering

**And** a legend explains: "Benchmark = calibrated measurement, Passive = directional estimate"

**AC-4: Trend line and shift detection**

**Given** sufficient TPP data points exist for a model (≥10 passive or ≥3 benchmark)
**When** the chart renders
**Then** a smoothed trend line (moving average) overlays the data
**And** if the trend changes significantly (sustained drop or rise of >20% from the 7-day moving average), a visual annotation marks the shift point
**And** a text label near the annotation: "TPP dropped ~X%" or "TPP rose ~X%" with the approximate date

**AC-5: Time range support**

**Given** the user selects a time range (24h, 7d, 30d, All)
**When** the TPP chart updates
**Then** it shows TPP data for the selected range
**And** for 24h: individual data points (passive + benchmark)
**And** for 7d: data points with daily averages for passive, individual benchmark points
**And** for 30d/All: daily or weekly average bars for passive, individual benchmark points

**AC-6: Token type weighting discovery display**

**Given** benchmark variants (input-heavy, output-heavy, cache-heavy) have been run for a model
**When** the TPP section renders
**Then** a "Rate Limit Weighting" card appears showing the discovered ratios:
- "For [model]: output tokens cost ~X× input in rate limit budget. Cache reads cost ~Y× input."
- Based on the TPP ratio between variants: if output-heavy TPP is 5× lower than input-heavy TPP, output tokens cost 5× more in credits
- Last measured date

**AC-7: Plain-English insight banner**

**Given** TPP data exists
**When** the insight banner renders
**Then** it shows the most relevant conclusion in plain English:
- If recent benchmark TPP is >20% lower than 30-day average: "Your token efficiency dropped ~X% recently — the same work now costs more headroom."
- If recent benchmark TPP is stable (±10%): "Token efficiency is stable — no detectable rate limit changes."
- If no benchmark exists: "Run a benchmark to get a calibrated reading of your token efficiency."
- If only passive data exists: "Passive monitoring suggests [direction]. Run a benchmark to confirm."

**AC-8: Empty state**

**Given** no TPP data exists (feature just enabled, no usage yet)
**When** the TPP section renders
**Then** it shows: "Enable the Measure button in Settings to start tracking token efficiency. Passive data will also appear after your next Claude Code session."

**AC-9: Series toggles**

**Given** the analytics series toggles exist
**When** the TPP chart is visible
**Then** toggles allow showing/hiding: passive data, benchmark points, trend line
**And** a model selector allows switching between models (or "all models" overlay)
**And** defaults: all visible for the most-used model

---

## Story 20.5: Historical TPP Backfill (Nice-to-Have)

As a developer using Claude Code,
I want cc-hdrm to compute approximate TPP values from my existing raw poll history,
So that I have some historical context when the TPP feature first launches.

**Note:** This story is lower priority than 20.1–20.4. The urgent question ("did something change recently?") is better answered by starting clean passive collection now + running a benchmark. Historical backfill from rollups is inherently low-confidence due to peak-min spread approximation and sliding window effects.

**Acceptance Criteria:**

**AC-1: Backfill trigger**

**Given** the TPP feature is enabled and no passive TPP measurements exist yet
**When** the app launches
**Then** a one-time backfill job runs in the background
**And** a subtle progress indicator appears if the backfill takes >5 seconds

**AC-2: Raw poll backfill only**

**Given** raw `usage_polls` exist (typically last ~24 hours)
**When** the backfill processes these
**Then** it applies the same passive measurement logic from Story 20.3:
- Pairs consecutive polls, computes deltas, queries log parser for tokens in each window per model
- Stores TPP measurements with `source = "passive-backfill"`, `confidence = "medium"`

**AC-3: Rollup-based backfill (optional, lower confidence)**

**Given** 5min/hourly rollups exist for older periods
**When** the backfill processes a rollup bucket
**Then** it approximates utilization delta as `five_hour_peak - five_hour_min` within each bucket
**And** queries the log parser for tokens in the rollup's `[period_start, period_end)` window, per model
**And** if both delta ≥1 and tokens > 0: computes approximate TPP and stores with `source = "rollup-backfill"`, `confidence = "low"`

**Note:** Rollup-based TPP is inherently noisy. Peak-min spread within an hourly bucket may include resets, concurrent sessions, and idle decay. This data is useful for spotting large (>30%) shifts but not subtle changes.

**AC-4: Graceful gaps**

**Given** no Claude Code JSONL logs exist for a historical period
**When** the backfill encounters a period with utilization changes but zero tokens
**Then** it stores a delta-only record (no TPP computed) rather than skipping entirely
**And** this preserves the utilization change data for context

**AC-5: Idempotency**

**Given** the backfill has already run
**When** the app is relaunched
**Then** the backfill does not re-run (checks for existing backfill records)
**And** a manual "Re-run backfill" option exists in settings for users who want to reprocess after log recovery
