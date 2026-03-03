# Sprint Change Proposal — 2026-03-02

**Author:** Boss
**Date:** 2026-03-02
**Scope:** Minor — Direct implementation by development team
**Status:** Approved

---

## Section 1: Issue Summary

Three user-identified UX improvements after completing Epics 1-18 (Phase 1 through Phase 5). The app is feature-complete but has three usability gaps:

1. **Clickable ring panels** — Ring gauges in the popover are the most prominent UI elements but non-interactive. Clicking the 5h ring should open the analytics window at the 24h view; clicking the 7d ring should open analytics at the 7d view.
2. **API downtime awareness** — API outages are shown visually (disconnected state) but never notified. Users have no historical record of when Anthropic's service was down. Graphs should show colored background regions during outage periods.
3. **First-run onboarding popup** — After Epic 18 introduced independent OAuth, first-time users see a bare "Sign In" button with no context. An automatic onboarding popup should explain what the app does and why sign-in is needed.

**Trigger:** User-identified improvement ideas, not triggered by a specific story failure.

---

## Section 2: Impact Analysis

### Epic Impact

| Epic                                       | Impact     | Details                                                                    |
| ------------------------------------------ | ---------- | -------------------------------------------------------------------------- |
| **Epic 4** (Detailed Usage Panel)          | Reopen     | Stories 4.2/4.3 ring gauges gain tap interaction                           |
| **Epic 5** (Threshold Notifications)       | Reopen     | New notification type: API connectivity transitions (down/up)              |
| **Epic 10** (Data Persistence)             | Reopen     | New table: persist API outage periods to SQLite                            |
| **Epic 12** (Sparkline/Analytics Launcher) | Minor note | Sparkline is no longer the only analytics launcher                         |
| **Epic 13** (Full Analytics Window)        | Reopen     | Support opening with pre-selected time range + outage background rendering |
| **Epic 18** (Independent OAuth)            | Extend     | First-run onboarding popup                                                 |

No epics invalidated. No new epics needed. No resequencing required.

### Artifact Conflicts

| Artifact         | Impact                                                                                          |
| ---------------- | ----------------------------------------------------------------------------------------------- |
| **PRD**          | Amend FR23 (no longer zero-config), amend FR36 (multiple analytics entry points), add FR49-FR52 |
| **UX Phase 1**   | Update ring gauge specs (clickable), update Journey 1 (OAuth sign-in, not zero-config)          |
| **UX Phase 3**   | Add outage background visual treatment, note ring gauges as additional analytics launchers      |
| **Architecture** | New api_outages table, outage tracker service, extended notification triggers                   |
| **Epic files**   | Add new stories to epics 4/5/10/13/18                                                           |

### Technical Impact

- **Database schema change** — New `api_outages` table (Change 2 only)
- **No architectural changes** — All changes extend existing patterns (notification state machine, chart rendering, tap gestures)
- **No infrastructure/deployment impact**

---

## Section 3: Recommended Approach

**Direct Adjustment** — Add 5 new stories across 5 existing epics.

**Rationale:**
- All infrastructure is in place (analytics window, notification service, database, polling engine)
- No architectural changes needed — each change extends proven patterns
- Low risk — additive features on top of stable, tested code
- No timeline disruption — can be prioritized independently

**Alternatives considered:**
- New "UX Polish" epic — rejected (changes map naturally to existing epics)
- Rollback — not applicable (nothing is broken)
- MVP scope change — not applicable (MVP shipped long ago)

---

## Section 4: Detailed Change Proposals

### Change 1: Clickable Ring Panels as Analytics Launchers

**PRD Amendment — FR36:**

Current:
> User can open a full analytics view in a separate window with zoomable historical charts across all retention periods

Proposed:
> User can open a full analytics view in a separate window with zoomable historical charts across all retention periods. User can open analytics from the sparkline (existing) or by clicking either ring gauge in the popover (5h ring opens 24h view, 7d ring opens 7d view).

**Story 4.2 (5-Hour Ring Gauge) — ADD acceptance criteria:**

- Given the 5h ring gauge section is visible in the popover
- When Alex clicks/taps anywhere in the 5h gauge section
- Then the analytics window opens (or comes to front) with "24h" time range pre-selected
- And the popover remains open
- And a subtle hover state indicates the gauge section is clickable
- And cursor changes to pointer (hand) on hover

**Story 4.3 (7-Day Ring Gauge) — ADD acceptance criteria:**

- Given the 7d ring gauge section is visible in the popover
- When Alex clicks/taps anywhere in the 7d gauge section
- Then the analytics window opens (or comes to front) with "7d" time range pre-selected
- And the popover remains open
- And a subtle hover state indicates the gauge section is clickable
- And cursor changes to pointer (hand) on hover

