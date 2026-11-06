import AppKit
import WebKit

/// Draws Mermaid diagrams with the bundled mermaid.js in a hidden web view, as PDF images that
/// views show natively. One diagram at a time; each source and appearance is drawn once.
final class MermaidRenderer: NSObject, WKNavigationDelegate {
    static let shared = MermaidRenderer()

    enum Result {
        case image(NSImage)
        case failed(String)
    }

    private var cache: [String: Result] = [:]
    private var webView: WKWebView?
    private var loaded: CheckedContinuation<Void, Never>?
    private var loading: Task<WKWebView?, Never>?
    /// The diagram being drawn: the next one waits for it.
    private var last: Task<Result, Never>?

    func cached(_ source: String, dark: Bool) -> Result? {
        cache[Self.key(source, dark)]
    }

    func render(_ source: String, dark: Bool) async -> Result {
        let key = Self.key(source, dark)
        if let hit = cache[key] { return hit }
        let previous = last
        let task = Task { () -> Result in
            _ = await previous?.value
            if let hit = cache[key] { return hit }
            let result = await draw(source, dark: dark)
            cache[key] = result
            NotificationCenter.default.post(name: .mermaidDidRender, object: nil)
            return result
        }
        last = task
        return await task.value
    }

    private static func key(_ source: String, _ dark: Bool) -> String {
        (dark ? "dark\n" : "light\n") + source
    }

    /// A system color in light or dark, as CSS.
    private static func hex(_ color: NSColor, dark: Bool) -> String {
        var css = dark ? "#1e1e1e" : "#ffffff"
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            guard let rgb = color.usingColorSpace(.sRGB) else { return }
            css = String(format: "#%02x%02x%02x", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
        }
        return css
    }

    // MARK: Drawing

    private func draw(_ source: String, dark: Bool) async -> Result {
        guard let web = await page() else { return .failed("mermaid.js isn’t in HQ’s bundle") }
        do {
            let arguments: [String: Any] = ["source": source, "dark": dark, "background": Self.hex(Ink.editorNS, dark: dark)]
            let size = try await web.callAsyncJavaScript(Self.script, arguments: arguments, contentWorld: .page) as? [Double]
            guard let size, size.count == 2, size[0] > 0, size[1] > 0 else { return .failed("The diagram is empty") }
            let rect = CGRect(x: 0, y: 0, width: size[0], height: size[1])
            if web.frame.width < rect.width || web.frame.height < rect.height {
                web.frame.size = CGSize(width: max(web.frame.width, rect.width), height: max(web.frame.height, rect.height))
            }
            let configuration = WKPDFConfiguration()
            configuration.rect = rect
            let data = try await web.pdf(configuration: configuration)
            guard let image = NSImage(data: data) else { return .failed("The diagram couldn’t be drawn") }
            image.size = rect.size
            return .image(image)
        } catch {
            let message = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
            return .failed(message.replacingOccurrences(of: "Error: ", with: ""))
        }
    }

    /// Renders into #box at the diagram's own size and returns that size.
    private static let script = """
        mermaid.initialize({
            startOnLoad: false, securityLevel: 'strict', suppressErrorRendering: true,
            theme: dark ? 'dark' : 'neutral',
            fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
            themeVariables: { background: background, edgeLabelBackground: background, fontSize: '14px' }
        });
        const box = document.getElementById('box');
        box.innerHTML = '';
        const { svg } = await mermaid.render('diagram' + Date.now(), source);
        box.innerHTML = svg;
        const element = box.querySelector('svg');
        const view = element.viewBox.baseVal;
        const width = Math.ceil(view && view.width ? view.width : element.getBoundingClientRect().width);
        const height = Math.ceil(view && view.height ? view.height : element.getBoundingClientRect().height);
        element.setAttribute('width', width);
        element.setAttribute('height', height);
        element.style.maxWidth = 'none';
        return [width, height];
        """

    // MARK: The page

    /// The web view with mermaid.js loaded, made on first use.
    private func page() async -> WKWebView? {
        if let loading { return await loading.value }
        let task = Task { () -> WKWebView? in
            guard let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "Mermaid"),
                  let script = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let configuration = WKWebViewConfiguration()
            configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 2048, height: 2048), configuration: configuration) // grid: ok room for a large diagram
            web.navigationDelegate = self
            web.setValue(false, forKey: "drawsBackground")
            await withCheckedContinuation { continuation in
                loaded = continuation
                web.loadHTMLString(Self.html, baseURL: nil)
            }
            webView = web
            return web
        }
        loading = task
        return await task.value
    }

    private static let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <style>html, body { margin: 0; padding: 0; background: transparent; } #box { display: inline-block; }</style>
        </head><body><div id="box"></div></body></html>
        """

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { finishLoading() }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finishLoading() }
    }

    private func finishLoading() {
        loaded?.resume()
        loaded = nil
    }
}

extension Notification.Name {
    /// A diagram was drawn: rows that hold it may change height.
    static let mermaidDidRender = Notification.Name("HQ.mermaidDidRender")
}
