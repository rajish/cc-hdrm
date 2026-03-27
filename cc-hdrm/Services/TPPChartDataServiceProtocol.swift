import Foundation

/// Protocol for preparing TPP data for chart visualization.
protocol TPPChartDataServiceProtocol: Sendable {
    /// Loads and transforms TPP measurement data into chart-ready format.
    /// - Parameters:
    ///   - timeRange: The time range to query data for
    ///   - model: Optional model filter. Nil loads data for all models.
    /// - Returns: Transformed chart data ready for rendering
    func loadTPPData(timeRange: TimeRange, model: String?) async throws -> TPPChartData

    /// Returns distinct models that have TPP data, sorted by frequency (most data first).
    func availableModels() async throws -> [String]
}
