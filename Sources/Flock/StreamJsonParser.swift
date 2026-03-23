import Foundation

// MARK: - StreamJsonEvent

enum StreamJsonEvent {
    case init_(sessionId: String, model: String)
    case thinking(text: String)
    case toolUse(name: String, input: [String: Any])
    case toolResult(content: String)
    case text(String)
    case result(isError: Bool, text: String?, costUsd: Double?)
}

// MARK: - StreamJsonParser

/// Parses Claude Code's `stream-json` output format.
///
/// Feed raw data from the process stdout into `feed(_:handler:)`.
/// Each newline-delimited JSON object is parsed and emitted as a
/// `StreamJsonEvent`. The parser buffers partial lines between calls.
final class StreamJsonParser {

    private var buffer = Data()
    private var lastResult: (isError: Bool, text: String?, costUsd: Double?)?

    /// Accumulates incoming data, splits on newlines, and emits events.
    func feed(_ data: Data, handler: (StreamJsonEvent) -> Void) {
        buffer.append(data)

        // Process all complete lines (newline-delimited JSON)
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer = Data(buffer[buffer.index(after: newlineIndex)...])

            guard !lineData.isEmpty else { continue }

            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }

            for event in parseEvent(type: type, json: json) {
                if case let .result(isError, text, costUsd) = event {
                    lastResult = (isError, text, costUsd)
                }
                handler(event)
            }
        }
    }

    /// Returns the last result event received, if any.
    func finalResult() -> (isError: Bool, text: String?, costUsd: Double?)? {
        return lastResult
    }

    // MARK: - Private

    /// Parses a single JSON object into zero or more events.
    private func parseEvent(type: String, json: [String: Any]) -> [StreamJsonEvent] {
        switch type {
        case "system":
            return parseSystemEvent(json)
        case "assistant":
            return parseAssistantEvent(json)
        case "result":
            return parseResultEvent(json)
        default:
            // Ignore unknown types (e.g. rate_limit_event)
            return []
        }
    }

    private func parseSystemEvent(_ json: [String: Any]) -> [StreamJsonEvent] {
        guard json["subtype"] as? String == "init" else { return [] }

        let sessionId = json["session_id"] as? String ?? ""
        let model = json["model"] as? String ?? ""
        return [.init_(sessionId: sessionId, model: model)]
    }

    private func parseAssistantEvent(_ json: [String: Any]) -> [StreamJsonEvent] {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return []
        }

        var events: [StreamJsonEvent] = []

        for block in content {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "text":
                if let text = block["text"] as? String {
                    events.append(.text(text))
                }

            case "thinking":
                if let thinking = block["thinking"] as? String {
                    events.append(.thinking(text: thinking))
                }

            case "tool_use":
                if let name = block["name"] as? String {
                    let input = block["input"] as? [String: Any] ?? [:]
                    events.append(.toolUse(name: name, input: input))
                }

            case "tool_result":
                if let resultContent = block["content"] as? String {
                    events.append(.toolResult(content: resultContent))
                }

            default:
                break
            }
        }

        return events
    }

    private func parseResultEvent(_ json: [String: Any]) -> [StreamJsonEvent] {
        let isError = json["is_error"] as? Bool ?? false
        let text = json["result"] as? String
        let costUsd = json["total_cost_usd"] as? Double
        return [.result(isError: isError, text: text, costUsd: costUsd)]
    }
}
