import Foundation

struct DayValue: Codable, Identifiable, Hashable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Everything measured in one Sunday-to-Saturday week.
struct WeekMetrics: Codable {
    var start: Date
    /// The last day of the week (a Saturday), at midnight.
    var end: Date

    // Activity
    var dailySteps: [DayValue] = []
    var stepsTotal: Double?
    var stepsAverage: Double?
    var distanceKm: Double?
    var flights: Double?
    var daysOver10k: Int = 0
    var daysUnder3k: Int = 0
    var bestDay: DayValue?
    var worstDay: DayValue?
    var activeKcalAverage: Double?
    var activeKcalGoal: Double?
    var exerciseMinAverage: Double?
    var exerciseMinGoal: Double?
    var standHoursAverage: Double?
    var standHoursGoal: Double?

    // Heart
    var dailyRestingHR: [DayValue] = []
    var restingHR: Double?
    var restingHRMin: Double?
    var restingHRMax: Double?
    var walkingHR: Double?
    var hrvMs: Double?
    var overnightHR: Double?
    var vo2Max: Double?

    // Sleep
    var sleepNights: Int = 0
    var sleepHours: Double?
    var deepHours: Double?
    var coreHours: Double?
    var remHours: Double?
    var awakeHours: Double?
    var bedtime: String?
    var wakeTime: String?

    // Other
    var walkingSpeedKmh: Double?
    var steadinessPct: Double?
    var respiratoryRate: Double?
    var headphoneDb: Double?
    var daylightMinPerDay: Double?

    // Body
    var weightKg: Double?
    var bodyFatPct: Double?
    var weighIns: Int = 0

    // Food and energy
    var dailyKcal: [DayValue] = []
    var mealsLogged: Int = 0
    var completeFoodDays: Int = 0
    var intakeKcal: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var fiberG: Double?
    var expenditureKcal: Double?

    // Water
    var dailyWaterMl: [DayValue] = []
    var waterDaysLogged: Int = 0
    var waterMlPerDay: Double?
    var smallBottles: Int = 0
    var largeBottles: Int = 0
}

struct HeadlineRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let change: String
}

struct WeeklyReport: Codable {
    var generatedAt: Date
    var name: String
    var current: WeekMetrics
    var previous: WeekMetrics
    var weightTrendKgPerWeek: Double?
    var weightInFourWeeksKg: Double?
    var weightInFourWeeksLowKg: Double?
    var weightInFourWeeksHighKg: Double?
    var bodyFatTrendPctPerWeek: Double?
    var bodyFatInFourWeeksPct: Double?
    /// The monthly goal and how this week measured against it; nil until a goal exists.
    var goalLine: String?
    var observations: [String]
    var meals: [MealSnapshot]

