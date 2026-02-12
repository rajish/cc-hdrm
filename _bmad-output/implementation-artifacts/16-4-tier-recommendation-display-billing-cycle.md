# Story 16.4: Tier Recommendation Display & Billing Cycle Preference

Status: ready-for-dev

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer using Claude Code,
I want to see tier recommendations in the analytics view and configure my billing cycle day,
so that recommendations are grounded in my actual billing periods and visible when relevant.

## Acceptance Criteria

1. **Given** TierRecommendationService returns a .downgrade or .upgrade recommendation
   **When** the analytics view renders
   **Then** a recommendation card appears below the subscription value bar (after any pattern findings from 16.2):
   - Natural language summary (e.g., "Your usage fits Pro ($20/mo) -- you'd save $80/mo")
   - When extra usage data exists: card shows total cost breakdown (e.g., "Base: $20 + Extra: $47 = $67 total")
   - When recommending tier change with extra usage context: shows comparison (e.g., "Max 5x at $100/mo would have covered this with no extra charges")
   - Based-on context: "Based on 12 weeks of usage data"
   - Card is dismissable (dismissed state persisted, re-shown if recommendation changes)

2. **Given** TierRecommendationService returns a .goodFit recommendation
   **When** the analytics view renders
   **Then** no card is shown (conditional visibility -- quiet when nothing actionable)

3. **Given** the settings view is open
   **When** SettingsView renders
   **Then** a "Billing" section appears within the Advanced disclosure group with:
   - Billing cycle day: picker with values "Not set" + 1-28
   - Help text: "Billing cycle alignment for tier recommendations"
   - Default: nil (unset / "Not set")

4. **Given** billing cycle day is configured
   **When** the subscription value bar renders for 30d or All time ranges
   **Then** dollar summaries align to complete billing cycles
   **And** the current partial cycle is visually distinguished (e.g., lighter fill or "so far" qualifier)

5. **Given** billing cycle day is not configured
   **When** tier recommendation or subscription value renders
   **Then** calculations use calendar months as approximation
   **And** settings shows a subtle hint: "Set your billing day for more accurate insights"

## Tasks / Subtasks

- [ ] Task 1: Add `dismissedTierRecommendation` fingerprint to PreferencesManager (AC: 1)
  - [ ] 1.1 `dismissedTierRecommendation: String?` already exists on `cc-hdrm/Services/PreferencesManagerProtocol.swift:37` -- verify it's implemented in `PreferencesManager.swift` and `MockPreferencesManager.swift`
  - [ ] 1.2 If not yet implemented in `PreferencesManager.swift`, add UserDefaults key + getter/setter + resetToDefaults cleanup

- [ ] Task 2: Add fingerprint computation to TierRecommendation model (AC: 1)
  - [ ] 2.1 Add `var fingerprint: String` computed property to `cc-hdrm/Models/TierRecommendation.swift`
  - [ ] 2.2 Fingerprint encodes recommendation direction + tier names (e.g., "downgrade-max5x-pro", "upgrade-pro-max5x")
  - [ ] 2.3 Changes when recommendation direction or tier changes, NOT when dollar amounts shift

- [ ] Task 3: Create TierRecommendationCard SwiftUI component (AC: 1, 2)
  - [ ] 3.1 Create `cc-hdrm/Views/TierRecommendationCard.swift`
  - [ ] 3.2 Accept `recommendation: TierRecommendation` and `onDismiss: () -> Void`
  - [ ] 3.3 Implement `buildTitle(for:)` -- "Consider [tier]" for downgrade/upgrade, "[tier] is a good fit" for goodFit
  - [ ] 3.4 Implement `buildSummary(for:)` -- natural language summary with dollar amounts
  - [ ] 3.5 Implement `buildContext(for:)` -- "Based on N weeks of usage data" for downgrade, rate-limit count for upgrade
  - [ ] 3.6 Style matching PatternFindingCard: `.quaternary.opacity(0.5)` background, 6pt corner radius, dismiss button with xmark
  - [ ] 3.7 Add VoiceOver support with combined accessibility label
  - [ ] 3.8 Make `buildTitle`, `buildSummary`, `buildContext` static for testability

