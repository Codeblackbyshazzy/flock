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

    private var idleTimer: Timer?
    private let idleTimeout: TimeInterval = 4.0

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
        if hasWord(text, "Reading") || hasWord(text, "Searching")
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
        if hasWord(text, "Thinking") || hasWord(text, "Reasoning")
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

    /// Check for a whole word (not substring of another word)
    private func hasWord(_ text: String, _ word: String) -> Bool {
        guard let range = text.range(of: word) else { return false }
        // Check character after the match isn't a lowercase letter (avoids false positives)
        if range.upperBound < text.endIndex {
            let next = text[range.upperBound]
            if next.isLowercase { return false }
        }
        return true
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
