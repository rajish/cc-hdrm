# Story 20.2: Claude Code Log Parser Service

Status: ready-for-dev

## Story

As a developer using Claude Code,
I want cc-hdrm to read my Claude Code session logs and extract token consumption data,
So that passive token efficiency monitoring can run continuously between calibrated benchmarks.

## Acceptance Criteria

**AC-1: JSONL discovery and scanning**

**Given** Claude Code session logs exist at `~/.claude/projects/*/*.jsonl` and `~/.claude/projects/*/<session-id>/subagents/*.jsonl`
**When** the log parser scans for session data
**Then** it discovers all `.jsonl` files across all project directories (not just the current project)
**And** it filters to files modified within the configured data retention window

**AC-2: Token extraction from assistant messages**

**Given** a JSONL file contains assistant-type messages with a `message.usage` object
**When** the parser reads a message line
**Then** it extracts:
- `timestamp` (ISO 8601 string from the top-level `timestamp` field, e.g. `"2026-03-14T19:53:23.101Z"` -> Unix ms)
- `model` (from `message.model`, e.g. `"claude-opus-4-6"`, `"claude-sonnet-4-6"`)
- `input_tokens` (from `message.usage.input_tokens` -- direct input, excluding cache)
- `output_tokens` (from `message.usage.output_tokens`)
- `cache_creation_input_tokens` (from `message.usage.cache_creation_input_tokens`)
- `cache_read_input_tokens` (from `message.usage.cache_read_input_tokens`)

**And** it skips lines where `type != "assistant"` or where `message.usage` is absent
**And** it handles malformed JSON lines gracefully (skip and increment error counter)

**AC-3: Request deduplication**

**Given** the JSONL format contains multiple streaming messages for the same `requestId`
**When** the parser processes a file
**Then** it deduplicates by `requestId` (top-level field), keeping only the final message (highest `output_tokens` count for that `requestId`, or the one with `stop_reason` set if available)
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

**And** no "weighted tokens" blending is applied -- callers receive raw types only
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

## Tasks / Subtasks

- [ ] Task 1: Create `ClaudeCodeLogParser` service with protocol (AC: 1, 2, 3)
  - [ ] 1.1 Create `ClaudeCodeLogParserProtocol` in `cc-hdrm/Services/ClaudeCodeLogParserProtocol.swift`
  - [ ] 1.2 Create `ClaudeCodeLogParser` in `cc-hdrm/Services/ClaudeCodeLogParser.swift`
  - [ ] 1.3 Implement JSONL file discovery: glob `~/.claude/projects/*/*.jsonl` and `~/.claude/projects/*/*/subagents/*.jsonl`
  - [ ] 1.4 Implement line-by-line JSON parsing with defensive extraction of token fields from assistant messages
  - [ ] 1.5 Implement `requestId` deduplication: collect all assistant messages per requestId, keep only the one with highest output_tokens

- [ ] Task 2: Create data models (AC: 2, 5, 6)
  - [ ] 2.1 Create `TokenRecord` struct in `cc-hdrm/Models/TokenRecord.swift` -- single extracted token event
  - [ ] 2.2 Create `TokenAggregate` struct in `cc-hdrm/Models/TokenAggregate.swift` -- per-model aggregation result
  - [ ] 2.3 Create `LogParserHealth` struct in `cc-hdrm/Models/LogParserHealth.swift` -- health status
  - [ ] 2.4 Run `xcodegen generate` after adding files

- [ ] Task 3: Implement incremental scanning (AC: 4, 8)
  - [ ] 3.1 Create `LogScanState` struct for per-file offset tracking (file path -> byte offset)
  - [ ] 3.2 Implement JSON persistence of scan state to `~/Library/Application Support/cc-hdrm/log-scan-state.json`
  - [ ] 3.3 Implement incremental read: seek to stored offset, read new bytes, process line-by-line
  - [ ] 3.4 Handle file truncation/deletion: detect file size < stored offset, reset to 0

- [ ] Task 4: Implement aggregation API (AC: 5)
  - [ ] 4.1 Store deduplicated `TokenRecord` entries in an in-memory array (sorted by timestamp)
  - [ ] 4.2 Implement `getTokens(from:to:model:)` -> `[TokenAggregate]` method with binary search on timestamp
  - [ ] 4.3 Return per-model aggregates with raw token counts only (no weighted blending)

- [ ] Task 5: Implement health indicator (AC: 6)
  - [ ] 5.1 Track line processing counters: totalLinesProcessed, successfulExtractions, failedLines
  - [ ] 5.2 Implement `getHealth()` -> `LogParserHealth` method
  - [ ] 5.3 Implement success rate calculation and 80% degradation threshold warning

