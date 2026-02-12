import Foundation
@testable import cc_hdrm

@MainActor
final class MockPatternNotificationService: PatternNotificationServiceProtocol {
    var processedFindings: [[PatternFinding]] = []
    var processCallCount = 0

    func processFindings(_ findings: [PatternFinding]) async {
        processCallCount += 1
        processedFindings.append(findings)
    }
}
