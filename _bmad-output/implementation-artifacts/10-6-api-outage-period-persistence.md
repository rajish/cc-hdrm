# Story 10.6: API Outage Period Tracking & Persistence

Status: done

## Story

As a **Claude Pro/Max subscriber using cc-hdrm**,
I want **API outage periods automatically tracked and persisted to SQLite** whenever the Anthropic API becomes unreachable,
so that **the analytics window can later render outage periods as distinct visual bands (Story 13.8), distinguishing "API was down" from "app wasn't running"**.

## Acceptance Criteria

1. **Given** PollingEngine detects an outage (2+ consecutive poll failures), **When** the outage begins, **Then** a new record is inserted into `api_outages` with `started_at` timestamp and `failure_reason`, **And** `ended_at` is NULL (ongoing outage).

2. **Given** an outage is ongoing (`ended_at` IS NULL), **When** the first successful poll completes, **Then** the outage record is updated with `ended_at` timestamp.

3. **Given** the app quits during an ongoing outage, **When** the app relaunches and the first poll succeeds, **Then** the open outage record is closed with `ended_at` = relaunch time (approximate).

4. **Given** the app quits during an ongoing outage, **When** the app relaunches and the first poll also fails, **Then** the existing open outage record remains open (outage continues).

5. **Given** HistoricalDataService queries for a time range, **When** outage data is requested, **Then** it returns all outage periods overlapping the requested range via `getOutagePeriods(from:to:) -> [OutagePeriod]`.

## Tasks / Subtasks

- [x] Task 1: Database migration v5→v6 — Create `api_outages` table (AC: 1)
  - [x] 1.1: Bump `currentSchemaVersion` from 5 to 6 in `cc-hdrm/Services/DatabaseManager.swift`
  - [x] 1.2: Add `createApiOutagesTable(_:)` private method with schema (see Dev Notes)
  - [x] 1.3: Call `createApiOutagesTable` from `ensureSchema()` for fresh installs (alongside existing table creation calls at line ~118)
  - [x] 1.4: Add `existingVersion < 6` migration case in `runMigrations()` (after existing `existingVersion < 5` block at line ~164)
- [x] Task 2: Create `OutagePeriod` model (AC: 5)
  - [x] 2.1: Create `cc-hdrm/Models/OutagePeriod.swift` — `struct OutagePeriod: Sendable, Equatable`
  - [x] 2.2: Properties: `id: Int64`, `startedAt: Int64` (Unix ms), `endedAt: Int64?`, `failureReason: String`
  - [x] 2.3: Computed properties: `isOngoing: Bool`, `startDate: Date`, `endDate: Date?`
- [x] Task 3: Protocol additions to HistoricalDataServiceProtocol (AC: 1-5)
  - [x] 3.1: Add `evaluateOutageState(apiReachable: Bool, failureReason: String?) async` to `cc-hdrm/Services/HistoricalDataServiceProtocol.swift`
  - [x] 3.2: Add `getOutagePeriods(from: Date?, to: Date?) async throws -> [OutagePeriod]`
  - [x] 3.3: Add `closeOpenOutages(endedAt: Date) async throws`
  - [x] 3.4: Add `loadOutageState() async throws` (restores in-memory state from DB on startup)
- [x] Task 4: Implement outage tracking in HistoricalDataService (AC: 1-4)
  - [x] 4.1: Add internal outage state properties: `consecutiveFailureCount: Int`, `outageActive: Bool`
  - [x] 4.2: Implement `evaluateOutageState` — 2-failure threshold, INSERT on outage start, UPDATE on recovery
  - [x] 4.3: Implement `getOutagePeriods(from:to:)` — query with overlap logic
  - [x] 4.4: Implement `closeOpenOutages(endedAt:)` — UPDATE all records where `ended_at IS NULL`
  - [x] 4.5: Implement `loadOutageState()` — check for open outages in DB, set `outageActive = true` if found
- [x] Task 5: PollingEngine integration (AC: 1-4)
  - [x] 5.1: Add outage state evaluation calls alongside existing `evaluateConnectivity` calls in `cc-hdrm/Services/PollingEngine.swift`
  - [x] 5.2: Map AppError types to failure reason strings (see Dev Notes mapping table)
  - [x] 5.3: Use fire-and-forget Task pattern for outage tracking (non-blocking, log errors)
