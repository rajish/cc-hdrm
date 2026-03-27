import SwiftUI
import os

/// Observable state object for benchmark progress and results.
@Observable
@MainActor
final class BenchmarkState {
    var progress: BenchmarkProgress = .idle
    var results: [BenchmarkVariantResult] = []
    var isRunning: Bool = false
    var lastMeasurementTimestamp: Int64?
}

/// Token Efficiency section in the analytics view.
/// Shows the Measure button, benchmark progress, and result cards.
struct BenchmarkSectionView: View {
    let benchmarkService: any BenchmarkServiceProtocol
    let tppStorageService: any TPPStorageServiceProtocol
    let preferencesManager: any PreferencesManagerProtocol
    let appState: AppState

    @State private var benchmarkState = BenchmarkState()
    @State private var showRecentWarning = false
    @State private var showActivityWarning = false
    @State private var validationResult: BenchmarkValidation = .ready

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "benchmark-ui"
    )

    /// Known Claude models for auto-detection fallback.
    private static let defaultModels = ["claude-sonnet-4-6"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Token Efficiency")
                    .font(.headline)

                Spacer()

                if benchmarkState.isRunning {
                    Button("Cancel") {
                        benchmarkService.cancel()
                        benchmarkState.isRunning = false
                        benchmarkState.progress = .cancelled
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                } else {
                    Button {
                        Task { await startMeasurement() }
                    } label: {
                        Label("Measure", systemImage: "gauge.with.dots.needle.33percent")
                    }
                    .help("Send test requests to measure token efficiency per model. Uses real tokens from your quota.")
                    .disabled(benchmarkState.isRunning)
                }
            }

            // Progress display
            if benchmarkState.isRunning {
                progressView
            }

            // Results
            if !benchmarkState.results.isEmpty {
                resultsView
            }
        }
        .alert("Recent Measurement", isPresented: $showRecentWarning) {
            Button("Proceed") {
                Task { await executeBenchmark() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let ts = benchmarkState.lastMeasurementTimestamp {
                let minutesAgo = Int((Date().timeIntervalSince1970 * 1000 - Double(ts)) / 60_000)
                Text("Last measurement was \(minutesAgo) minutes ago. Measure again?")
            } else {
                Text("Measure again?")
            }
        }
        .alert("Recent Activity Detected", isPresented: $showActivityWarning) {
            Button("Proceed") {
                Task { await executeBenchmark() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Recent usage detected -- measurement may be noisy. Proceed anyway?")
        }
        .task {
            // Load last benchmark timestamp on appear
            benchmarkState.lastMeasurementTimestamp = try? await tppStorageService.lastBenchmarkTimestamp()
        }
    }

    // MARK: - Progress View

    @ViewBuilder
    private var progressView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            switch benchmarkState.progress {
            case .validating:
                Text("Validating preconditions...")
            case .sendingRequest(let model, let variant):
                Text("Benchmarking \(model)... sending \(variant) request")
            case .polling(let model):
                Text("Polling for utilization update (\(model))...")
            case .computingResult(let model, let variant):
                Text("Result: \(model) \(variant)")
            case .completed:
                Text("Benchmark complete")
            case .cancelled:
                Text("Benchmark cancelled")
            case .failed(let reason):
                Text("Failed: \(reason)")
            case .idle:
                EmptyView()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Results View

    @ViewBuilder
    private var resultsView: some View {
        ForEach(Array(benchmarkState.results.enumerated()), id: \.offset) { _, result in
            resultCard(for: result)
        }

        // Weighting discovery: when multiple variants completed for the same model
        weightingDiscoveryView
    }

    @ViewBuilder
    private func resultCard(for result: BenchmarkVariantResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.model)
                    .font(.caption.bold())
                Text(result.variant.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if result.inconclusive {
                Text("Measurement inconclusive for \(result.model). This model may have a very high token allowance on your tier.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let m = result.measurement, let tpp = m.tppFiveHour {
                let tokens = m.totalRawTokens
                let delta = m.fiveHourDelta ?? 0

                Text("\(tokens) tokens \u{2192} \(String(format: "%.1f", delta))% utilization change \u{2192} TPP = \(formatTPP(tpp))")
                    .font(.caption)

                Text("\(result.model) currently gives you ~\(formatTPP(tpp)) tokens per 1% of your 5h budget")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    @ViewBuilder
    private var weightingDiscoveryView: some View {
        // Group results by model
        let modelGroups = Dictionary(grouping: benchmarkState.results.filter { !$0.inconclusive && $0.measurement != nil }, by: \.model)

        ForEach(Array(modelGroups.keys.sorted()), id: \.self) { model in
            let variants = modelGroups[model] ?? []
            if variants.count >= 2 {
                let outputTPP = variants.first(where: { $0.variant == .outputHeavy })?.measurement?.tppFiveHour
                let inputTPP = variants.first(where: { $0.variant == .inputHeavy })?.measurement?.tppFiveHour
                let cacheTPP = variants.first(where: { $0.variant == .cacheHeavy })?.measurement?.tppFiveHour

                VStack(alignment: .leading, spacing: 2) {
                    Text("Discovered weighting for \(model)")
                        .font(.caption.bold())

                    if let outTPP = outputTPP, let inTPP = inputTPP, inTPP > 0 {
                        let ratio = outTPP / inTPP
                        Text("Output tokens cost ~\(String(format: "%.1f", ratio))x more than input tokens in rate limit budget")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let inTPP = inputTPP, let caTPP = cacheTPP, inTPP > 0 {
                        let ratio = caTPP / inTPP
                        Text("Cache reads cost ~\(String(format: "%.1f", ratio))x input")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }
        }
    }

    // MARK: - Actions

    private func startMeasurement() async {
        // Check for recent measurement (AC-8)
        if let ts = benchmarkState.lastMeasurementTimestamp {
            let oneHourAgo = Int64(Date().timeIntervalSince1970 * 1000) - 3_600_000
            if ts > oneHourAgo {
                showRecentWarning = true
                return
            }
        }

        // Pre-measurement validation (AC-2)
        benchmarkState.progress = .validating
        let validation = await benchmarkService.validatePreconditions()

        switch validation {
        case .ready:
            await executeBenchmark()
        case .tokenExpired:
            benchmarkState.progress = .failed("Sign in to Anthropic first")
        case .utilizationTooHigh:
            benchmarkState.progress = .failed("Not enough headroom for a reliable measurement. Wait for a reset.")
        case .recentActivity:
            showActivityWarning = true
        }
    }

    private func executeBenchmark() async {
        benchmarkState.isRunning = true
        benchmarkState.results = []

        let models: [String]
        let storedModels = preferencesManager.benchmarkModels
        if storedModels.isEmpty {
            models = Self.defaultModels
        } else {
            models = storedModels
        }

        let variantStrings = preferencesManager.benchmarkVariants
        let variants = variantStrings.compactMap { BenchmarkVariant(rawValue: $0) }
        let effectiveVariants = variants.isEmpty ? [BenchmarkVariant.outputHeavy] : variants

        do {
            let results = try await benchmarkService.runBenchmark(
                models: models,
                variants: effectiveVariants,
                onProgress: { [benchmarkState] progress in
                    Task { @MainActor in
                        benchmarkState.progress = progress
                    }
                }
            )
            benchmarkState.results = results
            benchmarkState.lastMeasurementTimestamp = try? await tppStorageService.lastBenchmarkTimestamp()
        } catch {
            benchmarkState.progress = .failed(error.localizedDescription)
        }

        benchmarkState.isRunning = false
    }

    // MARK: - Formatting

    private func formatTPP(_ tpp: Double) -> String {
        if tpp >= 1000 {
            return String(format: "%.0f", tpp)
        } else {
            return String(format: "%.1f", tpp)
        }
    }
}
