import Foundation
import Testing
@testable import cc_hdrm

@Suite("UsageResponse Codable Tests")
struct UsageResponseTests {

    @Test("full API response parses all fields correctly")
    func fullResponseParsesAllFields() throws {
        let json = """
        {
            "five_hour": { "utilization": 18.0, "resets_at": "2026-01-31T01:59:59.782798+00:00" },
            "seven_day": { "utilization": 6.0, "resets_at": "2026-02-06T08:59:59.782818+00:00" },
            "seven_day_sonnet": { "utilization": 0.0, "resets_at": null },
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)

        #expect(response.fiveHour?.utilization == 18.0)
        #expect(response.fiveHour?.resetsAt == "2026-01-31T01:59:59.782798+00:00")
        #expect(response.sevenDay?.utilization == 6.0)
        #expect(response.sevenDay?.resetsAt == "2026-02-06T08:59:59.782818+00:00")
        #expect(response.sevenDaySonnet?.utilization == 0.0)
        #expect(response.sevenDaySonnet?.resetsAt == nil)
        #expect(response.extraUsage?.isEnabled == false)
        #expect(response.extraUsage?.monthlyLimit == nil)
        #expect(response.extraUsage?.usedCredits == nil)
        #expect(response.extraUsage?.utilization == nil)
    }

    @Test("response with missing seven_day parses without crash")
    func missingSevenDayParses() throws {
        let json = """
        {
            "five_hour": { "utilization": 50.0, "resets_at": "2026-01-31T01:59:59+00:00" }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)

        #expect(response.fiveHour?.utilization == 50.0)
        #expect(response.sevenDay == nil)
        #expect(response.sevenDaySonnet == nil)
        #expect(response.extraUsage == nil)
    }

    @Test("response with null resets_at parses as nil")
    func nullResetsAtParsesAsNil() throws {
        let json = """
        {
            "five_hour": { "utilization": 10.0, "resets_at": null }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)

        #expect(response.fiveHour?.utilization == 10.0)
        #expect(response.fiveHour?.resetsAt == nil)
    }

    @Test("response with unknown keys parses without crash")
    func unknownKeysIgnored() throws {
        let json = """
        {
            "five_hour": { "utilization": 18.0, "resets_at": null },
            "iguana_necktie": { "utilization": 99.0 },
            "seven_day_opus": { "utilization": 5.0 }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)

        #expect(response.fiveHour?.utilization == 18.0)
        #expect(response.sevenDay == nil)
    }

    @Test("empty JSON object parses as all-nil UsageResponse")
    func emptyObjectParsesAllNil() throws {
        let json = "{}".data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)

        #expect(response.fiveHour == nil)
        #expect(response.sevenDay == nil)
        #expect(response.sevenDaySonnet == nil)
        #expect(response.extraUsage == nil)
    }

    @Test("malformed JSON throws decode error")
    func malformedJsonThrows() {
        let json = "not json at all".data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(UsageResponse.self, from: json)
        }
    }
}