    var weekLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        let year = Calendar.current.component(.year, from: current.end)
        return "\(formatter.string(from: current.start)) – \(formatter.string(from: current.end)) \(year)"
    }

    var fileStem: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "Weekly health summary \(formatter.string(from: current.start))_to_\(formatter.string(from: current.end))"
    }

    var headlineRows: [HeadlineRow] {
        let c = current
        let p = previous
        var rows: [HeadlineRow?] = [
            Self.row("Steps per day", c.stepsAverage, p.stepsAverage, 0, ""),
            Self.row("Distance", c.distanceKm, p.distanceKm, 1, " km"),
            Self.row("Active energy per day", c.activeKcalAverage, p.activeKcalAverage, 0, " kcal"),
            Self.row("Exercise per day", c.exerciseMinAverage, p.exerciseMinAverage, 0, " min"),
            Self.row("Resting heart rate", c.restingHR, p.restingHR, 0, " bpm"),
            Self.row("Walking heart rate", c.walkingHR, p.walkingHR, 0, " bpm"),
            Self.row("Overnight heart rate", c.overnightHR, p.overnightHR, 0, " bpm"),
            Self.row("HRV (SDNN)", c.hrvMs, p.hrvMs, 0, " ms"),
            Self.row("VO2 max", c.vo2Max, p.vo2Max, 1, ""),
            Self.row("Sleep per night", c.sleepHours, p.sleepHours, 1, " h"),
            Self.row("Weight", c.weightKg, p.weightKg, 1, " kg"),
            Self.row("Body fat", c.bodyFatPct, p.bodyFatPct, 1, " %"),
            Self.row("Food intake per day", c.intakeKcal, p.intakeKcal, 0, " kcal"),
            Self.row("Protein per day", c.proteinG, p.proteinG, 0, " g"),
            Self.row("Carbohydrate per day", c.carbsG, p.carbsG, 0, " g"),
            Self.row("Fat per day", c.fatG, p.fatG, 0, " g"),
            Self.row("Water per day", c.waterMlPerDay.map { $0 / 1000 }, p.waterMlPerDay.map { $0 / 1000 }, 1, " L"),
            Self.row("Energy burned per day", c.expenditureKcal, p.expenditureKcal, 0, " kcal"),
            Self.row("Headphone level", c.headphoneDb, p.headphoneDb, 0, " dB"),
            Self.row("Time in daylight per day", c.daylightMinPerDay, p.daylightMinPerDay, 0, " min"),
        ]
        if c.sleepNights > 0 || p.sleepNights > 0 {
            rows.insert(HeadlineRow(label: "Nights of sleep recorded", value: "\(c.sleepNights)",
                                    change: Self.signed(Double(c.sleepNights - p.sleepNights), 0, "")), at: 10)
        }
        var result = rows.compactMap { $0 }
        if let future = weightInFourWeeksKg, let trend = weightTrendKgPerWeek {
            result.append(HeadlineRow(label: "Predicted weight in 4 weeks",
                                      value: String(format: "%.1f kg", future),
                                      change: String(format: "%+.2f kg/wk", trend)))
        }
        return result
    }

    /// Average daily nutrition on fully logged days; nil when no meals were logged.
    var nutritionLine: String? {
        let c = current
        guard let kcal = c.intakeKcal else {
            guard c.mealsLogged > 0 else { return nil }
            return "\(c.mealsLogged) meal\(c.mealsLogged == 1 ? "" : "s") logged, but no day had both lunch and dinner, so there is no daily average."
        }
        var text = String(format: "Average per fully logged day (%d of 7): %.0f kcal, protein %.0f g, carbohydrate %.0f g, fat %.0f g",
                          c.completeFoodDays, kcal, c.proteinG ?? 0, c.carbsG ?? 0, c.fatG ?? 0)
        if let fiber = c.fiberG { text += String(format: ", fibre %.0f g", fiber) }
        text += "."
        if let burned = c.expenditureKcal {
            text += String(format: " Energy burned averaged %.0f kcal a day, a balance of %+.0f kcal.", burned, kcal - burned)
        }
        return text
    }

    /// Where weight and body fat are heading; nil when there are too few readings.
    var forecastLine: String? {
        guard let trend = weightTrendKgPerWeek, let future = weightInFourWeeksKg else { return nil }
        var text = String(format: "Weight is moving %+.2f kg a week. If that continues it will be about %.1f kg in four weeks", trend, future)
        if let low = weightInFourWeeksLowKg, let high = weightInFourWeeksHighKg {
            text += String(format: " (likely between %.1f and %.1f kg)", low, high)
        }
        text += "."
        if let fatTrend = bodyFatTrendPctPerWeek, let fatFuture = bodyFatInFourWeeksPct {
            text += String(format: " Body fat is moving %+.2f points a week, heading for about %.1f%%.", fatTrend, fatFuture)
        }
        return text
    }

    /// Water drunk this week; nil when no bottles were logged.
    var waterLine: String? {
        let c = current
        guard let ml = c.waterMlPerDay else { return nil }
        let days = "\(c.waterDaysLogged) day\(c.waterDaysLogged == 1 ? "" : "s")"
        let small = "\(c.smallBottles) metal bottle\(c.smallBottles == 1 ? "" : "s") (500 ml)"
        let large = "\(c.largeBottles) bottled water\(c.largeBottles == 1 ? "" : "s") (1.5 L)"
        return String(format: "%.1f L a day on the ", ml / 1000) + days + " logged: " + small + " and " + large + " over the week."
    }

    private static func row(_ label: String, _ current: Double?, _ previous: Double?, _ decimals: Int, _ unit: String) -> HeadlineRow? {
        guard let current else { return nil }
        let value = String(format: "%.\(decimals)f", current) + unit
        let change = previous.map { signed(current - $0, decimals, unit) } ?? "–"
        return HeadlineRow(label: label, value: value, change: change)
    }

    private static func signed(_ delta: Double, _ decimals: Int, _ unit: String) -> String {
        let rounded = String(format: "%+.\(decimals)f", delta)
        let zero = String(format: "%+.\(decimals)f", 0.0)
        if rounded == zero || rounded == zero.replacingOccurrences(of: "+", with: "-") { return "no change" }
        return rounded + unit
    }

    /// A short takeaway paragraph for the top of the report and the email.
    var takeaway: String {
        var parts: [String] = []
        if let steps = current.stepsAverage {
            parts.append("averaged \(Int(steps.rounded())) steps a day")
        }
        if let hr = current.restingHR {
            parts.append("resting heart rate \(Int(hr.rounded())) bpm")
        }
        if let sleep = current.sleepHours {
            parts.append(String(format: "%.1f h of sleep on %d recorded night%@", sleep, current.sleepNights, current.sleepNights == 1 ? "" : "s"))
        }
        if let weight = current.weightKg {
            parts.append(String(format: "weight %.1f kg", weight))
        }
        if let intake = current.intakeKcal {
            parts.append("about \(Int(intake.rounded())) kcal eaten a day")
        }
        guard !parts.isEmpty else { return "No health data was available for this week." }
        return "This week \(name) " + parts.joined(separator: ", ") + "."
    }

    var emailSubject: String { "\(name)'s weekly health summary (\(weekLabel))" }

    var emailBody: String {
        var lines = ["Hi,", "", "Here is my health summary for \(weekLabel).", ""]
        for row in headlineRows.prefix(6) {
            let change = (row.change == "–") ? "" : " (\(row.change) vs last week)"
            lines.append("\(row.label): \(row.value)\(change)")
        }
        for extra in [nutritionLine, waterLine, forecastLine, goalLine] {
            if let extra {
                lines.append("")
                lines.append(extra)
            }
        }
        lines.append("")
        lines.append("The full report is attached. These readings come from consumer devices and are not a medical assessment.")
        lines.append("")
        lines.append(name)
        return lines.joined(separator: "\n")
    }

    var markdown: String {
        var text = "# Weekly health summary\n\n**\(weekLabel)**\n\n\(takeaway)\n\n"
        text += "| Measure | This week | Change |\n|---|---|---|\n"
        for row in headlineRows {
            text += "| \(row.label) | \(row.value) | \(row.change) |\n"
        }
        if let nutritionLine { text += "\n## Nutrition\n\n\(nutritionLine)\n" }
        if let waterLine { text += "\n## Water\n\n\(waterLine)\n" }
        if let forecastLine { text += "\n## Weight forecast\n\n\(forecastLine)\n" }
        if let goalLine { text += "\n## Monthly goal\n\n\(goalLine)\n" }
        text += "\n## Observations\n\n"
        for line in observations { text += "- \(line)\n" }
        text += "\nReadings come from consumer devices and meal estimates; this is not a medical assessment.\n"
        return text
    }
}

