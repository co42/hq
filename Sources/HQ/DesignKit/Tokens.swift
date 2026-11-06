import AppKit
import HQKit
import SwiftUI

// Two layers: Ink gives system colors a meaning; Metric, Radius and Motion are the scales.
// HQ uses the Mac's accent and system colors only, so it follows Light, Dark, Increase
// Contrast and the accent people chose, like Apple's own apps.

/// Meaning tokens. Parts and views read only these.
enum Ink {
    /// The accent the person chose for their Mac.
    static let accent = Color.accentColor
    static let accentText = Color.accentColor
    /// Text and symbols on an accent fill.
    static let onAccent = Color(nsColor: .alternateSelectedControlTextColor)

    /// Waiting on the user: a session that asks, a task in Review, a PR waiting for review.
    static let needsYou = Color(nsColor: .systemOrange)
    static let needsYouNS = NSColor.systemOrange
    /// Orange text: a deeper shade in light mode, so small text reads (4.5:1).
    static let needsYouTextNS = NSColor(name: "needsYouText") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .systemOrange
            : NSColor.systemOrange.blended(withFraction: 0.42, of: .black) ?? .systemOrange
    }
    static let needsYouText = Color(nsColor: needsYouTextNS)
    /// A tinted box or tag that needs the user.
    static let needsYouFill = Color(nsColor: .systemOrange).opacity(0.13)
    /// New since the user looked.
    static let unread = Color(nsColor: .systemBlue)
    static let unreadNS = NSColor.systemBlue
    static let unreadTextNS = NSColor(name: "unreadText") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.systemBlue.blended(withFraction: 0.18, of: .white) ?? .systemBlue
            : NSColor.systemBlue.blended(withFraction: 0.2, of: .black) ?? .systemBlue
    }
    static let unreadText = Color(nsColor: unreadTextNS)
    static let unreadFill = Color(nsColor: .systemBlue).opacity(0.12)
    /// Stopped on an error.
    static let failed = Color(nsColor: .systemRed)
    static let failedNS = NSColor.systemRed
    static let failedTextNS = NSColor(name: "failedText") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.systemRed.blended(withFraction: 0.12, of: .white) ?? .systemRed
            : NSColor.systemRed.blended(withFraction: 0.25, of: .black) ?? .systemRed
    }
    static let failedText = Color(nsColor: failedTextNS)
    static let failedFill = Color(nsColor: .systemRed).opacity(0.11)
    /// Task in progress.
    static let doing = Color(nsColor: .systemYellow)
    static let doingNS = NSColor.systemYellow
    /// Done, approved, checks passed: green symbols beside primary words.
    static let done = Color(nsColor: .systemGreen)
    static let doneNS = NSColor.systemGreen
    /// A merged pull request.
    static let merged = Color(nsColor: .systemPurple)

    /// Quiet states: idle, todo.
    static let quiet = HierarchicalShapeStyle.secondary
    /// Quieter states: ended.
    static let quieter = HierarchicalShapeStyle.tertiary

    /// One color per appearance: light, dark, and their Increase Contrast variants.
    static func dynamic(_ name: String, light: NSColor, dark: NSColor, lightHigh: NSColor? = nil, darkHigh: NSColor? = nil) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
            case .darkAqua: dark
            case .accessibilityHighContrastAqua: lightHigh ?? light
            case .accessibilityHighContrastDarkAqua: darkHigh ?? dark
            default: light
            }
        }
    }

    private static func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> NSColor { NSColor(white: white, alpha: alpha) }

    /// The page under the cards: a soft neutral, a step below the cards in both modes.
    static let contentNS = dynamic("canvas", light: NSColor(srgbRed: 0.953, green: 0.953, blue: 0.961, alpha: 1),
                                   dark: NSColor(srgbRed: 0.078, green: 0.078, blue: 0.086, alpha: 1),
                                   lightHigh: gray(0.92), darkHigh: gray(0.04))
    static let content = Color(nsColor: contentNS)
    /// A note's text.
    static let text = Color(nsColor: .textBackgroundColor)
    /// Raised cards: session cards, the PR, file and artifact cards, the lists: white, or an elevated gray in dark mode.
    static let surfaceNS = dynamic("surface", light: .white, dark: NSColor(srgbRed: 0.137, green: 0.137, blue: 0.149, alpha: 1),
                                   darkHigh: NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1))
    static let card = Color(nsColor: surfaceNS)
    /// A card's edge: a hairline that is a highlight in dark mode.
    static let cardHairlineNS = dynamic("hairline", light: gray(0, 0.07), dark: gray(1, 0.08), lightHigh: gray(0, 0.32), darkHigh: gray(1, 0.36))
    static let cardHairline = Color(nsColor: cardHairlineNS)
    /// A line between rows in a card, inset from the text.
    static let rowRuleNS = dynamic("rowRule", light: gray(0, 0.06), dark: gray(1, 0.06), lightHigh: gray(0, 0.2), darkHigh: gray(1, 0.24))
    static let rowRule = Color(nsColor: rowRuleNS)
    /// A card's shadow: a tight contact shadow and a soft far one.
    static let shadowNearNS = dynamic("shadowNear", light: gray(0, 0.06), dark: gray(0, 0.5))
    static let shadowNear = Color(nsColor: shadowNearNS)
    static let shadowFarNS = dynamic("shadowFar", light: gray(0, 0.07), dark: gray(0, 0.32))
    static let shadowFar = Color(nsColor: shadowFarNS)
    /// A card lifted under the pointer: the far shadow, deeper.
    static let shadowLifted = Color(nsColor: dynamic("shadowLifted", light: gray(0, 0.12), dark: gray(0, 0.5)))

    /// The tile behind a section's symbol, and the symbol's tint.
    static func section(_ section: PageSection) -> Color {
        switch section {
        case .pullRequests: Color(nsColor: .systemPurple)
        case .sessions: Color.accentColor
        case .files: Color(nsColor: .systemTeal)
        case .tasks: Color(nsColor: .systemOrange)
        }
    }

    static let backlogTile = Color(nsColor: .systemGray)
    /// Kind tiles: files, artifacts, and a draft PR.
    static let fileTile = Color(nsColor: .systemTeal)
    static let artifactTile = Color(nsColor: .systemIndigo)
    static let draftTile = Color(nsColor: .systemGray)
    /// A symbol on a section's tinted tile.
    static let onTile = Color.white

    /// The sky over the top of the page: three soft colors that follow the day.
    static func sky(_ mood: SkyMood) -> [Color] {
        switch mood {
        case .calm: [Color.accentColor, Color(nsColor: .systemIndigo), Color(nsColor: .systemTeal)]
        case .news: [Color(nsColor: .systemBlue), Color(nsColor: .systemCyan), Color(nsColor: .systemIndigo)]
        case .needsYou: [Color(nsColor: .systemOrange), Color(nsColor: .systemPink), Color(nsColor: .systemPurple)]
        }
    }

    /// How strong the sky is at its top: faint enough for text, enough for glass to catch.
    static func skyOpacity(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.3 : 0.24 }
    /// A card or a row under a dragged item.
    static let dropFill = Color.accentColor.opacity(0.14)
    /// A selected outline row: a tint that keeps text colors, gray when the outline isn't focused.
    /// Text and marks in AppKit rows: primary, secondary, tertiary (decoration only), and the accent.
    static let textNS = NSColor.labelColor
    static let secondaryTextNS = NSColor.secondaryLabelColor
    static let quietMarkNS = NSColor.tertiaryLabelColor
    /// A hidden description's first line after a title: present, well behind the title.
    static let previewTextNS = NSColor.tertiaryLabelColor
    static let accentNS = NSColor.controlAccentColor
    static let rowSelectionNS = NSColor.controlAccentColor.withAlphaComponent(0.2)
    static let rowSelection = Color(nsColor: rowSelectionNS)
    /// A selected session card: the selected row's tint over the card.
    /// A working session's state capsule.
    static let workingFill = Color(nsColor: NSColor.controlAccentColor.withAlphaComponent(0.12))
    /// A project's or a tag's chip: neutral; the label's color is in its mark.
    static let labelFillNS = NSColor.quaternarySystemFill
    static let labelFill = Color(nsColor: labelFillNS)
    static let cardSelection = Color(nsColor: NSColor.controlAccentColor.withAlphaComponent(0.14))
    /// The section in view, in the section bar: a quiet capsule inside the glass.
    static let barSelection = Color(nsColor: dynamic("barSelection", light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.12)))
    static let rowSelectionInactiveNS = NSColor.unemphasizedSelectedContentBackgroundColor
    /// Where a dragged card lands.
    static let dropNS = NSColor.controlAccentColor
    /// A row a dragged task would drop onto.
    static let rowDropNS = NSColor.controlAccentColor.withAlphaComponent(0.25)
    /// An orange or blue tag's fill, in AppKit rows.
    static let needsYouFillNS = NSColor.systemOrange.withAlphaComponent(0.13)
    static let unreadFillNS = NSColor.systemBlue.withAlphaComponent(0.13)
    /// Hover on custom rows and cards.
    static let hoverFill = Color(nsColor: .quaternarySystemFill)
    static let hoverFillNS = NSColor.quaternarySystemFill
    /// Selection while the list isn't focused or the window is inactive.
    static let selectionInactive = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    /// Chips and code blocks.
    static let chipFill = HierarchicalShapeStyle.quaternary
    /// The problem banner.
    static let bannerFill = Color(nsColor: .quaternarySystemFill)
    /// A box in the modal (subtasks, outputs, details), and its frame.
    static let boxFill = Color(nsColor: .quaternarySystemFill)
    static let boxFrame = Color(nsColor: .separatorColor)
    /// An editor's background, and behind a diagram's edge labels.
    static let editor = Color(nsColor: .textBackgroundColor)
    static let editorNS = NSColor.textBackgroundColor
    /// The bar beside a markdown quote.
    static let quoteBar = Color(nsColor: .separatorColor)

    /// The markdown editor's syntax colors.
    static let syntaxHeadingNS = NSColor.labelColor
    static let syntaxMarkerNS = NSColor.systemOrange.blended(withFraction: 0.2, of: .labelColor) ?? .secondaryLabelColor
    static let syntaxCodeNS = NSColor.secondaryLabelColor
    static let syntaxLinkNS = NSColor.linkColor
    static let syntaxQuietNS = NSColor.tertiaryLabelColor
}