- [x] Task 6: App startup — restore outage state (AC: 3-4)
  - [x] 6.1: Call `historicalDataService.loadOutageState()` after database initialization in `cc-hdrm/App/AppDelegate.swift`
  - [x] 6.2: Verify AC 3-4 are handled naturally by the combination of loadOutageState + evaluateOutageState flow
- [x] Task 7: Update MockHistoricalDataService (AC: all)
  - [x] 7.1: Add mock properties and implementations for all new protocol methods in `cc-hdrmTests/Mocks/MockHistoricalDataService.swift`
- [x] Task 8: Tests (AC: all)
  - [x] 8.1: DatabaseManager — `api_outages` table creation on fresh install
  - [x] 8.2: DatabaseManager — migration v5→v6 creates table and index
  - [x] 8.3: OutagePeriod model — computed properties, Equatable conformance
  - [x] 8.4: HistoricalDataService — single failure does NOT create outage record
  - [x] 8.5: HistoricalDataService — 2 consecutive failures creates outage record with correct failure_reason
  - [x] 8.6: HistoricalDataService — success after outage closes the record with ended_at
  - [x] 8.7: HistoricalDataService — multiple failures after outage detection don't create duplicate records
  - [x] 8.8: HistoricalDataService — success when no outage active is a no-op
  - [x] 8.9: HistoricalDataService — getOutagePeriods returns correct results for time ranges
  - [x] 8.10: HistoricalDataService — getOutagePeriods returns outages overlapping range boundaries
  - [x] 8.11: HistoricalDataService — loadOutageState sets outageActive from open DB record
  - [x] 8.12: HistoricalDataService — relaunch scenario: open outage + success closes it (AC 3)
  - [x] 8.13: HistoricalDataService — relaunch scenario: open outage + failure keeps it open (AC 4)
  - [x] 8.14: HistoricalDataService — graceful degradation: database unavailable skips all operations
  - [x] 8.15: PollingEngine — verify evaluateOutageState called with correct params on success
  - [x] 8.16: PollingEngine — verify evaluateOutageState called with correct failure reasons on each error type
- [x] Task 9: Run `xcodegen generate` and verify all tests pass

## Dev Notes

### Architecture Overview

This story adds **API outage period persistence** to the existing SQLite database. The feature is consumed by Story 13.8 (outage background rendering in analytics charts) which will visualize outage periods as colored background bands.

**Key distinction:**
- **Data gap** = cc-hdrm wasn't running (existing, rendered as hatched/grey in charts)
- **API outage** = cc-hdrm was running, Anthropic API was unreachable (new, will be muted red/salmon in charts)

### Database Schema

**Table: `api_outages`** — Added via migration v5→v6

```sql
CREATE TABLE IF NOT EXISTS api_outages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at INTEGER NOT NULL,    -- Unix ms (consistent with all other tables)
    ended_at INTEGER,               -- Unix ms, NULL if ongoing
    failure_reason TEXT NOT NULL     -- e.g., "networkUnreachable", "httpError:503"
);
CREATE INDEX IF NOT EXISTS idx_api_outages_started_at ON api_outages(started_at);
```

**Design note:** The sprint change proposal specifies `TEXT` (ISO 8601) for timestamps. This story uses `INTEGER` (Unix ms) instead for **consistency with all existing tables** (`usage_polls`, `usage_rollups`, `reset_events` all use INTEGER Unix ms). This avoids date-parsing overhead in range queries and keeps the query patterns uniform across the database.

### Outage Detection State Machine

HistoricalDataService maintains its own outage detection state independently from NotificationService (which tracks the same threshold for notification delivery). This keeps both services self-contained and testable.

```
                    ┌──────────────────┐
    app start ─────►│  loadOutageState  │
                    │  (check DB for    │
                    │  open outage)     │
                    └────────┬─────────┘
                             │
              ┌──────────────┴──────────────┐
              │                              │
     open outage found              no open outage
     outageActive = true            outageActive = false
     failureCount = 2               failureCount = 0
              │                              │
              ▼                              ▼
    ┌───────────────────────────────────────────┐
    │           evaluateOutageState()           │
    │                                           │
    │  apiReachable = true:                     │
    │    if outageActive → close outage record  │
    │    reset failureCount, outageActive       │
    │                                           │
    │  apiReachable = false:                    │
    │    failureCount++                         │
    │    if count >= 2 && !outageActive:        │
    │      INSERT new outage, outageActive=true │
    └───────────────────────────────────────────┘
```

