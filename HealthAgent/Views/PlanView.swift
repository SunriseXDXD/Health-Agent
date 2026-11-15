import SwiftUI
import SwiftData

/// The monthly weight goal, the daily and per-meal nutrition targets that follow
/// from it, and dish recommendations based on the meals already photographed.
struct PlanView: View {
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]

    @State private var plan: GoalPlan? = GoalStore.current
    @State private var suggestions: DishSuggestions? = DishStore.current
    @State private var daysWithEnergy = 0
    @State private var hasWeight = false
    @State private var currentWeight: Double?
    @State private var isEvaluating = false
    @State private var isSuggesting = false
    @State private var errorMessage: String?

    private var todaysMeals: [MealEntry] {
        meals.filter { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let plan {
                        goalCard(plan)
                        dailyCard(plan)
                        mealsCard(plan)
                        dishesCard(plan)
                    } else {
                        waitingCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Plan")
            .task { await refresh(force: false) }
            .refreshable { await refresh(force: false) }
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Cards

    private var waitingCard: some View {
        card("Monthly goal") {
            if isEvaluating {
                ProgressView("Looking at your last 7 days…")
            } else {
                Text("Your goal is set after a full week of data.")
                    .font(.subheadline)
                Label("\(daysWithEnergy) of the last 7 days have energy data (at least \(GoalPlanner.requiredDays) needed)",
                      systemImage: daysWithEnergy >= GoalPlanner.requiredDays ? "checkmark.circle.fill" : "circle")
                    .font(.footnote)
                Label(hasWeight ? "A recent weight is in Apple Health" : "No recent weight yet. Log one from the Today tab",
                      systemImage: hasWeight ? "checkmark.circle.fill" : "circle")
                    .font(.footnote)
                Text("Energy data comes from wearing the Apple Watch or carrying the iPhone during the day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func goalCard(_ plan: GoalPlan) -> some View {
        card("Monthly goal") {
            if plan.lossKgPerMonth > 0 {
                Text("Lose \(plan.lossKgPerMonth.text(1)) kg")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("\(plan.startWeightKg.text(1)) kg → \(plan.targetWeightKg.text(1)) kg by \(plan.targetDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
            } else {
                Text("Hold at \(plan.startWeightKg.text(1)) kg")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
            }
            if let currentWeight {
                let expected = plan.expectedWeight()
                let gap = currentWeight - expected
                let gapText = gap.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
                Text("Now \(currentWeight.text(1)) kg; on track would be \(expected.text(1)) kg (\(gapText) kg).")
                    .font(.footnote)
                    .foregroundStyle(gap <= 0.3 ? Color.green : Color.orange)
            }
            Text(plan.rationale)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("This is an estimate from consumer devices, not medical advice.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await refresh(force: true) }
            } label: {
                if isEvaluating {
                    ProgressView()
                } else {
                    Text(plan.isExpired ? "Month finished: set the next goal" : "Re-evaluate from the last 7 days")
                }
            }
            .font(.footnote)
            .disabled(isEvaluating)
        }
    }

    private func dailyCard(_ plan: GoalPlan) -> some View {
        let split = plan.energySplit
        return card("Daily target") {
            Text("\(plan.dailyKcal.wholeText) kcal")
                .font(.title2.weight(.semibold))
            Text("About \(plan.dailyDeficitKcal.wholeText) kcal below the \(plan.tdeeKcal.wholeText) kcal you burn")
                .font(.footnote)
                .foregroundStyle(.secondary)
            macroRow("Protein", grams: plan.proteinG, percent: split.protein, tint: .red)
            macroRow("Carbohydrate", grams: plan.carbsG, percent: split.carbs, tint: .orange)
            macroRow("Fat", grams: plan.fatG, percent: split.fat, tint: .yellow)
        }
    }

    private func macroRow(_ name: String, grams: Double, percent: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                Spacer()
                Text("\(grams.wholeText) g · \(percent.wholeText)% of energy").foregroundStyle(.secondary)
            }
            .font(.subheadline)
            ProgressView(value: min(max(percent / 100, 0), 1))
                .tint(tint)
        }
    }

    private func mealsCard(_ plan: GoalPlan) -> some View {
        let eaten = todaysMeals.reduce(0) { $0 + $1.kcal }
        let dinnerLogged = todaysMeals.contains { $0.mealType == .dinner }
        return card("Each meal") {
            ForEach(MealType.allCases) { type in
                let target = plan.target(for: type)
                HStack(alignment: .top) {
                    Image(systemName: type.symbol).frame(width: 28).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(type.title): \(target.kcal.wholeText) kcal").font(.subheadline.weight(.medium))
                        Text("Protein \(target.proteinG.wholeText) g · Carbs \(target.carbsG.wholeText) g · Fat \(target.fatG.wholeText) g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if eaten > 0 && !dinnerLogged {
                let left = max(plan.dailyKcal - eaten, 0)
                Text("You've had \(eaten.wholeText) kcal today, so about \(left.wholeText) kcal is left for dinner and snacks.")
                    .font(.footnote)
            }
            Text("No breakfast is planned; the day is split 45% lunch, 45% dinner, 10% snack.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func dishesCard(_ plan: GoalPlan) -> some View {
        card("Recommended dishes") {
            if let suggestions {
                dishList("Lunch", suggestions.lunch)
                dishList("Dinner", suggestions.dinner)
                if !suggestions.tip.isEmpty {
                    Text(suggestions.tip).font(.footnote)
                }
                Text("Based on your meal photos up to \(suggestions.generatedAt.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if meals.count < 3 {
                Text("Log at least 3 meals with photos and recommendations appear here, built from what you actually eat.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if meals.count >= 3 {
                Button {
                    Task { await suggest(plan) }
                } label: {
                    HStack {
                        if isSuggesting { ProgressView() }
                        Text(isSuggesting ? "Thinking…" : (suggestions == nil ? "Recommend dishes" : "Refresh recommendations"))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isSuggesting)
            }
        }
    }

    @ViewBuilder
    private func dishList(_ title: String, _ dishes: [DishSuggestion]) -> some View {
        if !dishes.isEmpty {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(dishes) { dish in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(dish.name).font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(dish.kcal.wholeText) kcal").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("P \(dish.proteinG.wholeText) g · C \(dish.carbsG.wholeText) g · F \(dish.fatG.wholeText) g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dish.reason).font(.caption)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Work

    /// Sets the goal once a full week of data exists. An existing goal is kept for its
    /// month unless `force` is true.
    @MainActor
    private func refresh(force: Bool) async {
        currentWeight = await HealthKitManager.shared.latest(.weightKg)?.value
        if plan != nil && !force { return }
        guard !isEvaluating else { return }
        isEvaluating = true
        defer { isEvaluating = false }

        switch await GoalPlanner.evaluate(meals: meals.map(\.snapshot)) {
        case .ready(let newPlan):
            GoalStore.current = newPlan
            plan = newPlan
        case .notReady(let days, let weight):
            daysWithEnergy = days
            hasWeight = weight
            if force { errorMessage = "The last 7 days don't have enough data yet (\(days) days with energy data, weight \(weight ? "found" : "missing")). Your current goal is unchanged." }
        }
    }

    @MainActor
    private func suggest(_ plan: GoalPlan) async {
        isSuggesting = true
        defer { isSuggesting = false }
        do {
            let result = try await GeminiClient.suggestDishes(meals: meals.map(\.snapshot), plan: plan)
            DishStore.current = result
            suggestions = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
