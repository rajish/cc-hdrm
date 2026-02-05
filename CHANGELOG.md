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

[Unreleased]: https://github.com/rajish/cc-hdrm/compare/v1.1.3...HEAD
[1.1.3]: https://github.com/rajish/cc-hdrm/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/rajish/cc-hdrm/compare/v1.0.2...v1.1.2
[1.0.2]: https://github.com/rajish/cc-hdrm/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/rajish/cc-hdrm/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/rajish/cc-hdrm/releases/tag/v1.0.0
