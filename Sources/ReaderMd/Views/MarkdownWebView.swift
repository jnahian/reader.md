import SwiftUI
import AppKit
import WebKit
import PDFKit
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
    /// Because this view consumes the drag, SwiftUI's `.onDrop(isTargeted:)` on
    /// ContentView never fires over the content pane. Report targeting up so the
    /// drop overlay appears here too — otherwise it only shows over the chrome,
    /// which is not where anyone drags.
    var onDragTargeted: ((Bool) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !droppedURLs(sender).isEmpty else { return super.draggingEntered(sender) }
        onDragTargeted?(true)
        return .copy
    }

    /// This override is the one that makes drops work at all over a rendered document.
    /// AppKit decides whether to permit a drop from the *last* draggingUpdated answer,
    /// and WKWebView's implementation returns `.none` — it asks the loaded page, which
    /// doesn't want the file. Without this, draggingEntered's `.copy` was overruled on
    /// the very next mouse move and performDragOperation never ran. Drops appeared to
    /// work only on the empty state, where the web view isn't the drag destination.
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedURLs(sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragTargeted?(false)
        super.draggingExited(sender)
    }

    /// No `super` call: `draggingEnded(_:)` is an *optional* NSDraggingDestination method
    /// and neither NSView nor WKWebView implements it, so `super.draggingEnded` raises
    /// "unrecognized selector". AppKit swallows the exception but leaves the drag session
    /// broken — the first drop lands, every drop after it is silently ignored.
    /// (`draggingExited(_:)` above is different: NSView does implement that one.)
    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDragTargeted?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragTargeted?(false)
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

/// Shown in place of the diff for a file with unresolved merge conflicts — `git diff`
/// on an unmerged path emits combined-diff format the hunk renderer doesn't understand.
/// Shared by updateNSView and the coordinator's "ready" handler so the two can't drift.
private let conflictNoticeMessage = "This file has unresolved merge conflicts"

