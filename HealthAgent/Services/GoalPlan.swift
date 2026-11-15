import Foundation

struct MealTarget {
    let kcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

/// A one-month weight goal and the daily nutrition that goes with it,
/// worked out from one full week of measurements.
struct GoalPlan: Codable {
    var createdAt: Date
    var periodStart: Date
    var periodEnd: Date
    var startWeightKg: Double
    var lossKgPerMonth: Double
    var tdeeKcal: Double
    var basalKcal: Double
    var observedIntakeKcal: Double?
    var bmi: Double?
    var dailyKcal: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var rationale: String

    var targetWeightKg: Double { startWeightKg - lossKgPerMonth }
    var targetDate: Date { createdAt.addingTimeInterval(30 * 86400) }
    var dailyDeficitKcal: Double { lossKgPerMonth * 7700 / 30 }
    var isExpired: Bool { Date() > targetDate }

    /// Share of daily energy from each macro, in percent.
    var energySplit: (protein: Double, carbs: Double, fat: Double) {
        let total = max(proteinG * 4 + carbsG * 4 + fatG * 9, 1)
        return (proteinG * 4 / total * 100, carbsG * 4 / total * 100, fatG * 9 / total * 100)
    }

    /// Breakfast is skipped, so the day is split between lunch, dinner and a small snack.
    static func share(for meal: MealType) -> Double {
        switch meal {
        case .lunch: return 0.45
        case .dinner: return 0.45
        case .snack: return 0.10
        }
    }

    func target(for meal: MealType) -> MealTarget {
        let share = GoalPlan.share(for: meal)
        return MealTarget(kcal: dailyKcal * share, proteinG: proteinG * share, carbsG: carbsG * share, fatG: fatG * share)
    }

    /// Where the weight should be today if the month is on track.
    func expectedWeight(on date: Date = Date()) -> Double {
        let fraction = min(max(date.timeIntervalSince(createdAt) / (30 * 86400), 0), 1)
        return startWeightKg - lossKgPerMonth * fraction
    }

    var summaryLine: String {
        let date = targetDate.formatted(date: .abbreviated, time: .omitted)
        if lossKgPerMonth <= 0 {
            return String(format: "Goal: hold weight at about %.1f kg until %@. Daily target %.0f kcal: protein %.0f g, carbohydrate %.0f g, fat %.0f g.",
                          startWeightKg, date, dailyKcal, proteinG, carbsG, fatG)
        }
        return String(format: "Goal: lose %.1f kg by %@ (%.1f kg to %.1f kg). Daily target %.0f kcal: protein %.0f g, carbohydrate %.0f g, fat %.0f g.",
                      lossKgPerMonth, date, startWeightKg, targetWeightKg, dailyKcal, proteinG, carbsG, fatG)
    }
}

enum GoalStore {
    private static let key = "goalPlan"

    static var current: GoalPlan? {
        get {
            guard let data = Prefs.defaults.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(GoalPlan.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                Prefs.defaults.set(data, forKey: key)
            } else {
                Prefs.defaults.removeObject(forKey: key)
            }
        }
    }
}

enum GoalEvaluation {
    case ready(GoalPlan)
    /// Not enough data yet: how many of the last 7 days have energy data, and whether a weight exists.
    case notReady(daysWithEnergy: Int, hasWeight: Bool)
}

enum GoalPlanner {
    static let requiredDays = 5

