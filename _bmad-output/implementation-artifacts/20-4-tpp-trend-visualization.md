# Story 20.4: TPP Trend Visualization

Status: dev-complete

## Story

As a developer using Claude Code,
I want to see how my token efficiency has changed over time, with plain-English conclusions and clear separation between calibrated and directional data,
So that I can identify if Anthropic has changed the rate limit weighting.

## Acceptance Criteria

**AC-1: TPP section in analytics**

**Given** the analytics window is open and TPP data exists
**When** the TPP section renders
**Then** a "Token Efficiency" section appears below the existing BenchmarkSectionView:
- Title: "Token Efficiency Trend"
- A plain-English insight banner at the top (see AC-7)
- Per-model chart(s) below

**Given** no TPP data exists AND the benchmark feature is disabled
**When** the analytics window renders
**Then** the TPP trend section does not appear (no empty shell)

**AC-2: Per-model chart rendering**

**Given** TPP data exists for one or more models
**When** the chart renders
**Then** each model with data gets its own chart area (or selectable model picker if many models):
- X-axis: time (matching the selected time range from AnalyticsView)
- Y-axis: TPP value (raw tokens per 1% utilization change)
- Model name as chart subtitle

**AC-3: Two-tier data visualization**

**Given** both passive and benchmark TPP data exist for a model
**When** the chart renders
**Then** the two data tiers are visually distinct:
- **Benchmark points:** Diamond-shaped markers, solid accent color, prominent. These are ground truth.
- **Passive band:** Lighter connected dots or shaded area showing continuous directional signal. Reduced visual weight compared to benchmarks.
- **Low-confidence data** (rollup-backfill, multi-model shared delta): Reduced opacity or dashed rendering

**And** a legend explains: "Benchmark = calibrated measurement, Passive = directional estimate"

**AC-4: Trend line and shift detection**

**Given** sufficient TPP data points exist for a model (>=10 passive or >=3 benchmark)
**When** the chart renders
**Then** a smoothed trend line (7-point moving average) overlays the data
**And** if the trend changes significantly (sustained drop or rise of >20% from the 7-day moving average), a visual annotation marks the shift point
**And** a text label near the annotation: "TPP dropped ~X%" or "TPP rose ~X%" with the approximate date

**AC-5: Time range support**

**Given** the user selects a time range (24h, 7d, 30d, All) via the existing TimeRangeSelector
**When** the TPP chart updates
**Then** it shows TPP data for the selected range
**And** for 24h: individual data points (passive + benchmark)
**And** for 7d: data points with daily averages for passive, individual benchmark points
**And** for 30d/All: daily or weekly average bars for passive, individual benchmark points

**AC-6: Token type weighting discovery display**

**Given** benchmark variants (input-heavy, output-heavy, cache-heavy) have been run for a model
**When** the TPP section renders
**Then** a "Rate Limit Weighting" card appears showing the discovered ratios:
- "For [model]: output tokens cost ~Xx input in rate limit budget. Cache reads cost ~Yx input."
- Based on the TPP ratio between variants
- Last measured date

**AC-7: Plain-English insight banner**

**Given** TPP data exists
**When** the insight banner renders
**Then** it shows the most relevant conclusion in plain English:
- If recent benchmark TPP is >20% lower than 30-day average: "Your token efficiency dropped ~X% recently -- the same work now costs more headroom."
- If recent benchmark TPP is stable (+-10%): "Token efficiency is stable -- no detectable rate limit changes."
- If no benchmark exists but passive data exists: "Passive monitoring suggests [direction]. Run a benchmark to confirm."
- If no TPP data at all: "Run a benchmark to get a calibrated reading of your token efficiency."

**AC-8: Empty state**

**Given** no TPP data exists (feature just enabled, no usage yet)
**When** the TPP section renders
**Then** it shows: "Enable the Measure button in Settings to start tracking token efficiency. Passive data will also appear after your next Claude Code session."

**AC-9: Series toggles**

**Given** the TPP chart is visible
**When** the user interacts with series toggles
**Then** toggles allow showing/hiding: passive data, benchmark points, trend line
**And** a model picker allows switching between models (or "All" overlay)
**And** defaults: all visible for the most-used model (model with most data points)