/// Wraps a WKWebView that renders markdown via bundled JS (marked, highlight.js, KaTeX, Mermaid).
struct MarkdownWebView: NSViewRepresentable {
    @EnvironmentObject var state: AppState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Paginated ⌘E export prints; printing drops CSS backgrounds unless
        // asked not to. 13.3+ only — on 13.0–13.2 page-by-page exports print
        // on white, accepted per the design spec.
        if #available(macOS 13.3, *) {
            config.preferences.shouldPrintBackgrounds = true
        }
        let controller = WKUserContentController()
        let messageNames = ["ready", "toc", "activeHeading", "openExternal", "openFile", "wordCount", "progress",
                             "rendered", "textSelected", "markClicked", "marksApplied", "findResult",
                             "diagramFullscreen"]
        for name in messageNames {
            controller.add(context.coordinator, name: name)
        }
        config.userContentController = controller

        let webView = DropWebView(frame: .zero, configuration: config)
        webView.registerForDraggedTypes([.fileURL])
        webView.onDrop = { [weak coord = context.coordinator] url in
            Task { @MainActor in coord?.state.openDropped(url) }
        }
        webView.onDragTargeted = { [weak coord = context.coordinator] targeted in
            Task { @MainActor in coord?.state.webDropTargeted = targeted }
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
        coord.applyAccent(isDark: context.environment.colorScheme == .dark)
        coord.applyReadingTheme(state.readingTheme.rawValue)
        coord.applyTypography(scale: state.fontScale, width: state.contentWidth)

        if state.canShowDiff {
            let pathChanged = coord.loadedPath != state.selectedFile?.url.path
            let tokenChanged = state.diffToken != coord.lastDiffToken
            if pathChanged {
                coord.loadedPath = state.selectedFile?.url.path
            }
            if pathChanged || tokenChanged {
                if let path = state.selectedFile?.url.path, state.gitStatus(for: path) == .conflicted {
                    coord.pushDiff(nil, empty: conflictNoticeMessage)
                } else if pathChanged && !tokenChanged {
                    // AppState.refreshDiff() recomputes the diff on a detached Task, so
                    // right after a file switch state.diffFile still holds the PREVIOUS
                    // file's hunks for a frame. Push a neutral placeholder instead of
                    // those stale hunks under the new file's name; the real diff follows
                    // once diffToken lands and tokenChanged fires on its own.
                    coord.pushDiff(nil, empty: "Loading diff…")
                } else {
                    coord.pushDiff(state.diffFile, empty: state.diffScope.emptyMessage)
                }
            }
        } else if let file = state.selectedFile, file.url.path != coord.loadedPath || coord.showingDiff {
            coord.load(file: file, resume: state.savedProgress(for: file.url.path))
        } else if state.selectedFile == nil {
            coord.clear()
        } else if state.reloadToken != coord.lastReloadToken {
            coord.reloadCurrent()
        }
        coord.lastReloadToken = state.reloadToken
        coord.lastDiffToken = state.diffToken

        // Native TOC scroll request.
        if let target = state.pendingScroll {
            coord.scroll(to: target)
            Task { @MainActor in state.pendingScroll = nil }
        }

        // In-page find.
        coord.applyFind(query: state.findQuery)
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

        // Share the rendered PDF.
        if state.shareToken != coord.lastShare {
            coord.lastShare = state.shareToken
            coord.sharePDF()
        }

        // Share the markdown file itself.
        if state.shareSourceToken != coord.lastShareSource {
            coord.lastShareSource = state.shareSourceToken
            coord.shareSource()
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
        var pendingResume: Double = 0
        var lastReloadToken: Int = 0
        var lastDiffToken = 0
        /// True while the web view is showing a diff, so leaving diff mode
        /// forces a re-render even though the path didn't change.
        var showingDiff = false
        var lastFindNext: Int = 0
        var lastFindPrev: Int = 0
        var lastExport: Int = 0
        var lastShare: Int = 0
        var lastShareSource: Int = 0
        var lastPushedMarks: [Mark] = []
        var lastShowResolved: Bool = true
        private var lastDark: Bool?
        private var lastAccent: String?
        private var lastReadingTheme: String?
        private var lastScale: Double?
        private var lastWidth: ContentWidth?
        private var lastFindQuery: String = ""
        private var activePopover: NSPopover?

        init(state: AppState) {
            self.state = state
            super.init()
            // Re-push when the user changes their accent in System Settings.
            NotificationCenter.default.addObserver(
                self, selector: #selector(systemColorsChanged),
                name: NSColor.systemColorsDidChangeNotification, object: nil)
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        @objc private func systemColorsChanged() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lastAccent = nil // force a re-push; the accent name → hex mapping changed
                self.applyAccent(isDark: self.lastDark ?? false)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}

        func applyTheme(isDark: Bool) {
            guard isReady, lastDark != isDark else { lastDark = isDark; return }
            lastDark = isDark
            webView?.evaluateJavaScript("window.ReaderMd.setTheme(\(isDark));")
        }

        /// Push the macOS accent color into the content pane so the standard theme's
        /// links follow System Settings. Resolved per light/dark, since the accent
        /// maps to a different concrete color in each. bridge.js applies it to the
        /// standard theme only — custom reading themes keep their own accents.
        func applyAccent(isDark: Bool) {
            let hex = Self.accentHex(isDark: isDark)
            guard isReady, lastAccent != hex else { lastAccent = hex; return }
            lastAccent = hex
            webView?.evaluateJavaScript("window.ReaderMd.setAccent('\(hex)');")
        }

        /// `NSColor.controlAccentColor` is a dynamic catalog color; resolve it under
        /// the active appearance and flatten to sRGB for a stable `#rrggbb` string.
        private static func accentHex(isDark: Bool) -> String {
            var resolved = NSColor.controlAccentColor
            NSAppearance(named: isDark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                resolved = NSColor.controlAccentColor
            }
            // If the catalog color won't flatten to sRGB, fall back to the theme's
            // own accent rather than reading components off a non-RGB color (throws).
            guard let c = resolved.usingColorSpace(.sRGB) else { return isDark ? "#4493f8" : "#0969da" }
            let r = Int((c.redComponent * 255).rounded())
            let g = Int((c.greenComponent * 255).rounded())
            let b = Int((c.blueComponent * 255).rounded())
            return String(format: "#%02x%02x%02x", r, g, b)
        }

        func applyReadingTheme(_ name: String) {
            guard isReady, lastReadingTheme != name else { lastReadingTheme = name; return }
            lastReadingTheme = name
            webView?.evaluateJavaScript("window.ReaderMd.setReadingTheme('\(name)');")
        }

        func applyTypography(scale: Double, width: ContentWidth) {
            guard isReady else { lastScale = scale; lastWidth = width; return }
            if lastScale != scale {
                lastScale = scale
                webView?.evaluateJavaScript("window.ReaderMd.setFontScale(\(scale));")
            }
            if lastWidth != width {
                lastWidth = width
                webView?.evaluateJavaScript("window.ReaderMd.setContentWidth('\(width.css)');")
            }
        }

        /// `resume` is the saved scroll fraction; the web view applies it once the
        /// document has rendered. Held on the coordinator so a load that arrives
        /// before `ready` still resumes when it's flushed.
        func load(file: FileNode, resume: Double) {
            loadedPath = file.url.path
            pendingResume = resume
            guard isReady else { return }
            pushCurrentFile(keepScroll: false)
        }

        /// Clearing an already-empty view must be a no-op. updateNSView runs on every
        /// SwiftUI pass, and the render this kicks off posts toc/wordCount/progress back
        /// to AppState — @Published writes, which schedule the next pass. Re-clearing
        /// unconditionally made that a loop that pinned the main thread at 100%, and a
        /// pinned main thread stops delivering mouse-moved: no :hover anywhere in the page.
        func clear() {
            guard loadedPath != nil || showingDiff else { return }
            loadedPath = nil
            showingDiff = false
            guard isReady else { return }
            webView?.evaluateJavaScript("window.ReaderMd.loadMarkdown('', '');")
        }

        func reloadCurrent() {
            guard isReady, loadedPath != nil else { return }
            pushCurrentFile(keepScroll: true)
        }

        func pushDiff(_ file: DiffFile?, empty: String) {
            guard isReady else { return }
            showingDiff = true
            let json = file?.jsonPayload() ?? "{\"hunks\":[],\"empty\":\(Self.encode(empty))}"
            webView?.evaluateJavaScript("window.ReaderMd.loadDiff(\(Self.encode(json)));")
        }

        private func pushCurrentFile(keepScroll: Bool) {
            if showingDiff {
                showingDiff = false
                webView?.evaluateJavaScript("window.ReaderMd.clearDiff();")
            }
            guard let path = loadedPath else { return }
            let dir = (path as NSString).deletingLastPathComponent
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            if keepScroll {
                webView?.evaluateJavaScript("window.ReaderMd.reloadMarkdown(\(Self.encode(text)), \(Self.encode(dir)));")
            } else {
                webView?.evaluateJavaScript("window.ReaderMd.loadMarkdown(\(Self.encode(text)), \(Self.encode(dir)), \(pendingResume));")
            }
        }

        func scroll(to id: String) {
            webView?.evaluateJavaScript("window.ReaderMd.scrollToHeading(\(Self.encode(id)));")
        }

        // MARK: Highlights (#1)

        func applyMarks(json: String) {
            guard !showingDiff else { return }
            webView?.evaluateJavaScript("window.ReaderMd.applyMarks(\(Self.encode(json)));")
            // Re-apply find AFTER marks so find wraps nest inside highlight wraps
            // (deterministic nesting). Both eval calls hit the same JS API in order.
            // refind(), not find() — it keeps the current match and does not scroll,
            // so an FSEvents re-render can't yank the viewport away from the reader.
            if !lastFindQuery.isEmpty {
                webView?.evaluateJavaScript("window.ReaderMd.refind();")
            }
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
            // getBoundingClientRect gives top-left viewport px; this WKWebView is
            // isFlipped, and NSPopover positions the rect in that same top-left
            // space — so pass y straight through. Measured on-device: flipping via
            // bounds.height mirrors the anchor to the wrong end. Do not flip.
            return NSRect(x: x, y: y, width: w, height: h)
        }

        // MARK: Find
        //
        // Find is JS-driven (bridge.js) — the native WKWebView.find gave no match
        // count and highlighted only the current match. applyFind is idempotent per
        // query via lastFindQuery; the rendered/marks path re-applies out-of-band.

        func applyFind(query: String) {
            guard isReady, query != lastFindQuery else { return }
            lastFindQuery = query
            webView?.evaluateJavaScript("window.ReaderMd.find(\(Self.encode(query)));")
        }

        func findStep(forward: Bool) {
            guard isReady, !lastFindQuery.isEmpty else { return }
            webView?.evaluateJavaScript("window.ReaderMd.findStep(\(forward));")
        }

        // MARK: Export

        func exportPDF() {
            // The export token lands here from inside updateNSView — a SwiftUI
            // render pass. The save panel's accessory view never attaches when
            // runModal starts there (the remote panel boots without it), so the
            // panel has to wait a tick — same reason ⌘F defers its focus grab.
            DispatchQueue.main.async { [weak self] in self?.presentExportPanel() }
        }

        func sharePDF() {
            // Deferred for the same reason exportPDF() is: the token arrives
            // inside a SwiftUI render pass. Setting `sharing` here rather than in
            // triggerShare() keeps that @Published write out of the pass too —
            // mutating observed state during an update is the "Publishing changes
            // from within view updates" warning, and a real source of loops.
            DispatchQueue.main.async { [weak self] in
                // No webView check here — renderPDF does it, and reports the
                // failure through the completion that clears `sharing`.
                guard let self else { return }
                state.sharing = true
                let url = ShareTemp.url(for: loadedPath)
                // `state` is captured strongly, not reached through `self`:
                // AppState outlives this coordinator, and a window closed
                // mid-render would otherwise drop the completion with `sharing`
                // still true — latching the flag on, so every later share is
                // refused by triggerShare()'s guard until the app restarts.
                let state = state
                renderPDF(to: url, layout: state.exportLayout) { [weak self] ok in
                    state.sharing = false
                    // A failed render matches export: return silently. An alert
                    // here would be the only one in the app.
                    guard ok, let self else { return }
                    presentSharePicker(for: url)
                }
            }
        }

        /// Shares the markdown itself. No render, so no temp file and no
        /// in-flight flag — the picker opens on the document where it sits.
        func shareSource() {
            // Deferred like the other two: the token arrives mid-render-pass.
            DispatchQueue.main.async { [weak self] in
                guard let self, let url = state.selectedFile?.url else { return }
                presentSharePicker(for: url)
            }
        }

        /// The picker needs a real NSView to anchor to, and a SwiftUI toolbar
        /// item doesn't hand you one. The web view's top-trailing corner sits
        /// directly under the toolbar, so .maxY puts the picker where the share
        /// button is. (Reading the item out of `window.toolbar?.items` would
        /// depend on SwiftUI's generated identifiers and break silently.)
        ///
        /// Main queue only: NSSharingServicePicker traps on
        /// `dispatch_assert_queue` anywhere else.
        private func presentSharePicker(for url: URL) {
            guard let webView else { return }
            let anchor = NSRect(x: webView.bounds.maxX - 1, y: webView.bounds.maxY,
                                width: 1, height: 1)
            NSSharingServicePicker(items: [url])
                .show(relativeTo: anchor, of: webView, preferredEdge: .maxY)
        }

        private func presentExportPanel() {
            // Kept as a presence check now that renderPDF does the binding:
            // showing a modal save panel that could only ever no-op is worse
            // than not showing one.
            guard webView != nil else { return }

            // Panel first (it now carries the layout choice), render after.
            // Cancel ends here — beforeExport() hasn't run, nothing to restore.
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            let base = (loadedPath as NSString?)?.lastPathComponent ?? "document"
            panel.nameFieldStringValue = (base as NSString).deletingPathExtension + ".pdf"

            let picker = NSPopUpButton(frame: .zero, pullsDown: false)
            picker.addItems(withTitles: ExportLayout.allCases.map(\.displayName))
            picker.selectItem(at: ExportLayout.allCases.firstIndex(of: state.exportLayout) ?? 0)
            let row = NSStackView(views: [NSTextField(labelWithString: "Layout:"), picker])
            row.orientation = .horizontal
            row.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 0)
            // The panel doesn't lay out its accessory — a zero-sized view
            // silently doesn't appear.
            row.setFrameSize(row.fittingSize)
            panel.accessoryView = row

            guard panel.runModal() == .OK, let url = panel.url else { return }
            // Per-export override, not a preference write: the default lives in
            // Settings ▸ Editing & Export. Persisting here meant one Continuous
            // export quietly changed every later export.
            let layout = ExportLayout.allCases[picker.indexOfSelectedItem]

            renderPDF(to: url, layout: layout) { _ in }
        }

        /// Renders the document to `url` and reports whether it landed there.
        /// `completion` is always called on the main queue.
        ///
        /// Both callers come through here. Find highlights and diagram zoom
        /// would otherwise bake into the PDF: beforeExport() resets them, and
        /// endExport() puts them back once the last render is done. They are
        /// document-wide, so a share has to be covered exactly as a save is —
        /// a share rendering on its own would bake the highlights in, and a ⌘E
        /// export running beside it would strip them mid-render. Both halves
        /// no-op when nothing is active, so there is no state to branch on.
        private func renderPDF(to url: URL, layout: ExportLayout,
                               completion: @escaping (Bool) -> Void) {
            guard let webView else { return completion(false) }
            activeExports += 1
            webView.evaluateJavaScript("window.ReaderMd.beforeExport();") { [weak self] _, _ in
                // Gone mid-render: endExport() belongs to the vanished
                // coordinator, so there is nothing to unwind but the caller.
                guard let self else { return completion(false) }
                switch layout {
                case .continuous: exportContinuous(to: url, completion: completion)
                case .pageByPage: exportPaginated(to: url, completion: completion)
                }
            }
        }

        /// Exports that have run beforeExport() and not yet finished rendering.
        /// The find highlights and diagram zoom are document-wide, so they can
        /// only be restored once the last one is done — ⌘E is live again while
        /// an export renders, and restoring after the first would bake the
        /// highlights into a second export still in flight.
        private var activeExports = 0

        private func endExport() {
            activeExports -= 1
            // Restores the exact find match the user was on; find() would scroll
            // them back to match 1 as a side effect of exporting.
            if activeExports == 0 { webView?.evaluateJavaScript("window.ReaderMd.afterExport();") }
        }

        private func exportContinuous(to url: URL, completion: @escaping (Bool) -> Void) {
            guard let webView else { endExport(); return completion(false) }
            webView.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
                self?.endExport()
                guard case let .success(data) = result else { return completion(false) }
                // The write, not the render, is what the caller waits on: the
                // share picker is handed this URL and needs a file at it.
                do {
                    try data.write(to: url)
                    completion(true)
                } catch {
                    completion(false)
                }
            }
        }

        /// Carried through the print operation's `contextInfo` so concurrent
        /// exports don't share one slot: ⌘E is live again the moment
        /// `runModal(for:)` returns, so a second export can start before the
        /// first finishes painting.
        private final class PendingExport {
            let url: URL
            let pageColor: CGColor?
            /// Rides along for the same reason: one completion per in-flight
            /// export, never a shared property two of them could overwrite.
            let completion: (Bool) -> Void
            init(url: URL, pageColor: CGColor?, completion: @escaping (Bool) -> Void) {
                self.url = url
                self.pageColor = pageColor
                self.completion = completion
            }
        }

        private func exportPaginated(to url: URL, completion: @escaping (Bool) -> Void) {
            guard let webView else { endExport(); return completion(false) }
            // The print engine leaves the paper margins unpainted, which reads
            // as a white frame around any non-white theme. Fetch the document
            // background so the finished PDF can be repainted edge to edge.
            webView.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") { [weak self] result, _ in
                guard let self else { return completion(false) }
                runPrintOperation(to: url, pageColor: Self.cssColor(result as? String),
                                  completion: completion)
            }
        }

        private func runPrintOperation(to url: URL, pageColor: CGColor?,
                                       completion: @escaping (Bool) -> Void) {
            // Nothing to print into: beforeExport() has already stripped the find
            // highlights and diagram zoom, so endExport() has to put them back.
            guard let webView, let window = webView.window else {
                endExport()
                return completion(false)
            }
            let info = NSPrintInfo()   // copies the shared defaults: system paper size + margins
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

            let op = webView.printOperation(with: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            // WKWebView's print view starts zero-sized and prints blank pages
            // unless given a frame before the run.
            op.view?.frame = webView.bounds
            // WKWebView print operations only work through runModal(for:...) —
            // a bare run() silently produces nothing. Panels are hidden, so
            // nothing modal is actually shown.
            let pending = PendingExport(url: url, pageColor: pageColor, completion: completion)
            op.runModal(for: window, delegate: self,
                        didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                        contextInfo: Unmanaged.passRetained(pending).toOpaque())
        }

        @objc private func printOperationDidRun(_ printOperation: NSPrintOperation,
                                                success: Bool,
                                                contextInfo: UnsafeMutableRawPointer?) {
            endExport()
            guard let contextInfo else { return }
            let pending = Unmanaged<PendingExport>.fromOpaque(contextInfo).takeRetainedValue()
            if success, let color = pending.pageColor {
                Self.paintPageBackground(url: pending.url, color: color)
            }
            // Last, and never before paintPageBackground: that rewrites the
            // finished PDF in place, and handing the URL to the share picker
            // mid-rewrite would AirDrop a file being overwritten under the
            // transfer.
            //
            // Hopped to the main queue because this is not it — the print
            // operation calls its didRun delegate on the thread it ran
            // (`_continueModalOperationToTheEnd:`), and NSSharingServicePicker
            // traps on `dispatch_assert_queue` if shown from anywhere else. The
            // hop is scheduled after paintPageBackground has already run, so the
            // ordering above still holds.
            DispatchQueue.main.async { pending.completion(success) }
        }

        /// "rgb(13, 17, 23)" / "rgba(…)" → CGColor. Nil for anything else,
        /// including a fully transparent background (nothing worth painting).
        private static func cssColor(_ css: String?) -> CGColor? {
            guard let css else { return nil }
            let nums = css.split(whereSeparator: { !"0123456789.".contains($0) })
                .compactMap { Double($0) }
            guard nums.count >= 3 else { return nil }
            if nums.count >= 4, nums[3] == 0 { return nil }
            return CGColor(srgbRed: nums[0] / 255, green: nums[1] / 255, blue: nums[2] / 255, alpha: 1)
        }

        /// Rewrite the PDF with `color` filled under every page, so the paper
        /// margins match the theme instead of staying printer-white. (The print
        /// engine paints the CSS background only inside the page area; neither
        /// canvas propagation nor `@page { background }` reaches the margins.)
        private static func paintPageBackground(url: URL, color: CGColor) {
            guard let data = try? Data(contentsOf: url),
                  let provider = CGDataProvider(data: data as CFData),
                  let doc = CGPDFDocument(provider), doc.numberOfPages > 0,
                  let firstPage = doc.page(at: 1) else { return }
            // drawPDFPage copies a page's content stream but not its /Annots,
            // so the rewrite alone would kill every link in the document. Lift
            // the annotations off the original before it's overwritten and
            // re-attach them below; moving the objects (rather than rebuilding
            // them) keeps internal heading jumps as well as external URLs.
            let links = PDFDocument(data: data).map { source in
                (0..<source.pageCount).map { source.page(at: $0)?.annotations ?? [] }
            } ?? []

            var mediaBox = firstPage.getBoxRect(.mediaBox)
            guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }
            for i in 1...doc.numberOfPages {
                guard let page = doc.page(at: i) else { continue }
                ctx.beginPDFPage(nil)
                ctx.setFillColor(color)
                ctx.fill(page.getBoxRect(.mediaBox))
                ctx.drawPDFPage(page)
                ctx.endPDFPage()
            }
            ctx.closePDF()

            guard links.contains(where: { !$0.isEmpty }),
                  let painted = PDFDocument(url: url) else { return }
            for (i, annotations) in links.enumerated() where i < painted.pageCount {
                for annotation in annotations { painted.page(at: i)?.addAnnotation(annotation) }
            }
            painted.write(to: url)
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
                if let accent = lastAccent {
                    webView?.evaluateJavaScript("window.ReaderMd.setAccent('\(accent)');")
                }
                if let scale = lastScale { webView?.evaluateJavaScript("window.ReaderMd.setFontScale(\(scale));") }
                if let width = lastWidth { webView?.evaluateJavaScript("window.ReaderMd.setContentWidth('\(width.css)');") }
                if let name = lastReadingTheme {
                    webView?.evaluateJavaScript("window.ReaderMd.setReadingTheme('\(name)');")
                }
                // Cold launch: updateNSView already ran once with isReady false, so
                // pushDiff/pushCurrentFile were both no-ops (see their `guard isReady`).
                // Restore whichever mode is actually current — diff mode must not
                // silently fall back to plain markdown just because it renders first.
                if state.canShowDiff {
                    if let path = state.selectedFile?.url.path, state.gitStatus(for: path) == .conflicted {
                        pushDiff(nil, empty: conflictNoticeMessage)
                    } else {
                        pushDiff(state.diffFile, empty: state.diffScope.emptyMessage)
                    }
                } else if loadedPath != nil {
                    pushCurrentFile(keepScroll: false)
                }

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
                    if self.state.reading.activeHeadingID == nil { self.state.reading.activeHeadingID = entries.first?.id }
                }

            case "activeHeading":
                guard let id = message.body as? String else { return }
                Task { @MainActor in self.state.reading.activeHeadingID = id }

            case "wordCount":
                guard let n = message.body as? Int else { return }
                Task { @MainActor in self.state.wordCount = n }

            case "progress":
                guard let p = message.body as? Double else { return }
                Task { @MainActor in self.state.recordProgress(p) }

            case "diagramFullscreen":
                // The overlay is inside the web view, so it can't cover the native
                // close-doc ✕ drawn above it — ContentView hides the button instead.
                guard let open = message.body as? Bool else { return }
                Task { @MainActor in self.state.diagramFullscreen = open }

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
                // It also drops any fullscreen diagram without an exit event, so the
                // flag has to clear here or the close-doc ✕ never comes back.
                Task { @MainActor in
                    self.state.diagramFullscreen = false
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

            case "findResult":
                guard let payload = message.body as? [String: Any],
                      let count = payload["count"] as? Int,
                      let index = payload["index"] as? Int else { return }
                Task { @MainActor in
                    self.state.findCount = count
                    self.state.findIndex = index
                }

            default:
                break
            }
        }
    }
}
