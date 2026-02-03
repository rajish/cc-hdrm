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

[Unreleased]: https://github.com/rajish/cc-hdrm/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/rajish/cc-hdrm/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/rajish/cc-hdrm/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/rajish/cc-hdrm/releases/tag/v1.0.0
