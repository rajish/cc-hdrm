# Story 7.2: Pre-Merge Version Bump Workflow

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a project maintainer,
I want the version to be bumped automatically when I include a release keyword in a PR title,
so that I don't have to manually edit Info.plist or remember version numbers.

## Acceptance Criteria

1. **Given** a maintainer opens a PR with `[patch]` in the title, **When** the `release-prepare.yml` GitHub Actions workflow runs, **Then** it reads the current version from Info.plist **And** bumps the patch component (e.g., `1.0.0` -> `1.0.1`) **And** commits the updated Info.plist back to the PR branch **And** the commit message is: `chore: bump version to {new_version}`.

2. **Given** a maintainer opens a PR with `[minor]` in the title, **When** the workflow runs, **Then** it bumps the minor component and resets patch (e.g., `1.0.1` -> `1.1.0`).

3. **Given** a maintainer opens a PR with `[major]` in the title, **When** the workflow runs, **Then** it bumps the major component and resets minor + patch (e.g., `1.1.0` -> `2.0.0`).

4. **Given** a PR title contains no release keyword (`[patch]`, `[minor]`, or `[major]`), **When** the workflow evaluates the PR, **Then** no version bump occurs, no commit is made, the workflow exits cleanly.

5. **Given** a non-maintainer opens a PR with a release keyword, **When** the workflow evaluates permissions, **Then** the version bump is skipped (only maintainers can trigger releases) **And** a comment or annotation indicates the keyword was ignored due to permissions.

## Tasks / Subtasks

