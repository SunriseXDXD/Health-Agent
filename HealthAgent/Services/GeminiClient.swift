import Foundation
import UIKit

struct MealEstimate {
    var summary: String
    var items: [FoodItem]
    var kcal: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var confidence: String
    var notes: String
}

enum AIError: LocalizedError {
    case missingKey
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add your Gemini API key in Settings first."
        case .http(let code, let message):
            return "Gemini API error \(code): \(message)"
        case .badResponse:
            return "Gemini returned a response the app could not read."
        }
    }
}

/// A small client for the Gemini API (free tier). The key is the user's own and stays on the device.
enum GeminiClient {
    /// Sends one generateContent request and returns the text of the reply.
    private static func generate(system: String, parts: [[String: Any]], config: [String: Any]) async throws -> String {
        let key = Keychain.apiKey
        guard !key.isEmpty else { throw AIError.missingKey }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Prefs.modelName):generateContent") else {
            throw AIError.http(0, "The model name in Settings is not valid.")
        }

        let systemPart: [String: Any] = ["text": system]
        let userContent: [String: Any] = ["role": "user", "parts": parts]
        let body: [String: Any] = [
            "system_instruction": ["parts": [systemPart]],
            "contents": [userContent],
            "generationConfig": config,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let error = json?["error"] as? [String: Any]
            let message = (error?["message"] as? String) ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.http(http.statusCode, message)
        }
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let replyParts = content["parts"] as? [[String: Any]] else { throw AIError.badResponse }

        // Skip any "thought" parts and keep the answer text.
        let text = replyParts
            .filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else { throw AIError.badResponse }
        return text
    }

    // MARK: - Meal analysis

    private static let mealSchemaJSON = """
    {
      "type": "OBJECT",
      "properties": {
        "summary": {"type": "STRING", "description": "Short name of the meal, under 60 characters."},
        "items": {
          "type": "ARRAY",
          "items": {
            "type": "OBJECT",
            "properties": {
              "name": {"type": "STRING"},
              "portion": {"type": "STRING", "description": "Estimated portion, e.g. 1 bowl, about 250 g."},
              "kcal": {"type": "NUMBER"},
              "protein_g": {"type": "NUMBER"},
              "carbs_g": {"type": "NUMBER"},
              "fat_g": {"type": "NUMBER"}
            },
            "required": ["name", "portion", "kcal", "protein_g", "carbs_g", "fat_g"]
          }
        },
        "total_kcal": {"type": "NUMBER"},
        "protein_g": {"type": "NUMBER"},
        "carbs_g": {"type": "NUMBER"},
        "fat_g": {"type": "NUMBER"},
        "fiber_g": {"type": "NUMBER"},
        "confidence": {"type": "STRING", "enum": ["low", "medium", "high"]},
        "notes": {"type": "STRING", "description": "One sentence on the main assumption or uncertainty."}
      },
      "required": ["summary", "items", "total_kcal", "protein_g", "carbs_g", "fat_g", "fiber_g", "confidence", "notes"]
    }
    """

    /// Estimates a meal's nutrition from a photo, a description, or both.
    static func analyzeMeal(description: String, image: UIImage?, mealType: MealType) async throws -> MealEstimate {
        var parts: [[String: Any]] = []
        if let image, let jpeg = image.resized(maxSide: 1568).jpegData(compressionQuality: 0.7) {
            let inline: [String: Any] = ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]
            parts.append(["inline_data": inline])
        }
        let note = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var prompt = "This is what I ate for \(mealType.title.lowercased()). "
        prompt += note.isEmpty ? "No description was given; go by the photo." : "My description: \(note)"
        prompt += "\nEstimate each food's portion and nutrition, then the meal totals. "
        prompt += "Use typical restaurant or canteen portions when the size is unclear, and count cooking oil and sauces."
        parts.append(["text": prompt])

        let schema = (try? JSONSerialization.jsonObject(with: Data(mealSchemaJSON.utf8))) ?? [String: Any]()
        let config: [String: Any] = [
            "response_mime_type": "application/json",
            "response_schema": schema,
            "temperature": 0.2,
        ]
        let system = "You are a careful nutrition estimator. Give realistic single best estimates, not ranges. The user may write in English or Chinese; write the summary and food names in English."

        let text = try await generate(system: system, parts: parts, config: config)
        guard let input = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
            throw AIError.badResponse
        }

        let rawItems = (input["items"] as? [[String: Any]]) ?? []
        let items = rawItems.map { item in
            FoodItem(
                name: (item["name"] as? String) ?? "Food",
                portion: (item["portion"] as? String) ?? "",
                kcal: number(item["kcal"]),
                proteinG: number(item["protein_g"]),
                carbsG: number(item["carbs_g"]),
                fatG: number(item["fat_g"])
            )
        }
        return MealEstimate(
            summary: (input["summary"] as? String) ?? "Meal",
            items: items,
            kcal: number(input["total_kcal"]),
            proteinG: number(input["protein_g"]),
            carbsG: number(input["carbs_g"]),
            fatG: number(input["fat_g"]),
            fiberG: number(input["fiber_g"]),
            confidence: (input["confidence"] as? String) ?? "",
            notes: (input["notes"] as? String) ?? ""
        )
    }

    // MARK: - Weekly observations

    /// Asks Gemini for two or three short observations on the week's figures.
    static func weeklyObservations(reportJSON: String) async throws -> [String] {
        let system = """
        You write the closing observations of a personal weekly health summary. The data comes \
        from an iPhone, an Apple Watch and the user's meal log. Rules: write 2 or 3 plain, practical \
        observations, one per line, each under 40 words, no bullets or numbering. Compare with the \
        previous week where the data allows. These are consumer-device readings, not a medical \
        assessment; suggest seeing a doctor only if resting heart rate stays near or above 100 bpm. \
        The user wears bone conduction earphones, so headphone levels read louder than usual: mention \
        them only as a week-over-week trend and never as a problem. The user skips breakfast by choice; \
        do not comment on that. Meal figures are estimates from photos.
        """
        let parts: [[String: Any]] = [["text": "This week's data and the previous week's, as JSON:\n\(reportJSON)"]]
        let text = try await generate(system: system, parts: parts, config: ["temperature": 0.4])
        let lines = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-•* ").union(.whitespaces)) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw AIError.badResponse }
        return Array(lines.prefix(3))
    }

    private static func number(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) ?? 0 }
        return 0
    }
}

extension UIImage {
    /// Scales the image down so its longer side is at most `maxSide` points.
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