enum WeeklyReportBuilder {
    /// The most recent complete Sunday-to-Saturday week. On a Sunday that is the 7 days ending yesterday.
    static func lastCompletedWeek(now: Date = Date()) -> (start: Date, endExclusive: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let thisSunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        let start = calendar.date(byAdding: .day, value: -7, to: thisSunday) ?? today
        return (start, thisSunday)
    }

    static func build(meals: [MealSnapshot], water: [WaterSnapshot], useAI: Bool) async -> WeeklyReport {
        let calendar = Calendar.current
        let week = lastCompletedWeek()
        let previousStart = calendar.date(byAdding: .day, value: -7, to: week.start) ?? week.start

        async let currentMetrics = metrics(from: week.start, to: week.endExclusive, meals: meals, water: water)
        async let previousMetrics = metrics(from: previousStart, to: week.start, meals: meals, water: water)
        let trendStart = calendar.date(byAdding: .day, value: -35, to: week.endExclusive) ?? previousStart
        async let weightSeries = HealthKitManager.shared.daily(.weightKg, from: trendStart, to: week.endExclusive)
        async let fatSeries = HealthKitManager.shared.daily(.bodyFat, from: trendStart, to: week.endExclusive)

        let current = await currentMetrics
        let previous = await previousMetrics
        let weights = await weightSeries.map { DataPoint(date: $0.key, value: $0.value) }
        let fit = Forecaster.fit(weights, windowDays: 35)
        let fats = await fatSeries.map { DataPoint(date: $0.key, value: $0.value * 100) }
        let fatFit = Forecaster.fit(fats, windowDays: 35)

        var report = WeeklyReport(
            generatedAt: Date(),
            name: Prefs.defaults.string(forKey: Prefs.userName) ?? "Me",
            current: current,
            previous: previous,
            weightTrendKgPerWeek: fit?.slopePerWeek,
            weightInFourWeeksKg: fit.map { $0.value(on: $0.lastDate.addingTimeInterval(28 * 86400)) },
            observations: [],
            meals: meals.filter { $0.date >= week.start && $0.date < week.endExclusive }.sorted { $0.date < $1.date }
        )

        if let fit {
            let band = fit.interval(on: fit.lastDate.addingTimeInterval(28 * 86400))
            report.weightInFourWeeksLowKg = band.lower
            report.weightInFourWeeksHighKg = band.upper
        }
        if let fatFit {
            report.bodyFatTrendPctPerWeek = fatFit.slopePerWeek
            report.bodyFatInFourWeeksPct = fatFit.value(on: fatFit.lastDate.addingTimeInterval(28 * 86400))
        }

        if let goal = GoalStore.current {
            var line = goal.summaryLine
            if let now = current.weightKg {
                line += String(format: " This week's weight averaged %.1f kg against %.1f kg expected by now.", now, goal.expectedWeight(on: week.endExclusive))
            }
            if let intake = current.intakeKcal {
                line += String(format: " Intake averaged %+.0f kcal against the daily target.", intake - goal.dailyKcal)
            }
            report.goalLine = line
        }

        report.observations = ruleBasedObservations(report)
        if useAI, !Keychain.apiKey.isEmpty, let json = try? encode(report), let text = String(data: json, encoding: .utf8) {
            if let lines = try? await GeminiClient.weeklyObservations(reportJSON: text) {
                report.observations = lines
            }
        }
        return report
    }