**Story 13.3 (Time Range Selector) — ADD acceptance criteria:**

- Given the analytics window is opened via a ring gauge click
- When `AnalyticsWindowController.show(timeRange:)` is called
- Then the window opens with the specified time range pre-selected instead of the default 24h
- And data loads for the specified range immediately

**UX Phase 3 — Analytics Launch Mechanism update:**

Analytics can be launched from three entry points:
1. Sparkline click → opens analytics at 24h (existing)
2. 5h ring gauge click → opens analytics at 24h
3. 7d ring gauge click → opens analytics at 7d

All three use `AnalyticsWindowController` and respect the "no duplicate window" rule.

**New Story — Clickable Ring Gauges as Analytics Launchers:**

As a developer using Claude Code, I want to click a ring gauge in the popover to open analytics for that time window, so that I can drill into detailed trends directly from the element I'm already looking at.

Acceptance Criteria:
- 5h gauge section click → analytics opens at 24h view
- 7d gauge section click → analytics opens at 7d view
- Hover shows pointer cursor + subtle background highlight
- If analytics is already open, brings to front and switches time range
- Popover stays open (same as sparkline click behavior)
- VoiceOver: gauge sections announce "Double-tap to open analytics"
- If historical data is unavailable (no SQLite data yet), click does nothing

**Implementation note:** `AnalyticsWindowController.toggle()` needs a variant or parameter: `show(timeRange: TimeRange)` that opens the window and sets the initial range.

**Effort:** Small

---

### Change 2: API Downtime Awareness

**PRD — New Functional Requirements:**

- **FR49:** App detects API connectivity transitions (reachable → unreachable, unreachable → reachable) and delivers macOS notifications for each transition
- **FR50:** App persists API outage periods (start timestamp, end timestamp, failure reason) to the local SQLite database for historical analysis
- **FR51:** User can see visually distinct background regions in analytics charts marking periods when the Claude API was unreachable due to Anthropic service failures (distinct from data gaps where cc-hdrm was not running)

**PRD — Disconnected Behavior section amendment — ADD:**

- Deliver macOS notification when API becomes unreachable (after 2+ consecutive failures): "Claude API is unreachable — monitoring continues"
- Deliver macOS notification when API recovers: "Claude API is back online"
- Persist outage periods for historical visualization

**Architecture — New Data Model:**

```sql
CREATE TABLE api_outages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at TEXT NOT NULL,       -- ISO 8601
    ended_at TEXT,                  -- ISO 8601, NULL if ongoing
    failure_reason TEXT NOT NULL    -- e.g., "networkUnreachable", "httpError:503"
);
```

**Design decision:** Notifications trigger after 2+ consecutive poll failures (matching existing backoff threshold) to avoid false alarms from momentary network blips. Graph backgrounds similarly only show outages that lasted beyond a minimum duration.

**Visual distinction:**
- Data gap (existing): hatched/grey — "cc-hdrm wasn't running"
- API outage (new): muted red/salmon tint — "Anthropic was down"
- Slope band (existing): warm tint — "burning fast"
- All three can coexist without visual conflict.

**New Story (Epic 5) — API Down/Up Notifications:**

As a developer using Claude Code, I want to be notified when the Claude API becomes unreachable and when it recovers, so that I know about Anthropic service disruptions even when I'm not looking at the menu bar.

Acceptance Criteria:
- After 2+ consecutive poll failures → notification: "Claude API unreachable" / "Monitoring continues — you'll be notified when it recovers"
- First successful poll after outage → notification: "Claude API is back" / "Service restored — usage data is current"
- Fire once per outage (not repeated during ongoing outage)
- If notification permission denied, visual fallback via menu bar (existing)
- "API status alerts" toggle in settings (default: on)

**New Story (Epic 10) — Outage Period Tracking & Persistence:**

As a developer using Claude Code, I want API outage periods stored in the database, so that analytics charts can show when Anthropic's service was down.

Acceptance Criteria:
- 2+ consecutive failures → insert `api_outages` record with `started_at`, `failure_reason`, `ended_at = NULL`
- First successful poll → update record with `ended_at`
- App quits during outage + relaunches with successful poll → close open record with relaunch time
- App quits during outage + relaunches with failed poll → existing open record remains open
- Query API: `getOutagePeriods(from:to:) -> [OutagePeriod]`

**New Story (Epic 13) — Outage Background Rendering in Analytics Charts:**

As a developer using Claude Code, I want to see colored background regions in analytics charts marking periods when the API was unreachable, so that I can distinguish "I wasn't using Claude" from "Anthropic was down."

