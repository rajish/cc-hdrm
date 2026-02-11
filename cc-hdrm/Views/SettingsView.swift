import SwiftUI

/// Settings view for configuring cc-hdrm preferences (AC #2, #3, #4, #5).
/// Reads/writes through PreferencesManagerProtocol — never touches UserDefaults directly.
struct SettingsView: View {
    let preferencesManager: PreferencesManagerProtocol
    let launchAtLoginService: LaunchAtLoginServiceProtocol
    let historicalDataService: (any HistoricalDataServiceProtocol)?
    var onDone: (() -> Void)?
    var onThresholdChange: (() -> Void)?
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

    /// Discrete poll interval options per AC #2.
    private static let pollIntervalOptions: [TimeInterval] = [10, 15, 30, 60, 120, 300]

    /// Discrete retention options mapping display labels to day values.
    private static let retentionOptions: [(label: String, days: Int)] = [
        ("30 days", 30),
        ("90 days", 90),
        ("6 months", 180),
        ("1 year", 365),
        ("2 years", 730),
        ("5 years", 1825),
    ]

    /// Warning threshold for database size (500 MB).
    private static let databaseSizeWarningThreshold: Int64 = 524_288_000

    init(preferencesManager: PreferencesManagerProtocol, launchAtLoginService: LaunchAtLoginServiceProtocol, historicalDataService: (any HistoricalDataServiceProtocol)? = nil, onDone: (() -> Void)? = nil, onThresholdChange: (() -> Void)? = nil, onClearHistory: (() -> Void)? = nil) {
        self.preferencesManager = preferencesManager
        self.launchAtLoginService = launchAtLoginService
        self.historicalDataService = historicalDataService
        self.onDone = onDone
        self.onThresholdChange = onThresholdChange
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
                    showAdvanced = false
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
