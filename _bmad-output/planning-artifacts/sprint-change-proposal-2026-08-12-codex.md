# Sprint Change Proposal — OpenAI Codex Usage Tracking

**Date:** 2026-08-12
**Author:** Boss (facilitated by SM / correct-course workflow)
**Status:** APPROVED 2026-08-12 — edits applied to PRD, epic list, and sprint status
**Mode:** Batch review
**Scope classification:** Moderate (backlog addition, new phase; architecture addendum required)

> Numbering note: Epic 21 is taken by the concurrent Fable Model Usage Tracking proposal
> (sprint-change-proposal-2026-08-12-fable.md). This proposal uses Epics 22–25.

---

## Section 1: Issue Summary

### Problem Statement

cc-hdrm tracks only Claude subscription usage. The user also runs OpenAI Codex, which has an analogous rate-limit system (5-hour primary window + weekly secondary window + purchasable credits) and the same pain: no passive, always-visible way to monitor headroom. The user must run `/status` inside the Codex TUI to see limits — exactly the workflow interruption cc-hdrm was built to eliminate for Claude.

### Discovery Context

- New stakeholder requirement (2026-08-12), not triggered by an in-flight story. All epics 1–21 are done or (Epic 21) separately proposed; this change is independent of the Fable epic.
- Decision inputs gathered at workflow start:
  - **Scope:** Full parity with Claude tracking (menu bar, notifications, history, analytics).
  - **Kill gate:** API spike story first, mirroring the 2026-01-31 Claude spike.
  - **Menu bar model:** Two separate status items (Claude and Codex), each with its own popover.
  - **Review mode:** Batch.

### Evidence of Feasibility

