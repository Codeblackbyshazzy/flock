import Foundation

enum FlockNotifications {
    static let focusPaneRequested = Notification.Name("FlockFocusPaneRequested")

    static func requestPermission() {
        // no-op: ad-hoc signed apps can't use UNUserNotificationCenter
    }

    static func setup() {
        // no-op: ad-hoc signed apps can't use UNUserNotificationCenter
    }

    static func sendCompletion(paneName: String, paneIndex: Int, duration: TimeInterval?) {
        let body = formatDuration(duration)
        sendOsascript(title: "Flock", message: "\(paneName) — \(body)")
    }

    static func sendAgentStateChange(paneName: String, paneIndex: Int, state: String) {
        sendOsascript(title: "Flock", message: "\(paneName) — \(state)")
    }

    private static func sendOsascript(title: String, message: String) {
        let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escaped)\" with title \"\(title)\""
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
    }

    private static func formatDuration(_ duration: TimeInterval?) -> String {
        guard let duration else { return "Completed" }
        let seconds = Int(duration)
        if seconds < 60 {
            return "Completed in \(seconds)s"
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if remainder == 0 {
            return "Completed in \(minutes)m"
        }
        return "Completed in \(minutes)m \(remainder)s"
    }
}
