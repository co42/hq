import AppKit
import HQKit

/// HQ_PERF_OPEN=<file title>, test copy only (tools/perf.sh, PERF_OPEN): opens that note, scrolls it to its end and back,
/// closes it, over and over; prints each round's times as `perf open …` lines.
@MainActor
enum PerfOpen {
    static func start(_ model: AppModel) {
        guard Store.isOverridden, let title = ProcessInfo.processInfo.environment["HQ_PERF_OPEN"], !title.isEmpty else { return }
        Task { @MainActor in
            var file: FileItem?
            for _ in 0..<300 where file == nil {
                file = model.files.first { $0.title == title || $0.id.hasSuffix("\(title).md") }
                if file == nil { try? await Task.sleep(for: .milliseconds(100)) }
            }
            guard let file else { return report("no file \(title)") }
            await model.loadFileBody(file.id)
            if let text = model.fileBody(file.id) {
                let parse = CACurrentMediaTime()
                let blocks = ViewerBlock.prepare(Markdown.blocks(text), style: .current)
                report("parse and measure \(Int((CACurrentMediaTime() - parse) * 1000)) ms, \(blocks.count) blocks, \(text.count) characters")
            }
            try? await Task.sleep(for: .seconds(1))
            for round in 1... { await Self.round(round, file, model) }
        }
    }

    private static func round(_ round: Int, _ file: FileItem, _ model: AppModel) async {
        let started = CACurrentMediaTime()
        var scroll: NSScrollView?
        let open = await Stall.measure([{ model.open(.file(file.id)) }], gap: 0.05)
        // Shown: the sheet's scroll view holds the note, taller than the sheet.
        for _ in 0..<400 {
            scroll = sheetScroll(model)
            if let scroll, model.fileBody(file.id) != nil, (scroll.documentView?.frame.height ?? 0) > scroll.contentView.bounds.height * 2 { break }
            scroll = nil
            try? await Task.sleep(for: .milliseconds(5))
        }
        let shown = Int((CACurrentMediaTime() - started) * 1000)
        guard let scroll else { return report("round \(round): the note never showed (\(shown) ms)") }
        let settle = await Stall.measure([{}], gap: 0.5)
        report("round \(round): shown after \(shown) ms (open stall \(open.worst) ms, then \(settle.worst) ms)")
        let end = max((scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height, 0)
        func move(_ steps: [CGFloat]) -> [() -> Void] {
            steps.map { y in {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
            } }
        }
        // A screen at a time to the end and back, then as a trackpad scrolls: 40 pt a frame.
        let jumps = Array(stride(from: 0, through: end, by: max(120, end / 40)))
        let paged = await Stall.measure(move(jumps + jumps.reversed()), gap: 0.02)
        let glide = Array(stride(from: 0, through: min(end, 4000), by: 40))
        let glided = await Stall.measure(move(glide + glide.reversed()), gap: 0.017)
        let close = await Stall.measure([{ model.closeModal() }], gap: 0.3)
        report("round \(round): \(Int(end)) pt; a screen a step: \(paged); 40 pt a step: \(glided); close \(close.worst) ms")
        try? await Task.sleep(for: .seconds(0.5))
    }

    /// The open sheet's tallest scroll view: a note's page.
    static func sheetScroll(_ model: AppModel) -> NSScrollView? {
        guard let sheet = model.window?.attachedSheet, let content = sheet.contentView else { return nil }
        func all(_ view: NSView) -> [NSScrollView] { ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(all) }
        return all(content).max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
    }

    private static func report(_ line: String) {
        print("perf open \(line)")
        fflush(stdout)
    }
}
