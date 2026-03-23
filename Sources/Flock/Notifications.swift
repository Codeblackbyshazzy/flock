import Foundation
import UserNotifications

enum FlockNotifications {
    static let focusPaneRequested = Notification.Name("FlockFocusPaneRequested")

    /// True when running inside a .app bundle (UNUserNotificationCenter requires this)
    private static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static func requestPermission() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func setup() {
        guard isAvailable else { return }
        let viewAction = UNNotificationAction(identifier: "VIEW", title: "View Pane", options: .foreground)

        let completionCategory = UNNotificationCategory(
            identifier: "PANE_COMPLETION",
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        let agentStateCategory = UNNotificationCategory(
            identifier: "AGENT_STATE",
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([completionCategory, agentStateCategory])
        center.delegate = FlockNotificationDelegate.shared
    }

    static func sendCompletion(paneName: String, paneIndex: Int, duration: TimeInterval?) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "Flock"
        content.subtitle = paneName
        content.body = formatDuration(duration)
        content.sound = .default
        content.categoryIdentifier = "PANE_COMPLETION"
        content.userInfo = ["paneIndex": paneIndex]

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func sendAgentStateChange(paneName: String, paneIndex: Int, state: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "Flock — \(paneName)"
        content.body = state
        content.sound = .default
        content.categoryIdentifier = "AGENT_STATE"
        content.userInfo = ["paneIndex": paneIndex]

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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

class FlockNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = FlockNotificationDelegate()

    private override init() {
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "VIEW" || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            let userInfo = response.notification.request.content.userInfo
            if let paneIndex = userInfo["paneIndex"] as? Int {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: FlockNotifications.focusPaneRequested,
                        object: nil,
                        userInfo: ["paneIndex": paneIndex]
                    )
                }
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}
