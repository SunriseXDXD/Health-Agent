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
    @AppStorage(Prefs.smallBottleMl) private var smallBottleMl = 500.0
    @AppStorage(Prefs.largeBottleMl) private var largeBottleMl = 1500.0

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
                    Text("DeepSeek API")
                } footer: {
                    Text("Used to estimate meals from photos, recommend dishes and write the weekly observations. Create a key at platform.deepseek.com. It is kept in this phone's Keychain and sent only to api.deepseek.com. The model must accept images; deepseek-flash does.")
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
                    bottleRow(WaterBottle.metal.title, value: $smallBottleMl)
                    bottleRow(WaterBottle.large.title, value: $largeBottleMl)
                } header: {
                    Text("Water bottles")
                } footer: {
                    Text("The size each button on the Today tab adds. Bottles already logged keep the size they had.")
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

    private func bottleRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("ml", value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("ml").foregroundStyle(.secondary)
        }
    }

    private func reschedule() {
        let snapshots = meals.map(\.snapshot)
        Task { await ReminderManager.reschedule(loggedMeals: snapshots) }
    }
}
