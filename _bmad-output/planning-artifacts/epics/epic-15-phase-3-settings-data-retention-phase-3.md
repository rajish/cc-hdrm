# Epic 15: Phase 3 Settings & Data Retention (Phase 3)

Alex configures how long cc-hdrm keeps historical data and optionally overrides credit limits for unknown subscription tiers.

## Story 15.1: Data Retention Configuration

As a developer using Claude Code,
I want to configure how long cc-hdrm retains historical data,
So that I can balance storage usage with analytical depth.

**Acceptance Criteria:**

**Given** the settings view is open (from Epic 6)
**When** SettingsView renders
**Then** a new "Historical Data" section appears with:

- Data retention: picker with options: 30 days, 90 days, 6 months, 1 year (default), 2 years, 5 years
- Database size: read-only display showing current size (e.g., "14.2 MB")
- "Clear History" button

**Given** Alex changes the retention period
**When** the value is saved to PreferencesManager
**Then** the next rollup cycle prunes data older than the new retention period

**Given** Alex clicks "Clear History"
**When** confirmation dialog appears and Alex confirms
**Then** all tables are truncated (usage_polls, usage_rollups, reset_events)
**And** the database is vacuumed to reclaim space
**And** sparkline and analytics show empty state until new data is collected

**Given** the database exceeds a reasonable size (e.g., 500 MB)
**When** the settings view opens
**Then** the database size is displayed with warning color
**And** a hint suggests reducing retention or clearing history

## Story 15.2: Custom Credit Limit Override

As a developer using Claude Code,
I want to manually set credit limits for unknown tiers,
So that headroom analysis works even if Anthropic introduces new tiers.

**Acceptance Criteria:**

**Given** the settings view is open
**When** SettingsView renders
**Then** an "Advanced" section appears (collapsed by default) with:

- Custom 5h credit limit: optional number field
- Custom 7d credit limit: optional number field
- Hint text: "Override credit limits if your tier isn't recognized"

**Given** Alex enters custom credit limits
**When** the values are saved to PreferencesManager
**Then** HeadroomAnalysisService uses the custom limits instead of tier lookup

**Given** custom limits are set AND tier is recognized
**When** HeadroomAnalysisService needs limits
**Then** tier lookup values take precedence (custom limits are fallback only)

**Given** invalid values are entered (e.g., negative numbers, zero)
**When** validation runs
**Then** the invalid values are rejected with inline error message
**And** previous valid values are retained
