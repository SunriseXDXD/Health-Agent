import Foundation
import SwiftData

enum MealType: String, Codable, CaseIterable, Identifiable {
    case lunch, dinner, snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snack: return "Snack"
        }
    }

    var symbol: String {
        switch self {
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "cup.and.saucer.fill"
        }
    }
}

/// One food in a meal, as estimated by DeepSeek or typed in by hand.
struct FoodItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var portion: String
    var kcal: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double

    enum CodingKeys: String, CodingKey {
        case name, portion, kcal, proteinG, carbsG, fatG
    }
}

@Model
final class MealEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var mealTypeRaw: String = MealType.lunch.rawValue
    var summary: String = ""
    var userNote: String = ""
    var kcal: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var fiberG: Double = 0
    var itemsData: Data?
    @Attribute(.externalStorage) var photo: Data?
    /// "deepseek", "gemini" (older entries) or "manual"
    var source: String = "manual"
    var confidence: String = ""
    var analysisNotes: String = ""

    init(date: Date, mealType: MealType) {
        self.id = UUID()
        self.date = date
        self.mealTypeRaw = mealType.rawValue
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    var items: [FoodItem] {
        get {
            guard let itemsData else { return [] }
            return (try? JSONDecoder().decode([FoodItem].self, from: itemsData)) ?? []
        }
        set { itemsData = try? JSONEncoder().encode(newValue) }
    }

    var snapshot: MealSnapshot {
        MealSnapshot(date: date, mealType: mealTypeRaw, summary: summary,
                     kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG, fiberG: fiberG)
    }
}

/// A plain value copy of a meal, safe to pass to background work and to export as JSON.
struct MealSnapshot: Codable, Hashable {
    var date: Date
    var mealType: String
    var summary: String
    var kcal: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
}

extension Array where Element == MealSnapshot {
    /// Days on which both lunch and dinner were logged. Breakfast is skipped, so these
    /// are the days whose calorie total can be trusted as a full day's intake.
    func completeDays(calendar: Calendar = .current) -> [Date: [MealSnapshot]] {
        let byDay = Dictionary(grouping: self) { calendar.startOfDay(for: $0.date) }
        return byDay.filter { _, meals in
            let types = Set(meals.map(\.mealType))
            return types.contains(MealType.lunch.rawValue) && types.contains(MealType.dinner.rawValue)
        }
    }
}
