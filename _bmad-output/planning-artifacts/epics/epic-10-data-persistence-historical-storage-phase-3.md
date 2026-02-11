# Epic 10: Data Persistence & Historical Storage (Phase 3)

Alex's usage data is no longer ephemeral — every poll snapshot is persisted to SQLite, rolled up at decreasing resolution as it ages, creating a permanent record of usage patterns.

## Story 10.1: Database Manager & Schema Creation

As a developer using Claude Code,
I want cc-hdrm to create and manage a SQLite database for historical data,
So that poll snapshots can be persisted reliably across app restarts.

**Acceptance Criteria:**

**Given** the app launches for the first time after Phase 3 upgrade
**When** DatabaseManager initializes
**Then** it creates a SQLite database at `~/Library/Application Support/cc-hdrm/usage.db`
**And** the database contains table `usage_polls` with columns: id (INTEGER PRIMARY KEY), timestamp (INTEGER), five_hour_util (REAL), five_hour_resets_at (INTEGER nullable), seven_day_util (REAL), seven_day_resets_at (INTEGER nullable)
**And** the database contains table `usage_rollups` with columns: id, period_start, period_end, resolution (TEXT), five_hour_avg, five_hour_peak, five_hour_min, seven_day_avg, seven_day_peak, seven_day_min, reset_count, waste_credits
**And** the database contains table `reset_events` with columns: id, timestamp, five_hour_peak, seven_day_util, tier, used_credits, constrained_credits, waste_credits
**And** indexes exist on: usage_polls(timestamp), usage_rollups(resolution, period_start), reset_events(timestamp)
**And** DatabaseManager conforms to DatabaseManagerProtocol for testability

**Given** the app launches on subsequent runs
**When** DatabaseManager initializes
**Then** it opens the existing database without recreating tables
**And** schema version is tracked for future migrations

**Given** the database file is corrupted or inaccessible
**When** DatabaseManager attempts to open
**Then** the error is logged via os.Logger (database category)
**And** the app continues functioning without historical features (graceful degradation)
**And** real-time usage display continues working normally

## Story 10.2: Historical Data Service & Poll Persistence

As a developer using Claude Code,
I want each poll snapshot to be automatically persisted,
So that I build a historical record without any manual action.

**Acceptance Criteria:**

**Given** a successful poll cycle completes with valid usage data
**When** PollingEngine receives the UsageResponse
**Then** HistoricalDataService.persistPoll() is called with the response data
**And** a new row is inserted into usage_polls with current timestamp and utilization values
**And** persistence happens asynchronously (does not block UI updates)
**And** HistoricalDataService conforms to HistoricalDataServiceProtocol for testability

**Given** the database write fails
**When** persistPoll() encounters an error
**Then** the error is logged via os.Logger
**And** the poll cycle is not retried (data for this cycle is lost)
**And** the app continues functioning — subsequent polls attempt persistence normally

**Given** the app has been running for 24+ hours
**When** the database is inspected
**Then** it contains one row per successful poll (~1440 rows for 30-second intervals over 24h)
**And** no duplicate timestamps exist

## Story 10.3: Reset Event Detection

As a developer using Claude Code,
I want cc-hdrm to detect when a 5h window resets,
So that headroom analysis can be performed at each reset boundary.

**Acceptance Criteria:**

**Given** two consecutive polls where the second poll's `five_hour_resets_at` differs from the first
**When** HistoricalDataService detects this shift
**Then** a new row is inserted into reset_events with the pre-reset peak utilization and current 7d utilization
**And** the tier from KeychainCredentials is recorded

**Given** `five_hour_resets_at` is null or missing in the API response
**When** HistoricalDataService detects a large utilization drop (e.g., 80% → 2%)
**Then** it infers a reset event occurred (fallback detection)
**And** logs the inferred reset via os.Logger (info level)

**Given** a reset event is detected
**When** the event is recorded
**Then** used_credits, constrained_credits, and waste_credits are calculated per the headroom analysis math (deferred to Epic 14 for full calculation)
**And** if credit limits are unknown for the tier, the credit fields are set to null

## Story 10.4: Tiered Rollup Engine

As a developer using Claude Code,
I want historical data to be rolled up at decreasing resolution as it ages,
So that storage remains efficient while preserving analytical value.

**Acceptance Criteria:**

**Given** usage_polls contains data older than 24 hours
**When** HistoricalDataService.ensureRollupsUpToDate() is called
**Then** raw polls from 24h-7d ago are aggregated into 5-minute rollups
**And** each rollup row contains: period_start, period_end, resolution='5min', avg/peak/min for both windows
**And** original raw polls older than 24h are deleted after rollup
**And** a metadata record tracks last_rollup_timestamp

**Given** usage_rollups contains 5-minute data older than 7 days
**When** ensureRollupsUpToDate() processes that data
**Then** 5-minute rollups from 7-30 days ago are aggregated into hourly rollups
**And** original 5-minute rollups older than 7 days are deleted after aggregation

**Given** usage_rollups contains hourly data older than 30 days
**When** ensureRollupsUpToDate() processes that data
**Then** hourly rollups from 30+ days ago are aggregated into daily summaries
**And** daily summaries include: avg utilization, peak utilization, min utilization, calculated waste %
**And** original hourly rollups older than 30 days are deleted

**Given** the analytics window opens
**When** the view loads
**Then** ensureRollupsUpToDate() is called before querying data
**And** rollup processing completes within 100ms for a typical day's data
**And** rollups are performed on-demand (not on a background timer)

## Story 10.5: Data Query APIs

As a developer using Claude Code,
I want to query historical data at the appropriate resolution for different time ranges,
So that analytics views can display relevant data efficiently.

**Acceptance Criteria:**

**Given** a request for the last 24 hours of data
**When** HistoricalDataService.getRecentPolls(hours: 24) is called
**Then** it returns raw poll data from usage_polls ordered by timestamp
**And** the result includes all fields needed for sparkline and chart rendering

**Given** a request for 7-day data
**When** HistoricalDataService.getRolledUpData(range: .week) is called
**Then** it returns 5-minute rollups for the 1-7 day range combined with raw data for <24h
**And** data is seamlessly stitched (no visible boundary between raw and rolled data)

**Given** a request for 30-day or all-time data
**When** getRolledUpData() is called with the appropriate range
**Then** it returns the correctly tiered data (daily for 30+ days, hourly for 7-30 days, etc.)

**Given** a request for reset events in a time range
**When** HistoricalDataService.getResetEvents(range:) is called
**Then** it returns all reset_events rows within the specified range
**And** results are ordered by timestamp ascending
