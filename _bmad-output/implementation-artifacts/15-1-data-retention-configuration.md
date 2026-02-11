# Story 15.1: Data Retention Configuration

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to configure how long cc-hdrm retains historical data,
so that I can balance storage usage with analytical depth.

## Acceptance Criteria

1. **Given** the settings view is open (from Epic 6)
   **When** SettingsView renders
   **Then** a new "Historical Data" section appears below the existing settings (above Reset to Defaults) with:
   - Data retention: picker with options: 30 days, 90 days, 6 months, 1 year (default), 2 years, 5 years
   - Database size: read-only display showing current size (e.g., "14.2 MB")
   - "Clear History" button

2. **Given** Alex changes the retention period
   **When** the value is saved to PreferencesManager
   **Then** the next rollup cycle prunes data older than the new retention period

3. **Given** Alex clicks "Clear History"
   **When** confirmation dialog appears and Alex confirms
   **Then** all tables are truncated (usage_polls, usage_rollups, reset_events)
   **And** the database is vacuumed to reclaim space
   **And** sparkline and analytics show empty state until new data is collected

4. **Given** the database exceeds a reasonable size (e.g., 500 MB)
   **When** the settings view opens
   **Then** the database size is displayed with warning color
   **And** a hint suggests reducing retention or clearing history

## Tasks / Subtasks

- [x] Task 1: Add `dataRetentionDays` preference (AC: 2)
  - [x] 1.1 Add `dataRetentionDays` to `PreferencesManagerProtocol` (`cc-hdrm/Services/PreferencesManagerProtocol.swift:13`)
  - [x] 1.2 Add `com.cc-hdrm.dataRetentionDays` key to `PreferencesManager.Keys` enum (`cc-hdrm/Services/PreferencesManager.swift:14`)
  - [x] 1.3 Implement getter/setter with default 365, clamp to valid range 30...1825
  - [x] 1.4 Add to `resetToDefaults()` method (`cc-hdrm/Services/PreferencesManager.swift:183`)
  - [x] 1.5 Add `PreferencesDefaults.dataRetentionDays = 365` to defaults enum (`cc-hdrm/Services/PreferencesManagerProtocol.swift:4`)

- [x] Task 2: Wire retention preference into rollup engine (AC: 2)
  - [x] 2.1 In `HistoricalDataService.ensureRollupsUpToDate()` (`cc-hdrm/Services/HistoricalDataService.swift:715`), replace hardcoded `Self.defaultRetentionDays` with `preferencesManager?.dataRetentionDays ?? Self.defaultRetentionDays`
  - [x] 2.2 Verify `preferencesManager` is already injected into `HistoricalDataService` (it is, at `cc-hdrm/Services/HistoricalDataService.swift:10`)

- [x] Task 3: Add `clearAllData()` method (AC: 3)
  - [x] 3.1 Add `clearAllData() async throws` to `HistoricalDataServiceProtocol` (`cc-hdrm/Services/HistoricalDataServiceProtocol.swift`)
  - [x] 3.2 Implement in `HistoricalDataService`: DELETE all rows from `usage_polls`, `usage_rollups`, `reset_events`
  - [x] 3.3 Reset `rollup_metadata` last_rollup_timestamp to nil (DELETE FROM rollup_metadata)
  - [x] 3.4 Execute `VACUUM` on the connection to reclaim disk space
  - [x] 3.5 Log the operation at `.info` level

- [x] Task 4: Thread `HistoricalDataService` and clear callback through view hierarchy (AC: 1, 3)
  - [x] 4.1 Add `historicalDataService: (any HistoricalDataServiceProtocol)?` parameter to `SettingsView` init (`cc-hdrm/Views/SettingsView.swift:20`)
  - [x] 4.2 Add `onClearHistory: (() -> Void)?` callback to `SettingsView` for sparkline clearing
  - [x] 4.3 Thread `historicalDataService` through `GearMenuView` (`cc-hdrm/Views/GearMenuView.swift:10`)
  - [x] 4.4 Thread `historicalDataService` through `PopoverFooterView` (`cc-hdrm/Views/PopoverFooterView.swift`)
  - [x] 4.5 Thread `historicalDataService` from `PopoverView` down (check where PopoverView gets its services)
  - [x] 4.6 Thread `onClearHistory` callback from PopoverView (or AppDelegate) to clear `appState.sparklineData`

