import AppKit
import HQKit
import SwiftUI

/// Every SF Symbol HQ uses, named once. The self-test checks that each exists.
enum KitIcon: String, CaseIterable {
    // Toolbar and page
    case new = "plus"
    case addTask = "plus.circle.fill"
    case markSeen = "checkmark.circle"
    case search = "magnifyingglass"
    case hide = "eye.slash"
    case show = "eye"
    case disclosure = "chevron.right"
    // Section tiles
    case sessions = "sparkles"
    case files = "doc.on.doc.fill"
    case tasks = "checklist"
    case backlog = "tray.full.fill"
    // Rows
    case startSession = "apple.terminal"
    case description = "text.alignleft"
    case toBacklog = "tray.and.arrow.down"
    case toTasks = "tray.and.arrow.up"
    case trash = "trash"
    case project = "shippingbox"
    case tag = "tag"
    case pin = "pin"
    case pinned = "pin.fill"
    // Outputs
    case file = "doc.text"
    case fileTile = "doc.text.fill"
    case artifact = "globe"
    case pullRequest = "arrow.triangle.pull"
    case merged = "arrow.triangle.merge"
    case closedPR = "xmark.circle"
    case issue = "smallcircle.filled.circle"
    case checkPassed = "checkmark.circle.fill"
    case checkFailed = "xmark.circle.fill"
    case checkRunning = "circle.dotted"
    case allReviewed = "checkmark.seal.fill"
    // Actions
    case copy = "document.on.document"
    case openExternal = "arrow.up.right.square"
    case close = "xmark"
    case back = "chevron.backward"
    case reload = "arrow.clockwise"
    case unlink = "minus.circle.fill"
    case link = "link"
    case copied = "checkmark"
    case filter = "line.3.horizontal.decrease"
    case filterOn = "line.3.horizontal.decrease.circle.fill"
    case importItem = "square.and.arrow.down"
    case hideDone = "checklist.checked"
    // Health and Settings
    case problem = "exclamationmark.triangle.fill"
    case pending = "circle.dashed"
    case plugin = "puzzlepiece.extension"
    case vault = "books.vertical"
    case general = "gearshape"
    case keyboard = "keyboard"
    case ghostty = "terminal"
    case checked = "checkmark.square.fill"
    case unchecked = "square"

    var name: String { rawValue }

    var image: Image { Image(systemName: rawValue) }

    var nsImage: NSImage? {
        NSImage(systemSymbolName: rawValue, accessibilityDescription: nil)
    }

    /// Symbol sizes in AppKit rows: `.row` for row actions and type icons, `.mark` for the open arrow and pill icons.
    enum RowSize { case row, mark }

    func nsImage(_ size: RowSize, weight: NSFont.Weight = .regular) -> NSImage? {
        nsImage?.withSymbolConfiguration(.init(pointSize: size == .row ? 11 : 10, weight: weight))
    }

    static func github(_ item: GitHubItem) -> KitIcon {
        if item.kind == .issue { return .issue }
        switch item.state {
        case .open, .draft: return .pullRequest
        case .merged: return .merged
        case .closed: return .closedPR
        }
    }
}

extension Label where Title == Text, Icon == Image {
    init(_ title: String, icon: KitIcon) {
        self.init(title, systemImage: icon.rawValue)
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    init(_ title: String, icon: KitIcon, action: @escaping () -> Void) {
        self.init(title, systemImage: icon.rawValue, action: action)
    }
}

extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    init(_ title: String, icon: KitIcon) {
        self.init(title, systemImage: icon.rawValue)
    }
}

