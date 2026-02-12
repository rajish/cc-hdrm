# Story 16.5: Context-Aware Insight Engine

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want the analytics value section to choose the single most relevant conclusion from multiple valid lenses,
so that the display tells me what matters most right now instead of showing every metric at once.

## Acceptance Criteria

1. **Given** the analytics value section has multiple data sources available (subscription value, pattern findings, tier recommendation, usage trend)
   **When** the context-aware insight engine evaluates what to display
   **Then** it selects insights by priority:
   1. Active pattern findings (forgotten subscription, chronic mismatch) -- highest priority
   2. Tier recommendation (actionable downgrade/upgrade) -- high priority
   3. Notable usage deviation from personal baseline -- medium priority
   4. Subscription value summary -- default fallback

2. **Given** multiple insights compete for display
   **When** the value section renders
   **Then** the highest-priority insight is shown prominently
   **And** a secondary insight may appear as a subdued one-liner below
   **And** no more than two insights are shown simultaneously

3. **Given** the user dismisses an insight card
   **When** the value section re-evaluates
   **Then** the next-priority insight promotes to the primary position
   **And** the dismissed insight does not reappear until conditions change materially

4. **Given** insights are displayed
   **When** the text is generated
   **Then** it uses natural language, not raw numbers:
   - "About three-quarters" not "76.2%"
   - "Your heaviest week since November" not "Peak: 847,291 credits"
   - "Roughly double your usual" not "198% of average"
   **And** precise values are available on hover/VoiceOver for users who want them

5. **Given** the emotional tone of the data varies
   **When** insights are composed
   **Then** tone matches context:
   - High utilization near reset: cautious, not celebratory
   - Low utilization with headroom: reassuring, not accusatory
   - Chronic pattern detected: matter-of-fact, not alarmist

## Tasks / Subtasks

- [x] Task 1: Extend ValueInsight model for priority and hover detail (AC: 1, 4)
  - [x] 1.1 Add `priority: InsightPriority` enum to `cc-hdrm/Services/ValueInsightEngine.swift` -- cases: `.patternFinding`, `.tierRecommendation`, `.usageDeviation`, `.summary` (descending priority)
  - [x] 1.2 Add `preciseDetail: String?` to `ValueInsight` for hover/VoiceOver tooltip (e.g., "76.2% of $200 monthly limit")
  - [x] 1.3 Keep existing `text` and `isQuiet` properties unchanged for backward compatibility

- [x] Task 2: Add natural language formatting helpers (AC: 4)
  - [x] 2.1 Create `cc-hdrm/Services/NaturalLanguageFormatter.swift`
  - [x] 2.2 Implement `formatPercentNatural(_ value: Double) -> String` -- "about three-quarters", "roughly half", "nearly all", "a small fraction" etc. based on value ranges
  - [x] 2.3 Implement `formatComparisonNatural(current: Double, baseline: Double) -> String` -- "roughly double your usual", "about a third less than typical", "close to your average"
  - [x] 2.4 Implement `formatRelativeTimeNatural(monthName: String, year: Int?) -> String` -- "since November", "since March 2025"
  - [x] 2.5 Make all methods static on an enum (same pattern as `ValueInsightEngine`)

- [x] Task 3: Refactor ValueInsightEngine to produce prioritized insights (AC: 1, 2, 4, 5)
  - [x] 3.1 Add `computeInsights()` (plural) method to `cc-hdrm/Services/ValueInsightEngine.swift` returning `[ValueInsight]` sorted by priority
  - [x] 3.2 Keep existing `computeInsight()` as usage-specific method (not a wrapper — `computeInsights()` calls `computeInsight()` internally, so wrapping would cause infinite recursion)
  - [x] 3.3 Integrate `NaturalLanguageFormatter` into text generation -- replace raw percentages with natural language where appropriate
  - [x] 3.4 Add `preciseDetail` to each insight for tooltip access
  - [x] 3.5 Add tone-matching logic: cautious near high utilization, reassuring at low utilization, matter-of-fact for patterns

- [x] Task 4: Add insight prioritization for pattern findings and tier recommendations (AC: 1, 3)
  - [x] 4.1 Add `static func insightFromPatternFinding(_ finding: PatternFinding) -> ValueInsight` to `ValueInsightEngine`
  - [x] 4.2 Add `static func insightFromTierRecommendation(_ recommendation: TierRecommendation) -> ValueInsight` to `ValueInsightEngine`
  - [x] 4.3 These convert existing types into `ValueInsight` with appropriate priority, natural language text, and tone

