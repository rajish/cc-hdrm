import Foundation
import Testing
@testable import cc_hdrm

@Suite("TPPMeasurement Tests")
struct TPPMeasurementTests {

    @Test("BenchmarkVariant rawValue round-trips correctly")
    func benchmarkVariantRawValues() {
        #expect(BenchmarkVariant.outputHeavy.rawValue == "output-heavy")
        #expect(BenchmarkVariant.inputHeavy.rawValue == "input-heavy")
        #expect(BenchmarkVariant.cacheHeavy.rawValue == "cache-heavy")

        #expect(BenchmarkVariant(rawValue: "output-heavy") == .outputHeavy)
        #expect(BenchmarkVariant(rawValue: "input-heavy") == .inputHeavy)
        #expect(BenchmarkVariant(rawValue: "cache-heavy") == .cacheHeavy)
        #expect(BenchmarkVariant(rawValue: "invalid") == nil)
    }

    @Test("MeasurementSource rawValue round-trips correctly")
    func measurementSourceRawValues() {
        #expect(MeasurementSource.benchmark.rawValue == "benchmark")
        #expect(MeasurementSource.passive.rawValue == "passive")
        #expect(MeasurementSource.passiveBackfill.rawValue == "passive-backfill")
        #expect(MeasurementSource.rollupBackfill.rawValue == "rollup-backfill")
    }

    @Test("computedTppFiveHour returns correct value when delta is positive")
    func computedTppFiveHourPositiveDelta() {
        let measurement = TPPMeasurement(
            id: nil, timestamp: 1000, windowStart: nil, model: "test",
            variant: "output-heavy", source: .benchmark,
            fiveHourBefore: 10.0, fiveHourAfter: 12.0, fiveHourDelta: 2.0,
            sevenDayBefore: nil, sevenDayAfter: nil, sevenDayDelta: nil,
            inputTokens: 100, outputTokens: 900,
            cacheCreateTokens: 0, cacheReadTokens: 0,
            totalRawTokens: 1000,
            tppFiveHour: nil, tppSevenDay: nil,
            confidence: .high, messageCount: 1
        )
        #expect(measurement.computedTppFiveHour == 500.0) // 1000 / 2.0
    }

    @Test("computedTppFiveHour returns nil when delta is zero")
    func computedTppFiveHourZeroDelta() {
        let measurement = TPPMeasurement(
            id: nil, timestamp: 1000, windowStart: nil, model: "test",
            variant: "output-heavy", source: .benchmark,
            fiveHourBefore: 10.0, fiveHourAfter: 10.0, fiveHourDelta: 0.0,
            sevenDayBefore: nil, sevenDayAfter: nil, sevenDayDelta: nil,
            inputTokens: 100, outputTokens: 900,
            cacheCreateTokens: 0, cacheReadTokens: 0,
            totalRawTokens: 1000,
            tppFiveHour: nil, tppSevenDay: nil,
            confidence: .high, messageCount: 1
        )
        #expect(measurement.computedTppFiveHour == nil)
    }

    @Test("computedTppFiveHour returns nil when delta is nil")
    func computedTppFiveHourNilDelta() {
        let measurement = TPPMeasurement(
            id: nil, timestamp: 1000, windowStart: nil, model: "test",
            variant: "output-heavy", source: .benchmark,
            fiveHourBefore: nil, fiveHourAfter: nil, fiveHourDelta: nil,
            sevenDayBefore: nil, sevenDayAfter: nil, sevenDayDelta: nil,
            inputTokens: 100, outputTokens: 900,
            cacheCreateTokens: 0, cacheReadTokens: 0,
            totalRawTokens: 1000,
            tppFiveHour: nil, tppSevenDay: nil,
            confidence: .high, messageCount: 1
        )
        #expect(measurement.computedTppFiveHour == nil)
    }

    @Test("computedTppSevenDay returns correct value when delta is positive")
    func computedTppSevenDayPositiveDelta() {
        let measurement = TPPMeasurement(
            id: nil, timestamp: 1000, windowStart: nil, model: "test",
            variant: "output-heavy", source: .benchmark,
            fiveHourBefore: nil, fiveHourAfter: nil, fiveHourDelta: nil,
            sevenDayBefore: 5.0, sevenDayAfter: 6.0, sevenDayDelta: 1.0,
            inputTokens: 100, outputTokens: 400,
            cacheCreateTokens: 0, cacheReadTokens: 0,
            totalRawTokens: 500,
            tppFiveHour: nil, tppSevenDay: nil,
            confidence: .high, messageCount: 1
        )
        #expect(measurement.computedTppSevenDay == 500.0)
    }

    @Test("fromBenchmark creates measurement with computed TPP values")
    func fromBenchmarkComputation() {
        let m = TPPMeasurement.fromBenchmark(
            model: "claude-sonnet-4-6",
            variant: .outputHeavy,
            fiveHourBefore: 10.0,
            fiveHourAfter: 14.0,
            sevenDayBefore: 2.0,
            sevenDayAfter: 3.0,
            inputTokens: 15,
            outputTokens: 985,
            cacheCreateTokens: 0,
            cacheReadTokens: 0
        )

        #expect(m.model == "claude-sonnet-4-6")
        #expect(m.variant == "output-heavy")
        #expect(m.source == .benchmark)
        #expect(m.totalRawTokens == 1000)
        #expect(m.fiveHourDelta == 4.0)
        #expect(m.tppFiveHour == 250.0) // 1000 / 4.0
        #expect(m.sevenDayDelta == 1.0)
        #expect(m.tppSevenDay == 1000.0) // 1000 / 1.0
        #expect(m.confidence == .high)
        #expect(m.messageCount == 1)
    }

    @Test("fromBenchmark with zero delta produces nil TPP")
    func fromBenchmarkZeroDelta() {
        let m = TPPMeasurement.fromBenchmark(
            model: "claude-sonnet-4-6",
            variant: .outputHeavy,
            fiveHourBefore: 10.0,
            fiveHourAfter: 10.0,
            sevenDayBefore: nil,
            sevenDayAfter: nil,
            inputTokens: 15,
            outputTokens: 485
        )

        #expect(m.fiveHourDelta == 0.0)
        #expect(m.tppFiveHour == nil)
        #expect(m.sevenDayDelta == nil)
        #expect(m.tppSevenDay == nil)
    }

    @Test("BenchmarkVariant displayName is correct")
    func variantDisplayNames() {
        #expect(BenchmarkVariant.outputHeavy.displayName == "Output-heavy")
        #expect(BenchmarkVariant.inputHeavy.displayName == "Input-heavy")
        #expect(BenchmarkVariant.cacheHeavy.displayName == "Cache-heavy")
    }

    @Test("BenchmarkVariant CaseIterable has all cases")
    func variantCaseIterable() {
        #expect(BenchmarkVariant.allCases.count == 3)
    }
}
