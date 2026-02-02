import Foundation

/// Protocol for the update check service, enabling testability via mock injection.
protocol UpdateCheckServiceProtocol: AnyObject, Sendable {
    func checkForUpdate() async
}
