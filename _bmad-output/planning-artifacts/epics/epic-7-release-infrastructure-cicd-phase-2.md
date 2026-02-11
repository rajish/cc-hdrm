# Epic 7: Release Infrastructure & CI/CD (Phase 2)

The maintainer merges a PR with `[minor]` in the title and walks away. GitHub Actions bumps the version, tags the release, builds the binary, generates a changelog from merged PRs, and publishes to GitHub Releases — no manual steps.

## Story 7.1: Semantic Versioning Scheme & CHANGELOG

As a project maintainer,
I want a consistent versioning scheme and changelog format,
So that users and contributors can track what changed between releases.

**Acceptance Criteria:**

**Given** the project repository
**When** a developer inspects versioning
**Then** the version lives in Info.plist (`CFBundleShortVersionString`) as the single source of truth
**And** git tags follow the format `v{major}.{minor}.{patch}` (e.g., `v1.0.0`, `v1.1.0`)
**And** CHANGELOG.md exists in the repo root

**Given** a new release is published
**When** the changelog is generated
**Then** the CHANGELOG.md contains a section `## [version] - YYYY-MM-DD`
**And** the section includes an auto-generated list of merged PR titles since the last tag
**And** if the release PR body contained content between `<!-- release-notes-start -->` and `<!-- release-notes-end -->` markers, that content appears as a preamble above the PR list

## Story 7.2: Pre-Merge Version Bump Workflow

As a project maintainer,
I want the version to be bumped automatically when I include a release keyword in a PR title,
So that I don't have to manually edit Info.plist or remember version numbers.

**Acceptance Criteria:**

**Given** a maintainer opens a PR with `[patch]` at the front of the title (e.g., `[patch] feat: my feature`)
**When** the `release-prepare.yml` GitHub Actions workflow runs
**Then** it reads the current version from Info.plist
**And** bumps the patch component (e.g., `1.0.0` → `1.0.1`)
**And** commits the updated Info.plist back to the PR branch
**And** the commit message is: `chore: bump version to {new_version}`

**Given** a maintainer opens a PR with `[minor]` at the front of the title
**When** the workflow runs
**Then** it bumps the minor component and resets patch (e.g., `1.0.1` → `1.1.0`)

**Given** a maintainer opens a PR with `[major]` at the front of the title
**When** the workflow runs
**Then** it bumps the major component and resets minor + patch (e.g., `1.1.0` → `2.0.0`)

**Given** a PR title contains no release keyword
**When** the workflow evaluates the PR
**Then** no version bump occurs, no commit is made, the workflow exits cleanly

**Given** a non-maintainer opens a PR with a release keyword
**When** the workflow evaluates permissions
**Then** the version bump is skipped (only maintainers can trigger releases)
**And** a comment or annotation indicates the keyword was ignored due to permissions

## Story 7.3: Post-Merge Release Publish Workflow

As a project maintainer,
I want merging a release PR to automatically build, package, and publish,
So that the entire release process requires zero manual steps after merge.

**Acceptance Criteria:**

**Given** a PR with a version bump commit is merged to `master`
**When** the `release-publish.yml` GitHub Actions workflow runs
**Then** it detects the version from the bumped Info.plist
**And** tags `master` with `v{version}`
**And** auto-generates a changelog entry from merged PR titles since the previous tag
**And** if the merged PR body contained release notes between `<!-- release-notes-start -->` and `<!-- release-notes-end -->`, prepends that preamble
**And** updates CHANGELOG.md with the new entry and commits to `master`
**And** builds a universal binary (arm64 + x86_64) via `xcodebuild`
**And** creates a ZIP: `cc-hdrm-{version}-macOS.zip`
**And** creates a GitHub Release with the changelog entry as body and the ZIP as an asset

**Given** a PR without a version bump commit is merged to `master`
**When** the workflow evaluates the merge
**Then** no release is triggered, the workflow exits cleanly

**Given** the build fails during the release workflow
**When** `xcodebuild` returns a non-zero exit code
**Then** the workflow fails, no GitHub Release is created, no tag is pushed
**And** the maintainer is notified via GitHub Actions failure notification
