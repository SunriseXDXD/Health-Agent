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
            return "Add your DeepSeek API key in Settings first."
        case .http(let code, let message):
            return "DeepSeek API error \(code): \(message)"
        case .badResponse:
            return "DeepSeek returned a response the app could not read."
        }
    }
}

/// A small client for the DeepSeek API (OpenAI-compatible chat completions).
/// The key is the user's own and stays on the device.
enum DeepSeekClient {
    private static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    /// Sends one chat request and returns the text of the reply. With `json` set, the reply
    /// is forced to a JSON object; DeepSeek can return a blank reply in that mode, so one
    /// blank reply is retried.
    private static func generate(system: String, parts: [[String: Any]], json: Bool, temperature: Double) async throws -> String {
        let key = Keychain.apiKey
        guard !key.isEmpty else { throw AIError.missingKey }

        var body: [String: Any] = [
            "model": Prefs.modelName,
            "messages": [
                ["role": "system", "content": system] as [String: Any],
                ["role": "user", "content": parts] as [String: Any],
            ],
            "temperature": temperature,
            "max_tokens": 4000,
        ]
        if json { body["response_format"] = ["type": "json_object"] }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        for attempt in 0..<2 {
            let (data, response) = try await URLSession.shared.data(for: request)
            let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let error = reply?["error"] as? [String: Any]
                let message = (error?["message"] as? String) ?? String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIError.http(http.statusCode, message)
            }
            guard let choices = reply?["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else { throw AIError.badResponse }

            // Only the answer is used; any "reasoning_content" from thinking mode is ignored.
            var text = ((message["content"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("```") {
                text = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !text.isEmpty { return text }
            if attempt == 0 { continue }
        }
        throw AIError.badResponse
    }

    private static func textPart(_ text: String) -> [String: Any] {
        ["type": "text", "text": text]
    }

    private static func imagePart(_ jpeg: Data) -> [String: Any] {
        let url: [String: Any] = ["url": "data:image/jpeg;base64," + jpeg.base64EncodedString()]
        return ["type": "image_url", "image_url": url]
    }

    /// Instruction telling the model which JSON shape to return.
    private static func jsonInstruction(_ shape: String) -> String {
        "\n\nReply with a single json object only, no other text, in exactly this shape:\n" + shape
    }

    // MARK: - Meal analysis

    private static let mealShape = """
    {
      "summary": "short name of the meal, under 60 characters",
      "items": [
        {"name": "food", "portion": "estimated portion, e.g. 1 bowl, about 250 g", "kcal": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0}
      ],
      "total_kcal": 0,
      "protein_g": 0,
      "carbs_g": 0,
      "fat_g": 0,
      "fiber_g": 0,
      "confidence": "low | medium | high",
      "notes": "one sentence on the main assumption or uncertainty"
    }
    """

    /// Estimates a meal's nutrition from a photo, a description, or both.
    static func analyzeMeal(description: String, image: UIImage?, mealType: MealType) async throws -> MealEstimate {
        var parts: [[String: Any]] = []
        if let image, let jpeg = image.resized(maxSide: 1568).jpegData(compressionQuality: 0.7) {
            parts.append(imagePart(jpeg))
        }
        let note = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var prompt = "This is what I ate for \(mealType.title.lowercased()). "
        prompt += note.isEmpty ? "No description was given; go by the photo." : "My description: \(note)"
        prompt += "\nEstimate each food's portion and nutrition, then the meal totals. "
        prompt += "Use typical restaurant or canteen portions when the size is unclear, and count cooking oil and sauces."
        parts.append(textPart(prompt))

        let system = "You are a careful nutrition estimator. Give realistic single best estimates, not ranges. The user may write in English or Chinese; write the summary and food names in English. Numbers are plain numbers without units." + jsonInstruction(mealShape)

        let text = try await generate(system: system, parts: parts, json: true, temperature: 0.2)
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

    // MARK: - Dish suggestions

    private static let dishShape = """
    {
      "lunch": [
        {"name": "dish", "reason": "one sentence: why it fits, and the portion or swap that makes it fit", "kcal": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0}
      ],
      "dinner": [
        {"name": "dish", "reason": "one sentence", "kcal": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0}
      ],
      "tip": "one practical sentence for the coming week"
    }
    """

    /// Recommends lunch and dinner dishes that fit the plan, starting from what the user already eats.
    static func suggestDishes(meals: [MealSnapshot], plan: GoalPlan) async throws -> DishSuggestions {
        let recent = meals.sorted { $0.date > $1.date }.prefix(30)
        let history = recent.map { meal in
            String(format: "- %@: %@ (%.0f kcal, protein %.0f g, carbs %.0f g, fat %.0f g)",
                   meal.mealType, meal.summary, meal.kcal, meal.proteinG, meal.carbsG, meal.fatG)
        }.joined(separator: "\n")
        let lunch = plan.target(for: .lunch)
        let dinner = plan.target(for: .dinner)
        let prompt = """
        These are meals I logged recently. They were identified from photos I took, so they show what I actually eat and can get:
        \(history)

        My targets per meal:
        - Lunch: about \(Int(lunch.kcal)) kcal, protein \(Int(lunch.proteinG)) g, carbohydrate \(Int(lunch.carbsG)) g, fat \(Int(lunch.fatG)) g
        - Dinner: about \(Int(dinner.kcal)) kcal, protein \(Int(dinner.proteinG)) g, carbohydrate \(Int(dinner.carbsG)) g, fat \(Int(dinner.fatG)) g

        Recommend 3 lunch dishes and 3 dinner dishes. Start from dishes I already eat or close variants I could get at the same places, and say what portion, swap or side makes each one fit the target. Give estimated nutrition for the dish as you recommend it.
        """
        let system = "You are a practical meal planner. Recommend ordinary, obtainable dishes, not recipes. Write in English. Keep each reason to one sentence. Numbers are plain numbers without units." + jsonInstruction(dishShape)

        let text = try await generate(system: system, parts: [textPart(prompt)], json: true, temperature: 0.6)
        guard let output = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
            throw AIError.badResponse
        }
        func dishes(_ key: String) -> [DishSuggestion] {
            ((output[key] as? [[String: Any]]) ?? []).map { item in
                DishSuggestion(
                    name: (item["name"] as? String) ?? "Dish",
                    reason: (item["reason"] as? String) ?? "",
                    kcal: number(item["kcal"]),
                    proteinG: number(item["protein_g"]),
                    carbsG: number(item["carbs_g"]),
                    fatG: number(item["fat_g"])
                )
            }
        }
        let result = DishSuggestions(generatedAt: Date(), lunch: dishes("lunch"), dinner: dishes("dinner"),
                                     tip: (output["tip"] as? String) ?? "")
        guard !result.lunch.isEmpty || !result.dinner.isEmpty else { throw AIError.badResponse }
        return result
    }

    // MARK: - Weekly observations

    /// Asks DeepSeek for two or three short observations on the week's figures.
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
        let parts = [textPart("This week's data and the previous week's, as JSON:\n\(reportJSON)")]
        let text = try await generate(system: system, parts: parts, json: false, temperature: 0.4)
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