- [ ] Task 6: Write tests (AC: all)
  - [ ] 6.1 Create `cc-hdrmTests/Services/ClaudeCodeLogParserTests.swift`
  - [ ] 6.2 Test JSONL parsing: valid assistant message, non-assistant message, malformed JSON, missing usage field
  - [ ] 6.3 Test requestId deduplication: multiple messages for same requestId, keep highest output_tokens
  - [ ] 6.4 Test incremental scanning: initial scan sets offset, subsequent scan reads from offset, truncated file resets
  - [ ] 6.5 Test aggregation: single model, multiple models, time range filtering, model filtering
  - [ ] 6.6 Test health: success rate calculation, degradation threshold
  - [ ] 6.7 Run `xcodegen generate && swift test` to verify all tests pass

- [ ] Task 7: Wire service into app (AC: all)
  - [ ] 7.1 Add `ClaudeCodeLogParser` property to `AppDelegate` in `cc-hdrm/App/AppDelegate.swift`
  - [ ] 7.2 Initialize parser during `applicationDidFinishLaunching` alongside other services
  - [ ] 7.3 Trigger initial scan on app launch (async, non-blocking)
  - [ ] 7.4 Run `xcodegen generate` after all changes

## Dev Notes

### JSONL Format (Observed from Real Files)

The Claude Code JSONL format is **not a stable API**. The parser must be maximally defensive.

**Top-level line structure:**
```json
{
  "type": "assistant",          // FILTER: only process "assistant" type
  "timestamp": "2026-03-14T19:53:23.101Z",  // ISO 8601 -> parse to Unix ms
  "requestId": "req_011CZ3ZH...",  // DEDUP KEY
  "message": {
    "model": "claude-opus-4-6",
    "usage": {
      "input_tokens": 3,
      "output_tokens": 228,
      "cache_creation_input_tokens": 12163,
      "cache_read_input_tokens": 8821
      // Also contains: cache_creation, service_tier, inference_geo — IGNORE these
    },
    "stop_reason": "tool_use",    // or "end_turn", or null for streaming
    "id": "msg_01NPr3cnJUXR..."
  }
}
```

**Other line types to skip:** `"user"`, `"system"`, `"file-history-snapshot"`, `"progress"`, and any unknown type.

**Deduplication pattern observed:**
- Same `requestId` appears across multiple lines (streaming progress updates)
- Streaming messages typically have `stop_reason: null` and low `output_tokens`
- Final message has `stop_reason` set (`"tool_use"` or `"end_turn"`) and highest `output_tokens`
- Example: `req_011CZ3ZH...` has 3 entries with output_tokens: 11, 11, 228 — keep the 228 one

**Subagent files:**
- Located at `~/.claude/projects/<project-hash>/<session-id>/subagents/agent-<hash>.jsonl`
- Same line format as main session files (include `type`, `message.usage`, `requestId`)
- Must be included in discovery

### Architecture & Patterns

**Service pattern:** Follow the established `Protocol + Implementation` pair convention:
- `ClaudeCodeLogParserProtocol.swift` — protocol for testability
- `ClaudeCodeLogParser.swift` — implementation

**Concurrency:** Use structured concurrency (`async/await`). No GCD, no Combine. The initial scan can be launched as a background `Task` from AppDelegate.

**Logging:** Use `os.Logger` with subsystem `"com.cc-hdrm.app"` and category `"logparser"`. Log key events: scan start, files discovered, scan complete (with counts), errors. Never log file contents or token values at info level.

**Error handling:** The parser is a best-effort enrichment layer. Failures must never crash the app or affect other services. Use graceful degradation: if parsing fails, return empty results. Track failures in health metrics.

**File I/O:** Use `FileManager` for file discovery and `FileHandle` for incremental reads (seek to offset, read to end). Process lines one at a time to bound memory usage.

**Data retention:** Filter JSONL files by modification date against the configured data retention window from `PreferencesManager.dataRetentionDays` (default 365 days).

**No database dependency:** This service stores its in-memory token data and scan state independently. It does NOT write to the SQLite database. The scan state file is a simple JSON file at `~/Library/Application Support/cc-hdrm/log-scan-state.json`.

**Thread safety:** The service must be `Sendable`. Use `@unchecked Sendable` with an internal `NSLock` to protect mutable state (same pattern as `DatabaseManager`). Or use an actor if more natural.

