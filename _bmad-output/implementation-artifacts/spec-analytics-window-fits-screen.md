---
title: 'Keep the analytics window inside the screen'
type: 'bugfix'
created: '2026-11-02'
status: 'done'
baseline_commit: '249807cc60aa7f652db44293e408da39065f6f15'
review_loop_iteration: 0
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** During the 1.7.0 trial the Analytics window ran off the bottom of the screen. Its content has no scrolling and the window grows to fit it, so macOS saved a height of 2,227 points on a 2,160-point screen, with its lower 92 points below the screen's edge.

**Approach:** Stop the content from growing the window, scroll everything below the range controls, and pull any saved oversized or off-screen position back inside the screen when the window is created.

## Boundaries & Constraints

**Always:** The fix applies to all accounts. The title bar, range controls and legend stay visible while scrolling. The user can still resize the window and the app still remembers size and position. The main chart keeps a usable height and still grows with a bigger window.

**Ask First:** Any change to what the sections show, or to their order.

**Never:** No change to chart data, hiding rules or section contents. No edit to `cc-hdrm/cc_hdrm.entitlements`. No deleting of the saved frame from user defaults.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Frame fits | Saved frame inside the visible screen | Unchanged | N/A |
| Too tall | Saved frame taller than the visible screen | Height reduced to the visible height, fully on screen | Logged at info level |
| Too wide | Saved frame wider than the visible screen | Width reduced to the visible width, fully on screen | Logged at info level |
| Below or beside the screen | Size fits, origin outside the screen | Moved inside, size unchanged | Logged at info level |
| No screen known | No window screen and no main screen | Frame left as restored | N/A |

</frozen-after-approval>

## Code Map

- `cc-hdrm/Views/AnalyticsWindow.swift:110-142` -- `createPanel()`: builds the panel, restores the frame with `setFrameAutosaveName`, and assigns a default `NSHostingView`, whose default sizing options let content resize the window.
- `cc-hdrm/Views/OnboardingWindowController.swift:43-45` -- existing use of `sizingOptions` on a hosting view.
- `cc-hdrm/Views/AnalyticsView.swift:150-185` -- `body`: a plain `VStack` of title bar, controls, legend, `UsageChart`, `valueSection`, benchmark and tokens-per-percent sections, with no scroll view.
- `cc-hdrm/Views/UsageChart.swift:43` -- `maxHeight: .infinity`: would collapse to its ideal height inside a scroll view, so it needs a height from the caller.
- `cc-hdrm/Views/TPPTrendChartView.swift:54` -- `minHeight: 180`: holds its height inside a scroll view, no change needed.
- `cc-hdrmTests/Views/AnalyticsWindowTests.swift` -- Swift Testing suite for the window; add the frame cases here.

## Tasks & Acceptance

**Execution:**
- [x] `cc-hdrm/Views/AnalyticsWindow.swift` -- Set the hosting view's `sizingOptions` to `[.minSize]`. After the frame is restored, apply a new pure `static func fitted(_ frame: NSRect, in visible: NSRect) -> NSRect` against the screen's `visibleFrame`, logging when it changes the frame -- content can no longer grow the window, and frames already saved too large recover.
- [x] `cc-hdrm/Views/AnalyticsView.swift` -- Wrap everything below `outageLegend` in a vertical `ScrollView`. Size `UsageChart` with `containerRelativeFrame(.vertical)`, at least 280 points and otherwise 60 percent of the scroll area -- the sections stay reachable and the chart keeps a usable height.
- [x] `cc-hdrmTests/Views/AnalyticsWindowTests.swift` -- Add one test for each frame row of the matrix -- covers the clamping logic.

**Acceptance Criteria:**
- Given a saved height of 2,227 points on a 2,160-point screen, when the window opens, then all of its edges are on screen.
- Given data that makes the content taller than the window, when the data loads, then the window size does not change and the content scrolls.
- Given a window at its default size, when the user scrolls to the end, then the last section is fully visible.
- Given the user resizes the window and reopens it, when it opens, then the new size and position are restored.

## Spec Change Log

## Design Notes

`[.minSize]` rather than `[]`: it keeps the content's minimum width from being clipped when the window is narrowed. A vertical scroll view reports almost no minimum height, so height can no longer push the window past the screen.

## Verification

**Commands:**
- `/usr/bin/lockf -k /tmp/cchdrm-xcodebuild.lock nice -n 15 xcodebuild -jobs 4 -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test -only-testing:cc-hdrmTests/AnalyticsWindowTests` -- expected: suite passes, with the new cases actually run.

**Manual checks (if no CLI):**
- On the release build, open Analytics with the real saved frame: all edges on screen, title bar reachable, scrolling reaches the last section, main chart readable, window resizable.

## Suggested Review Order

**Window size**

- Content can no longer grow the window, which is the root cause.
  [`AnalyticsWindow.swift:143`](../../cc-hdrm/Views/AnalyticsWindow.swift#L143)

- Gives the window a real minimum, replacing the unused panel minimum.
  [`AnalyticsWindow.swift:141`](../../cc-hdrm/Views/AnalyticsWindow.swift#L141)

- Repairs a saved frame on each open, because the panel is rebuilt every time.
  [`AnalyticsWindow.swift:151`](../../cc-hdrm/Views/AnalyticsWindow.swift#L151)

- Shrinks first, then moves, so every edge ends on screen.
  [`AnalyticsWindow.swift:162`](../../cc-hdrm/Views/AnalyticsWindow.swift#L162)

**Scrolling layout**

- Title bar and controls stay fixed; everything below scrolls.
  [`AnalyticsView.swift:157`](../../cc-hdrm/Views/AnalyticsView.swift#L157)

- The chart needs a height of its own inside a scroll view.
  [`AnalyticsView.swift:171`](../../cc-hdrm/Views/AnalyticsView.swift#L171)

**Tests**

- Opens the real window with an oversized saved frame.
  [`AnalyticsWindowTests.swift:230`](../../cc-hdrmTests/Views/AnalyticsWindowTests.swift#L230)