### Failure Reason Mapping (PollingEngine → HistoricalDataService)

| PollingEngine Error | `failureReason` String | evaluateConnectivity called? |
|---|---|---|
| `.networkUnreachable` | `"networkUnreachable"` | Yes |
| `.apiError(statusCode, _)` (non-401) | `"httpError:{statusCode}"` | Yes |
| `.parseError` | `"parseError"` | Yes |
| Default AppError | `"unknown"` | Yes |
| Non-AppError catch | `"unknown"` | Yes |
| `.apiError(401, _)` | N/A — not called | No (API reachable, auth issue) |
| Credential errors | N/A — not called | No (no API attempt) |

### PollingEngine Integration Pattern

Add `evaluateOutageState` calls alongside **every existing** `evaluateConnectivity` call site in `cc-hdrm/Services/PollingEngine.swift`. There are 6 call sites:

**Success path** (line 219 of PollingEngine.swift):
```swift
await notificationService?.evaluateConnectivity(apiReachable: true)
// NEW: Record outage recovery (fire-and-forget)
Task {
    await historicalDataService?.evaluateOutageState(apiReachable: true, failureReason: nil)
}
```

**Failure paths** (lines 295, 312, 321, 330, 339 of PollingEngine.swift):
```swift
await notificationService?.evaluateConnectivity(apiReachable: false)
// NEW: Record outage state (fire-and-forget)
Task {
    await historicalDataService?.evaluateOutageState(apiReachable: false, failureReason: "<mapped_reason>")
}
```

### App Startup / Relaunch Flow

The `loadOutageState()` method handles AC 3 and AC 4 automatically:
1. On startup, check DB for open outages (`ended_at IS NULL`)
2. If open outage exists → set `outageActive = true`, `consecutiveFailureCount = 2` (already past threshold)
3. First poll cycle runs:
   - **Success** → `evaluateOutageState(apiReachable: true)` → closes the open outage record (AC 3)
   - **Failure** → `evaluateOutageState(apiReachable: false)` → outageActive already true, no new record, counter increments (AC 4)

Call `loadOutageState()` in `cc-hdrm/App/AppDelegate.swift` after `DatabaseManager.shared.initialize()` and after HistoricalDataService construction, **before** `pollingEngine.start()`.

### getOutagePeriods Query Design

The query must find outages that **overlap** the requested time range, not just those that start within it. An outage overlaps `[from, to]` if:
- `started_at <= to` AND (`ended_at >= from` OR `ended_at IS NULL`)

```sql
SELECT id, started_at, ended_at, failure_reason
FROM api_outages
WHERE started_at <= ? AND (ended_at >= ? OR ended_at IS NULL)
ORDER BY started_at ASC
```

If `from` is nil, omit the `ended_at >= ?` clause. If `to` is nil, omit the `started_at <= ?` clause.

### Existing Patterns to Follow

- **Thread safety:** HistoricalDataService is `@unchecked Sendable` with `DatabaseManager` handling its own locking via `NSLock`. Outage state properties (`consecutiveFailureCount`, `outageActive`) are only mutated within `evaluateOutageState` which is called sequentially from PollingEngine's poll cycle. No additional locking needed.
- **SQLITE_TRANSIENT:** Use `unsafeBitCast(-1, to: sqlite3_destructor_type.self)` for text binding (see `cc-hdrm/Services/DatabaseManager.swift:10`)
- **Graceful degradation:** Guard `databaseManager.isAvailable` at the top of every method (see existing `persistPoll` at `cc-hdrm/Services/HistoricalDataService.swift:52`)
- **Logging:** Use `os.Logger` with subsystem `"com.cc-hdrm.app"`, category `"historical"` (existing logger in HistoricalDataService)
- **Statement cleanup:** Always use `defer { sqlite3_finalize(statement) }` pattern
- **Test pattern:** Use `DatabaseManager(databasePath:)` with temp directory, `defer { cleanup() }` (see `cc-hdrmTests/Services/DatabaseManagerTests.swift:11-26`)
- **Method does not throw on outage tracking:** `evaluateOutageState` should handle errors internally (log and continue) — same as `NotificationService.evaluateConnectivity` which never throws

### Project Structure Notes

