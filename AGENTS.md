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