- Codex CLI stores OAuth credentials on disk at `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`), including JWT claims with email and plan type.
- Usage endpoint: `GET https://chatgpt.com/backend-api/wham/usage` with `Authorization: Bearer <token>`. Response contains `rate_limit.primary_window` (session/5h) and `rate_limit.secondary_window` (weekly), `additional_rate_limits[]` (per-model), and credits fields (balance, hasCredits, unlimited).
- Credit inventory endpoint: `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`.
- Prior art: CodexBar (steipete/CodexBar) is a shipping macOS menu bar app reading exactly this surface — the approach is proven.
- **Caveat:** these are undocumented internal endpoints (same risk class as Claude's `api/oauth/usage`). Paths, fields, and access rules may change. Token refresh mechanism and endpoint must be validated in the spike.

---

## Section 2: Impact Analysis

### Epic Impact

| Area | Impact |
| --- | --- |
| Epics 1–20 | **None.** All done; no rollback, no modification. Change is purely additive. |
| Epic 21 (Fable) | **None.** Independent scope (Claude API's model-scoped limits vs. a new provider). No shared files beyond the usual planning artifacts. |
| New epics | Four new epics (22–25) forming **Phase 7: Codex Usage Tracking**. |
| Sequencing | Epic 22 (spike + pipeline) gates everything. 23 → 24/25 after. 24 and 25 are independent of each other. Phase 7 has no dependency on Epic 21 and can run before, after, or parallel to it. |
| Kill gate | Story 22.1 spike. If the usage endpoint cannot be reached from a standalone macOS process with `auth.json` tokens, Phase 7 is killed and Epics 23–25 are cancelled. |

### Story Impact

- No existing stories change. All new stories (see Section 4).
- Reuse-heavy: `PollingEngine` pattern, `NotificationService` threshold state machines, `SlopeCalculationService`, SQLite rollup engine, gauge/popover components are all designed as reusable layers.

### Artifact Conflicts

| Artifact | Conflict | Resolution |
| --- | --- | --- |
| PRD | Claude-only framing; FR list ends at FR48; **NFR8 forbids transmission to any endpoint other than `api.anthropic.com`, `platform.claude.com`** (+`api.github.com` in project-context) | Add Phase 7 section, FR49–FR60, amend NFR8, add NFR14–NFR15 |
| Architecture | No provider concept; boundaries table maps one API client to one host; SQLite schema has no provider dimension | Phase 7 architecture addendum (new services, second status item, schema migration) |
| UX spec | Single menu bar item, single popover | Codex addendum: second status item + mirrored popover layout |
| project-context.md | Integrations, boundaries, and constraint 3 (endpoint allowlist) are Claude-only | Update after Epic 22 lands (implementation-time task, not proposal-time) |
| sprint-status.yaml | No Phase 7 entries; concurrent Fable branch also appends here | Add epics 22–25 with status `backlog` upon approval, appended after the Fable block (shared-resource rule: each branch touches only its own entries) |
| Entitlements / sandbox | App must read `~/.codex/auth.json` from disk | Validate in spike 22.1. **`cc_hdrm.entitlements` is a protected file** — any change requires explicit user instruction |

### Technical Impact

- **New network host:** `chatgpt.com` (+ token-refresh host, TBD in spike — likely `auth.openai.com`). Security posture (NFR8-style allowlist) must be explicitly widened, not silently.
- **Credentials on disk, not Keychain:** different threat model. Read-only file access; never write to `auth.json`; never log tokens (extends existing logging rule).
- **Two polling lanes:** Codex polling must fail independently — a Codex outage must never degrade Claude display, and vice versa.
- **SQLite migration:** provider dimension for historical data. Migration must preserve all existing Claude history (lesson from Story 17.5: never destroy rollup history).
- **Naming:** "cc-hdrm" reads as Claude-Code-specific. Out of scope for this change; noted for future consideration.

### Explicitly Deferred (not in Phase 7)

| Item | Why deferred |
| --- | --- |
| Codex Token Efficiency Ratio (TPP) | TPP depends on parsing Claude Code session logs; Codex equivalent needs its own log-format research. Separate epic if wanted. |
| Codex unused-capacity three-band breakdown (FR40-style) | Requires validated credit-math for Codex windows; revisit after spike + real poll data exist. |
| Codex tier recommendation / subscription intelligence | Requires Codex pricing model research; premature before basic tracking ships. |

---

## Section 3: Recommended Approach

**Selected path: Option 1 — Direct Adjustment (additive epics).**

| Option | Verdict | Rationale |
| --- | --- | --- |
| 1. Direct Adjustment | **Selected** | Backlog holds only the independent Fable epic; change is purely additive; existing architecture layers were built for reuse. Effort: High (full parity). Risk: Medium (undocumented API — mitigated by kill-gate spike). |
| 2. Rollback | Not viable | Nothing to roll back; no completed work conflicts. |
| 3. MVP Review | Not viable | MVP shipped long ago; this is post-MVP expansion, not scope reduction. |

**Risk assessment:**

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Codex endpoint unreachable outside ChatGPT web context (Cloudflare/CORS/device checks) | Medium | Fatal to phase | Spike 22.1 kill gate before any UI work |
| OpenAI changes undocumented API | Medium | Medium | Defensive parsing (all fields optional), graceful degradation — same pattern as Claude |
| Token refresh semantics unknown | Medium | Medium | Spike documents refresh; fallback UX: "run codex to refresh" status (mirrors Claude token-expiry UX) |
| SQLite migration corrupts Claude history | Low | High | Additive migration only; no destructive DDL; migration test against copy of real DB |
| Menu bar clutter (two items) | Low | Low | User-chosen; Codex item auto-hides when no `auth.json` present or tracking disabled |

**Timeline impact:** No existing commitments affected. Phase 7 is new work, roughly comparable in size to Phase 3 (epics 10–13).

---

## Section 4: Detailed Change Proposals

### 4.1 PRD (`_bmad-output/planning-artifacts/prd.md`)

**Edit 1 — Phase list: add Phase 7 after Phase 4 section.**

NEW:

```markdown
### Phase 7: Codex Usage Tracking

Extend cc-hdrm to monitor OpenAI Codex subscription limits alongside Claude, with full
feature parity for core tracking: dedicated menu bar item, popover panel, threshold
notifications, historical persistence, and analytics integration.

**Kill Condition:** If the Codex usage endpoint cannot be reached from a standalone
macOS process using `~/.codex/auth.json` credentials, Phase 7 is killed (spike story 22.1).

**Data source (to be validated by spike):**
- Credentials: `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`), JWT claims carry plan type
- Usage: `GET https://chatgpt.com/backend-api/wham/usage` — `rate_limit.primary_window`
  (5h session), `rate_limit.secondary_window` (weekly), `additional_rate_limits[]`,
  credits (balance / hasCredits / unlimited)
- Credits inventory: `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`
- Token refresh: mechanism TBD in spike

**Deferred beyond Phase 7:** Codex TPP, Codex unused-capacity breakdown, Codex tier
recommendation.
```

**Edit 2 — Functional Requirements: append new section.**

NEW:

```markdown
### Codex Usage Tracking (Phase 7)

- FR49: App can read Codex OAuth credentials from `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`) without user interaction, read-only
- FR50: App can detect the user's Codex plan type from stored credentials
- FR51: App can fetch current Codex usage data (5h primary window, weekly secondary window, credits) from the ChatGPT backend usage endpoint
- FR52: App can detect expired/invalid Codex credentials and display an actionable status message ("run codex to refresh" or equivalent validated by spike)
- FR53: User can see Codex 5h headroom in a dedicated second menu bar item with the same color/weight coding as Claude
- FR54: User can click the Codex menu bar item to expand a Codex panel with 5h and weekly gauges, reset countdowns, plan type, and credits balance when available
- FR55: User can see per-window slope indicators for Codex (menu bar + popover), reusing the 4-level slope model
- FR56: User can receive threshold notifications for Codex 5h and weekly windows at configurable headroom thresholds
- FR57: User can enable/disable Codex tracking in settings; the Codex menu bar item auto-hides when no credentials are found or tracking is disabled
- FR58: App persists Codex poll snapshots to SQLite with a provider dimension, participating in the existing tiered rollup strategy
- FR59: User can view Codex historical data in the analytics window via provider selection
- FR60: Codex polling failures degrade gracefully and independently — Claude tracking is never affected by Codex errors, and vice versa
```

**Edit 3 — Non-Functional Requirements: amend NFR8, add NFR14–NFR15.**

OLD:

```markdown
- NFR8: No credentials or usage data are transmitted to any endpoint other than `api.anthropic.com` (usage data) and `platform.claude.com` (token refresh)
```

NEW:

```markdown
- NFR8: No credentials or usage data are transmitted to any endpoint other than `api.anthropic.com` (Claude usage), `platform.claude.com` (Claude token refresh), and `chatgpt.com` (Codex usage; plus the Codex token-refresh endpoint documented by the Phase 7 spike)
- NFR14: Codex credentials are read from `auth.json` fresh each poll cycle, never written back, never persisted elsewhere, and never logged
- NFR15: Claude and Codex polling lanes are failure-isolated — an error in one provider's pipeline must not affect the other's display, notifications, or persistence
```

**Edit 4 — Phase 4: Future list: append deferred Codex items.**

NEW (appended to existing list):

```markdown
- Codex Token Efficiency Ratio, unused-capacity breakdown, tier recommendation (deferred from Phase 7)
```

### 4.2 Epic List (`_bmad-output/planning-artifacts/epics/epic-list.md`)

**Edit 5 — append four new epics after Epic 21.**

NEW:

```markdown
## Epic 22: Codex Data Pipeline & API Spike (Phase 7)

Alex uses Codex alongside Claude — cc-hdrm silently finds his Codex credentials in
`~/.codex/auth.json` and starts polling his usage. Story 22.1 is a kill-gate spike
mirroring the Claude API spike: validate endpoint reachability, document auth,
response format, and token refresh. Codex polling runs in its own failure-isolated lane.
**FRs covered:** FR49, FR50, FR51, FR52, FR60
**Stories:** 22.1 API Spike (kill gate), 22.2 Codex Credentials Service, 22.3 Codex API
Client & Defensive Parsing, 22.4 Codex Polling Lane & Expiry Handling

## Epic 23: Codex Menu Bar & Popover (Phase 7)

Alex glances at a second menu bar item and knows his Codex headroom instantly — same
color coding, same weight escalation. Clicking it opens a Codex popover with 5h and
weekly ring gauges, countdowns, plan type, credits balance, and slope indicators.
The item auto-hides when Codex isn't installed.
**FRs covered:** FR53, FR54, FR55, FR57 (auto-hide)
**Stories:** 23.1 Second Status Item & Headroom Display, 23.2 Codex Popover Panel,
23.3 Codex Error & Status States, 23.4 Codex Slope Indicators

## Epic 24: Codex Notifications & Settings (Phase 7)

Alex never hits the Codex wall by surprise — threshold notifications fire for both
Codex windows with reset context, and settings let him tune thresholds or switch
Codex tracking off entirely.
**FRs covered:** FR56, FR57
**Stories:** 24.1 Codex Threshold Notifications, 24.2 Codex Settings Integration

## Epic 25: Codex History & Analytics (Phase 7)

Alex's Codex usage builds the same permanent record his Claude usage does — poll
snapshots persisted with a provider dimension, rolled up on the existing tiers, and
explorable in the analytics window via provider selection.
**FRs covered:** FR58, FR59
**Stories:** 25.1 Provider-Dimension Schema Migration (additive, non-destructive),
25.2 Codex Poll Persistence & Rollups, 25.3 Analytics Provider Integration
```

### 4.3 Sprint Status (`_bmad-output/implementation-artifacts/sprint-status.yaml`)

**Edit 6 — append Phase 7 entries after the Fable block.**

NEW:

```yaml
  # Sprint Change Proposal 2026-08-12 (Codex) — Phase 7
  epic-22: backlog  # Codex Data Pipeline & API Spike — 22.1 is kill gate for Phase 7
  22-1-codex-api-spike: backlog
  22-2-codex-credentials-service: backlog
  22-3-codex-api-client-defensive-parsing: backlog
  22-4-codex-polling-lane-expiry-handling: backlog

  epic-23: backlog  # Codex Menu Bar & Popover
  23-1-second-status-item-headroom-display: backlog
  23-2-codex-popover-panel: backlog
  23-3-codex-error-status-states: backlog
  23-4-codex-slope-indicators: backlog

  epic-24: backlog  # Codex Notifications & Settings
  24-1-codex-threshold-notifications: backlog
  24-2-codex-settings-integration: backlog

  epic-25: backlog  # Codex History & Analytics
  25-1-provider-dimension-schema-migration: backlog
  25-2-codex-poll-persistence-rollups: backlog
  25-3-analytics-provider-integration: backlog
```

### 4.4 Architecture (`_bmad-output/planning-artifacts/architecture.md`)

**Edit 7 — Phase 7 addendum (summary; full addendum authored when Epic 22 spike results land, same pattern as prior phases).**

Key decisions to record:

- **New services:** `CodexCredentialsService` (only component reading `~/.codex/auth.json`), `CodexAPIClient` (only component calling `chatgpt.com`). Token refresh service only if the spike proves refresh is needed and feasible.
- **No premature provider abstraction.** Codex services are concrete siblings of the Claude services. A shared `Provider` protocol is introduced only if/when a third provider appears.
- **Polling:** second independent polling loop (own `Task`, own error mapping to a Codex-specific connection status in `AppState`). Failure isolation per NFR15.
- **State:** `AppState` gains a Codex section (usage, connection status, plan) — same one-way flow, services write via methods, views read-only.
- **UI:** second `NSStatusItem` with its own popover, reusing gauge/countdown/status-message components. Auto-hide when no credentials or disabled.
- **Persistence:** additive SQLite migration adding provider dimension. **Non-destructive** — existing Claude rows untouched (Story 17.5 lesson). Rollup engine parameterized by provider.
- **Boundaries table additions:**

| Boundary | Owner Component | Rule |
| --- | --- | --- |
| Codex credentials file | `CodexCredentialsService` | Only component reading `auth.json`; read-only |
| HTTP (Codex usage) | `CodexAPIClient` | Only component calling `chatgpt.com` |

### 4.5 UX Specification

**Edit 8 — Codex addendum (authored during Epic 23, informed by spike data):**

- Second menu bar item: distinct glyph (Claude keeps `✳`; Codex gets its own symbol — decided in 23.1) with identical color/weight escalation from `HeadroomState`.
- Codex popover mirrors Claude popover layout: 5h ring + weekly ring, countdowns, plan/freshness footer, credits line when credits exist.
- Both popovers reuse existing accessibility patterns (triple-encoded state: number + color + weight).

---

## Section 5: Implementation Handoff

**Scope classification: Moderate** — backlog reorganization (new phase, four epics), plus an architecture addendum. No fundamental replan: existing goals, MVP, and completed work are untouched.

| Role | Responsibility |
| --- | --- |
| SM (create-story workflow) | Create Story 22.1 first via `/bmad-bmm-create-story`; subsequent stories follow the standard BMAD lifecycle one at a time |
| Dev (dev-story workflow) | Implement 22.1 spike; report kill-gate verdict before any further Phase 7 story is created |
| Architect | Author the Phase 7 architecture addendum after spike results (endpoint, refresh, sandbox/entitlement findings) |
| User (Boss) | Kill/go decision on spike results; explicit instruction required if entitlements changes turn out to be needed |

**Sequencing & gates:**

1. Approve this proposal → update `sprint-status.yaml` + PRD + epic list.
2. Epic 22, Story 22.1 spike → **kill gate**. Go: continue. Kill: cancel epics 22–25, revert PRD Phase 7 to a "investigated, not feasible" note.
3. Epic 22 remainder → Epic 23 → Epics 24 and 25 (either order, independent).

**Success criteria:**

- Spike documents: auth format, endpoint contract, response schema, refresh mechanism, sandbox/file-access findings.
- Codex tracking meets the same bars as Claude: <60s staleness, failure isolation, zero false-negative notifications, no credential leakage to logs/disk.
- Claude functionality fully unaffected (regression: existing test suite stays green).
