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
            "limits": [
                {
                    "kind": "weekly_scoped",
                    "percent": 63,
                    "resets_at": "2026-08-12T22:00:00.059415+00:00",
                    "is_active": true,
                    "scope": { "model": { "id": "claude-fable-5", "display_name": "Fable" } }
                }
            ],
            "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)

        #expect(response.fiveHour?.utilization == 18.0)
        #expect(response.fiveHour?.resetsAt == "2026-01-31T01:59:59.782798+00:00")
        #expect(response.sevenDay?.utilization == 6.0)
        #expect(response.sevenDay?.resetsAt == "2026-02-06T08:59:59.782818+00:00")
        #expect(response.limits?.count == 1)
        #expect(response.limits?.first?.kind == "weekly_scoped")
        #expect(response.limits?.first?.percent == 63)
        #expect(response.limits?.first?.resetsAt == "2026-08-12T22:00:00.059415+00:00")
        #expect(response.limits?.first?.isActive == true)
        #expect(response.limits?.first?.scope?.model?.id == "claude-fable-5")
        #expect(response.limits?.first?.scope?.model?.displayName == "Fable")
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
        #expect(response.limits == nil)
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
        #expect(response.limits == nil)
        #expect(response.extraUsage == nil)
    }

    @Test("malformed JSON throws decode error")
    func malformedJsonThrows() {
        let json = "not json at all".data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(UsageResponse.self, from: json)
        }
    }

    @Test("empty limits array decodes as empty")
    func emptyLimitsArrayDecodes() throws {
        let json = """
        {
            "five_hour": { "utilization": 10.0, "resets_at": null },
            "limits": []
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)

        #expect(response.limits?.isEmpty == true)
    }

    @Test("limits with non-scoped and unknown kinds decode without crash")
    func nonScopedAndUnknownKindsDecode() throws {
        let json = """
        {
            "limits": [
                { "kind": "session", "percent": 18 },
                { "kind": "weekly_all", "percent": 6 },
                { "kind": "daily_scoped", "percent": 40 }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)

        #expect(response.limits?.count == 3)
        #expect(response.limits?[0].kind == "session")
        #expect(response.limits?[1].kind == "weekly_all")
        #expect(response.limits?[2].kind == "daily_scoped")
    }

    @Test("scoped entry with null and missing subfields keeps entry with nils")
    func nullAndMissingSubfieldsDecode() throws {
        let json = """
        {
            "limits": [
                {
                    "kind": "weekly_scoped",
                    "percent": 25,
                    "resets_at": null,
                    "scope": { "model": { "id": null } }
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)

        let entry = try #require(response.limits?.first)
        #expect(entry.kind == "weekly_scoped")
        #expect(entry.percent == 25)
        #expect(entry.resetsAt == nil)
        #expect(entry.scope?.model?.id == nil)
        #expect(entry.scope?.model?.displayName == nil)
    }

    @Test("scoped entry without percent decodes with nil percent")
    func missingPercentDecodes() throws {
        let json = """
        {
            "limits": [
                {
                    "kind": "weekly_scoped",
                    "resets_at": "2026-08-12T22:00:00.059415+00:00",
                    "scope": { "model": { "display_name": "Fable" } }
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)

        let entry = try #require(response.limits?.first)
        #expect(entry.percent == nil)
        #expect(entry.scope?.model?.displayName == "Fable")
    }

    @Test("limit entry with unknown keys decodes without crash")
    func limitEntryUnknownKeysIgnored() throws {
        let json = """
        {
            "limits": [
                {
                    "kind": "weekly_scoped",
                    "percent": 12,
                    "iguana_necktie": { "utilization": 99.0 },
                    "scope": { "model": { "display_name": "Fable" }, "surface": "api", "future_field": 1 }
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)

        let entry = try #require(response.limits?.first)
        #expect(entry.percent == 12)
        #expect(entry.scope?.surface == "api")
        #expect(entry.scope?.model?.displayName == "Fable")
    }
}
