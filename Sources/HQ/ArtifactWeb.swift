import AppKit
import SwiftUI
import WebKit

/// A claude.ai artifact in a web view. HQ keeps its own claude.ai sign-in, apart from the
/// browser's, in a persistent cookie store; test runs keep nothing and never reach the network.
struct ArtifactWebView: NSViewRepresentable {
    let url: URL
    /// A stand-in page for test runs and snapshots.
    var standIn: String?
    @Binding var state: ArtifactLoad
    /// Bumped by Reload.
    var reloads = 0
    /// The artifact's own title, from its page.
    var onTitle: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = Self.store
        // As Safari: Google refuses sign-in in a web view it doesn't know.
        configuration.applicationNameForUserAgent = Self.safariName
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.underPageBackgroundColor = Ink.editorNS
        // No white flash in dark mode before the page paints.
        web.setValue(false, forKey: "drawsBackground")
        context.coordinator.observe(web)
        context.coordinator.load(web)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let coordinator = context.coordinator
        let reload = reloads != coordinator.parent.reloads
        coordinator.parent = self
        if reload { coordinator.load(web) }
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading()
    }

    /// One store for every artifact, so one sign-in lasts.
    @MainActor static let store: WKWebsiteDataStore = Store.isOverridden
        ? .nonPersistent()
        : WKWebsiteDataStore(forIdentifier: UUID(uuidString: "6F1B3C2A-1D7E-4B1C-9C55-2E1A7B0C4D21")!)

    /// "Version/26.0 Safari/605.1.15", from the installed Safari.
    static let safariName: String = {
        let version = Bundle(path: "/Applications/Safari.app")?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "26.0"
        return "Version/\(version) Safari/605.1.15"
    }()

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: ArtifactWebView
        /// claude.ai asked to sign in: once that's done, go back to the artifact.
        private var signingIn = false
        private var observations: [NSKeyValueObservation] = []

        init(_ parent: ArtifactWebView) {
            self.parent = parent
        }

        /// claude.ai routes in the page: its URL and title change without a navigation. WebKit reports both on the main thread.
        func observe(_ web: WKWebView) {
            observations = [
                web.observe(\.url) { [weak self] web, _ in MainActor.assumeIsolated { self?.changed(web) } },
                web.observe(\.title) { [weak self] web, _ in MainActor.assumeIsolated { self?.changed(web) } },
            ]
        }

        private func changed(_ web: WKWebView) {
            guard parent.standIn == nil, let url = web.url else { return }
            // The page's own title, once claude.ai shows the artifact: the one HQ lists it by.
            if !signingIn, url.path().contains("/artifact"), let title = ArtifactLoad.realTitle(web.title) {
                ArtifactLoad.log("title \(url.path()) “\(web.title ?? "")”")
                parent.onTitle(title)
            }
            let step = ArtifactLoad.step(url, title: web.title, artifact: parent.url, signingIn: signingIn)
            if signingIn || step != .none { ArtifactLoad.log("\(step) \(url.host() ?? "") \(url.path()) “\(web.title ?? "")”") }
            switch step {
            case .signIn:
                signingIn = true
                set(.signIn)
            case .shown:
                signingIn = false
                set(.shown)
            case .reload:
                load(web)
            case .none:
                break
            }
        }

        private func set(_ state: ArtifactLoad) {
            if parent.state != state { parent.state = state }
        }

        func load(_ web: WKWebView) {
            signingIn = false
            // Called while SwiftUI updates the view: the state changes right after.
            DispatchQueue.main.async { self.parent.state = .loading }
            if let html = parent.standIn {
                web.loadHTMLString(html, baseURL: nil)
            } else {
                web.load(URLRequest(url: parent.url))
            }
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            // Through the identity provider's pages, the bar keeps saying what's going on.
            if let url = web.url, parent.standIn == nil, signingIn || ArtifactLoad.isSignIn(url, title: web.title) {
                set(.signIn)
            } else {
                set(.shown)
            }
        }

        func webView(_ web: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            fail(error)
        }

        func webView(_ web: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            fail(error)
        }

        private func fail(_ error: any Error) {
            let error = error as NSError
            if signingIn { ArtifactLoad.log("error \(error.code) \(error.localizedDescription)") }
            // A navigation replaced by the next one isn't a failure.
            guard error.code != NSURLErrorCancelled else { return }
            set(.failed(error.localizedDescription))
        }

        /// Links that open a new window: sign-in stays here, whatever its host; anything else opens in the browser.
        func webView(_ web: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let url = action.request.url else { return nil }
            if signingIn || ArtifactLoad.staysInHQ(url) {
                web.load(action.request)
            } else {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}

/// Where an artifact's web view is.
enum ArtifactLoad: Equatable {
    case loading
    case shown
    /// claude.ai shows its sign-in page.
    case signIn
    case failed(String)

    /// An artifact page's title without claude.ai's name; nil for claude.ai's own pages ("Claude", sign-in).
    static func realTitle(_ title: String?) -> String? {
        var text = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" | Claude", " - Claude", " – Claude", " — Claude"] where text.hasSuffix(suffix) { text.removeLast(suffix.count) }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text != "Claude", !text.hasPrefix("Sign in") else { return nil }
        return text
    }

    /// Signed out, an artifact's own URL shows "Sign in to view this page", titled "Sign in – Claude".
    static func isSignIn(_ url: URL, title: String?) -> Bool {
        guard url.host() == "claude.ai" else { return false }
        return url.path().hasPrefix("/login") || url.path().hasPrefix("/magic-link") || (title ?? "").hasPrefix("Sign in")
    }

    /// What a page change means while an artifact loads or the user signs in.
    enum Step: Equatable {
        case signIn, shown
        /// Signed in, but claude.ai lost the way back: load the artifact again.
        case reload
        case none
    }

    /// Only claude.ai's home pages send the user back to the artifact: any other page on the way may be
    /// the identity provider's callback, which must finish to set the session.
    static func step(_ url: URL, title: String?, artifact: URL, signingIn: Bool) -> Step {
        if isSignIn(url, title: title) { return .signIn }
        guard signingIn, url.host() == artifact.host() else { return .none }
        if url.path() == artifact.path() { return .shown }
        return isHome(url) ? .reload : .none
    }

    static func isHome(_ url: URL) -> Bool {
        url.host() == "claude.ai" && ["", "/", "/new", "/recents"].contains(url.path())
    }

    /// The sign-in's steps, host and path only, in ~/Library/Logs/HQ/claude-sign-in.log, to see where one stops.
    static func log(_ line: String) {
        AppLog.write(line, to: "claude-sign-in.log")
    }

    /// claude.ai, and the pages its sign-in goes through.
    static func staysInHQ(_ url: URL) -> Bool {
        guard let host = url.host() else { return false }
        return ["claude.ai", "accounts.google.com", "appleid.apple.com"].contains(host) || host.hasSuffix(".claude.ai")
    }
}