/// Sizes.
nonisolated enum Metric {
    /// Status glyphs: one size and one stroke for the whole family.
    static var glyph: CGFloat { 14 * Zoom.factor }
    static var glyphSlot: CGFloat { 16 * Zoom.factor }
    static var glyphStroke: CGFloat { 1.5 * Zoom.factor }
    static var unreadDot: CGFloat { 8 * Zoom.factor }
    static var attentionDot: CGFloat { 6 * Zoom.factor }
    static var lineGap: CGFloat { 2 * Zoom.factor }
    static var chipHeight: CGFloat { 18 * Zoom.factor }
    /// The page: at most this wide, centered, with its side margins.
    static var pageMax: CGFloat { 1240 * Zoom.factor }
    static var pageMargin: CGFloat { 28 * Zoom.factor }
    static var pageMarginNarrow: CGFloat { 20 * Zoom.factor }
    /// Below this window width the page takes the narrow margins.
    static var narrowWindow: CGFloat { 900 * Zoom.factor }
    /// Session cards: fixed height, columns by content width.
    static var card: CGFloat { 68 * Zoom.factor }
    static var cardGap: CGFloat { 12 * Zoom.factor }
    static var fourColumns: CGFloat { 1200 * Zoom.factor }
    static var threeColumns: CGFloat { 1060 * Zoom.factor }
    static var twoColumns: CGFloat { 692 * Zoom.factor }
    /// A session card's state capsule.
    static var statePill: CGFloat { 22 * Zoom.factor }
    /// Card shadows: a contact shadow, and a soft far one (deeper while lifted).
    static var shadowNearRadius: CGFloat { 1 * Zoom.factor }
    static var shadowNearY: CGFloat { 1 * Zoom.factor }
    static var shadowFarRadius: CGFloat { 12 * Zoom.factor }
    static var shadowFarY: CGFloat { 4 * Zoom.factor }
    static var shadowLiftRadius: CGFloat { 20 * Zoom.factor }
    static var shadowLiftY: CGFloat { 8 * Zoom.factor }
    /// The glow of a card that needs the user.
    static var glowRadius: CGFloat { 14 * Zoom.factor }
    /// The page's title, and the sky behind the top of the page.
    static var pageTitleTop: CGFloat { 8 * Zoom.factor }
    static var pageTitle: CGFloat { 52 * Zoom.factor }
    static var skyHeight: CGFloat { 420 * Zoom.factor }
    /// A section's symbol tile beside its title.
    static var sectionTile: CGFloat { 24 * Zoom.factor }
    /// "All reviewed" alone in its card: on the grid, whatever its text measures.
    static var allReviewed: CGFloat { 96 * Zoom.factor }
    /// A PR's, a file's or an artifact's kind tile at the start of its row.
    static var kindTile: CGFloat { 20 * Zoom.factor }
    /// The floating section bar under the toolbar.
    static var sectionBar: CGFloat { 32 * Zoom.factor }
    static var sectionBarItem: CGFloat { 28 * Zoom.factor }
    /// The color dot in a project's or a tag's chip.
    static var labelDot: CGFloat { 6 * Zoom.factor }
    /// Faces.
    static var faceCard: CGFloat { 44 * Zoom.factor }
    static var faceRow: CGFloat { 22 * Zoom.factor }
    static var faceChip: CGFloat { 16 * Zoom.factor }
    static var faceModal: CGFloat { 72 * Zoom.factor }
    static var badgeRing: CGFloat { 2 * Zoom.factor }
    /// Pull requests: two cards side by side from this content width; fixed columns in each row.
    static var prSideBySide: CGFloat { 1100 * Zoom.factor }
    static var prRow: CGFloat { 40 * Zoom.factor }
    /// The rows of PRs, files and artifacts: one line for files and artifacts; a fixed status or date column, then the key.
    static var itemRow: CGFloat { 32 * Zoom.factor }
    static var rowStatus: CGFloat { 176 * Zoom.factor }
    static var rowKey: CGFloat { 44 * Zoom.factor }
    /// Buttons, toggles, pop-ups and searches on the right of a section's title.
    static var headerControl: CGFloat { 28 * Zoom.factor }
    /// The outline.
    static var outlineRow: CGFloat { 32 * Zoom.factor }
    /// A list's header row: its title line and 12 pt to its card.
    static var outlineHeader: CGFloat { 44 * Zoom.factor }
    /// Above the Backlog's header: the space between sections.
    static var backlogHeaderGap: CGFloat { 28 * Zoom.factor }
    static var outlineIndent: CGFloat { 20 * Zoom.factor }
    static var outlineQuick: CGFloat { 32 * Zoom.factor }
    static var outlineEmpty: CGFloat { 36 * Zoom.factor }
    /// Space above a top-level task after the first: groups read apart from their subtasks.
    static var outlineGroupGap: CGFloat { 16 * Zoom.factor }
    /// Space inside a list's card above its first task.
    static var listCardPadding: CGFloat { 8 * Zoom.factor }
    /// The line of links under a task's title.
    static var linksLine: CGFloat { 22 * Zoom.factor }
    /// A hidden description's first line shows when this much room is left.
    static var previewMinimum: CGFloat { 80 * Zoom.factor }
    /// Hover actions in a row: a 22 pt hit area each.
    static var rowAction: CGFloat { 22 * Zoom.factor }
    static var quickOpenWidth: CGFloat { 560 * Zoom.factor }
    static var quickOpenHeight: CGFloat { 432 * Zoom.factor }
    static var quickOpenRow: CGFloat { 36 * Zoom.factor }
    static var searchWidth: CGFloat { 200 * Zoom.factor }
    /// A list's search field in its header.
    static var listSearch: CGFloat { 180 * Zoom.factor }
    static var listSearchMin: CGFloat { 96 * Zoom.factor }
    /// Link…'s list in its popover.
    static var linkPicker: CGFloat { 280 * Zoom.factor }
    /// A linked task's chip in a pull request's header, before it truncates.
    static var linkedTaskMax: CGFloat { 240 * Zoom.factor }
    /// The field + opens after a list of tags.
    static var tagField: CGFloat { 140 * Zoom.factor }
    static let settingsWidth: CGFloat = 520
    static var sheetWidth: CGFloat { 480 * Zoom.factor }
    static let windowMin = CGSize(width: 720, height: 600)
    /// The modal: this share of the window's content, at least `modalMin`.
    static let modalShare: CGFloat = 0.88
    static let modalMin = CGSize(width: 720, height: 520)
    static var modalHeader: CGFloat { 52 * Zoom.factor }
    /// A push button's height in the modal's header.
    static var modalButton: CGFloat { 24 * Zoom.factor }
    /// The header's side margin: as far as its buttons sit from the top, so they nest in the sheet's round corners.
    static var modalEdge: CGFloat { (modalHeader - modalButton) / 2 }
    /// The modal's text column.
    static var pageWidth: CGFloat { 760 * Zoom.factor }
    /// Labels in the task modal's property grid.
    static var propertyLabel: CGFloat { 72 * Zoom.factor }
    static var boxRow: CGFloat { 32 * Zoom.factor }
    /// Editors before they scroll.
    static var editorMin: CGFloat { 160 * Zoom.factor }
    /// The markdown editor's line height, as a multiple of its font's.
    static let editorLineHeight: CGFloat = 1.35
    static var messageEditor: CGFloat { 200 * Zoom.factor }
    /// A Mermaid diagram while it's drawn the first time.
    static var diagramPlaceholder: CGFloat { 120 * Zoom.factor }
    /// The bar beside a quote.
    static var quoteBar: CGFloat { 3 * Zoom.factor }
    /// A pill's inner padding and icon in AppKit rows.
    static var pillPadding: CGFloat { 6 * Zoom.factor }
    static var pillIcon: CGFloat { 12 * Zoom.factor }
    /// Outline row parts that hide before the title shrinks under `titleMinimum`.
    static var titleMinimum: CGFloat { 120 * Zoom.factor }
    static var reviewPillMax: CGFloat { 220 * Zoom.factor }
    static var projectPillMax: CGFloat { 140 * Zoom.factor }
    /// A chip's gap in flowing lists.
    static var chipGap: CGFloat { 6 * Zoom.factor }
}

