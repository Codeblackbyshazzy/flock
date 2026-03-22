import Foundation

class CostTracker {
    static let shared = CostTracker()
    static let costDidUpdate = Notification.Name("FlockCostDidUpdate")

    // Per-pane costs keyed by ObjectIdentifier
    private var paneCosts: [ObjectIdentifier: Double] = [:]

    // Buffer partial lines per pane (terminal output comes in chunks)
    private var lineBuffers: [ObjectIdentifier: String] = [:]

    // ANSI escape sequence patterns to strip before scanning
    private static let ansiCSI = try! NSRegularExpression(pattern: "\\x1b\\[[0-9;]*[a-zA-Z]")
    private static let ansiOSC = try! NSRegularExpression(pattern: "\\x1b\\][^\\x07]*\\x07")

    // Dollar amount pattern: $0.08, $1.23, $12.3456, $0.1234
    private static let dollarPattern = try! NSRegularExpression(pattern: "\\$([0-9]+\\.?[0-9]*)")

    private static let bufferCap = 4096

    private init() {}

    // Process raw terminal output bytes for a pane
    func processOutput(_ data: ArraySlice<UInt8>, for pane: TerminalPane) {
        let id = ObjectIdentifier(pane)

        guard let chunk = String(bytes: data, encoding: .utf8) else { return }

        var buffer = lineBuffers[id] ?? ""
        buffer.append(chunk)

        // Cap the buffer to avoid unbounded memory growth
        if buffer.count > CostTracker.bufferCap {
            buffer = String(buffer.suffix(CostTracker.bufferCap))
        }

        // Split on newline or carriage return to find complete lines
        let separators = CharacterSet(charactersIn: "\n\r")
        var remaining = buffer
        var updated = false

        while let sepRange = remaining.rangeOfCharacter(from: separators) {
            let line = String(remaining[remaining.startIndex..<sepRange.lowerBound])
            remaining = String(remaining[sepRange.upperBound...])

            // Strip leading separators (handles \r\n)
            remaining = String(remaining.drop(while: { $0 == "\r" || $0 == "\n" }))

            if let cost = extractCost(from: line) {
                let current = paneCosts[id] ?? 0
                if cost > current {
                    paneCosts[id] = cost
                    updated = true
                }
            }
        }

        lineBuffers[id] = remaining

        if updated {
            NotificationCenter.default.post(name: CostTracker.costDidUpdate, object: nil)
        }
    }

    func cost(for pane: TerminalPane) -> Double {
        paneCosts[ObjectIdentifier(pane)] ?? 0
    }

    var totalCost: Double {
        paneCosts.values.reduce(0, +)
    }

    func resetCost(for pane: TerminalPane) {
        let id = ObjectIdentifier(pane)
        paneCosts.removeValue(forKey: id)
        lineBuffers.removeValue(forKey: id)
    }

    // MARK: - Private

    private func extractCost(from line: String) -> Double? {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        // Strip ANSI escape sequences
        var cleaned = CostTracker.ansiCSI.stringByReplacingMatches(in: line, range: fullRange, withTemplate: "")
        let nsClean = cleaned as NSString
        let cleanRange = NSRange(location: 0, length: nsClean.length)
        cleaned = CostTracker.ansiOSC.stringByReplacingMatches(in: cleaned, range: cleanRange, withTemplate: "")

        // Find all dollar amounts and return the highest in this line
        let nsFinal = cleaned as NSString
        let finalRange = NSRange(location: 0, length: nsFinal.length)
        let matches = CostTracker.dollarPattern.matches(in: cleaned, range: finalRange)

        var highest: Double?
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let valueRange = match.range(at: 1)
            let valueStr = nsFinal.substring(with: valueRange)
            if let value = Double(valueStr), value > 0 {
                if highest == nil || value > highest! {
                    highest = value
                }
            }
        }
        return highest
    }
}
