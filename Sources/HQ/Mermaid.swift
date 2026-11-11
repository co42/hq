import AppKit
import WebKit

/// Draws Mermaid diagrams with the bundled mermaid.js in a hidden web view, as PDF images that views show natively.
/// One diagram at a time; each source and appearance is drawn once, a failure again a minute later.
final class MermaidRenderer: NSObject, WKNavigationDelegate {
    static let shared = MermaidRenderer()

    enum Result {
        case image(NSImage)
        case failed(String)
    }

    /// A diagram that takes longer fails, and the page is made again for the next one.
    static var timeout: Duration = .seconds(5)
    /// A failure is shown this long before the diagram is tried again.
    static var failureLasts: TimeInterval = 60

    private var cache: [String: Result] = [:]
    private var failures: [String: (message: String, at: Date)] = [:]
    private var webView: WKWebView?
    private var loaded: CheckedContinuation<Void, Never>?
    private var loading: Task<WKWebView?, Never>?
    /// The page didn't load: it's made again on next use.
    private var loadFailed = false
    /// The page while it loads.
    private weak var loadingView: WKWebView?
    /// The diagram being drawn: the next one waits for it.
    private var last: Task<Result, Never>?

    func cached(_ source: String, dark: Bool) -> Result? {
        let key = Self.key(source, dark)
        if let hit = cache[key] { return hit }
        guard let failure = failures[key], Date.now.timeIntervalSince(failure.at) < Self.failureLasts else { return nil }
        return .failed(failure.message)
    }

    /// Diagrams asked for and not drawn yet: snapshots wait for them.
    private(set) var drawing = 0
    /// Pages made so far: a new one after a timeout or a lost web process.
    private(set) var pages = 0

    /// The page's web process, for the self-test.
    var webProcess: pid_t? {
        guard let webView, webView.responds(to: NSSelectorFromString("_webProcessIdentifier")) else { return nil }
        return (webView.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value
    }

    func render(_ source: String, dark: Bool) async -> Result {
        if let hit = cached(source, dark: dark) { return hit }
        let key = Self.key(source, dark)
        drawing += 1
        defer { drawing -= 1 }
        let previous = last
        let task = Task { () -> Result in
            _ = await previous?.value
            if let hit = cached(source, dark: dark) { return hit }
            let result = await drawInTime(source, dark: dark)
            switch result {
            case .image: cache[key] = result
            case .failed(let message): failures[key] = (message, .now)
            }
            NotificationCenter.default.post(name: .mermaidDidRender, object: nil)
            return result
        }
        last = task
        return await task.value
    }

    /// The diagram, or a failure once `timeout` passes: then the page is dropped, so the next diagram doesn't wait on it.
    private func drawInTime(_ source: String, dark: Bool) async -> Result {
        let race = Race()
        // A new page loads mermaid.js first.
        let limit = webView == nil ? Self.timeout * 3 : Self.timeout
        return await withCheckedContinuation { continuation in
            race.continuation = continuation
            Task {
                var result = await draw(source, dark: dark)
                // A page whose web process went away: once more on a new one.
                if case .failed(Self.lostPage) = result, race.continuation != nil {
                    dropPage()
                    result = await draw(source, dark: dark)
                }
                race.finish(result)
            }
            Task {
                try? await Task.sleep(for: limit)
                guard race.continuation != nil else { return }
                NSLog("HQ: a Mermaid diagram took over %@ to draw: the page is made again", "\(limit)")
                dropPage()
                race.finish(.failed("It took too long to draw"))
            }
        }
    }

    /// Resumes its continuation once: with the first of the drawing and the timeout.
    private final class Race {
        var continuation: CheckedContinuation<Result, Never>?

        func finish(_ result: Result) {
            continuation?.resume(returning: result)
            continuation = nil
        }
    }

    /// Forgets the page: the next diagram loads a new one. Failures may have come from it, so they go too.
    private func dropPage() {
        for page in [webView, loadingView].compactMap(\.self) {
            page.navigationDelegate = nil
            page.stopLoading()
        }
        webView = nil
        loading = nil
        generation += 1
        finishLoading()
        failures.removeAll()
    }

    /// Counts dropped pages: a page still loading when it's dropped isn't used.
    private var generation = 0

    private static var hasScript: Bool { Bundle.main.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "Mermaid") != nil }

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
        guard let web = await page() else { return .failed(Self.hasScript ? "Its page didn’t load" : "mermaid.js isn’t in HQ’s bundle") }
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
            let error = error as NSError
            let message = error.userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
            let gone = [WKError.Code.webContentProcessTerminated.rawValue, WKError.Code.webViewInvalidated.rawValue]
            if (error.domain == WKError.errorDomain && gone.contains(error.code)) || message.contains("Can't find variable: mermaid") {
                return .failed(Self.lostPage)
            }
            return .failed(message.replacingOccurrences(of: "Error: ", with: ""))
        }
    }

    /// What a draw says when its page lost its web process or its script.
    private static let lostPage = "Its page went away"

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

    /// The web view with mermaid.js loaded, made on first use and again after it's dropped or didn't load.
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
            loadingView = web
            pages += 1
            loadFailed = false
            let made = generation
            await withCheckedContinuation { continuation in
                loaded = continuation
                web.loadHTMLString(Self.html, baseURL: nil)
            }
            guard made == generation else { return nil }
            guard !loadFailed else {
                loading = nil
                return nil
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

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated {
            NSLog("HQ: the Mermaid page didn't load: %@", error.localizedDescription)
            loadFailed = true
            finishLoading()
        }
    }

    /// WebKit ended the page's process: the next diagram makes a new page.
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated {
            NSLog("HQ: the Mermaid page's web process ended: it's made again on the next diagram")
            if webView === self.webView || webView === loadingView { dropPage() }
        }
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
