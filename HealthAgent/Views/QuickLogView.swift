import SwiftUI
import SwiftData
import PhotosUI

/// Photo-only meal logging: take or pick a picture, Gemini works out the nutrition,
/// and the meal is saved without any typing.
struct QuickLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allMeals: [MealEntry]

    enum Phase: Equatable {
        case pick
        case analyzing
        case done
        case failed(String)
    }

    @State private var mealType: MealType
    @State private var image: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showManual = false
    @State private var phase: Phase = .pick
    @State private var saved: MealEntry?
    @State private var editing: MealEntry?

    init(mealType: MealType) {
        _mealType = State(initialValue: mealType)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(phase == .analyzing || phase == .done)

                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    phaseContent
                }
                .padding()
            }
            .navigationTitle("Log \(mealType.title.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if phase != .done {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if phase == .done {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { picked in
                    image = picked
                    Task { await analyze() }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                        image = picked
                        await analyze()
                    }
                }
            }
            .sheet(isPresented: $showManual, onDismiss: { dismiss() }) {
                AddMealView(mealType: mealType)
            }
            .sheet(item: $editing) { meal in
                AddMealView(mealType: meal.mealType, existing: meal)
            }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .pick:
            photoButtons
            Text("Take or choose one photo of the meal. The calories and macros are worked out and saved for you.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Type it in instead") { showManual = true }
                .font(.footnote)
        case .analyzing:
            ProgressView("Working out the nutrition…")
                .padding(.top, 8)
        case .done:
            if let saved { resultCard(saved) }
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await analyze() } }
                .buttonStyle(.borderedProminent)
            photoButtons
            Button("Type it in instead") { showManual = true }
                .font(.footnote)
        }
    }

    private var photoButtons: some View {
        HStack(spacing: 12) {
            Button {
                showCamera = true
            } label: {
                Label("Camera", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Photo library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
    }

    private func resultCard(_ meal: MealEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            Text(meal.summary).font(.title3.weight(.semibold))
            Text("\(meal.kcal.wholeText) kcal")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Protein \(meal.proteinG.wholeText) g · Carbs \(meal.carbsG.wholeText) g · Fat \(meal.fatG.wholeText) g")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Divider()
            ForEach(meal.items) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.name)
                        Text(item.portion).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(item.kcal.wholeText) kcal").foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            if !meal.analysisNotes.isEmpty {
                Text("\(meal.confidence.capitalized) confidence. \(meal.analysisNotes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Something's off? Adjust it") { editing = meal }
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @MainActor
    private func analyze() async {
        guard let image, phase != .analyzing else { return }
        phase = .analyzing
        do {
            let estimate = try await GeminiClient.analyzeMeal(description: "", image: image, mealType: mealType)
            guard estimate.kcal > 0 else {
                phase = .failed("No food could be recognised in that photo. Try another one.")
                return
            }
            let entry = MealEntry(date: Date(), mealType: mealType)
            entry.summary = estimate.summary
            entry.kcal = estimate.kcal.rounded()
            entry.proteinG = estimate.proteinG.rounded()
            entry.carbsG = estimate.carbsG.rounded()
            entry.fatG = estimate.fatG.rounded()
            entry.fiberG = estimate.fiberG.rounded()
            entry.items = estimate.items
            entry.confidence = estimate.confidence
            entry.analysisNotes = estimate.notes
            entry.source = "gemini"
            entry.photo = image.resized(maxSide: 1024).jpegData(compressionQuality: 0.6)
            context.insert(entry)
            try? context.save()
            saved = entry
            phase = .done

            let snapshot = entry.snapshot
            let snapshots = allMeals.map(\.snapshot) + [snapshot]
            let writeToHealth = Prefs.defaults.bool(forKey: Prefs.writeToHealth)
            Task {
                if writeToHealth { await HealthKitManager.shared.saveMeal(snapshot) }
                await ReminderManager.reschedule(loggedMeals: snapshots)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
