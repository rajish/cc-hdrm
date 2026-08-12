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

**Correct workflow** (keyword goes at the FRONT of the title):
```
gh pr create --title "[patch] feat: my feature" --body "..."
# Wait for Pre-Merge Version Bump workflow to push version commit
gh pr merge N --squash
```

**Common mistake — does NOT work:**
```
gh pr create --title "feat: my feature" --body "..."
gh pr merge N --squash --subject "[patch] feat: my feature"
# ❌ Pre-merge workflow never sees [patch] — no version bump — no release
```

**If you forgot the keyword**, edit the PR title before merging:
```
gh pr edit N --title "[patch] feat: my feature"
# Wait for Pre-Merge Version Bump workflow to complete
gh pr merge N --squash
```

## BMAD Methodology — Story Lifecycle (v6.11+)

This project follows the **BMAD workflow** for all feature development. The story lifecycle is:

1. **Build Story** (`bmad-build` skill) — the official implementation loop: clarify intent, plan, implement, review, present. Replaces the old create-story + dev-story pair. Story artifacts live in `_bmad-output/implementation-artifacts/`
2. **Code Review** (`bmad-code-review` skill) — adversarial senior dev review, an extra layer on top of Build's built-in review; auto-fix with user approval
3. **PR + CI + CodeRabbit** — Create PR, wait for CI and CodeRabbit review, address findings
4. **Merge** — Squash-merge to master
5. **Next Story** — Repeat from step 1

**NEVER skip the BMAD workflows.** Each step has a dedicated workflow that enforces templates, instructions, and validation checklists. Do NOT perform these steps manually — hand-rolled output bypasses quality gates and produces artifacts missing critical context.

- **`bmad-build`** — Enforces story structure, dev context, acceptance criteria tracking, and its own review pass. Do NOT hand-roll story files or start coding without it. `bmad-create-story` and `bmad-dev-story` are deprecated shims that forward here — do not invoke them.
- **`bmad-code-review`** — Runs an adversarial review that must find specific problems. Do NOT substitute a casual self-review or skip this step before creating a PR.
- **`bmad-sprint-planning`** — Owns the readiness gate and `sprint-status.yaml` generation/repair; also serves sprint status summaries (the old `bmad-sprint-status` forwards here).

**Key files:**
- Sprint status: `_bmad-output/implementation-artifacts/sprint-status.yaml` — shared resource, each branch should only update its own story status
- Story files: `_bmad-output/implementation-artifacts/{epic}-{story}-{slug}.md`
- BMAD config: `_bmad/bmm/config.yaml`

## Agent Teams — Coordination Rules

When running parallel agent teams, follow these rules to avoid destructive conflicts:

- **Always use git worktrees.** Agents sharing one working directory causes file deletion, branch conflicts, and unrecoverable state. Create worktrees at sibling paths (e.g., `../cc-hdrm-track-a`, `../cc-hdrm-track-b`).
- **Single-task assignments only.** Agents will blow through task dependency gates unless given single-task assignments with explicit "go idle when done" instructions. Do not give agents multi-task autonomy across review gates.
- **Use `shutdown_request` to halt agents.** Agents often ignore stop/hold messages if they are mid-turn. Use `shutdown_request` instead of plain messages for reliable halting.
- **Sprint status is a shared resource.** Each branch should only update its own story's status in `sprint-status.yaml` to avoid merge conflicts.

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