- [x] Task 1: Create `.github/workflows/` directory (AC: #1)
  - [x] Create `.github/workflows/` directory structure in the repo root

- [x] Task 2: Create `release-prepare.yml` workflow (AC: #1, #2, #3, #4, #5)
  - [x] Define workflow trigger: `pull_request` events (`opened`, `edited`, `synchronize`) targeting `master`
  - [x] Add permission check: verify `github.actor` has maintainer/admin permission on the repo
  - [x] Parse PR title for release keywords: `[patch]`, `[minor]`, `[major]` (case-insensitive)
  - [x] If no keyword found, exit cleanly with success (AC #4)
  - [x] If non-maintainer, skip bump and add PR comment explaining why (AC #5)
  - [x] Read current version from `cc-hdrm/Info.plist` (`CFBundleShortVersionString`)
  - [x] Compute new version based on keyword (patch/minor/major semver bump)
  - [x] Update `CFBundleShortVersionString` in `cc-hdrm/Info.plist` with the new version
  - [x] Commit the change to the PR branch with message: `chore: bump version to {new_version}`
  - [x] Push the commit back to the PR branch

- [x] Task 3: Add workflow documentation to README.md (AC: #1-#5)
  - [x] Update the Versioning section in README.md to explain the automated pre-merge workflow
  - [x] Document which PR events trigger the workflow
  - [x] Document the permission requirement (maintainer-only)

## Dev Notes

### Architecture Compliance

- **No Swift code changes.** This story is entirely GitHub Actions infrastructure.
- Architecture specifies workflow file location: `.github/workflows/release-prepare.yml` [Source: `_bmad-output/planning-artifacts/architecture.md` #Phase 2 Architectural Additions, line 713].
- Architecture specifies the release trigger mechanism: "Keyword in PR title: `[patch]`, `[minor]`, or `[major]`. No keyword = no release. Only PRs from maintainers trigger the release workflow (enforced via GitHub Actions permission check on actor)." [Source: `_bmad-output/planning-artifacts/architecture.md` #Release Packaging & CI/CD, line 690].
- Architecture specifies pre-merge workflow steps: detect keyword -> read current version from Info.plist -> bump version -> commit updated Info.plist back to PR branch [Source: `_bmad-output/planning-artifacts/architecture.md` lines 692-697].
- Default branch is `master` (confirmed in Story 7.1 and via `git branch -r`).
- Info.plist is the single source of truth for version (`CFBundleShortVersionString`), currently at `1.0.0` after Story 7.1.

### Key Implementation Details

**Workflow trigger configuration:**

```yaml
on:
  pull_request:
    types: [opened, edited, synchronize]
    branches: [master]
```

The workflow needs to trigger on `edited` (title changes) and `synchronize` (new commits pushed) in addition to `opened`, so that renaming a PR to add/remove a keyword re-evaluates the version bump.

**Keyword parsing:**

Extract from `github.event.pull_request.title` using a regex or shell pattern match. Keywords are case-insensitive: `[patch]`, `[Patch]`, `[PATCH]` all match. Only the first keyword found is used (if someone puts both `[minor]` and `[patch]`, pick the highest precedence: major > minor > patch).

**Version parsing from Info.plist:**

The version lives in `cc-hdrm/Info.plist` as:

```xml
<key>CFBundleShortVersionString</key>
<string>1.0.0</string>
```

Use `grep` or `sed`/`awk` to extract the value, or use `PlistBuddy`:

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" cc-hdrm/Info.plist
```

However, since this runs on GitHub Actions (Ubuntu runner), `PlistBuddy` is NOT available. Use `sed` or `python` to parse the XML plist instead:

```bash
# Extract version from Info.plist using sed
CURRENT_VERSION=$(sed -n '/CFBundleShortVersionString/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' cc-hdrm/Info.plist)
```

**Version bump logic:**

```bash
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
case "$BUMP_TYPE" in
  major) NEW_VERSION="$((MAJOR+1)).0.0" ;;
  minor) NEW_VERSION="${MAJOR}.$((MINOR+1)).0" ;;
  patch) NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH+1))" ;;
esac
```

**Writing back to Info.plist:**

```bash
sed -i "s|<string>${CURRENT_VERSION}</string>|<string>${NEW_VERSION}</string>|" cc-hdrm/Info.plist
```

Note: The `sed -i` syntax differs between macOS and Linux. On GitHub Actions (Ubuntu), use `sed -i` (no quotes after `-i`). Target only the line after `CFBundleShortVersionString` to avoid accidentally replacing `CFBundleVersion`.

Safer approach — target specifically:

```bash
sed -i "/<key>CFBundleShortVersionString<\/key>/{n;s|<string>.*</string>|<string>${NEW_VERSION}</string>|;}" cc-hdrm/Info.plist
```

**Committing back to PR branch:**

The workflow needs write permission to push commits back to the PR branch. This requires:

```yaml
permissions:
  contents: write
  pull-requests: write
```

And the commit/push:

```bash
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add cc-hdrm/Info.plist
git commit -m "chore: bump version to ${NEW_VERSION}"
git push
```

**Important:** When the workflow pushes a commit, it could trigger itself again (since `synchronize` fires on new commits). To prevent infinite loops, check if the latest commit was already a version bump commit:

```bash
LAST_COMMIT_MSG=$(git log -1 --format='%s')
if [[ "$LAST_COMMIT_MSG" == chore:\ bump\ version\ to\ * ]]; then
  echo "Last commit is already a version bump. Skipping."
  exit 0
fi
```

**Permission check:**

Use the GitHub API to check if the PR author has maintainer/admin permission:

```yaml
- name: Check permissions
  uses: actions/github-script@v7
  id: check-permission
  with:
    script: |
      const { data } = await github.rest.repos.getCollaboratorPermissionLevel({
        owner: context.repo.owner,
        repo: context.repo.repo,
        username: context.payload.pull_request.user.login
      });
      const allowed = ['admin', 'maintain'].includes(data.permission);
      core.setOutput('allowed', allowed);
      if (!allowed) {
        await github.rest.issues.createComment({
          owner: context.repo.owner,
          repo: context.repo.repo,
          issue_number: context.payload.pull_request.number,
          body: `⚠️ Release keyword detected in PR title, but @${context.payload.pull_request.user.login} does not have maintainer permissions. Version bump skipped.`
        });
      }
```

Alternatively, for a solo-maintainer repo, a simpler approach is to check `github.repository_owner == github.actor` or use a hardcoded list. But the API approach is more robust.

**Idempotency consideration:**

If the workflow runs multiple times (e.g., PR title edited), it should always bump from the **base version** (the version on `master`), not from whatever version might already be on the PR branch from a previous bump. This prevents double-bumping.

Strategy: Always read the version from `master` branch first, compute the bump, then check if the PR branch already has that version. If it does, skip.

```bash
# Get version from master (base branch)
BASE_VERSION=$(git show origin/master:cc-hdrm/Info.plist | sed -n '/CFBundleShortVersionString/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}')

# Compute new version from BASE_VERSION (not current branch version)
# ... bump logic ...

# Check if PR branch already has this version
CURRENT_VERSION=$(sed -n '/CFBundleShortVersionString/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' cc-hdrm/Info.plist)
if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
  echo "Version already bumped to ${NEW_VERSION}. Skipping."
  exit 0
fi
```

### Previous Story Intelligence (7.1)

- Story 7.1 established `v1.0.0` tag, fixed Info.plist to 3-part semver `1.0.0`.
- No `.github/workflows/` directory exists yet — this story creates it.
- CHANGELOG.md was updated with proper Keep a Changelog format and comparison links.
- README.md has a "Versioning" section that documents the release keyword convention — this story should update it to explain the automated workflow.
- 340 tests passing, no regressions. This story adds no Swift code, test count remains unchanged.
- Project was flattened (commit `a6f115f`): Xcode project at repo root, Info.plist at `cc-hdrm/Info.plist`.
- Remote: `https://github.com/rajish/cc-hdrm.git`, default branch: `master`.

### Git Intelligence

Recent commits show Story 7.1 just completed (`b90824d`, `b5f0229`). The project has a `v1.0.0` tag. No workflows directory exists. The developer will need to create `.github/workflows/` from scratch.

Key pattern from recent work: commit messages use the format `Add story X.Y: description` for story implementations and `Fix story X.Y: description` for code review fixes. The workflow's auto-commits should use a distinct format (`chore: bump version to X.Y.Z`) to be easily distinguishable.

### Project Structure Notes

- `.github/workflows/` does NOT exist yet — must be created
- `cc-hdrm/Info.plist` at lines 17-18 contains `CFBundleShortVersionString`
- `cc-hdrm/cc_hdrm.entitlements` — PROTECTED, do not touch
- `README.md` — has Versioning section (added in Story 7.1) that should be updated

### File Structure Requirements

Files to CREATE:
```
.github/workflows/release-prepare.yml    # NEW — pre-merge version bump workflow
```

Files to MODIFY:
```
README.md                                # MODIFY — update Versioning section with automated workflow details
```

Files NOT to modify:
```
cc-hdrm/Info.plist                       # Read by workflow but NOT modified by dev agent — workflow modifies it at runtime
cc-hdrm/cc_hdrm.entitlements            # PROTECTED — do not touch
CHANGELOG.md                             # Not relevant to this story
```

### Testing Requirements

- **No Swift tests required.** This story creates a GitHub Actions workflow file only.
- **Workflow testing:** The workflow can only be fully tested by pushing to GitHub and opening a PR. The developer should:
  1. Verify the YAML is valid (use `actionlint` or manual YAML validation)
  2. Verify the shell scripts work locally by running the version parse/bump logic against `cc-hdrm/Info.plist`
  3. After pushing, open a test PR with `[patch]` in the title to validate end-to-end
- **Existing tests:** 340 tests remain unchanged. No Swift code modified.

### Library & Framework Requirements

- **GitHub Actions:** Uses `actions/checkout@v4`, `actions/github-script@v7` (standard GitHub-provided actions)
- No new Swift libraries, frameworks, or dependencies
- No external GitHub Actions marketplace actions beyond the official `actions/*` namespace

### Anti-Patterns to Avoid

- DO NOT modify `cc-hdrm/cc_hdrm.entitlements` — protected file
- DO NOT modify `cc-hdrm/Info.plist` directly in this story — the workflow modifies it at runtime
- DO NOT use `PlistBuddy` in the workflow — it's macOS-only and GitHub Actions runs on Ubuntu
- DO NOT add any Swift code or new source files
- DO NOT create `release-publish.yml` — that belongs to Story 7.3
- DO NOT trigger on `push` events — the workflow should only run on PR events
- DO NOT allow the workflow to run in an infinite loop (must skip if last commit is a version bump)
- DO NOT bump from the PR branch version — always compute from the `master` (base branch) version to prevent double-bumping
- DO NOT use `macos-latest` runner — use `ubuntu-latest` (cheaper, faster, sufficient for this workflow)
- DO NOT hardcode the base branch name in multiple places — use `github.event.pull_request.base.ref` or a single variable

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` #Story 7.2, lines 782-813] — Full acceptance criteria
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Release Packaging & CI/CD, lines 688-714] — Versioning scheme, release trigger, pre-merge workflow spec, file locations
- [Source: `_bmad-output/planning-artifacts/architecture.md` line 713] — `.github/workflows/release-prepare.yml` file location
- [Source: `_bmad-output/planning-artifacts/prd.md` #FR31, line 321] — "Maintainer can trigger a semver release by including [patch], [minor], or [major] in a PR title merged to master"
- [Source: `_bmad-output/planning-artifacts/prd.md` #FR32, line 322] — "Release changelog is auto-generated from merged PR titles since last tag" (Story 7.3, but context for how 7.2 feeds into it)
- [Source: `_bmad-output/implementation-artifacts/7-1-semantic-versioning-scheme-changelog.md`] — Previous story: v1.0.0 baseline, Info.plist version format, README versioning section
- [Source: `cc-hdrm/Info.plist` lines 17-18] — `CFBundleShortVersionString = 1.0.0`
- [Source: `_bmad-output/planning-artifacts/project-context.md`] — Architecture overview, technology stack, project structure

## Dev Agent Record

### Agent Model Used

claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

- Pre-existing Xcode build issue: `CpResource` tries to copy `cc-hdrm/cc-hdrm.xcodeproj` which doesn't exist at that path (xcodeproj is at repo root after flattening). Not caused by this story.

### Completion Notes List

- Created `.github/workflows/release-prepare.yml` — full pre-merge version bump workflow
- Workflow handles: keyword parsing (case-insensitive, precedence major>minor>patch), permission check via GitHub API, idempotent version bump from base branch, infinite loop guard, PR comment for non-maintainers
- Updated README.md Versioning section with comprehensive automated workflow documentation
- Version parse/bump shell logic verified locally against `cc-hdrm/Info.plist` (1.0.0 → patch:1.0.1, minor:1.1.0, major:2.0.0)
- YAML syntax validated
- No Swift code changed; existing 340 tests unaffected

### Change Log

- 2026-02-02: Implemented Story 7.2 — Pre-Merge Version Bump Workflow
- 2026-02-02: Code review fixes — removed dead code step, switched new_version from GITHUB_ENV to GITHUB_OUTPUT, added base branch fetch, added semver validation, clarified README base branch wording, added concurrency control, documented sprint-status.yaml in File List

### File List

- `.github/workflows/release-prepare.yml` — NEW: GitHub Actions workflow for automated pre-merge version bumps
- `README.md` — MODIFIED: Updated Versioning section with automated workflow documentation
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — MODIFIED: Updated 7-2 status to review
