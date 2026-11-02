import Foundation

/// Protocol for preparing TPP data for chart visualization.
protocol TPPChartDataServiceProtocol: Sendable {
    /// Loads and transforms TPP measurement data into chart-ready format.
    /// - Parameters:
    ///   - timeRange: The time range to query data for
    ///   - model: Optional model filter. Nil loads data for all models.
    ///   - basis: The basis to show. Nil, or a basis absent from the range, shows the basis of the newest passive reading.
    ///   - hasNoFiveHourNumber: The account has no 5-hour number now, so any 5-hour rows are history.
    /// - Returns: Transformed chart data, all computed from one basis
    func loadTPPData(timeRange: TimeRange, model: String?, basis: TPPBasis?, hasNoFiveHourNumber: Bool) async throws -> TPPChartData

    /// Returns distinct models that have TPP data, sorted by frequency (most data first).
    func availableModels() async throws -> [String]
}
