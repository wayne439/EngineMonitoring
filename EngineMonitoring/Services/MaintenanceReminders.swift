import Foundation
import UserNotifications

/// Local reminders on the iPad for date-based maintenance items: one when an item becomes due soon and one on its due date.
/// Hour-based items (oil) are checked when logs are imported, since the iPad cannot know engine hours ahead.
enum MaintenanceReminders {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    @MainActor
    static func reschedule(store: MaintenanceStore, summaries: [FlightSummary]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: store.items.flatMap { ["mx-\($0.id)-soon", "mx-\($0.id)-due"] })
        let cal = Calendar.current
        for item in store.items {
            let s = store.status(item, summaries: summaries)
            guard let due = s.nextDate else { continue }
            func add(_ id: String, _ date: Date, _ body: String) {
                guard date > Date() else { return }
                var comps = cal.dateComponents([.year, .month, .day], from: date)
                comps.hour = 9
                let content = UNMutableNotificationContent()
                content.title = "N63KA: \(item.name)"
                content.body = body
                content.sound = .default
                center.add(UNNotificationRequest(identifier: id, content: content,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
            if let soon = cal.date(byAdding: .day, value: -item.warnDays, to: due) {
                add("mx-\(item.id)-soon", soon, "Due in \(item.warnDays) days. Open MAINTENANCE to record it.")
            }
            add("mx-\(item.id)-due", due, "Due today. Open MAINTENANCE to record the result.")
        }
    }
}
