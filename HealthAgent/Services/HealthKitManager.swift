import Foundation
import HealthKit

/// A quantity type paired with the unit the app reads it in.
struct Metric {
    let id: HKQuantityTypeIdentifier
    let unit: HKUnit

    static let bpm = HKUnit.count().unitDivided(by: .minute())

    static let steps = Metric(id: .stepCount, unit: .count())
    static let distanceKm = Metric(id: .distanceWalkingRunning, unit: .meterUnit(with: .kilo))
    static let flights = Metric(id: .flightsClimbed, unit: .count())
    static let activeKcal = Metric(id: .activeEnergyBurned, unit: .kilocalorie())
    static let basalKcal = Metric(id: .basalEnergyBurned, unit: .kilocalorie())
    static let exerciseMin = Metric(id: .appleExerciseTime, unit: .minute())
    static let restingHR = Metric(id: .restingHeartRate, unit: bpm)
    static let walkingHR = Metric(id: .walkingHeartRateAverage, unit: bpm)
    static let heartRate = Metric(id: .heartRate, unit: bpm)
    static let hrvMs = Metric(id: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
    static let vo2Max = Metric(id: .vo2Max, unit: HKUnit(from: "ml/kg*min"))
    static let walkingSpeedMps = Metric(id: .walkingSpeed, unit: HKUnit.meter().unitDivided(by: .second()))
    static let steadiness = Metric(id: .appleWalkingSteadiness, unit: .percent())
    static let respiratory = Metric(id: .respiratoryRate, unit: bpm)
    static let headphoneDb = Metric(id: .headphoneAudioExposure, unit: .decibelAWeightedSoundPressureLevel())
    static let daylightMin = Metric(id: .timeInDaylight, unit: .minute())
    static let weightKg = Metric(id: .bodyMass, unit: .gramUnit(with: .kilo))
    static let bodyFat = Metric(id: .bodyFatPercentage, unit: .percent())
    static let leanMassKg = Metric(id: .leanBodyMass, unit: .gramUnit(with: .kilo))
    static let dietaryKcal = Metric(id: .dietaryEnergyConsumed, unit: .kilocalorie())

    static let allRead: [Metric] = [
        steps, distanceKm, flights, activeKcal, basalKcal, exerciseMin, restingHR, walkingHR,
        heartRate, hrvMs, vo2Max, walkingSpeedMps, steadiness, respiratory, headphoneDb,
        daylightMin, weightKg, bodyFat, leanMassKg, dietaryKcal,
    ]
}

/// One night of sleep, keyed by the day the user woke up.
struct SleepNight: Identifiable {
    let day: Date
    var asleep: TimeInterval = 0
    var core: TimeInterval = 0
    var deep: TimeInterval = 0
    var rem: TimeInterval = 0
    var awake: TimeInterval = 0
    var bedtime: Date?
    var wake: Date?

    var id: Date { day }
    var asleepHours: Double { asleep / 3600 }
}

struct ActivityDay {
    let activeKcal: Double
    let activeGoal: Double
    let exerciseMin: Double
    let exerciseGoal: Double
    let standHours: Double
    let standGoal: Double
}

/// All reads from and writes to Apple Health go through here. Read failures return
/// empty results, because HealthKit does not reveal whether read access was denied.
final class HealthKitManager {
    static let shared = HealthKitManager()

    let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        for metric in Metric.allRead { set.insert(HKQuantityType(metric.id)) }
        set.insert(HKCategoryType(.sleepAnalysis))
        set.insert(HKObjectType.activitySummaryType())
        return set
    }

