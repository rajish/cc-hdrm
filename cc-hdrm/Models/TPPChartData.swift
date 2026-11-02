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
    /// The basis every value in this chart was computed from.
    var basis: TPPBasis = .fiveHour
    /// Bases with readings in the selected range, weekly first.
    var availableBases: [TPPBasis] = []

    /// Accounts with only 5-hour readings keep the original axis label.
    var yAxisLabel: String {
        guard basis == .weekly || availableBases.count > 1 else { return "tokens/%" }
        return basis == .weekly ? "tokens per weekly %" : "tokens per 5-hour %"
    }

    /// Explains the basis when it is not obvious. Nil for accounts with only 5-hour readings.
    var basisCaption: String? {
        guard basis == .weekly || availableBases.count > 1 else { return nil }
        switch basis {
        case .weekly:
            return "Measured on weekly steps: each reading covers at least 1% of the weekly allowance. Whole-percent steps make single readings rough, so read the trend."
        case .fiveHour:
            return "Measured on 5-hour steps. These values run about 10x lower than weekly readings and are not comparable with them."
        }
    }

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
