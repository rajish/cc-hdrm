# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
  Release notes convention: When creating a release PR, include optional
  preamble content between these markers in the PR body:

    < !-- release-notes-start -- >
    Your release summary here
    < !-- release-notes-end -- >

  (Remove spaces from the marker tags above when using them.)
  This content will appear as a preamble above the auto-generated PR list
  in the changelog entry for that release.
-->

## [Unreleased]

## [1.3.1] - 2026-02-19

### Changed

- ci: remove temporary tap auth test workflow
- ci: add temporary workflow to test Homebrew tap auth
- fix: use GitHub App token for Homebrew tap push (#79)

## [1.3.0] - 2026-02-16

### Changed

- feat: extra usage step-end line visualization above 100% in 24h chart (#76)
- feat: extra usage visualization and tooltip data in bar chart views (#75)
- fix: extend x-axis domain to prevent last bar overlapping Y-axis labels (#77)
- fix: add trailing padding to prevent last bar overlapping Y-axis labels (#74)
- fix: detect 7d utilization drops in monotonic clamping reset logic (#73)
- fix: chart x-axis domain, 7d reset detection in chart and service layers (#68)
- fix: chart Y-axis clipping and extra usage 7d trigger detection (#67)
- fix: use integer cents for extra usage currency display (#63)
- feat: extra usage alerts and configuration with threshold notifications (Story 17.4)
- feat: analytics extra usage crossover visualization with 100% reference line (Story 17.3)
- feat: popover extra usage card with progress bar and billing cycle reset (Story 17.2)
- feat: extra usage state propagation and menu bar indicator (Story 17.1) (#59)
- feat: cycle-over-cycle bar chart and self-benchmarking anchors (Story 16.6) (#58)
- feat: context-aware insight engine with NL formatting and tone matching (Story 16.5) (#57)
- docs: create stories 16.5 and 16.6 via BMAD workflow, update sprint status (#56)
- feat: tier recommendation display card with billing cycle settings (Story 16.4) (#54)
- docs: create story 16.4 via BMAD workflow, update sprint status
- feat: pattern notification and analytics display (Story 16.2)
- fix: handle negative savings in tier cost comparison (#53)
- feat: slow-burn pattern detection service (Story 16.1) (#49)
- docs: mark story 16.3 as done in sprint status (#51)
- feat: tier recommendation service with billing cycle support (Story 16.3) (#50)
- feat: custom credit limit override for unknown tiers (Story 15.2) (#48)
- feat: data retention configuration with clear history (Story 15.1) (#47)
- feat: analytics view conditional display with data qualifier (Story 14.5) (#46)
- docs: address CodeRabbit review feedback across planning artifacts (#45)
- docs: shard epics into individual files and update planning artifacts (#44)
- feat: context-aware value summary with terminology refactor (Story 14.4) (#42)
- feat: persist extra usage data to SQLite database (#43)
- feat: subscription value bar with dollar-based utilization tracking (Story 14.3) (#41)
- feat: headroom analysis service with code review fixes (Story 14.2) (#38)

## [1.2.0] - 2026-02-07

### What's New in v1.2

**Full Analytics Window** — click the popover sparkline to open a floating analytics panel with:
- Time range selector (24h / 7d / 30d / All) at appropriate data resolution
- Step-area chart for 24h with sawtooth pattern, reset markers, and slope-based background tints
- Bar chart for longer ranges showing peak utilization per hour or day
- Independent 5h/7d series toggles with per-range persistence
- Honest gap rendering for periods when cc-hdrm wasn't running

### Changed

- feat: gap rendering in charts with hover tooltips (Story 13.7) (#36)
- feat: bar chart for 7d/30d/All analytics time ranges (Story 13.6) (#35)
- feat: step-area chart for 24h analytics view (Story 13.5)
- feat: per-time-range series toggle persistence (Story 13.4) (#33)
- feat: verify time range selector and add data loading tests (Story 13.3) (#32)
- feat: analytics view layout with data wiring, UsageChart and HeadroomBreakdownBar stubs (Story 13.2) (#31)
- feat: Story 13.1 — Analytics Window Shell (NSPanel) (#30)

## [1.1.4] - 2026-02-05

### Changed

- feat: credit-math 7d promotion, gauge overlay, slope normalization, popover quotas (Story 3.3) [patch]

## [1.1.3] - 2026-02-05

### Changed

- Release 1.1.3

## [1.1.2] - 2026-02-05

### Changed

- chore: release v1.1.1 (#24)
- [minor] Update README for v1.1.0 release (#22)
- chore: mark Story 12.4 and Epic 12 as done (#21)
- fix: add timing delays to reset detection tests for CI stability (#20)
- feat: integrate Sparkline into PopoverView with analytics toggle (Story 12.4) (#19)
- feat: add AnalyticsWindow controller and toggle mechanism (Story 12.3) (#18)
- feat: add Sparkline component for 24h usage visualization (Story 12.2) (#17)
- feat: add sparkline data preparation for 24h visualization (Story 12.1) (#16)
- feat: add slope indicators to popover gauges (Story 11.4) (#15)
- feat: add menu bar slope display with escalation-only arrows (Story 11.3) (#14)
- feat: replace sparkle icon with dynamic gauge in menu bar (#13)
- feat: add slope level color mapping and actionability (Story 11.2) (#12)
- fix: address CodeRabbit review feedback for Story 11.1 (#11)
- feat: add slope calculation service with ring buffer (Story 11.1) (#10)
- feat: add TimeRange-based getResetEvents API and finalize Data Query layer (Story 10.5) (#9)
- feat: implement tiered rollup engine with metadata tracking (Story 10.4) (#8)
- feat: add reset event detection for 5-hour window boundaries (Story 10.3) (#7)
- feat: add HistoricalDataService for poll data persistence (Story 10.2) (#6)
- feat: add DatabaseManager with SQLite schema for historical data (Story 10.1) (#5)
- chore: remove entitlements from xcodegen config, add token refresh tech spec
- docs: add Phase 3 planning documents (historical tracking, slope indicator, analytics) (#3)
- fix: disable entitlements for ad-hoc signed CI/release builds

## [1.0.2] - 2026-02-03

### Changed

- feat: add Homebrew Cask tap + auto-update workflow step (Story 9.1)
- Fix story 8.1 code review issues: AC #2 DMG preference, test URLs, initializer isolation, redundant wrapper, empty assets test
- feat: add dismissable update badge with download link (Story 8.2)
- feat: add UpdateCheckService for GitHub release update detection
- Update project-context.md for Phase 2: add new services, GitHub API integration, refined HTTP boundaries
- Update story 7.3 with CI fixes, test fixes, Xcode upgrade, and first release notes

## [1.0.1] - 2026-02-02

### Changed

- Fix notification tests: replace unmockable UNNotificationSettings with authorizationStatus() protocol method
- Upgrade CI to Xcode 26.2 and revert Swift 6.0 concurrency workarounds
- Fix CI: Swift 6 strict concurrency errors and test scheme discovery
- Add story 7.3: post-merge release publish workflow with code review fixes
- Add story 7.2: pre-merge version bump workflow with code review fixes
- Fix story 7.1 code review issues: changelog completeness, nested comments, sprint status cleanup

## [1.0.0] - 2026-02-02

### Added

- Menu bar headroom display with color-coded remaining capacity
- Context-adaptive display with constraint promotion at low headroom
- Click-to-expand popover with headroom detail view
- 5-hour headroom ring gauge with reset countdown
- 7-day headroom ring gauge with reset countdown
- Background polling engine (30-second intervals)
- Data freshness tracking with staleness detection
- API client for Anthropic usage endpoint
- Keychain credential discovery (reads Claude Code OAuth tokens)
- Automatic token expiry detection and refresh
- Notification permission service with system authorization
- Threshold state machine with warning notifications at configurable levels
- Critical threshold persistent notifications
- Settings view UI with click-away dismiss
- Preferences manager with UserDefaults persistence
- Configurable notification thresholds
- Launch at login via SMAppService
- Xcode project with XcodeGen configuration

[Unreleased]: https://github.com/rajish/cc-hdrm/compare/v1.3.1...HEAD
[1.3.1]: https://github.com/rajish/cc-hdrm/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/rajish/cc-hdrm/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/rajish/cc-hdrm/compare/v1.1.4...v1.2.0
[1.1.4]: https://github.com/rajish/cc-hdrm/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/rajish/cc-hdrm/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/rajish/cc-hdrm/compare/v1.0.2...v1.1.2
[1.0.2]: https://github.com/rajish/cc-hdrm/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/rajish/cc-hdrm/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/rajish/cc-hdrm/releases/tag/v1.0.0
