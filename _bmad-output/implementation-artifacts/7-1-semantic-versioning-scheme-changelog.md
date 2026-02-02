# Story 7.1: Semantic Versioning Scheme & CHANGELOG

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a project maintainer,
I want a consistent versioning scheme and changelog format,
so that users and contributors can track what changed between releases.

## Acceptance Criteria

1. **Given** the project repository, **When** a developer inspects versioning, **Then** the version lives in Info.plist (`CFBundleShortVersionString`) as the single source of truth **And** the format is `{major}.{minor}.{patch}` (e.g., `1.0.0`) **And** git tags follow the format `v{major}.{minor}.{patch}` (e.g., `v1.0.0`).

2. **Given** the project repository, **When** a developer inspects the changelog, **Then** CHANGELOG.md exists in the repo root **And** follows the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format **And** contains an `[Unreleased]` section for changes not yet released.

3. **Given** a new release is published, **When** the changelog is generated, **Then** CHANGELOG.md contains a section `## [version] - YYYY-MM-DD` **And** the section includes an auto-generated list of merged PR titles since the last tag **And** if the release PR body contained content between `<!-- release-notes-start -->` and `<!-- release-notes-end -->` markers, that content appears as a preamble above the PR list.

## Tasks / Subtasks

- [x] Task 1: Fix Info.plist version to semver 3-part format (AC: #1)
  - [x] Update `CFBundleShortVersionString` from `1.0` to `1.0.0` in `cc-hdrm/Info.plist`
  - [x] Verify `CFBundleVersion` stays as `1` (build number, independent of marketing version)

- [x] Task 2: Create initial git tag (AC: #1)
  - [x] Tag the current `master` HEAD as `v1.0.0`
  - [x] Push the tag to origin

- [x] Task 3: Update CHANGELOG.md to semver-compliant format (AC: #2, #3)
  - [x] Update CHANGELOG.md header to reference semantic versioning: "This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)"
  - [x] Move current `[Unreleased]` content into a `## [1.0.0] - YYYY-MM-DD` section (use today's date or the date of the initial release tag)
  - [x] Add a fresh empty `[Unreleased]` section above the `[1.0.0]` section
  - [x] Add comparison links at the bottom: `[Unreleased]` compares `v1.0.0...HEAD`, `[1.0.0]` links to the tag
  - [x] Add a comment documenting the release notes marker convention: `<!-- release-notes-start -->` / `<!-- release-notes-end -->` for future PR-driven preambles (AC #3)

- [x] Task 4: Document versioning conventions in the project (AC: #1, #2, #3)
  - [x] Add a "Versioning" section to README.md explaining: semver scheme, Info.plist as source of truth, tag format `v{major}.{minor}.{patch}`, CHANGELOG format, release keyword convention (`[patch]`/`[minor]`/`[major]` in PR titles for future CI/CD in Stories 7.2/7.3)

## Dev Notes

### Architecture Compliance

- **No new Swift code.** This story is entirely project infrastructure: plist edit, changelog formatting, git tag, README documentation.
- **Info.plist** is the single source of truth for the marketing version (`CFBundleShortVersionString`). The architecture doc specifies this explicitly: "Version string in Info.plist (CFBundleShortVersionString) and git tag (v1.0.0, v1.1.0)" [Source: `_bmad-output/planning-artifacts/architecture.md` #Release Packaging & CI/CD, line 688].
- **Default branch** is `master` (confirmed via `git branch -r` showing `origin/master`).
- **Remote** is `https://github.com/rajish/cc-hdrm.git`.

### Key Implementation Details

**Info.plist version fix:**

The current `CFBundleShortVersionString` is `1.0` (2-part). Semver requires 3-part `{major}.{minor}.{patch}`. Change to `1.0.0`. This is a one-line XML edit:

```xml
<!-- Before -->
<key>CFBundleShortVersionString</key>
<string>1.0</string>

<!-- After -->
<key>CFBundleShortVersionString</key>
<string>1.0.0</string>
```

`CFBundleVersion` (`1`) is the build number and is independent — leave it as-is.

**CHANGELOG.md current state:**

CHANGELOG.md already exists with Keep a Changelog format and an `[Unreleased]` section listing MVP features. The work is:
1. Add semver adherence note
2. Convert current `[Unreleased]` content to `[1.0.0]` release section
3. Add fresh `[Unreleased]` section
4. Fix comparison links at bottom

**Git tag:**

No tags exist currently (`git tag -l` returns empty). Create `v1.0.0` on current HEAD to mark the baseline for all future release automation (Stories 7.2 and 7.3 will detect version bumps by comparing against the latest tag).

```bash
git tag v1.0.0
git push origin v1.0.0
```

**Release notes marker convention (AC #3):**

Future releases (Stories 7.2/7.3) will auto-generate changelog entries from merged PR titles. If a release PR body contains content between these markers:

```markdown
<!-- release-notes-start -->
Custom preamble text here
<!-- release-notes-end -->
```

...that content becomes a preamble above the auto-generated PR list. Document this convention now so it's established before the CI/CD workflows are built.

### Previous Story Intelligence (6.4)

- 341 tests passing, zero regressions. This story adds no Swift code, so test count should remain unchanged.
- Project was recently flattened: Xcode project moved to repo root (commit `a6f115f`).
- CHANGELOG.md was created during earlier development but hasn't been versioned with tags yet.

### Git Intelligence

Recent commits show mature project with 6 completed epics. The repo has never had a release tag — this story establishes the versioning baseline.

Key commit: `a6f115f Flatten project structure: move Xcode project to repo root` — confirms `cc-hdrm/Info.plist` is the correct path (not nested deeper).

### Project Structure Notes

- `cc-hdrm/Info.plist` — version source of truth (line 17-18)
- `CHANGELOG.md` — repo root, already exists
- `README.md` — repo root, add Versioning section
- No `.github/workflows/` directory yet — created in Stories 7.2 and 7.3

### File Structure Requirements

Files to MODIFY:
```
cc-hdrm/Info.plist          # MODIFY — CFBundleShortVersionString 1.0 -> 1.0.0
CHANGELOG.md                # MODIFY — add semver note, convert [Unreleased] to [1.0.0], add fresh [Unreleased]
README.md                   # MODIFY — add Versioning section documenting conventions
```

Files NOT to modify:
```
cc-hdrm/cc_hdrm.entitlements   # PROTECTED — do not touch
```

No files to CREATE (all target files already exist).

### Testing Requirements

- **No new tests required.** This story modifies no Swift source code.
- **Verify existing tests still pass:** Run `xcodebuild test` to confirm 341 tests pass with zero regressions after the Info.plist version change.
- The version string change in Info.plist should not affect any test — no tests currently read `CFBundleShortVersionString`.

### Library & Framework Requirements

- No new libraries, frameworks, or dependencies.
- No Swift code changes.

### Anti-Patterns to Avoid

- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT change `CFBundleVersion` (build number) — it's independent of the marketing version
- DO NOT use a 2-part version like `1.0` — semver requires 3-part `major.minor.patch`
- DO NOT create the `.github/workflows/` directory or any workflow files — those belong to Stories 7.2 and 7.3
- DO NOT add any Swift code or new source files
- DO NOT force-push the tag — standard `git push origin v1.0.0` only

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` #Story 7.1] — Full acceptance criteria
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Release Packaging & CI/CD, line 688] — "Version string in Info.plist (CFBundleShortVersionString) and git tag (v1.0.0, v1.1.0). Default branch: master."
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Phase 2 Architectural Additions, lines 692-710] — Pre-merge and post-merge workflow specs, CHANGELOG format, release notes markers
- [Source: `_bmad-output/planning-artifacts/architecture.md` line 713] — `.github/workflows/release-prepare.yml` and `release-publish.yml` file locations (for Stories 7.2/7.3)
- [Source: `cc-hdrm/Info.plist` lines 17-18] — Current `CFBundleShortVersionString = 1.0`
- [Source: `CHANGELOG.md`] — Current Keep a Changelog format with `[Unreleased]` section
- [Source: `_bmad-output/planning-artifacts/project-context.md`] — Architecture overview, technology stack
- [Source: `_bmad-output/implementation-artifacts/6-4-launch-at-login.md`] — Previous story: 341 tests, project structure patterns

## Dev Agent Record

### Agent Model Used

claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

- 340 tests passing after Info.plist change (no regressions)
- XcodeGen project regeneration required before test run

### Completion Notes List

- Task 1: Updated `CFBundleShortVersionString` from `1.0` to `1.0.0` in `cc-hdrm/Info.plist`. `CFBundleVersion` unchanged at `1`.
- Task 2: Git tag `v1.0.0` created on commit containing all story changes and pushed to origin.
- Task 3: CHANGELOG.md reformatted — added semver adherence note, moved Unreleased content to `[1.0.0] - 2026-02-02` section, added fresh Unreleased section, added comparison links, documented release notes marker convention.
- Task 4: Added "Versioning" section to README.md documenting semver scheme, Info.plist source of truth, tag format, CHANGELOG format, and release keyword convention.
- No new Swift code. No new tests required. 340 existing tests pass.

### Change Log

- 2026-02-02: Story 7.1 implemented — semver versioning baseline established with v1.0.0 tag

### File List

- `cc-hdrm/Info.plist` — MODIFIED (CFBundleShortVersionString 1.0 → 1.0.0)
- `CHANGELOG.md` — MODIFIED (semver format, [1.0.0] release section, comparison links)
- `README.md` — MODIFIED (added Versioning section)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — MODIFIED (7-1 status update)
- `_bmad-output/implementation-artifacts/7-1-semantic-versioning-scheme-changelog.md` — MODIFIED (task checkboxes, dev agent record)
