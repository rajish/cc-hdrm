---
stepsCompleted: [1, 2, 3, 4, 5]
inputDocuments:
  - _bmad-output/implementation-artifacts/tech-spec-claude-usage-monitor.md
date: 2026-01-30
author: Boss
projectName: cc-hdrm
---

# Product Brief: cc-hdrm

## Executive Summary

cc-hdrm is a macOS menu bar utility that gives Claude Pro/Max subscribers always-visible, glanceable usage data -- like iStat Menus for your Claude subscription. Developers using Claude through coding agents (CLI, TUI, Desktop) currently have no passive way to monitor their usage limits, leading to unexpected mid-task cutoffs and constant anxiety about remaining capacity. cc-hdrm solves this by polling the Claude usage API in the background and displaying live usage bars, reset countdowns, and color-coded warnings directly in the macOS menu bar -- zero tokens spent, zero workflow interruption.

---

## Core Vision

### Problem Statement

Developers on Claude Pro/Max plans who work through coding agents (Claude Code CLI, OpenCode TUI, OpenCode Desktop) have no passive, glanceable way to monitor their subscription usage. The only options -- the `/usage` slash command, the claude.ai web dashboard, or the claude-counter browser extension -- all require active interruption of the developer's workflow.

### Problem Impact

Power users frequently hit usage limits and get **cut off mid-task**, losing momentum, context, and flow state. Worse, the lack of visibility creates persistent **anxiety** -- developers can't pace their work because they don't know where they stand. Every deep coding session carries the risk of an abrupt, unwarned stop.

### Why Existing Solutions Fall Short

| Solution                 | Limitation                                                  |
| ------------------------ | ----------------------------------------------------------- |
| `/usage` slash command     | Costs tokens, requires typing mid-conversation, breaks flow |
| claude.ai web dashboard  | Full context switch to browser, manual navigation           |
| claude-counter extension | Browser-only -- useless for CLI/TUI/Desktop users           |

All three require the developer to **take action**. None of them passively **inform**.

### Proposed Solution

A native macOS menu bar app that continuously polls Claude's usage API and displays subscription utilization at a glance. Compact menu bar indicator (percentage or color-coded icon) expands on click to show detailed 5-hour and 7-day usage bars with reset countdowns. Proactive notifications warn developers as they approach limits (e.g. 80%, 95%), giving them time to pace work or wrap up tasks before being cut off.

### Key Differentiators

- **Zero token cost** -- runs entirely outside the conversation context, no MCP overhead
- **Always visible** -- menu bar presence means no action required to check usage
- **Proactive warnings** -- notifications before limits hit, preventing surprise cutoffs
- **Native macOS** -- Swift/SwiftUI, lightweight (~15-30 MB), feels like a first-class system utility
- **Open source** -- community-driven, extensible to other platforms over time

## Target Users

### Primary Users

**Persona: Alex -- The Always-On Power Dev**

- **Profile:** Solo developer on a Claude Max plan. Uses Claude as a constant companion across multiple projects simultaneously -- coding, debugging, refactoring, architecture, documentation. Multiple Claude Code windows open at all times.
- **Environment:** macOS, lives in the terminal. Claude Code is running 24/7 across several projects.
- **Motivation:** Maximum productivity. Claude is a core part of their workflow, not an occasional tool.
- **Pain:** Frequently hits usage limits without warning, gets cut off mid-task. Has no way to know which of their active sessions is burning through capacity fastest or how much headroom remains. The anxiety of not knowing is a constant background hum.
- **Workarounds today:** Occasionally runs `/usage` (costs tokens, breaks flow), checks claude.ai in a browser (context switch), or just guesses and hopes.
- **Success looks like:** Glances at the menu bar, sees they're at 78% with a reset in 47 minutes, decides to wrap up the current task before starting a big refactor. No surprise cutoffs. No anxiety. Just informed pacing.

### Secondary Users

N/A -- cc-hdrm is a solo developer tool. No team, admin, or oversight roles.

### User Journey

