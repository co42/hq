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
    /// Blocked: it can't be done now. A task blocked by another shows the same red, as a ring.
    static let blocked = Color(nsColor: .systemRed)
    static let blockedNS = NSColor.systemRed
    static let blockedTextNS = failedTextNS
    static let blockedText = failedText
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
    /// A done task's card: flat, behind the open ones.
    static let doneCardNS = dynamic("doneCard", light: gray(1, 0.55), dark: NSColor(srgbRed: 0.137, green: 0.137, blue: 0.149, alpha: 0.5))
    /// A block's tray: a task with subtasks, a shade under its cards.
    static let trayNS = dynamic("tray", light: gray(0, 0.035), dark: gray(1, 0.035), lightHigh: gray(0, 0.08), darkHigh: gray(1, 0.09))
    static let blockedRingNS = NSColor.systemRed.withAlphaComponent(0.6)
    /// A card's edge: a hairline that is a highlight in dark mode.
    static let cardHairlineNS = dynamic("hairline", light: gray(0, 0.07), dark: gray(1, 0.08), lightHigh: gray(0, 0.32), darkHigh: gray(1, 0.36))
    static let cardHairline = Color(nsColor: cardHairlineNS)
    /// The edge of the card a new task is typed in: dashed, a card not made yet (2026-11-10).
    static let newCardLineNS = dynamic("newCardLine", light: gray(0, 0.2), dark: gray(1, 0.22), lightHigh: gray(0, 0.45), darkHigh: gray(1, 0.5))
    static let newCardLine = Color(nsColor: newCardLineNS)
    /// A card's control that is on: a task's description shown.
    static let markOnNS = NSColor.controlAccentColor.withAlphaComponent(0.14)
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
        // Orange is for what needs the user: the Tasks tile isn't (2026-11-11).
        case .tasks: Color(nsColor: .systemIndigo)
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
    /// A selected task card's tint, under its accent ring.
    static let cardSelectionNS = NSColor.controlAccentColor.withAlphaComponent(0.06)
    /// The card a dragged task would drop onto: its surface with a touch of the accent, opaque over the tray.
    static let dropCardNS = NSColor(name: "dropCard") { appearance in
        var color = surfaceNS
        appearance.performAsCurrentDrawingAppearance { color = surfaceNS.usingColorSpace(.sRGB)?.blended(withFraction: 0.14, of: NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue) ?? surfaceNS }
        return color
    }
    /// The capsule of the tasks a task is blocked by.
    static let blockedChipNS = NSColor.systemRed.withAlphaComponent(0.11)
    /// A row a dragged task would drop onto.
    static let rowDropNS = NSColor.controlAccentColor.withAlphaComponent(0.25)
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
    static var lineGap: CGFloat { 2 * Zoom.factor }
    static var chipHeight: CGFloat { 18 * Zoom.factor }
    /// The page: at most this wide, centered, with its side margins.
    static var pageMax: CGFloat { 1240 * Zoom.factor }
    static var pageMargin: CGFloat { 28 * Zoom.factor }
    static var pageMarginNarrow: CGFloat { 20 * Zoom.factor }
    /// Below this window width the page takes the narrow margins.
    static var narrowWindow: CGFloat { 900 * Zoom.factor }
    /// Session cards: fixed height, two columns from this content width.
    static var card: CGFloat { 68 * Zoom.factor }
    static var cardGap: CGFloat { 12 * Zoom.factor }
    static var twoColumns: CGFloat { 1060 * Zoom.factor }
    /// A team on its card: the faces in its tray, the toggle after them, their state badges.
    static var faceTeam: CGFloat { 26 * Zoom.factor }
    static var teamToggle: CGFloat { 26 * Zoom.factor }
    static var teamBadge: CGFloat { 13 * Zoom.factor }
    /// The name keeps at least this much beside a team's faces, and the time over the state takes about this much.
    static var teamName: CGFloat { 190 * Zoom.factor }
    static var cardState: CGFloat { 110 * Zoom.factor }
    /// An open team's rows: their height, their face, and how far each level sits in.
    static var teamRow: CGFloat { 34 * Zoom.factor }
    static var faceTeamRow: CGFloat { 24 * Zoom.factor }
    static var teamIndent: CGFloat { 28 * Zoom.factor }
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
    /// A window at least this wide has room for the section bar in the toolbar, between New and the search.
    static var sectionBarWindow: CGFloat { 960 * Zoom.factor }
    static var sectionBarItem: CGFloat { 28 * Zoom.factor }
    /// The color dot in a project's or a tag's chip.
    static var labelDot: CGFloat { 6 * Zoom.factor }
    /// Faces.
    static var faceCard: CGFloat { 44 * Zoom.factor }
    static var faceRow: CGFloat { 22 * Zoom.factor }
    /// A selected card's ring, as a session card's.
    static var selectionRing: CGFloat { 2 * Zoom.factor }
    static var faceChip: CGFloat { 16 * Zoom.factor }
    /// A face in a menu: the menu bar icon's Focus items. Menus don't zoom.
    static let faceMenu: CGFloat = 16
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
    /// The outline: a card's first line with its padding above and below.
    static var outlineRow: CGFloat { 36 * Zoom.factor }
    /// The outline's container column for faces: the face cell places itself at a card's end.
    static var facesColumn: CGFloat { 22 * Zoom.factor }
    /// A card's first line: the glyph, the key, the title and what's at its end.
    static var cardLine: CGFloat { 20 * Zoom.factor }
    /// A card's padding left and right of its content.
    static var cardPadding: CGFloat { 12 * Zoom.factor }
    /// A top-level task's big card: its padding all around.
    static var bigCardPadding: CGFloat { 14 * Zoom.factor }
    /// A big card's title line, under its first line.
    static var bigTitleLine: CGFloat { 24 * Zoom.factor }
    /// A subtask's card, in from its parent's (but a story's own subtasks).
    static var subtaskIndent: CGFloat { 24 * Zoom.factor }
    /// A story's tray: its padding around the big card and its subtasks.
    static var storyTrayPadding: CGFloat { 10 * Zoom.factor }
    /// A dragged task over a card's top or bottom edge, this deep, goes between cards; over the rest, onto the card.
    static var dropEdge: CGFloat { 8 * Zoom.factor }
    /// The fold chevron and the face at a card's end.
    static var cardEndControl: CGFloat { 20 * Zoom.factor }
    /// A list's header row: its title line and 12 pt to its card.
    static var outlineHeader: CGFloat { 44 * Zoom.factor }
    /// Above the Backlog's header: the space between sections.
    static var backlogHeaderGap: CGFloat { 28 * Zoom.factor }
    static var outlineQuick: CGFloat { 36 * Zoom.factor }
    /// The dashes of the new task's card edge.
    static var newCardDash: [CGFloat] { [4 * Zoom.factor, 3 * Zoom.factor] }
    static var outlineEmpty: CGFloat { 36 * Zoom.factor }
    /// A block's tray: its padding around its header and its subtasks.
    static var trayPadding: CGFloat { 8 * Zoom.factor }
    /// Between two task cards in the outline.
    static var taskGap: CGFloat { 8 * Zoom.factor }
    /// Between two top-level tasks: stories read apart.
    static var storyGap: CGFloat { 24 * Zoom.factor }
    /// A top-level task's progress line, under its title.
    static var storyLine: CGFloat { 28 * Zoom.factor }
    /// A top-level task's progress bar, and its height.
    static var storyBar: CGFloat { 200 * Zoom.factor }
    static var storyBarHeight: CGFloat { 6 * Zoom.factor }
    /// A block's progress bar, on its header's line.
    static var blockBar: CGFloat { 64 * Zoom.factor }
    /// A Blocked task's reason, under its title.
    static var reasonLine: CGFloat { 18 * Zoom.factor }
    /// The line of links under a task's title.
    static var linksLine: CGFloat { 20 * Zoom.factor }
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
    /// The When picker's popover.
    static var whenPicker: CGFloat { 300 * Zoom.factor }
    /// A linked task's chip in a pull request's header, before it truncates.
    static var linkedTaskMax: CGFloat { 240 * Zoom.factor }
    /// The field + opens after a list of tags.
    static var tagField: CGFloat { 140 * Zoom.factor }
    static let settingsWidth: CGFloat = 520
    /// A secret pasted in Settings, the Slack token.
    static let settingsField: CGFloat = 240
    static var sheetWidth: CGFloat { 480 * Zoom.factor }
    static let windowMin = CGSize(width: 720, height: 600)
    /// The modal: this share of the window's content, at least `modalMin`.
    static let modalShare: CGFloat = 0.88
    static let modalMin = CGSize(width: 720, height: 520)
    /// New Reminder…: what, its links, when, important, then its buttons.
    static let reminderSheet = CGSize(width: 560, height: 262)
    /// New Task…: the title, a description, the list, the project and the links, then its buttons.
    static let taskSheet = CGSize(width: 560, height: 328)
    /// New File…: its title, then its buttons.
    static let fileSheet = CGSize(width: 560, height: 160)
    /// Import Artifact…: its link with a word on it, its title, then its buttons.
    static let importSheet = CGSize(width: 560, height: 212)
    /// Start a Session: name, folder, role, parent, history, the first message, then its buttons.
    static let startSheet = CGSize(width: 720, height: 600)
    /// Its pop-ups, one width, so a long folder or session name never pushes the form past the sheet.
    static var startPicker: CGFloat { 260 * Zoom.factor }
    /// The Roles modal's list card, beside the role from this modal width, above it under.
    static var rolesList: CGFloat { 260 * Zoom.factor }
    static var rolesSideBySide: CGFloat { 900 * Zoom.factor }
    static var roleRow: CGFloat { 44 * Zoom.factor }
    /// A team's level in a menu: its sessions' faces step in by this.
    static let menuIndent: CGFloat = 16
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
    /// A markdown editor in a row grows with its text up to this, then scrolls.
    static var editorMaximum: CGFloat { 480 * Zoom.factor }
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
    /// No motion: test and snapshot runs wait on what shows, not on how it moves (HQ_MOTION=1, or a UI group, turns it back on).
    static var still = false
    /// Hover fills and buttons that show on hover: a fade.
    static var hover: Animation? { still ? nil : .easeOut(duration: 0.08) }
    /// One sway of a working session's face, left and back, in seconds.
    static let faceSway: TimeInterval = 2
    /// Frames a second of the sway.
    static let faceFrameRate = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
    /// Quick Open fading in.
    static var appearSeconds: TimeInterval { still ? 0 : 0.18 }
    /// A card or the bell that needs the user glows and breathes: half a breath, from faint to bright, in seconds.
    static let blinkHalf: TimeInterval = 0.9
    /// A card rising under the pointer.
    static var lift: Animation? { still ? nil : .smooth(duration: liftSeconds) }
    static let liftSeconds: TimeInterval = 0.18
    /// The sky changing with the day's state.
    static let skySeconds: TimeInterval = 1.4
    /// The section bar's highlight gliding to the section in view, and the page scrolling there.
    static var glide: Animation? { still ? nil : .easeInOut(duration: 0.26) }
    /// A clicked section holds the bar this long while the page scrolls, in seconds.
    static let holdSeconds: TimeInterval = 0.7
    /// A status glyph that changed: a short spring, in seconds.
    static let popSeconds: TimeInterval = 0.34
    /// How long the pointer rests before a tooltip shows, in milliseconds (AppKit's own is about a second).
    static let tooltipMilliseconds = 100
    /// Cards and trays sliding with the outline's rows as a task folds or unfolds, about AppKit's own.
    static var rowsSeconds: TimeInterval { still ? 0 : 0.25 }
    /// A selected task with blocked-by or after links: the content of unrelated cards fades to this, still readable (2026-11-11).
    static let dimmedOpacity: CGFloat = 0.62
    /// "Copied" on what a click copied (Copy Link, a task's key), in seconds.
    static let copiedSeconds: TimeInterval = 1.5

    /// Runs AppKit row and item changes with no animation when `still` asks for it (HQ ignores Reduce Motion, DESIGN.md §12).
    @MainActor static func appKit(still: Bool = false, _ changes: () -> Void) {
        NSAnimationContext.beginGrouping()
        if still || Motion.still { NSAnimationContext.current.duration = 0 }
        changes()
        NSAnimationContext.endGrouping()
    }
}
