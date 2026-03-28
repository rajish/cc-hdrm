import SwiftUI

/// Settings view for configuring cc-hdrm preferences (AC #2, #3, #4, #5).
/// Reads/writes through PreferencesManagerProtocol — never touches UserDefaults directly.
struct SettingsView: View {
    let preferencesManager: PreferencesManagerProtocol
    let launchAtLoginService: LaunchAtLoginServiceProtocol
    let historicalDataService: (any HistoricalDataServiceProtocol)?
    let backfillService: (any HistoricalTPPBackfillServiceProtocol)?
    let appState: AppState?
    var onDone: (() -> Void)?
    var onThresholdChange: (() -> Void)?
    var onPollIntervalChange: (() -> Void)?
    var onClearHistory: (() -> Void)?

    @State private var warningThreshold: Double
    @State private var criticalThreshold: Double
    @State private var pollInterval: TimeInterval
    @State private var launchAtLogin: Bool
    @State private var isUpdating = false
    @State private var databaseSizeBytes: Int64 = 0
    @State private var dataRetentionDays: Int
    @State private var showClearConfirmation = false
    @State private var isClearing = false
    @State private var showAdvanced = false
    @State private var customFiveHourText: String
    @State private var customSevenDayText: String
    @State private var fiveHourError: String?
    @State private var sevenDayError: String?
    @State private var billingCycleDay: Int
    @State private var apiStatusAlertsEnabled: Bool
    @State private var extraUsageAlertsEnabled: Bool
    @State private var extraUsageThreshold50: Bool
    @State private var extraUsageThreshold75: Bool
    @State private var extraUsageThreshold90: Bool
    @State private var extraUsageEnteredAlert: Bool
    @State private var benchmarkEnabled: Bool
    @State private var benchmarkVariantOutputHeavy: Bool
    @State private var benchmarkVariantInputHeavy: Bool
    @State private var benchmarkVariantCacheHeavy: Bool
    @State private var isBackfillRunning = false
    @State private var backfillResultMessage: String?

    /// Discrete poll interval options per AC #2.
    private static let pollIntervalOptions: [TimeInterval] = [10, 15, 30, 60, 120, 300, 600, 900, 1800]

    /// Discrete retention options mapping display labels to day values.
    private static let retentionOptions: [(label: String, days: Int)] = [
        ("30 days", 30),
        ("90 days", 90),
        ("6 months", 180),
        ("1 year", 365),
        ("2 years", 730),
        ("5 years", 1825),
    ]

    /// Billing cycle day options: 0 = "Not set", 1-28 = specific day.
    private static let billingCycleDayOptions: [Int] = [0] + Array(1...28)

    /// Warning threshold for database size (500 MB).
    private static let databaseSizeWarningThreshold: Int64 = 524_288_000

