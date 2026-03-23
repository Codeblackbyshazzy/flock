import Foundation

// MARK: - Compression Stats

struct CompressionStats {
    var rawBytes: Int = 0
    var noiseBytes: Int = 0          // ANSI control sequences, cursor movement
    var progressBarBytes: Int = 0     // Collapsed progress bars
    var boilerplateBytes: Int = 0     // Headers, copyright notices
    var semanticFoldBytes: Int = 0    // Large outputs that were summarized
    var errorLines: Int = 0           // Lines preserved (never compressed)

    var compressedBytes: Int {
        noiseBytes + progressBarBytes + boilerplateBytes + semanticFoldBytes
    }

    var compressionRatio: Double {
        guard rawBytes > 0 else { return 0 }
        return Double(compressedBytes) / Double(rawBytes)
    }

    var percentSaved: Int {
        Int(compressionRatio * 100)
    }

    // Token estimation (~4 chars per token on average for code/terminal output)
    private static let charsPerToken: Double = 4.0

    var tokensTotal: Int {
        Int(Double(rawBytes) / Self.charsPerToken)
    }

    var tokensSaved: Int {
        Int(Double(compressedBytes) / Self.charsPerToken)
    }

    var tokensDelivered: Int {
        tokensTotal - tokensSaved
    }

    // Per-category token breakdown
    var noiseTokens: Int { Int(Double(noiseBytes) / Self.charsPerToken) }
    var progressBarTokens: Int { Int(Double(progressBarBytes) / Self.charsPerToken) }
    var boilerplateTokens: Int { Int(Double(boilerplateBytes) / Self.charsPerToken) }
    var semanticFoldTokens: Int { Int(Double(semanticFoldBytes) / Self.charsPerToken) }

    // Aggregate multiple stats (for session-wide totals)
    static func aggregate(_ all: [CompressionStats]) -> CompressionStats {
        var result = CompressionStats()
        for s in all {
            result.rawBytes += s.rawBytes
            result.noiseBytes += s.noiseBytes
            result.progressBarBytes += s.progressBarBytes
            result.boilerplateBytes += s.boilerplateBytes
            result.semanticFoldBytes += s.semanticFoldBytes
            result.errorLines += s.errorLines
        }
        return result
    }
}

// MARK: - Folded Chunk

struct FoldedChunk {
    let id: Int
    let summary: String
    let originalByteCount: Int
    let tailLines: [String]    // Last N lines preserved
    let timestamp: Date
}

// MARK: - PTYStreamCompressor

/// Compresses PTY output streams by stripping non-semantic ANSI, collapsing
/// progress bars, removing boilerplate, and folding large outputs.
///
/// Two outputs:
///   1. Raw data passes through to SwiftTerm unchanged (for rendering)
///   2. Compressed output stored in `compressedLines` (clean context for LLMs)
///
/// Stats track real compression: raw input bytes vs compressed output bytes.
final class PTYStreamCompressor {

    private(set) var stats = CompressionStats()
    private(set) var foldedChunks: [FoldedChunk] = []

    /// Compressed output -- clean lines with noise stripped.
    /// This is the actual compressed context, usable by LLMs.
    private(set) var compressedLines: [String] = []
    private let maxCompressedLines = 5_000

    /// Only start counting after user interaction.
    /// 5s grace period blocks terminal negotiation + shell/Claude startup.
    private(set) var isReady = false
    private let createdAt = Date()
    private let startupGrace: TimeInterval = 5.0

    func markReady() {
        guard !isReady, Date().timeIntervalSince(createdAt) > startupGrace else { return }
        isReady = true
    }

    var onStatsUpdate: ((CompressionStats) -> Void)?

    // Buffering for command output detection
    private var lineBuffer: [String] = []
    private var currentLine = ""
    private var outputStartTime: Date?
    private var chunkIdCounter = 0

    // Progress bar state
    private var isInProgressBar = false
    private var progressBarByteAccum = 0

