import SwiftUI
import UIKit
import WebKit

struct WebScreen: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()   // keeps the login cookie between launches
        config.applicationNameForUserAgent = "StrapifyPicklistApp/1.0"
        let controller = WKUserContentController()
        // scan.js uses Apple's scanner when this is true (see NativeScanner); a browser never has it.
        let flag = "window.__nativeScanAvailable = \(NativeScanner.isSupported ? "true" : "false");"
        controller.addUserScript(WKUserScript(source: flag, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.add(context.coordinator.scanner, name: "picklistScan")
        config.userContentController = controller

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        // Lay out exactly like the Home Screen PWA: the page fills the whole screen and places
        // itself around the notch, home bar and the iPhone Duo's fold and side edges with its own
        // viewport-fit=cover + env(safe-area-inset-*) CSS. Letting UIKit also inset the scroll
        // view gave double (or missing) gaps.
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.bounces = false          // no rubber-band, like the PWA
        web.isOpaque = false
        web.backgroundColor = .systemBackground
        web.scrollView.backgroundColor = .systemBackground

        context.coordinator.scanner.web = web
        context.coordinator.web = web
        web.load(URLRequest(url: Config.start))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let scanner = NativeScanner()
        weak var web: WKWebView?

        /// A Swift string as a JavaScript string literal (quotes and escapes handled by JSON).
        static func jsString(_ value: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [value]),
                  let array = String(data: data, encoding: .utf8) else { return "\"\"" }
            return String(array.dropFirst().dropLast())
        }

        /// Own pages stay in the app; Shopify admin, tracking links etc. open in Safari or their own app.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
            let scheme = url.scheme?.lowercased() ?? ""
            if ["about", "blob", "data"].contains(scheme) { return decisionHandler(.allow) }
            let web = scheme == "http" || scheme == "https"
            let mainFrame = navigationAction.targetFrame?.isMainFrame ?? false
            // Our own pages, and anything loading inside a frame (link previews, PDFs), stay put.
            if web && (Config.isOwnHost(url) || !mainFrame) && navigationAction.targetFrame != nil {
                return decisionHandler(.allow)
            }
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        /// window.open / target=_blank: our own pages open in place, everything else in Safari.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                if Config.isOwnHost(url) {
                    webView.load(URLRequest(url: url))
                } else {
                    UIApplication.shared.open(url)
                }
            }
            return nil
        }

        /// The web camera fallback (photo / text scan): grant camera to our own site without a second web prompt
        /// (iOS still asks once for the app itself).
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
            decisionHandler(origin.host.lowercased() == "picklist.strapify.com.au" ? .grant : .prompt)
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
            present(message, ok: { completionHandler() }, cancel: nil)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
            present(message, ok: { completionHandler(true) }, cancel: { completionHandler(false) })
        }

        /// iOS can kill the web content process in the background; come back to a live page.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        private func present(_ message: String, ok: @escaping () -> Void, cancel: (() -> Void)?) {
            guard let root = web?.window?.rootViewController else {
                ok()
                return
            }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            if let cancel {
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in cancel() })
            }
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in ok() })
            var top = root
            while let next = top.presentedViewController { top = next }
            top.present(alert, animated: true)
        }
    }
}