    init(preferencesManager: PreferencesManagerProtocol, launchAtLoginService: LaunchAtLoginServiceProtocol, historicalDataService: (any HistoricalDataServiceProtocol)? = nil, backfillService: (any HistoricalTPPBackfillServiceProtocol)? = nil, appState: AppState? = nil, onDone: (() -> Void)? = nil, onThresholdChange: (() -> Void)? = nil, onPollIntervalChange: (() -> Void)? = nil, onClearHistory: (() -> Void)? = nil) {
        self.preferencesManager = preferencesManager
        self.launchAtLoginService = launchAtLoginService
        self.historicalDataService = historicalDataService
        self.backfillService = backfillService
        self.appState = appState
        self.onDone = onDone
        self.onThresholdChange = onThresholdChange
        self.onPollIntervalChange = onPollIntervalChange
        self.onClearHistory = onClearHistory
        _warningThreshold = State(initialValue: preferencesManager.warningThreshold)
        _criticalThreshold = State(initialValue: preferencesManager.criticalThreshold)
        _pollInterval = State(initialValue: preferencesManager.pollInterval)
        // Snap to nearest valid picker option so the Picker always has a matching tag
        let rawRetention = preferencesManager.dataRetentionDays
        let validDays = Self.retentionOptions.map(\.days)
        let snapped = validDays.min(by: { abs($0 - rawRetention) < abs($1 - rawRetention) }) ?? rawRetention
        _dataRetentionDays = State(initialValue: snapped)
        // AC #3: Initialize from SMAppService reality, not stored preference
        _launchAtLogin = State(initialValue: launchAtLoginService.isEnabled)
        _customFiveHourText = State(initialValue: preferencesManager.customFiveHourCredits.map(String.init) ?? "")
        _customSevenDayText = State(initialValue: preferencesManager.customSevenDayCredits.map(String.init) ?? "")
        _billingCycleDay = State(initialValue: preferencesManager.billingCycleDay ?? 0)
        _apiStatusAlertsEnabled = State(initialValue: preferencesManager.apiStatusAlertsEnabled)
        _extraUsageAlertsEnabled = State(initialValue: preferencesManager.extraUsageAlertsEnabled)
        _extraUsageThreshold50 = State(initialValue: preferencesManager.extraUsageThreshold50Enabled)
        _extraUsageThreshold75 = State(initialValue: preferencesManager.extraUsageThreshold75Enabled)
        _extraUsageThreshold90 = State(initialValue: preferencesManager.extraUsageThreshold90Enabled)
        _extraUsageEnteredAlert = State(initialValue: preferencesManager.extraUsageEnteredAlertEnabled)
        _benchmarkEnabled = State(initialValue: preferencesManager.isBenchmarkEnabled)
        let storedVariants = preferencesManager.benchmarkVariants
        _benchmarkVariantOutputHeavy = State(initialValue: storedVariants.contains(BenchmarkVariant.outputHeavy.rawValue))
        _benchmarkVariantInputHeavy = State(initialValue: storedVariants.contains(BenchmarkVariant.inputHeavy.rawValue))
        _benchmarkVariantCacheHeavy = State(initialValue: storedVariants.contains(BenchmarkVariant.cacheHeavy.rawValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
                .padding(.bottom, 4)

            // Warning threshold stepper (AC #2: range 6-50%, default 20%)
            HStack {
                Text("Warning threshold")
                Spacer()
                Stepper(
                    "\(Int(warningThreshold))%",
                    value: $warningThreshold,
                    in: 6...50,
                    step: 1
                )
                .onChange(of: warningThreshold) { _, newValue in
                    guard !isUpdating else { return }
                    isUpdating = true
                    preferencesManager.warningThreshold = newValue
                    // Re-read in case PreferencesManager clamped or reset
                    warningThreshold = preferencesManager.warningThreshold
                    criticalThreshold = preferencesManager.criticalThreshold
                    isUpdating = false
                    onThresholdChange?()
                }
                .accessibilityLabel("Warning notification threshold, \(Int(warningThreshold)) percent")
            }

            // Critical threshold stepper (AC #2: range 1-49%, must be < warning)
            HStack {
                Text("Critical threshold")
                Spacer()
                Stepper(
                    "\(Int(criticalThreshold))%",
                    value: $criticalThreshold,
                    in: 1...49,
                    step: 1
                )
                .onChange(of: criticalThreshold) { _, newValue in
                    guard !isUpdating else { return }
                    isUpdating = true
                    preferencesManager.criticalThreshold = newValue
                    // Re-read in case PreferencesManager clamped or reset
                    warningThreshold = preferencesManager.warningThreshold
                    criticalThreshold = preferencesManager.criticalThreshold
                    isUpdating = false
                    onThresholdChange?()
                }
                .accessibilityLabel("Critical notification threshold, \(Int(criticalThreshold)) percent")
            }

            // API Status Alerts toggle (Story 5.4)
            Toggle("API status alerts", isOn: $apiStatusAlertsEnabled)
                .onChange(of: apiStatusAlertsEnabled) { _, newValue in
                    preferencesManager.apiStatusAlertsEnabled = newValue
                }
                .accessibilityLabel("API status alerts, \(apiStatusAlertsEnabled ? "on" : "off")")

            // Extra Usage Alerts subsection (Story 17.4)
            if let appState, appState.extraUsageEnabled {
                Divider()

                Text("Extra Usage Alerts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Toggle("Extra usage alerts", isOn: $extraUsageAlertsEnabled)
                    .onChange(of: extraUsageAlertsEnabled) { _, newValue in
                        preferencesManager.extraUsageAlertsEnabled = newValue
                    }
                    .accessibilityLabel("Extra usage alerts master toggle, \(extraUsageAlertsEnabled ? "on" : "off")")

                Toggle("Alert at 50%", isOn: $extraUsageThreshold50)
                    .padding(.leading, 16)
                    .disabled(!extraUsageAlertsEnabled)
                    .onChange(of: extraUsageThreshold50) { _, newValue in
                        preferencesManager.extraUsageThreshold50Enabled = newValue
                    }
                    .accessibilityLabel("Alert at 50 percent threshold, \(extraUsageThreshold50 ? "on" : "off")")

                Toggle("Alert at 75%", isOn: $extraUsageThreshold75)
                    .padding(.leading, 16)
                    .disabled(!extraUsageAlertsEnabled)
                    .onChange(of: extraUsageThreshold75) { _, newValue in
                        preferencesManager.extraUsageThreshold75Enabled = newValue
                    }
                    .accessibilityLabel("Alert at 75 percent threshold, \(extraUsageThreshold75 ? "on" : "off")")

                Toggle("Alert at 90%", isOn: $extraUsageThreshold90)
                    .padding(.leading, 16)
                    .disabled(!extraUsageAlertsEnabled)
                    .onChange(of: extraUsageThreshold90) { _, newValue in
                        preferencesManager.extraUsageThreshold90Enabled = newValue
                    }
                    .accessibilityLabel("Alert at 90 percent threshold, \(extraUsageThreshold90 ? "on" : "off")")

                Toggle("Entered extra usage", isOn: $extraUsageEnteredAlert)
                    .padding(.leading, 16)
                    .disabled(!extraUsageAlertsEnabled)
                    .onChange(of: extraUsageEnteredAlert) { _, newValue in
                        preferencesManager.extraUsageEnteredAlertEnabled = newValue
                    }
                    .accessibilityLabel("Entered extra usage alert, \(extraUsageEnteredAlert ? "on" : "off")")

                Text("Get notified when your extra usage spending crosses these thresholds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Poll interval picker (AC #2: 10s, 15s, 30s, 60s, 120s, 300s)
            HStack {
                Text("Poll interval")
                Spacer()
                Picker("Poll interval", selection: $pollInterval) {
                    ForEach(Self.pollIntervalOptions, id: \.self) { interval in
                        Text(Self.formatInterval(interval)).tag(interval)
                    }
                }
                .labelsHidden()
                .onChange(of: pollInterval) { _, newValue in
                    guard !isUpdating else { return }
                    isUpdating = true
                    preferencesManager.pollInterval = newValue
                    pollInterval = preferencesManager.pollInterval
                    isUpdating = false
                    onPollIntervalChange?()
                }
                .accessibilityLabel("Poll interval, \(Self.formatInterval(pollInterval))")
            }

            // Launch at login toggle (AC #1, #2, #3: wired to SMAppService via LaunchAtLoginService)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    guard !isUpdating else { return }
                    isUpdating = true
                    if newValue {
                        launchAtLoginService.register()
                    } else {
                        launchAtLoginService.unregister()
                    }
                    // Re-read actual state — handles permission denial / registration failure (Task 3)
                    let actualState = launchAtLoginService.isEnabled
                    launchAtLogin = actualState
                    preferencesManager.launchAtLogin = actualState
                    isUpdating = false
                }
                .accessibilityLabel("Launch at login, \(launchAtLogin ? "on" : "off")")

            // Historical Data section (Story 15.1)
            if historicalDataService != nil {
                Divider()

                Text("Historical Data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Data retention picker
                HStack {
                    Text("Data retention")
                    Spacer()
                    Picker("Data retention", selection: $dataRetentionDays) {
                        ForEach(Self.retentionOptions, id: \.days) { option in
                            Text(option.label).tag(option.days)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: dataRetentionDays) { _, newValue in
                        guard !isUpdating else { return }
                        isUpdating = true
                        preferencesManager.dataRetentionDays = newValue
                        dataRetentionDays = preferencesManager.dataRetentionDays
                        isUpdating = false
                    }
                    .accessibilityLabel("Data retention period, \(Self.retentionLabel(for: dataRetentionDays))")
                }

                // Database size display
                HStack {
                    Text("Database size")
                    Spacer()
                    Text(Self.formatSize(databaseSizeBytes))
                        .foregroundStyle(databaseSizeBytes > Self.databaseSizeWarningThreshold ? Color.headroomWarning : .secondary)
                        .accessibilityLabel("Database size, \(Self.formatSize(databaseSizeBytes))")
                }

                // Warning hint when database is large
                if databaseSizeBytes > Self.databaseSizeWarningThreshold {
                    Text("Consider reducing retention or clearing history")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Clear History button
                HStack {
                    Spacer()
                    Button("Clear History\u{2026}") {
                        showClearConfirmation = true
                    }
                    .disabled(isClearing)
                    .accessibilityLabel("Clear all historical usage data")
                    Spacer()
                }
            }

            // Token Efficiency section (Story 20.1)
            Divider()

            Text("Token Efficiency")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle("Enable Measure button", isOn: $benchmarkEnabled)
                .onChange(of: benchmarkEnabled) { _, newValue in
                    preferencesManager.isBenchmarkEnabled = newValue
                }
                .accessibilityLabel("Enable benchmark measure button, \(benchmarkEnabled ? "on" : "off")")

            if benchmarkEnabled {
                Text("Benchmark variants")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Output-heavy", isOn: $benchmarkVariantOutputHeavy)
                    .padding(.leading, 16)
                    .onChange(of: benchmarkVariantOutputHeavy) { _, _ in syncBenchmarkVariants() }
                    .accessibilityLabel("Output heavy variant, \(benchmarkVariantOutputHeavy ? "on" : "off")")

                Toggle("Input-heavy", isOn: $benchmarkVariantInputHeavy)
                    .padding(.leading, 16)
                    .onChange(of: benchmarkVariantInputHeavy) { _, _ in syncBenchmarkVariants() }
                    .accessibilityLabel("Input heavy variant, \(benchmarkVariantInputHeavy ? "on" : "off")")

                Toggle("Cache-heavy", isOn: $benchmarkVariantCacheHeavy)
                    .padding(.leading, 16)
                    .onChange(of: benchmarkVariantCacheHeavy) { _, _ in syncBenchmarkVariants() }
                    .accessibilityLabel("Cache heavy variant, \(benchmarkVariantCacheHeavy ? "on" : "off")")

                Text("Benchmark sends test requests per model to measure how many tokens equal 1% of your usage budget. Each variant uses ~2K-5K tokens. Running all variants for all models uses the most tokens but reveals the most about rate limit weighting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if preferencesManager.tppBackfillCompleted, let backfillService {
                HStack {
                    Spacer()
                    Button(isBackfillRunning ? "Running\u{2026}" : "Re-run TPP Backfill") {
                        isBackfillRunning = true
                        backfillResultMessage = nil
                        Task {
                            let count = await backfillService.runBackfill(force: true)
                            backfillResultMessage = "Backfill complete — \(count) measurements generated"
                            isBackfillRunning = false
                        }
                    }
                    .disabled(isBackfillRunning)
                    .accessibilityLabel("Re-run historical TPP backfill")
                    Spacer()
                }

                if let message = backfillResultMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Advanced section (Story 15.2: Custom credit limit override)
            Divider()

            DisclosureGroup(isExpanded: $showAdvanced) {
                Text("Override credit limits if your tier isn't recognized")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("5-hour credit limit")
                    Spacer()
                    TextField("None", text: $customFiveHourText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Custom five hour credit limit")
                }
                .onChange(of: customFiveHourText) { _, newValue in
                    guard !isUpdating else { return }
                    isUpdating = true
                    switch Self.validateCreditInput(newValue) {
                    case .clear:
                        preferencesManager.customFiveHourCredits = nil
                        fiveHourError = nil
                    case .valid(let value):
                        preferencesManager.customFiveHourCredits = value
                        fiveHourError = nil
                    case .invalid(let message):
                        fiveHourError = message
                    }
                    isUpdating = false
                }

                if let error = fiveHourError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Validation error: \(error)")
                }

                HStack {
                    Text("7-day credit limit")
                    Spacer()
                    TextField("None", text: $customSevenDayText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Custom seven day credit limit")
                }
                .onChange(of: customSevenDayText) { _, newValue in
                    guard !isUpdating else { return }
                    isUpdating = true
                    switch Self.validateCreditInput(newValue) {
                    case .clear:
                        preferencesManager.customSevenDayCredits = nil
                        sevenDayError = nil
                    case .valid(let value):
                        preferencesManager.customSevenDayCredits = value
                        sevenDayError = nil
                    case .invalid(let message):
                        sevenDayError = message
                    }
                    isUpdating = false
                }

                if let error = sevenDayError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Validation error: \(error)")
                }

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
                    .onChange(of: billingCycleDay) { _, newValue in
                        guard !isUpdating else { return }
                        isUpdating = true
                        preferencesManager.billingCycleDay = newValue == 0 ? nil : newValue
                        billingCycleDay = preferencesManager.billingCycleDay ?? 0
                        appState?.updateBillingCycleDay(preferencesManager.billingCycleDay)
                        isUpdating = false
                    }
                    .accessibilityLabel("Billing cycle day, \(billingCycleDay == 0 ? "not set" : "day \(billingCycleDay)")")
                }
            } label: {
                Text("Advanced")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }

            Divider()

            // Reset to Defaults button (AC #4)
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    preferencesManager.resetToDefaults()
                    launchAtLoginService.unregister()
                    warningThreshold = preferencesManager.warningThreshold
                    criticalThreshold = preferencesManager.criticalThreshold
                    pollInterval = preferencesManager.pollInterval
                    dataRetentionDays = preferencesManager.dataRetentionDays
                    launchAtLogin = launchAtLoginService.isEnabled
                    preferencesManager.launchAtLogin = launchAtLogin
                    customFiveHourText = ""
                    customSevenDayText = ""
                    fiveHourError = nil
                    sevenDayError = nil
                    billingCycleDay = 0
                    appState?.updateBillingCycleDay(nil)
                    apiStatusAlertsEnabled = preferencesManager.apiStatusAlertsEnabled
                    extraUsageAlertsEnabled = preferencesManager.extraUsageAlertsEnabled
                    extraUsageThreshold50 = preferencesManager.extraUsageThreshold50Enabled
                    extraUsageThreshold75 = preferencesManager.extraUsageThreshold75Enabled
                    extraUsageThreshold90 = preferencesManager.extraUsageThreshold90Enabled
                    extraUsageEnteredAlert = preferencesManager.extraUsageEnteredAlertEnabled
                    showAdvanced = false
                    benchmarkEnabled = preferencesManager.isBenchmarkEnabled
                    benchmarkVariantOutputHeavy = true
                    benchmarkVariantInputHeavy = false
                    benchmarkVariantCacheHeavy = false
                    syncBenchmarkVariants()
                    onThresholdChange?()
                }
                .accessibilityLabel("Reset all settings to default values")
                Spacer()
            }

            HStack {
                Spacer()
                Button("Done") {
                    onDone?()
                }
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityLabel("Close settings")
            }
        }
        .padding()
        .frame(width: 280)
        .task {
            // Load database size asynchronously on appear
            if let service = historicalDataService {
                databaseSizeBytes = (try? await service.getDatabaseSize()) ?? 0
            }
        }
        .alert("Clear History?", isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) {
                isClearing = true
                Task {
                    do {
                        try await historicalDataService?.clearAllData()
                        onClearHistory?()
                    } catch {
                        // Clear failed — size will refresh unchanged, indicating failure to user
                    }
                    databaseSizeBytes = (try? await historicalDataService?.getDatabaseSize()) ?? 0
                    isClearing = false
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all historical usage data. Sparkline and analytics will show empty until new data is collected.")
        }
    }

    /// Formats a TimeInterval into a human-readable short string.
    static func formatInterval(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            return "\(seconds / 60)m"
        }
    }

    /// Formats byte count into human-readable size string.
    static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Returns the display label for a given retention days value.
    static func retentionLabel(for days: Int) -> String {
        retentionOptions.first { $0.days == days }?.label ?? "\(days) days"
    }

    /// Syncs benchmark variant toggles to the preferences manager.
    private func syncBenchmarkVariants() {
        var variants: [String] = []
        if benchmarkVariantOutputHeavy { variants.append(BenchmarkVariant.outputHeavy.rawValue) }
        if benchmarkVariantInputHeavy { variants.append(BenchmarkVariant.inputHeavy.rawValue) }
        if benchmarkVariantCacheHeavy { variants.append(BenchmarkVariant.cacheHeavy.rawValue) }
        preferencesManager.benchmarkVariants = variants
    }

    /// Result of validating credit limit text input.
    enum CreditInputValidation: Equatable {
        /// Text was empty — clear the stored preference.
        case clear
        /// Text parsed to a valid positive integer.
        case valid(Int)
        /// Text was invalid — do not update the stored preference.
        case invalid(String)
    }

    /// Validates credit limit text input and returns the appropriate action.
    static func validateCreditInput(_ text: String) -> CreditInputValidation {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return .clear
        } else if let value = Int(trimmed), value > 0 {
            return .valid(value)
        } else {
            return .invalid("Must be a positive whole number")
        }
    }
}
