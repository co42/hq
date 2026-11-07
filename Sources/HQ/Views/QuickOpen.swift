import AppKit
import HQKit
import SwiftUI

/// One result in Quick Open.
struct QuickOpenResult: Identifiable, Hashable {
    enum Kind: Int, CaseIterable {
        case sessions, tasks, pullRequests, files, artifacts

        var title: String {
            switch self {
            case .sessions: "Sessions"
            case .tasks: "Tasks"
            case .pullRequests: "Pull Requests and Issues"
            case .files: "Files"
            case .artifacts: "Artifacts"
            }
        }
    }

    var route: ModalRoute
    var kind: Kind
    var title: String
    var detail: String?
    var offsets: [Int] = []
    var score = 0

    var id: ModalRoute { route }
}

/// Builds and acts on Quick Open's results.
enum QuickOpen {
    static let perKind = 5

    static func results(_ model: AppModel, query: String) -> [QuickOpenResult] {
        var all: [QuickOpenResult] = []
        func add(_ route: ModalRoute, _ kind: QuickOpenResult.Kind, _ title: String, _ detail: String?, match: String? = nil) {
            if query.isEmpty {
                all.append(QuickOpenResult(route: route, kind: kind, title: title, detail: detail))
            } else if let found = Fuzzy.match(query, in: match ?? title) {
                // Offsets index the matched text; keep only those inside the title.
                let shift = (match ?? title).count - title.count
                let offsets = found.offsets.map { $0 - shift }.filter { $0 >= 0 }
                all.append(QuickOpenResult(route: route, kind: kind, title: title, detail: detail, offsets: offsets, score: found.score))
            }
        }
        let sessions = query.isEmpty ? model.gridSessions : model.sessions
        for session in sessions {
            add(.session(session.id), .sessions, session.name, session.status.needsYou ? "Needs you" : session.repo)
        }
        let tasks = query.isEmpty ? model.tasks.filter { $0.status == .doing } : model.tasks
        for task in tasks {
            add(.task(task.id), .tasks, task.title, task.key, match: "\(task.key) \(task.title)")
        }
        for item in model.github?.items ?? [] {
            add(.github(item.url), .pullRequests, item.title, item.reference, match: "\(item.reference) \(item.title)")
        }
        for file in model.files.sorted(by: { $0.modified > $1.modified }) {
            add(.file(file.id), .files, file.title, file.modified.formatted(date: .abbreviated, time: .omitted))
        }
        for artifact in model.artifacts.sorted(by: { $0.published > $1.published }) {
            add(.artifact(artifact.id), .artifacts, artifact.title, nil)
        }
        let limit = query.isEmpty ? 3 : perKind
        return QuickOpenResult.Kind.allCases.flatMap { kind in
            Array(all.filter { $0.kind == kind }.sorted { $0.score > $1.score }.prefix(limit))
        }
    }

    /// ⌘Return: the item's outside action.
    static func actionTitle(_ result: QuickOpenResult, model: AppModel) -> String {
        switch result.route {
        case .session(let id): model.session(id)?.isRunning == false ? "Resume" : "Focus"
        case .task, .file: "Open in Obsidian"
        case .artifact: "Open in Browser"
        case .github: "Open on GitHub"
        default: "Open"
        }
    }

    /// Return: the item's modal.
    static func open(_ result: QuickOpenResult, model: AppModel) {
        model.open(result.route)
    }

    /// ⌘Return: Ghostty, Obsidian, the browser or GitHub.
    static func openOutside(_ result: QuickOpenResult, model: AppModel) {
        model.openOutside(result.route)
    }
}

