import Foundation

/// Reads Claude Code session JSONL files to compute usage (tokens + cost) for today.
/// Also fetches plan utilization from the Anthropic OAuth API.
/// Refreshes on a timer and posts a notification when data changes.
class UsageTracker {
    static let shared = UsageTracker()
    static let didUpdate = Notification.Name("UsageTrackerDidUpdate")

    struct Usage: Equatable {
        var totalTokens: Int = 0
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheReadTokens: Int = 0
        var cacheCreateTokens: Int = 0
        var costUSD: Double = 0
        var sessionCount: Int = 0
    }

    struct Limits: Equatable {
        var fiveHourPercent: Double = 0
        var sevenDayPercent: Double = 0
        var fiveHourResetsAt: String?
        var sevenDayResetsAt: String?
        var available: Bool = false
    }

    private(set) var today = Usage()
    private(set) var limits = Limits()
    private var timer: Timer?
    private var limitsTimer: Timer?
    private let queue = DispatchQueue(label: "com.flock.usage", qos: .utility)

    // Claude API pricing per million tokens (2025)
    private struct Pricing {
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheCreate: Double
    }

    private let pricing: [String: Pricing] = [
        "claude-opus-4-6":             Pricing(input: 15.0,  output: 75.0,  cacheRead: 1.875,  cacheCreate: 18.75),
        "claude-sonnet-4-5-20250929":  Pricing(input: 3.0,   output: 15.0,  cacheRead: 0.30,   cacheCreate: 3.75),
        "claude-sonnet-4-6":           Pricing(input: 3.0,   output: 15.0,  cacheRead: 0.30,   cacheCreate: 3.75),
        "claude-haiku-4-5-20251001":   Pricing(input: 0.80,  output: 4.0,   cacheRead: 0.08,   cacheCreate: 1.0),
    ]

    private let defaultPricing = Pricing(input: 3.0, output: 15.0, cacheRead: 0.30, cacheCreate: 3.75)

    private init() {}

    func start() {
        refresh()
        fetchLimits()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Limits are rate-limited, so poll less frequently (every 2 min)
        limitsTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.fetchLimits()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        limitsTimer?.invalidate()
        limitsTimer = nil
    }

    func refresh() {
        queue.async { [weak self] in
            self?.scan()
        }
    }

    // MARK: - Token/Cost Scanning

    private func scan() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let projectsDir = "\(home)/.claude/projects"

        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { return }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        var usage = Usage()

        for project in projectDirs {
            let projectPath = "\(projectsDir)/\(project)"
            guard let files = try? fm.contentsOfDirectory(atPath: projectPath) else { continue }

            for file in files where file.hasSuffix(".jsonl") {
                let filePath = "\(projectPath)/\(file)"
                guard let attrs = try? fm.attributesOfItem(atPath: filePath),
                      let modDate = attrs[.modificationDate] as? Date,
                      modDate >= todayStart else { continue }

                usage.sessionCount += 1
                parseSession(at: filePath, into: &usage, since: todayStart)
            }
        }

        let changed = usage != today
        DispatchQueue.main.async { [weak self] in
            self?.today = usage
            if changed {
                NotificationCenter.default.post(name: UsageTracker.didUpdate, object: nil)
            }
        }
    }

    private func parseSession(at path: String, into usage: inout Usage, since startOfDay: Date) {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return }

        for line in content.split(separator: "\n") {
            guard line.contains("\"type\":\"assistant\"") || line.contains("\"type\": \"assistant\"") else { continue }

            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let message = json["message"] as? [String: Any],
                  let usageDict = message["usage"] as? [String: Any] else { continue }

            // Check timestamp is today
            if let timestamp = json["timestamp"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: timestamp), date < startOfDay {
                    continue
                }
            }

            let input = usageDict["input_tokens"] as? Int ?? 0
            let output = usageDict["output_tokens"] as? Int ?? 0
            let cacheRead = usageDict["cache_read_input_tokens"] as? Int ?? 0
            let cacheCreate = usageDict["cache_creation_input_tokens"] as? Int ?? 0
            let model = message["model"] as? String ?? ""

            usage.inputTokens += input
            usage.outputTokens += output
            usage.cacheReadTokens += cacheRead
            usage.cacheCreateTokens += cacheCreate
            usage.totalTokens += input + output + cacheRead + cacheCreate

            let p = pricing[model] ?? defaultPricing
            usage.costUSD += Double(input) / 1_000_000 * p.input
                           + Double(output) / 1_000_000 * p.output
                           + Double(cacheRead) / 1_000_000 * p.cacheRead
                           + Double(cacheCreate) / 1_000_000 * p.cacheCreate
        }
    }

    // MARK: - Plan Limits (OAuth API)

    private func fetchLimits() {
        queue.async { [weak self] in
            guard let token = self?.getOAuthToken() else { return }
            self?.fetchUsageLimits(token: token)
        }
    }

    private func getOAuthToken() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Try credentials file first
        let credPath = "\(home)/.claude/.credentials.json"
        if let data = FileManager.default.contents(atPath: credPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String {
            return token
        }

        // Fall back to macOS Keychain
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let json = try? JSONSerialization.jsonObject(with: Data(str.utf8)) as? [String: Any],
               let oauth = json["claudeAiOauth"] as? [String: Any],
               let token = oauth["accessToken"] as? String {
                return token
            }
        } catch {}

        return nil
    }

    private func fetchUsageLimits(token: String) {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            var newLimits = Limits()
            newLimits.available = true

            if let fiveHour = json["five_hour"] as? [String: Any] {
                newLimits.fiveHourPercent = fiveHour["utilization"] as? Double ?? 0
                newLimits.fiveHourResetsAt = fiveHour["resets_at"] as? String
            }
            if let sevenDay = json["seven_day"] as? [String: Any] {
                newLimits.sevenDayPercent = sevenDay["utilization"] as? Double ?? 0
                newLimits.sevenDayResetsAt = sevenDay["resets_at"] as? String
            }

            let changed = newLimits != self?.limits
            DispatchQueue.main.async {
                self?.limits = newLimits
                if changed {
                    NotificationCenter.default.post(name: UsageTracker.didUpdate, object: nil)
                }
            }
        }
        task.resume()
    }

    // MARK: - Formatting

    var formattedCost: String {
        let cost = today.costUSD
        if cost < 0.01 { return "$0.00" }
        if cost < 10 { return String(format: "$%.2f", cost) }
        return String(format: "$%.0f", cost)
    }

    var formattedTokens: String {
        let t = today.totalTokens
        if t < 1000 { return "\(t)" }
        if t < 1_000_000 { return String(format: "%.1fK", Double(t) / 1000) }
        return String(format: "%.1fM", Double(t) / 1_000_000)
    }

    var formattedLimit: String? {
        guard limits.available else { return nil }
        let pct = limits.fiveHourPercent
        return "\(Int(pct))%"
    }

    var statusText: String {
        guard limits.available else { return "" }
        let pct = Int(limits.fiveHourPercent)
        if let resetStr = limits.fiveHourResetsAt, let resetTime = parseISO8601(resetStr) {
            let remaining = resetTime.timeIntervalSinceNow
            if remaining > 0 {
                let hours = Int(remaining) / 3600
                let minutes = (Int(remaining) % 3600) / 60
                let resetLabel = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
                return "\(pct)% used  ·  resets in \(resetLabel)"
            }
        }
        return "\(pct)% used"
    }

    private func parseISO8601(_ str: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: str) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: str)
    }
}