- [ ] Task 4: Integrate TierRecommendationCard into AnalyticsView (AC: 1, 2)
  - [ ] 4.1 Add `tierRecommendationService: (any TierRecommendationServiceProtocol)?` parameter to `cc-hdrm/Views/AnalyticsView.swift`
  - [ ] 4.2 Add `@State private var tierRecommendation: TierRecommendation?` state
  - [ ] 4.3 Add `.task` modifier to call `loadTierRecommendation()` on appear
  - [ ] 4.4 Build `tierRecommendationCard` ViewBuilder that:
    - Checks recommendation is `.downgrade` or `.upgrade` (skip `.goodFit` per AC 2)
    - Checks fingerprint is NOT equal to `dismissedTierRecommendation` (skip if dismissed)
    - Renders `TierRecommendationCard` with dismiss callback
  - [ ] 4.5 Implement `dismissTierRecommendation()` to write fingerprint to PreferencesManager
  - [ ] 4.6 Insert card after `patternFindingCards` and before `ContextAwareValueSummary`

- [ ] Task 5: Update AnalyticsWindow to pass TierRecommendationService (AC: 1)
  - [ ] 5.1 Add `tierRecommendationService` parameter to `cc-hdrm/Views/AnalyticsWindow.swift` configure/createPanel/reset methods
  - [ ] 5.2 Pass through to AnalyticsView initializer

- [ ] Task 6: Add billing cycle day picker to SettingsView (AC: 3, 5)
  - [ ] 6.1 Add `@State private var billingCycleDay: Int` to `cc-hdrm/Views/SettingsView.swift` (0 = "Not set", 1-28 = day)
  - [ ] 6.2 Initialize from `preferencesManager.billingCycleDay ?? 0` in init
  - [ ] 6.3 Add picker within the Advanced disclosure group, after custom credit limit fields
  - [ ] 6.4 Help text: "Billing cycle alignment for tier recommendations"
  - [ ] 6.5 Add `.onChange` handler to write `nil` for 0, else value to `preferencesManager.billingCycleDay`
  - [ ] 6.6 Reset billing cycle day to 0 in Reset to Defaults handler
  - [ ] 6.7 Add accessibility label: "Billing cycle day, [not set/day N]"

- [ ] Task 7: Wire up TierRecommendationService in AppDelegate (AC: 1)
  - [ ] 7.1 TierRecommendationService is already instantiated in `cc-hdrm/App/AppDelegate.swift` (Story 16.3 created the service)
  - [ ] 7.2 Pass existing `tierRecommendationService` to AnalyticsWindow.configure()
  - [ ] 7.3 Verify PollingEngine receives the service (already done if 16.3 wired it)

- [ ] Task 8: Write unit tests for TierRecommendationCard (AC: 1, 2)
  - [ ] 8.1 Create `cc-hdrmTests/Views/TierRecommendationCardTests.swift`
  - [ ] 8.2 Test `buildTitle` returns "Consider [tier]" for downgrade
  - [ ] 8.3 Test `buildTitle` returns "Consider [tier]" for upgrade
  - [ ] 8.4 Test `buildSummary` includes savings amount for downgrade
  - [ ] 8.5 Test `buildSummary` includes costComparison string for upgrade with extra usage
  - [ ] 8.6 Test `buildSummary` includes rate-limit count for upgrade without costComparison
  - [ ] 8.7 Test `buildContext` returns "Based on N weeks" for downgrade
  - [ ] 8.8 Test `buildContext` returns rate-limit count for upgrade
  - [ ] 8.9 Test `buildContext` returns nil for goodFit
  - [ ] 8.10 Test accessibility label combines all text components