- [x] Task 5: Create InsightStack view component (AC: 2, 3)
  - [x] 5.1 Create `cc-hdrm/Views/InsightStack.swift`
  - [x] 5.2 Accept `insights: [ValueInsight]` (pre-sorted by priority)
  - [x] 5.3 Show first insight as primary (`.caption` font, `.primary` foreground)
  - [x] 5.4 Show second insight as subdued one-liner (`.caption2` font, `.tertiary` foreground)
  - [x] 5.5 Cap at 2 visible insights maximum
  - [x] 5.6 Add `.help()` tooltip modifier with `preciseDetail` for hover access (AC 4)
  - [x] 5.7 Add VoiceOver: combined accessibility label with precise detail

- [x] Task 6: Integrate InsightStack into AnalyticsView value section (AC: 1, 2, 3)
  - [x] 6.1 Replace standalone `ContextAwareValueSummary` in `cc-hdrm/Views/AnalyticsView.swift` with `InsightStack`
  - [x] 6.2 Build combined insight list: pattern findings + tier recommendation + usage insight from ValueInsightEngine
  - [x] 6.3 Filter out dismissed items (reuse existing dismissal checks)
  - [x] 6.4 Sort by priority and pass to InsightStack
  - [x] 6.5 On dismiss of primary insight, next insight promotes automatically (list re-sorts without dismissed item)

- [x] Task 7: Write unit tests for NaturalLanguageFormatter (AC: 4)
  - [x] 7.1 Create `cc-hdrmTests/Services/NaturalLanguageFormatterTests.swift`
  - [x] 7.2 Test percent ranges: 0-10% -> "a small fraction", 20-30% -> "about a quarter", 45-55% -> "roughly half", 70-80% -> "about three-quarters", 90-100% -> "nearly all"
  - [x] 7.3 Test comparison formatting: 2x -> "roughly double", 0.5x -> "about half", 1.0x -> "close to your average"
  - [x] 7.4 Test relative time formatting with and without year

- [x] Task 8: Write unit tests for extended ValueInsightEngine (AC: 1, 2, 5)
  - [x] 8.1 Add tests in `cc-hdrmTests/Services/ValueInsightEngineTests.swift` (existing file)
  - [x] 8.2 Test `computeInsights()` returns multiple insights sorted by priority
  - [x] 8.3 Test pattern finding conversion produces `.patternFinding` priority
  - [x] 8.4 Test tier recommendation conversion produces `.tierRecommendation` priority
  - [x] 8.5 Test `preciseDetail` is populated for each insight type
  - [x] 8.6 Test tone matching: high utilization produces cautious text, low utilization produces reassuring text

- [x] Task 9: Run `xcodegen generate` and verify compilation + all tests pass

## Dev Notes

### Architecture Context

This story transforms the current fixed-order value section (bar -> pattern cards -> tier card -> summary) into a priority-driven insight system. The key change is centralizing insight selection logic in `ValueInsightEngine` rather than having each component independently decide its visibility.

**Current state (before this story):**
- `HeadroomBreakdownBar` has its own visibility logic (quiet detection, data span check)
- `PatternFindingCard` cards render independently with dismissal filtering
- `TierRecommendationCard` renders independently with fingerprint-based dismissal
- `ContextAwareValueSummary` renders a single text line from `ValueInsightEngine`

