# Epic 9: Homebrew Tap Distribution (Phase 2)

A developer finds cc-hdrm, runs `brew install cc-hdrm`, and it works. Upgrades flow through `brew upgrade` automatically when new releases are published.

## Story 9.1: Homebrew Tap Repository Setup

As a project maintainer,
I want a Homebrew tap repository with a working formula,
So that users can install cc-hdrm via `brew install`.

**Acceptance Criteria:**

**Given** the maintainer creates a separate repository `{owner}/homebrew-tap`
**When** the repository is configured
**Then** it contains `Formula/cc-hdrm.rb` with a valid Homebrew formula
**And** the formula downloads the ZIP asset from the latest GitHub Release
**And** the formula includes the correct SHA256 checksum of the ZIP
**And** the formula installs the cc-hdrm.app bundle to the appropriate location

**Given** a user runs `brew tap {owner}/tap && brew install cc-hdrm`
**When** Homebrew processes the formula
**Then** cc-hdrm is downloaded, extracted, and installed
**And** the user can launch cc-hdrm from the installed location

**Given** a user runs `brew upgrade cc-hdrm` after a new release
**When** the formula has been updated with the new version and SHA256
**Then** the new version is downloaded and installed, replacing the old version

## Story 9.2: Automated Homebrew Formula Update

As a project maintainer,
I want the Homebrew formula to be updated automatically when a release is published,
So that Homebrew users get new versions without manual formula maintenance.

**Acceptance Criteria:**

**Given** the `release-publish.yml` workflow has created a GitHub Release with a ZIP asset
**When** the Homebrew update step runs
**Then** it computes the SHA256 of the uploaded ZIP asset
**And** updates `Formula/cc-hdrm.rb` in the `{owner}/homebrew-tap` repository with the new version URL and SHA256
**And** commits and pushes the formula update

**Given** the Homebrew formula update fails (e.g., push permission denied)
**When** the step fails
**Then** the GitHub Release is still published (formula update is non-blocking)
**And** the maintainer is notified of the formula update failure
