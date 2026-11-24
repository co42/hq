import AppKit
import Observation

/// What Settings › Appearance turns on, and how strong (DESIGN.md §12, Look): the sky and the light of cards in a state.
/// Views read it in their body, so a change redraws them.
@Observable final class Look {
    static let shared = Look()

    /// The strengths a slider runs between, as a share of the look as first designed.
    static let strengths: ClosedRange<Double> = 0.25...2
    /// A slider moves in steps of 5% of the look as designed.
    static let step = 0.05

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

    var sky: Sky { didSet { save(sky.rawValue, Key.sky) } }
    /// Both parts of the sky.
    var skyStrength: Double { didSet { save(skyStrength, Key.skyStrength) } }
    /// A card that needs the user, or failed, lights up from its face's side and glows.
    var stateLight: Bool { didSet { save(stateLight, Key.stateLight) } }
    var stateStrength: Double { didSet { save(stateStrength, Key.stateStrength) } }
    /// A card whose session or team works takes the accent from its face's side, without a glow.
    var workingLight: Bool { didSet { save(workingLight, Key.workingLight) } }
    var workingStrength: Double { didSet { save(workingStrength, Key.workingStrength) } }
    /// Cards catch light: a rim along their top edge, a faint fall of light down their fill, softer and deeper shadows.
    var litCards: Bool { didSet { save(litCards, Key.litCards) } }
    var litStrength: Double { didSet { save(litStrength, Key.litStrength) } }
    /// Cards and the outline's trays let the sky through.
    var frosted: Bool { didSet { save(frosted, Key.frosted) } }
    var frostStrength: Double { didSet { save(frostStrength, Key.frostStrength) } }
    /// Section and kind tiles with a gloss, progress bars with light, a card's face with a soft shadow.
    var richMarks: Bool { didSet { save(richMarks, Key.richMarks) } }

    /// Increase Contrast keeps cards solid and unlit: their edges carry them.
    private var plain: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }

    /// A card's light while lit cards are on.
    var lit: Double? { litCards && !plain ? litStrength : nil }
    /// How much of a card's own color stays while frosted: 1 is solid.
    var cardOpacity: Double { frosted && !plain ? max(0.35, 1 - 0.28 * frostStrength) : 1 }

    /// Posted on any change, for the AppKit views that draw cards and bars.
    static let changed = Notification.Name("Look.changed")

    private enum Key {
        static let sky = "look.sky"
        static let skyStrength = "look.skyStrength"
        static let stateLight = "look.stateLight"
        static let stateStrength = "look.stateStrength"
        static let workingLight = "look.workingLight"
        static let workingStrength = "look.workingStrength"
        static let litCards = "look.litCards"
        static let litStrength = "look.litStrength"
        static let frosted = "look.frosted"
        static let frostStrength = "look.frostStrength"
        static let richMarks = "look.richMarks"
    }

    private init() {
        let defaults = Prefs.defaults
        func strength(_ key: String, _ standard: Double) -> Double { Self.clamped(defaults.object(forKey: key) as? Double ?? standard) }
        func on(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        sky = (defaults.string(forKey: Key.sky)).flatMap(Sky.init(rawValue:)) ?? .topAndBottom
        skyStrength = strength(Key.skyStrength, 0.8)
        stateLight = on(Key.stateLight)
        stateStrength = strength(Key.stateStrength, 0.5)
        workingLight = on(Key.workingLight)
        workingStrength = strength(Key.workingStrength, 1.3)
        litCards = on(Key.litCards)
        litStrength = strength(Key.litStrength, 0.4)
        frosted = defaults.object(forKey: Key.frosted) as? Bool ?? false
        frostStrength = strength(Key.frostStrength, 1)
        richMarks = defaults.object(forKey: Key.richMarks) as? Bool ?? false
    }

    private func save(_ value: Any, _ key: String) {
        Prefs.defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    private static func clamped(_ value: Double) -> Double { min(max(value, strengths.lowerBound), strengths.upperBound) }
}
