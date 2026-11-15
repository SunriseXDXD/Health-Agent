import SwiftUI
import SwiftData

struct TodaySnapshot {
    var steps: Double?
    var activeKcal: Double?
    var basalKcal: Double?
    var exerciseMin: Double?
    var restingHR: Double?
    var sleepHours: Double?
    var weight: (date: Date, value: Double)?
    var bodyFat: (date: Date, value: Double)?
}

struct TodayView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \WaterEntry.date, order: .reverse) private var waters: [WaterEntry]

    @State private var snapshot = TodaySnapshot()
    @State private var editing: MealEntry?
    @State private var showWeightSheet = false
    @State private var showSettings = false

    private var todaysMeals: [MealEntry] {
        meals.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var eatenKcal: Double { todaysMeals.reduce(0) { $0 + $1.kcal } }
    private var burnedKcal: Double { (snapshot.activeKcal ?? 0) + (snapshot.basalKcal ?? 0) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    energyCard
                    mealsCard
                    waterCard
                    statsGrid
                    bodyCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await load() } }
            }
            .sheet(item: $editing) { meal in
                AddMealView(mealType: meal.mealType, existing: meal)
            }
            .sheet(isPresented: $showWeightSheet, onDismiss: { Task { await load() } }) {
                LogWeightView()
            }
        }
    }

    // MARK: - Cards

    private var energyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Energy today").font(.headline)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text(eatenKcal.wholeText).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("kcal eaten").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(burnedKcal > 0 ? burnedKcal.wholeText : "–").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("kcal burned so far").font(.caption).foregroundStyle(.secondary)
                }
            }
            let protein = todaysMeals.reduce(0) { $0 + $1.proteinG }
            let carbs = todaysMeals.reduce(0) { $0 + $1.carbsG }
            let fat = todaysMeals.reduce(0) { $0 + $1.fatG }
            Text("Protein \(protein.wholeText) g · Carbs \(carbs.wholeText) g · Fat \(fat.wholeText) g")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var mealsCard: some View {
        VStack(spacing: 0) {
            mealRow(.lunch)
            Divider().padding(.leading, 48)
            mealRow(.dinner)
            ForEach(todaysMeals.filter { $0.mealType == .snack }) { snack in
                Divider().padding(.leading, 48)
                loggedRow(snack)
            }
            Divider().padding(.leading, 48)
            Button {
                router.mealToLog = .snack
            } label: {
                Label("Add a snack", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func mealRow(_ type: MealType) -> some View {
        if let meal = todaysMeals.first(where: { $0.mealType == type }) {
            loggedRow(meal)
        } else {
            Button {
                router.mealToLog = type
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: type.symbol).frame(width: 36).foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text("Log \(type.title.lowercased())").font(.body.weight(.medium))
                        Text("Not logged yet").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "camera.fill")
                }
                .padding(.vertical, 12)
            }
        }
    }

    private func loggedRow(_ meal: MealEntry) -> some View {
        Button {
            editing = meal
        } label: {
            HStack(spacing: 12) {
                Image(systemName: meal.mealType.symbol).frame(width: 36).foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text(meal.summary).font(.body.weight(.medium)).lineLimit(1)
                    Text("\(meal.mealType.title) · P \(meal.proteinG.wholeText) g · C \(meal.carbsG.wholeText) g · F \(meal.fatG.wholeText) g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(meal.kcal.wholeText) kcal").font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var todaysWater: [WaterEntry] {
        waters.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var waterCard: some View {
        let today = todaysWater
        let total = today.reduce(0) { $0 + $1.ml }
        let small = today.filter { $0.ml < 1000 }.count
        let large = today.filter { $0.ml >= 1000 }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Water", systemImage: "drop.fill").font(.headline).foregroundStyle(.blue)
                Spacer()
                if !today.isEmpty {
                    Button("Undo") { undoWater() }.font(.subheadline)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text((total / 1000).text(1)).font(.system(size: 34, weight: .bold, design: .rounded))
                Text("L today").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(small) × 500 ml · \(large) × 1.5 L")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ForEach(WaterBottle.allCases) { bottle in
                    Button {
                        addWater(bottle)
                    } label: {
                        VStack(spacing: 2) {
                            Text("+ \(bottle.sizeLabel)").font(.body.weight(.semibold))
                            Text(bottle.title).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func addWater(_ bottle: WaterBottle) {
        let entry = WaterEntry(date: Date(), ml: bottle.ml)
        context.insert(entry)
        try? context.save()
        let date = entry.date
        if Prefs.defaults.bool(forKey: Prefs.writeToHealth) {
            Task { await HealthKitManager.shared.saveWater(ml: bottle.ml, date: date) }
        }
    }

    /// Removes the most recent bottle logged today.
    private func undoWater() {
        guard let last = todaysWater.first else { return }
        let date = last.date
        context.delete(last)
        try? context.save()
        Task { await HealthKitManager.shared.deleteWater(at: date) }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(title: "Steps", value: snapshot.steps?.wholeText ?? "–", symbol: "figure.walk", tint: .green)
            StatTile(title: "Exercise", value: snapshot.exerciseMin.map { "\($0.wholeText) min" } ?? "–", symbol: "flame.fill", tint: .orange)
            StatTile(title: "Resting heart rate", value: snapshot.restingHR.map { "\($0.wholeText) bpm" } ?? "–", symbol: "heart.fill", tint: .red)
            StatTile(title: "Sleep last night", value: snapshot.sleepHours.map { "\($0.text(1)) h" } ?? "–", symbol: "bed.double.fill", tint: .indigo)
        }
    }

    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Body").font(.headline)
                Spacer()
                Button("Log weight") { showWeightSheet = true }
                    .font(.subheadline)
            }
            HStack {
                VStack(alignment: .leading) {
                    Text(snapshot.weight.map { "\($0.value.text(1)) kg" } ?? "–").font(.title2.weight(.semibold))
                    Text(snapshot.weight.map { "Weight · \($0.date.formatted(date: .abbreviated, time: .omitted))" } ?? "No weight in Health yet")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(snapshot.bodyFat.map { "\(($0.value * 100).text(1)) %" } ?? "–").font(.title2.weight(.semibold))
                    Text("Body fat").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Loading

    private func load() async {
        let health = HealthKitManager.shared
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: start) ?? start

        var next = TodaySnapshot()
        next.steps = await health.aggregate(.steps, from: start, to: end)
        next.activeKcal = await health.aggregate(.activeKcal, from: start, to: end)
        next.basalKcal = await health.aggregate(.basalKcal, from: start, to: end)
        next.exerciseMin = await health.aggregate(.exerciseMin, from: start, to: end)
        next.restingHR = await health.latest(.restingHR)?.value
        next.sleepHours = await health.sleepNights(from: weekAgo, to: end).last(where: { $0.day == start })?.asleepHours
        next.weight = await health.latest(.weightKg)
        next.bodyFat = await health.latest(.bodyFat)
        snapshot = next
    }
}

/// Manual weigh-in, saved to Apple Health so the trend charts pick it up.
struct LogWeightView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var weight: Double?
    @State private var bodyFat: Double?
    @State private var date = Date()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("kg", value: $weight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Body fat")
                        Spacer()
                        TextField("optional", value: $bodyFat, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("%").foregroundStyle(.secondary)
                    }
                    DatePicker("When", selection: $date)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else {
                        Text("Saved to Apple Health. If you use a smart scale that already writes to Health, you don't need this.")
                    }
                }
            }
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled((weight ?? 0) <= 0 && (bodyFat ?? 0) <= 0)
                }
            }
        }
    }

    private func save() async {
        do {
            if let weight, weight > 0 {
                try await HealthKitManager.shared.save(.weightKg, value: weight, date: date)
            }
            if let bodyFat, bodyFat > 0 {
                try await HealthKitManager.shared.save(.bodyFat, value: bodyFat / 100, date: date)
            }
            dismiss()
        } catch {
            errorMessage = "Could not save to Health. Check that Health Agent may write weight in Settings › Health › Data Access."
        }
    }
}
