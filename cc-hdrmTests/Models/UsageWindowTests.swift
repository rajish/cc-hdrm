import Testing
@testable import cc_hdrm

@Suite("UsageWindow Tests")
struct UsageWindowTests {

    // MARK: - Case Tests

    @Test("UsageWindow has exactly 2 cases")
    func exactlyTwoCases() {
        #expect(UsageWindow.allCases.count == 2)
        #expect(UsageWindow.allCases.contains(.fiveHour))
        #expect(UsageWindow.allCases.contains(.sevenDay))
    }

    // MARK: - RawValue Tests

    @Test("rawValue is the enum case name")
    func rawValues() {
        #expect(UsageWindow.fiveHour.rawValue == "fiveHour")
        #expect(UsageWindow.sevenDay.rawValue == "sevenDay")
    }

    // MARK: - Equatable Tests

    @Test("UsageWindow conforms to Equatable")
    func equatable() {
        let window1 = UsageWindow.fiveHour
        let window2 = UsageWindow.fiveHour
        let window3 = UsageWindow.sevenDay
        #expect(window1 == window2)
        #expect(window1 != window3)
    }

    // MARK: - Sendable Tests

    @Test("UsageWindow is Sendable")
    func sendable() async {
        let window = UsageWindow.fiveHour
        // Pass across isolation boundary to verify Sendable
        let result = await Task.detached {
            return window
        }.value
        #expect(result == .fiveHour)
    }
}