- All models in `cc-hdrm/Models/` (e.g., `UsagePoll.swift`, `ResetEvent.swift`)
- All services in `cc-hdrm/Services/`
- All protocols in `cc-hdrm/Services/` as separate `*Protocol.swift` files
- Tests mirror source structure: `cc-hdrmTests/Services/`, `cc-hdrmTests/Models/`, `cc-hdrmTests/Mocks/`
- After adding `OutagePeriod.swift`, run `xcodegen generate` to update the Xcode project

### Previous Story Intelligence (Epic 10)

**Story 10.1 (DatabaseManager):** Established migration pattern — `getSchemaVersion()` → `runMigrations()` with version checks. Fresh installs call `createXxxTable()` from `ensureSchema()`. Migration creates same table for existing DBs. Follow this exact pattern for `api_outages`.

**Story 10.2 (HistoricalDataService):** Established fire-and-forget Task pattern for persistence in PollingEngine. `persistPoll` is called in a background Task (PollingEngine.swift lines 224-243). Follow the same non-blocking pattern for outage tracking.

**Story 10.3 (Reset Detection):** Established the pattern of HistoricalDataService maintaining internal detection state (`utilizationDropThreshold`, `resetCooldownMs`). The outage detection follows the same self-contained pattern.

**Story 10.4 (Rollup Engine):** Added `rollup_metadata` table, established SQL transaction pattern (`BEGIN TRANSACTION` / `COMMIT`). No relevance to outage tracking.

**Story 10.5 (Query APIs):** Established `TimeRange` enum and range-query patterns. The `getOutagePeriods(from:to:)` method uses `Date?` parameters instead of `TimeRange` since outage queries need precise boundaries for chart overlay rendering.

**Story 5.4 (API Connectivity Notifications):** Direct predecessor. Established the 2-consecutive-failure threshold and outage/recovery notification pattern in `NotificationService`. Story 10.6 mirrors this threshold for persistence. The notification identifier patterns (`"api-outage"`, `"api-recovered"`) and guard checks (`isAuthorized`, `apiStatusAlertsEnabled`) are notification-specific and NOT needed in the persistence layer.

### Code Review Findings from Previous Stories

- **SQLITE_TRANSIENT memory safety** (Story 10.1): Always use the `SQLITE_TRANSIENT` constant for text binding, not `SQLITE_STATIC`
- **Thread safety** (Story 10.1): DatabaseManager uses `NSLock` internally — callers don't need their own locking
- **Fire-and-forget Tasks** (Story 10.2): Use `Task { ... }` for persistence calls from PollingEngine to avoid blocking the poll cycle
- **Test cleanup** (Story 10.1): Always `closeConnection()` before deleting test DB files

### References

- [Source: `_bmad-output/planning-artifacts/epics/epic-10-data-persistence-historical-storage-phase-3.md` — Story 10.6 AC and schema]
- [Source: `_bmad-output/planning-artifacts/sprint-change-proposal-2026-03-02.md` — Change 2: API Downtime Awareness]
- [Source: `_bmad-output/implementation-artifacts/5-4-api-connectivity-notifications.md` — Outage/recovery state machine reference]
- [Source: `cc-hdrm/Services/DatabaseManager.swift` — Migration pattern, schema version 5]
- [Source: `cc-hdrm/Services/HistoricalDataService.swift` — Persistence patterns, graceful degradation]
- [Source: `cc-hdrm/Services/HistoricalDataServiceProtocol.swift` — Protocol extension point]
- [Source: `cc-hdrm/Services/PollingEngine.swift` — evaluateConnectivity call sites (lines 219, 295, 312, 321, 330, 339)]
- [Source: `cc-hdrm/Services/NotificationService.swift` — Connectivity state machine (lines 222-248)]
- [Source: `cc-hdrm/Models/AppError.swift` — Error type mapping for failure reasons]
- [Source: `cc-hdrmTests/Mocks/MockHistoricalDataService.swift` — Mock update template]
- [Source: `cc-hdrmTests/Services/DatabaseManagerTests.swift` — Test pattern with temp DB]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- Build error: `SQLITE_TRANSIENT` not accessible from HistoricalDataService — fixed by using `Self.SQLITE_TRANSIENT` (class already has a `private static let` for it)
- Build error: `PreviewHistoricalDataService` in AnalyticsView.swift needed new protocol methods — added stubs

### Completion Notes List