/// Quick Open's floating glass panel, centered on HQ's window.
final class QuickOpenPanel: NSPanel {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init(contentRect: NSRect(origin: .zero, size: CGSize(width: Metric.quickOpenWidth, height: Metric.quickOpenHeight)),
                   styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        let host = NSHostingView(rootView: QuickOpenView { [weak self] in self?.dismiss() }
            .environment(model)
            )
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { dismiss() }

    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    func toggle(over window: NSWindow?) {
        isVisible ? dismiss() : show(over: window)
    }

    func show(over window: NSWindow?) {
        model.quickOpenQuery = ""
        model.quickOpenIndex = 0
        if let frame = window?.frame {
            // Centered across, in the upper third, like Spotlight over its window.
            setFrameOrigin(NSPoint(x: frame.midX - self.frame.width / 2,
                                   y: frame.maxY - frame.height / 3 - self.frame.height / 2))
        } else {
            center()
        }
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .focusQuickOpen, object: nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.appearSeconds
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
    }
}

extension Notification.Name {
    static let focusQuickOpen = Notification.Name("HQ.focusQuickOpen")
}

struct QuickOpenView: View {
    let close: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let results = QuickOpen.results(model, query: model.quickOpenQuery)
        let index = min(model.quickOpenIndex, max(results.count - 1, 0))
        VStack(spacing: 0) {
            HStack(spacing: Space.md) {
                KitIcon.search.image
                    .font(KitType.field.font)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                QuickOpenField(text: $model.quickOpenQuery, prompt: "Open a session, task, pull request, file or artifact") { command in
                    switch command {
                    case .up: model.quickOpenIndex = max(index - 1, 0)
                    case .down: model.quickOpenIndex = min(index + 1, max(results.count - 1, 0))
                    case .open, .show:
                        guard results.indices.contains(index) else { return }
                        command == .open ? QuickOpen.open(results[index], model: model) : QuickOpen.openOutside(results[index], model: model)
                        close()
                    case .cancel: close()
                    }
                }
            }
            .padding(.horizontal, Space.lg)
            .frame(height: Space.section + Space.xl)

            Divider()

            if results.isEmpty {
                ContentUnavailableView.search(text: model.quickOpenQuery)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        // At most 25 rows: a plain stack, one flat list of headers and results.
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(QuickOpenLine.lines(results)) { line in
                                switch line {
                                case .header(let kind):
                                    Text(kind.title)
                                        .kitType(.groupLabel)
                                        .foregroundStyle(.secondary)
                                        .accessibilityAddTraits(.isHeader)
                                        .padding(.horizontal, Space.sm)
                                        .padding(.top, Space.sm)
                                        .padding(.bottom, Space.xs)
                                case .result(let offset, let result):
                                    QuickOpenRow(title: result.title, matched: result.offsets, detail: result.detail,
                                                 selected: offset == index) {
                                        icon(result)
                                    }
                                    .onTapGesture {
                                        QuickOpen.open(result, model: model)
                                        close()
                                    }
                                    .onHover { if $0 { model.quickOpenIndex = offset } }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityAddTraits(offset == index ? [.isButton, .isSelected] : .isButton)
                                    .accessibilityAction {
                                        QuickOpen.open(result, model: model)
                                        close()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Space.sm)
                        .padding(.bottom, Space.sm)
                    }
                    .onChange(of: index) {
                        guard results.indices.contains(index) else { return }
                        proxy.scrollTo(QuickOpenLine.result(index, results[index]).id)
                        // VoiceOver stays in the field: it hears the row the arrows chose.
                        AccessibilityNotification.Announcement(results[index].title).post()
                    }
                }
            }

            Divider()

            HStack(spacing: Space.sm) {
                Spacer()
                if results.indices.contains(index) {
                    actionHint("Show Details", key: "↩")
                    Text("·").foregroundStyle(.tertiary)
                    actionHint(QuickOpen.actionTitle(results[index], model: model), key: "⌘↩")
                }
            }
            .kitType(.secondary)
            .padding(.horizontal, Space.lg)
            .frame(height: Space.section)
        }
        .frame(width: Metric.quickOpenWidth, height: Metric.quickOpenHeight)
        .onChange(of: model.quickOpenQuery) { model.quickOpenIndex = 0 }
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.quickOpen))
    }

    private func actionHint(_ title: String, key: String) -> some View {
        HStack(spacing: Space.xs) {
            Text(title).foregroundStyle(.secondary)
            Text(key).kitType(.key).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func icon(_ result: QuickOpenResult) -> some View {
        switch result.route {
        case .session(let id):
            if let session = model.session(id) { SessionFace(session, size: Metric.faceChip) }
        case .task(let id):
            if let task = model.task(id) { TaskGlyph(status: task.status) }
        case .github(let url):
            if let item = model.githubItem(url) { GitHubStateIcon(item: item) }
        case .file: KitIcon.file.image.foregroundStyle(.secondary)
        case .artifact: KitIcon.artifact.image.foregroundStyle(.secondary)
        default: EmptyView()
        }
    }
}

/// One line of the results: a kind's header, or a result with its place in the list.
private enum QuickOpenLine: Identifiable {
    case header(QuickOpenResult.Kind)
    case result(Int, QuickOpenResult)

    var id: String {
        switch self {
        case .header(let kind): "header-\(kind.rawValue)"
        case .result(_, let result): "\(result.route)"
        }
    }

    static func lines(_ results: [QuickOpenResult]) -> [QuickOpenLine] {
        var lines: [QuickOpenLine] = []
        for (offset, result) in results.enumerated() {
            if offset == 0 || results[offset - 1].kind != result.kind { lines.append(.header(result.kind)) }
            lines.append(.result(offset, result))
        }
        return lines
    }
}

/// Quick Open's field: an NSTextField, so ↑↓, Return and Escape reach the results while it has focus.
struct QuickOpenField: NSViewRepresentable {
    enum Command { case up, down, open, show, cancel }

    @Binding var text: String
    let prompt: String
    let onCommand: (Command) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = KitType.field.nsFont
        field.placeholderString = prompt
        field.delegate = context.coordinator
        field.cell?.lineBreakMode = .byTruncatingTail
        field.setAccessibilityLabel("Quick Open")
        context.coordinator.observe(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickOpenField
        private var token: NSObjectProtocol?

        init(_ parent: QuickOpenField) {
            self.parent = parent
        }

        func observe(_ field: NSTextField) {
            token = NotificationCenter.default.addObserver(forName: .focusQuickOpen, object: nil, queue: .main) { [weak field] _ in
                MainActor.assumeIsolated { _ = field?.window?.makeFirstResponder(field) }
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.onCommand(.up)
            case #selector(NSResponder.moveDown(_:)): parent.onCommand(.down)
            case #selector(NSResponder.insertNewline(_:)):
                parent.onCommand(NSApp.currentEvent?.modifierFlags.contains(.command) == true ? .show : .open)
            case #selector(NSResponder.cancelOperation(_:)): parent.onCommand(.cancel)
            default: return false
            }
            return true
        }
    }
}