    // Semantic fold threshold (~1,500 tokens = 6,000 chars)
    private let semanticFoldCharThreshold = 6_000
    private let tailLinesToKeep = 20

    // Debounce stats updates
    private var statsDebounceTimer: Timer?
    private let statsDebounceInterval: TimeInterval = 0.5

    // MARK: - ANSI Patterns

    // Cursor movement, screen clear, scrolling -- non-semantic ANSI
    private static let cursorMovePattern: NSRegularExpression = {
        let pattern = "\\x1B\\[(?:[0-9;]*[ABCDGHJKST]|\\?[0-9;]*[hl]|[0-9]*[LM]|=[0-9;]*[hl])"
        return try! NSRegularExpression(pattern: pattern)
    }()

    // Color/style ANSI -- these ARE semantic (keep them)
    private static let colorPattern: NSRegularExpression = {
        let pattern = "\\x1B\\[[0-9;]*m"
        return try! NSRegularExpression(pattern: pattern)
    }()

    // All ANSI escapes
    private static let allAnsiPattern: NSRegularExpression = {
        let pattern = "\\x1B(?:\\[[0-9;?]*[A-Za-z]|\\][^\u{07}]*\u{07}|\\([A-Z]|[>=<])"
        return try! NSRegularExpression(pattern: pattern)
    }()

    // MARK: - Error Safety Keywords (never compress lines containing these)

    private static let errorKeywords: [String] = [
        "Error", "error:", "ERROR",
        "Fail", "fail:", "FAIL", "FAILED",
        "Exception", "exception:",
        "Reject", "reject:", "REJECTED",
        "panic:", "PANIC",
        "fatal:", "FATAL",
        "warning:", "Warning:", "WARN",
    ]

    // MARK: - Progress Bar Patterns

