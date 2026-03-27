import Foundation

/// Health status of the Claude Code log parser service.
/// Tracks parsing success rates and scan metadata for degradation detection.
struct LogParserHealth: Sendable, Equatable {
    /// Total JSONL lines processed across all files
    let totalLinesProcessed: Int
    /// Lines that successfully yielded token data
    let successfulExtractions: Int
    /// Lines that failed parsing (malformed JSON, unexpected schema)
    let failedLines: Int
    /// Percentage of successful extractions (0-100)
    let successRate: Double
    /// When the last scan completed
    let lastScanTimestamp: Date
    /// Number of JSONL files scanned
    let filesScanned: Int

    /// Whether the success rate indicates degradation (below 80%)
    var isDegraded: Bool {
        totalLinesProcessed > 0 && successRate < 80.0
    }

    /// User-facing warning message when degraded
    var degradationWarning: String? {
        guard isDegraded else { return nil }
        return "Token data extraction degraded (\(String(format: "%.0f", successRate))% success rate). Claude Code log format may have changed."
    }
}
