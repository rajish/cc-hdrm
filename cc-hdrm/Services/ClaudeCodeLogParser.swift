import Foundation
import os

/// Scans Claude Code JSONL session logs and extracts token consumption data.
/// Supports incremental scanning with persisted file offsets for efficient re-scans.
///
/// ## Thread Safety
/// Uses `@unchecked Sendable` with an internal `NSLock` to protect all mutable state,
/// following the same pattern as `DatabaseManager`.
final class ClaudeCodeLogParser: ClaudeCodeLogParserProtocol, @unchecked Sendable {

    // MARK: - Scan State Persistence

    /// Persisted state for a single JSONL file.
    struct FileScanState: Codable, Sendable {
        var byteOffset: UInt64
        var lastModified: Int64
    }

    /// Top-level scan state persisted to disk.
    struct ScanState: Codable, Sendable {
        var version: Int = 1
        var lastFullScanTimestamp: Int64?
        var files: [String: FileScanState] = [:]
    }

    // MARK: - Properties

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "logparser"
    )

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601WithoutFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private let lock = NSLock()

    // MARK: - Protected State (access only under lock)

    private var records: [TokenRecord] = []
    private var scanState = ScanState()
    private var totalLinesProcessed: Int = 0
    private var successfulExtractions: Int = 0
    private var failedLines: Int = 0
    private var lastScanTimestamp: Date = .distantPast
    private var filesScanned: Int = 0

    // MARK: - Immutable Configuration

    private let scanStatePath: URL
    private let claudeProjectsPath: URL
    private let dataRetentionDays: Int
    private let fileManager: FileManager

    // MARK: - Init

    /// Creates a log parser with the default production paths.
    /// - Parameter dataRetentionDays: Number of days to retain data (default: 365)
    init(dataRetentionDays: Int = PreferencesDefaults.dataRetentionDays) {
        let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.scanStatePath = appSupportURL
            .appendingPathComponent("cc-hdrm", isDirectory: true)
            .appendingPathComponent("log-scan-state.json")
        self.claudeProjectsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        self.dataRetentionDays = dataRetentionDays
        self.fileManager = .default
        loadScanState()
    }

    /// Test-only initializer with injectable paths.
    init(scanStatePath: URL, claudeProjectsPath: URL, dataRetentionDays: Int = 365, fileManager: FileManager = .default) {
        self.scanStatePath = scanStatePath
        self.claudeProjectsPath = claudeProjectsPath
        self.dataRetentionDays = dataRetentionDays
        self.fileManager = fileManager
        loadScanState()
    }

    // MARK: - ClaudeCodeLogParserProtocol

    func scan() async {
        Self.logger.info("Starting log scan")
        let jsonlFiles = discoverJSONLFiles()
        Self.logger.info("Discovered \(jsonlFiles.count) JSONL files")

        var newRecords: [TokenRecord] = []
        var scanTotalLines = 0
        var scanSuccessful = 0
        var scanFailed = 0

        for filePath in jsonlFiles {
            let result = processFile(filePath)
            newRecords.append(contentsOf: result.records)
            scanTotalLines += result.totalLines
            scanSuccessful += result.successfulLines
            scanFailed += result.failedLines
        }

        mergeScanResults(
            newRecords: newRecords,
            totalLines: scanTotalLines,
            successful: scanSuccessful,
            failed: scanFailed,
            fileCount: jsonlFiles.count
        )

        persistScanState()

        Self.logger.info("Scan complete: \(newRecords.count) records from \(jsonlFiles.count) files (\(scanSuccessful) ok, \(scanFailed) failed)")
    }

    func getTokens(from start: Int64, to end: Int64, model: String?) -> [TokenAggregate] {
        lock.lock()
        let snapshot = records
        lock.unlock()

        // Binary search for start index
        let startIdx = binarySearchLowerBound(snapshot, timestamp: start)
        guard startIdx < snapshot.count else { return [] }

        var aggregates: [String: TokenAggregate] = [:]

        for i in startIdx..<snapshot.count {
            let record = snapshot[i]
            if record.timestamp >= end { break }
            if record.timestamp < start { continue }
            if let filterModel = model, record.model != filterModel { continue }

            if var existing = aggregates[record.model] {
                existing.inputTokens += record.inputTokens
                existing.outputTokens += record.outputTokens
                existing.cacheCreateTokens += record.cacheCreateTokens
                existing.cacheReadTokens += record.cacheReadTokens
                existing.messageCount += 1
                aggregates[record.model] = existing
            } else {
                aggregates[record.model] = TokenAggregate(
                    model: record.model,
                    inputTokens: record.inputTokens,
                    outputTokens: record.outputTokens,
                    cacheCreateTokens: record.cacheCreateTokens,
                    cacheReadTokens: record.cacheReadTokens,
                    messageCount: 1
                )
            }
        }

        return Array(aggregates.values).sorted { $0.model < $1.model }
    }

    func getHealth() -> LogParserHealth {
        lock.lock()
        let total = totalLinesProcessed
        let successful = successfulExtractions
        let failed = failedLines
        let lastScan = lastScanTimestamp
        let files = filesScanned
        lock.unlock()

        let rate = total > 0 ? (Double(successful) / Double(total)) * 100.0 : 100.0
        return LogParserHealth(
            totalLinesProcessed: total,
            successfulExtractions: successful,
            failedLines: failed,
            successRate: rate,
            lastScanTimestamp: lastScan,
            filesScanned: files
        )
    }

    // MARK: - State Mutation (synchronous, lock-safe)

    /// Merge scan results into in-memory state under lock.
    /// Extracted as a synchronous method so NSLock can be used safely (not in async context).
    private func mergeScanResults(newRecords: [TokenRecord], totalLines: Int, successful: Int, failed: Int, fileCount: Int) {
        lock.lock()
        records.append(contentsOf: newRecords)
        records.sort { $0.timestamp < $1.timestamp }
        totalLinesProcessed += totalLines
        successfulExtractions += successful
        failedLines += failed
        lastScanTimestamp = Date()
        filesScanned = fileCount
        scanState.lastFullScanTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
        lock.unlock()
    }

    // MARK: - File Discovery

    /// Discovers all JSONL files under `~/.claude/projects/` matching the expected patterns.
    /// Filters by data retention window (modification date).
    private func discoverJSONLFiles() -> [String] {
        let projectsPath = claudeProjectsPath.path
        guard fileManager.fileExists(atPath: projectsPath) else {
            Self.logger.info("Claude projects directory not found at \(projectsPath)")
            return []
        }

        var jsonlFiles: [String] = []
        let cutoffDate = Date().addingTimeInterval(-Double(dataRetentionDays) * 86400)

        // Enumerate all contents recursively
        guard let enumerator = fileManager.enumerator(
            at: claudeProjectsPath,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            Self.logger.warning("Failed to create directory enumerator for \(projectsPath)")
            return []
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            // Check if regular file and within retention window
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard resourceValues.isRegularFile == true else { continue }
                if let modDate = resourceValues.contentModificationDate, modDate < cutoffDate {
                    continue
                }
            } catch {
                // If we can't read attributes, still try to process the file
                Self.logger.debug("Failed to read attributes for \(fileURL.path): \(error.localizedDescription)")
            }

            jsonlFiles.append(fileURL.path)
        }

        return jsonlFiles
    }

    // MARK: - File Processing

    /// Result of processing a single JSONL file.
    private struct FileProcessingResult {
        let records: [TokenRecord]
        let totalLines: Int
        let successfulLines: Int
        let failedLines: Int
    }

    /// Process a single JSONL file with incremental scanning support.
    private func processFile(_ filePath: String) -> FileProcessingResult {
        // Determine start offset
        lock.lock()
        let storedState = scanState.files[filePath]
        lock.unlock()

        var startOffset: UInt64 = 0

        // Check file size for truncation detection
        do {
            let attrs = try fileManager.attributesOfItem(atPath: filePath)
            let fileSize = UInt64((attrs[.size] as? Int) ?? 0)

            if let stored = storedState {
                if fileSize < stored.byteOffset {
                    // File was truncated — reset to beginning
                    Self.logger.info("File truncated, re-scanning: \(filePath)")
                    startOffset = 0
                } else if fileSize == stored.byteOffset {
                    // No new data
                    return FileProcessingResult(records: [], totalLines: 0, successfulLines: 0, failedLines: 0)
                } else {
                    startOffset = stored.byteOffset
                }
            }
        } catch {
            Self.logger.warning("Failed to read file attributes: \(filePath) — \(error.localizedDescription)")
            return FileProcessingResult(records: [], totalLines: 0, successfulLines: 0, failedLines: 0)
        }

        // Read new data from offset
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            Self.logger.warning("Failed to open file: \(filePath)")
            return FileProcessingResult(records: [], totalLines: 0, successfulLines: 0, failedLines: 0)
        }
        defer { fileHandle.closeFile() }

        fileHandle.seek(toFileOffset: startOffset)
        let data = fileHandle.readDataToEndOfFile()
        let endOffset = startOffset + UInt64(data.count)

        // Update scan state
        let modifiedMs = Int64(Date().timeIntervalSince1970 * 1000)
        lock.lock()
        scanState.files[filePath] = FileScanState(byteOffset: endOffset, lastModified: modifiedMs)
        lock.unlock()

        guard !data.isEmpty else {
            return FileProcessingResult(records: [], totalLines: 0, successfulLines: 0, failedLines: 0)
        }

        // Parse lines
        guard let content = String(data: data, encoding: .utf8) else {
            Self.logger.warning("Failed to decode UTF-8 from: \(filePath)")
            return FileProcessingResult(records: [], totalLines: 0, successfulLines: 0, failedLines: 0)
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        var pendingByRequestId: [String: (record: TokenRecord, stopReason: String?)] = [:]
        var totalLines = 0
        var successfulLines = 0
        var failedLines = 0

        for line in lines {
            totalLines += 1
            guard let parsed = parseLine(line) else {
                failedLines += 1
                continue
            }

            // parsed is nil for non-assistant or missing-usage lines (not failures)
            guard let extraction = parsed.extraction else {
                // Skipped line (non-assistant, missing usage) — not a failure
                successfulLines += 1
                continue
            }

            successfulLines += 1

            // Deduplicate by requestId
            if let requestId = parsed.requestId {
                if let existing = pendingByRequestId[requestId] {
                    // Keep the one with higher output_tokens, or the one with stop_reason set
                    if extraction.record.outputTokens > existing.record.outputTokens ||
                       (extraction.stopReason != nil && existing.stopReason == nil) {
                        pendingByRequestId[requestId] = (extraction.record, extraction.stopReason)
                    }
                } else {
                    pendingByRequestId[requestId] = (extraction.record, extraction.stopReason)
                }
            } else {
                // No requestId — treat as standalone (shouldn't happen normally)
                pendingByRequestId[UUID().uuidString] = (extraction.record, extraction.stopReason)
            }
        }

        let records = pendingByRequestId.values.map(\.record)
        return FileProcessingResult(records: records, totalLines: totalLines, successfulLines: successfulLines, failedLines: failedLines)
    }

    // MARK: - Line Parsing

    /// Parsed result from a single JSONL line.
    private struct ParsedLine {
        let requestId: String?
        let extraction: ExtractionResult?
    }

    /// Extraction result containing the token record and stop reason.
    private struct ExtractionResult {
        let record: TokenRecord
        let stopReason: String?
    }

    /// Parse a single JSONL line, extracting token data if it's an assistant message with usage.
    /// Returns nil if the line is malformed JSON. Returns ParsedLine with nil extraction if the line
    /// is valid JSON but not an assistant message or lacks usage data.
    private func parseLine(_ line: String) -> ParsedLine? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil // Malformed JSON
        }

        let requestId = json["requestId"] as? String

        // Only process assistant messages
        guard let type = json["type"] as? String, type == "assistant" else {
            return ParsedLine(requestId: requestId, extraction: nil)
        }

        // Extract message.usage
        guard let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else {
            return ParsedLine(requestId: requestId, extraction: nil)
        }

        // Parse timestamp
        let timestamp: Int64
        if let tsString = json["timestamp"] as? String {
            timestamp = parseISO8601ToUnixMs(tsString)
        } else {
            timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        }

        // Extract model
        let model = (message["model"] as? String) ?? "unknown"

        // Extract token counts (default to 0 if missing)
        let inputTokens = usage["input_tokens"] as? Int ?? 0
        let outputTokens = usage["output_tokens"] as? Int ?? 0
        let cacheCreateTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0

        let stopReason = message["stop_reason"] as? String

        let record = TokenRecord(
            timestamp: timestamp,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreateTokens: cacheCreateTokens,
            cacheReadTokens: cacheReadTokens
        )

        return ParsedLine(
            requestId: requestId,
            extraction: ExtractionResult(record: record, stopReason: stopReason)
        )
    }

    /// Parse ISO 8601 timestamp string to Unix milliseconds.
    private func parseISO8601ToUnixMs(_ string: String) -> Int64 {
        if let date = Self.iso8601WithFractional.date(from: string) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        // Try without fractional seconds
        if let date = Self.iso8601WithoutFractional.date(from: string) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        return Int64(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: - Binary Search

    /// Find the lower bound index for a given timestamp in a sorted array.
    private func binarySearchLowerBound(_ records: [TokenRecord], timestamp: Int64) -> Int {
        var lo = 0
        var hi = records.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if records[mid].timestamp < timestamp {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    // MARK: - Scan State Persistence

    /// Load scan state from disk. Called once during init.
    private func loadScanState() {
        guard fileManager.fileExists(atPath: scanStatePath.path) else { return }
        do {
            let data = try Data(contentsOf: scanStatePath)
            let state = try JSONDecoder().decode(ScanState.self, from: data)
            lock.lock()
            scanState = state
            lock.unlock()
            Self.logger.info("Loaded scan state with \(state.files.count) file entries")
        } catch {
            Self.logger.warning("Failed to load scan state: \(error.localizedDescription)")
        }
    }

    /// Persist scan state to disk.
    private func persistScanState() {
        lock.lock()
        let state = scanState
        lock.unlock()

        do {
            let dir = scanStatePath.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let data = try JSONEncoder().encode(state)
            try data.write(to: scanStatePath, options: .atomic)
        } catch {
            Self.logger.warning("Failed to persist scan state: \(error.localizedDescription)")
        }
    }
}
