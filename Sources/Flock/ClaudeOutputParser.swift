import Foundation

// MARK: - AgentState

enum AgentState: String {
    case idle
    case thinking
    case writing
    case running
    case reading
    case waiting
    case error

    var label: String {
        switch self {
        case .idle:     return ""
        case .thinking: return "Thinking…"
        case .writing:  return "Writing files"
        case .running:  return "Running command"
        case .reading:  return "Reading…"
        case .waiting:  return "Needs input"
        case .error:    return "Error"
        }
    }

    var symbol: String {
        switch self {
        case .idle:     return ""
        case .thinking: return "brain"
        case .writing:  return "doc.text"
        case .running:  return "terminal"
        case .reading:  return "doc.text.magnifyingglass"
        case .waiting:  return "exclamationmark.bubble"
        case .error:    return "xmark.circle"
        }
    }

    fileprivate var priority: Int {
        switch self {
        case .idle:     return 0
        case .thinking: return 1
        case .reading:  return 2
        case .running:  return 3
        case .writing:  return 4
        case .error:    return 5
        case .waiting:  return 6
        }
    }
}

// MARK: - ClaudeOutputParser

/// Detects agent state from raw terminal output.
///
/// TUI agents (Claude Code, Amp) redraw the entire screen each frame.
/// Each redraw contains the full visible content, so we check each
/// incoming chunk independently — no buffering needed.
/// We strip ANSI escapes, collapse whitespace, extract all "words",
/// then match against known tokens.
final class ClaudeOutputParser {

    private(set) var state: AgentState = .idle
    var onStateChange: ((AgentState) -> Void)?

    /// Fires when a structured action is detected (file read, write, search, etc.)
    var onActionDetected: ((JournalActionType, String, [String]) -> Void)?

    private var idleTimer: Timer?
    private let idleTimeout: TimeInterval = 4.0

    // Deduplication: track all recently emitted actions (not just the last one)
    private var recentActions: [String: Date] = [:]

    // MARK: - ANSI stripping

    private static let ansiPattern: NSRegularExpression = {
        let pattern = "\\x1B(?:\\[[0-9;?]*[A-Za-z]|\\][^\u{07}]*\u{07}|\\([A-Z]|[>=<])"
        return try! NSRegularExpression(pattern: pattern)
    }()

