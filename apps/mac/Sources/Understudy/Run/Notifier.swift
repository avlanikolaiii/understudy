import AppKit
import UserNotifications

/// macOS notifications for runs: finished, blocked, or waiting for the person's OK. Clicking one
/// opens Understudy where it matters. Permission is asked the first time one is needed.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Opens a page of the main window: "skills" (the run) or "results" (its receipt).
    var open: (String) -> Void = { _ in }
    private var asked = false

    func post(title: String, body: String, opens page: String) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let send = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.userInfo = ["page": page]
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        guard !asked else { return send() }
        asked = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { DispatchQueue.main.async(execute: send) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let page = response.notification.request.content.userInfo["page"] as? String ?? "results"
        DispatchQueue.main.async { self.open(page) }
        completionHandler()
    }

    /// Shows them even while Understudy is in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