## Tasks / Subtasks

- [x] Task 1: Create `TPPChartDataService` for data preparation (AC: 1, 2, 4, 5, 7)
  - [x] 1.1 Create `cc-hdrm/Services/TPPChartDataServiceProtocol.swift` with protocol: `loadTPPData(timeRange:model:) async throws -> TPPChartData`
  - [x] 1.2 Create `cc-hdrm/Services/TPPChartDataService.swift` implementing the protocol, injecting `TPPStorageServiceProtocol`
  - [x] 1.3 Implement time range mapping: convert `TimeRange` to `(from: Int64, to: Int64)` using `TimeRange.startTimestamp` and current time
  - [x] 1.4 Fetch measurements via `tppStorageService.getMeasurements(from:to:source:model:confidence:)` -- fetch all sources, separate in memory
  - [x] 1.5 Compute daily/weekly averages for passive data in longer time ranges (7d: daily avg, 30d/All: weekly avg)
  - [x] 1.6 Compute 7-point moving average trend line from passive TPP data
  - [x] 1.7 Implement shift detection: find points where trend deviates >20% from 7-day moving average; return shift annotations with direction, percentage, and date
  - [x] 1.8 Compute insight text using logic from AC-7: compare recent benchmark TPP vs 30-day average, determine message
  - [x] 1.9 Determine available models from data: query all measurements, extract distinct model values, sort by count descending (most-used first)

- [x] Task 2: Create `TPPChartData` model (AC: all)
  - [x] 2.1 Create `cc-hdrm/Models/TPPChartData.swift` with struct containing:
    - `passivePoints: [TPPChartPoint]` -- passive measurements (individual or averaged depending on time range)
    - `benchmarkPoints: [TPPChartPoint]` -- benchmark measurements (always individual)
    - `trendLine: [TPPChartPoint]` -- smoothed moving average line
    - `shiftAnnotations: [TPPShiftAnnotation]` -- detected trend shifts
    - `insightText: String` -- plain-English insight for the banner
    - `availableModels: [String]` -- distinct models with data, sorted by frequency
    - `weightingDiscovery: TPPWeightingDiscovery?` -- variant-based weighting ratios (AC-6)
    - `isEmpty: Bool` -- convenience: no passive AND no benchmark data
  - [x] 2.2 Create `TPPChartPoint` struct: `timestamp: Date`, `tppValue: Double`, `source: MeasurementSource`, `confidence: MeasurementConfidence`, `isAverage: Bool` (for aggregated points)
  - [x] 2.3 Create `TPPShiftAnnotation` struct: `date: Date`, `direction: ShiftDirection` (.up/.down), `percentChange: Double`, `label: String`
  - [x] 2.4 Create `TPPWeightingDiscovery` struct: `model: String`, `outputToInputRatio: Double?`, `cacheToInputRatio: Double?`, `lastMeasuredDate: Date`

- [x] Task 3: Create `TPPTrendChartView` SwiftUI chart (AC: 2, 3, 4, 5)
  - [x] 3.1 Create `cc-hdrm/Views/TPPTrendChartView.swift` using Swift Charts framework (`import Charts`)
  - [x] 3.2 Render passive points as `PointMark` with `.circle` symbol, reduced opacity (0.5), connected with `LineMark` at opacity 0.3
  - [x] 3.3 Render benchmark points as `PointMark` with `.diamond` symbol, full opacity, accent color
  - [x] 3.4 Render trend line as `LineMark` with `.interpolationMethod(.catmullRom)` for smooth curve
  - [x] 3.5 Render low-confidence points (confidence == .low) at reduced opacity (0.25)
  - [x] 3.6 X-axis: `.value("Time", point.timestamp)` with automatic date formatting
  - [x] 3.7 Y-axis: `.value("TPP", point.tppValue)` with "tokens/%" label
  - [x] 3.8 Add shift annotations as `RuleMark` vertical lines at shift dates with text annotation
  - [x] 3.9 Add chart legend: "Benchmark" diamond + "Passive" circle + "Trend" line
  - [x] 3.10 Wrap chart in bordered rounded rectangle (matching UsageChart container style)
  - [x] 3.11 Show ProgressView when loading, "No data" message when empty