- Implemented database migration v5→v6 with `api_outages` table (INTEGER Unix ms timestamps, consistent with all existing tables)
- Created `OutagePeriod` model with `Sendable`, `Equatable` conformance and computed Date properties
- Added 4 new protocol methods to `HistoricalDataServiceProtocol`: `evaluateOutageState`, `getOutagePeriods`, `closeOpenOutages`, `loadOutageState`
- Implemented outage state machine in HistoricalDataService with 2-failure threshold, independent from NotificationService's connectivity tracking
- Integrated outage evaluation into all 6 PollingEngine error paths (networkUnreachable, httpError, parseError, unknown, non-AppError catch, success) using fire-and-forget Tasks
- 401 errors correctly excluded from outage tracking (API reachable, auth issue)
- App startup restores outage state from DB before polling starts, enabling natural AC 3/4 handling
- Updated MockHistoricalDataService, PEMockHistoricalDataService, and PreviewHistoricalDataService for protocol conformance
- Updated existing DatabaseManager tests to expect schema version 6 (was 5)
- 32 new tests across 4 test suites; full regression suite: 1315 tests, 0 failures

### Senior Developer Review (AI)

**Reviewer:** Claude Opus 4.6 (adversarial code review)
**Date:** 2026-03-03
**Outcome:** Changes Requested → All Fixed

**Findings (7 total: 2 High, 3 Medium, 2 Low):**

- [x] [AI-Review][HIGH] `clearAllData()` did not include `api_outages` table — user's "Clear History" left outage data behind. **Fixed:** Added `"api_outages"` to tables array.
- [x] [AI-Review][HIGH] `pruneOldData()` had no retention pruning for `api_outages` — records would accumulate unboundedly. **Fixed:** Added DELETE for closed outage records older than retention cutoff (ongoing outages preserved).
- [x] [AI-Review][MEDIUM] `closeOpenOutages` is unused in production code (recovery handled inline by `evaluateOutageState`). **Fixed:** Added doc comment noting it's retained for Story 13.8 (outage background rendering).
- [x] [AI-Review][MEDIUM] Thread safety documentation inaccuracy — Dev Notes claimed sequential calls but fire-and-forget Tasks create unstructured concurrency. **Fixed:** Added thread safety comment documenting the actual concurrency model and why it's safe.
- [x] [AI-Review][MEDIUM] `evaluateOutageState` reset in-memory state unconditionally on recovery even if DB update failed, creating state/DB inconsistency. **Fixed:** State reset now conditional on successful DB close; failures keep `outageActive=true` for retry on next success.
- [x] [AI-Review][LOW] Missing test for `loadOutageState` with no open outages. **Fixed:** Added test verifying closed records don't activate outage state.
- [ ] [AI-Review][LOW] Timing-based test assertions for fire-and-forget Tasks (100ms sleep). Accepted — consistent with existing codebase pattern, practically reliable.

**Post-fix test results:** 1316 tests, 0 failures (1 new test added by review)

### Change Log

- 2026-03-03: Story 10.6 implemented — API outage period tracking and persistence
- 2026-03-03: Code review — 6 of 7 findings fixed (clearAllData, pruneOldData, evaluateOutageState state reset, thread safety docs, test gap)

### File List

New files:
- `cc-hdrm/Models/OutagePeriod.swift`
- `cc-hdrmTests/Models/OutagePeriodTests.swift`
- `cc-hdrmTests/Services/OutageTrackingTests.swift`

Modified files:
- `cc-hdrm/Services/DatabaseManager.swift` (schema v6, migration, createApiOutagesTable)
- `cc-hdrm/Services/HistoricalDataService.swift` (outage state machine, 4 new methods)
- `cc-hdrm/Services/HistoricalDataServiceProtocol.swift` (4 new protocol methods)
- `cc-hdrm/Services/PollingEngine.swift` (evaluateOutageState calls at 6 sites)
- `cc-hdrm/App/AppDelegate.swift` (loadOutageState on startup)
- `cc-hdrm/Views/AnalyticsView.swift` (PreviewHistoricalDataService protocol stubs)
- `cc-hdrmTests/Mocks/MockHistoricalDataService.swift` (new mock methods)
- `cc-hdrmTests/Services/PollingEngineTests.swift` (PEMock update + 5 new tests)
- `cc-hdrmTests/Services/DatabaseManagerTests.swift` (schema version 5→6 in assertions)
