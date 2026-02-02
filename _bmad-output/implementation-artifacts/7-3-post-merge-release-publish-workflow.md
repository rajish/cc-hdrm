# Story 7.3: Post-Merge Release Publish Workflow

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a project maintainer,
I want merging a release PR to automatically build, package, and publish,
so that the entire release process requires zero manual steps after merge.

## Acceptance Criteria

1. **Given** a PR with a version bump commit is merged to `master`, **When** the `release-publish.yml` GitHub Actions workflow runs, **Then** it detects the version from the bumped Info.plist **And** tags `master` with `v{version}` **And** auto-generates a changelog entry from merged PR titles since the previous tag **And** if the merged PR body contained release notes between `<!-- release-notes-start -->` and `<!-- release-notes-end -->`, prepends that preamble **And** updates CHANGELOG.md with the new entry and commits to `master` **And** builds a universal binary (arm64 + x86_64) via `xcodebuild` **And** creates a ZIP: `cc-hdrm-{version}-macos.zip` **And** creates a GitHub Release with the changelog entry as body and the ZIP as an asset.

2. **Given** a PR without a version bump commit is merged to `master`, **When** the workflow evaluates the merge, **Then** no release is triggered, the workflow exits cleanly.

3. **Given** the build fails during the release workflow, **When** `xcodebuild` returns a non-zero exit code, **Then** the workflow fails, no GitHub Release is created, no tag is pushed **And** the maintainer is notified via GitHub Actions failure notification.

## Tasks / Subtasks