- [x] Task 4: Create `TPPSectionView` container (AC: 1, 6, 7, 8, 9)
  - [x] 4.1 Create `cc-hdrm/Views/TPPSectionView.swift` with the full section layout
  - [x] 4.2 Section header: "Token Efficiency Trend" (.headline font, matching BenchmarkSectionView)
  - [x] 4.3 Insight banner: display `chartData.insightText` in `.caption` font, `.secondary` style
  - [x] 4.4 Model picker: `Picker` bound to `@State var selectedModel: String?` with available models from `chartData.availableModels`; default to first (most-used)
  - [x] 4.5 Series toggles: three toggle buttons for Passive/Benchmark/Trend visibility using the existing `seriesToggleButton` pattern from AnalyticsView
  - [x] 4.6 TPPTrendChartView embedded with the selected model's data, filtered by visible series
  - [x] 4.7 Weighting discovery card below chart (AC-6): show ratios if benchmark variants exist for selected model
  - [x] 4.8 Empty state: show AC-8 message when `chartData.isEmpty` and benchmark not enabled
  - [x] 4.9 Accept `tppStorageService`, `preferencesManager`, `selectedTimeRange` as parameters (injected from AnalyticsView)

- [x] Task 5: Integrate into AnalyticsView (AC: 1, 5)
  - [x] 5.1 Add `TPPSectionView` to `cc-hdrm/Views/AnalyticsView.swift` body, after the existing `BenchmarkSectionView` block
  - [x] 5.2 Pass `tppStorageService`, `preferencesManager`, and `selectedTimeRange` binding
  - [x] 5.3 Only render when `tppStorageService != nil` (same guard pattern as BenchmarkSectionView)
  - [x] 5.4 Add `Divider()` before the section (matching the BenchmarkSectionView pattern at line 103)
  - [x] 5.5 TPPSectionView reloads data when `selectedTimeRange` changes (use `.task(id: selectedTimeRange)`)

- [x] Task 6: Write tests (AC: all)
  - [x] 6.1 Create `cc-hdrmTests/Services/TPPChartDataServiceTests.swift`
  - [x] 6.2 Test insight text generation: benchmark drop >20% -> "dropped" message; stable -> "stable" message; no benchmark -> passive suggestion; no data -> empty message
  - [x] 6.3 Test daily average computation: 5 passive points in one day -> single averaged point
  - [x] 6.4 Test moving average: verify 7-point window produces correct smoothed values
  - [x] 6.5 Test shift detection: inject a 30% TPP drop -> verify annotation generated with correct direction and percentage
  - [x] 6.6 Test model discovery: mixed-model data -> models sorted by frequency descending
  - [x] 6.7 Test weighting discovery: output-heavy TPP 5x lower than input-heavy -> ratio ~5.0
  - [x] 6.8 Test time range filtering: verify correct from/to timestamps for each TimeRange case
  - [x] 6.9 Create `cc-hdrmTests/Models/TPPChartDataTests.swift` for model struct tests
  - [x] 6.10 Test `TPPChartData.isEmpty` logic: no passive + no benchmark = true; any data = false

- [x] Task 7: Run `xcodegen generate` and verify build
  - [x] 7.1 Run `xcodegen generate` after all files are added
  - [x] 7.2 Verify build compiles cleanly
  - [x] 7.3 Verify all tests pass

## Dev Notes

### Architecture Compliance

- **Pattern:** MVVM with Service Layer. `TPPChartDataService` is a pure data-transformation service -- fetches raw `TPPMeasurement` records from `TPPStorageService` and transforms them into chart-ready data. No direct DB access.
- **Concurrency:** Swift structured concurrency only. `TPPChartDataService` methods are `async throws`. No GCD, no Combine.
- **State flow:** `TPPStorageService` -> `TPPChartDataService` -> `TPPSectionView` (via `@State`). AppState is NOT modified by this story.
- **Protocol-first:** `TPPChartDataServiceProtocol.swift` + `TPPChartDataService.swift` as separate files.
- **Logging:** Use `os.Logger` with subsystem `"com.cc-hdrm.app"` and category `"tpp-chart"`.
- **Sendable:** `TPPChartData`, `TPPChartPoint`, `TPPShiftAnnotation`, `TPPWeightingDiscovery` are all value types (structs) -- inherently Sendable.

