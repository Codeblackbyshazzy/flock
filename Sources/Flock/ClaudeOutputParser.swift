import Foundation

// MARK: - AgentState

enum AgentState: String {
    case idle
    case thinking
    case writing
    case running
    case waiting
    case error

    var label: String {
        switch self {
        case .idle:     return ""
        case .thinking: return "Thinking..."
        case .writing:  return "Writing files"
        case .running:  return "Running command"
        case .waiting:  return "Waiting for input"
        case .error:    return "Error"
        }
    }

    var symbol: String {
        switch self {
        case .idle:     return ""
        case .thinking: return "brain"
        case .writing:  return "doc.text"
        case .running:  return "terminal"
        case .waiting:  return "exclamationmark.bubble"
        case .error:    return "xmark.circle"
        }
    }

    /// Priority for conflict resolution (higher wins).
    fileprivate var priority: Int {
        switch self {
        case .idle:     return 0
        case .thinking: return 1
        case .running:  return 2
        case .writing:  return 3
        case .error:    return 4
        case .waiting:  return 5
        }
    }
}

// MARK: - ClaudeOutputParser

/// Parses raw Claude CLI terminal output (with ANSI escapes) to detect
/// the current agent state based on text patterns.
final class ClaudeOutputParser {

    private(set) var state: AgentState = .idle
    var onStateChange: ((AgentState) -> Void)?

    private var idleTimer: Timer?
    private let idleTimeout: TimeInterval = 3.0

    // MARK: - Regex

    /// Matches ANSI escape sequences: CSI sequences, OSC sequences, and simple escapes.
    private static let ansiPattern: NSRegularExpression = {
        // CSI: \x1B[ ... letter
        // OSC: \x1B] ... BEL/ST
        // Simple two-byte escapes: \x1B followed by single char
        let pattern = "\\x1B(?:\\[[0-9;]*[A-Za-z]|\\][^\u{07}]*\u{07}|\\([A-Z]|[>=<])"
        return try! NSRegularExpression(pattern: pattern)
    }()

    // MARK: - Feed

    /// Strips ANSI escapes from `text`, then pattern-matches to detect state changes.
    func feed(_ text: String) {
        let clean = stripAnsi(text)
        let detected = detectState(clean)

        resetIdleTimer()

        guard detected != state else { return }
        state = detected
        let newState = detected
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(newState)
        }
    }

    // MARK: - Reset

    func reset() {
        idleTimer?.invalidate()
        idleTimer = nil
        state = .idle
    }

    // MARK: - Private

    private func stripAnsi(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return Self.ansiPattern.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: ""
        )
    }

    private func detectState(_ text: String) -> AgentState {
        let lines = text.components(separatedBy: .newlines)
        var best: AgentState = .idle

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let candidate = classifyLine(trimmed)
            if candidate.priority > best.priority {
                best = candidate
            }

            // Short-circuit at max priority
            if best == .waiting { return best }
        }

        return best
    }

    private func classifyLine(_ line: String) -> AgentState {
        let lower = line.lowercased()

        // Waiting patterns (highest priority)
        if lower.contains("do you want to")
            || lower.contains("allow")
            || lower.contains("y/n")
            || lower.contains("yes/no")
            || lower.contains("(y/n)") {
            return .waiting
        }

        // Error patterns
        if lower.contains("error:")
            || lower.contains("failed")
            || lower.hasPrefix("error") {
            return .error
        }

        // Writing patterns
        if lower.hasPrefix("write file:")
            || lower.hasPrefix("edit file:")
            || lower.hasPrefix("created")
            || lineContainsFilePath(line) {
            return .writing
        }

        // Running patterns
        if lower.hasPrefix("running:")
            || lower.hasPrefix("executing:")
            || line.hasPrefix("$ ")
            || line.hasPrefix("> ") {
            return .running
        }

        // Thinking patterns
        if lower.contains("thinking")
            || lower.contains("⠋") || lower.contains("⠙")
            || lower.contains("⠹") || lower.contains("⠸")
            || lower.contains("⠼") || lower.contains("⠴")
            || lower.contains("⠦") || lower.contains("⠧")
            || lower.contains("⠇") || lower.contains("⠏") {
            return .thinking
        }

        return .idle
    }

    /// Detects lines that look like file paths with common extensions.
    private func lineContainsFilePath(_ line: String) -> Bool {
        let extensions = [
            ".swift", ".ts", ".tsx", ".js", ".jsx", ".py", ".rs",
            ".go", ".json", ".yaml", ".yml", ".toml", ".md",
            ".html", ".css", ".scss", ".txt", ".sh", ".sql"
        ]
        for ext in extensions {
            if line.contains(ext) { return true }
        }
        return false
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
