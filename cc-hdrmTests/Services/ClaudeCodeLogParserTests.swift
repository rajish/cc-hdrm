import Foundation
import Testing
@testable import cc_hdrm

@Suite("ClaudeCodeLogParser Tests")
struct ClaudeCodeLogParserTests {

    // MARK: - Test Helpers

    /// Creates a temporary directory for test fixtures.
    private func makeTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-hdrm-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    /// Creates a parser configured to use temporary test directories.
    private func makeParser(tempDir: URL) -> ClaudeCodeLogParser {
        let scanStatePath = tempDir.appendingPathComponent("scan-state.json")
        let projectsPath = tempDir.appendingPathComponent("projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: projectsPath, withIntermediateDirectories: true)
        return ClaudeCodeLogParser(
            scanStatePath: scanStatePath,
            claudeProjectsPath: projectsPath,
            dataRetentionDays: 365
        )
    }

    /// Creates a JSONL file at the given path with the provided lines.
    private func writeJSONLFile(at directory: URL, name: String = "session.jsonl", lines: [String]) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filePath = directory.appendingPathComponent(name)
        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: filePath, atomically: true, encoding: .utf8)
        return filePath
    }

    /// Creates a valid assistant message JSON line.
    private func assistantLine(
        requestId: String = "req_001",
        timestamp: String = "2026-03-14T19:53:23.101Z",
        model: String = "claude-opus-4-6",
        inputTokens: Int = 100,
        outputTokens: Int = 200,
        cacheCreateTokens: Int = 500,
        cacheReadTokens: Int = 300,
        stopReason: String? = "end_turn"
    ) -> String {
        var stopReasonJSON = "null"
        if let sr = stopReason {
            stopReasonJSON = "\"\(sr)\""
        }
        return """
        {"type":"assistant","timestamp":"\(timestamp)","requestId":"\(requestId)","message":{"model":"\(model)","usage":{"input_tokens":\(inputTokens),"output_tokens":\(outputTokens),"cache_creation_input_tokens":\(cacheCreateTokens),"cache_read_input_tokens":\(cacheReadTokens)},"stop_reason":\(stopReasonJSON)}}
        """
    }

    /// Creates a user-type message JSON line.
    private func userLine(requestId: String = "req_001") -> String {
        return """
        {"type":"user","timestamp":"2026-03-14T19:53:20.000Z","requestId":"\(requestId)","message":{"content":"hello"}}
        """
    }

    /// Creates a system-type message JSON line.
    private func systemLine() -> String {
        return """
        {"type":"system","timestamp":"2026-03-14T19:53:19.000Z","message":{"content":"system prompt"}}
        """
    }

    /// Cleanup helper.
    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - AC-2: Token Extraction Tests

    @Test("Parse valid assistant message with all usage fields")
    func parseValidAssistantMessage() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)
        let projectDir = tempDir.appendingPathComponent("projects/proj1")
        _ = try writeJSONLFile(at: projectDir, lines: [
            assistantLine(
                requestId: "req_001",
                model: "claude-opus-4-6",
                inputTokens: 100,
                outputTokens: 200,
                cacheCreateTokens: 500,
                cacheReadTokens: 300
            )
        ])

        await parser.scan()

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let hourAgo = now - 3_600_000
        let aggregates = parser.getTokens(from: hourAgo, to: now + 3_600_000)

        #expect(aggregates.count == 1)
        #expect(aggregates[0].model == "claude-opus-4-6")
        #expect(aggregates[0].inputTokens == 100)
        #expect(aggregates[0].outputTokens == 200)
        #expect(aggregates[0].cacheCreateTokens == 500)
        #expect(aggregates[0].cacheReadTokens == 300)
        #expect(aggregates[0].messageCount == 1)
    }

    @Test("Skip non-assistant messages (user, system)")
    func skipNonAssistantMessages() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)
        let projectDir = tempDir.appendingPathComponent("projects/proj1")
        _ = try writeJSONLFile(at: projectDir, lines: [
            userLine(),
            systemLine(),
            """
            {"type":"file-history-snapshot","timestamp":"2026-03-14T19:53:18.000Z","data":{}}
            """,
            assistantLine(requestId: "req_002", outputTokens: 50)
        ])

        await parser.scan()

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let aggregates = parser.getTokens(from: 0, to: now + 3_600_000)

        #expect(aggregates.count == 1)
        #expect(aggregates[0].outputTokens == 50)
        #expect(aggregates[0].messageCount == 1)
    }

    @Test("Handle malformed JSON lines gracefully")
    func handleMalformedJSON() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)
        let projectDir = tempDir.appendingPathComponent("projects/proj1")
        _ = try writeJSONLFile(at: projectDir, lines: [
            "not json at all",
            "{incomplete json",
            "",
            assistantLine(requestId: "req_good", outputTokens: 42)
        ])

        await parser.scan()

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let aggregates = parser.getTokens(from: 0, to: now + 3_600_000)

        #expect(aggregates.count == 1)
        #expect(aggregates[0].outputTokens == 42)

        let health = parser.getHealth()
        #expect(health.failedLines >= 2) // "not json at all" and "{incomplete json"
    }

    @Test("Handle assistant message without usage field")
    func handleMissingUsage() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)
        let projectDir = tempDir.appendingPathComponent("projects/proj1")
        _ = try writeJSONLFile(at: projectDir, lines: [
            """
            {"type":"assistant","timestamp":"2026-03-14T19:53:23.101Z","requestId":"req_nousage","message":{"model":"claude-opus-4-6"}}
            """,
            assistantLine(requestId: "req_withusage", outputTokens: 77)
        ])

        await parser.scan()

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let aggregates = parser.getTokens(from: 0, to: now + 3_600_000)

        #expect(aggregates.count == 1)
        #expect(aggregates[0].outputTokens == 77)
    }

    // MARK: - AC-3: Request Deduplication Tests

    @Test("Dedup: keep message with highest output_tokens for same requestId")
    func deduplicateByRequestId() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)
        let projectDir = tempDir.appendingPathComponent("projects/proj1")
        _ = try writeJSONLFile(at: projectDir, lines: [
            assistantLine(requestId: "req_dup", outputTokens: 11, stopReason: nil),
            assistantLine(requestId: "req_dup", outputTokens: 11, stopReason: nil),
            assistantLine(requestId: "req_dup", outputTokens: 228, stopReason: "tool_use")
        ])

        await parser.scan()

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let aggregates = parser.getTokens(from: 0, to: now + 3_600_000)

        #expect(aggregates.count == 1)
        #expect(aggregates[0].outputTokens == 228)
        #expect(aggregates[0].messageCount == 1)
    }

    @Test("Dedup: prefer message with stop_reason set")
    func deduplicatePreferStopReason() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)
        let projectDir = tempDir.appendingPathComponent("projects/proj1")
        _ = try writeJSONLFile(at: projectDir, lines: [
            assistantLine(requestId: "req_sr", outputTokens: 50, stopReason: nil),
            assistantLine(requestId: "req_sr", outputTokens: 50, stopReason: "end_turn")
        ])

        await parser.scan()

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let aggregates = parser.getTokens(from: 0, to: now + 3_600_000)

        #expect(aggregates.count == 1)
        #expect(aggregates[0].outputTokens == 50)
        #expect(aggregates[0].messageCount == 1)
    }

    // MARK: - AC-4: Incremental Scanning Tests

    @Test("Incremental scan reads only new data after offset")
    func incrementalScan() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)
        let projectDir = tempDir.appendingPathComponent("projects/proj1")
        let filePath = try writeJSONLFile(at: projectDir, lines: [
            assistantLine(requestId: "req_a", timestamp: "2026-03-14T10:00:00.000Z", outputTokens: 100)
        ])

        await parser.scan()

        var aggregates = parser.getTokens(from: 0, to: Int64(Date().timeIntervalSince1970 * 1000) + 3_600_000)
        #expect(aggregates.count == 1)
        #expect(aggregates[0].outputTokens == 100)

        // Append new data
        let newLine = assistantLine(requestId: "req_b", timestamp: "2026-03-14T11:00:00.000Z", outputTokens: 200) + "\n"
        let fileHandle = try FileHandle(forWritingTo: filePath)
        fileHandle.seekToEndOfFile()
        fileHandle.write(newLine.data(using: .utf8)!)
        fileHandle.closeFile()

        await parser.scan()

        aggregates = parser.getTokens(from: 0, to: Int64(Date().timeIntervalSince1970 * 1000) + 3_600_000)
        #expect(aggregates.count == 1) // Same model
        #expect(aggregates[0].outputTokens == 300) // 100 + 200
        #expect(aggregates[0].messageCount == 2)
    }

    @Test("Truncated file resets offset to zero")
    func truncatedFileResetsOffset() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)
        let projectDir = tempDir.appendingPathComponent("projects/proj1")
        let filePath = try writeJSONLFile(at: projectDir, lines: [
            assistantLine(requestId: "req_orig1", timestamp: "2026-03-14T10:00:00.000Z", outputTokens: 100),
            assistantLine(requestId: "req_orig2", timestamp: "2026-03-14T10:01:00.000Z", outputTokens: 200)
        ])

        await parser.scan()

        // Truncate file by overwriting with shorter content
        let shortContent = assistantLine(requestId: "req_new", timestamp: "2026-03-14T12:00:00.000Z", outputTokens: 50) + "\n"
        try shortContent.write(to: filePath, atomically: true, encoding: .utf8)

        await parser.scan()

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let aggregates = parser.getTokens(from: 0, to: now + 3_600_000)
        // Should have records from both scans: 100, 200 from first scan + 50 from re-scan
        #expect(aggregates.count == 1)
        #expect(aggregates[0].outputTokens == 350)
        #expect(aggregates[0].messageCount == 3)
    }

    // MARK: - AC-5: Aggregation Tests

    @Test("Aggregate tokens from multiple models")
    func aggregateMultipleModels() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)
        let projectDir = tempDir.appendingPathComponent("projects/proj1")
        _ = try writeJSONLFile(at: projectDir, lines: [
            assistantLine(requestId: "req_o1", timestamp: "2026-03-14T10:00:00.000Z", model: "claude-opus-4-6", inputTokens: 100, outputTokens: 200),
            assistantLine(requestId: "req_s1", timestamp: "2026-03-14T10:01:00.000Z", model: "claude-sonnet-4-6", inputTokens: 50, outputTokens: 75),
            assistantLine(requestId: "req_o2", timestamp: "2026-03-14T10:02:00.000Z", model: "claude-opus-4-6", inputTokens: 150, outputTokens: 300)
        ])

        await parser.scan()

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let aggregates = parser.getTokens(from: 0, to: now + 3_600_000)

        #expect(aggregates.count == 2)

        // Sorted by model name
        let opus = aggregates.first { $0.model == "claude-opus-4-6" }
        let sonnet = aggregates.first { $0.model == "claude-sonnet-4-6" }

        #expect(opus != nil)
        #expect(opus?.inputTokens == 250)
        #expect(opus?.outputTokens == 500)
        #expect(opus?.messageCount == 2)

        #expect(sonnet != nil)
        #expect(sonnet?.inputTokens == 50)
        #expect(sonnet?.outputTokens == 75)
        #expect(sonnet?.messageCount == 1)
    }

    @Test("Time range filtering returns correct subset")
    func timeRangeFiltering() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)
        let projectDir = tempDir.appendingPathComponent("projects/proj1")
        _ = try writeJSONLFile(at: projectDir, lines: [
            assistantLine(requestId: "req_early", timestamp: "2026-03-14T08:00:00.000Z", outputTokens: 100),
            assistantLine(requestId: "req_mid", timestamp: "2026-03-14T10:00:00.000Z", outputTokens: 200),
            assistantLine(requestId: "req_late", timestamp: "2026-03-14T12:00:00.000Z", outputTokens: 300)
        ])

        await parser.scan()

        // Query only the middle window (9:00-11:00)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let start = Int64(formatter.date(from: "2026-03-14T09:00:00Z")!.timeIntervalSince1970 * 1000)
        let end = Int64(formatter.date(from: "2026-03-14T11:00:00Z")!.timeIntervalSince1970 * 1000)

        let aggregates = parser.getTokens(from: start, to: end)
        #expect(aggregates.count == 1)
        #expect(aggregates[0].outputTokens == 200)
        #expect(aggregates[0].messageCount == 1)
    }

    @Test("Model filtering returns only matching model")
    func modelFiltering() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)
        let projectDir = tempDir.appendingPathComponent("projects/proj1")
        _ = try writeJSONLFile(at: projectDir, lines: [
            assistantLine(requestId: "req_o1", timestamp: "2026-03-14T10:00:00.000Z", model: "claude-opus-4-6", outputTokens: 200),
            assistantLine(requestId: "req_s1", timestamp: "2026-03-14T10:01:00.000Z", model: "claude-sonnet-4-6", outputTokens: 75)
        ])

        await parser.scan()

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let aggregates = parser.getTokens(from: 0, to: now + 3_600_000, model: "claude-sonnet-4-6")

        #expect(aggregates.count == 1)
        #expect(aggregates[0].model == "claude-sonnet-4-6")
        #expect(aggregates[0].outputTokens == 75)
    }

    // MARK: - AC-6: Health Indicator Tests

    @Test("Health reports correct success rate")
    func healthSuccessRate() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)
        let projectDir = tempDir.appendingPathComponent("projects/proj1")
        _ = try writeJSONLFile(at: projectDir, lines: [
            assistantLine(requestId: "req_1", outputTokens: 100),
            assistantLine(requestId: "req_2", outputTokens: 200),
            "malformed json line",
            "{bad: json}",
            assistantLine(requestId: "req_3", outputTokens: 300)
        ])

        await parser.scan()

        let health = parser.getHealth()
        // 4 non-empty lines processed (empty lines are filtered out)
        // 3 assistant lines successful, 1 malformed line ({bad: json} is also malformed)
        #expect(health.totalLinesProcessed == 5)
        #expect(health.successfulExtractions == 3)
        #expect(health.failedLines == 2)
        #expect(health.filesScanned == 1)
        #expect(health.isDegraded) // 3/5 = 60% — below 80% threshold
    }

    @Test("Health degradation threshold at 80%")
    func healthDegradationThreshold() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)
        let projectDir = tempDir.appendingPathComponent("projects/proj1")

        // Create 10 lines: 7 valid + 3 malformed = 70% success -> degraded
        var lines: [String] = []
        for i in 0..<7 {
            lines.append(assistantLine(requestId: "req_\(i)", outputTokens: 10))
        }
        lines.append("bad1")
        lines.append("bad2")
        lines.append("bad3")

        _ = try writeJSONLFile(at: projectDir, lines: lines)

        await parser.scan()

        let health = parser.getHealth()
        #expect(health.successRate == 70.0)
        #expect(health.isDegraded)
        #expect(health.degradationWarning != nil)
        #expect(health.degradationWarning!.contains("70%"))
    }

    @Test("Health not degraded when success rate is above 80%")
    func healthNotDegraded() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)
        let projectDir = tempDir.appendingPathComponent("projects/proj1")

        // 9 valid + 1 bad = 90%
        var lines: [String] = []
        for i in 0..<9 {
            lines.append(assistantLine(requestId: "req_\(i)", outputTokens: 10))
        }
        lines.append("bad")

        _ = try writeJSONLFile(at: projectDir, lines: lines)

        await parser.scan()

        let health = parser.getHealth()
        #expect(health.successRate == 90.0)
        #expect(!health.isDegraded)
        #expect(health.degradationWarning == nil)
    }

    // MARK: - AC-1: File Discovery Tests

    @Test("Discovers JSONL files in project directories")
    func discoversProjectFiles() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)

        // Create files in different project directories
        let proj1 = tempDir.appendingPathComponent("projects/proj1")
        let proj2 = tempDir.appendingPathComponent("projects/proj2")
        _ = try writeJSONLFile(at: proj1, name: "session1.jsonl", lines: [
            assistantLine(requestId: "req_p1", outputTokens: 100)
        ])
        _ = try writeJSONLFile(at: proj2, name: "session2.jsonl", lines: [
            assistantLine(requestId: "req_p2", outputTokens: 200)
        ])

        await parser.scan()

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let aggregates = parser.getTokens(from: 0, to: now + 3_600_000)

        #expect(aggregates.count == 1) // Same model
        #expect(aggregates[0].outputTokens == 300) // 100 + 200
        #expect(aggregates[0].messageCount == 2)
    }

    @Test("Discovers subagent JSONL files")
    func discoversSubagentFiles() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let parser = makeParser(tempDir: tempDir)

        // Main session file
        let proj = tempDir.appendingPathComponent("projects/proj1")
        _ = try writeJSONLFile(at: proj, name: "session.jsonl", lines: [
            assistantLine(requestId: "req_main", outputTokens: 100)
        ])

        // Subagent file
        let subagentDir = proj.appendingPathComponent("session-abc/subagents")
        _ = try writeJSONLFile(at: subagentDir, name: "agent-xyz.jsonl", lines: [
            assistantLine(requestId: "req_sub", outputTokens: 50)
        ])

        await parser.scan()

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let aggregates = parser.getTokens(from: 0, to: now + 3_600_000)

        #expect(aggregates.count == 1)
        #expect(aggregates[0].outputTokens == 150) // 100 + 50
        #expect(aggregates[0].messageCount == 2)
    }

    // MARK: - AC-8: Scan State Persistence Tests

    @Test("Scan state persists across parser instances")
    func scanStatePersistence() async throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let scanStatePath = tempDir.appendingPathComponent("scan-state.json")
        let projectsPath = tempDir.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsPath, withIntermediateDirectories: true)

        // First parser instance
        let parser1 = ClaudeCodeLogParser(
            scanStatePath: scanStatePath,
            claudeProjectsPath: projectsPath
        )

        let proj = projectsPath.appendingPathComponent("proj1")
        let filePath = try writeJSONLFile(at: proj, name: "session.jsonl", lines: [
            assistantLine(requestId: "req_1", timestamp: "2026-03-14T10:00:00.000Z", outputTokens: 100)
        ])

        await parser1.scan()

        // Append new data
        let newLine = assistantLine(requestId: "req_2", timestamp: "2026-03-14T11:00:00.000Z", outputTokens: 200) + "\n"
        let fh = try FileHandle(forWritingTo: filePath)
        fh.seekToEndOfFile()
        fh.write(newLine.data(using: .utf8)!)
        fh.closeFile()

        // Second parser instance (reads persisted state)
        let parser2 = ClaudeCodeLogParser(
            scanStatePath: scanStatePath,
            claudeProjectsPath: projectsPath
        )

        await parser2.scan()

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let aggregates = parser2.getTokens(from: 0, to: now + 3_600_000)

        // parser2 should only have the new record (req_2) since it resumed from offset
        #expect(aggregates.count == 1)
        #expect(aggregates[0].outputTokens == 200)
        #expect(aggregates[0].messageCount == 1)
    }
}