/// Corner radii. Nested corners are concentric.
nonisolated enum Radius {
    static var chip: CGFloat { 6 * Zoom.factor }
    static var control: CGFloat { 8 * Zoom.factor }
    static var row: CGFloat { 10 * Zoom.factor }
    /// Raised cards; rows inside them sit `Space.xs + 2` in, so their 10 is concentric.
    static var card: CGFloat { 16 * Zoom.factor }
    /// A section's symbol tile, and a row's kind tile.
    static var tile: CGFloat { 7 * Zoom.factor }
    static var kindTile: CGFloat { 6 * Zoom.factor }
    static var quickOpen: CGFloat { 26 * Zoom.factor }
}

/// Every animation goes through Motion, so Reduce Motion applies everywhere.
enum Motion {
    /// Hover fills and buttons that show on hover: a fade.
    static let hover = Animation.easeOut(duration: 0.08)
    /// One sway of a working session's face, left and back, in seconds.
    static let faceSway: TimeInterval = 2
    /// Frames a second of the sway.
    static let faceFrameRate = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
    /// Quick Open fading in.
    static let appearSeconds: TimeInterval = 0.18
    /// A card that needs the user, or is done unread, glows and breathes: half a breath, from faint to bright, in seconds.
    static let blinkHalf: TimeInterval = 0.9
    /// A card rising under the pointer.
    static let lift = Animation.smooth(duration: liftSeconds)
    static let liftSeconds: TimeInterval = 0.18
    /// The sky changing with the day's state.
    static let skySeconds: TimeInterval = 1.4
    /// The section bar's highlight gliding to the section in view, and the page scrolling there.
    static let glide = Animation.easeInOut(duration: 0.26)
    /// A clicked section holds the bar this long while the page scrolls, in seconds.
    static let holdSeconds: TimeInterval = 0.7
    /// A status glyph that changed: a short spring, in seconds.
    static let popSeconds: TimeInterval = 0.34
    /// "Copied" on what a click copied (Copy Link, a task's key), in seconds.
    static let copiedSeconds: TimeInterval = 1.5

    /// Runs AppKit row and item changes with no animation when `still` asks for it (HQ ignores Reduce Motion, DESIGN.md §12).
    @MainActor static func appKit(still: Bool = false, _ changes: () -> Void) {
        NSAnimationContext.beginGrouping()
        if still { NSAnimationContext.current.duration = 0 }
        changes()
        NSAnimationContext.endGrouping()
    }
}
