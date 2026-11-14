import SwiftUI
import SwiftData
import Charts

struct TrendsData {
    var weight: [DataPoint] = []
    var bodyFat: [DataPoint] = []
    var steps: [DataPoint] = []
    var restingHR: [DataPoint] = []
    var sleep: [DataPoint] = []
    var expenditure: [Date: Double] = [:]
}

struct TrendsView: View {
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]

    @State private var rangeDays = 90
    @State private var horizonWeeks = 8
    @State private var data = TrendsData()
    @State private var isLoading = false

    private var rangeStart: Date {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: -rangeDays, to: today) ?? today
    }

    private var intake: [DataPoint] {
        let calendar = Calendar.current
        let start = rangeStart
        let recent = meals.filter { $0.date >= start }
        let grouped = Dictionary(grouping: recent) { calendar.startOfDay(for: $0.date) }
        return grouped.map { DataPoint(date: $0.key, value: $0.value.reduce(0) { $0 + $1.kcal }) }
            .sorted { $0.date < $1.date }
    }

    private var energyBalance: EnergyBalance? {
        let since = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? rangeStart
        return EnergyBalance.compute(meals: meals.map(\.snapshot), expenditure: data.expenditure, since: since)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Range", selection: $rangeDays) {
                        Text("1 M").tag(30)
                        Text("3 M").tag(90)
                        Text("6 M").tag(180)
                        Text("1 Y").tag(365)
                    }
                    .pickerStyle(.segmented)

                    card("Weight", subtitle: "Dots are weigh-ins, the line is the smoothed trend, the dashed line is the forecast") {
                        ForecastChart(points: data.weight, unit: "kg", decimals: 1, horizonWeeks: horizonWeeks, tint: .blue,
                                      emptyText: "No weight in Apple Health for this period. Log one from the Today tab or use a scale that syncs to Health.")
                        horizonPicker
                    }

                    card("Body fat", subtitle: "Same method as weight") {
                        ForecastChart(points: data.bodyFat, unit: "%", decimals: 1, horizonWeeks: horizonWeeks, tint: .purple,
                                      emptyText: "No body fat readings in Apple Health for this period.")
                    }

                    card("Energy in and out", subtitle: "Bars are logged food; the line is active plus resting energy from Health") {
                        energyChart
                        energyBalanceText
                    }

                    card("Steps", subtitle: nil) {
                        simpleChart(data.steps, tint: .green, bars: true)
                    }
                    card("Resting heart rate", subtitle: nil) {
                        simpleChart(data.restingHR, tint: .red, bars: false)
                    }
                    card("Sleep (hours)", subtitle: nil) {
                        simpleChart(data.sleep, tint: .indigo, bars: true)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trends")
            .overlay(alignment: .top) {
                if isLoading { ProgressView().padding(.top, 8) }
            }
            .task(id: rangeDays) { await load() }
            .refreshable { await load() }
        }
    }

    private var horizonPicker: some View {
        Picker("Forecast", selection: $horizonWeeks) {
            Text("4 weeks ahead").tag(4)
            Text("8 weeks ahead").tag(8)
            Text("12 weeks ahead").tag(12)
        }
        .pickerStyle(.segmented)
    }

    private func card<Content: View>(_ title: String, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var energyChart: some View {
        let burned = data.expenditure
            .map { DataPoint(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
        if intake.isEmpty && burned.isEmpty {
            emptyState("Nothing to show yet. Log a few meals and this fills in.")
        } else {
            Chart {
                ForEach(intake) { point in
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value("kcal", point.value))
                        .foregroundStyle(Color.orange.opacity(0.8))
                }
                ForEach(burned) { point in
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value("kcal", point.value))
                        .foregroundStyle(Color.gray)
                        .interpolationMethod(.monotone)
                }
            }
            .frame(height: 200)
        }
    }

    @ViewBuilder
    private var energyBalanceText: some View {
        if let balance = energyBalance {
            let direction = balance.dailyBalance < 0 ? "deficit" : "surplus"
            let gap = abs(balance.dailyBalance).wholeText
            let rate = balance.kgPerWeek.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
            let first = "Over \(balance.completeDays) fully logged days in the last 4 weeks you ate about \(balance.averageIntake.wholeText) kcal and burned about \(balance.averageExpenditure.wholeText) kcal a day."
            let second = "That \(direction) of \(gap) kcal points to roughly \(rate) kg a week."
            Text(first + " " + second)
                .font(.footnote)
            Text("Photo-based calorie estimates and watch energy figures can each be off by 10–20%, so treat this as a rough cross-check on the weight trend.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("An energy-balance estimate appears after 3 days with both lunch and dinner logged.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func simpleChart(_ points: [DataPoint], tint: Color, bars: Bool) -> some View {
        if points.isEmpty {
            emptyState("No data in Apple Health for this period.")
        } else {
            Chart(points) { point in
                if bars {
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value("Value", point.value))
                        .foregroundStyle(tint.opacity(0.8))
                } else {
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value("Value", point.value))
                        .foregroundStyle(tint)
                        .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: .automatic(includesZero: bars))
            .frame(height: 160)
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let health = HealthKitManager.shared
        let start = rangeStart
        let end = Date()
        let today = Calendar.current.startOfDay(for: end)

        func series(_ values: [Date: Double], scale: Double = 1) -> [DataPoint] {
            values.map { DataPoint(date: $0.key, value: $0.value * scale) }.sorted { $0.date < $1.date }
        }

        async let weight = health.daily(.weightKg, from: start, to: end)
        async let bodyFat = health.daily(.bodyFat, from: start, to: end)
        async let steps = health.daily(.steps, from: start, to: end)
        async let resting = health.daily(.restingHR, from: start, to: end)
        async let active = health.daily(.activeKcal, from: start, to: end)
        async let basal = health.daily(.basalKcal, from: start, to: end)
        async let nights = health.sleepNights(from: start, to: end)

        var next = TrendsData()
        next.weight = series(await weight)
        next.bodyFat = series(await bodyFat, scale: 100)
        next.steps = series(await steps)
        next.restingHR = series(await resting)
        next.sleep = (await nights).map { DataPoint(date: $0.day, value: $0.asleepHours) }

        // Daily energy use, leaving out today because the day is not over yet.
        let activeDays = await active
        let basalDays = await basal
        var burned: [Date: Double] = [:]
        for (day, value) in activeDays where day < today {
            if let base = basalDays[day] { burned[day] = value + base }
        }
        next.expenditure = burned
        data = next
    }
}

/// A measurement over time with a smoothed trend and a straight-line forecast.
struct ForecastChart: View {
    let points: [DataPoint]
    let unit: String
    let decimals: Int
    let horizonWeeks: Int
    let tint: Color
    let emptyText: String

    private var smoothed: [DataPoint] { Forecaster.smoothed(points) }

    /// The recent trend: the last 4 weeks if they hold enough readings, otherwise the last 8.
    private var fit: LinearFit? {
        Forecaster.fit(points, windowDays: 28) ?? Forecaster.fit(points, windowDays: 56)
    }

    private var projection: [ForecastPoint] {
        guard let fit else { return [] }
        return Forecaster.project(fit, weeks: horizonWeeks)
    }

    var body: some View {
        if points.isEmpty {
            Text(emptyText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                chart
                summary
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(projection) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("Low", point.lower), yEnd: .value("High", point.upper))
                    .foregroundStyle(tint.opacity(0.15))
            }
            ForEach(points) { point in
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(Color.gray.opacity(0.6))
                    .symbolSize(16)
            }
            ForEach(smoothed) { point in
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value), series: .value("Series", "Trend"))
                    .foregroundStyle(tint)
                    .interpolationMethod(.monotone)
            }
            ForEach(projection) { point in
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value), series: .value("Series", "Forecast"))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 220)
    }

    @ViewBuilder
    private var summary: some View {
        if let fit, let last = projection.last {
            let rate = fit.slopePerWeek.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
            Text("Recent trend: \(rate) \(unit) a week, from \(fit.count) readings.")
                .font(.footnote.weight(.medium))
            Text("If it continues: about \(last.value.text(decimals)) \(unit) on \(last.date.formatted(date: .abbreviated, time: .omitted)) (likely between \(last.lower.text(decimals)) and \(last.upper.text(decimals))).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("A forecast appears once there are at least 4 readings spread over a week or more.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