    private func stripAnsi(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return Self.ansiPattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    // MARK: - Feed

    func feed(_ text: String) {
        let clean = stripAnsi(text)
        guard clean.count > 5 else { return }  // skip tiny fragments

        // Collapse whitespace and extract a compact string to search
        let compact = clean.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                          .joined(separator: " ")
        guard !compact.isEmpty else { return }

        let detected = detectState(compact)

        // Only transition away from idle if we found something;
        // idle transitions happen via the timer
        if detected != .idle {
            resetIdleTimer()
            if detected != state {
                // Log journal action on state transitions only
                extractActionOnTransition(to: detected, text: compact)
                state = detected
                let s = detected
                DispatchQueue.main.async { [weak self] in
                    self?.onStateChange?(s)
                }
            }
        } else if state != .idle {
            // Still getting output but no patterns — reset idle timer
            resetIdleTimer()
        }
    }

    func reset() {
        idleTimer?.invalidate()
        idleTimer = nil
        state = .idle
    }

    // MARK: - Detection

    private func detectState(_ text: String) -> AgentState {
        // Priority: waiting > error > writing > running > reading > thinking

        // Waiting / permission
        if text.contains("wants to") || text.contains("Permission")
            || text.localizedCaseInsensitiveContains("(y/n)")
            || text.localizedCaseInsensitiveContains("Yes, allow")
            || text.localizedCaseInsensitiveContains("No, deny")
            || text.contains("Do you want") {
            return .waiting
        }

        // Error
        if text.contains("Error:") || text.contains("error:")
            || text.contains("FAILED") || text.contains("API error")
            || text.contains("hit your limit") || text.contains("Rate limit") {
            return .error
        }

        // Writing
        if text.contains("Write(") || text.contains("Edit(")
            || text.contains("write_file") || text.contains("edit_file")
            || text.contains("create_file")
            || text.contains("Writing") || text.contains("Wrote ") {
            return .writing
        }

        // Running commands
        if text.contains("Bash(") || text.contains("running for")
            || text.contains("Executing") {
            return .running
        }

        // Reading
        if text.contains("Reading") || text.contains("Searching")
            || text.contains("Searched") || text.contains("Queried")
            || text.contains("Grep(") || text.contains("Read(")
            || text.contains("glob(") || text.contains("finder(") {
            return .reading
        }

        // Thinking — braille spinners are the most reliable signal
        if containsBraille(text) {
            return .thinking
        }

        // Text-based thinking
        if text.contains("Thinking") || text.contains("Reasoning")
            || text.contains("Thought for") || text.contains("Resolving") {
            return .thinking
        }

        return .idle
    }

    /// Check for braille spinner characters (⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏)
    private func containsBraille(_ text: String) -> Bool {
        for c in text {
            let v = c.unicodeScalars.first?.value ?? 0
            if v >= 0x280B && v <= 0x283F {  // braille pattern range
                return true
            }
        }
        return false
    }

    // MARK: - Action Extraction (state-transition based)

    /// Only extract journal actions when the agent state actually transitions.
    /// This avoids false positives from conversation text that happens to
    /// contain tool names like "Bash(" or "Read(".
    private func extractActionOnTransition(to newState: AgentState, text: String) {
        let now = Date()

        var actionType: JournalActionType?
        var summary: String?
        var filePaths: [String] = []

        switch newState {
        case .reading:
            if let path = extractValidPath(from: text) {
                actionType = .fileRead
                summary = "Read \(shortenPath(path))"
                filePaths = [path]
            } else if let name = extractFileName(from: text) {
                actionType = .fileRead
                summary = "Read \(name)"
            } else if text.contains("Grep(") || text.contains("Searching") {
                actionType = .grep
                summary = "Searching"
            } else {
                actionType = .fileRead
                summary = "Reading"
            }
        case .writing:
            if let path = extractValidPath(from: text) {
                let isEdit = text.contains("Edit(") || text.contains("edit_file")
                actionType = isEdit ? .fileEdit : .fileWrite
                summary = "\(isEdit ? "Edit" : "Write") \(shortenPath(path))"
                filePaths = [path]
            } else if let name = extractFileName(from: text) {
                let isEdit = text.contains("Edit(") || text.contains("edit_file")
                actionType = isEdit ? .fileEdit : .fileWrite
                summary = "\(isEdit ? "Edit" : "Write") \(name)"
            } else {
                actionType = .fileWrite
                summary = "Writing"
            }
        case .running:
            actionType = .bash
            summary = "Running command"
        default:
            return
        }

        guard let type = actionType, let sum = summary else { return }

        // Dedup on state + summary (so different files pass through, same file is deduped)
        let dedupKey = "\(newState.rawValue):\(sum)"

        // Prune stale entries
        recentActions = recentActions.filter { now.timeIntervalSince($0.value) < 30.0 }

        if let lastTime = recentActions[dedupKey], now.timeIntervalSince(lastTime) < 30.0 {
            return
        }
        recentActions[dedupKey] = now

        let t = type
        let s = sum
        let f = filePaths
        DispatchQueue.main.async { [weak self] in
            self?.onActionDetected?(t, s, f)
        }
    }

    /// Scans text for a valid absolute file path.
    private func extractValidPath(from text: String) -> String? {
        // Look for paths starting with /Users/, /tmp/, etc.
        let validPrefixes = ["/Users/", "/tmp/", "/var/", "/home/", "/opt/", "/etc/", "/private/"]
        for prefix in validPrefixes {
            guard let prefixRange = text.range(of: prefix) else { continue }
            let pathStart = prefixRange.lowerBound
            let pathSubstring = text[pathStart...]
            let endIdx = pathSubstring.firstIndex(where: { $0 == " " || $0 == ")" || $0 == "," || $0 == "\"" || $0 == "\n" })
                ?? pathSubstring.endIndex
            let path = String(pathSubstring[..<endIdx])
            guard path.count > 5 else { continue }
            if path.contains("(") || path.contains("{") || path.contains(";") { continue }
            return path
        }
        // Also check ~/ paths
        if let tildeRange = text.range(of: "~/") {
            let pathSubstring = text[tildeRange.lowerBound...]
            let endIdx = pathSubstring.firstIndex(where: { $0 == " " || $0 == ")" || $0 == "," || $0 == "\"" || $0 == "\n" })
                ?? pathSubstring.endIndex
            let path = String(pathSubstring[..<endIdx])
            if path.count > 3 { return path }
        }
        return nil
    }

    /// Extracts a filename (e.g. "Foo.swift") from text near tool markers.
    /// Fallback when full path isn't available due to TUI truncation.
    private func extractFileName(from text: String) -> String? {
        // Look for common file patterns near Read(, Edit(, Write(
        let markers = ["Read(", "Edit(", "Write("]
        for marker in markers {
            guard let range = text.range(of: marker) else { continue }
            let rest = String(text[range.upperBound...].prefix(120))
            // Match something.ext pattern
            if let match = rest.range(of: #"[A-Za-z0-9_\-]+\.[a-zA-Z]{1,10}"#, options: .regularExpression) {
                let name = String(rest[match])
                // Skip obvious non-files
                if name.contains("..") || name.hasPrefix(".") { continue }
                return name
            }
        }
        return nil
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Idle Timer

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { [weak self] _ in
            guard let self = self, self.state != .idle else { return }
            self.state = .idle
            self.onStateChange?(.idle)
        }
    }
}