### Swift Charts Framework

This story uses Apple's built-in `Charts` framework (`import Charts`), which is already available on macOS 14+ (the app's deployment target). The existing codebase uses `Charts` in `StepAreaChartView.swift` and `BarChartView.swift`.

Key chart marks to use:
- `PointMark` for individual data points (passive circles, benchmark diamonds)
- `LineMark` for trend line and passive connections
- `RuleMark` for shift annotation vertical lines
- `.symbol()` modifier for marker shapes: `.circle` for passive, `.diamond` for benchmark
- `.foregroundStyle(by:)` for legend color coding
- `.interpolationMethod(.catmullRom)` for smooth trend line

### Data Flow for TPP Visualization

```
TPPStorageService.getMeasurements(from:to:...)
  -> [TPPMeasurement]
  -> TPPChartDataService transforms:
     1. Separate by source (passive vs benchmark)
     2. For passive: compute averages per time bucket (day/week depending on range)
     3. Compute 7-point moving average trend line
     4. Detect shifts (>20% deviation from 7-day MA)
     5. Compute insight text
     6. Extract distinct models
     7. Compute weighting discovery from benchmark variants
  -> TPPChartData
  -> TPPSectionView renders
```

### Time Range to Data Resolution Mapping

| Time Range | Passive Resolution | Benchmark Resolution | Trend Line |
|-----------|-------------------|---------------------|------------|
| 24h (`.day`) | Individual points | Individual points | 7-point MA if >=10 points |
| 7d (`.week`) | Daily averages | Individual points | 7-point MA on daily averages |
| 30d (`.month`) | Daily averages | Individual points | 7-point MA on daily averages |
| All (`.all`) | Weekly averages | Individual points | 7-point MA on weekly averages |

### Moving Average Computation

Use a simple 7-point sliding window:
```swift
func computeMovingAverage(points: [TPPChartPoint], windowSize: Int = 7) -> [TPPChartPoint] {
    guard points.count >= windowSize else { return [] }
    var result: [TPPChartPoint] = []
    for i in (windowSize - 1)..<points.count {
        let window = points[(i - windowSize + 1)...i]
        let avg = window.map(\.tppValue).reduce(0, +) / Double(windowSize)
        result.append(TPPChartPoint(timestamp: points[i].timestamp, tppValue: avg, source: .passive, confidence: .medium, isAverage: true))
    }
    return result
}
```

### Shift Detection Algorithm

1. Compute 7-day moving average of passive TPP values
2. For each point, compare to the MA value at the same index
3. If the ratio `(point / MA)` deviates by >20% for 3+ consecutive points:
   - Mark the first deviation point as a shift
   - Direction: `.down` if point < MA * 0.8, `.up` if point > MA * 1.2
   - Percentage: `((point / MA) - 1.0) * 100`
4. Only report the first shift per sustained run (avoid annotation spam)

### Insight Text Logic

Priority order (first match wins):
1. Recent benchmark vs 30-day avg: `getAverageTPP(from: 30daysAgo, to: now, source: .benchmark)` vs `latestBenchmark(model:variant:)`
   - Drop >20%: "Your token efficiency dropped ~X% recently -- the same work now costs more headroom."
   - Stable +-10%: "Token efficiency is stable -- no detectable rate limit changes."
   - Rise >20%: "Your token efficiency improved ~X% -- you're getting more tokens per % of headroom."
2. Passive only: analyze trend direction from last 7 days of passive data
   - "Passive monitoring suggests efficiency is [declining/stable/improving]. Run a benchmark to confirm."
3. No data: "Run a benchmark to get a calibrated reading of your token efficiency."

### Weighting Discovery Logic

Reuse the same comparison logic already in `BenchmarkSectionView.weightingDiscoveryView` (line 175-208). To avoid duplication, the `TPPChartDataService` computes the ratios from stored benchmark measurements:

```swift
// Query latest benchmark for each variant of the selected model
let outputHeavy = try await tppStorage.latestBenchmark(model: model, variant: "output-heavy")
let inputHeavy = try await tppStorage.latestBenchmark(model: model, variant: "input-heavy")
let cacheHeavy = try await tppStorage.latestBenchmark(model: model, variant: "cache-heavy")

// Compute ratios from TPP values (lower TPP = more expensive token type)
let outputToInputRatio: Double? = if let outTPP = outputHeavy?.tppFiveHour, let inTPP = inputHeavy?.tppFiveHour, inTPP > 0 { inTPP / outTPP } else { nil }
```

**IMPORTANT:** The weighting ratio is `inputTPP / outputTPP` (not the inverse). If output-heavy has TPP=1000 and input-heavy has TPP=5000, output tokens cost 5x more (lower TPP means fewer total tokens per 1% = more expensive per token type).

### AnalyticsView Integration Point

The `TPPSectionView` goes in `cc-hdrm/Views/AnalyticsView.swift` body, after the existing BenchmarkSectionView block (line 103-110):

```swift
// Existing BenchmarkSectionView block (lines 100-110)
if let benchmarkService, let tppStorageService, let preferencesManager,
   preferencesManager.isBenchmarkEnabled {
    Divider()
    BenchmarkSectionView(...)
}

// NEW: TPP Trend Visualization (Story 20.4)
if let tppStorageService {
    Divider()
    TPPSectionView(
        tppStorageService: tppStorageService,
        preferencesManager: preferencesManager,
        selectedTimeRange: selectedTimeRange
    )
}
```

**Note:** TPPSectionView is shown whenever `tppStorageService` is available, regardless of `isBenchmarkEnabled`. Passive data can exist even without the benchmark feature enabled. The section handles its own empty state (AC-8).

### Existing Services to Reuse (DO NOT REINVENT)

| Need | Existing Service | Location |
|------|-----------------|----------|
| TPP measurements query | `TPPStorageServiceProtocol.getMeasurements(from:to:source:model:confidence:)` | `cc-hdrm/Services/TPPStorageServiceProtocol.swift:33` |
| TPP averages | `TPPStorageServiceProtocol.getAverageTPP(from:to:model:source:)` | `cc-hdrm/Services/TPPStorageServiceProtocol.swift:42` |
| Latest benchmark | `TPPStorageServiceProtocol.latestBenchmark(model:variant:)` | `cc-hdrm/Services/TPPStorageServiceProtocol.swift:14` |
| TPP measurement model | `TPPMeasurement` struct | `cc-hdrm/Models/TPPMeasurement.swift` |
| Measurement enums | `MeasurementSource`, `MeasurementConfidence` | `cc-hdrm/Models/TPPMeasurement.swift:19-31` |
| Time range model | `TimeRange` enum with `startTimestamp` | `cc-hdrm/Models/TimeRange.swift` |
| Chart framework patterns | `StepAreaChartView` (PointMark, LineMark usage) | `cc-hdrm/Views/StepAreaChartView.swift` |
| Chart container style | `UsageChart` (bordered RoundedRectangle, empty states) | `cc-hdrm/Views/UsageChart.swift` |
| Series toggle pattern | `AnalyticsView.seriesToggleButton()` | `cc-hdrm/Views/AnalyticsView.swift:487-510` |
| Section header style | `BenchmarkSectionView` header pattern | `cc-hdrm/Views/BenchmarkSectionView.swift:36-59` |
| Weighting discovery display | `BenchmarkSectionView.weightingDiscoveryView` | `cc-hdrm/Views/BenchmarkSectionView.swift:175-208` |
| Benchmark enabled check | `PreferencesManagerProtocol.isBenchmarkEnabled` | `cc-hdrm/Services/PreferencesManager.swift` |
| Service wiring | `AnalyticsWindow.configure()` | `cc-hdrm/Views/AnalyticsWindow.swift:33-51` |
| AnalyticsView integration | `AnalyticsView.body` | `cc-hdrm/Views/AnalyticsView.swift:83-134` |

### File Structure