- [x] Task 5: Add "Historical Data" section to SettingsView (AC: 1, 4)
  - [x] 5.1 Add `@State private var databaseSizeBytes: Int64 = 0` for async size loading
  - [x] 5.2 Add `@State private var dataRetentionDays: Int` initialized from `preferencesManager.dataRetentionDays`
  - [x] 5.3 Add `@State private var showClearConfirmation = false` for alert state
  - [x] 5.4 Add `@State private var isClearing = false` for loading state during clear operation
  - [x] 5.5 Add a Divider and "Historical Data" section header (`.font(.subheadline)`)
  - [x] 5.6 Add retention Picker with discrete options: `[30, 90, 180, 365, 730, 1825]` days, display labels: "30 days", "90 days", "6 months", "1 year", "2 years", "5 years"
  - [x] 5.7 Wire picker `.onChange` to write `preferencesManager.dataRetentionDays`
  - [x] 5.8 Add database size HStack: `Text("Database size")` + `Spacer()` + formatted size text
  - [x] 5.9 Format size: bytes -> KB/MB/GB with 1 decimal (use `ByteCountFormatter`)
  - [x] 5.10 Apply `.headroomWarning` foreground color when size > 500 MB (524,288,000 bytes)
  - [x] 5.11 Add hint text when > 500 MB: `"Consider reducing retention or clearing history"` with `.font(.caption)` and `.foregroundStyle(.secondary)`
  - [x] 5.12 Add "Clear History..." button centered, styled to indicate destructive action
  - [x] 5.13 Load database size on `.task { }` modifier (async on appear)
  - [x] 5.14 Add accessibility labels to all new controls

- [x] Task 6: Add Clear History confirmation dialog (AC: 3)
  - [x] 6.1 Add `.alert("Clear History?", isPresented: $showClearConfirmation)` to the view
  - [x] 6.2 Alert message: "This will permanently delete all historical usage data. Sparkline and analytics will show empty until new data is collected."
  - [x] 6.3 Destructive "Clear" button: calls `clearAllData()`, then `onClearHistory?()`, then refreshes database size
  - [x] 6.4 Cancel button dismisses
  - [x] 6.5 Show progress or disable button while `isClearing` is true
  - [x] 6.6 After clear, refresh `databaseSizeBytes` to show updated (smaller) size

- [x] Task 7: Update mocks for new protocol method (AC: 1, 2, 3)
  - [x] 7.1 Add `clearAllData()` to `MockHistoricalDataService` (`cc-hdrmTests/Mocks/MockHistoricalDataService.swift`)
  - [x] 7.2 Add `clearAllData()` to `PEMockHistoricalDataService` in `PollingEngineTests` (`cc-hdrmTests/Services/PollingEngineTests.swift:150`)
  - [x] 7.3 Add `clearAllData()` to `AnalyticsView` preview mock (`cc-hdrm/Views/AnalyticsView.swift:380`)
  - [x] 7.4 Add `dataRetentionDays` to any mock `PreferencesManager` if used in tests

- [x] Task 8: Write tests (AC: 1, 2, 3, 4)
  - [x] 8.1 Test `PreferencesManager.dataRetentionDays` default is 365
  - [x] 8.2 Test `dataRetentionDays` setter clamps to 30...1825 range
  - [x] 8.3 Test `resetToDefaults()` resets `dataRetentionDays` to 365
  - [x] 8.4 Test `clearAllData()` empties all three tables
  - [x] 8.5 Test `clearAllData()` resets rollup_metadata
  - [x] 8.6 Test database size decreases after `clearAllData()` (VACUUM reclaims space)
  - [x] 8.7 Test `ensureRollupsUpToDate()` uses preference-based retention instead of hardcoded
  - [x] 8.8 Test SettingsView renders "Historical Data" section with retention picker

## Dev Notes

### Architecture Context

This story adds the first user-configurable data management feature. The existing infrastructure is mature:

- **`HistoricalDataService`** already has `pruneOldData(retentionDays:)` and `getDatabaseSize()` methods fully implemented
- **`PreferencesManager`** pattern is well established with `Keys` enum, getter/setter with clamping, and `resetToDefaults()`
- **`SettingsView`** is a compact popover-based view (280px wide) with steppers, pickers, toggles, and a reset button
- The rollup engine in `ensureRollupsUpToDate()` already calls `pruneOldData()` as its final step (line 715) but uses a hardcoded 90-day default

### Key Integration Points

**Retention wiring (minimal change):**
The critical code change is at `cc-hdrm/Services/HistoricalDataService.swift:715`:
```swift
// BEFORE (hardcoded):
try await performPruneOldData(retentionDays: Self.defaultRetentionDays, connection: connection)

// AFTER (preference-driven):
let retention = preferencesManager?.dataRetentionDays ?? Self.defaultRetentionDays
try await performPruneOldData(retentionDays: retention, connection: connection)
```

**Clear History implementation:**
SQLite `DELETE FROM` + `VACUUM` pattern. VACUUM rewrites the database file to reclaim freed pages. Must be executed outside a transaction (SQLite requirement).

```swift
func clearAllData() async throws {
    guard databaseManager.isAvailable else { return }
    let connection = try databaseManager.getConnection()
    // Delete all data
    sqlite3_exec(connection, "DELETE FROM usage_polls", nil, nil, nil)
    sqlite3_exec(connection, "DELETE FROM usage_rollups", nil, nil, nil)
    sqlite3_exec(connection, "DELETE FROM reset_events", nil, nil, nil)
    sqlite3_exec(connection, "DELETE FROM rollup_metadata", nil, nil, nil)
    // VACUUM must run outside transaction
    sqlite3_exec(connection, "VACUUM", nil, nil, nil)
}
```

**View hierarchy threading:**
The service dependency chain for SettingsView is:
`PopoverView` -> `PopoverFooterView` -> `GearMenuView` -> `SettingsView`

All three intermediate views need the `historicalDataService` parameter added. Follow the existing pattern of passing `preferencesManager` and `launchAtLoginService` through these views.

For sparkline clearing, use a callback `onClearHistory: (() -> Void)?` threaded from PopoverView (which has access to AppState) down to SettingsView.

### Retention Picker Options

| Display Label | Days Value | Notes |
|---|---|---|
| 30 days | 30 | Minimum retention |
| 90 days | 90 | Current hardcoded default |
| 6 months | 180 | |
| 1 year | 365 | New default per epic spec |
| 2 years | 730 | |
| 5 years | 1825 | Maximum retention |

### Database Size Formatting

Use `ByteCountFormatter` for platform-consistent formatting:
```swift
private func formatSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
```

Warning threshold: 500 MB = 524,288,000 bytes. Use `.headroomWarning` color from the existing `Color+Headroom.swift` asset catalog.

### Important: VACUUM Constraint

SQLite `VACUUM` cannot run inside a transaction. The `clearAllData()` method must NOT wrap its operations in `BEGIN TRANSACTION / COMMIT`. Use individual `DELETE FROM` statements followed by `VACUUM` at the end.

### Existing `defaultRetentionDays`

`HistoricalDataService` has `private static let defaultRetentionDays: Int = 90` at line 620. This should remain as a fallback but the preference value should take precedence. The epic spec says the default should be 1 year (365 days), which will be the `PreferencesDefaults.dataRetentionDays` value.

### Potential Pitfalls

1. **macOS `.alert()` in popover**: SwiftUI `.alert()` may not present correctly inside a `.popover()` on macOS. If the confirmation dialog fails to appear, move it to the `.popover()` level in `GearMenuView` or use a `confirmationDialog` modifier instead.

2. **VACUUM blocks the connection**: `VACUUM` rewrites the entire database file and blocks all other operations. For very large databases this could take noticeable time. The `isClearing` state in SettingsView handles this, but the UI must remain responsive (run on a background task, not main thread).

3. **`resetToDefaults()` scope**: The existing `resetToDefaults()` should reset `dataRetentionDays` to 365 but should NOT clear historical data. Retention preference reset != data deletion. These are separate user actions.