1. **Discovery:** Finds cc-hdrm on GitHub (or Homebrew) while searching for Claude usage monitoring solutions.
2. **Onboarding:** Downloads the app, launches it. It reads credentials from the macOS Keychain automatically -- no manual auth setup. Usage bars appear in the menu bar within seconds.
3. **Core Usage:** Never interacts with it directly. It's just *there* -- a number or color in the menu bar. Clicks to expand when they want detail. Gets a notification when approaching 80%.
4. **Aha Moment:** Sees they're at 92% of their 5-hour window with a reset in 12 minutes. Pauses, grabs coffee, comes back with full capacity instead of getting cut off mid-task.
5. **Long-term:** It becomes invisible infrastructure -- like a battery indicator. They'd feel blind without it.

## Success Metrics

### User Success

- **Zero surprise cutoffs** -- the user is never caught off guard by a usage limit. They always knew it was coming and had time to adjust.
- **No workflow interruption to check usage** -- the user never types `/usage`, opens claude.ai, or takes any action to learn their usage status.
- **Informed pacing** -- the user consciously adjusts their work intensity based on visible usage data (e.g. delays a big refactor when at 85%).

### Business Objectives

N/A -- cc-hdrm is a personal open source utility, not a revenue product.

### Key Performance Indicators

| KPI                   | Target                                            | Measurement                                 |
| --------------------- | ------------------------------------------------- | ------------------------------------------- |
| App reliability       | 99%+ uptime during dev sessions                   | App doesn't crash, hang, or lose connection |
| Data freshness        | Usage data no more than 60s stale                 | Poll interval + API response time           |
| Notification accuracy | Zero false negatives on threshold warnings        | User is always warned before hitting limits |
| Memory footprint      | Under 50 MB                                       | Activity Monitor                            |
| GitHub stars          | 100+ in first 6 months                            | GitHub                                      |
| Setup time            | Under 2 minutes from download to working menu bar | No manual auth config needed                |

## MVP Scope

### Core Features

1. **Menu bar indicator** -- compact display showing 5-hour usage percentage with color coding (green < 60%, yellow 60-80%, orange 80-95%, red > 95%)
2. **Click-to-expand panel** -- detailed view showing:
   - 5-hour session usage bar + reset countdown
   - 7-day weekly usage bar + reset countdown
   - Subscription tier display (Pro/Max)
3. **Automatic authentication** -- reads OAuth credentials from macOS Keychain (Claude Code's existing credentials). Zero manual setup.
4. **Background polling** -- fetches usage data every 30-60 seconds, entirely outside any Claude conversation
5. **Threshold notifications** -- macOS native notifications at 80% and 95% usage levels

### Out of Scope for MVP

- Usage graphs / historical trends over time
- Prediction of time-to-limit based on usage slope
- Sonnet-specific usage breakdown
- Extra usage / spending tracking
- Configurable notification thresholds (hardcoded at 80%/95%)
- Configurable poll interval
- Homebrew / DMG distribution (build from source)
- Launch at login preference
- Linux / Windows support
- Token refresh (relies on Claude Code to refresh expired tokens)

### MVP Success Criteria

- App runs stable for 8+ hours without crash or memory leak
- Usage data stays current (no more than 60s stale)
- User is notified before hitting limits -- zero surprise cutoffs
- Setup time under 2 minutes (clone, build, run)
- Memory under 50 MB

### Future Vision

- **Usage graphs** -- historical usage patterns over hours/days/weeks, visualized in the expanded panel
- **Limit prediction** -- based on recent usage slope, estimate when the current window will hit 100% (e.g. "At current pace, you'll hit the 5h limit in ~23 minutes")
- **Configurable thresholds and polling** -- user preferences for notification levels and update frequency
- **Homebrew tap** -- `brew install cc-hdrm` for easy distribution
- **Launch at login** -- system preference to auto-start
- **Sonnet breakdown** -- separate tracking for Sonnet-specific usage windows
- **Linux tray support** -- community-contributed platform expansion