    private static let progressPatterns: [NSRegularExpression] = {
        let patterns = [
            "\\[#+\\s*\\]\\s*\\d+%",
            "[|\\[][\u{2588}\u{2591}\u{2592}\u{2593}#=\\->\\s]+[|\\]]\\s*\\d+",
            "^\\s*\\d{1,3}%\\s",
            "(?:Pull complete|Downloading|Extracting)\\s*\\[?[=>\\s]*\\]?",
            "added \\d+ packages?",
            "^[\\s]*[\u{2800}-\u{28FF}]",
            "^\\s*(Compiling|Downloading|Downloaded)\\s+\\S+\\s+v",
            "^\\s*[\\[(]\\d+/\\d+[\\])]",
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    // MARK: - Boilerplate Patterns

    private static let boilerplatePatterns: [NSRegularExpression] = {
        let patterns = [
            "(?i)copyright\\s+(?:\\(c\\)|\\u{00A9})\\s*\\d{4}",
            "(?i)licensed under",
            "(?i)all rights reserved",
            "(?i)^\\s*version\\s+\\d+\\.\\d+",
            "(?i)webpack compiled",
            "(?i)build completed",
            "^Python \\d+\\.\\d+\\.\\d+",
            "^Node\\.js v\\d+",
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    // MARK: - Feed Data

    /// Analyze and compress a chunk of PTY output data.
    func feed(_ data: ArraySlice<UInt8>) {
        guard isReady else { return }
        let byteCount = data.count
        stats.rawBytes += byteCount

        guard let text = String(bytes: data, encoding: .utf8) else {
            stats.noiseBytes += byteCount
            scheduleStatsUpdate()
            return
        }

        analyzeAndCompress(text, byteCount: byteCount)
        scheduleStatsUpdate()
    }

    /// Analyze and compress a text string.
    func feedText(_ text: String) {
        guard isReady else { return }
        let byteCount = text.utf8.count
        stats.rawBytes += byteCount
        analyzeAndCompress(text, byteCount: byteCount)
        scheduleStatsUpdate()
    }

    /// Get the compressed context as a single string.
    var compressedContext: String {
        compressedLines.joined(separator: "\n")
    }

    func reset() {
        stats = CompressionStats()
        foldedChunks.removeAll()
        compressedLines.removeAll()
        lineBuffer.removeAll()
        currentLine = ""
        outputStartTime = nil
        isReady = false
        isInProgressBar = false
        progressBarByteAccum = 0
        chunkIdCounter = 0
        statsDebounceTimer?.invalidate()
        statsDebounceTimer = nil
    }

    // MARK: - Analysis + Compression

    private func analyzeAndCompress(_ text: String, byteCount: Int) {
        // Count ANSI noise bytes
        let noiseBytes = measureAnsiNoise(text)
        stats.noiseBytes += noiseBytes

        // Split into lines for line-level analysis + compression
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            currentLine += line

            if lines.count > 1 {
                let action = classifyLine(currentLine)
                applyLineAction(currentLine, action: action)
                lineBuffer.append(currentLine)
                currentLine = ""
            }
        }

        if text.hasSuffix("\n") || text.hasSuffix("\r") {
            if !currentLine.isEmpty {
                let action = classifyLine(currentLine)
                applyLineAction(currentLine, action: action)
                lineBuffer.append(currentLine)
                currentLine = ""
            }
        }

        checkSemanticFoldThreshold()
        trimCompressedBuffer()
    }

    // MARK: - Line Classification

    private enum LineAction {
        case keep           // Add cleaned line to compressed output
        case keepError      // Error line -- always preserve verbatim
        case dropProgress   // Progress bar -- drop from compressed output
        case dropBoilerplate // Boilerplate -- drop from compressed output
    }

    private func classifyLine(_ line: String) -> LineAction {
        let stripped = stripAllAnsi(line)

        if Self.containsErrorKeyword(stripped) {
            return .keepError
        }
        if isProgressBar(stripped) {
            return .dropProgress
        }
        if isBoilerplate(stripped) {
            return .dropBoilerplate
        }
        return .keep
    }

    private func applyLineAction(_ line: String, action: LineAction) {
        let lineBytes = line.utf8.count

        switch action {
        case .keepError:
            stats.errorLines += 1
            // Keep error lines in compressed output with ANSI stripped
            let clean = stripAllAnsi(line).trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty {
                compressedLines.append(clean)
            }

        case .keep:
            if isInProgressBar {
                isInProgressBar = false
                progressBarByteAccum = 0
            }
            // Strip non-semantic ANSI, keep the content
            let clean = stripNonSemanticAnsi(line).trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty {
                compressedLines.append(clean)
            }

        case .dropProgress:
            stats.progressBarBytes += lineBytes
            isInProgressBar = true
            progressBarByteAccum += lineBytes
            // Dropped from compressed output

        case .dropBoilerplate:
            stats.boilerplateBytes += lineBytes
            // Dropped from compressed output
        }
    }

    // MARK: - ANSI Noise Measurement

    private func measureAnsiNoise(_ text: String) -> Int {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        let allMatches = Self.allAnsiPattern.matches(in: text, range: range)
        var totalAnsi = 0
        for match in allMatches {
            totalAnsi += nsText.substring(with: match.range).utf8.count
        }

        let colorMatches = Self.colorPattern.matches(in: text, range: range)
        var colorBytes = 0
        for match in colorMatches {
            colorBytes += nsText.substring(with: match.range).utf8.count
        }

        return max(0, totalAnsi - colorBytes)
    }

    // MARK: - ANSI Stripping

    /// Strip ALL ANSI escapes (for error lines that need full cleaning).
    private func stripAllAnsi(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return Self.allAnsiPattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    /// Strip only non-semantic ANSI (cursor movement, screen control).
    /// Keeps color/style codes since those carry meaning.
    private func stripNonSemanticAnsi(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return Self.cursorMovePattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    // MARK: - Progress Bar Detection

    private func isProgressBar(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        let nsLine = trimmed as NSString
        let range = NSRange(location: 0, length: nsLine.length)

        for pattern in Self.progressPatterns {
            if pattern.firstMatch(in: trimmed, range: range) != nil {
                return true
            }
        }

        if line.contains("\r") && !line.contains("\n") && line.count > 5 {
            return true
        }

        return false
    }

    // MARK: - Boilerplate Detection

    private func isBoilerplate(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 10 else { return false }

        let nsLine = trimmed as NSString
        let range = NSRange(location: 0, length: nsLine.length)

        for pattern in Self.boilerplatePatterns {
            if pattern.firstMatch(in: trimmed, range: range) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Error Safety

    private static func containsErrorKeyword(_ line: String) -> Bool {
        for keyword in errorKeywords {
            if line.contains(keyword) { return true }
        }
        return false
    }

    // MARK: - Semantic Folding

    private func checkSemanticFoldThreshold() {
        let totalChars = lineBuffer.reduce(0) { $0 + $1.count }
        guard totalChars >= semanticFoldCharThreshold else { return }

        let totalBytes = lineBuffer.reduce(0) { $0 + $1.utf8.count }
        let summary = generateSummary(lines: lineBuffer)
        let tail = Array(lineBuffer.suffix(tailLinesToKeep))

        chunkIdCounter += 1
        let chunk = FoldedChunk(
            id: chunkIdCounter,
            summary: summary,
            originalByteCount: totalBytes,
            tailLines: tail,
            timestamp: Date()
        )
        foldedChunks.append(chunk)

        let tailBytes = tail.reduce(0) { $0 + $1.utf8.count }
        stats.semanticFoldBytes += max(0, totalBytes - tailBytes)

        // Replace the big block in compressed output with summary + tail
        let foldedCount = lineBuffer.count - tailLinesToKeep
        if foldedCount > 0, compressedLines.count >= foldedCount {
            compressedLines.removeLast(min(foldedCount, compressedLines.count))
        }
        compressedLines.append(summary)
        for line in tail {
            compressedLines.append(stripAllAnsi(line))
        }

        lineBuffer.removeAll()
    }

    private func generateSummary(lines: [String]) -> String {
        let strippedLines = lines.map { stripAllAnsi($0) }
        let nonEmpty = strippedLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let lineCount = nonEmpty.count

        let errorCount = nonEmpty.filter { Self.containsErrorKeyword($0) }.count

        var patterns: [String] = []

        let testLines = nonEmpty.filter {
            $0.contains("PASS") || $0.contains("FAIL") || $0.contains("test") || $0.contains("spec")
        }
        if testLines.count > 2 {
            let passing = testLines.filter { $0.contains("PASS") || $0.contains("pass") }.count
            let failing = testLines.filter { $0.contains("FAIL") || $0.contains("fail") }.count
            patterns.append("Tests: \(passing) passed, \(failing) failed")
        }

        let installLines = nonEmpty.filter {
            $0.contains("install") || $0.contains("added") || $0.contains("download")
        }
        if installLines.count > 2 {
            patterns.append("Package install/download output")
        }

        let buildLines = nonEmpty.filter {
            $0.contains("Compiling") || $0.contains("Building") || $0.contains("Linking")
        }
        if buildLines.count > 2 {
            patterns.append("Build output (\(buildLines.count) steps)")
        }

        let patternsStr = patterns.isEmpty ? "" : " | " + patterns.joined(separator: ", ")
        var summary = "[Folded: \(lineCount) lines, ~\(lineCount * 4) tokens"
        if errorCount > 0 {
            summary += ", \(errorCount) errors preserved"
        }
        summary += patternsStr + "]"
        return summary
    }

    // MARK: - Buffer Management

    private func trimCompressedBuffer() {
        if compressedLines.count > maxCompressedLines {
            compressedLines.removeFirst(compressedLines.count - maxCompressedLines)
        }
    }

    private func scheduleStatsUpdate() {
        guard statsDebounceTimer == nil else { return }
        statsDebounceTimer = Timer.scheduledTimer(withTimeInterval: statsDebounceInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.statsDebounceTimer = nil
            self.onStatsUpdate?(self.stats)
        }
    }
}