4. **Race with PollingEngine**: While `clearAllData()` is running, a poll cycle could insert new data. This is acceptable -- the clear deletes existing data, and the next poll adds fresh data naturally. No lock coordination needed.

5. **`@State` init from protocol property**: Follow the existing pattern at `cc-hdrm/Views/SettingsView.swift:25-29` -- initialize `@State` in `init()` with `_dataRetentionDays = State(initialValue: preferencesManager.dataRetentionDays)`.

6. **`isUpdating` guard pattern**: All `.onChange` handlers in SettingsView use the `isUpdating` flag to prevent recursive triggers. The new retention picker must follow the same pattern (see lines 49-50 and 72-73 of SettingsView).

### Project Structure Notes

- All changes are within existing files. No new files needed.
- Follows layer-based organization: Services for data logic, Views for UI, no cross-cutting
- `PreferencesManager` remains the ONLY component that touches UserDefaults
- `HistoricalDataService` remains the ONLY component that queries the database
- `DatabaseManager` is not directly modified (VACUUM runs through the existing connection)

### References

- [Source: cc-hdrm/Services/PreferencesManager.swift] - Existing preference key patterns and getter/setter with clamping
- [Source: cc-hdrm/Services/PreferencesManagerProtocol.swift] - Protocol definition and PreferencesDefaults enum
- [Source: cc-hdrm/Services/HistoricalDataService.swift:620] - Hardcoded `defaultRetentionDays = 90`
- [Source: cc-hdrm/Services/HistoricalDataService.swift:715] - Where retention is used in `ensureRollupsUpToDate()`
- [Source: cc-hdrm/Services/HistoricalDataService.swift:234-250] - Existing `getDatabaseSize()` implementation
- [Source: cc-hdrm/Services/HistoricalDataService.swift:745-752] - Existing `pruneOldData()` public method
- [Source: cc-hdrm/Services/HistoricalDataServiceProtocol.swift] - Protocol with existing methods to extend
- [Source: cc-hdrm/Services/DatabaseManager.swift] - Schema (4 tables: usage_polls, usage_rollups, reset_events, rollup_metadata)
- [Source: cc-hdrm/Views/SettingsView.swift] - Current settings layout: steppers, picker, toggle, reset, done
- [Source: cc-hdrm/Views/GearMenuView.swift] - Creates SettingsView with preferencesManager and launchAtLoginService
- [Source: cc-hdrm/Views/PopoverFooterView.swift:29] - Creates GearMenuView, needs historicalDataService passed through
- [Source: cc-hdrm/State/AppState.swift:58] - `sparklineData` property and `updateSparklineData()` method (line 224)
- [Source: cc-hdrmTests/Mocks/MockHistoricalDataService.swift:85] - Mock getDatabaseSize, needs clearAllData added
- [Source: cc-hdrmTests/Services/PollingEngineTests.swift:150] - PEMockHistoricalDataService needs clearAllData
- [Source: cc-hdrm/Views/AnalyticsView.swift:380] - Preview mock needs clearAllData
- [Source: _bmad-output/planning-artifacts/epics/epic-15-phase-3-settings-data-retention-phase-3.md] - Epic definition
- [Source: _bmad-output/planning-artifacts/project-context.md] - Tech stack and architectural patterns

## Change Log

- 2026-02-11: Implemented all 8 tasks for Story 15.1 Data Retention Configuration. Added `dataRetentionDays` preference with clamping (30-1825 days, default 365), wired into rollup engine pruning. Implemented `clearAllData()` with VACUUM. Added "Historical Data" section to SettingsView with retention picker, database size display, 500MB warning, and Clear History confirmation dialog. Threaded `historicalDataService` and `onClearHistory` through full view hierarchy. Updated all 4 protocol conformances. Added 16 new tests (888 total, all pass).
- 2026-02-11: Code review fixes: (1) clearAllData now checks sqlite3_exec return codes and throws on DELETE failure, VACUUM failure is non-fatal warning. (2) SettingsView uses do/catch for clearAllData — skips onClearHistory on failure so sparkline isn't incorrectly cleared. (3) onClearHistory closes AnalyticsWindow so it reloads fresh on reopen (AC 3 analytics empty state). (4) Fixed clearAllDataEmptiesAllTables test: corrected usage_rollups column names and added rollup count verification. (5) Added clearAllData graceful degradation test. 889 tests, all pass.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (claude-opus-4-6)