    private var shareTypes: Set<HKSampleType> {
        let ids: [HKQuantityTypeIdentifier] = [
            .bodyMass, .bodyFatPercentage,
            .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal,
        ]
        return Set(ids.map { HKQuantityType($0) })
    }

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            Prefs.defaults.set(true, forKey: Prefs.healthRequested)
        } catch {
            print("HealthKit authorization failed: \(error)")
        }
    }

    // MARK: - Daily series

    /// One value per local day: a sum for cumulative types (steps, energy) and an
    /// average for the rest. HealthKit removes iPhone / Apple Watch overlap in sums.
    func daily(_ metric: Metric, from start: Date, to end: Date) async -> [Date: Double] {
        guard isAvailable else { return [:] }
        let type = HKQuantityType(metric.id)
        let cumulative = type.aggregationStyle == .cumulative
        let options: HKStatisticsOptions = cumulative ? .cumulativeSum : .discreteAverage
        let anchor = Calendar.current.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                var result: [Date: Double] = [:]
                collection?.enumerateStatistics(from: anchor, to: end) { stats, _ in
                    let quantity = cumulative ? stats.sumQuantity() : stats.averageQuantity()
                    if let quantity {
                        result[stats.startDate] = quantity.doubleValue(for: metric.unit)
                    }
                }
                continuation.resume(returning: result)
            }
            self.store.execute(query)
        }
    }

    /// The sum (cumulative types) or average (other types) over one period.
    func aggregate(_ metric: Metric, from start: Date, to end: Date) async -> Double? {
        guard isAvailable else { return nil }
        let type = HKQuantityType(metric.id)
        let cumulative = type.aggregationStyle == .cumulative
        let options: HKStatisticsOptions = cumulative ? .cumulativeSum : .discreteAverage
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, stats, _ in
                let quantity = cumulative ? stats?.sumQuantity() : stats?.averageQuantity()
                continuation.resume(returning: quantity?.doubleValue(for: metric.unit))
            }
            self.store.execute(query)
        }
    }

    /// The most recent sample of a type, such as the last weigh-in.
    func latest(_ metric: Metric) async -> (date: Date, value: Double)? {
        guard isAvailable else { return nil }
        let type = HKQuantityType(metric.id)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    continuation.resume(returning: (sample.endDate, sample.quantity.doubleValue(for: metric.unit)))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            self.store.execute(query)
        }
    }

    // MARK: - Sleep

    /// Sleep grouped into nights. A sample that ends before 6 pm belongs to that day's night.
    func sleepNights(from start: Date, to end: Date) async -> [SleepNight] {
        guard isAvailable else { return [] }
        let calendar = Calendar.current
        let type = HKCategoryType(.sleepAnalysis)
        let queryStart = start.addingTimeInterval(-12 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: end, options: [])

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            self.store.execute(query)
        }

        var nights: [Date: SleepNight] = [:]
        var asleepIntervals: [Date: [(Date, Date)]] = [:]

        for sample in samples {
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { continue }
            let day = calendar.startOfDay(for: sample.endDate.addingTimeInterval(6 * 3600))
            guard day >= calendar.startOfDay(for: start), day < end else { continue }
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            var night = nights[day] ?? SleepNight(day: day)

            switch value {
            case .inBed:
                continue
            case .awake:
                night.awake += duration
            case .asleepCore:
                night.core += duration
                asleepIntervals[day, default: []].append((sample.startDate, sample.endDate))
            case .asleepDeep:
                night.deep += duration
                asleepIntervals[day, default: []].append((sample.startDate, sample.endDate))
            case .asleepREM:
                night.rem += duration
                asleepIntervals[day, default: []].append((sample.startDate, sample.endDate))
            case .asleepUnspecified:
                asleepIntervals[day, default: []].append((sample.startDate, sample.endDate))
            @unknown default:
                continue
            }
            nights[day] = night
        }

        // Total time asleep is the union of the asleep intervals, so two sources
        // recording the same night are not counted twice.
        var result: [SleepNight] = []
        for (day, intervals) in asleepIntervals {
            guard !intervals.isEmpty else { continue }
            var night = nights[day] ?? SleepNight(day: day)
            let sorted = intervals.sorted { $0.0 < $1.0 }
            var total: TimeInterval = 0
            var currentStart = sorted[0].0
            var currentEnd = sorted[0].1
            for interval in sorted.dropFirst() {
                if interval.0 <= currentEnd {
                    currentEnd = max(currentEnd, interval.1)
                } else {
                    total += currentEnd.timeIntervalSince(currentStart)
                    currentStart = interval.0
                    currentEnd = interval.1
                }
            }
            total += currentEnd.timeIntervalSince(currentStart)
            night.asleep = total
            night.bedtime = sorted.first?.0
            night.wake = sorted.map { $0.1 }.max()
            // Ignore stray fragments shorter than an hour.
            if total >= 3600 { result.append(night) }
        }
        return result.sorted { $0.day < $1.day }
    }

    // MARK: - Activity rings

    func activityDays(from start: Date, to end: Date) async -> [ActivityDay] {
        guard isAvailable else { return [] }
        let calendar = Calendar.current
        var startComponents = calendar.dateComponents([.era, .year, .month, .day], from: start)
        startComponents.calendar = calendar
        let lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        var endComponents = calendar.dateComponents([.era, .year, .month, .day], from: lastDay)
        endComponents.calendar = calendar
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: startComponents, end: endComponents)

        return await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                let days = (summaries ?? []).map { summary in
                    ActivityDay(
                        activeKcal: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                        activeGoal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                        exerciseMin: summary.appleExerciseTime.doubleValue(for: .minute()),
                        exerciseGoal: summary.appleExerciseTimeGoal.doubleValue(for: .minute()),
                        standHours: summary.appleStandHours.doubleValue(for: .count()),
                        standGoal: summary.appleStandHoursGoal.doubleValue(for: .count())
                    )
                }
                continuation.resume(returning: days)
            }
            self.store.execute(query)
        }
    }

    // MARK: - Writing

    func save(_ metric: Metric, value: Double, date: Date, metadata: [String: Any]? = nil) async throws {
        let quantity = HKQuantity(unit: metric.unit, doubleValue: value)
        let sample = HKQuantitySample(type: HKQuantityType(metric.id), quantity: quantity, start: date, end: date, metadata: metadata)
        try await store.save(sample)
    }

    /// Saves a meal's energy and macros to Apple Health so other apps see them too.
    func saveMeal(_ meal: MealSnapshot) async {
        guard isAvailable else { return }
        let metadata: [String: Any] = [HKMetadataKeyFoodType: meal.summary.isEmpty ? meal.mealType : meal.summary]
        let entries: [(HKQuantityTypeIdentifier, HKUnit, Double)] = [
            (.dietaryEnergyConsumed, .kilocalorie(), meal.kcal),
            (.dietaryProtein, .gram(), meal.proteinG),
            (.dietaryCarbohydrates, .gram(), meal.carbsG),
            (.dietaryFatTotal, .gram(), meal.fatG),
        ]
        let samples: [HKObject] = entries.filter { $0.2 > 0 }.map { id, unit, value in
            HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: value),
                             start: meal.date, end: meal.date, metadata: metadata)
        }
        guard !samples.isEmpty else { return }
        do {
            try await store.save(samples)
        } catch {
            print("Saving meal to Health failed: \(error)")
        }
    }
}
