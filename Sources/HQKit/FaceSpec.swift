import Foundation

/// An sRGB color as numbers, for the face palette and its contrast rules.
public struct RGB: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// CIELAB L*: how light it looks, 0 to 100.
    public var lightness: Double {
        let y = luminance
        return y > 0.008856 ? 116 * pow(y, 1.0 / 3) - 16 : 903.3 * y
    }

    public func contrast(_ other: RGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// The faces' colors. Backgrounds come in two tiers (pastel and deep) of one OKLCH lightness and
/// chroma each, so every skin tone has backgrounds it stands out from; none is near orange or red.
public enum FacePalette {
    public static let backgrounds: [RGB] = [
        0xE3DCB3, 0xBCE7CE, 0xB2E5F2, 0xC7DCFF, 0xE3D2F9, 0xF8CDE0,
        0x59914D, 0x00958F, 0x3188BE, 0x7377C3, 0x9E68AB, 0xB3628A,
    ].map(RGB.init)
    /// Three light (CIELAB L* 90, 84, 78), three medium (71, 64, 60) and three deep (43, 33, 22) tones (T-293).
    public static let skins: [RGB] = [
        0xF9DFCB, 0xF2CBAA, 0xE8B993,
        0xD9A472, 0xC8905F, 0xBA8556,
        0x8B5A3A, 0x6C432B, 0x4B2D1D,
    ].map(RGB.init)

    public enum SkinGroup: Int, Sendable, CaseIterable { case light, medium, deep }

    /// Three tones in each group, light to deep.
    public static func group(ofSkin index: Int) -> SkinGroup { SkinGroup(rawValue: min(index / 3, 2)) ?? .deep }
    /// Six natural colors, then two playful ones.
    public static let hair: [RGB] = [0x2A1E19, 0x4B2E20, 0x7A4A2A, 0xC99A5B, 0xA9A4A0, 0xA8482A, 0x5B6CE0, 0xD06AB0].map(RGB.init)
    public static let clothes: [RGB] = [0x33363D, 0xEDEFF2, 0x3E6A9E, 0x2A8C88, 0x3F7F4E, 0x7546A0, 0xB0446F, 0xCDB894, 0x24324F, 0x6AA7E0].map(RGB.init)
    public static let inkDark = RGB(0x160C08)
    public static let inkLight = RGB(0xFFF4EA)
    public static let gold = RGB(0xE9B949)
    public static let lens = RGB(0x15161A)
    public static let visor = RGB(0x4FB3E8)
    public static let blush = RGB(0xF08AA0)
    public static let freckle = RGB(0x8B5A2B)
    public static let mouth = RGB(0x3B1F14)
    public static let tongue = RGB(0xE96A7E)
    public static let white = RGB(0xFFFFFF)
    public static let black = RGB(0x000000)

    /// Eyes and mouth: whichever ink stands out more from the skin.
    public static func ink(on skin: Int) -> RGB {
        skins[skin].contrast(inkDark) >= skins[skin].contrast(inkLight) ? inkDark : inkLight
    }
}

/// A session's face: which parts, from its id. Pure and stable: the same id and salt give the
/// same face everywhere. `SessionFace` in DesignKit draws it.
public struct FaceSpec: Sendable, Hashable {
    public enum Pattern: Int, Sendable, CaseIterable { case none, diagonal, stripes, rings, dots }
    public enum Shape: Int, Sendable, CaseIterable { case round, oval, square, soft }
    public enum Hair: Int, Sendable, CaseIterable { case bald, short, swoop, curly, bun, long, bob, afro, mohawk, spikes }
    public enum Headwear: Int, Sendable, CaseIterable { case none, beanie, cap, topHat, beret, party, headband, crown, bucket, hood }
    public enum Eyes: Int, Sendable, CaseIterable { case dots, happy, sleepy, wink, wide, glance }
    public enum Eyewear: Int, Sendable, CaseIterable { case none, round, square, shades, visor, monocle }
    public enum FacialHair: Int, Sendable, CaseIterable { case none, mustache, beard, goatee, stubble }
    public enum Mouth: Int, Sendable, CaseIterable { case smile, grin, flat, open, smirk, tongue }
    public enum Extra: Int, Sendable, CaseIterable { case headphones, earrings, freckles, blush }

    public var background: Int
    public var pattern: Pattern
    public var skin: Int
    public var shape: Shape
    public var hair: Hair
    public var hairColor: Int
    public var headwear: Headwear
    public var headwearColor: Int
    public var eyes: Eyes
    public var eyewear: Eyewear
    public var facialHair: FacialHair
    public var mouth: Mouth
    public var extras: Set<Extra>
    public var clothes: Int

    /// Shades and a visor cover the eyes.
    public var eyesHidden: Bool { eyewear == .shades || eyewear == .visor }

    public init(id: String, salt: Int = 0) {
        var random = SeededRandom(seed: Self.hash("\(id)#\(salt)"))
        background = random.index(FacePalette.backgrounds.count)
        pattern = random.pick([.none: 5, .diagonal: 2, .stripes: 2, .rings: 2, .dots: 2])
        skin = random.index(FacePalette.skins.count)
        shape = random.pick([.round: 3, .oval: 3, .square: 2, .soft: 2])
        hair = random.pick([.bald: 1, .short: 3, .swoop: 3, .curly: 3, .bun: 2, .long: 3, .bob: 3, .afro: 2, .mohawk: 1, .spikes: 1])
        hairColor = random.pick(Dictionary(uniqueKeysWithValues: (0..<FacePalette.hair.count).map { ($0, $0 < 6 ? 4 : 1) }))
        headwear = random.pick([.none: 12, .beanie: 2, .cap: 2, .topHat: 1, .beret: 1, .party: 1, .headband: 1, .crown: 1, .bucket: 1, .hood: 1])
        headwearColor = random.index(FacePalette.clothes.count)
        eyes = random.pick([.dots: 4, .happy: 2, .sleepy: 1, .wink: 1, .wide: 2, .glance: 1])
        eyewear = random.pick([.none: 10, .round: 2, .square: 2, .shades: 1, .visor: 1, .monocle: 1])
        facialHair = random.pick([.none: 10, .mustache: 2, .beard: 2, .goatee: 1, .stubble: 1])
        mouth = random.pick([.smile: 4, .grin: 2, .flat: 1, .open: 1, .smirk: 2, .tongue: 1])
        extras = []
        for extra in Extra.allCases where random.chance(extra == .blush ? 0.3 : 0.14) { extras.insert(extra) }
        clothes = random.index(FacePalette.clothes.count)

        // Rules, each redrawn from the same stream so the result stays stable.
        for _ in 0..<12 where !Self.fits(hair, under: headwear) {
            hair = random.pick([.bald: 1, .short: 3, .swoop: 3, .curly: 3, .bun: 2, .long: 3, .bob: 3, .afro: 2, .mohawk: 1, .spikes: 1])
        }
        if !Self.fits(hair, under: headwear) { hair = .short }
        if headwear != .none && headwear != .headband { extras.remove(.headphones) }
        if facialHair == .beard || facialHair == .stubble, mouth == .tongue { mouth = .smile }
        for _ in 0..<12 where FacePalette.skins[skin].contrast(FacePalette.backgrounds[background]) < Self.skinContrast {
            background = random.index(FacePalette.backgrounds.count)
        }
        if FacePalette.skins[skin].contrast(FacePalette.backgrounds[background]) < Self.skinContrast {
            background = FacePalette.backgrounds.indices.max { FacePalette.skins[skin].contrast(FacePalette.backgrounds[$0]) < FacePalette.skins[skin].contrast(FacePalette.backgrounds[$1]) } ?? 0
        }
    }

    /// Skin against the background, so the head's silhouette reads at 16 pt.
    public static let skinContrast = 1.4
    /// Eyes and mouth against the skin.
    public static let featureContrast = 3.0

    /// A hat that would cut a hairstyle badly: that hair is drawn again.
    public static func fits(_ hair: Hair, under headwear: Headwear) -> Bool {
        switch headwear {
        case .none, .headband: return true
        case .beanie, .cap, .bucket, .topHat: return ![.bun, .afro, .mohawk, .spikes].contains(hair)
        case .hood: return ![.bun, .afro, .mohawk, .spikes, .long].contains(hair)
        case .beret, .party, .crown: return ![.mohawk, .spikes].contains(hair)
        }
    }

    /// FNV-1a over the UTF-8 bytes.
    static func hash(_ text: String) -> UInt64 {
        var value: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x100000001b3
        }
        return value
    }

    /// The traits two open sessions must not share.
    public var signature: Int { background * 16 + headwear.rawValue }

    /// How many salts a new session's face tries.
    public static let tries = 16

    /// The salt that sets a new session's face apart from the open sessions' (T-293): the first of `tries` whose background
    /// and headwear none of them shares, with a skin tone none of them has, in the skin group they show least. When no
    /// salt meets all three, the group goes first, then the tone.
    public static func salt(for id: String, among open: [FaceSpec]) -> Int {
        let signatures = Set(open.map(\.signature))
        let tones = Set(open.map(\.skin))
        let groups = Dictionary(grouping: open) { FacePalette.group(ofSkin: $0.skin) }.mapValues(\.count)
        let fewest = FacePalette.SkinGroup.allCases.map { groups[$0] ?? 0 }.min() ?? 0
        let faces = (0..<tries).map { FaceSpec(id: id, salt: $0) }
        let rules: [(FaceSpec) -> Bool] = [
            { !signatures.contains($0.signature) && !tones.contains($0.skin) && groups[FacePalette.group(ofSkin: $0.skin), default: 0] == fewest },
            { !signatures.contains($0.signature) && !tones.contains($0.skin) },
            { !signatures.contains($0.signature) },
        ]
        for rule in rules {
            if let salt = faces.firstIndex(where: rule) { return salt }
        }
        return 0
    }
}

/// SplitMix64: small, fast and the same on every run.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func index(_ count: Int) -> Int { Int(next() % UInt64(count)) }

    mutating func chance(_ probability: Double) -> Bool { unit() < probability }

    /// A weighted pick, in a fixed order so the stream gives the same answer every run.
    mutating func pick<T: Hashable & RawRepresentable>(_ weights: [T: Int]) -> T where T.RawValue == Int {
        let ordered = weights.sorted { $0.key.rawValue < $1.key.rawValue }
        var roll = Int(next() % UInt64(ordered.reduce(0) { $0 + $1.value }))
        for (value, weight) in ordered {
            if roll < weight { return value }
            roll -= weight
        }
        return ordered[0].key
    }

    mutating func pick(_ weights: [Int: Int]) -> Int {
        let ordered = weights.sorted { $0.key < $1.key }
        var roll = Int(next() % UInt64(ordered.reduce(0) { $0 + $1.value }))
        for (value, weight) in ordered {
            if roll < weight { return value }
            roll -= weight
        }
        return ordered[0].key
    }
}
