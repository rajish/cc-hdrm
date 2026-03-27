import SwiftUI
import os

/// Container view for the Token Efficiency Trend section in AnalyticsView.
///
/// Displays:
/// - Insight banner with plain-English conclusion
/// - Model picker for switching between models
/// - Series toggles (passive, benchmark, trend)
/// - TPPTrendChartView with the selected model's data
/// - Weighting discovery card (when benchmark variants exist)
/// - Empty state when no data exists
struct TPPSectionView: View {
    let tppStorageService: any TPPStorageServiceProtocol
    let preferencesManager: (any PreferencesManagerProtocol)?
    let selectedTimeRange: TimeRange

    @State private var chartData: TPPChartData = .empty
    @State private var isLoading = false
    @State private var selectedModel: String?
    @State private var showPassive = true
    @State private var showBenchmark = true
    @State private var showTrend = true

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "tpp-section"
    )

    private var isBenchmarkEnabled: Bool {
        preferencesManager?.isBenchmarkEnabled ?? false
    }

    var body: some View {
        // AC-1: Do not render an empty shell when there is no data and benchmark is disabled.
        if isLoading || !chartData.isEmpty || isBenchmarkEnabled {
            sectionContent
                .task(id: TaskTrigger(timeRange: selectedTimeRange, model: selectedModel)) {
                    await loadData()
                }
        } else {
            // Emit nothing — no data and benchmark disabled. Still kick off load so we
            // re-evaluate if passive data arrives.
            Color.clear
                .frame(width: 0, height: 0)
                .task(id: TaskTrigger(timeRange: selectedTimeRange, model: selectedModel)) {
                    await loadData()
                }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack {
                Text("Token Efficiency Trend")
                    .font(.headline)
                Spacer()
            }

            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading trend data...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if chartData.isEmpty {
                emptyState
            } else {
                // Insight banner (AC-7)
                Text(chartData.insightText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                // Controls: model picker + series toggles
                controlsRow

                // Chart
                TPPTrendChartView(
                    chartData: chartData,
                    showPassive: showPassive,
                    showBenchmark: showBenchmark,
                    showTrend: showTrend
                )

                // Legend
                legendRow

                // Weighting discovery card (AC-6)
                if let discovery = chartData.weightingDiscovery {
                    weightingCard(discovery)
                }
            }
        }
    }

    // MARK: - Task Trigger

    /// Hashable trigger combining time range and model for `.task(id:)`.
    private struct TaskTrigger: Equatable, Hashable {
        let timeRange: TimeRange
        let model: String?
    }

    // MARK: - Empty State (AC-8)

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("Enable the Measure button in Settings to start tracking token efficiency. Passive data will also appear after your next Claude Code session.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Controls Row

    private var controlsRow: some View {
        HStack {
            // Model picker
            if chartData.availableModels.count > 1 {
                Picker("Model", selection: $selectedModel) {
                    Text("All").tag(nil as String?)
                    ForEach(chartData.availableModels, id: \.self) { model in
                        Text(model).tag(model as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            } else if let model = chartData.availableModels.first {
                Text(model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Series toggles
            seriesToggles
        }
    }

    private var seriesToggles: some View {
        HStack(spacing: 8) {
            seriesToggleButton(label: "Passive", color: .secondary, isActive: $showPassive)

            Text("|")
                .font(.caption)
                .foregroundStyle(.quaternary)

            seriesToggleButton(label: "Benchmark", color: .accentColor, isActive: $showBenchmark)

            Text("|")
                .font(.caption)
                .foregroundStyle(.quaternary)

            seriesToggleButton(label: "Trend", color: .orange, isActive: $showTrend)
        }
    }

    private func seriesToggleButton(label: String, color: Color, isActive: Binding<Bool>) -> some View {
        Button(action: {
            isActive.wrappedValue.toggle()
        }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isActive.wrappedValue ? color : .secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(isActive.wrappedValue ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel("\(label) series, \(isActive.wrappedValue ? "enabled" : "disabled")")
        .accessibilityHint("Press to toggle")
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: 12) {
            legendItem(symbol: "diamond.fill", label: "Benchmark = calibrated measurement", color: .accentColor)
            legendItem(symbol: "circle.fill", label: "Passive = directional estimate", color: .secondary)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(symbol: String, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.system(size: 7))
            Text(label)
        }
    }

    // MARK: - Weighting Discovery Card (AC-6)

    private func weightingCard(_ discovery: TPPWeightingDiscovery) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Rate Limit Weighting")
                .font(.caption.bold())

            if let outRatio = discovery.outputToInputRatio {
                Text("For \(discovery.model): output tokens cost ~\(String(format: "%.1f", outRatio))x input in rate limit budget.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let cacheRatio = discovery.cacheToInputRatio {
                Text("Cache reads cost ~\(String(format: "%.1f", cacheRatio))x input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Last measured: \(discovery.lastMeasuredDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let service = TPPChartDataService(tppStorage: tppStorageService)
            chartData = try await service.loadTPPData(
                timeRange: selectedTimeRange,
                model: selectedModel
            )

            // Default to the most-used model if none selected
            if selectedModel == nil, let firstModel = chartData.availableModels.first {
                selectedModel = firstModel
            }
        } catch is CancellationError {
            // Discarded — user switched time ranges
        } catch {
            Self.logger.error("Failed to load TPP chart data: \(error.localizedDescription)")
        }
    }
}
