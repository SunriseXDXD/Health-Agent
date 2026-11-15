import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var meals: [MealEntry]

    @AppStorage(Prefs.userName) private var userName = "Xuyao"
    @AppStorage(Prefs.model) private var model = Prefs.defaultModel
    @AppStorage(Prefs.remindersOn) private var remindersOn = true
    @AppStorage(Prefs.lunchMinutes) private var lunchMinutes = 13 * 60
    @AppStorage(Prefs.dinnerMinutes) private var dinnerMinutes = 19 * 60 + 30
    @AppStorage(Prefs.reportHour) private var reportHour = 11
    @AppStorage(Prefs.recipients) private var recipients = ""
    @AppStorage(Prefs.writeToHealth) private var writeToHealth = true

    @State private var apiKey = Keychain.apiKey
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: apiKey) { _, value in Keychain.apiKey = value }
                    TextField("Model", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Gemini API")
                } footer: {
                    Text("Used to estimate meals from photos and to write the weekly observations. Create a free key at aistudio.google.com (no card needed). It is kept in this phone's Keychain and sent only to Google. On the free tier Google may use what you send to improve its products. If the model name stops working, try gemini-3.8-flash or gemini-3.1-flash-lite.")
                }

                Section {
                    Toggle("Meal and report reminders", isOn: $remindersOn)
                    if remindersOn {
                        DatePicker("Lunch reminder", selection: $lunchMinutes.asTimeOfDay, displayedComponents: .hourAndMinute)
                        DatePicker("Dinner reminder", selection: $dinnerMinutes.asTimeOfDay, displayedComponents: .hourAndMinute)
                        Stepper("Sunday report at \(reportHour):00", value: $reportHour, in: 6...22)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    if notificationsDenied {
                        Text("Notifications are turned off for Health Agent. Turn them on in Settings › Notifications.")
                            .foregroundStyle(.red)
                    } else {
                        Text("No breakfast reminder. A meal you have already logged does not get a reminder that day.")
                    }
                }

                Section {
                    TextField("Your name", text: $userName)
                    TextField("Email addresses, separated by commas", text: $recipients, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                } header: {
                    Text("Weekly report")
                } footer: {
                    Text("On Sunday a notification arrives at the time above; tapping it opens the report email to these addresses, ready to send.")
                }

                Section {
                    Toggle("Save meals and water to Apple Health", isOn: $writeToHealth)
                    Button("Review Health access") {
                        Task { await HealthKitManager.shared.requestAuthorization() }
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("If a chart stays empty, open the Health app › your picture › Apps › Health Agent and turn on the categories you want to share.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: remindersOn) { _, _ in reschedule() }
            .onChange(of: lunchMinutes) { _, _ in reschedule() }
            .onChange(of: dinnerMinutes) { _, _ in reschedule() }
            .onChange(of: reportHour) { _, _ in reschedule() }
            .task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                notificationsDenied = settings.authorizationStatus == .denied
            }
        }
    }

    private func reschedule() {
        let snapshots = meals.map(\.snapshot)
        Task { await ReminderManager.reschedule(loggedMeals: snapshots) }
    }
}
