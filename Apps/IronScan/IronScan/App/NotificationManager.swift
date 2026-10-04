import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private static let dailyReminderIdentifier = "daily_ironscan_reminder"
    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {}

    func requestNotificationPermission() async -> Bool {
        do {
            return try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleDailyScanReminder(hour: Int = 9, minute: Int = 0) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.dailyReminderIdentifier])

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let content = UNMutableNotificationContent()
        content.title = "Time for your daily IronScan! 🩸"
        content.body = "Take a quick scan today to keep your hemoglobin tracking accurate."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.dailyReminderIdentifier,
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request)
    }
}
