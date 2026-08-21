import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Requests permission only when needed, then posts an immediate native
    /// notification. The return value reports whether `add()` succeeded; the
    /// TimerManager field is intentionally named `Attempted`, so denied or
    /// failed delivery is not misrepresented as a successful notification.
    func sendCompletionNotification(timerID: UUID, timerName: String) async -> Bool {
        do {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else { return false }
            case .authorized, .provisional:
                break
            case .denied:
                return false
            @unknown default:
                return false
            }

            let content = UNMutableNotificationContent()
            content.title = "Timer 完成"
            content.body = "「\(timerName)」倒數已結束。"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "timer-completed-\(timerID.uuidString)",
                content: content,
                trigger: nil
            )
            try await center.add(request)
            return true
        } catch {
            // Notification permission and delivery are optional OS services.
            // The timer itself remains completed even when delivery fails.
            return false
        }
    }
}