| Purpose | Path | Status |
|---------|------|--------|
| Chart data service protocol | `cc-hdrm/Services/TPPChartDataServiceProtocol.swift` | New |
| Chart data service impl | `cc-hdrm/Services/TPPChartDataService.swift` | New |
| Chart data model | `cc-hdrm/Models/TPPChartData.swift` | New |
| TPP trend chart view | `cc-hdrm/Views/TPPTrendChartView.swift` | New |
| TPP section container | `cc-hdrm/Views/TPPSectionView.swift` | New |
| Chart data service tests | `cc-hdrmTests/Services/TPPChartDataServiceTests.swift` | New |
| Chart data model tests | `cc-hdrmTests/Models/TPPChartDataTests.swift` | New |
| Modified: AnalyticsView | `cc-hdrm/Views/AnalyticsView.swift` | Modified -- add TPPSectionView |

### Testing Standards

- Framework: Swift Testing (`import Testing`, `@Test`, `#expect`)
- Mocks: Create `MockTPPStorageService` in test file (or reuse existing mock from `cc-hdrmTests/Services/BenchmarkServiceTests.swift` -- check if it already conforms to the full `TPPStorageServiceProtocol`)
- `TPPChartDataService` tests: inject mock storage, verify correct data transformation, averaging, trend computation, insight text
- Model tests: verify `isEmpty`, `TPPChartPoint` creation, `TPPShiftAnnotation` properties
- All `@MainActor` tests use `@MainActor` attribute
- Use in-memory test data (no DB needed -- mock the storage protocol)

### Project Structure Notes

- All new files go in existing directories: `cc-hdrm/Services/`, `cc-hdrm/Models/`, `cc-hdrm/Views/`, `cc-hdrmTests/Services/`, `cc-hdrmTests/Models/`
- One type per file, file name matches type name
- Run `xcodegen generate` after adding files

### Previous Story Learnings

From Story 20.1 code review:
- [Fixed] Off-by-one in retry loop: use `< maxRetries` not `<= maxRetries`
- [Fixed] ForEach non-unique IDs when multiple variants per model -- use compound ID (e.g., `"\(model)-\(variant)"`)
- [Deferred] `SQLITE_TRANSIENT` duplicate constant per file -- accepted project pattern, follow it

From Story 20.3 code review:
- [Fixed] storePassiveResult was verbatim copy of storeBenchmarkResult -- extracted shared INSERT helper. Follow this pattern: reuse, don't copy.
- [Fixed] Logger calls inside lock.withLock blocks -- move log calls outside locks
- [Deferred] Int32 truncation for token counts in sqlite3_bind_int -- pre-existing pattern, follow it

From Story 20.2:
- Log parser stores data in-memory only (no DB) -- scan must be triggered before querying
- `getTokens()` returns `[TokenAggregate]` with per-model separation

### Cross-Story Context

- **Story 20.1** (done): Created `tpp_measurements` table, `TPPMeasurement` model, `TPPStorageService`, `BenchmarkService`, `BenchmarkSectionView`. The benchmark section already shows results as cards -- this story adds the chart visualization BELOW the benchmark section.
- **Story 20.2** (done): Created `ClaudeCodeLogParser` service. Not directly used by this story (parser feeds the passive engine, not the visualization).
- **Story 20.3** (done): Created `PassiveTPPEngine`, extended `TPPStorageService` with `getMeasurements()` and `getAverageTPP()` query methods. These are the primary data sources for this story.
- **Story 20.5** (future): Backfill will add `source = "passive-backfill"` and `source = "rollup-backfill"` data. The visualization must handle these sources -- render them with reduced visual weight (low confidence).

### Anti-Patterns to Avoid

- **Do NOT query the database directly from the view.** Use `TPPChartDataService` as the intermediary.
- **Do NOT compute moving averages or aggregations in SwiftUI views.** All data transformation happens in the service layer.
- **Do NOT create a new AnalyticsWindow dependency.** `TPPSectionView` receives `tppStorageService` from `AnalyticsView`, which already has it.
- **Do NOT mix passive and benchmark data into a single series.** They are conceptually distinct and must be visually distinct (AC-3).
- **Do NOT hardcode model names.** Discover models dynamically from the data.
- **Do NOT modify the existing `BenchmarkSectionView`.** The weighting discovery card in AC-6 is in `TPPSectionView`, not a modification to the benchmark section.

