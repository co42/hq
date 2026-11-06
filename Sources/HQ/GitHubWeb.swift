import AppKit
import SwiftUI
import WebKit

/// A pull request's or an issue's page on github.com, so the user reads and reviews it without leaving HQ. HQ keeps its own
/// GitHub sign-in, apart from the browser's, in a persistent cookie store; test runs keep nothing and never reach the network.
struct GitHubWebView: NSViewRepresentable {
    let url: URL
    /// A stand-in page for test runs and snapshots.
    var standIn: String?
    @Binding var state: ArtifactLoad
    /// Bumped by Reload.
    var reloads = 0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = Self.store
        configuration.applicationNameForUserAgent = ArtifactWebView.safariName
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.underPageBackgroundColor = Ink.editorNS
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

    /// One store for every GitHub page, so one sign-in lasts.
    @MainActor static let store: WKWebsiteDataStore = Store.isOverridden
        ? .nonPersistent()
        : WKWebsiteDataStore(forIdentifier: UUID(uuidString: "0C4E8D7A-58B1-4F0E-A6D2-91B7E3C5A4F8")!)

    /// GitHub's own pages: a link to one stays in HQ.
    static func isGitHub(_ url: URL) -> Bool {
        guard let host = url.host() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com") || host.hasSuffix(".githubusercontent.com")
    }

    /// GitHub asks the user to sign in, or to pass their organization's single sign-on.
    static func isSignIn(_ url: URL) -> Bool {
        guard url.host() == "github.com" else { return false }
        let path = url.path()
        return path.hasPrefix("/login") || path.hasPrefix("/session") || path.hasPrefix("/sessions") || path.contains("/sso")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: GitHubWebView
        private var observation: NSKeyValueObservation?

        init(_ parent: GitHubWebView) {
            self.parent = parent
        }

        /// GitHub moves between its pages without a navigation: its URL says when it asks to sign in.
        func observe(_ web: WKWebView) {
            observation = web.observe(\.url) { [weak self] web, _ in
                MainActor.assumeIsolated {
                    guard let self, self.parent.standIn == nil, let url = web.url, url.host() == "github.com" else { return }
                    self.set(GitHubWebView.isSignIn(url) ? .signIn : .shown)
                }
            }
        }

        private func set(_ state: ArtifactLoad) {
            if parent.state != state { parent.state = state }
        }

        func load(_ web: WKWebView) {
            // Called while SwiftUI updates the view: the state changes right after.
            DispatchQueue.main.async { self.parent.state = .loading }
            if let html = parent.standIn {
                web.loadHTMLString(html, baseURL: nil)
            } else {
                web.load(URLRequest(url: parent.url))
            }
        }

        /// A link the user clicks from a GitHub page to another site opens in the browser. Redirects, forms and the
        /// pages of a sign-in (their organization's identity provider) stay here.
        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, action.targetFrame?.isMainFrame ?? true,
                  let url = action.request.url, !GitHubWebView.isGitHub(url), url.scheme?.hasPrefix("http") == true,
                  let current = web.url, GitHubWebView.isGitHub(current) else { return decisionHandler(.allow) }
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            if parent.standIn == nil, let url = web.url, GitHubWebView.isSignIn(url) {
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
            // A navigation replaced by the next one, or a link sent to the browser, isn't a failure.
            guard error.code != NSURLErrorCancelled, error.code != 102 else { return }
            set(.failed(error.localizedDescription))
        }

        /// Links that open a new window: GitHub's own pages load here, others open in the browser.
        func webView(_ web: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let url = action.request.url else { return nil }
            if GitHubWebView.isGitHub(url) {
                web.load(action.request)
            } else {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}
