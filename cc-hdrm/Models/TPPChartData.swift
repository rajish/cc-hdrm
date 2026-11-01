import Foundation

/// Direction of a detected TPP trend shift.
enum ShiftDirection: Sendable {
    case up
    case down
}

/// A single point in the TPP trend chart.
struct TPPChartPoint: Sendable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let tppValue: Double
    let source: MeasurementSource
    let confidence: MeasurementConfidence
    let isAverage: Bool
}

/// Annotation marking a detected shift in TPP trend.
struct TPPShiftAnnotation: Sendable, Identifiable {
    let id = UUID()
    let date: Date
    let direction: ShiftDirection
    let percentChange: Double
    let label: String
}

/// Discovered token type weighting ratios from benchmark variants.
struct TPPWeightingDiscovery: Sendable {
    let model: String
    let outputToInputRatio: Double?
    let cacheToInputRatio: Double?
    let lastMeasuredDate: Date
}

/// Chart-ready data for the TPP trend visualization.
struct TPPChartData: Sendable {
    let passivePoints: [TPPChartPoint]
    let benchmarkPoints: [TPPChartPoint]
    let trendLine: [TPPChartPoint]
    let shiftAnnotations: [TPPShiftAnnotation]
    let insightText: String
    let availableModels: [String]
    let weightingDiscovery: TPPWeightingDiscovery?

    /// True when there is no passive AND no benchmark data.
    var isEmpty: Bool {
        passivePoints.isEmpty && benchmarkPoints.isEmpty
    }

    /// Empty chart data with a default insight message.
    static let empty = TPPChartData(
        passivePoints: [],
        benchmarkPoints: [],
        trendLine: [],
        shiftAnnotations: [],
        insightText: "Run a benchmark to get a calibrated reading of your token efficiency.",
        availableModels: [],
        weightingDiscovery: nil
    )
}
