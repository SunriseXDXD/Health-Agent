import Foundation
import Security

/// UserDefaults keys and defaults shared by the settings screen and the services.
enum Prefs {
    static let model = "geminiModel"
    static let remindersOn = "remindersOn"
    static let lunchMinutes = "lunchMinutes"
    static let dinnerMinutes = "dinnerMinutes"
    static let reportHour = "reportHour"
    static let recipients = "reportRecipients"
    static let userName = "userName"
    static let writeToHealth = "writeToHealth"
    static let healthRequested = "healthRequested"
    static let smallBottleMl = "smallBottleMl"
    static let largeBottleMl = "largeBottleMl"

    static let defaultModel = "gemini-3.5-flash"

    static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            model: defaultModel,
            remindersOn: true,
            lunchMinutes: 13 * 60,
            dinnerMinutes: 19 * 60 + 30,
            reportHour: 11,
            recipients: "",
            userName: "Xuyao",
            writeToHealth: true,
            smallBottleMl: 500.0,
            largeBottleMl: 1500.0,
        ])
    }

    static var recipientList: [String] {
        (defaults.string(forKey: recipients) ?? "")
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " || $0 == "\n" })
            .map { String($0) }
            .filter { $0.contains("@") }
    }

    static var modelName: String {
        let value = (defaults.string(forKey: model) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? defaultModel : value
    }
}

/// The Gemini API key lives in the Keychain, not in UserDefaults.
enum Keychain {
    private static let service = "com.xuyaofeng.HealthAgent"
    private static let account = "gemini-api-key"

    static var apiKey: String {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let value = String(data: data, encoding: .utf8) else { return "" }
            return value
        }
        set {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(base as CFDictionary)
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            var add = base
            add[kSecValueData as String] = Data(trimmed.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