- [ ] Task 9: Write unit tests for TierRecommendation fingerprint (AC: 1)
  - [ ] 9.1 Add tests in `cc-hdrmTests/Models/TierRecommendationTests.swift` (new file or append)
  - [ ] 9.2 Test downgrade fingerprint encodes direction + tiers
  - [ ] 9.3 Test upgrade fingerprint encodes direction + tiers
  - [ ] 9.4 Test fingerprint changes when tiers change but stays stable when dollar amounts change

- [ ] Task 10: Run `xcodegen generate` and verify compilation + tests pass

## Dev Notes

### Architecture Context

This story is the display layer for Story 16.3's `TierRecommendationService`. It follows the established pattern from Story 16.2 (PatternFindingCard + AnalyticsView integration). The architecture document (lines 992-1014, 1584-1591) maps FR48 ("Analytics displays total cost breakdown") to `AnalyticsView.swift`.

**Key design decisions:**
- `TierRecommendationCard` is a pure view component with static text builders (same testability pattern as PatternFindingCard)
- `.goodFit` recommendations are intentionally invisible -- the card only appears for actionable recommendations (AC 2)
- Dismissal uses a fingerprint-based system: dismissed state resets when the recommendation direction or tiers change
- Billing cycle day picker goes inside the existing Advanced disclosure group (not a separate section)

### Key Integration Points

**Files consumed (read-only):**
- `cc-hdrm/Models/TierRecommendation.swift` -- enum with `.downgrade`, `.upgrade`, `.goodFit` cases (Story 16.3)
- `cc-hdrm/Services/TierRecommendationServiceProtocol.swift` -- `recommendTier(for:)` API (Story 16.3)
- `cc-hdrm/Services/TierRecommendationService.swift` -- implementation (Story 16.3)
- `cc-hdrm/Views/PatternFindingCard.swift` -- visual style reference (Story 16.2)
- `cc-hdrm/Models/RateLimitTier.swift:displayName` -- human-readable tier names (Story 16.1)

**Files to create:**
- `cc-hdrm/Views/TierRecommendationCard.swift` -- NEW, recommendation card component
- `cc-hdrmTests/Views/TierRecommendationCardTests.swift` -- NEW, text builder tests

**Files to modify:**
- `cc-hdrm/Models/TierRecommendation.swift` -- add `fingerprint` computed property
- `cc-hdrm/Views/AnalyticsView.swift` -- add `tierRecommendationService` param, recommendation card in value section
- `cc-hdrm/Views/AnalyticsWindow.swift` -- add `tierRecommendationService` to configure/createPanel/reset
- `cc-hdrm/Views/SettingsView.swift` -- add billing cycle day picker in Advanced section
- `cc-hdrm/App/AppDelegate.swift` -- pass tierRecommendationService to AnalyticsWindow

**Existing mocks available:**
- `cc-hdrmTests/Mocks/MockTierRecommendationService.swift` -- already created in Story 16.3
- `cc-hdrmTests/Mocks/MockPreferencesManager.swift` -- has `billingCycleDay`, `dismissedTierRecommendation`

### TierRecommendationCard Design

The card mirrors `PatternFindingCard`'s visual design for consistency:

```
┌────────────────────────────────────────────────┐
│ Consider Pro                              [×]  │
│ Pro would cover your usage and save ~$80/mo    │
│ Based on 12 weeks of usage data                │
└────────────────────────────────────────────────┘
```

- **Title** (`.caption` bold): "Consider [tier]" or "[tier] is a good fit"
- **Summary** (`.caption2` secondary): Natural language with dollar amounts
- **Context** (`.caption2` tertiary, optional): Data confidence or rate-limit count
- **Dismiss** button: xmark icon, writes fingerprint to PreferencesManager

### Fingerprint-Based Dismissal

Unlike `PatternFindingCard` which uses cooldown keys, the recommendation card uses a fingerprint:

```swift
extension TierRecommendation {
    var fingerprint: String {
        switch self {
        case .downgrade(let currentTier, _, let recommendedTier, _, _, _):
            return "downgrade-\(currentTier.rawValue)-\(recommendedTier.rawValue)"
        case .upgrade(let currentTier, _, let recommendedTier, _, _, _):
            return "upgrade-\(currentTier.rawValue)-\(recommendedTier.rawValue)"
        case .goodFit(let tier, _):
            return "goodfit-\(tier.rawValue)"
        }
    }
}
```

When the user dismisses, the fingerprint is saved to `PreferencesManager.dismissedTierRecommendation`. The card reappears only when the fingerprint changes (different direction or different tiers).

### AnalyticsView Integration

The card is inserted in the value section between `patternFindingCards` and `ContextAwareValueSummary`:

```swift
// Pattern finding cards (Story 16.2)
patternFindingCards
// Tier recommendation card (Story 16.4) -- after patterns, before summary
tierRecommendationCard
// Summary
ContextAwareValueSummary(...)
```

Loading follows the same `.task` pattern:
```swift
.task {
    await loadTierRecommendation()
}
```

### Billing Cycle Day Picker (SettingsView)

The picker goes inside the Advanced disclosure group after custom credit limits:

```swift
// Inside DisclosureGroup("Advanced")
// ... existing custom credit limit fields ...

Divider()
    .padding(.vertical, 4)

Text("Billing cycle alignment for tier recommendations")
    .font(.caption)
    .foregroundStyle(.secondary)

HStack {
    Text("Billing cycle day")
    Spacer()
    Picker("Billing cycle day", selection: $billingCycleDay) {
        Text("Not set").tag(0)
        ForEach(1...28, id: \.self) { day in
            Text("\(day)").tag(day)
        }
    }
    .labelsHidden()
    .frame(width: 80)
}
```

**Important:** The `billingCycleDay` property already exists on `PreferencesManagerProtocol` (added in Story 16.3). This task only adds the UI.

### Potential Pitfalls

1. **`.goodFit` should NOT show a card:** Per AC 2, the card is conditional -- only `.downgrade` and `.upgrade` are visible. Don't render anything for `.goodFit`.

2. **Fingerprint must be direction+tiers, not dollar-based:** If the fingerprint included dollar amounts, minor cost fluctuations would reset the dismissed state. Use raw tier values and direction only.

3. **`dismissedTierRecommendation` already on protocol:** The property `dismissedTierRecommendation: String?` is already declared on `PreferencesManagerProtocol` (line 37) and `MockPreferencesManager`. Verify the concrete `PreferencesManager` implements it with UserDefaults persistence. If not, add it.

4. **AnalyticsView already has `preferencesManager` param:** Added in Story 16.2. Reuse the existing optional parameter -- don't add a second one.

5. **Billing cycle day 0 maps to nil:** The picker uses `0` as the tag for "Not set". The `.onChange` handler must convert 0 to `nil` before writing to PreferencesManager.

6. **TimeRange for recommendation:** Use `selectedTimeRange` when calling `recommendTier(for:)`. The recommendation adapts to the selected analysis period.

7. **Reset to Defaults must clear billing cycle day:** Add `billingCycleDay = 0` to the Reset to Defaults handler in SettingsView.

8. **Card placement order matters:** Pattern findings (16.2) come first, then tier recommendation (16.4), then summary. This matches the epic's specified card ordering.

### Previous Story Intelligence

Key learnings from Stories 16.2 and 16.3:
- **PatternFindingCard visual pattern:** Use `.quaternary.opacity(0.5)` background, 6pt corner radius, `.caption`/`.caption2` fonts. Match exactly for visual consistency.
- **AnalyticsView optional dependencies:** Both `patternDetector` and `preferencesManager` are optional params. Follow the same pattern for `tierRecommendationService`.
- **AnalyticsWindow dependency passthrough:** configure() → createPanel() → reset() chain passes dependencies through. Add `tierRecommendationService` to all three.
- **Static text builders for testability:** PatternNotificationService and TierRecommendationCard both use static methods to generate text, enabling unit testing without instantiating views.
- **buildCostComparison fix (PR 53):** The `costComparison` string in `.upgrade` may be nil (no extra usage) or present. Handle both cases in `buildSummary`.
- **MockTierRecommendationService already exists:** Created in Story 16.3 at `cc-hdrmTests/Mocks/MockTierRecommendationService.swift`.

