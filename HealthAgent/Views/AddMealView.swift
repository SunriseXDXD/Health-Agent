import SwiftUI
import SwiftData
import PhotosUI

/// Logs a new meal or edits an existing one. A photo and/or a line of text goes to
/// DeepSeek for an estimate; every number can be corrected by hand before saving.
struct AddMealView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allMeals: [MealEntry]

    private let existing: MealEntry?

    @State private var mealType: MealType
    @State private var date: Date
    @State private var note: String
    @State private var summary: String
    @State private var kcal: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double
    @State private var fiber: Double
    @State private var items: [FoodItem]
    @State private var confidence: String
    @State private var analysisNotes: String
    @State private var source: String
    @State private var image: UIImage?

    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isAnalyzing = false
    @State private var errorMessage: String?

    init(mealType: MealType, existing: MealEntry? = nil) {
        self.existing = existing
        _mealType = State(initialValue: existing?.mealType ?? mealType)
        _date = State(initialValue: existing?.date ?? Date())
        _note = State(initialValue: existing?.userNote ?? "")
        _summary = State(initialValue: existing?.summary ?? "")
        _kcal = State(initialValue: existing?.kcal ?? 0)
        _protein = State(initialValue: existing?.proteinG ?? 0)
        _carbs = State(initialValue: existing?.carbsG ?? 0)
        _fat = State(initialValue: existing?.fatG ?? 0)
        _fiber = State(initialValue: existing?.fiberG ?? 0)
        _items = State(initialValue: existing?.items ?? [])
        _confidence = State(initialValue: existing?.confidence ?? "")
        _analysisNotes = State(initialValue: existing?.analysisNotes ?? "")
        _source = State(initialValue: existing?.source ?? "manual")
        _image = State(initialValue: existing?.photo.flatMap { UIImage(data: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                mealSection
                photoSection
                analyzeSection
                if !items.isEmpty { itemsSection }
                nutritionSection
            }
            .navigationTitle(existing == nil ? "Log a meal" : "Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(kcal <= 0 && summary.isEmpty)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image = $0 }
                    .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                        image = picked
                    }
                }
            }
            .alert("Could not estimate the meal", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var mealSection: some View {
        Section {
            Picker("Meal", selection: $mealType) {
                ForEach(MealType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
            DatePicker("When", selection: $date)
        }
    }

    private var photoSection: some View {
        Section("Photo") {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Button {
                    showCamera = true
                } label: {
                    Label("Camera", systemImage: "camera")
                }
                .buttonStyle(.bordered)
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Library", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                if image != nil {
                    Spacer()
                    Button("Remove", role: .destructive) { image = nil }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private var analyzeSection: some View {
        Section {
            TextField("What did you eat? e.g. beef noodles, a boiled egg, iced tea", text: $note, axis: .vertical)
                .lineLimit(2...5)
            Button {
                Task { await analyze() }
            } label: {
                HStack {
                    if isAnalyzing { ProgressView() }
                    Text(isAnalyzing ? "Estimating…" : "Estimate nutrition with DeepSeek")
                }
            }
            .disabled(isAnalyzing || (image == nil && note.trimmingCharacters(in: .whitespaces).isEmpty))
        } header: {
            Text("Description")
        } footer: {
            if !analysisNotes.isEmpty {
                Text("\(confidence.capitalized) confidence. \(analysisNotes)")
            } else {
                Text("Add a photo, a description, or both. You can also skip the estimate and type the numbers below.")
            }
        }
    }

    private var itemsSection: some View {
        Section("Estimated items") {
            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.name)
                        Text(item.portion).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(item.kcal.wholeText) kcal").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var nutritionSection: some View {
        Section("Nutrition") {
            TextField("Name of the meal", text: $summary)
            numberRow("Energy", value: $kcal, unit: "kcal")
            numberRow("Protein", value: $protein, unit: "g")
            numberRow("Carbohydrate", value: $carbs, unit: "g")
            numberRow("Fat", value: $fat, unit: "g")
            numberRow("Fibre", value: $fiber, unit: "g")
        }
    }

    private func numberRow(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
        }
    }

    private func analyze() async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let estimate = try await DeepSeekClient.analyzeMeal(description: note, image: image, mealType: mealType)
            summary = estimate.summary
            items = estimate.items
            kcal = estimate.kcal.rounded()
            protein = estimate.proteinG.rounded()
            carbs = estimate.carbsG.rounded()
            fat = estimate.fatG.rounded()
            fiber = estimate.fiberG.rounded()
            confidence = estimate.confidence
            analysisNotes = estimate.notes
            source = "deepseek"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        let isNew = existing == nil
        let entry = existing ?? MealEntry(date: date, mealType: mealType)
        entry.date = date
        entry.mealType = mealType
        entry.userNote = note
        entry.summary = summary.isEmpty ? mealType.title : summary
        entry.kcal = kcal
        entry.proteinG = protein
        entry.carbsG = carbs
        entry.fatG = fat
        entry.fiberG = fiber
        entry.items = items
        entry.confidence = confidence
        entry.analysisNotes = analysisNotes
        entry.source = source
        entry.photo = image?.resized(maxSide: 1024).jpegData(compressionQuality: 0.6)
        if isNew { context.insert(entry) }
        try? context.save()

        let snapshot = entry.snapshot
        var snapshots = allMeals.map(\.snapshot)
        if isNew { snapshots.append(snapshot) }
        let writeToHealth = isNew && Prefs.defaults.bool(forKey: Prefs.writeToHealth)
        Task {
            if writeToHealth { await HealthKitManager.shared.saveMeal(snapshot) }
            await ReminderManager.reschedule(loggedMeals: snapshots)
        }
        dismiss()
    }
}
