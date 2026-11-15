import Foundation
import SwiftData

/// The two containers water is usually drunk from.
enum WaterBottle: String, CaseIterable, Identifiable {
    case metal
    case large

    var id: String { rawValue }

    var ml: Double {
        switch self {
        case .metal: return 500
        case .large: return 1500
        }
    }

    var title: String {
        switch self {
        case .metal: return "Metal bottle"
        case .large: return "Bottled water"
        }
    }

    var sizeLabel: String {
        switch self {
        case .metal: return "500 ml"
        case .large: return "1.5 L"
        }
    }
}

/// One finished bottle of water.
@Model
final class WaterEntry {
    var date: Date = Date()
    var ml: Double = 0

    init(date: Date, ml: Double) {
        self.date = date
        self.ml = ml
    }

    var snapshot: WaterSnapshot { WaterSnapshot(date: date, ml: ml) }
}

struct WaterSnapshot: Codable, Hashable {
    var date: Date
    var ml: Double
}