### File Paths (Project-Relative)

| Purpose | Path |
|---------|------|
| Protocol | `cc-hdrm/Services/ClaudeCodeLogParserProtocol.swift` |
| Implementation | `cc-hdrm/Services/ClaudeCodeLogParser.swift` |
| TokenRecord model | `cc-hdrm/Models/TokenRecord.swift` |
| TokenAggregate model | `cc-hdrm/Models/TokenAggregate.swift` |
| LogParserHealth model | `cc-hdrm/Models/LogParserHealth.swift` |
| Tests | `cc-hdrmTests/Services/ClaudeCodeLogParserTests.swift` |
| Scan state persistence | `~/Library/Application Support/cc-hdrm/log-scan-state.json` |
| AppDelegate wiring | `cc-hdrm/App/AppDelegate.swift` |

### Testing Strategy

Use Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`). Create temporary JSONL files in test fixtures with known content. Use in-memory scan state (no file persistence in tests). Mock `FileManager` paths to point to temp directories.

Key test scenarios:
- Parse valid assistant message with all usage fields
- Skip non-assistant messages (`type: "user"`, `type: "system"`)
- Handle malformed JSON (incomplete lines, non-JSON content)
- Handle missing `message.usage` in assistant messages
- Dedup: 3 messages with same requestId, keep the one with max output_tokens
- Incremental: write file, scan, append to file, scan again — verify only new data processed
- Aggregation: tokens from 2 models in overlapping time window, verify per-model separation
- Health: inject N valid + M invalid lines, verify successRate = N/(N+M)*100

### Project Structure Notes

- New files go in `cc-hdrm/Services/` and `cc-hdrm/Models/` per layer-based organization
- Run `xcodegen generate` after adding any Swift files (project uses XcodeGen with `project.yml`)
- No new external dependencies — use only Foundation and os frameworks
- Test file goes in `cc-hdrmTests/Services/` mirroring source structure

### Cross-Story Context

- Story 20.1 (Active Benchmark) is the sibling story that creates the `tpp_measurements` table and benchmark infrastructure. The log parser does NOT depend on 20.1 — it is an independent, self-contained service
- Story 20.3 (TPP Data Model & Passive Measurement Engine) will be the primary consumer of this parser, calling `getTokens(from:to:model:)` to correlate token consumption with utilization changes
- Story 20.5 (Historical TPP Backfill) will also use this parser for retroactive TPP computation from existing logs
- The parser does NOT compute TPP or interact with the database. It is a pure extraction service

### Existing Patterns to Follow

- **Protocol naming:** `ClaudeCodeLogParserProtocol` (matches `KeychainServiceProtocol`, `APIClientProtocol`, etc.)
- **Logger setup:** `private static let logger = Logger(subsystem: "com.cc-hdrm.app", category: "logparser")`
- **Sendable conformance:** Use `@unchecked Sendable` with `NSLock` (matches `DatabaseManager`) or actor
- **Codable models:** `TokenRecord`, `TokenAggregate`, `LogParserHealth` should be `Sendable` and `Equatable`
- **App wiring:** Add property to `AppDelegate`, initialize in `applicationDidFinishLaunching` alongside existing services (see `cc-hdrm/App/AppDelegate.swift` lines 7-60 for pattern)
- **Test helpers:** Create private helper methods for test data construction (matches `SlopeCalculationServiceTests`)

### Scan State File Format

```json
{
  "version": 1,
  "lastFullScanTimestamp": 1711900000000,
  "files": {
    "/Users/user/.claude/projects/proj1/session1.jsonl": {
      "byteOffset": 524288,
      "lastModified": 1711900000000
    }
  }
}
```

### References

- [Epic 20 spec: Story 20.2 ACs](../_bmad-output/planning-artifacts/epics/epic-20-token-efficiency-ratio-phase-6.md)
- [Architecture: Service patterns](../_bmad-output/planning-artifacts/architecture.md) — Protocol + Implementation, os.Logger, error handling
- [Architecture: Database patterns](../_bmad-output/planning-artifacts/architecture.md) — App Support directory convention, scan state file follows same base path
- [Project context: Technology stack](../_bmad-output/planning-artifacts/project-context.md) — Swift 6, SwiftUI, zero external dependencies
- [DatabaseManager pattern](cc-hdrm/Services/DatabaseManager.swift) — @unchecked Sendable with NSLock, singleton, App Support path convention
- [SlopeCalculationServiceTests](cc-hdrmTests/Services/SlopeCalculationServiceTests.swift) — Swift Testing patterns, helper methods

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