**Target state (after this story):**
- `HeadroomBreakdownBar` remains unchanged (it's a data visualization, not an insight)
- Pattern findings and tier recommendations are convertible to `ValueInsight` entries
- `InsightStack` replaces `ContextAwareValueSummary`, showing up to 2 prioritized insights
- The existing card components (`PatternFindingCard`, `TierRecommendationCard`) remain for their visual treatment — `InsightStack` provides the textual summary below them
- Dismissal of cards causes the summary text in `InsightStack` to re-evaluate

**Important: This is NOT a wholesale replacement of the card system.** The existing cards (pattern findings, tier recommendation) continue to render in their current positions. `InsightStack` replaces only the `ContextAwareValueSummary` text line, adding priority awareness and natural language improvements to that summary. The cards and the summary coexist.

### Key Integration Points

**Files consumed (read-only):**
- `cc-hdrm/Models/PatternFinding.swift` -- 6-case enum with `title`, `summary`, `cooldownKey` (Story 16.1)
- `cc-hdrm/Models/TierRecommendation.swift` -- 3-case enum with `recommendationFingerprint`, `isActionable` (Stories 16.3, 16.4)
- `cc-hdrm/Services/SubscriptionValueCalculator.swift` -- `SubscriptionValue` struct and `calculate()` (Story 14.4)
- `cc-hdrm/Services/HeadroomAnalysisServiceProtocol.swift` -- `aggregateBreakdown(events:)` (Story 14.2)

**Files to create:**
- `cc-hdrm/Services/NaturalLanguageFormatter.swift` -- NEW, natural language helpers
- `cc-hdrm/Views/InsightStack.swift` -- NEW, prioritized insight display (replaces ContextAwareValueSummary)
- `cc-hdrmTests/Services/NaturalLanguageFormatterTests.swift` -- NEW, formatter tests

**Files to modify:**
- `cc-hdrm/Services/ValueInsightEngine.swift` -- add `InsightPriority` enum, `preciseDetail` to `ValueInsight`, `computeInsights()` method, insight conversion methods
- `cc-hdrm/Views/AnalyticsView.swift` -- replace `ContextAwareValueSummary` with `InsightStack`, build combined insight list

**Files to potentially deprecate (but keep for now):**
- `cc-hdrm/Views/ContextAwareValueSummary.swift` -- functionality absorbed into `InsightStack`. Keep the file but mark as deprecated, or remove if no other consumers exist.

**Existing mocks available:**
- `cc-hdrmTests/Mocks/MockPreferencesManager.swift` -- has `dismissedPatternFindings`, `dismissedTierRecommendation`
- `cc-hdrmTests/Mocks/MockTierRecommendationService.swift` -- has `recommendTier(for:)` stub

### InsightStack Design

```
Primary insight (caption, primary color):
  "Your heaviest week since November"          [hover: "87.3% vs 52% average"]

Secondary insight (caption2, tertiary color):
  "Pro would save you ~$80/mo"
```

- Maximum 2 insights shown
- Primary insight gets `.caption` font, `.primary` foreground
- Secondary insight gets `.caption2` font, `.tertiary` foreground
- Both have `.help()` tooltip with `preciseDetail` for hover
- VoiceOver reads combined label including precise values

### Natural Language Formatting

Percent ranges and their natural language equivalents:

| Range | Natural Language |
|-------|-----------------|
| 0-10% | "a small fraction" |
| 10-20% | "about a tenth" |
| 20-30% | "about a quarter" |
| 30-40% | "about a third" |
| 40-60% | "roughly half" |
| 60-70% | "about two-thirds" |
| 70-80% | "about three-quarters" |
| 80-90% | "most" |
| 90-100% | "nearly all" |

Comparison phrases:
- Ratio > 1.8: "roughly double your usual"
- Ratio 1.3-1.8: "noticeably more than typical"
- Ratio 0.7-1.3: "close to your average"
- Ratio 0.4-0.7: "noticeably less than typical"
- Ratio < 0.4: "about half your usual"

### Tone Matching (AC 5)

Tone is determined by utilization context:

- **High utilization (>80%) near reset window:** Cautious tone. "You're running close to your limit" not "Great usage!"
- **Low utilization (<20%) with headroom:** Reassuring. "Plenty of room left" not "You're barely using your plan"
- **Chronic pattern:** Matter-of-fact. "Usage has been declining for 3 months" not "Warning: declining usage detected!"
- **Quiet (20-80%):** Neutral. Standard dollar or percentage summary.

### Potential Pitfalls

1. **Don't break existing card visibility:** The `PatternFindingCard` and `TierRecommendationCard` components must continue rendering in their current positions. `InsightStack` replaces only the text summary line, not the cards themselves.

2. **Backward compatibility of `computeInsight()`:** Existing callers (ContextAwareValueSummary, isQuietValueInsight) use the single-insight API. Keep it working by delegating to `computeInsights().first`.

3. **Don't over-convert to natural language:** Dollar amounts and tier names should remain precise (e.g., "$80/mo", "Pro"). Only utilization percentages and relative comparisons get natural language treatment.

4. **Hover tooltip on macOS:** Use SwiftUI's `.help()` modifier for tooltips. This is native macOS behavior — no custom popover needed.

5. **Testing tone is subjective:** Focus tests on verifiable outputs (e.g., "cautious" text contains certain phrases, "reassuring" text contains others) rather than testing the emotion itself.

6. **InsightStack must handle 0 insights gracefully:** When no data sources produce insights (fresh install), show a simple "No data yet" fallback.

7. **Priority ties:** When multiple insights share the same priority level (e.g., two pattern findings), use the existing order from `patternFindings` array (which comes from `analyzePatterns()`).

8. **Don't duplicate pattern/recommendation info in summary:** If a PatternFindingCard is already visible, the InsightStack should not repeat its content. The insight engine should detect when a pattern finding is already shown as a card and skip it for the text summary.

### Previous Story Intelligence

Key learnings from Stories 16.2 and 16.4:
- **Card components are pure views:** PatternFindingCard and TierRecommendationCard accept data + onDismiss. They don't fetch data themselves. Follow this pattern.
- **Static text builders for testability:** Both card components use static methods. InsightStack's text generation should be static/testable too via ValueInsightEngine.
- **AnalyticsView value section order:** HeadroomBreakdownBar -> patternFindingCards -> tierRecommendationCard -> ContextAwareValueSummary. InsightStack replaces only the last item.
- **Quiet detection drives bar visibility:** `isQuietValueInsight` already uses `ValueInsightEngine.computeInsight()`. Ensure `computeInsights()` produces consistent quiet flags.
- **ValueInsightEngine is a pure enum:** No stored state, all methods are static. Maintain this pattern.

### Git Intelligence

Recent commits:
- `36e060f` (Story 16.4): TierRecommendationCard, billing cycle picker, fingerprint dismissal
- `def04b8` (Story 16.2): PatternFindingCard, notification delivery, cooldown persistence
- `b3d9d79` (PR 53): Fixed negative savings in tier cost comparison
- `5bfec97` (Story 16.1): SubscriptionPatternDetector with 6 pattern types
- `a4d1bf4` (Story 16.3): TierRecommendationService, billingCycleDay preference

### Project Structure Notes

New files to create:
```
cc-hdrm/Services/NaturalLanguageFormatter.swift            # NEW - Natural language helpers
cc-hdrm/Views/InsightStack.swift                           # NEW - Prioritized insight display
cc-hdrmTests/Services/NaturalLanguageFormatterTests.swift   # NEW - Formatter tests
```

Files to modify:
```
cc-hdrm/Services/ValueInsightEngine.swift                  # EXTEND with priority, plural insights, tone
cc-hdrm/Views/AnalyticsView.swift                          # REPLACE ContextAwareValueSummary with InsightStack
```

After adding files, run `xcodegen generate` to regenerate the Xcode project.

### References

- [Source: _bmad-output/planning-artifacts/epics/epic-16-subscription-intelligence-phase-4.md:238-291] - Story 16.5 acceptance criteria
- [Source: cc-hdrm/Services/ValueInsightEngine.swift:1-283] - Current ValueInsightEngine (computeInsight, monthly utilizations, quiet detection)
- [Source: cc-hdrm/Views/ContextAwareValueSummary.swift:1-44] - Current summary view (to be replaced by InsightStack)
- [Source: cc-hdrm/Views/AnalyticsView.swift:103-145] - Value section rendering order
- [Source: cc-hdrm/Views/AnalyticsView.swift:154-177] - isQuietValueInsight logic using ValueInsightEngine
- [Source: cc-hdrm/Views/PatternFindingCard.swift:1-36] - Pattern card visual style
- [Source: cc-hdrm/Views/TierRecommendationCard.swift:1-98] - Tier recommendation card
- [Source: cc-hdrm/Models/PatternFinding.swift:1-78] - 6-case pattern finding enum
- [Source: cc-hdrm/Models/TierRecommendation.swift:1-53] - 3-case recommendation enum with fingerprint
- [Source: cc-hdrm/Services/SubscriptionValueCalculator.swift:1-101] - SubscriptionValue struct
- [Source: _bmad-output/implementation-artifacts/16-2-pattern-notification-analytics-display.md] - Story 16.2 (PatternFindingCard predecessor)
- [Source: _bmad-output/implementation-artifacts/16-4-tier-recommendation-display-billing-cycle.md] - Story 16.4 (TierRecommendationCard predecessor)

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

None — all tests passed on first run after implementation.

### Completion Notes List

- **Task 1**: Added `InsightPriority` enum (4 cases: patternFinding=3, tierRecommendation=2, usageDeviation=1, summary=0) and `preciseDetail: String?` to `ValueInsight`. Backward-compatible init with defaults.
- **Task 2**: Created `NaturalLanguageFormatter` enum with 4 static methods: `formatPercentNatural` (9 ranges), `formatComparisonNatural` (5 ratio bands), `formatRelativeTimeNatural` (year-aware), `monthName`.
- **Task 3**: Integrated NaturalLanguageFormatter into all 4 insight methods (day/week/month/all). Added `preciseDetail` to every usage insight. Implemented tone-matching: >80% util produces cautious text ("Close to limit", "Running close to limit"), <20% produces reassuring text ("Plenty of room", "Light usage"), 20-80% uses NL ("Roughly half of today's capacity"). Dollar amounts stay precise per Dev Notes. Note: `computeInsight()` kept as the usage-specific implementation (not a wrapper for `computeInsights().first`) to avoid infinite recursion since `computeInsights()` calls `computeInsight()` internally.
- **Task 4**: Added `insightFromPatternFinding` (uses finding.summary as text, finding.title as preciseDetail) and `insightFromTierRecommendation` (uses TierRecommendationCard.buildSummary, returns nil for .goodFit).
- **Task 5**: Created `InsightStack` view — primary insight with .caption/.primary, secondary with .caption2/.tertiary, capped at 2, .help() tooltip for preciseDetail, combined VoiceOver label.
- **Task 6**: Replaced `ContextAwareValueSummary` usage in AnalyticsView with `InsightStack`. Builds combined insight list from visible pattern findings, visible tier recommendation, and usage insight. Dismissed items filtered before passing to InsightStack.
- **Task 7**: 16 NaturalLanguageFormatter tests covering all percent ranges, comparison ratios, relative time with/without year, and monthName.
- **Task 8**: Extended ValueInsightEngineTests with 5 preciseDetail tests (day dollar, week comparison, all-time, pattern finding, tier recommendation) and 5 tone-matching tests (high util cautious, low util dollar reassuring, low util percentage reassuring, neutral NL, pattern matter-of-fact).
- **Task 9**: xcodegen generate succeeded. 1036 tests in 90 suites — all pass, zero failures.

### Change Log

- 2026-02-12: Implemented Story 16.5 — context-aware insight engine with NL formatting, prioritized multi-insight display, tone matching, and preciseDetail tooltips.
- 2026-02-12: Code review fixes — 8 findings (2 HIGH, 3 MEDIUM, 3 LOW), all fixed:
  - H1: Fixed usageDeviation priority never assigned (week deviation now uses .usageDeviation)
  - H2: Fixed pattern/recommendation duplication between cards and InsightStack (InsightStack now shows usage insights only, cards handle findings/recommendations)
  - M1: Fixed formatPercentNatural range boundaries to match spec (10-20%="about a tenth", not 10-25%)
  - M2: Deduplicated insight computation in AnalyticsView (computeUsageInsight() used once for both quiet check and display)
  - M3: Removed dead ContextAwareValueSummary.swift
  - L1: Fixed inconsistent VoiceOver label (secondary insight now combines NL text + detail like primary)
  - L2: Documented AGENTS.md in File List
  - L3: Added dismiss-promote and usageDeviation priority tests

### File List

**New files:**
- `cc-hdrm/Services/NaturalLanguageFormatter.swift` — Natural language formatting helpers
- `cc-hdrm/Views/InsightStack.swift` — Prioritized insight display (replaces ContextAwareValueSummary)
- `cc-hdrmTests/Services/NaturalLanguageFormatterTests.swift` — 16 formatter tests

**Modified files:**
- `cc-hdrm/Services/ValueInsightEngine.swift` — Added InsightPriority, preciseDetail, computeInsights(), NL integration, tone matching, capitalizeFirst helper, insight conversion methods; review fix: .usageDeviation priority for week deviation
- `cc-hdrm/Views/AnalyticsView.swift` — Replaced ContextAwareValueSummary with InsightStack; review fix: deduplicated computation via computeUsageInsight(), removed card duplication in InsightStack
- `cc-hdrm/Views/TierRecommendationCard.swift` — Updated doc comment (ContextAwareValueSummary → InsightStack)
- `cc-hdrm/Views/InsightStack.swift` — Review fix: consistent VoiceOver labels for primary and secondary insights
- `cc-hdrm/Services/NaturalLanguageFormatter.swift` — Review fix: corrected range boundaries to match spec
- `cc-hdrmTests/Services/ValueInsightEngineTests.swift` — Updated 6 existing tests for NL format, added 12 new tests (5 preciseDetail + 5 tone + usageDeviation priority + dismiss-promote)
- `cc-hdrmTests/Services/NaturalLanguageFormatterTests.swift` — Review fix: updated test values for corrected ranges, added boundary tests
- `AGENTS.md` — Added BMAD methodology and agent teams documentation sections
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — Story status: ready-for-dev → in-progress → review → done
- `_bmad-output/implementation-artifacts/16-5-context-aware-insight-engine.md` — Task checkboxes, dev agent record, file list, review notes

**Removed files:**
- `cc-hdrm/Views/ContextAwareValueSummary.swift` — Dead code removed (functionality absorbed by InsightStack)
