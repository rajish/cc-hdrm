# Story 9.1: Homebrew Tap Repository Setup

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a project maintainer,
I want a Homebrew tap repository with a working formula,
so that users can install cc-hdrm via `brew install`.

## Acceptance Criteria

1. **Given** the maintainer creates a separate repository `rajish/homebrew-tap`, **When** the repository is configured, **Then** it contains `Formula/cc-hdrm.rb` with a valid Homebrew formula **And** the formula downloads the ZIP asset from the latest GitHub Release **And** the formula includes the correct SHA256 checksum of the ZIP **And** the formula installs the cc-hdrm.app bundle to the appropriate location.

2. **Given** a user runs `brew tap rajish/tap && brew install cc-hdrm`, **When** Homebrew processes the formula, **Then** cc-hdrm is downloaded, extracted, and installed **And** the user can launch cc-hdrm from the installed location.

3. **Given** a user runs `brew upgrade cc-hdrm` after a new release, **When** the formula has been updated with the new version and SHA256, **Then** the new version is downloaded and installed, replacing the old version.

## Tasks / Subtasks

- [x] Task 1: Create `rajish/homebrew-tap` repository on GitHub (AC: #1)
  - [x] Create the repository (public, with README)
  - [x] Create `Casks/` directory structure (Cask, not Formula — per Dev Notes)

- [x] Task 2: Create `Casks/cc-hdrm.rb` Homebrew Cask formula (AC: #1, #2)
  - [x] Write Cask formula (not regular formula — this is a .app bundle, not a CLI binary)
  - [x] Use the latest GitHub Release ZIP asset URL as the download source
  - [x] Compute and include SHA256 checksum of the current ZIP asset
  - [x] Configure `app "cc-hdrm.app"` to install to `/Applications`
  - [x] Add `zap` stash for clean uninstall (UserDefaults, login items)

- [x] Task 3: Add `release-publish.yml` step to auto-update Homebrew formula (AC: #3)
  - [x] Add new step after "Create GitHub Release" in `.github/workflows/release-publish.yml`
  - [x] Compute SHA256 of the ZIP asset
  - [x] Update `Casks/cc-hdrm.rb` in `rajish/homebrew-tap` via GitHub API / git clone+push
  - [x] Commit and push the formula update
  - [x] Ensure formula update failure is non-blocking (release still publishes via `continue-on-error: true`)

- [x] Task 4: Test the full flow manually (AC: #1, #2, #3)
  - [x] `brew tap rajish/tap` — tapped 1 cask successfully
  - [x] `brew install --cask cc-hdrm` — downloaded, extracted, installed to `/Applications`
  - [x] Verify app launches from `/Applications` — confirmed
  - [x] `brew uninstall --cask cc-hdrm` — clean removal from `/Applications`

## Dev Notes

### Architecture Compliance

- This story is **infrastructure-only** — no Swift code changes, no changes to the cc-hdrm Xcode project.
- The Homebrew tap is a **separate repository** (`rajish/homebrew-tap`), not part of this monorepo.
- The only file modified in this repository is `.github/workflows/release-publish.yml` to add the auto-update step.
- `cc_hdrm.entitlements` — **PROTECTED, DO NOT MODIFY**.

### Key Implementation Details

**Cask vs Formula Decision:**

cc-hdrm is a macOS `.app` bundle (GUI application), not a command-line tool compiled from source. Homebrew **Casks** are the correct mechanism for distributing pre-built macOS applications. Do NOT use a regular Ruby formula with `def install` — use a Cask definition.

**Cask file: `Casks/cc-hdrm.rb`** (not `Formula/cc-hdrm.rb`):

```ruby
cask "cc-hdrm" do
  version "1.0.1"
  sha256 "COMPUTED_SHA256_OF_ZIP"

  url "https://github.com/rajish/cc-hdrm/releases/download/v#{version}/cc-hdrm-#{version}-macos.zip"
  name "cc-hdrm"
  desc "Menu bar utility showing Claude API usage headroom"
  homepage "https://github.com/rajish/cc-hdrm"

  depends_on macos: ">= :sonoma"

  app "cc-hdrm.app"

  zap trash: [
    "~/Library/Preferences/com.cc-hdrm.app.plist",
  ]
end
```

**Important Cask notes:**
- The tap repo structure for casks is `Casks/cc-hdrm.rb` (not `Formula/`)
- Users install via `brew tap rajish/tap && brew install --cask cc-hdrm`
- Or shorthand: `brew install rajish/tap/cc-hdrm`
- The ZIP from GitHub Releases already contains `cc-hdrm.app` — Homebrew extracts and copies to `/Applications`

**Alternative: If epics mandate `Formula/` path (regular formula):**

The epics text says `Formula/cc-hdrm.rb`. If the maintainer prefers a regular formula that downloads and installs the ZIP manually:

```ruby
class CcHdrm < Formula
  desc "Menu bar utility showing Claude API usage headroom"
  homepage "https://github.com/rajish/cc-hdrm"
  url "https://github.com/rajish/cc-hdrm/releases/download/v1.0.1/cc-hdrm-1.0.1-macos.zip"
  sha256 "COMPUTED_SHA256_OF_ZIP"
  version "1.0.1"

  depends_on macos: :sonoma

  def install
    prefix.install "cc-hdrm.app"
  end

  def caveats
    <<~EOS
      cc-hdrm.app has been installed to:
        #{prefix}/cc-hdrm.app

      To launch, open it from Finder or run:
        open #{prefix}/cc-hdrm.app
    EOS
  end
end
```

**Recommendation: Use Cask.** It's the standard Homebrew mechanism for macOS GUI apps and provides the best user experience (installs to `/Applications`, shows in Launchpad, clean uninstall).

**Release workflow auto-update step:**

Add the following step to `.github/workflows/release-publish.yml` AFTER the "Create GitHub Release" step:

```yaml
    - name: Update Homebrew formula
      if: steps.detect.outputs.release == 'true'
      continue-on-error: true  # Non-blocking — release still publishes
      env:
        GH_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}
        NEW_VERSION: ${{ steps.detect.outputs.version }}
      run: |
        # Compute SHA256 of the ZIP asset
        ZIP_SHA256=$(shasum -a 256 "cc-hdrm-${NEW_VERSION}-macos.zip" | awk '{print $1}')
        
        # Clone the tap repo
        git clone https://x-access-token:${GH_TOKEN}@github.com/rajish/homebrew-tap.git /tmp/homebrew-tap
        cd /tmp/homebrew-tap
        
        # Update Cask file
        cat > Casks/cc-hdrm.rb << CASKEOF
        cask "cc-hdrm" do
          version "${NEW_VERSION}"
          sha256 "${ZIP_SHA256}"
        
          url "https://github.com/rajish/cc-hdrm/releases/download/v#{version}/cc-hdrm-#{version}-macos.zip"
          name "cc-hdrm"
          desc "Menu bar utility showing Claude API usage headroom"
          homepage "https://github.com/rajish/cc-hdrm"
        
          depends_on macos: ">= :sonoma"
        
          app "cc-hdrm.app"
        
          zap trash: [
            "~/Library/Preferences/com.cc-hdrm.app.plist",
          ]
        end
        CASKEOF
        
        git config user.name "github-actions[bot]"
        git config user.email "github-actions[bot]@users.noreply.github.com"
        git add Casks/cc-hdrm.rb
        git diff --cached --quiet && { echo "No formula changes."; exit 0; }
        git commit -m "chore: update cc-hdrm to ${NEW_VERSION}"
        git push
```

**GitHub Token for cross-repo push:**

The default `GITHUB_TOKEN` is scoped to the current repository. To push to `rajish/homebrew-tap`, a **Personal Access Token (PAT)** or **fine-grained token** with `contents: write` permission on the tap repo is required. Store it as a repository secret named `HOMEBREW_TAP_TOKEN` in `rajish/cc-hdrm`.

### Previous Story Intelligence (8.2)

- Story 8.2 already shows "or `brew upgrade cc-hdrm`" in the update badge (UpdateBadgeView) — this story makes that hint actionable. [Source: `cc-hdrm/Views/UpdateBadgeView.swift`]
- The release pipeline (`.github/workflows/release-publish.yml`) already builds both ZIP and DMG assets, computes SHA256 checksums, and publishes GitHub Releases. This story extends it with one additional step. [Source: `.github/workflows/release-publish.yml` lines 264-284]
- The CI runs on `macos-15` with Xcode 26.2, uses XcodeGen for project generation. [Source: `.github/workflows/release-publish.yml` lines 16-24]

### Git Intelligence

- Recent commits are Epic 8 (update check service, update badge). Release infrastructure was completed in Epic 7.
- Current version: `v1.0.1` (latest release tag).
- Repository: `rajish/cc-hdrm` at `https://github.com/rajish/cc-hdrm.git`.
- Default branch: `master`.

### Project Structure Notes

Files to CREATE (in separate `rajish/homebrew-tap` repository):
```
homebrew-tap/
├── README.md
└── Casks/
    └── cc-hdrm.rb           # Homebrew Cask formula
```

Files to MODIFY (in this repository):
```
.github/workflows/release-publish.yml    # ADD Homebrew formula auto-update step
```

Files NOT to modify:
```
cc-hdrm/cc_hdrm.entitlements            # PROTECTED — do not touch
cc-hdrm/**                               # No Swift code changes in this story
```

### Testing Requirements

- **No automated tests** — this is infrastructure-only.
- Manual verification:
  1. Create `rajish/homebrew-tap` repo with Cask file
  2. `brew tap rajish/tap` — should succeed
  3. `brew install --cask cc-hdrm` — should download ZIP, extract, install to `/Applications`
  4. Launch cc-hdrm from `/Applications` — should work
  5. `brew uninstall --cask cc-hdrm` — should remove from `/Applications`
- Release workflow auto-update verified on next release (or via manual workflow dispatch test)

### Library & Framework Requirements

- **Homebrew** (user's machine) — Cask support is built-in
- **GitHub Actions** — existing `release-publish.yml` workflow
- **GitHub PAT** — `HOMEBREW_TAP_TOKEN` secret for cross-repo push
- **No new Swift dependencies.** No changes to the Xcode project.

### Anti-Patterns to Avoid

- DO NOT use a regular Homebrew Formula for a macOS .app bundle — use a Cask
- DO NOT put the formula in this repository — it belongs in a separate `homebrew-tap` repo
- DO NOT use `GITHUB_TOKEN` for cross-repo push — it only has permissions for the current repo
- DO NOT make the Homebrew update step blocking — use `continue-on-error: true`
- DO NOT modify any Swift source code for this story
- DO NOT modify `cc_hdrm.entitlements` — **PROTECTED**
- DO NOT hardcode SHA256 in the workflow — compute it dynamically from the built artifact

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` #Story 9.1, lines 912-935] — Full acceptance criteria
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Homebrew Tap, lines 717-725] — Architecture decision: separate repo, Formula, brew upgrade
- [Source: `_bmad-output/planning-artifacts/architecture.md` #Release Packaging, lines 688-714] — CI/CD pipeline that this story extends
- [Source: `.github/workflows/release-publish.yml`] — Existing release workflow to add Homebrew update step
- [Source: `cc-hdrm/Views/UpdateBadgeView.swift`] — Already shows "or brew upgrade cc-hdrm" hint
- [Source: `_bmad-output/implementation-artifacts/8-2-dismissable-update-badge-download-link.md`] — Previous story with Homebrew hint implementation
- [Source: `_bmad-output/planning-artifacts/project-context.md` line 9] — "Homebrew tap planned"

## Dev Agent Record

### Agent Model Used

claude-opus-4-5 (anthropic/claude-opus-4-5)

### Debug Log References

None — clean implementation, no issues encountered.

### Completion Notes List

- Created `rajish/homebrew-tap` public repo on GitHub
- Used **Cask** (not Formula) per Dev Notes — correct for macOS .app bundles
- Directory is `Casks/` not `Formula/` per Homebrew Cask convention
- Cask file uses v1.0.1 with SHA256 `3054dd181f7b88c4981039a1ec5ed01185308008ff62bbd5a14151671a0df357`
- Added "Update Homebrew Cask formula" step to `release-publish.yml` after "Create GitHub Release"
- Step uses `continue-on-error: true` so release still publishes if tap update fails
- Step requires `HOMEBREW_TAP_TOKEN` secret (PAT with `contents:write` on the tap repo)
- Full manual test passed: tap → install → launch → uninstall all succeeded
- No Swift code modified. No entitlements touched.

### Code Review Fixes (AI)

Reviewed by: claude-opus-4-5 (adversarial code review)

**H1 — Scope overlap with Story 9.2:** Story 9.2 cancelled — its scope (auto-update workflow step) was fully absorbed into Task 3.

**H2 — Heredoc+sed complexity:** Replaced quoted heredoc + 3 `sed` commands with unquoted heredoc. Shell expands `${NEW_VERSION}` and `${ZIP_SHA256}` directly; Ruby `#{version}` passes through unmodified. Eliminated all `sed` calls and the fragile whitespace stripping (L1).

**M1 — GH_TOKEN shadowing:** Renamed env var from `GH_TOKEN` to `TAP_TOKEN` to avoid shadowing the `gh` CLI convention used by the adjacent "Create GitHub Release" step.

**M2 — Architecture doc stale:** Updated `architecture.md` Homebrew Tap section: `Formula/` → `Casks/`, CLI binary → .app bundle, manual maintenance → auto-updated by workflow.

**M3 — Missing ZIP existence check:** Added `[ ! -f "${ZIP_FILE}" ]` guard with `::error::` annotation before `shasum` computation.

### File List

**Created (in `rajish/homebrew-tap` repo):**
- `README.md` — install/upgrade/uninstall instructions
- `Casks/cc-hdrm.rb` — Homebrew Cask formula for cc-hdrm v1.0.1

**Modified (in this repo):**
- `.github/workflows/release-publish.yml` — added "Update Homebrew Cask formula" step; review fixes (H2, M1, M3)
- `_bmad-output/planning-artifacts/architecture.md` — Homebrew Tap section updated (M2)
- `_bmad-output/implementation-artifacts/9-1-homebrew-tap-repository-setup.md` — story file updates
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — status tracking; 9.2 cancelled