Acceptance Criteria:
- Outage periods render as vertical background bands with muted red/salmon tint
- Bands span full chart height behind data
- Hover tooltip: "API outage: [duration]" with start/end times
- Legend entry: colored swatch + "API outage" (only when outages exist in visible range)
- If both data gap AND outage overlap, outage background takes precedence
- No outage data in visible range → no background or legend entry

**Effort:** Medium (3 stories across 3 epics)

---

### Change 3: First-Run Onboarding Popup

**PRD Amendments:**

**FR23** (current):
> App can launch and display usage data without any manual configuration

**FR23** (proposed):
> App can launch and begin the authentication flow with minimal user effort — a one-time browser sign-in is required on first launch

**NEW FR52:** On first launch (no stored credentials), the app presents a welcoming onboarding popup explaining that sign-in is required, what the app does, and a single action button to start the OAuth flow.

**UX Phase 1 — Journey 1 update:**

Current: "He launches the app. No login screen, no setup wizard, no config file. A small 42% appears in his menu bar within seconds."

Proposed: "He launches the app. A friendly popup greets him: cc-hdrm monitors his Claude subscription usage from the menu bar — he just needs to sign in once with his Anthropic account. He clicks 'Sign In', approves in his browser, and within seconds a small 42% appears in his menu bar. He exhales. For the first time, he knows exactly where he stands."

**New Story (Epic 18) — First-Run Onboarding Popup:**

As a first-time cc-hdrm user, I want to see a welcoming popup explaining what the app does and that sign-in is needed, so that I understand why I'm being asked to authenticate and feel confident proceeding.

Acceptance Criteria:

- Given the app launches for the first time (no stored credentials, `hasCompletedOnboarding = false`)
- When AppDelegate finishes initialization
- Then the onboarding popup appears automatically as a centered NSPanel (not attached to menu bar) within 1 second of launch
- And the menu bar icon is visible behind the popup showing "✳ —"

Popup content:
- App icon and name
- Brief description: "cc-hdrm shows your Claude subscription usage in the menu bar — always visible, zero tokens spent."
- Explanation: "Sign in with your Anthropic account to get started. This is a one-time setup."
- Primary button: "Sign In" (triggers OAuth flow, dismisses popup)
- Secondary button: "Later" (dismisses popup, shows existing unauthenticated popover state)

Behavioral rules:
- Popup is modal (clicking outside does not dismiss)
- Popup does NOT reappear after dismissal (either via Sign In or Later)
- "Later" does not suppress the Sign In button in the popover (existing behavior)
- Previously authenticated users who signed out do NOT see the onboarding popup (only true first-run)
- Detection: UserDefaults `hasCompletedOnboarding` flag (NOT credential presence)
- Flag set to `true` when user clicks Sign In OR Later (both mean they've seen onboarding)
- VoiceOver: all text accessible, "Sign In" button focused by default

**Effort:** Small

---

## Section 5: Implementation Handoff

### Scope Classification: Minor

All three changes are direct implementation by the development team. No PO/PM/Architect escalation needed.

### Suggested Priority Order

1. **Change 3: Onboarding popup** — Fixes a real first-impression gap for every new user
2. **Change 1: Ring click** — Straightforward UX win, low effort
3. **Change 2: API downtime** — Most complex, builds on 1 & 3 being done

### New Stories Summary

| Story                       | Epic      | Description                             | Effort |
| --------------------------- | --------- | --------------------------------------- | ------ |
| Clickable Ring Gauges       | Epic 4/13 | 5h/7d ring → analytics at 24h/7d        | Small  |
| API Down/Up Notifications   | Epic 5    | Notify on connectivity transitions      | Small  |
| Outage Period Persistence   | Epic 10   | Track outage start/end in SQLite        | Medium |
| Outage Background in Charts | Epic 13   | Colored background bands for outages    | Medium |
| First-Run Onboarding Popup  | Epic 18   | Automatic welcome popup on first launch | Small  |

### Workflow

Each story follows the standard BMAD lifecycle:
1. SM creates story via `/bmad-bmm-create-story`
2. Dev implements via `/bmad-bmm-dev-story`
3. Code review via `/bmad-bmm-code-review`
4. PR + CI + CodeRabbit → Merge

### Artifact Updates Required

Before story creation:
- [ ] Update PRD: amend FR23, FR36, add FR49-FR52
- [ ] Update UX Phase 1: Journey 1, ring gauge behavior
- [ ] Update UX Phase 3: outage background spec, analytics launch points
- [ ] Update epic files: add new stories
- [ ] Update sprint-status.yaml: add new story entries
