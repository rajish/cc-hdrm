import Foundation
@testable import cc_hdrm

/// Minimal mock for UpdateCheckServiceProtocol. Stores a result to apply on checkForUpdate().
final class MockUpdateCheckService: UpdateCheckServiceProtocol, @unchecked Sendable {
    var checkForUpdateCallCount = 0
    var availableUpdateResult: AvailableUpdate?
    var appState: AppState?

    func checkForUpdate() async {
        checkForUpdateCallCount += 1
        if let update = availableUpdateResult, let appState {
            await MainActor.run {
                appState.updateAvailableUpdate(update)
            }
        }
    }
}
