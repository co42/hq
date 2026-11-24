import Foundation
import Observation

/// What Settings › Appearance turns on, and how strong (DESIGN.md §12, Look): the sky and the light of cards in a state.
/// Views read it in their body, so a change redraws them.
@Observable final class Look {
    static let shared = Look()

    /// The strengths a slider runs between; 1 is the look as designed.
    static let strengths: ClosedRange<Double> = 0.25...2

    /// Where the sky shows: nowhere, the top of the page, or the top and the window's foot.
    enum Sky: String, CaseIterable, Identifiable {
        case none, top, topAndBottom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: "None"
            case .top: "Top"
            case .topAndBottom: "Top and Bottom"
            }
        }
    }

    var sky: Sky { didSet { Prefs.defaults.set(sky.rawValue, forKey: Key.sky) } }
    /// Both parts of the sky.
    var skyStrength: Double { didSet { Prefs.defaults.set(skyStrength, forKey: Key.skyStrength) } }
    /// A card that needs the user, or failed, lights up from its face's side; a working one takes a faint accent wash.
    var stateLight: Bool { didSet { Prefs.defaults.set(stateLight, forKey: Key.stateLight) } }
    var stateStrength: Double { didSet { Prefs.defaults.set(stateStrength, forKey: Key.stateStrength) } }

    private enum Key {
        static let sky = "look.sky"
        static let skyStrength = "look.skyStrength"
        static let stateLight = "look.stateLight"
        static let stateStrength = "look.stateStrength"
    }

    private init() {
        let defaults = Prefs.defaults
        sky = (defaults.string(forKey: Key.sky)).flatMap(Sky.init(rawValue:)) ?? .topAndBottom
        skyStrength = Self.clamped(defaults.object(forKey: Key.skyStrength) as? Double ?? 1)
        stateLight = defaults.object(forKey: Key.stateLight) as? Bool ?? true
        stateStrength = Self.clamped(defaults.object(forKey: Key.stateStrength) as? Double ?? 1)
    }

    private static func clamped(_ value: Double) -> Double { min(max(value, strengths.lowerBound), strengths.upperBound) }
}
