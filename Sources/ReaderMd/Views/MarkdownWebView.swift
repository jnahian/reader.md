import SwiftUI
import WebKit
import UniformTypeIdentifiers

extension Bundle {
    /// Resource bundle that works both under `swift run` and inside a packaged .app.
    /// Bundle.module's generated accessor looks next to the executable / at the .app
    /// root — neither is signable. make-app.sh instead copies resources into
    /// Contents/Resources, where Bundle.main finds them. Fall back to .module for dev.
    static var resources: Bundle {
        Bundle.main.url(forResource: "web", withExtension: nil) != nil ? .main : .module
    }
}

/// Wraps a WKWebView that renders markdown via bundled JS (marked, highlight.js, KaTeX, Mermaid).
struct MarkdownWebView: NSViewRepresentable {
    @EnvironmentObject var state: AppState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        for name in ["ready", "toc", "activeHeading", "openExternal", "openFile", "wordCount", "progress"] {
            controller.add(context.coordinator, name: name)
        }
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // transparent → matches theme
        context.coordinator.webView = webView

        guard let webDir = Bundle.resources.url(forResource: "web", withExtension: nil) else {
            return webView
        }
        let template = webDir.appendingPathComponent("template.html")
        // Broad read access so file:// images referenced by local markdown load.
        webView.loadFileURL(template, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator
        coord.state = state
        coord.applyTheme(isDark: context.environment.colorScheme == .dark)
        coord.applyTypography(scale: state.fontScale, wide: state.wideReading)

        if let file = state.selectedFile, file.url.path != coord.loadedPath {
            coord.load(file: file)
        } else if state.selectedFile == nil {
            coord.clear()
        } else if state.reloadToken != coord.lastReloadToken {
            coord.reloadCurrent()
        }
        coord.lastReloadToken = state.reloadToken

        // Native TOC scroll request.
        if let target = state.pendingScroll {
            coord.scroll(to: target)
            Task { @MainActor in state.pendingScroll = nil }
        }

        // In-page find.
        coord.applyFind(query: state.showFind ? state.findQuery : "")
        if state.findNextToken != coord.lastFindNext {
            coord.lastFindNext = state.findNextToken
            coord.findStep(forward: true)
        }
        if state.findPrevToken != coord.lastFindPrev {
            coord.lastFindPrev = state.findPrevToken
            coord.findStep(forward: false)
        }

        // Export to PDF.
        if state.exportToken != coord.lastExport {
            coord.lastExport = state.exportToken
            coord.exportPDF()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var state: AppState
        weak var webView: WKWebView?
        var isReady = false
        var loadedPath: String?
        var lastReloadToken: Int = 0
        var lastFindNext: Int = 0
        var lastFindPrev: Int = 0
        var lastExport: Int = 0
        private var lastDark: Bool?
        private var lastScale: Double?
        private var lastWide: Bool?
        private var lastFindQuery: String = ""

        init(state: AppState) {
            self.state = state
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}

        func applyTheme(isDark: Bool) {
            guard isReady, lastDark != isDark else { lastDark = isDark; return }
            lastDark = isDark
            webView?.evaluateJavaScript("window.ReaderMd.setTheme(\(isDark));")
        }

        func applyTypography(scale: Double, wide: Bool) {
            guard isReady else { lastScale = scale; lastWide = wide; return }
            if lastScale != scale {
                lastScale = scale
                webView?.evaluateJavaScript("window.ReaderMd.setFontScale(\(scale));")
            }
            if lastWide != wide {
                lastWide = wide
                webView?.evaluateJavaScript("window.ReaderMd.setWide(\(wide));")
            }
        }

        func load(file: FileNode) {
            loadedPath = file.url.path
            guard isReady else { return }
            pushCurrentFile(keepScroll: false)
        }

        func clear() {
            loadedPath = nil
            guard isReady else { return }
            webView?.evaluateJavaScript("window.ReaderMd.loadMarkdown('', '');")
        }

        func reloadCurrent() {
            guard isReady, loadedPath != nil else { return }
            pushCurrentFile(keepScroll: true)
        }

        private func pushCurrentFile(keepScroll: Bool) {
            guard let path = loadedPath else { return }
            let dir = (path as NSString).deletingLastPathComponent
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            let fn = keepScroll ? "reloadMarkdown" : "loadMarkdown"
            webView?.evaluateJavaScript("window.ReaderMd.\(fn)(\(Self.encode(text)), \(Self.encode(dir)));")
        }

        func scroll(to id: String) {
            webView?.evaluateJavaScript("window.ReaderMd.scrollToHeading(\(Self.encode(id)));")
        }

        // MARK: Find

        func applyFind(query: String) {
            guard isReady, query != lastFindQuery else { return }
            lastFindQuery = query
            guard let webView else { return }
            if query.isEmpty {
                webView.evaluateJavaScript("window.getSelection().removeAllRanges();")
                return
            }
            let cfg = WKFindConfiguration()
            cfg.caseSensitive = false
            cfg.wraps = true
            webView.find(query, configuration: cfg) { _ in }
        }

        func findStep(forward: Bool) {
            guard isReady, !lastFindQuery.isEmpty, let webView else { return }
            let cfg = WKFindConfiguration()
            cfg.caseSensitive = false
            cfg.wraps = true
            cfg.backwards = !forward
            webView.find(lastFindQuery, configuration: cfg) { _ in }
        }

        // MARK: Export

        func exportPDF() {
            guard let webView else { return }
            let cfg = WKPDFConfiguration()
            webView.createPDF(configuration: cfg) { result in
                guard case let .success(data) = result else { return }
                Task { @MainActor in self.savePDF(data) }
            }
        }

        @MainActor
        private func savePDF(_ data: Data) {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            let base = (loadedPath as NSString?)?.lastPathComponent ?? "document"
            panel.nameFieldStringValue = (base as NSString).deletingPathExtension + ".pdf"
            if panel.runModal() == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }

        /// JSON-encode a string into a safe JS string literal.
        private static func encode(_ s: String) -> String {
            let data = try? JSONSerialization.data(withJSONObject: [s], options: [])
            if let data, let json = String(data: data, encoding: .utf8) {
                return String(json.dropFirst().dropLast())
            }
            return "\"\""
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "ready":
                isReady = true
                if let dark = lastDark {
                    webView?.evaluateJavaScript("window.ReaderMd.setTheme(\(dark));")
                }
                if let scale = lastScale { webView?.evaluateJavaScript("window.ReaderMd.setFontScale(\(scale));") }
                if let wide = lastWide { webView?.evaluateJavaScript("window.ReaderMd.setWide(\(wide));") }
                if loadedPath != nil { pushCurrentFile(keepScroll: false) }

            case "toc":
                guard let arr = message.body as? [[String: Any]] else { return }
                let entries: [TOCEntry] = arr.compactMap { item in
                    guard let id = item["id"] as? String,
                          let text = item["text"] as? String,
                          let level = item["level"] as? Int else { return nil }
                    return TOCEntry(id: id, text: text, level: level)
                }
                Task { @MainActor in
                    self.state.toc = entries
                    if self.state.activeHeadingID == nil { self.state.activeHeadingID = entries.first?.id }
                }

            case "activeHeading":
                guard let id = message.body as? String else { return }
                Task { @MainActor in self.state.activeHeadingID = id }

            case "wordCount":
                guard let n = message.body as? Int else { return }
                Task { @MainActor in self.state.wordCount = n }

            case "progress":
                guard let p = message.body as? Double else { return }
                Task { @MainActor in self.state.scrollProgress = p }

            case "openExternal":
                if let s = message.body as? String, let url = URL(string: s) {
                    NSWorkspace.shared.open(url)
                }

            case "openFile":
                if let path = message.body as? String {
                    Task { @MainActor in self.state.openPath(path) }
                }

            default:
                break
            }
        }
    }
}
