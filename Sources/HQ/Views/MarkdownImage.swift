import AppKit
import HQKit
import ImageIO
import SwiftUI

/// An image in markdown, `![alt](url)` or `![[picture.png]]` (T-368 item 7): in the column, fit, its corners rounded; read and
/// scaled down off the main thread; a double-click expands it, as a diagram.
struct MarkdownImage: View {
    let url: URL
    let alt: String
    var expand: ((NSImage) -> Void)?
    @Environment(AppModel.self) private var model
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                DiagramImage(image: image, expand: expand.map { expand in { expand(image) } })
                    .aspectRatio(image.size, contentMode: .fit)
                    .frame(maxWidth: image.size.width)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .accessibilityLabel(alt.isEmpty ? "Image" : alt)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if failed {
                Text("Couldn’t show the image \(alt.isEmpty ? url.lastPathComponent : alt)").kitType(.secondary).foregroundStyle(.secondary)
            } else {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Ink.chipFill).frame(height: Metric.diagramPlaceholder)
            }
        }
        .task(id: url) {
            let vault = model.vault?.root.deletingLastPathComponent()
            image = await MarkdownImages.load(url, vault: vault)
            failed = image == nil
        }
    }
}

/// Images read once, scaled to at most 2,000 pixels, off the main thread.
enum MarkdownImages {
    private static var cache: [URL: NSImage] = [:]

    static func load(_ url: URL, vault: URL?) async -> NSImage? {
        if let cached = cache[url] { return cached }
        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let data = await data(url, vault: vault), let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceThumbnailMaxPixelSize: 2000]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            // At half its pixels, a Retina screen's points.
            return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        }.value
        if let image { cache[url] = image }
        return image
    }

    /// An address's bytes; an `![[name]]` is looked for by its name anywhere in the vault.
    private nonisolated static func data(_ url: URL, vault: URL?) async -> Data? {
        if url.scheme == "http" || url.scheme == "https" {
            return try? await URLSession.shared.data(from: url).0
        }
        if let name = Markdown.noteName(url) {
            guard let vault, let file = find(name, in: vault) else { return nil }
            return try? Data(contentsOf: file)
        }
        if url.isFileURL { return try? Data(contentsOf: url) }
        if let vault, !url.path.isEmpty { return try? Data(contentsOf: vault.appending(path: url.path)) }
        return nil
    }

    /// A file by its name, or its path from the vault's top.
    private nonisolated static func find(_ name: String, in vault: URL) -> URL? {
        let direct = vault.appending(path: name)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        let wanted = (name as NSString).lastPathComponent
        let files = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        while let file = files?.nextObject() as? URL {
            if file.lastPathComponent == wanted { return file }
        }
        return nil
    }
}

/// `![[Note]]`: a card that opens the note, its title and, when HQ has it, its first line (T-368 item 7).
struct NoteEmbed: View {
    let name: String
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var model

    var body: some View {
        let file = model.files.first { $0.title == name || $0.id == name || ($0.id as NSString).deletingPathExtension == name }
        let line = file.flatMap { model.fileBody($0.id) }.map(Self.firstLine) ?? ""
        Button {
            let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? name
            if let url = URL(string: "\(Markdown.noteScheme):\(encoded)") { openURL(url) }
        } label: {
            HStack(spacing: Space.sm) {
                KitIcon.file.image.foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(file?.title ?? name).kitType(.titleStrong).lineLimit(1)
                    if !line.isEmpty { Text(line).kitType(.secondary).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.sm)
            .background(Ink.chipFill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(name)")
        .ownsItsClicks()
    }
}

extension NoteEmbed {
    /// A note's first line after its `# Title`.
    static func firstLine(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("# "), let end = trimmed.firstIndex(of: "\n") else { return Markdown.firstLine(trimmed) }
        return Markdown.firstLine(String(trimmed[end...]))
    }
}
