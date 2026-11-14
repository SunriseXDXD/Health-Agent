import SwiftUI
import SwiftData
import UserNotifications

/// Which tab is showing, and whether a reminder asked for the meal logger to open.
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    enum Tab: Hashable { case today, meals, trends, report, settings }

    @Published var tab: Tab = .today
    @Published var mealToLog: MealType?
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Prefs.registerDefaults()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Show reminders even when the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Tapping a reminder opens the meal logger or the weekly report.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let kind = info["kind"] as? String
        let meal = info["meal"] as? String
        DispatchQueue.main.async {
            if kind == "meal" {
                AppRouter.shared.tab = .today
                AppRouter.shared.mealToLog = MealType(rawValue: meal ?? "") ?? .lunch
            } else if kind == "report" {
                AppRouter.shared.tab = .report
            }
        }
        completionHandler()
    }
}

@main
struct HealthAgentApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = AppRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
        }
        .modelContainer(for: MealEntry.self)
    }
}

struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @Query private var meals: [MealEntry]

    var body: some View {
        TabView(selection: $router.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "heart.text.square") }
                .tag(AppRouter.Tab.today)
            MealsView()
                .tabItem { Label("Meals", systemImage: "fork.knife") }
                .tag(AppRouter.Tab.meals)
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                .tag(AppRouter.Tab.trends)
            ReportView()
                .tabItem { Label("Weekly", systemImage: "doc.text") }
                .tag(AppRouter.Tab.report)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppRouter.Tab.settings)
        }
        .sheet(item: $router.mealToLog) { mealType in
            QuickLogView(mealType: mealType)
        }
        .task {
            await HealthKitManager.shared.requestAuthorization()
            await ReminderManager.requestPermission()
            await ReminderManager.reschedule(loggedMeals: meals.map(\.snapshot))
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            let snapshots = meals.map(\.snapshot)
            Task { await ReminderManager.reschedule(loggedMeals: snapshots) }
        }
    }
}
