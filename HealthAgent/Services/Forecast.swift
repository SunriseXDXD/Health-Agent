import Foundation

struct DataPoint: Identifiable, Hashable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct ForecastPoint: Identifiable {
    let date: Date
    let value: Double
    let lower: Double
    let upper: Double
    var id: Date { date }
}

/// A straight-line fit of value against time, with what is needed for a prediction interval.
struct LinearFit {
    let origin: Date
    let slopePerDay: Double
    let intercept: Double
    let residualSD: Double
    let count: Int
    let meanX: Double
    let sxx: Double
    let lastDate: Date

    var slopePerWeek: Double { slopePerDay * 7 }

    private func x(_ date: Date) -> Double { date.timeIntervalSince(origin) / 86400 }

    func value(on date: Date) -> Double { intercept + slopePerDay * x(date) }

    /// Roughly a 95% prediction interval for a single new measurement on that date.
    func interval(on date: Date) -> (lower: Double, upper: Double) {
        let dx = x(date) - meanX
        let spread = residualSD * (1 + 1 / Double(count) + (sxx > 0 ? dx * dx / sxx : 0)).squareRoot()
        let centre = value(on: date)
        return (centre - 2 * spread, centre + 2 * spread)
    }
}

enum Forecaster {
    /// Least-squares line through the points of the last `windowDays` days.
    /// Needs at least 4 points spread over at least 7 days.
    static func fit(_ points: [DataPoint], windowDays: Int) -> LinearFit? {
        guard let last = points.map(\.date).max() else { return nil }
        let cutoff = last.addingTimeInterval(-Double(windowDays) * 86400)
        let recent = points.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        guard recent.count >= 4, let first = recent.first,
              last.timeIntervalSince(first.date) >= 7 * 86400 else { return nil }

        let origin = first.date
        let xs = recent.map { $0.date.timeIntervalSince(origin) / 86400 }
        let ys = recent.map(\.value)
        let n = Double(recent.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var sxx = 0.0
        var sxy = 0.0
        for (x, y) in zip(xs, ys) {
            sxx += (x - meanX) * (x - meanX)
            sxy += (x - meanX) * (y - meanY)
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        var sse = 0.0
        for (x, y) in zip(xs, ys) {
            let error = y - (intercept + slope * x)
            sse += error * error
        }
        let residualSD = (sse / max(n - 2, 1)).squareRoot()
        return LinearFit(origin: origin, slopePerDay: slope, intercept: intercept, residualSD: residualSD,
                         count: recent.count, meanX: meanX, sxx: sxx, lastDate: last)
    }

    /// Weekly points from the last measurement out to `weeks` weeks ahead.
    static func project(_ fit: LinearFit, weeks: Int) -> [ForecastPoint] {
        (0...weeks).map { week in
            let date = fit.lastDate.addingTimeInterval(Double(week) * 7 * 86400)
            let band = fit.interval(on: date)
            return ForecastPoint(date: date, value: fit.value(on: date), lower: band.lower, upper: band.upper)
        }
    }

    /// Exponentially smoothed series that evens out day-to-day water-weight noise.
    static func smoothed(_ points: [DataPoint], alpha: Double = 0.15) -> [DataPoint] {
        let sorted = points.sorted { $0.date < $1.date }
        guard var level = sorted.first?.value else { return [] }
        return sorted.map { point in
            level += alpha * (point.value - level)
            return DataPoint(date: point.date, value: level)
        }
    }
}

/// What the logged food and the measured energy use imply for body weight.
struct EnergyBalance {
    let completeDays: Int
    let averageIntake: Double
    let averageExpenditure: Double

    var dailyBalance: Double { averageIntake - averageExpenditure }
    /// About 7,700 kcal corresponds to one kilogram of body fat.
    var kgPerWeek: Double { dailyBalance * 7 / 7700 }

    /// Uses only days with both lunch and dinner logged and with energy data from Health.
    static func compute(meals: [MealSnapshot], expenditure: [Date: Double], since: Date) -> EnergyBalance? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = meals.completeDays(calendar: calendar).filter { $0.key >= since && $0.key < today }
        var intakes: [Double] = []
        var burns: [Double] = []
        for (day, dayMeals) in days {
            guard let burned = expenditure[day], burned > 800 else { continue }
            intakes.append(dayMeals.reduce(0) { $0 + $1.kcal })
            burns.append(burned)
        }
        guard intakes.count >= 3 else { return nil }
        return EnergyBalance(
            completeDays: intakes.count,
            averageIntake: intakes.reduce(0, +) / Double(intakes.count),
            averageExpenditure: burns.reduce(0, +) / Double(burns.count)
        )
    }
}
