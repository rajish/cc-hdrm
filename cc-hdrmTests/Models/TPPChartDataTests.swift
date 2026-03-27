import Testing
@testable import cc_hdrm

@Suite("TPPChartData Model Tests")
struct TPPChartDataTests {

    @Test("isEmpty is true when no passive and no benchmark data")
    func isEmptyNoData() {
        let data = TPPChartData(
            passivePoints: [],
            benchmarkPoints: [],
            trendLine: [],
            shiftAnnotations: [],
            insightText: "No data",
            availableModels: [],
            weightingDiscovery: nil
        )
        #expect(data.isEmpty == true)
    }

    @Test("isEmpty is false when passive data exists")
    func isEmptyWithPassive() {
        let point = TPPChartPoint(
            timestamp: Date(),
            tppValue: 1000.0,
            source: .passive,
            confidence: .medium,
            isAverage: false
        )
        let data = TPPChartData(
            passivePoints: [point],
            benchmarkPoints: [],
            trendLine: [],
            shiftAnnotations: [],
            insightText: "Has data",
            availableModels: ["claude-sonnet-4-6"],
            weightingDiscovery: nil
        )
        #expect(data.isEmpty == false)
    }

    @Test("isEmpty is false when benchmark data exists")
    func isEmptyWithBenchmark() {
        let point = TPPChartPoint(
            timestamp: Date(),
            tppValue: 1000.0,
            source: .benchmark,
            confidence: .high,
            isAverage: false
        )
        let data = TPPChartData(
            passivePoints: [],
            benchmarkPoints: [point],
            trendLine: [],
            shiftAnnotations: [],
            insightText: "Has data",
            availableModels: ["claude-sonnet-4-6"],
            weightingDiscovery: nil
        )
        #expect(data.isEmpty == false)
    }

    @Test("Static empty has correct default insight text")
    func staticEmpty() {
        let data = TPPChartData.empty
        #expect(data.isEmpty == true)
        #expect(data.insightText.contains("benchmark"))
        #expect(data.availableModels.isEmpty)
    }

    @Test("TPPChartPoint stores all properties correctly")
    func chartPointProperties() {
        let date = Date()
        let point = TPPChartPoint(
            timestamp: date,
            tppValue: 1234.5,
            source: .passive,
            confidence: .low,
            isAverage: true
        )
        #expect(point.timestamp == date)
        #expect(point.tppValue == 1234.5)
        #expect(point.source == .passive)
        #expect(point.confidence == .low)
        #expect(point.isAverage == true)
    }

    @Test("TPPShiftAnnotation stores direction and label")
    func shiftAnnotation() {
        let annotation = TPPShiftAnnotation(
            date: Date(),
            direction: .down,
            percentChange: -25.0,
            label: "TPP dropped ~25%"
        )
        #expect(annotation.direction == .down)
        #expect(annotation.percentChange == -25.0)
        #expect(annotation.label.contains("dropped"))
    }

    @Test("TPPWeightingDiscovery stores ratios correctly")
    func weightingDiscovery() {
        let discovery = TPPWeightingDiscovery(
            model: "claude-sonnet-4-6",
            outputToInputRatio: 5.0,
            cacheToInputRatio: 0.2,
            lastMeasuredDate: Date()
        )
        #expect(discovery.model == "claude-sonnet-4-6")
        #expect(discovery.outputToInputRatio == 5.0)
        #expect(discovery.cacheToInputRatio == 0.2)
    }
}
