import Foundation
import SwiftData

/// The two containers water is usually drunk from. Their sizes are set in Settings.
enum WaterBottle: String, CaseIterable, Identifiable {
    case metal
    case large

    var id: String { rawValue }

    var defaultMl: Double {
        switch self {
        case .metal: return 500
        case .large: return 1500
        }
    }

    /// The size currently set for this bottle, in millilitres.
    var ml: Double {
        let key = self == .metal ? Prefs.smallBottleMl : Prefs.largeBottleMl
        let stored = Prefs.defaults.double(forKey: key)
        return stored > 0 ? stored : defaultMl
    }

    var title: String {
        switch self {
        case .metal: return "Metal bottle"
        case .large: return "Bottled water"
        }
    }

    var sizeLabel: String { WaterBottle.label(ml) }

    /// "500 ml" below a litre, "1.5 L" from a litre up.
    static func label(_ ml: Double) -> String {
        ml < 1000 ? "\(Int(ml.rounded())) ml" : String(format: "%g L", (ml / 10).rounded() / 100)
    }
}

/// One finished bottle of water. The volume is stored with the entry, so changing a
/// bottle's size later does not alter what was already logged.
@Model
final class WaterEntry {
    var date: Date = Date()
    var ml: Double = 0
    var kind: String = WaterBottle.metal.rawValue

    init(date: Date, ml: Double, kind: WaterBottle) {
        self.date = date
        self.ml = ml
        self.kind = kind.rawValue
    }

    var snapshot: WaterSnapshot { WaterSnapshot(date: date, ml: ml, kind: kind) }
}

struct WaterSnapshot: Codable, Hashable {
    var date: Date
    var ml: Double
    var kind: String
}
