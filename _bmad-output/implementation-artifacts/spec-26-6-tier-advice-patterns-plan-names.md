---
title: 'Tier Advice, Patterns and Plan Names (Story 26.6)'
type: 'feature'
created: '2026-11-01'
status: 'done'
baseline_commit: '3550adf0087e577a6719bebb66e6d7a1696d5c8d'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-26-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** With no 5-hour number, the missing peak counts as 0, so every cheaper plan passes its 5-hour check and headroom reads 100%. Forgotten-subscription and usage-decay findings never fire. Plan names are also out of date.

**Approach:** Weekly cycles drive advice and patterns. Every change applies only when weekly cycles or no-number polls are present, so accounts with a number follow the 1.6.0 path. Max 20x shows as "Ultra" and Max 5x as "Max".

## Boundaries & Constraints

**Always:** Accounts with a number match 1.6.0, proven by tests. Raw tier strings stay as they are. Unknown tier strings stay percentage-only. An unknown string is logged once at INFO with public privacy.

**Ask First:** Nothing open. This runs unattended, so defaults are in Design Notes.

**Never:** Add a guessed tier string. Change a credit value. Decide from a plan name or cutover date. Run `DELETE` or `DROP`, change the schema, read the Keychain or open the real `usage.db` by hand. Modify `cc-hdrm/cc_hdrm.entitlements`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Weekly-only, heavy | Ultra, cycles at 70% | good fit, 30% headroom | N/A |
| Weekly-only, moderate | Ultra, cycles at 30% | no downgrade: Max's 5-hour limit cannot be checked | N/A |
| Weekly-only, tiny | Ultra, cycles at 3% | downgrade to Max: the whole week fits one 5-hour window | N/A |
| Weekly exhausted | Pro, cycles at 100% | upgrade to Max, rate limits counted from weekly | N/A |
| Mixed, old high 5-hour peak | Max, old peak 100%, cycles at 20% | good fit, not "needs Ultra" | N/A |
| Mixed, overlap | 5-hour events inside a cycle's 7 days | left out of peaks and counts | N/A |
| Number, sleep gap | empty-peak row, no cycles | same result as 1.6.0 | N/A |
| Forgotten, no number | weekly peak under 5% for 2 weeks | finding, using the weekly peak | N/A |
| Decay, no number | monthly cycle peaks fall for 3 months | finding, using cycle peaks only | N/A |
| Unknown tier | weekly cycles on an unknown string | no advice, no credits, no crash | logged once at INFO |

</frozen-after-approval>

## Code Map

- `cc-hdrm/Models/RateLimitTier.swift` -- `displayName`, `resolve`, the once-only log.
- `cc-hdrm/Models/ResetEvent.swift` -- `excludingWeeklyOverlap()` returns its input when no cycle exists, which keeps the 1.6.0 path. Gains `endsInWeeklyCycle`.
- `cc-hdrm/Services/TierRecommendationService.swift` -- fit check, headroom, rate-limit count, data span.
- `cc-hdrm/Services/SubscriptionPatternDetector.swift` -- forgotten, overpaying and decay read 5-hour values. Underpowering and both extra-usage patterns already work without them.
- `cc-hdrm/Models/KeychainCredentials.swift`, `cc-hdrm/Services/PollingEngine.swift`, `cc-hdrm/Views/PopoverFooterView.swift` -- the footer shows the raw "max" for an Ultra account.
- Read-only evidence: `cc-hdrm/Models/TierRecommendation.swift` fingerprints use `rawValue`. `cc-hdrm/Models/PatternFinding.swift` `cooldownKey` uses the finding type. Nothing stores or compares `displayName`.

## Tasks & Acceptance

