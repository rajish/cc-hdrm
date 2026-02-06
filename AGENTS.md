# Agent Instructions

## Protected Files — DO NOT MODIFY

The following files must **never** be modified unless the user explicitly instructs you to do so:

- `cc-hdrm/cc_hdrm.entitlements` — Xcode entitlements plist. Modifying or emptying this file breaks Keychain access and network permissions at runtime. If a task does not specifically require entitlement changes, leave this file untouched.

## Gitignored Files — DO NOT FLAG IN REVIEWS

The following are intentionally **not tracked by git**:

- `*.xcodeproj/` — Xcode project files (including `project.pbxproj`) are gitignored. When reviewing story File Lists, do NOT report these as "missing from git" or "undocumented changes" — they cannot be tracked.

## XcodeGen — Project Generation

This project uses **XcodeGen** with `project.yml`. After adding new Swift files:

```bash
xcodegen generate
```

This regenerates `cc-hdrm.xcodeproj` with all files in `cc-hdrm/` and `cc-hdrmTests/` auto-discovered.

## Story Creation — File Path References

When creating stories, every reference to an existing project file **must** use a project-relative path (e.g., `cc-hdrm/Services/NotificationService.swift`), not just a filename. This eliminates unnecessary file searches by dev agents and saves tokens. Applies to all sections: Tasks, Dev Notes, File Structure Requirements, References, and inline code comments.

## Release Workflow — Version Bump via PR Title

**IMPORTANT:** Do NOT add `[patch]`, `[minor]`, or `[major]` keywords to PR titles or commit messages unless the user explicitly requests a release. These keywords trigger automated version bumps and releases. Only add them when the user specifically asks for a release.

This project uses a **two-stage release pipeline**:

1. **Pre-Merge (`release-prepare.yml`)**: Triggers on `pull_request` events (opened, edited, synchronize). Reads the **PR title** for `[patch]`, `[minor]`, or `[major]` keywords. If found, bumps `cc-hdrm/Info.plist` version and pushes a commit to the PR branch.
2. **Post-Merge (`release-publish.yml`)**: Triggers on push to `master`. Compares `Info.plist` version between the previous and current commit. If version changed, creates a GitHub release with binary assets.

**To trigger a release**, the `[patch]`/`[minor]`/`[major]` keyword must be in the **PR title** — NOT in the merge commit subject. The pre-merge workflow reads `github.event.pull_request.title`, so the keyword must be present there for the version bump commit to be pushed to the PR branch before merge.

**Correct workflow:**
```
gh pr create --title "feat: my feature [patch]" --body "..."
# Wait for Pre-Merge Version Bump workflow to push version commit
gh pr merge N --squash
```

**Common mistake — does NOT work:**
```
gh pr create --title "feat: my feature" --body "..."
gh pr merge N --squash --subject "feat: my feature [patch]"
# ❌ Pre-merge workflow never sees [patch] — no version bump — no release
```

**If you forgot the keyword**, edit the PR title before merging:
```
gh pr edit N --title "feat: my feature [patch]"
# Wait for Pre-Merge Version Bump workflow to complete
gh pr merge N --squash
```

## Pull Request & Commit Messages — GitHub Reference Prevention

**NEVER** use `#` followed by a number in PR titles, descriptions, or commit messages. GitHub automatically converts `#N` into links to issues/PRs, which creates confusing cross-references.

**Bad examples:**
- `AC #1`, `AC #2` → GitHub renders as links to PR/issue 1, 2
- `Story #10.2` → GitHub renders as link to PR/issue 10

**Good alternatives:**
- Use words: `AC-1`, `AC 1`, `AC1`, `Acceptance Criteria 1`
- Use parentheses: `(AC 1)`, `(Story 10.2)`
- Use brackets: `[AC-1]`, `[Story 10.2]`
- Spell out: `first acceptance criterion`, `Story 10.2`
