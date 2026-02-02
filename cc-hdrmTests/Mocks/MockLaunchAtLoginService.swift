import Foundation
@testable import cc_hdrm

/// In-memory mock for LaunchAtLoginServiceProtocol. No SMAppService involved.
final class MockLaunchAtLoginService: LaunchAtLoginServiceProtocol {
    var isEnabled: Bool = false
    var registerCallCount = 0
    var unregisterCallCount = 0
    var shouldThrowOnRegister = false
    var shouldThrowOnUnregister = false

    func register() {
        registerCallCount += 1
        if shouldThrowOnRegister {
            // Simulate failure — isEnabled stays unchanged
            return
        }
        isEnabled = true
    }

    func unregister() {
        unregisterCallCount += 1
        if shouldThrowOnUnregister {
            // Simulate failure — isEnabled stays unchanged
            return
        }
        isEnabled = false
    }
}
