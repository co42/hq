import AppKit
import SwiftUI

/// Type roles (DESIGN.md §12). The system font with macOS text styles.
enum KitType {
    /// Rows, cards, subtasks: Body 13.
    case title
    /// Top-level tasks, card names: Body 13 semibold.
    case titleStrong
    /// Unread card names: Body 13 bold.
    case titleBold
    /// Second lines, chips, tags: Subheadline 11.
    case secondary
    /// Durations, counts, dates: Subheadline 11 with monospaced digits.
    case meta
    /// Keys (T-12), branches, paths: Subheadline 11 monospaced.
    case key
    /// Tool input and code: Callout 12 monospaced.
    case code
    /// Body text.
    case body
    case callout
    /// Section headers on the page: Title 3 15 semibold.
    case section
    /// A section's title beside its tile: Title 2 17 bold.
    case sectionTitle
    /// The page's title, the day: Large Title 26 bold, and its date beside it, regular.
    case largeTitle, largeTitleLight
    /// The modal's header title: Headline 13.
    case header
    /// Labels in the modal (On it, Subtasks): Subheadline 11 semibold.
    case groupLabel
    /// A markdown editor: Body 13 monospaced.
    case editor
    /// Quick Open's field, Title 2 17.
    case field
    /// The modal's item title, Title 1 22 semibold.
    case pageTitle
    /// Markdown headings: Title 2, Title 3, then Headline.
    case heading1, heading2, heading3
    /// A markdown table's header row: Callout 12 semibold.
    case tableHeader

    /// The role's text style, weight and design; its size is the style's times View › Zoom.
    private var parts: (style: NSFont.TextStyle, weight: Font.Weight, design: Font.Design) {
        switch self {
        case .title, .body: (.body, .regular, .default)
        case .titleStrong: (.body, .semibold, .default)
        case .titleBold, .header, .heading3: (.body, .bold, .default)
        case .secondary, .meta: (.subheadline, .regular, .default)
        case .key: (.subheadline, .regular, .monospaced)
        case .code: (.callout, .regular, .monospaced)
        case .editor: (.body, .regular, .monospaced)
        case .callout: (.callout, .regular, .default)
        case .section, .heading2: (.title3, .semibold, .default)
        case .sectionTitle: (.title2, .bold, .default)
        case .largeTitle: (.largeTitle, .bold, .default)
        case .largeTitleLight: (.largeTitle, .regular, .default)
        case .groupLabel: (.subheadline, .semibold, .default)
        case .field: (.title2, .regular, .default)
        case .pageTitle: (.title1, .semibold, .default)
        case .heading1: (.title2, .semibold, .default)
        case .tableHeader: (.callout, .semibold, .default)
        }
    }

    /// The size a text style has at 100%, times the zoom.
    static func size(_ style: NSFont.TextStyle) -> CGFloat { NSFont.preferredFont(forTextStyle: style).pointSize * Zoom.factor }

    var font: Font {
        let parts = parts
        let font = Font.system(size: Self.size(parts.style), weight: parts.weight, design: parts.design)
        return self == .meta ? font.monospacedDigit() : font
    }

    /// For AppKit views (the outline, Quick Open's field, the editor): made once per role, since rows ask on every draw.
    var nsFont: NSFont {
        if let font = Self.fonts[self] { return font }
        let font = makeFont()
        Self.fonts[self] = font
        return font
    }

    private static var fonts: [KitType: NSFont] = [:]

    /// The zoom changed: fonts are made again at the new size.
    static func resetFonts() { fonts = [:] }

    private func makeFont() -> NSFont {
        let body = Self.size(.body)
        let small = Self.size(.subheadline)
        switch self {
        case .field: return .systemFont(ofSize: Self.size(.title2))
        case .titleStrong: return .systemFont(ofSize: body, weight: .semibold)
        case .titleBold: return .systemFont(ofSize: body, weight: .bold)
        case .secondary: return .systemFont(ofSize: small)
        case .meta: return .monospacedDigitSystemFont(ofSize: small, weight: .regular)
        case .key: return .monospacedSystemFont(ofSize: small, weight: .regular)
        case .groupLabel: return .systemFont(ofSize: small, weight: .semibold)
        case .editor: return .monospacedSystemFont(ofSize: body, weight: .regular)
        case .code: return .monospacedSystemFont(ofSize: Self.size(.callout), weight: .regular)
        case .section: return .systemFont(ofSize: Self.size(.title3), weight: .semibold)
        default: return .systemFont(ofSize: body)
        }
    }
}

extension View {
    func kitType(_ type: KitType) -> some View { font(type.font) }
}

extension Text {
    func kitType(_ type: KitType) -> Text { font(type.font) }
}
