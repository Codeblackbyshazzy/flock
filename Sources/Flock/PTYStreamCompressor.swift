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

/// Analyzes PTY output streams to track noise vs. signal and provide
/// compression analytics. Operates as a parallel layer — does NOT modify
/// the data flowing to SwiftTerm (which needs raw bytes for rendering).
///
/// Compression levels:
///   Level 1 — ANSI noise detection + progress bar collapsing
///   Level 2 — Boilerplate/header folding + semantic summarization
final class PTYStreamCompressor {

    private(set) var stats = CompressionStats()
    private(set) var foldedChunks: [FoldedChunk] = []

    /// Only start counting compression after user sends first keystroke.
    /// Shell startup ANSI noise is not meaningful compression.
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

    // Semantic fold threshold (~1,500 tokens ≈ 6,000 chars)
    private let semanticFoldCharThreshold = 6_000
    private let tailLinesToKeep = 20

    // Debounce stats updates
    private var statsDebounceTimer: Timer?
    private let statsDebounceInterval: TimeInterval = 0.5

    // MARK: - ANSI Patterns

    // Cursor movement, screen clear, scrolling — non-semantic ANSI
    private static let cursorMovePattern: NSRegularExpression = {
        // CSI sequences for cursor positioning, erasing, scrolling
        // \e[H \e[2J \e[K \e[nA \e[nB \e[nC \e[nD \e[nG \e[n;nH \e[?25h/l etc.
        let pattern = "\\x1B\\[(?:[0-9;]*[ABCDGHJKST]|\\?[0-9;]*[hl]|[0-9]*[LM]|=[0-9;]*[hl])"
        return try! NSRegularExpression(pattern: pattern)
    }()

    // Color/style ANSI — these ARE semantic (keep them)
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
            // npm style: [####    ] 45%
            "\\[#+\\s*\\]\\s*\\d+%",
            // pip/generic: |████░░░░| 67%
            "[|\\[][\u{2588}\u{2591}\u{2592}\u{2593}#=\\->\\s]+[|\\]]\\s*\\d+",
            // percentage with progress: 45% or 100%
            "^\\s*\\d{1,3}%\\s",
            // docker pull: abc123: Pull complete / Downloading [===>  ]
            "(?:Pull complete|Downloading|Extracting)\\s*\\[?[=>\\s]*\\]?",
            // npm install progress: added X packages
            "added \\d+ packages?",
            // spinner chars followed by text (⠋⠙⠹⠸ etc.)
            "^[\\s]*[\u{2800}-\u{28FF}]",
            // Cargo/Rust: Compiling foo v1.2.3 (repetitive)
            "^\\s*(Compiling|Downloading|Downloaded)\\s+\\S+\\s+v",
            // Generic progress: [n/m] or (n/m)
            "^\\s*[\\[(]\\d+/\\d+[\\])]",
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    // MARK: - Boilerplate Patterns

