# Epic List

## Epic 1: Zero-Config Launch & Credential Discovery

Alex launches the app and it silently finds his Claude credentials — or shows him exactly what's wrong. App runs as menu bar utility (no dock icon, no main window), reads OAuth credentials from macOS Keychain, detects subscription tier, and handles token expiry with clear actionable messaging.
**FRs covered:** FR1, FR2, FR5, FR16, FR23

## Epic 2: Live Usage Data Pipeline

Alex's usage data flows automatically — the app fetches from the Claude API in the background and keeps itself current, handling errors gracefully with auto-recovery.
**FRs covered:** FR3, FR4, FR14, FR15, FR20, FR21, FR22

## Epic 3: Always-Visible Menu Bar Headroom

Alex glances at his menu bar and instantly knows how much headroom he has — color-coded, weight-escalated percentage that registers in peripheral vision in under one second. Story 3.3 (course correction) refines the 7d promotion rule to credit-math, adds gauge corner dot/label for 7d awareness, normalizes slope to credit terms, and adds quotas display.
**FRs covered:** FR6, FR7, FR39 (partial — credit-math promotion)

## Epic 4: Detailed Usage Panel

Alex clicks to expand and sees the full picture — both usage windows with ring gauges, countdowns with relative and absolute times, subscription tier, data freshness, and app controls.
**FRs covered:** FR8, FR9, FR10, FR11, FR12, FR13, FR24

## Epic 5: Threshold Notifications

Alex gets notified before he hits the wall — macOS notifications fire at 20% and 5% headroom for both windows independently, with full context including reset countdowns and absolute times. Never misses a warning, even when AFK.
**FRs covered:** FR17, FR18, FR19

## Epic 6: User Preferences & Settings (Phase 2)

Alex tweaks cc-hdrm to fit his workflow — adjustable notification thresholds, custom poll interval, launch at login. All accessible from a settings view in the gear menu, all taking effect immediately.
**FRs covered:** FR27, FR28, FR29, FR30

## Epic 7: Release Infrastructure & CI/CD (Phase 2)

The maintainer merges a PR with `[minor]` in the title and walks away. GitHub Actions bumps the version, tags the release, builds the binary, generates a changelog from merged PRs, and publishes to GitHub Releases — no manual steps.
**FRs covered:** FR31, FR32

## Epic 8: In-App Update Awareness (Phase 2)

Alex sees a subtle badge in the popover when a new version is available — one click to download, one click to dismiss. No nag, no interruption, just awareness.
**FRs covered:** FR25, FR26

## Epic 9: Homebrew Tap Distribution (Phase 2)

A developer finds cc-hdrm, runs `brew install cc-hdrm`, and it works. Upgrades flow through `brew upgrade` automatically when new releases are published.
**FRs covered:** (supports FR25/FR26 Homebrew update path)

## Epic 10: Data Persistence & Historical Storage (Phase 3)

Alex's usage data is no longer ephemeral — every poll snapshot is persisted to SQLite, rolled up at decreasing resolution as it ages, creating a permanent record of usage patterns.
**FRs covered:** FR33, FR34

## Epic 11: Usage Slope Indicator (Phase 3)

Alex sees not just where he stands, but how fast he's burning. A 4-level slope indicator (↘→↗⬆) appears in the menu bar when burn rate is actionable, and always in the popover for both windows.
**FRs covered:** FR42, FR43, FR44, FR45

## Epic 12: 24h Sparkline & Analytics Launcher (Phase 3)

Alex glances at the popover and sees a compact 24-hour usage trend — a step-area sparkline showing the sawtooth pattern of his recent sessions. Clicking it opens the analytics window.
**FRs covered:** FR35, FR37 (sparkline gaps)

## Epic 13: Full Analytics Window (Phase 3)

Alex clicks the sparkline and a floating analytics panel appears — zoomable charts across all retention periods, time range selectors, series toggles, and honest gap rendering for periods when cc-hdrm wasn't running.
**FRs covered:** FR36, FR37 (chart gaps)

## Epic 14: Headroom Analysis & Unused Capacity Breakdown (Phase 3)

Alex sees the real story behind his usage — a three-band breakdown showing what he actually used, what was blocked by the weekly limit (not unused!), and what he genuinely left on the table.
**FRs covered:** FR39, FR40, FR41

## Epic 15: Phase 3 Settings & Data Retention (Phase 3)

Alex configures how long cc-hdrm keeps historical data and optionally overrides credit limits for unknown subscription tiers.
**FRs covered:** FR38

## Epic 16: Subscription Intelligence (Phase 4)

Alex doesn't just see what happened — cc-hdrm tells him what it means. Slow-burn patterns surface as macOS notifications before they become costly surprises. Tier recommendations answer "am I on the right plan?" with concrete numbers. The analytics view presents the single most relevant conclusion from multiple valid lenses, anchored against Alex's own usage history.

## Epic 17: Extra Usage Visibility & Alerts (Phase 5)

Alex doesn't just hit the wall anymore — when his 5h or 7d plan quota runs out, Anthropic's pay-as-you-go overflow kicks in and cc-hdrm shows him exactly what it's costing. The menu bar glows amber when extra credits are burning, the popover shows a live spend bar with balance and reset date, and the analytics window reveals which cycles crossed the 100% line and by how much. Configurable alerts fire when extra spend crosses thresholds.
