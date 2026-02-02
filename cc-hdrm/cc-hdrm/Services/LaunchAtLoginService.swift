import Foundation
import ServiceManagement
import os

/// Production implementation of LaunchAtLoginServiceProtocol.
/// Wraps SMAppService.mainApp for login item registration. This is the ONLY file that imports ServiceManagement.
final class LaunchAtLoginService: LaunchAtLoginServiceProtocol {
    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "preferences"
    )

    /// Reads the actual SMAppService.mainApp.status — reflects System Settings reality.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func register() {
        do {
            try SMAppService.mainApp.register()
            Self.logger.info("Registered as login item")
        } catch {
            Self.logger.error("Failed to register as login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    func unregister() {
        do {
            try SMAppService.mainApp.unregister()
            Self.logger.info("Unregistered as login item")
        } catch {
            Self.logger.error("Failed to unregister as login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}
