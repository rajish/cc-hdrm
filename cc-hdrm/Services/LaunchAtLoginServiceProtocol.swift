import Foundation

/// Protocol for managing launch-at-login registration via SMAppService.
/// Only `LaunchAtLoginService` imports ServiceManagement — all consumers use this protocol.
protocol LaunchAtLoginServiceProtocol: AnyObject {
    /// Whether the app is currently registered as a login item (reads SMAppService.mainApp.status).
    var isEnabled: Bool { get }

    /// Register the app as a login item. May fail silently (logged via os.Logger).
    func register()

    /// Unregister the app as a login item. May fail silently (logged via os.Logger).
    func unregister()
}
