import SwiftUI

/// Settings view for configuring cc-hdrm preferences (AC #2, #3, #4, #5).
/// Reads/writes through PreferencesManagerProtocol — never touches UserDefaults directly.
struct SettingsView: View {
    let preferencesManager: PreferencesManagerProtocol
    var onDone: (() -> Void)?
    var onThresholdChange: (() -> Void)?

    @State private var warningThreshold: Double
    @State private var criticalThreshold: Double
    @State private var pollInterval: TimeInterval
    @State private var launchAtLogin: Bool
    @State private var isUpdating = false

    /// Discrete poll interval options per AC #2.
    private static let pollIntervalOptions: [TimeInterval] = [10, 15, 30, 60, 120, 300]

    init(preferencesManager: PreferencesManagerProtocol, onDone: (() -> Void)? = nil, onThresholdChange: (() -> Void)? = nil) {
        self.preferencesManager = preferencesManager
        self.onDone = onDone
        self.onThresholdChange = onThresholdChange
        _warningThreshold = State(initialValue: preferencesManager.warningThreshold)
        _criticalThreshold = State(initialValue: preferencesManager.criticalThreshold)
        _pollInterval = State(initialValue: preferencesManager.pollInterval)
        _launchAtLogin = State(initialValue: preferencesManager.launchAtLogin)
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

            // Launch at login toggle (AC #2: default off)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    guard !isUpdating else { return }
                    isUpdating = true
                    preferencesManager.launchAtLogin = newValue
                    launchAtLogin = preferencesManager.launchAtLogin
                    isUpdating = false
                }
                .accessibilityLabel("Launch at login, \(launchAtLogin ? "on" : "off")")

            Divider()

            // Reset to Defaults button (AC #4)
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    preferencesManager.resetToDefaults()
                    warningThreshold = preferencesManager.warningThreshold
                    criticalThreshold = preferencesManager.criticalThreshold
                    pollInterval = preferencesManager.pollInterval
                    launchAtLogin = preferencesManager.launchAtLogin
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
}