**Execution:**
- [x] `cc-hdrm/Models/RateLimitTier.swift` -- new names, unknown string logged once.
- [x] `cc-hdrm/Models/ResetEvent.swift` -- add `endsInWeeklyCycle`.
- [x] `cc-hdrm/Services/TierRecommendationService.swift` -- use counted events and a weekly fit check when the account ends in a cycle.
- [x] `cc-hdrm/Services/SubscriptionPatternDetector.swift` -- weekly inputs for forgotten, overpaying and decay.
- [x] `cc-hdrm/Models/KeychainCredentials.swift`, `cc-hdrm/Services/PollingEngine.swift` -- footer shows the current plan name.
- [x] `cc-hdrmTests/Services/NoFiveHourAdviceTests.swift` -- the matrix, plus proofs for accounts with a number.
- [x] `cc-hdrmTests/Models/RateLimitTierTests.swift`, `cc-hdrmTests/Models/KeychainCredentialsTests.swift` -- names, log-once and plan name.
- [x] Existing tests that assert the old names -- use the new names.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` -- record what was found and left alone.
- [x] `_bmad-output/implementation-artifacts/sprint-status.yaml` -- set `26-6-tier-advice-patterns-plan-names: done` only.

**Acceptance Criteria:**
- Given weekly-only history, when advice and patterns run, then they use non-zero weekly inputs and show no downgrade bias.
- Given an account with a number, when advice and patterns run, then results match 1.6.0.
- Given mixed history, when advice runs, then overlapping events are not counted and no 5-hour capacity decides the account's own plan or a dearer one.
- Given any known tier, when a user reads a plan name, then it says Pro, Max or Ultra.

## Spec Change Log

- Review round 1. Findings: a downgrade could slip through for an account back on a number; the card and the notification disagreed between 3.3% and 3.96%; old 5-hour hits inflated the rate-limit count; a known tier hid a team label. Amended Design Notes for each. Patched in place rather than reverted, because the fixes shrink the code and keep its tests. KEEP: the 1.6.0 path stays reachable unchanged when no cycle is counted.

## Design Notes

Defaults chosen, since no human is available:
- **"No number" for advice:** the latest counted event is a weekly cycle. An account back on a number returns to its 5-hour peaks, but counted cycles still bind cheaper plans.
- **Cheaper plans:** they all have a 5-hour limit that a weekly-only history cannot check. So a downgrade needs the highest cycle's whole credits, plus the 20% margin, to fit under that limit. Only about 3.3% or less of Ultra's weekly passes for Max. Above that, the card says Ultra is a good fit and shows the real headroom. Measuring the largest 5-hour rise in weekly use would allow more downgrades, but needs more code and relies on unpublished 5-hour credits. The chronic-overpaying pattern uses the same bound and margin, so the card and the notification agree.
- **Own plan and dearer plans:** judged on weekly only. This is what stops "needs Ultra" for a 5-hour limit the account does not have. No plan name is checked: Ultra is simply never a cheaper plan.
- **Old 5-hour peaks:** still count against cheaper plans, because those plans keep the limit.
- **Headroom and rate-limit count:** from weekly cycles only when the account ends in a cycle, so bases are not mixed.
- **Minimum data:** a first event that is a weekly cycle stands for its 7 days, so two cycles make 14 days.
- **Forgotten:** a calendar week with no 5-hour values uses its highest weekly value. It reads polls, because an idle account may report no reset and so record no cycle.
- **Decay:** cycle peaks per month, not rollups. Old months have no cycles and are left out, so a changed account waits for 4 months of cycles. This avoids comparing two bases. Rollup peaks were rejected: daily rows read higher than 5-minute rows, which would look like decay.
- **Footer:** shows the current name when the tier is known, so "pro" becomes "Pro" and "max" becomes "Max" or "Ultra". An unknown tier, or a team or enterprise account, keeps what the account reports.
- **Log-once:** runs before the custom-limits branch, which otherwise logs nothing. Once per launch per string. The existing warning is untouched.
- **Old unflagged rows:** an account's history before its first flagged cycle stays on the 1.6.0 path.

## Verification

**Commands:**
- `xcodegen generate` -- expected: project created, so the new test file compiles.
- `/usr/bin/lockf -k /tmp/cchdrm-xcodebuild.lock nice -n 15 xcodebuild -jobs 4 -project cc-hdrm.xcodeproj -scheme cc-hdrm -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= test` -- expected: all tests pass.

**Manual checks (if no CLI):**
- Not run: no app launches on this machine. On a real Ultra account, start `log stream --level info --predicate 'subsystem == "com.cc-hdrm.app" AND category == "tier"'` before launching the app, because macOS does not keep INFO lines on disk by default. Check the card after two weekly cycles.

## Suggested Review Order

**The decision**

- Entry point: a cheaper plan must hold a whole week; own and dearer plans ignore old 5-hour peaks.
  [`TierRecommendationService.swift:87`](../../cc-hdrm/Services/TierRecommendationService.swift#L87)

- One rule for "reports no number now", from recorded cycles rather than plan name.
  [`ResetEvent.swift:61`](../../cc-hdrm/Models/ResetEvent.swift#L61)

- Headroom and rate-limit count read one basis, never both.
  [`TierRecommendationService.swift:216`](../../cc-hdrm/Services/TierRecommendationService.swift#L216)

- A first cycle stands for its 7 days, so two cycles reach the minimum.
  [`TierRecommendationService.swift:191`](../../cc-hdrm/Services/TierRecommendationService.swift#L191)

**Patterns**

- Same whole-week bound and margin as the card, so the two agree.
  [`SubscriptionPatternDetector.swift:209`](../../cc-hdrm/Services/SubscriptionPatternDetector.swift#L209)

- A week with no 5-hour values uses its weekly peak.
  [`SubscriptionPatternDetector.swift:104`](../../cc-hdrm/Services/SubscriptionPatternDetector.swift#L104)

- Decay picks one basis; months from before the change are left out.
  [`SubscriptionPatternDetector.swift:326`](../../cc-hdrm/Services/SubscriptionPatternDetector.swift#L326)

- Cycle peaks per month, free of rollup resolution bias.
  [`SubscriptionPatternDetector.swift:486`](../../cc-hdrm/Services/SubscriptionPatternDetector.swift#L486)

**Plan names and unknown tiers**

- Display names change; raw strings stay.
  [`RateLimitTier.swift:44`](../../cc-hdrm/Models/RateLimitTier.swift#L44)

- Once per launch per string, ahead of the custom-limits branch.
  [`RateLimitTier.swift:94`](../../cc-hdrm/Models/RateLimitTier.swift#L94)

- The footer gets the current name; team and enterprise keep their label.
  [`KeychainCredentials.swift:15`](../../cc-hdrm/Models/KeychainCredentials.swift#L15)

- Both footer update points.
  [`PollingEngine.swift:149`](../../cc-hdrm/Services/PollingEngine.swift#L149)

**Tests**

- Moderate use refuses a downgrade the old check would give.
  [`NoFiveHourAdviceTests.swift:177`](../../cc-hdrmTests/Services/NoFiveHourAdviceTests.swift#L177)

- Back on a number: old cycles still bind cheaper plans.
  [`NoFiveHourAdviceTests.swift:261`](../../cc-hdrmTests/Services/NoFiveHourAdviceTests.swift#L261)

- A number keeps the 1.6.0 downgrade at the same usage.
  [`NoFiveHourAdviceTests.swift:284`](../../cc-hdrmTests/Services/NoFiveHourAdviceTests.swift#L284)

- Decay never compares two bases.
  [`NoFiveHourAdviceTests.swift:384`](../../cc-hdrmTests/Services/NoFiveHourAdviceTests.swift#L384)
