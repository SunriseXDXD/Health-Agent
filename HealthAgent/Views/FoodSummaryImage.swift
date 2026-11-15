import SwiftUI
import Charts

/// A picture for the weekly email: a pie chart of where the week's food energy came
/// from, and a table of every meal logged.
struct FoodSummaryCard: View {
    let report: WeeklyReport

    struct Slice: Identifiable {
        let name: String
        let grams: Double
        let kcal: Double
        let color: Color
        var id: String { name }
    }

    private var meals: [MealSnapshot] { report.meals }

    private var slices: [Slice] {
        let protein = meals.reduce(0) { $0 + $1.proteinG }
        let carbs = meals.reduce(0) { $0 + $1.carbsG }
        let fat = meals.reduce(0) { $0 + $1.fatG }
        return [
            Slice(name: "Protein", grams: protein, kcal: protein * 4, color: Color(red: 0.85, green: 0.25, blue: 0.3)),
            Slice(name: "Carbohydrate", grams: carbs, kcal: carbs * 4, color: Color(red: 0.95, green: 0.6, blue: 0.2)),
            Slice(name: "Fat", grams: fat, kcal: fat * 9, color: Color(red: 0.25, green: 0.5, blue: 0.85)),
        ]
    }

    private var totalKcal: Double { meals.reduce(0) { $0 + $1.kcal } }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(report.name)'s food this week")
                    .font(.system(size: 24, weight: .bold))
                Text("\(report.weekLabel) · \(meals.count) meal\(meals.count == 1 ? "" : "s") logged · \(Int(totalKcal.rounded())) kcal in total")
                    .font(.system(size: 13))
                    .foregroundStyle(.gray)
            }
            pieSection
            table
            Text("Nutrition values are estimates made from meal photos.")
                .font(.system(size: 10))
                .foregroundStyle(.gray)
        }
        .padding(28)
        .frame(width: 720, alignment: .leading)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
    }

    private var pieSection: some View {
        let macroKcal = max(slices.reduce(0) { $0 + $1.kcal }, 1)
        return HStack(alignment: .center, spacing: 28) {
            Chart(slices) { slice in
                SectorMark(angle: .value("kcal", slice.kcal), angularInset: 1.5)
                    .foregroundStyle(slice.color)
            }
            .chartLegend(.hidden)
            .frame(width: 190, height: 190)

            VStack(alignment: .leading, spacing: 12) {
                Text("Where the energy came from")
                    .font(.system(size: 15, weight: .semibold))
                ForEach(slices) { slice in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(slice.color).frame(width: 14, height: 14)
                        Text(slice.name).frame(width: 110, alignment: .leading)
                        Text("\(Int((slice.kcal / macroKcal * 100).rounded()))%")
                            .fontWeight(.semibold)
                            .frame(width: 44, alignment: .trailing)
                        Text("\(Int(slice.grams.rounded())) g").foregroundStyle(.gray)
                    }
                    .font(.system(size: 13))
                }
            }
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            row("Day", "Meal", "Food", "kcal", "P (g)", "C (g)", "F (g)", bold: true)
            Divider()
            ForEach(Array(meals.enumerated()), id: \.offset) { _, meal in
                row(Self.dayFormatter.string(from: meal.date),
                    meal.mealType.capitalized,
                    meal.summary,
                    number(meal.kcal), number(meal.proteinG), number(meal.carbsG), number(meal.fatG),
                    bold: false)
                Divider()
            }
            row("Total", "", "",
                number(totalKcal),
                number(meals.reduce(0) { $0 + $1.proteinG }),
                number(meals.reduce(0) { $0 + $1.carbsG }),
                number(meals.reduce(0) { $0 + $1.fatG }),
                bold: true)
        }
    }

    private func number(_ value: Double) -> String { String(Int(value.rounded())) }

    private func row(_ day: String, _ meal: String, _ food: String, _ kcal: String,
                     _ protein: String, _ carbs: String, _ fat: String, bold: Bool) -> some View {
        HStack(spacing: 8) {
            Text(day).frame(width: 84, alignment: .leading)
            Text(meal).frame(width: 56, alignment: .leading)
            Text(food).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(kcal).frame(width: 52, alignment: .trailing)
            Text(protein).frame(width: 44, alignment: .trailing)
            Text(carbs).frame(width: 44, alignment: .trailing)
            Text(fat).frame(width: 44, alignment: .trailing)
        }
        .font(.system(size: 12, weight: bold ? .semibold : .regular))
        .padding(.vertical, 6)
    }
}

enum FoodImage {
    /// Renders the card as a PNG; nil when no meals were logged that week.
    @MainActor
    static func render(_ report: WeeklyReport) -> Data? {
        guard !report.meals.isEmpty else { return nil }
        let renderer = ImageRenderer(content: FoodSummaryCard(report: report))
        renderer.scale = 2
        return renderer.uiImage?.pngData()
    }
}