    /// Looks at the last 7 complete days and proposes a goal for the next month.
    static func evaluate(meals: [MealSnapshot]) async -> GoalEvaluation {
        let health = HealthKitManager.shared
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end

        async let activeSeries = health.daily(.activeKcal, from: start, to: end)
        async let basalSeries = health.daily(.basalKcal, from: start, to: end)
        async let weightSeries = health.daily(.weightKg, from: start, to: end)
        async let latestWeight = health.latest(.weightKg)
        async let latestHeight = health.latest(.heightM)

        let active = await activeSeries
        let basal = await basalSeries
        var burns: [Double] = []
        var rests: [Double] = []
        for (day, value) in active {
            guard let rest = basal[day], rest > 500 else { continue }
            burns.append(value + rest)
            rests.append(rest)
        }

        // Weight: this week's average, or the last weigh-in if it is recent.
        let weekWeights = Array((await weightSeries).values)
        var weight: Double?
        if !weekWeights.isEmpty {
            weight = weekWeights.reduce(0, +) / Double(weekWeights.count)
        } else if let last = await latestWeight, last.date > start.addingTimeInterval(-14 * 86400) {
            weight = last.value
        }

        guard burns.count >= requiredDays, let weight else {
            return .notReady(daysWithEnergy: burns.count, hasWeight: weight != nil)
        }

        let tdee = burns.reduce(0, +) / Double(burns.count)
        let rest = rests.reduce(0, +) / Double(rests.count)
        let height = await latestHeight
        let bmi = height.map { weight / ($0.value * $0.value) }

        let complete = meals.filter { $0.date >= start && $0.date < end }.completeDays(calendar: calendar)
        let intakes = complete.values.map { $0.reduce(0) { $0 + $1.kcal } }
        let intake = intakes.isEmpty ? nil : intakes.reduce(0, +) / Double(intakes.count)

        // Three limits on the pace; the goal is the gentlest of them.
        let byBodyWeight = 0.005 * weight * 30 / 7        // 0.5% of body weight a week
        let byShare = 0.25 * tdee * 30 / 7700             // eat no less than 75% of energy used
        let byFloor = max(tdee - rest, 0) * 30 / 7700     // eat no less than resting energy use
        var loss = (min(byBodyWeight, byShare, byFloor) * 10).rounded(.down) / 10

        var rationale = String(format: "Over the 7 days to %@ you burned about %.0f kcal a day at %.1f kg.",
                               (calendar.date(byAdding: .day, value: -1, to: end) ?? end).formatted(date: .abbreviated, time: .omitted), tdee, weight)
        if let bmi, bmi < 20 {
            loss = 0
            rationale += String(format: " Your BMI is %.1f, already at the lower end of the healthy range, so the plan is to hold your weight.", bmi)
        } else if loss <= 0 {
            loss = 0
            rationale += " Your measured activity leaves no safe room for a deficit, so the plan is to hold your weight."
        } else {
            rationale += String(format: " Losing %.1f kg in a month needs a gap of about %.0f kcal a day, which keeps your intake above your resting energy use (%.0f kcal).",
                                loss, loss * 7700 / 30, rest)
        }
        if let intake {
            rationale += String(format: " On fully logged days you ate about %.0f kcal.", intake)
        }

        let dailyKcal = ((tdee - loss * 7700 / 30) / 10).rounded() * 10
        let protein = (1.6 * weight).rounded()
        let fat = (0.25 * dailyKcal / 9).rounded()
        let carbs = max((dailyKcal - protein * 4 - fat * 9) / 4, 0).rounded()

        let plan = GoalPlan(
            createdAt: Date(), periodStart: start, periodEnd: end,
            startWeightKg: weight, lossKgPerMonth: loss, tdeeKcal: tdee, basalKcal: rest,
            observedIntakeKcal: intake, bmi: bmi,
            dailyKcal: dailyKcal, proteinG: protein, carbsG: carbs, fatG: fat,
            rationale: rationale
        )
        return .ready(plan)
    }
}

// MARK: - Dish suggestions

struct DishSuggestion: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var reason: String
    var kcal: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double

    enum CodingKeys: String, CodingKey {
        case name, reason, kcal, proteinG, carbsG, fatG
    }
}

struct DishSuggestions: Codable {
    var generatedAt: Date
    var lunch: [DishSuggestion]
    var dinner: [DishSuggestion]
    var tip: String
}

enum DishStore {
    private static let key = "dishSuggestions"

    static var current: DishSuggestions? {
        get {
            guard let data = Prefs.defaults.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(DishSuggestions.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                Prefs.defaults.set(data, forKey: key)
            } else {
                Prefs.defaults.removeObject(forKey: key)
            }
        }
    }
}
