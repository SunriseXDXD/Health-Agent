import Foundation
import UserNotifications

/// Lunch and dinner reminders plus the Sunday report reminder, all as local notifications.
enum ReminderManager {
    private static let center = UNUserNotificationCenter.current()
    private static let daysAhead = 14

    static func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Rebuilds the schedule. Meal reminders are scheduled one by one for the next two
    /// weeks, so a meal that is already logged gets no reminder that day.
    static func reschedule(loggedMeals: [MealSnapshot]) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix("meal-") || $0 == "weekly-report" }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard Prefs.defaults.bool(forKey: Prefs.remindersOn) else { return }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let logged = Set(loggedMeals.map { key(day: calendar.startOfDay(for: $0.date), meal: $0.mealType) })

        let slots: [(MealType, Int, String)] = [
            (.lunch, Prefs.defaults.integer(forKey: Prefs.lunchMinutes), "What did you have for lunch?"),
            (.dinner, Prefs.defaults.integer(forKey: Prefs.dinnerMinutes), "What did you have for dinner?"),
        ]

        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for (meal, minutes, title) in slots {
                guard !logged.contains(key(day: day, meal: meal.rawValue)),
                      let fireDate = calendar.date(byAdding: .minute, value: minutes, to: day),
                      fireDate > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = title
                content.body = "Snap a photo or type a line, and the calories and macros are worked out for you."
                content.sound = .default
                content.userInfo = ["kind": "meal", "meal": meal.rawValue]

                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: "meal-" + key(day: day, meal: meal.rawValue), content: content, trigger: trigger)
                try? await center.add(request)
            }
        }

        // Sunday report reminder (weekday 1 is Sunday in the Gregorian calendar).
        var sunday = DateComponents()
        sunday.weekday = 1
        sunday.hour = Prefs.defaults.integer(forKey: Prefs.reportHour)
        sunday.minute = 0
        let content = UNMutableNotificationContent()
        content.title = "Your weekly health summary is ready"
        content.body = "Open to review last week's numbers and send the report to your family."
        content.sound = .default
        content.userInfo = ["kind": "report"]
        let trigger = UNCalendarNotificationTrigger(dateMatching: sunday, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: "weekly-report", content: content, trigger: trigger))
    }

    private static func key(day: Date, meal: String) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-\(meal)"
    }
}
