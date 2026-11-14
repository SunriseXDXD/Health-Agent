import SwiftUI
import SwiftData

/// The full meal log, newest day first.
struct MealsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: AppRouter
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @State private var editing: MealEntry?

    private var days: [(day: Date, meals: [MealEntry])] {
        let grouped = Dictionary(grouping: meals) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.map { (day: $0.key, meals: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            Group {
                if meals.isEmpty {
                    ContentUnavailableView("No meals yet", systemImage: "fork.knife",
                                           description: Text("Log lunch or dinner with a photo or a short description."))
                } else {
                    List {
                        ForEach(days, id: \.day) { group in
                            Section {
                                ForEach(group.meals) { meal in
                                    Button { editing = meal } label: { row(meal) }
                                        .buttonStyle(.plain)
                                }
                                .onDelete { offsets in
                                    for index in offsets { context.delete(group.meals[index]) }
                                    try? context.save()
                                }
                            } header: {
                                HStack {
                                    Text(group.day.formatted(date: .complete, time: .omitted))
                                    Spacer()
                                    Text("\(group.meals.reduce(0) { $0 + $1.kcal }.wholeText) kcal")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Meals")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(MealType.allCases) { type in
                            Button(type.title, systemImage: type.symbol) { router.mealToLog = type }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { meal in
                AddMealView(mealType: meal.mealType, existing: meal)
            }
        }
    }

    private func row(_ meal: MealEntry) -> some View {
        HStack(spacing: 12) {
            if let data = meal.photo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: meal.mealType.symbol)
                    .frame(width: 52, height: 52)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.summary).lineLimit(1)
                Text("\(meal.mealType.title) · P \(meal.proteinG.wholeText) · C \(meal.carbsG.wholeText) · F \(meal.fatG.wholeText) g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(meal.kcal.wholeText)")
                .font(.subheadline.weight(.semibold))
            Text("kcal").font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
