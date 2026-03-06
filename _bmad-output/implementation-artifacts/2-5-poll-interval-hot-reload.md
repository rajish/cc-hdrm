# Story 2.5: Poll Interval Hot Reload

Status: done

## Story

As a developer adjusting the poll interval in settings,
I want the new interval to take effect immediately,
so that I don't have to wait for the old (potentially much longer) timer to expire first.

## Acceptance Criteria

1. **Given** the polling engine is running with a 5-minute interval, **When** the user changes the poll interval to 10 seconds in settings, **Then** the next poll fires within 10 seconds of the change (not after the remaining 5-minute sleep).

2. **Given** the polling engine is in exponential backoff (e.g., 600s after rate limiting), **When** the user changes the poll interval, **Then** the backoff state is preserved and the new base interval is used for the next `computeNextInterval()` calculation **And** the current sleep is interrupted so the engine re-evaluates immediately.

3. **Given** the polling engine is stopped (no credentials), **When** the user changes the poll interval, **Then** nothing happens (no crash, no spurious poll).

4. **Given** the user rapidly changes the poll interval multiple times, **When** the settings picker fires onChange repeatedly, **Then** only the final interval value takes effect **And** no duplicate polling tasks are spawned.

## Tasks / Subtasks

- [x] Task 1: Add `restartPolling()` method to PollingEngine (AC: 1, 2, 4)
  - [x] 1.1 In `cc-hdrm/Services/PollingEngineProtocol.swift`: add `func restartPolling()` to the protocol
  - [x] 1.2 In `cc-hdrm/Services/PollingEngine.swift`: implement `restartPolling()` that cancels the existing `pollingTask` and creates a new one with the same while-loop structure as `start()`, but WITHOUT an initial `performPollCycle()` (the data is still fresh from the last poll)
  - [x] 1.3 The new task reads `computeNextInterval()` which already reads `preferencesManager.pollInterval` — so the new interval is picked up automatically
  - [x] 1.4 Guard against calling `restartPolling()` when `pollingTask` is nil (AC 3)

- [x] Task 2: Wire settings change to restart polling (AC: 1, 4)
  - [x] 2.1 In `cc-hdrm/Views/SettingsView.swift`: the `.onChange(of: pollInterval)` handler at line 204 already writes to `preferencesManager.pollInterval` — add a call to restart the polling engine after the write
  - [x] 2.2 Pass a callback closure `onPollIntervalChange: () -> Void` to SettingsView (same pattern as `onThresholdChange` in PopoverView)
  - [x] 2.3 In `cc-hdrm/App/AppDelegate.swift` (or PopoverView where SettingsView is created): wire the callback to call `pollingEngine?.restartPolling()`
  - [x] 2.4 Alternative simpler approach: add `restartPolling()` to `PollingEngineProtocol`, pass the engine reference to SettingsView, and call it directly — evaluate which is cleaner given the existing dependency chain

- [x] Task 3: Write tests (AC: all)
  - [x] 3.1 Test: `restartPolling()` when `pollingTask` is nil does not crash
  - [x] 3.2 Test: `restartPolling()` cancels the old `pollingTask` (verify via `Task.isCancelled`)
  - [x] 3.3 Test: after `restartPolling()`, next interval uses updated `preferencesManager.pollInterval`
  - [x] 3.4 Test: `consecutiveFailureCount` is preserved across `restartPolling()` (backoff not lost)

## Dev Notes

### Root Cause

In `cc-hdrm/Services/PollingEngine.swift` lines 66-75, `start()` creates a `pollingTask` that loops with `Task.sleep(for: .seconds(interval))`. The interval is read at the top of each iteration, but `Task.sleep` is not interruptible by preference changes — it blocks for the full duration. If the user changes from 300s to 10s mid-sleep, the engine won't notice until the 300s sleep completes.

### Recommended Approach

Add a `restartPolling()` method that cancels the current `pollingTask` (which cancels the in-flight `Task.sleep`) and starts a new loop. This is the same stop/start pattern already used in `AppDelegate.performSignIn()` at line 299-301.

Key difference from `start()`: `restartPolling()` should NOT call `performPollCycle()` immediately — the data is still fresh from the last successful poll. It just needs to reset the sleep timer.

