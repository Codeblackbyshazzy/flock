import Foundation
import UserNotifications

enum FlockNotifications {
    static let focusPaneRequested = Notification.Name("FlockFocusPaneRequested")

    private static var useNative = false
    /// Debounce: track last notification per pane to suppress duplicates
    private static var lastNotification: [String: (message: String, time: Date)] = [:]
    private static let debounceInterval: TimeInterval = 5.0

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { useNative = granted }
        }
    }

    static func setup() {
        // Check if we already have permission (e.g. from a previous launch)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                if settings.authorizationStatus == .authorized {
                    useNative = true
                } else if settings.authorizationStatus == .notDetermined {
                    // Auto-request on first launch
                    requestPermission()
                }
            }
        }
    }

    static func sendCompletion(paneName: String, paneIndex: Int, duration: TimeInterval?) {
        let body = formatDuration(duration)
        send(title: "Flock", body: "\(paneName) — \(body)", key: "pane-\(paneIndex)")
    }

    static func sendAgentStateChange(paneName: String, paneIndex: Int, state: String) {
        send(title: "Flock", body: "\(paneName) — \(state)", key: "pane-\(paneIndex)")
    }

    private static func send(title: String, body: String, key: String) {
        // Debounce: skip if same message for same pane within interval
        let now = Date()
        if let last = lastNotification[key],
           last.message == body,
           now.timeIntervalSince(last.time) < debounceInterval {
            return
        }
        lastNotification[key] = (message: body, time: now)

        if useNative {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        } else {
            sendOsascript(title: title, message: body)
        }
    }

    private static func escapeAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func sendOsascript(title: String, message: String) {
        let escapedMsg = escapeAppleScript(message)
        let escapedTitle = escapeAppleScript(title)
        let script = "display notification \"\(escapedMsg)\" with title \"\(escapedTitle)\""
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