    private static let boilerplatePatterns: [NSRegularExpression] = {
        let patterns = [
            // Copyright/license headers
            "(?i)copyright\\s+(?:\\(c\\)|©)\\s*\\d{4}",
            "(?i)licensed under",
            "(?i)all rights reserved",
            // Common CLI banners
            "(?i)^\\s*version\\s+\\d+\\.\\d+",
            // Webpack/bundler summaries (repeated build info)
            "(?i)webpack compiled",
            "(?i)build completed",
            // Python/Node version headers
            "^Python \\d+\\.\\d+\\.\\d+",
            "^Node\\.js v\\d+",
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    // MARK: - Feed Data

    /// Analyze a chunk of PTY output data. Call this for every `dataReceived` event.
    func feed(_ data: ArraySlice<UInt8>) {
        guard isReady else { return }
        let byteCount = data.count
        stats.rawBytes += byteCount

        guard let text = String(bytes: data, encoding: .utf8) else {
            // Binary data — count as noise
            stats.noiseBytes += byteCount
            scheduleStatsUpdate()
            return
        }

        analyzeText(text, byteCount: byteCount)
        scheduleStatsUpdate()
    }

    /// Analyze a text string (convenience for when text is already decoded).
    func feedText(_ text: String) {
        guard isReady else { return }
        let byteCount = text.utf8.count
        stats.rawBytes += byteCount
        analyzeText(text, byteCount: byteCount)
        scheduleStatsUpdate()
    }

    func reset() {
        stats = CompressionStats()
        foldedChunks.removeAll()
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

    // MARK: - Analysis

    private func analyzeText(_ text: String, byteCount: Int) {
        // Level 1: Detect ANSI noise
        let noiseBytes = measureAnsiNoise(text)
        stats.noiseBytes += noiseBytes

        // Split into lines for line-level analysis
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            currentLine += line

            // Check if this is a complete line (text had newlines)
            if lines.count > 1 {
                analyzeLine(currentLine)
                lineBuffer.append(currentLine)
                currentLine = ""
            }
        }
        // Keep partial line in currentLine for next chunk

        // If the last component wasn't empty, it's a partial line — already in currentLine
        if text.hasSuffix("\n") || text.hasSuffix("\r") {
            if !currentLine.isEmpty {
                analyzeLine(currentLine)
                lineBuffer.append(currentLine)
                currentLine = ""
            }
        }

        // Semantic folding: check if buffered output exceeds threshold
        checkSemanticFoldThreshold()
    }

    private func analyzeLine(_ line: String) {
        let stripped = stripAllAnsi(line)

        // Safety: never count error lines as compressed
        if Self.containsErrorKeyword(stripped) {
            stats.errorLines += 1
            return
        }

        let lineBytes = line.utf8.count

        // Level 1: Progress bar detection
        if isProgressBar(stripped) {
            stats.progressBarBytes += lineBytes
            isInProgressBar = true
            progressBarByteAccum += lineBytes
            return
        } else if isInProgressBar {
            // Exiting a progress bar sequence
            isInProgressBar = false
            progressBarByteAccum = 0
        }

        // Level 2: Boilerplate detection
        if isBoilerplate(stripped) {
            stats.boilerplateBytes += lineBytes
            return
        }
    }

    // MARK: - ANSI Noise Measurement

    /// Measure bytes consumed by non-semantic ANSI sequences (cursor movement, screen clear).
    /// Color sequences are NOT counted as noise.
    private func measureAnsiNoise(_ text: String) -> Int {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        // Total ANSI bytes
        let allMatches = Self.allAnsiPattern.matches(in: text, range: range)
        var totalAnsi = 0
        for match in allMatches {
            totalAnsi += nsText.substring(with: match.range).utf8.count
        }

        // Subtract color/style ANSI (those are semantic)
        let colorMatches = Self.colorPattern.matches(in: text, range: range)
        var colorBytes = 0
        for match in colorMatches {
            colorBytes += nsText.substring(with: match.range).utf8.count
        }

        return max(0, totalAnsi - colorBytes)
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

        // Carriage return without newline often indicates progress overwrite
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

        // Generate a fold summary
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
        stats.semanticFoldBytes += max(0, totalBytes - tail.reduce(0) { $0 + $1.utf8.count })

        // Reset buffer
        lineBuffer.removeAll()
    }

    /// Generate a heuristic summary of buffered output lines.
    private func generateSummary(lines: [String]) -> String {
        let strippedLines = lines.map { stripAllAnsi($0) }
        let nonEmpty = strippedLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let lineCount = nonEmpty.count

        // Count error/warning lines
        let errorCount = nonEmpty.filter { Self.containsErrorKeyword($0) }.count

        // Detect common patterns
        var patterns: [String] = []

        // Check for test output
        let testLines = nonEmpty.filter {
            $0.contains("PASS") || $0.contains("FAIL") || $0.contains("test") || $0.contains("spec")
        }
        if testLines.count > 2 {
            let passing = testLines.filter { $0.contains("PASS") || $0.contains("pass") }.count
            let failing = testLines.filter { $0.contains("FAIL") || $0.contains("fail") }.count
            patterns.append("Tests: \(passing) passed, \(failing) failed")
        }

        // Check for install/download output
        let installLines = nonEmpty.filter {
            $0.contains("install") || $0.contains("added") || $0.contains("download")
        }
        if installLines.count > 2 {
            patterns.append("Package install/download output")
        }

        // Check for build output
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

    // MARK: - Helpers

    private func stripAllAnsi(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return Self.allAnsiPattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
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