### Files to Modify

- `cc-hdrm/Services/PollingEngineProtocol.swift` — add `restartPolling()` to protocol
- `cc-hdrm/Services/PollingEngine.swift` — implement `restartPolling()`
- `cc-hdrm/Views/SettingsView.swift` — trigger restart on interval change
- `cc-hdrm/App/AppDelegate.swift` or `cc-hdrm/Views/PopoverView.swift` — wire the callback (depends on approach chosen in Task 2)

### References

- [Source: cc-hdrm/Services/PollingEngine.swift lines 62-76] — current `start()` / `stop()` with non-interruptible sleep
- [Source: cc-hdrm/Services/PollingEngine.swift lines 91-106] — `computeNextInterval()` already reads live preference
- [Source: cc-hdrm/Views/SettingsView.swift lines 204-209] — poll interval onChange handler
- [Source: cc-hdrm/App/AppDelegate.swift lines 299-301] — existing stop/start pattern after sign-in

## Dev Agent Record

### Agent Model Used

claude-opus-4-6

### Debug Log References

### Completion Notes List

- Task 1: Added `restartPolling()` to `PollingEngineProtocol` and implemented in `PollingEngine`. The method guards against nil `pollingTask` (AC 3), cancels the existing task, and creates a new while-loop that reads `computeNextInterval()` without an immediate `performPollCycle()`. `consecutiveFailureCount` and `retryAfterOverride` are instance properties untouched by restart, so backoff state is preserved (AC 2).
- Task 2: Chose the callback closure approach (subtask 2.2) over direct engine injection (subtask 2.4) because it follows the existing `onThresholdChange` pattern exactly. Threaded `onPollIntervalChange` through AppDelegate -> PopoverView -> (GearMenuView | PopoverFooterView -> GearMenuView) -> SettingsView. Each rapid onChange call cancels the previous pollingTask and creates a new one — only the final interval takes effect (AC 4).
- Task 3: Added 4 unit tests in `PollingEngineRestartTests` suite covering all ACs. Updated `MockPollingEngine` in `AppDelegateTests` to conform to the new protocol requirement.

### File List

- cc-hdrm/Services/PollingEngineProtocol.swift (modified) — added `restartPolling()` to protocol
- cc-hdrm/Services/PollingEngine.swift (modified) — implemented `restartPolling()`, extracted `startPollingLoop()` to deduplicate
- cc-hdrm/Views/SettingsView.swift (modified) — added `onPollIntervalChange` callback, called on poll interval change
- cc-hdrm/Views/GearMenuView.swift (modified) — threaded `onPollIntervalChange` to SettingsView
- cc-hdrm/Views/PopoverView.swift (modified) — threaded `onPollIntervalChange` to GearMenuView and PopoverFooterView
- cc-hdrm/Views/PopoverFooterView.swift (modified) — threaded `onPollIntervalChange` to GearMenuView
- cc-hdrm/App/AppDelegate.swift (modified) — wired `onPollIntervalChange` to `pollingEngine?.restartPolling()`
- cc-hdrmTests/Services/PollingEngineTests.swift (modified) — added `PollingEngineRestartTests` suite (4 tests)
- cc-hdrmTests/App/AppDelegateTests.swift (modified) — updated `MockPollingEngine` with `restartPolling()`
- _bmad-output/implementation-artifacts/sprint-status.yaml (modified) — status: in-progress -> review
- _bmad-output/implementation-artifacts/2-5-poll-interval-hot-reload.md (modified) — story file updates

### Change Log

- 2026-03-06: Implemented poll interval hot reload — `restartPolling()` cancels in-flight `Task.sleep` and starts a new loop with the updated interval. Threaded `onPollIntervalChange` callback through view hierarchy following existing `onThresholdChange` pattern.
- 2026-03-06: Code review fixes — extracted `startPollingLoop()` to eliminate duplicated polling loop (MEDIUM-1), reverted unrelated APIClient.swift rate limit header logging (MEDIUM-2), added interval value to restart log message (LOW-3), strengthened `restartPollingUsesUpdatedInterval` test assertion (LOW-5).
