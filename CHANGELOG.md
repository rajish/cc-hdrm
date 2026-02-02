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

[Unreleased]: https://github.com/rajish/cc-hdrm/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/rajish/cc-hdrm/releases/tag/v1.0.0
