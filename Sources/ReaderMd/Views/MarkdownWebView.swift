import SwiftUI
import AppKit
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

/// WKWebView that accepts file/folder drops (the plain web view swallows the
/// drag before SwiftUI's .onDrop can see it, so drops over the body do nothing).
final class DropWebView: WKWebView {
    var onDrop: ((URL) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedURLs(sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedURLs(sender)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        urls.forEach { onDrop?($0) }
        return true
    }

    private func droppedURLs(_ sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}

/// Wraps a WKWebView that renders markdown via bundled JS (marked, highlight.js, KaTeX, Mermaid).
struct MarkdownWebView: NSViewRepresentable {
    @EnvironmentObject var state: AppState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        let messageNames = ["ready", "toc", "activeHeading", "openExternal", "openFile", "wordCount", "progress",
                             "rendered", "textSelected", "markClicked", "marksApplied"]
        for name in messageNames {
            controller.add(context.coordinator, name: name)
        }
        config.userContentController = controller

        let webView = DropWebView(frame: .zero, configuration: config)
        webView.registerForDraggedTypes([.fileURL])
        webView.onDrop = { [weak coord = context.coordinator] url in
            Task { @MainActor in coord?.state.openDropped(url) }
        }
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

        // Highlights: re-apply whenever the mark set OR resolved-thread visibility
        // changes. A fresh render always re-applies too (see the "rendered" message
        // handler), since re-rendering wipes the <mark> wrapper spans regardless.
        if coord.isReady, state.marks != coord.lastPushedMarks || state.showResolvedThreads != coord.lastShowResolved {
            coord.lastPushedMarks = state.marks
            coord.lastShowResolved = state.showResolvedThreads
            coord.applyMarks(json: state.marksJSON())
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
        var lastPushedMarks: [Mark] = []
        var lastShowResolved: Bool = true
        private var lastDark: Bool?
        private var lastScale: Double?
        private var lastWide: Bool?
        private var lastFindQuery: String = ""
        private var activePopover: NSPopover?

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

        // MARK: Highlights (#1)

        func applyMarks(json: String) {
            webView?.evaluateJavaScript("window.ReaderMd.applyMarks(\(Self.encode(json)));")
        }

        /// Selection popover: pick a color and/or start a thread on a new highlight.
        private func showCreatePopover(anchor: TextAnchor, rect: [String: Double]) {
            let defaultColor = HighlightColor.yellow
            let view = MarkPopoverView(
                color: nil,
                comments: [],
                resolved: false,
                onPickColor: { [weak self] color in
                    guard let self else { return }
                    Task { @MainActor in self.state.createMark(anchor: anchor, color: color) }
                    self.hidePopover()
                },
                onReply: { [weak self] text in
                    guard let self else { return }
                    Task { @MainActor in self.state.createMark(anchor: anchor, color: defaultColor, note: text) }
                    self.hidePopover()
                },
                onDeleteThread: nil,
                onToggleResolved: nil,
                onRemoveMark: nil
            )
            presentPopover(view, rect: rect)
        }

        /// Existing-highlight popover: change color, manage its thread, or remove it.
        private func showEditPopover(markID: UUID, rect: [String: Double]) {
            Task { @MainActor in
                guard let mark = self.state.marks.first(where: { $0.id == markID }) else { return }
                let view = MarkPopoverView(
                    color: mark.color,
                    comments: mark.comments,
                    resolved: mark.resolved,
                    onPickColor: { [weak self] color in
                        guard let self else { return }
                        Task { @MainActor in self.state.setMarkColor(markID, color: color) }
                        self.hidePopover()
                    },
                    onReply: { [weak self] text in
                        guard let self else { return }
                        // Re-show (not just hide) so the thread list reflects the new
                        // reply — the popover's view was built from a value snapshot,
                        // it doesn't observe AppState changes on its own.
                        Task { @MainActor in
                            self.state.addComment(markID, text: text)
                            self.hidePopover()
                            self.showEditPopover(markID: markID, rect: rect)
                        }
                    },
                    onDeleteThread: { [weak self] in
                        guard let self else { return }
                        Task { @MainActor in self.state.deleteThread(markID) }
                        self.hidePopover()
                    },
                    onToggleResolved: { [weak self] in
                        guard let self else { return }
                        Task { @MainActor in self.state.setResolved(markID, resolved: !mark.resolved) }
                        self.hidePopover()
                    },
                    onRemoveMark: { [weak self] in
                        guard let self else { return }
                        Task { @MainActor in self.state.deleteMark(markID) }
                        self.hidePopover()
                    }
                )
                self.presentPopover(view, rect: rect)
            }
        }

        private func presentPopover<Content: View>(_ content: Content, rect: [String: Double]) {
            guard let webView else { return }
            hidePopover()
            let controller = NSHostingController(rootView: content)
            let popover = NSPopover()
            popover.contentViewController = controller
            popover.behavior = .transient
            activePopover = popover
            popover.show(relativeTo: positioningRect(from: rect, in: webView), of: webView, preferredEdge: .maxY)
        }

        private func hidePopover() {
            activePopover?.performClose(nil)
            activePopover = nil
        }

        /// The `rect` payload from JS is viewport-relative CSS px (top-left origin);
        /// convert to the webView's own coordinate space for NSPopover positioning.
        private func positioningRect(from rect: [String: Double], in view: NSView) -> NSRect {
            let x = rect["x"] ?? 0, y = rect["y"] ?? 0
            let w = max(rect["width"] ?? 0, 1), h = max(rect["height"] ?? 0, 1)
            if view.isFlipped {
                return NSRect(x: x, y: y, width: w, height: h)
            }
            return NSRect(x: x, y: view.bounds.height - y - h, width: w, height: h)
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

            case "rendered":
                // A fresh render wipes any <mark> wrapper spans — always re-apply.
                Task { @MainActor in
                    self.lastPushedMarks = self.state.marks
                    self.lastShowResolved = self.state.showResolvedThreads
                    self.applyMarks(json: self.state.marksJSON())
                }

            case "textSelected":
                guard let payload = message.body as? [String: Any],
                      let quote = payload["quote"] as? String,
                      let prefix = payload["prefix"] as? String,
                      let suffix = payload["suffix"] as? String,
                      let startOffset = payload["startOffset"] as? Int,
                      let rect = payload["rect"] as? [String: Double] else {
                    hidePopover()
                    return
                }
                let anchor = TextAnchor(quote: quote, prefix: prefix, suffix: suffix, startOffset: startOffset)
                showCreatePopover(anchor: anchor, rect: rect)

            case "markClicked":
                guard let payload = message.body as? [String: Any],
                      let idString = payload["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let rect = payload["rect"] as? [String: Double] else { return }
                showEditPopover(markID: id, rect: rect)

            case "marksApplied":
                guard let ids = message.body as? [String] else { return }
                Task { @MainActor in self.state.setOrphanedMarkIDs(ids) }

            default:
                break
            }
        }
    }
}