- [x] Task 1: Create `release-publish.yml` workflow (AC: #1, #2, #3)
  - [x] Define workflow trigger: `push` to `master` branch
  - [x] Add version bump detection: check if merge commit contains `chore: bump version to` commit
  - [x] Extract version from Info.plist
  - [x] Tag `master` with `v{version}` and push tag
  - [x] Retrieve merged PR body for release notes preamble extraction
  - [x] Auto-generate changelog entry from merged PR titles since previous tag
  - [x] Update CHANGELOG.md with new entry (preamble + PR list) and commit to `master`
  - [x] Build universal binary via `xcodebuild archive` (arm64 + x86_64) using XcodeGen
  - [x] Create ZIP: `cc-hdrm-{version}-macos.zip`
  - [x] Create DMG: `cc-hdrm-{version}.dmg`
  - [x] Compute SHA256 checksums
  - [x] Create GitHub Release with changelog body and ZIP/DMG/checksums as assets

- [x] Task 2: Remove or deprecate existing `release.yml` (AC: #1)
  - [x] The existing `release.yml` triggers on tag push and duplicates build/release logic
  - [x] Either remove it (since `release-publish.yml` handles the full pipeline) or keep it as a fallback and document the relationship

- [x] Task 3: Update README.md Versioning section (AC: #1)
  - [x] Document the post-merge automated release pipeline
  - [x] Explain how changelog generation works
  - [x] Document the release notes preamble convention

## Dev Notes

### Architecture Compliance

- **No Swift code changes.** This story is entirely GitHub Actions infrastructure, like Story 7.2.
- Architecture specifies workflow file location: `.github/workflows/release-publish.yml` [Source: `_bmad-output/planning-artifacts/architecture.md` line 714].
- Architecture specifies the post-merge workflow steps (lines 699-708): detect version bump commit -> tag -> changelog -> build -> ZIP -> GitHub Release -> Homebrew formula update.
- Homebrew formula update (architecture step 9) belongs to Epic 9 (Story 9.2), **NOT this story**. Skip it here.
- Default branch is `master` (confirmed in Stories 7.1, 7.2 and via `git branch -r`).
- Info.plist at `cc-hdrm/Info.plist` is the version source of truth, currently `1.0.0`.

### Key Implementation Details

**Workflow trigger configuration:**

```yaml
on:
  push:
    branches: [master]
```

The workflow triggers on every push to `master`, including merges. It must detect whether the push includes a version bump commit before proceeding.

**Version bump detection:**

The pre-merge workflow (Story 7.2) creates commits with the message `chore: bump version to {version}`. The post-merge workflow should scan the merged commits for this pattern:

```bash
# Check if any commit in the push contains a version bump
VERSION_BUMP_COMMIT=$(git log --format='%s' ${{ github.event.before }}..${{ github.sha }} | grep -m1 '^chore: bump version to ')
if [ -z "$VERSION_BUMP_COMMIT" ]; then
  echo "No version bump commit found. Skipping release."
  exit 0
fi
NEW_VERSION=$(echo "$VERSION_BUMP_COMMIT" | sed 's/chore: bump version to //')
```

**Edge case:** `github.event.before` may be `0000000` on force push or first push. Guard against this:

```bash
if [ "${{ github.event.before }}" = "0000000000000000000000000000000000000000" ]; then
  echo "Initial push or force push detected. Checking HEAD commit only."
  VERSION_BUMP_COMMIT=$(git log -1 --format='%s' | grep -m1 '^chore: bump version to ')
fi
```

**Also validate against Info.plist** to ensure consistency:

```bash
PLIST_VERSION=$(sed -n '/CFBundleShortVersionString/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' cc-hdrm/Info.plist)
if [ "$NEW_VERSION" != "$PLIST_VERSION" ]; then
  echo "::error::Version mismatch: commit says ${NEW_VERSION} but Info.plist says ${PLIST_VERSION}"
  exit 1
fi
```

**Tagging:**

```bash
git tag "v${NEW_VERSION}"
git push origin "v${NEW_VERSION}"
```

**Important:** Tag BEFORE creating the release. The tag must exist for the GitHub Release to reference it. But tag AFTER changelog update so the tag points to the commit that includes the updated CHANGELOG.md. This creates a chicken-and-egg problem.

**Resolution:** Tag after the changelog commit. The flow is:
1. Detect version bump
2. Generate changelog entry
3. Update CHANGELOG.md and commit to `master`
4. Tag the changelog commit with `v{version}`
5. Push tag
6. Build from tagged commit
7. Create GitHub Release

**Changelog generation:**

```bash
# Get previous tag
PREV_TAG=$(git describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo "")

# Get merged PR titles since previous tag
if [ -n "$PREV_TAG" ]; then
  PR_LIST=$(git log "${PREV_TAG}..HEAD" --merges --format='%s' | sed 's/^Merge pull request #\([0-9]*\) from .*/- #\1/' || true)
fi
```

Better approach using GitHub API to get actual PR titles:

```bash
# Use gh CLI or GitHub API to list merged PRs since last tag
PREV_TAG_DATE=$(git log -1 --format='%aI' "$PREV_TAG" 2>/dev/null || echo "1970-01-01T00:00:00Z")
```

Or use `git log` with `--oneline` for commits since last tag, filtering out automation commits:

```bash
PREV_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || git rev-list --max-parents=0 HEAD)
ENTRIES=$(git log "${PREV_TAG}..HEAD^" --oneline --no-merges | grep -v '^.*chore: bump version to' || true)
```

**Release notes preamble extraction:**

The merged PR's body may contain content between `<!-- release-notes-start -->` and `<!-- release-notes-end -->`. Use the GitHub API to fetch the PR body:

```bash
# Find the PR number from the merge commit
PR_NUMBER=$(gh pr list --state merged --search "$(git log -1 --format='%s' HEAD)" --json number --jq '.[0].number' 2>/dev/null || echo "")

if [ -n "$PR_NUMBER" ]; then
  PR_BODY=$(gh pr view "$PR_NUMBER" --json body --jq '.body')
  PREAMBLE=$(echo "$PR_BODY" | sed -n '/<!-- release-notes-start -->/,/<!-- release-notes-end -->/{ /<!--/d; p; }')
fi
```

**CHANGELOG.md update:**

Insert a new section after `## [Unreleased]`:

```bash
DATE=$(date +%Y-%m-%d)
CHANGELOG_ENTRY="## [${NEW_VERSION}] - ${DATE}\n\n"
if [ -n "$PREAMBLE" ]; then
  CHANGELOG_ENTRY="${CHANGELOG_ENTRY}${PREAMBLE}\n\n"
fi
CHANGELOG_ENTRY="${CHANGELOG_ENTRY}### Changed\n\n${PR_TITLES}\n"
```

Also update the comparison links at the bottom of CHANGELOG.md.

**Build (from existing `release.yml` patterns):**

The project uses **XcodeGen** to generate the Xcode project. The existing `ci.yml` and `release.yml` both install XcodeGen via Homebrew and run `xcodegen generate` before building. Follow this pattern:

```yaml
- name: Install XcodeGen
  run: brew install xcodegen

- name: Generate Xcode project
  run: xcodegen generate

- name: Build Universal Binary
  run: |
    xcodebuild \
      -project cc-hdrm.xcodeproj \
      -scheme cc-hdrm \
      -configuration Release \
      -destination 'generic/platform=macOS' \
      -archivePath build/cc-hdrm.xcarchive \
      CODE_SIGN_IDENTITY="-" \
      CODE_SIGNING_REQUIRED=NO \
      ONLY_ACTIVE_ARCH=NO \
      archive
```

**Packaging (from existing `release.yml`):**

```bash
# Export app
APP_PATH="build/cc-hdrm.xcarchive/Products/Applications/cc-hdrm.app"
mkdir -p release-staging
cp -R "$APP_PATH" release-staging/

# Create ZIP
cd release-staging
zip -r "../cc-hdrm-v${NEW_VERSION}-macos.zip" cc-hdrm.app
cd ..

# Create DMG
hdiutil create -volname "cc-hdrm" \
  -srcfolder release-staging \
  -ov -format UDZO \
  "cc-hdrm-v${NEW_VERSION}.dmg"

# SHA256 checksums
shasum -a 256 "cc-hdrm-v${NEW_VERSION}-macos.zip" >> checksums.txt
shasum -a 256 "cc-hdrm-v${NEW_VERSION}.dmg" >> checksums.txt
```

**GitHub Release creation:**

Use `softprops/action-gh-release@v2` (same as existing `release.yml`) or `gh release create`:

```yaml
- name: Create GitHub Release
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    gh release create "v${NEW_VERSION}" \
      --title "v${NEW_VERSION}" \
      --notes "${RELEASE_BODY}" \
      "cc-hdrm-v${NEW_VERSION}-macos.zip" \
      "cc-hdrm-v${NEW_VERSION}.dmg" \
      checksums.txt
```

**Concurrency control:**

```yaml
concurrency:
  group: release-publish
  cancel-in-progress: false  # Never cancel a release in progress
```

**Runner:** Must use `macos-15` (not `ubuntu-latest`) because `xcodebuild` is required for building. This differs from Story 7.2 which used `ubuntu-latest`.

### Previous Story Intelligence (7.2)

- Story 7.2 created `.github/workflows/release-prepare.yml` — the pre-merge workflow that creates the `chore: bump version to {version}` commits this story detects.
- Existing `release.yml` already handles tag-triggered builds with DMG, ZIP, checksums, and GitHub Release via `softprops/action-gh-release@v2`. This workflow should be **replaced** by `release-publish.yml` since the new workflow manages the entire pipeline including tagging.
- Existing `ci.yml` handles build+test on PR and push to master. It will still run alongside the release workflow.
- `release-prepare.yml` uses `ubuntu-latest` because it only does shell/git operations. This story needs `macos-15` for `xcodebuild`.
- The project uses **XcodeGen** (`brew install xcodegen` + `xcodegen generate`) before any Xcode builds. All existing workflows follow this pattern.
- Version parsing from Info.plist uses `sed -n '/CFBundleShortVersionString/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}'` — reuse this exact pattern.
- GitHub Actions bot identity: `github-actions[bot]` / `github-actions[bot]@users.noreply.github.com` — reuse for changelog commits.
- 340 tests passing, no regressions. This story adds no Swift code.

### Git Intelligence

Recent commits: Story 7.2 (`0ad74e4`) created `release-prepare.yml`. Story 7.1 (`b5f0229`) established v1.0.0 baseline. The `release.yml` and `ci.yml` were added in commit `05a4c49` as part of open source setup.

The existing `release.yml` triggers on `v*` tags and does build+release. Since `release-publish.yml` will create tags AND build+release, the old `release.yml` would trigger redundantly. It must be removed or disabled to prevent double releases.

### Project Structure Notes

- `.github/workflows/release-prepare.yml` exists (Story 7.2)
- `.github/workflows/release.yml` exists (pre-existing, tag-triggered build+release) — to be replaced
- `.github/workflows/ci.yml` exists (build+test on PR/push) — unchanged
- `cc-hdrm/Info.plist` at lines 17-18 contains `CFBundleShortVersionString`
- `cc-hdrm/cc_hdrm.entitlements` — PROTECTED, do not touch
- `CHANGELOG.md` — will be modified by the workflow at runtime, not by dev agent
- `README.md` — has Versioning section to update with post-merge workflow docs
- Project uses XcodeGen (`project.yml` at repo root) — no `.xcodeproj` committed

### File Structure Requirements

Files to CREATE:
```
.github/workflows/release-publish.yml    # NEW — post-merge release publish workflow
```

Files to MODIFY:
```
README.md                                # MODIFY — add post-merge release documentation to Versioning section
```

Files to REMOVE:
```
.github/workflows/release.yml           # REMOVE — replaced by release-publish.yml (prevents double release on tag push)
```

Files NOT to modify:
```
cc-hdrm/Info.plist                       # Read by workflow at runtime, not modified by dev agent
cc-hdrm/cc_hdrm.entitlements            # PROTECTED — do not touch
CHANGELOG.md                             # Modified by workflow at runtime, not by dev agent
.github/workflows/release-prepare.yml   # Existing Story 7.2 workflow — do not touch
.github/workflows/ci.yml                # Existing CI workflow — do not touch
```

### Testing Requirements

- **No Swift tests required.** This story creates a GitHub Actions workflow file only.
- **Workflow testing:** The workflow can only be fully tested by pushing to GitHub and merging a PR with a version bump. The developer should:
  1. Verify the YAML is valid (use `actionlint` or manual YAML validation)
  2. Verify shell scripts work locally where possible (version parsing, changelog generation logic)
  3. After pushing, open a test PR with `[patch]` in the title, let 7.2's workflow bump the version, then merge to validate end-to-end
- **Existing tests:** 340 tests remain unchanged. No Swift code modified.

### Library & Framework Requirements

- **GitHub Actions:** Uses `actions/checkout@v4`, `softprops/action-gh-release@v2` (already used by existing `release.yml`)
- **GitHub CLI (`gh`):** Pre-installed on GitHub Actions runners, used for PR body retrieval
- **XcodeGen:** Installed via Homebrew on macOS runner, used to generate Xcode project before build
- No new Swift libraries, frameworks, or dependencies
- No external GitHub Actions marketplace actions beyond `actions/*` and `softprops/action-gh-release@v2`

### Anti-Patterns to Avoid

- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT modify `cc-hdrm/Info.plist` directly — workflow reads it at runtime
- DO NOT modify `CHANGELOG.md` directly — workflow updates it at runtime
- DO NOT use `ubuntu-latest` runner — `xcodebuild` requires macOS
- DO NOT tag before updating CHANGELOG.md — tag should point to the commit with the updated changelog
- DO NOT create the tag if it already exists — guard against re-runs
- DO NOT trigger on `pull_request` events — this workflow triggers on `push` to `master` only
- DO NOT skip XcodeGen step — the project has no committed `.xcodeproj`
- DO NOT leave `release.yml` active — it would fire on the tag push and create a duplicate release
- DO NOT use `cancel-in-progress: true` for releases — a cancelled release could leave partial artifacts
- DO NOT hardcode `master` in multiple places — use a variable or `github.event.repository.default_branch`

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` #Story 7.3, lines 814-841] — Full acceptance criteria
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Release Packaging & CI/CD, lines 686-714] — Post-merge workflow spec (steps 1-9), file locations
- [Source: `_bmad-output/planning-artifacts/architecture.md` line 714] — `.github/workflows/release-publish.yml` file location
- [Source: `_bmad-output/planning-artifacts/prd.md` #FR31] — "Maintainer can trigger a semver release by including [patch], [minor], or [major] in a PR title merged to master"
- [Source: `_bmad-output/planning-artifacts/prd.md` #FR32] — "Release changelog is auto-generated from merged PR titles since last tag, with optional maintainer preamble"
- [Source: `_bmad-output/implementation-artifacts/7-2-pre-merge-version-bump-workflow.md`] — Previous story: release-prepare.yml patterns, version parsing, commit conventions
- [Source: `.github/workflows/release.yml`] — Existing tag-triggered release workflow (to be replaced)
- [Source: `.github/workflows/release-prepare.yml`] — Pre-merge version bump workflow (Story 7.2)
- [Source: `.github/workflows/ci.yml`] — CI build+test workflow (unchanged)
- [Source: `cc-hdrm/Info.plist` lines 17-18] — `CFBundleShortVersionString = 1.0.0`
- [Source: `CHANGELOG.md`] — Current changelog format with comparison links
- [Source: `_bmad-output/planning-artifacts/project-context.md`] — Architecture overview, technology stack, project structure

## Dev Agent Record

### Agent Model Used

claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

### Completion Notes List

- Created `.github/workflows/release-publish.yml` — full post-merge release pipeline: version bump detection, Info.plist validation, changelog generation with preamble support, CHANGELOG.md update via Python, tag creation, XcodeGen + xcodebuild archive, ZIP/DMG packaging, SHA256 checksums, GitHub Release via `gh`.
- Removed `.github/workflows/release.yml` — replaced by `release-publish.yml` to prevent duplicate releases on tag push.
- Updated `README.md` Versioning section with post-merge release pipeline documentation including changelog generation and release notes preamble convention.
- No Swift code changes. 341 existing tests pass with zero regressions.

### Architecture Deviations

- **Tag-after-changelog ordering:** Architecture spec (line 699-702) lists tagging as step 2 and changelog as step 3. Implementation reverses this so the tag points to the commit that includes the updated CHANGELOG.md. This avoids a tag pointing to a commit without the changelog entry. Intentional deviation — the architecture sequence describes logical steps, not strict ordering constraints.

### Change Log

- 2026-02-02: Code review fixes — H1 (documented ordering deviation), H2 (CHANGELOG.md guard), H3 ([skip ci] on changelog commit), M2 (artifact naming), M3 (PR lookup robustness)
- 2026-02-02: Implemented Story 7.3 — post-merge release publish workflow

### File List

- `.github/workflows/release-publish.yml` (CREATED)
- `.github/workflows/release.yml` (REMOVED)
- `README.md` (MODIFIED)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (MODIFIED)