### Debug Log References

- VACUUM test initially failed with 100 rows (database didn't grow beyond minimum page allocation). Fixed by inserting 1500 rows across multiple tables.
- GearMenuView test compilation failure due to `let` optional property not providing default in synthesized memberwise init. Fixed by changing to `var` for optional service/callback properties.
- AppDelegate PopoverView creation was before HistoricalDataService creation. Reordered to create services first, then PopoverView, so `historicalDataServiceRef` is available for injection.

### Completion Notes List

- Task 1: Added `dataRetentionDays` to PreferencesDefaults (365), PreferencesManagerProtocol, PreferencesManager.Keys, getter/setter with 30...1825 clamping, resetToDefaults()
- Task 2: Replaced hardcoded `Self.defaultRetentionDays` with `preferencesManager?.dataRetentionDays ?? Self.defaultRetentionDays` in ensureRollupsUpToDate()
- Task 3: Added `clearAllData()` to protocol and implementation — DELETEs from 4 tables + VACUUM, with graceful degradation and info logging
- Task 4: Threaded `historicalDataService` (optional) and `onClearHistory` callback through PopoverView -> PopoverFooterView -> GearMenuView -> SettingsView. Wired in AppDelegate with `appState.updateSparklineData([])` callback
- Task 5: Full "Historical Data" section in SettingsView: retention picker (6 options), database size display with ByteCountFormatter, 500MB warning color + hint, Clear History button, .task database size loading, accessibility labels
- Task 6: Alert confirmation dialog with destructive Clear button calling clearAllData() + onClearHistory() + size refresh, disabled while isClearing
- Task 7: Updated MockHistoricalDataService, PEMockHistoricalDataService, PreviewHistoricalDataService, MockPreferencesManager with new protocol methods
- Task 8: 16 new tests — 7 PreferencesManager (default, clamping, persistence, reset), 5 HistoricalDataService (clearAllData empties tables, resets metadata, VACUUM shrinks, preference retention prune/keep), 3 SettingsView (renders with service, formatSize, retentionLabel), 1 existing resetToDefaults test expanded

### File List

- cc-hdrm/Services/PreferencesManagerProtocol.swift (modified: added dataRetentionDays to protocol and PreferencesDefaults)
- cc-hdrm/Services/PreferencesManager.swift (modified: added Keys.dataRetentionDays, getter/setter with clamping, resetToDefaults)
- cc-hdrm/Services/HistoricalDataServiceProtocol.swift (modified: added clearAllData() method)
- cc-hdrm/Services/HistoricalDataService.swift (modified: added clearAllData() implementation, preference-based retention in ensureRollupsUpToDate)
- cc-hdrm/Views/SettingsView.swift (modified: added Historical Data section with retention picker, database size, clear history)
- cc-hdrm/Views/GearMenuView.swift (modified: threaded historicalDataService and onClearHistory)
- cc-hdrm/Views/PopoverFooterView.swift (modified: threaded historicalDataService and onClearHistory)
- cc-hdrm/Views/PopoverView.swift (modified: threaded historicalDataService and onClearHistory)
- cc-hdrm/Views/AnalyticsView.swift (modified: added clearAllData to preview mock)
- cc-hdrm/App/AppDelegate.swift (modified: reordered popover creation after services, wired historicalDataService and onClearHistory)
- cc-hdrmTests/Mocks/MockPreferencesManager.swift (modified: added dataRetentionDays property and reset)
- cc-hdrmTests/Mocks/MockHistoricalDataService.swift (modified: added clearAllData mock)
- cc-hdrmTests/Services/PollingEngineTests.swift (modified: added clearAllData to PEMockHistoricalDataService)
- cc-hdrmTests/Services/PreferencesManagerTests.swift (modified: added 7 dataRetentionDays tests, expanded resetToDefaults test)
- cc-hdrmTests/Services/HistoricalDataServiceTests.swift (modified: added 5 tests for clearAllData and preference-based retention)
- cc-hdrmTests/Views/SettingsViewTests.swift (modified: added 3 tests for Historical Data section rendering)