### References

- [Source: `_bmad-output/planning-artifacts/epics/epic-20-token-efficiency-ratio-phase-6.md` -- Story 20.4 ACs]
- [Source: `_bmad-output/planning-artifacts/architecture.md` -- MVVM pattern, service layer, naming]
- [Source: `_bmad-output/planning-artifacts/project-context.md` -- Tech stack, zero external deps, Charts framework]
- [Source: `cc-hdrm/Services/TPPStorageServiceProtocol.swift` -- getMeasurements, getAverageTPP, latestBenchmark API]
- [Source: `cc-hdrm/Models/TPPMeasurement.swift` -- TPPMeasurement struct, MeasurementSource, MeasurementConfidence enums]
- [Source: `cc-hdrm/Models/TimeRange.swift` -- TimeRange enum with startTimestamp]
- [Source: `cc-hdrm/Views/AnalyticsView.swift:83-134` -- Body layout, BenchmarkSectionView integration point]
- [Source: `cc-hdrm/Views/AnalyticsWindow.swift:33-51` -- configure() with tppStorageService parameter]
- [Source: `cc-hdrm/Views/BenchmarkSectionView.swift:36-59` -- Section header and layout pattern]
- [Source: `cc-hdrm/Views/BenchmarkSectionView.swift:175-208` -- Weighting discovery view pattern]
- [Source: `cc-hdrm/Views/StepAreaChartView.swift` -- Swift Charts usage patterns (PointMark, LineMark)]
- [Source: `cc-hdrm/Views/UsageChart.swift` -- Chart container, empty state, loading patterns]
- [Source: `cc-hdrm/Views/AnalyticsView.swift:487-510` -- Series toggle button pattern]
- [Source: `_bmad-output/implementation-artifacts/20-3-tpp-data-model-passive-measurement-engine.md` -- Previous story learnings]
- [Source: `_bmad-output/implementation-artifacts/20-1-active-benchmark-measurement.md` -- Benchmark patterns, review findings]

## Dev Agent Record

### Agent Model Used

claude-opus-4-6 (1M context)

### Debug Log References

- Compilation verified via `swiftc -typecheck` -- no errors, only pre-existing warnings

### Completion Notes List

- All 7 tasks completed with all subtasks
- TPPChartDataService handles data transformation: averaging, trend line, shift detection, insight text, weighting discovery
- TPPTrendChartView uses Swift Charts with two-tier visualization (diamond benchmarks, circle passive, smooth trend)
- TPPSectionView integrated into AnalyticsView below BenchmarkSectionView with model picker and series toggles
- 14 tests covering: insight text generation, daily averages, moving average, shift detection, model discovery, weighting discovery, time range filtering, isEmpty logic, model properties

### File List

| File | Status | Description |
|------|--------|-------------|
| `cc-hdrm/Models/TPPChartData.swift` | New | TPPChartData, TPPChartPoint, TPPShiftAnnotation, TPPWeightingDiscovery, ShiftDirection |
| `cc-hdrm/Services/TPPChartDataServiceProtocol.swift` | New | Protocol for chart data preparation service |
| `cc-hdrm/Services/TPPChartDataService.swift` | New | Implementation: averaging, trend line, shift detection, insight text, weighting |
| `cc-hdrm/Views/TPPTrendChartView.swift` | New | Swift Charts view with two-tier data, trend line, shift annotations |
| `cc-hdrm/Views/TPPSectionView.swift` | New | Container: insight banner, model picker, series toggles, chart, weighting card |
| `cc-hdrm/Views/AnalyticsView.swift` | Modified | Added TPPSectionView after BenchmarkSectionView block |
| `cc-hdrmTests/Services/TPPChartDataServiceTests.swift` | New | Service tests: insight, averages, moving avg, shifts, models, weighting, time range |
| `cc-hdrmTests/Models/TPPChartDataTests.swift` | New | Model tests: isEmpty, properties, static empty |
| `_bmad-output/implementation-artifacts/20-4-tpp-trend-visualization.md` | Modified | Task completion tracking, dev agent record |