### Git Intelligence

Recent commits:
- `def04b8` (Story 16.2): Pattern notification and analytics display -- added patternDetector/preferencesManager to AnalyticsView
- `b3d9d79` (PR 53): Fixed negative savings in tier cost comparison -- buildCostComparison now branches on savings > 0
- `5bfec97` (Story 16.1): Added displayName to RateLimitTier
- `a4d1bf4` (Story 16.3): Created TierRecommendationService, TierRecommendation model, billingCycleDay preference

### Project Structure Notes

New files to create:
```
cc-hdrm/Views/TierRecommendationCard.swift               # NEW - Recommendation card component
cc-hdrmTests/Views/TierRecommendationCardTests.swift      # NEW - Text builder tests
```

Files to modify:
```
cc-hdrm/Models/TierRecommendation.swift                   # ADD fingerprint property
cc-hdrm/Views/AnalyticsView.swift                         # ADD tierRecommendationService, card
cc-hdrm/Views/AnalyticsWindow.swift                       # ADD tierRecommendationService passthrough
cc-hdrm/Views/SettingsView.swift                          # ADD billing cycle day picker
cc-hdrm/App/AppDelegate.swift                             # WIRE tierRecommendationService to AnalyticsWindow
```

After adding files, run `xcodegen generate` to regenerate the Xcode project.

### References

- [Source: _bmad-output/planning-artifacts/epics/epic-16-subscription-intelligence-phase-4.md:198-237] - Story 16.4 acceptance criteria
- [Source: _bmad-output/planning-artifacts/architecture.md:992-1014] - TierRecommendationService architecture
- [Source: _bmad-output/planning-artifacts/architecture.md:1037-1070] - RateLimitTier with monthlyPrice
- [Source: _bmad-output/planning-artifacts/architecture.md:1253-1279] - AnalyticsView layout
- [Source: _bmad-output/planning-artifacts/architecture.md:1554-1562] - PreferencesManager billingCycleDay
- [Source: _bmad-output/planning-artifacts/architecture.md:1584-1591] - FR48 maps tier recommendation display to AnalyticsView
- [Source: cc-hdrm/Models/TierRecommendation.swift:1-32] - TierRecommendation enum with downgrade/upgrade/goodFit
- [Source: cc-hdrm/Services/TierRecommendationServiceProtocol.swift] - recommendTier(for:) protocol
- [Source: cc-hdrm/Services/TierRecommendationService.swift:1-346] - Full implementation
- [Source: cc-hdrm/Views/AnalyticsView.swift:11-17] - Existing AnalyticsView params (patternDetector, preferencesManager already added by 16.2)
- [Source: cc-hdrm/Views/AnalyticsView.swift:128-139] - Value section insertion point for card
- [Source: cc-hdrm/Views/PatternFindingCard.swift:1-36] - Visual style reference
- [Source: cc-hdrm/Views/SettingsView.swift:211-286] - Advanced disclosure group where billing cycle picker goes
- [Source: cc-hdrm/Services/PreferencesManagerProtocol.swift:33-37] - billingCycleDay + dismissedTierRecommendation already on protocol
- [Source: cc-hdrmTests/Mocks/MockTierRecommendationService.swift] - Mock already available
- [Source: cc-hdrmTests/Mocks/MockPreferencesManager.swift] - Has billingCycleDay + dismissedTierRecommendation
- [Source: _bmad-output/implementation-artifacts/16-2-pattern-notification-analytics-display.md] - Story 16.2 implementation (predecessor)
- [Source: _bmad-output/implementation-artifacts/16-3-tier-recommendation-service.md] - Story 16.3 implementation (prerequisite)

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