    static func encode(_ report: WeeklyReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    // MARK: - One week of metrics

    static func metrics(from start: Date, to end: Date, meals: [MealSnapshot], water: [WaterSnapshot]) async -> WeekMetrics {
        let health = HealthKitManager.shared
        let calendar = Calendar.current
        let lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? start
        var m = WeekMetrics(start: start, end: lastDay)

        async let steps = health.daily(.steps, from: start, to: end)
        async let distance = health.aggregate(.distanceKm, from: start, to: end)
        async let flights = health.aggregate(.flights, from: start, to: end)
        async let active = health.daily(.activeKcal, from: start, to: end)
        async let basal = health.daily(.basalKcal, from: start, to: end)
        async let exercise = health.daily(.exerciseMin, from: start, to: end)
        async let rings = health.activityDays(from: start, to: end)
        async let resting = health.daily(.restingHR, from: start, to: end)
        async let walkingHR = health.aggregate(.walkingHR, from: start, to: end)
        async let hrv = health.aggregate(.hrvMs, from: start, to: end)
        async let vo2 = health.aggregate(.vo2Max, from: start, to: end)
        async let nights = health.sleepNights(from: start, to: end)
        async let speed = health.aggregate(.walkingSpeedMps, from: start, to: end)
        async let steadiness = health.aggregate(.steadiness, from: start, to: end)
        async let respiratory = health.aggregate(.respiratory, from: start, to: end)
        async let headphone = health.aggregate(.headphoneDb, from: start, to: end)
        async let daylight = health.daily(.daylightMin, from: start, to: end)
        async let weight = health.daily(.weightKg, from: start, to: end)
        async let bodyFat = health.daily(.bodyFat, from: start, to: end)

        // Activity
        let stepDays = await steps
        m.dailySteps = stepDays.map { DayValue(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
        if !m.dailySteps.isEmpty {
            let total = m.dailySteps.reduce(0) { $0 + $1.value }
            m.stepsTotal = total
            m.stepsAverage = total / Double(m.dailySteps.count)
            m.daysOver10k = m.dailySteps.filter { $0.value >= 10_000 }.count
            m.daysUnder3k = m.dailySteps.filter { $0.value < 3_000 }.count
            m.bestDay = m.dailySteps.max { $0.value < $1.value }
            m.worstDay = m.dailySteps.min { $0.value < $1.value }
        }
        m.distanceKm = await distance
        m.flights = await flights

        let activeDays = await active
        let basalDays = await basal
        m.activeKcalAverage = average(Array(activeDays.values))
        m.exerciseMinAverage = average(Array((await exercise).values))
        let burnDays = activeDays.compactMap { day, value -> Double? in
            guard let base = basalDays[day] else { return nil }
            return value + base
        }
        m.expenditureKcal = average(burnDays)

        let ringDays = await rings
        if !ringDays.isEmpty {
            m.activeKcalGoal = average(ringDays.map(\.activeGoal).filter { $0 > 0 })
            m.exerciseMinGoal = average(ringDays.map(\.exerciseGoal).filter { $0 > 0 })
            m.standHoursAverage = average(ringDays.map(\.standHours))
            m.standHoursGoal = average(ringDays.map(\.standGoal).filter { $0 > 0 })
        }

        // Heart
        let restingDays = await resting
        m.dailyRestingHR = restingDays.map { DayValue(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
        m.restingHR = average(Array(restingDays.values))
        m.restingHRMin = restingDays.values.min()
        m.restingHRMax = restingDays.values.max()
        m.walkingHR = await walkingHR
        m.hrvMs = await hrv
        m.vo2Max = await vo2

        var overnight: [Double] = []
        var day = start
        while day < end {
            let from = day.addingTimeInterval(2 * 3600)
            let to = day.addingTimeInterval(7 * 3600)
            if let value = await health.aggregate(.heartRate, from: from, to: to) { overnight.append(value) }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end
        }
        m.overnightHR = average(overnight)

        // Sleep
        let sleep = await nights
        m.sleepNights = sleep.count
        if !sleep.isEmpty {
            m.sleepHours = average(sleep.map { $0.asleep / 3600 })
            let staged = sleep.filter { $0.core + $0.deep + $0.rem > 0 }
            if !staged.isEmpty {
                m.deepHours = average(staged.map { $0.deep / 3600 })
                m.coreHours = average(staged.map { $0.core / 3600 })
                m.remHours = average(staged.map { $0.rem / 3600 })
                m.awakeHours = average(staged.map { $0.awake / 3600 })
            }
            m.bedtime = typicalTime(sleep.compactMap(\.bedtime))
            m.wakeTime = typicalTime(sleep.compactMap(\.wake))
        }

        // Other
        m.walkingSpeedKmh = (await speed).map { $0 * 3.6 }
        m.steadinessPct = (await steadiness).map { $0 * 100 }
        m.respiratoryRate = await respiratory
        m.headphoneDb = await headphone
        m.daylightMinPerDay = average(Array((await daylight).values))

        // Body
        let weightDays = await weight
        m.weightKg = average(Array(weightDays.values))
        m.weighIns = weightDays.count
        m.bodyFatPct = average(Array((await bodyFat).values)).map { $0 * 100 }

        // Food
        let weekMeals = meals.filter { $0.date >= start && $0.date < end }
        m.mealsLogged = weekMeals.count
        let byDay = Dictionary(grouping: weekMeals) { calendar.startOfDay(for: $0.date) }
        m.dailyKcal = byDay.map { DayValue(date: $0.key, value: $0.value.reduce(0) { $0 + $1.kcal }) }.sorted { $0.date < $1.date }
        let complete = weekMeals.completeDays(calendar: calendar)
        m.completeFoodDays = complete.count
        if !complete.isEmpty {
            m.intakeKcal = average(complete.values.map { $0.reduce(0) { $0 + $1.kcal } })
            m.proteinG = average(complete.values.map { $0.reduce(0) { $0 + $1.proteinG } })
            m.carbsG = average(complete.values.map { $0.reduce(0) { $0 + $1.carbsG } })
            m.fatG = average(complete.values.map { $0.reduce(0) { $0 + $1.fatG } })
            m.fiberG = average(complete.values.map { $0.reduce(0) { $0 + $1.fiberG } })
        }

        // Water
        let weekWater = water.filter { $0.date >= start && $0.date < end }
        let waterByDay = Dictionary(grouping: weekWater) { calendar.startOfDay(for: $0.date) }
        m.dailyWaterMl = waterByDay.map { DayValue(date: $0.key, value: $0.value.reduce(0) { $0 + $1.ml }) }.sorted { $0.date < $1.date }
        m.waterDaysLogged = waterByDay.count
        m.waterMlPerDay = average(m.dailyWaterMl.map(\.value))
        m.smallBottles = weekWater.filter { $0.ml < 1000 }.count
        m.largeBottles = weekWater.filter { $0.ml >= 1000 }.count
        return m
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// The average clock time of a set of dates, handling times either side of midnight.
    private static func typicalTime(_ dates: [Date]) -> String? {
        guard !dates.isEmpty else { return nil }
        let calendar = Calendar.current
        let shifted = dates.map { date -> Double in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            return Double((minutes + 720) % 1440)   // measured from noon
        }
        let mean = Int((shifted.reduce(0, +) / Double(shifted.count)).rounded())
        let minutes = (mean + 720) % 1440
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: - Observations without the API

    static func ruleBasedObservations(_ report: WeeklyReport) -> [String] {
        let c = report.current
        let p = report.previous
        var lines: [String] = []

        if let steps = c.stepsAverage {
            var line = "You averaged \(Int(steps.rounded())) steps a day, with \(c.daysOver10k) day\(c.daysOver10k == 1 ? "" : "s") at 10,000 or more"
            if let before = p.stepsAverage, before > 0 {
                let change = (steps - before) / before * 100
                line += String(format: " (%+.0f%% on the week before)", change)
            }
            lines.append(line + ".")
        }
        if let hr = c.restingHR {
            var line = "Resting heart rate averaged \(Int(hr.rounded())) bpm"
            if let before = p.restingHR { line += String(format: ", %+.0f bpm against last week", hr - before) }
            if hr >= 98 { line += "; it is staying near 100, which is worth raising with a doctor" }
            lines.append(line + ".")
        }
        if let intake = c.intakeKcal, let burned = c.expenditureKcal {
            let balance = intake - burned
            let weekly = balance * 7 / 7700
            lines.append(String(format: "On the %d fully logged day%@ you ate about %.0f kcal against %.0f kcal burned, a balance that points to roughly %+.1f kg a week.",
                                c.completeFoodDays, c.completeFoodDays == 1 ? "" : "s", intake, burned, weekly))
        } else if c.sleepNights < 4 {
            lines.append("Sleep was recorded on only \(c.sleepNights) night\(c.sleepNights == 1 ? "" : "s"); wearing the Watch to bed more often would make the sleep figures more useful.")
        }
        if lines.isEmpty { lines.append("There was too little data this week to say much. Check that Health access is turned on for this app.") }
        return Array(lines.prefix(3))
    }
}

/// Saves each week's report where the Files app (On My iPhone › Health Agent) can see it.
enum ReportFiles {
    static var folder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documents.appendingPathComponent("Weekly summaries", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func save(_ report: WeeklyReport, pdf: Data?) -> (pdf: URL?, json: URL?, markdown: URL?) {
        let stem = report.fileStem
        var pdfURL: URL?
        var jsonURL: URL?
        var markdownURL: URL?

        if let pdf {
            let url = folder.appendingPathComponent(stem + ".pdf")
            if (try? pdf.write(to: url, options: .atomic)) != nil { pdfURL = url }
        }
        if let json = try? WeeklyReportBuilder.encode(report) {
            let url = folder.appendingPathComponent(stem + ".json")
            if (try? json.write(to: url, options: .atomic)) != nil { jsonURL = url }
        }
        let url = folder.appendingPathComponent(stem + ".md")
        if (try? report.markdown.write(to: url, atomically: true, encoding: .utf8)) != nil { markdownURL = url }
        return (pdfURL, jsonURL, markdownURL)
    }
}
