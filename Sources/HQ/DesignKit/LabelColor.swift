import AppKit
import SwiftUI

/// A tag's or a project's color: one of the Mac's system colors, picked by the user or given by the name.
nonisolated enum LabelColor: String, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var baseNS: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .teal: .systemTeal
        case .cyan: .systemCyan
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .brown: .systemBrown
        case .gray: .systemGray
        }
    }

    /// The label's text: darker in light mode, lighter in dark mode, readable on its fill.
    var textNS: NSColor {
        let base = baseNS
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? base.blended(withFraction: 0.25, of: .white) ?? base
                : base.blended(withFraction: self == .yellow ? 0.55 : 0.42, of: .black) ?? base
        }
    }

    var fillNS: NSColor { baseNS.withAlphaComponent(0.16) }
    var base: Color { Color(nsColor: baseNS) }
    var text: Color { Color(nsColor: textNS) }
    var fill: Color { Color(nsColor: fillNS) }

    /// A filled dot, for menus.
    var swatch: NSImage {
        let side = Metric.glyph - 2
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { [baseNS] rect in
            baseNS.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// The color a name gets until the user picks one, the same on every launch.
    static func automatic(_ name: String) -> LabelColor {
        let palette: [LabelColor] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .red, .mint, .cyan, .brown]
        var hash: UInt64 = 5381
        for byte in name.lowercased().utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return palette[Int(hash % UInt64(palette.count))]
    }
}

/// A label on a neutral capsule, its color only in its mark: a dot for `#perf`, the tinted symbol for a project.
struct LabelChip: View {
    let text: String
    let color: LabelColor
    var icon: KitIcon?

    var body: some View {
        HStack(spacing: Space.xs + 1) {
            if icon == .tag || icon == nil {
                Circle().fill(color.base).frame(width: Metric.labelDot, height: Metric.labelDot)
            } else if let icon {
                icon.image.imageScale(.small).foregroundStyle(color.text)
            }
            Text(text).lineLimit(1).foregroundStyle(.secondary)
        }
        .labelCapsule()
    }
}

/// A fact on a label's capsule, without a color: a session's folder and branch, its model and context (T-446).
struct FactChip: View {
    let text: String
    var truncation: Text.TruncationMode = .tail

    var body: some View {
        Text(text).lineLimit(1).truncationMode(truncation).foregroundStyle(.secondary).monospacedDigit()
            .labelCapsule()
    }
}

private extension View {
    func labelCapsule() -> some View {
        kitType(.secondary)
            .fontWeight(.medium)
            .padding(.horizontal, Space.xs + 2)
            .frame(height: Metric.chipHeight)
            .background(Ink.labelFill, in: Capsule())
    }
}
