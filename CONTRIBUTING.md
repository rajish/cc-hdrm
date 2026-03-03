# Contributing to cc-hdrm

Thanks for your interest in contributing. This document covers the process for contributing to this project.

## Getting Started

1. Fork the repository
2. Clone your fork
3. Create a branch from `master` for your change

### Development Setup

You need:
- macOS 14.0 (Sonoma) or later
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```sh
git clone https://github.com/<your-username>/cc-hdrm.git
cd cc-hdrm
xcodegen generate
open cc-hdrm.xcodeproj
```

### Running Tests

From Xcode: `Cmd+U`

From the command line:

```sh
cd cc-hdrm
xcodegen generate
xcodebuild -project cc-hdrm.xcodeproj -scheme cc-hdrmTests -destination 'platform=macOS' test
```

## How to Contribute

### Reporting Bugs

Open an [issue](https://github.com/rajish/cc-hdrm/issues/new?template=bug_report.md) with:
- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Console logs if relevant (`Console.app`, filter by `cc-hdrm`)

### Suggesting Features

Open an [issue](https://github.com/rajish/cc-hdrm/issues/new?template=feature_request.md) describing:
- The problem you're trying to solve
- Your proposed solution
- Alternatives you've considered

### Submitting Code

1. Open an issue first to discuss the change (unless it's a small fix)
2. Fork and create a branch: `git checkout -b fix/description` or `git checkout -b feat/description`
3. Make your changes
4. Ensure tests pass
5. Submit a pull request against `master`

### Pull Request Guidelines

- Keep PRs focused — one change per PR
- Follow existing code style and naming conventions (see Architecture section below)
- Add tests for new functionality
- Update documentation if behavior changes

## Architecture

The project follows MVVM with these conventions:

| Layer      | Location           | Purpose                            |
| ---------- | ------------------ | ---------------------------------- |
| Models     | `cc-hdrm/Models/`     | Data types, enums, value objects   |
| Services   | `cc-hdrm/Services/`   | API client, Keychain, polling      |
| State      | `cc-hdrm/State/`      | `AppState` — single source of truth  |
| Views      | `cc-hdrm/Views/`      | SwiftUI views                      |
| Extensions | `cc-hdrm/Extensions/` | Type extensions                    |

Key principles:
- Zero external dependencies — use only Apple SDK frameworks
- Protocol-based services for testability
- `@Observable` for state management
- Swift 6.0 strict concurrency

## Versioning

This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) (`major.minor.patch`).

- **Source of truth:** `CFBundleShortVersionString` in `cc-hdrm/Info.plist`
- **Git tags:** `v{major}.{minor}.{patch}` (e.g., `v1.0.0`)
- **Changelog:** [CHANGELOG.md](CHANGELOG.md) follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format with an `[Unreleased]` section for pending changes
- **Release keywords:** Include `[patch]`, `[minor]`, or `[major]` in PR titles to trigger an automated version bump

### Automated Pre-Merge Version Bump

The [`release-prepare.yml`](.github/workflows/release-prepare.yml) GitHub Actions workflow automatically bumps the version when a release keyword is detected in a PR title targeting `master`.

**How it works:**

1. A maintainer opens (or edits) a PR with `[patch]`, `[minor]`, or `[major]` in the title
2. The workflow reads the current version from `master`'s `cc-hdrm/Info.plist`
3. It computes the new semver version and commits the updated `Info.plist` back to the PR branch
4. The commit message is `chore: bump version to {new_version}`

**Trigger events:** `opened`, `edited` (title change), `synchronize` (new push)

**Rules:**
- Only maintainers can trigger version bumps — non-maintainer keywords are ignored with a PR comment
- No keyword = no bump, workflow exits cleanly
- If multiple keywords are present, highest precedence wins: `major` > `minor` > `patch`
- Keywords are case-insensitive (`[Patch]`, `[MINOR]`, etc.)
- The workflow is idempotent — re-runs read the version from the PR's base branch (typically `master`), not the PR branch

### Automated Post-Merge Release

The [`release-publish.yml`](.github/workflows/release-publish.yml) GitHub Actions workflow runs on every push to `master`. When it detects a version bump commit (from the pre-merge workflow above), it automatically builds, packages, and publishes a release.

**Pipeline steps:**

1. Detect the `chore: bump version to {version}` commit in the push
2. Validate the version matches `CFBundleShortVersionString` in `cc-hdrm/Info.plist`
3. Auto-generate a changelog entry from commit messages since the previous tag
4. Update `CHANGELOG.md` and commit to `master`
5. Tag the changelog commit with `v{version}`
6. Build a universal binary (arm64 + x86\_64) via `xcodebuild archive`
7. Package as ZIP (`cc-hdrm-{version}-macos.zip`) and DMG (`cc-hdrm-{version}.dmg`)
8. Compute SHA256 checksums
9. Create a GitHub Release with the changelog entry as body and ZIP/DMG/checksums as assets

**Changelog generation:** Commit messages since the previous tag are collected automatically, excluding automation commits. If the merged PR body contains content between `<!-- release-notes-start -->` and `<!-- release-notes-end -->` markers, that content is prepended as a release summary.

**No version bump = no release.** If a push to `master` doesn't include a version bump commit, the workflow exits cleanly.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
