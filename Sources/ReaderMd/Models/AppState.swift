import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

enum AppearanceMode: String, CaseIterable {
    case light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Icon reflects the mode you'd switch *to*.
    var symbol: String {
        switch self {
        case .light: return "moon"
        case .dark: return "sun.max"
        }
    }

    var toggled: AppearanceMode { self == .dark ? .light : .dark }
}

/// A curated content-pane theme: a palette + font stack + highlight.js
/// stylesheet pair. Orthogonal to `AppearanceMode` (light/dark) — a theme
/// defines *both* of its modes. The set is fixed; not user-editable.
enum ReadingTheme: String, CaseIterable {
    case standard, editorial, terminal

    var displayName: String {
        switch self {
        case .standard:  return "Standard"
        case .editorial: return "Editorial"
        case .terminal:  return "Terminal"
        }
    }

    /// Resolve a persisted rawValue, failing closed to `.standard` when the
    /// name is absent or unrecognized (so removing a theme can't brick startup).
    static func named(_ raw: String?) -> ReadingTheme {
        raw.flatMap(ReadingTheme.init(rawValue:)) ?? .standard
    }
}

/// A heading in the currently open document, used for the outline.
struct TOCEntry: Identifiable, Equatable {
    let id: String   // heading element id
    let text: String
    let level: Int   // 1...4
}

/// A markdown file paired with the root folder it lives under, for quick-open.
struct IndexedFile: Identifiable {
    let node: FileNode
    let rootName: String      // display name of the owning root folder
    let relativePath: String  // path from the root, e.g. "guides/setup.md"
    var id: String { node.id }

    /// Folder portion of the relative path (without the filename), or "" if at the root.
    var relativeFolder: String {
        let parts = relativePath.split(separator: "/")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "/")
    }

    /// Full text a fuzzy query is matched against: "root/folder/file.md".
    var searchText: String { "\(rootName)/\(relativePath)" }

    /// Human-readable location shown under the filename, e.g. "docs › guides".
    var locationLabel: String {
        let folder = relativeFolder
        return folder.isEmpty ? rootName : "\(rootName) › \(folder.replacingOccurrences(of: "/", with: " › "))"
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var roots: [RootFolder] = []
    @Published var selectedFile: FileNode?
    @Published var searchQuery: String = ""
    @Published var theme: AppearanceMode = .light
    @Published var readingTheme: ReadingTheme = .standard
    @Published var showTOC: Bool = false
    @Published var focusSearch: Bool = false   // toggled to request focus

    // Outline state, populated by the web view.
    @Published var toc: [TOCEntry] = []
    @Published var activeHeadingID: String?
    @Published var pendingScroll: String?   // heading id the TOC asked to scroll to
    @Published var reloadToken: Int = 0      // bumped to force a re-read of the open file

    // Reading / typography
    @Published var fontScale: Double = 1.0     // 0.7 ... 1.6
    @Published var wideReading: Bool = false

    // Chrome layout
    @Published var showSidebar: Bool = true
    @Published var sidebarWidth: Double = 260

    // Reading feedback (posted from the web view)
    @Published var scrollProgress: Double = 0  // 0...1
    @Published var wordCount: Int = 0

    // Overlays
    @Published var showQuickOpen: Bool = false

    /// True while a file drag is over the web view. The web view consumes the drag
    /// before SwiftUI's `.onDrop` sees it, so it reports targeting separately from
    /// the chrome's `isTargeted`; ContentView shows the overlay when either is set.
    @Published var webDropTargeted: Bool = false
    @Published var showFind: Bool = false
    @Published var findQuery: String = ""
    @Published var findCount: Int = 0
    @Published var findIndex: Int = 0
    @Published var showAddRemote: Bool = false
    @Published var editingRemote: RemoteSpec? = nil
    @Published var syncAlertError: String? = nil

    // One-shot triggers consumed by the web view
    @Published var findNextToken: Int = 0
    @Published var findPrevToken: Int = 0
    @Published var exportToken: Int = 0

    // Highlights/annotations/comments (#1/#2/#3) for the current document.
    @Published var marks: [Mark] = []
    @Published var orphanedMarkIDs: Set<UUID> = []
    @Published var showResolvedThreads: Bool = true
    private let markStore = MarkStore()
    private var currentMarkDoc: MarkDocument?

    // Navigation history
    @Published private(set) var recentFiles: [String] = []
    private var backStack: [FileNode] = []
    private var forwardStack: [FileNode] = []
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func requestScroll(to id: String) {
        activeHeadingID = id
        pendingScroll = id
    }

    private var watchers: [FolderWatcher] = []

    init() {
        theme = Settings.loadTheme()
        readingTheme = Settings.loadReadingTheme()
        showTOC = Settings.loadShowTOC()
        fontScale = Settings.loadFontScale()
        wideReading = Settings.loadWideReading()
        showSidebar = Settings.loadShowSidebar()
        sidebarWidth = Settings.loadSidebarWidth()
        recentFiles = Settings.loadRecents()
        showResolvedThreads = Settings.loadShowResolvedThreads()
        loadSavedRoots()
        loadSavedRemotes()
    }

    // MARK: - Folder management

    private func loadSavedRoots() {
        let paths = Settings.loadFolderPaths()
        for path in paths where FileManager.default.fileExists(atPath: path) {
            addRoot(URL(fileURLWithPath: path), persist: false)
        }
        persistRoots()
    }

    func pickFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            for url in panel.urls { addRoot(url, persist: false) }
            persistRoots()
        }
    }

    /// Add a folder dropped onto the window.
    func addDroppedFolder(_ url: URL) {
        addRoot(url, persist: true)
    }

    /// Handle a file/folder dropped onto the window or content body:
    /// folders register as roots, markdown files open directly.
    func openDropped(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        if isDir.boolValue {
            addDroppedFolder(url)
        } else if FileScanner.markdownExtensions.contains(url.pathExtension.lowercased()) {
            open(FileNode(url: url, isDirectory: false))
        }
    }

    /// Open a single markdown file (not tied to any root folder).
    func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = FileScanner.markdownExtensions.compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK, let url = panel.url {
            open(FileNode(url: url, isDirectory: false))
        }
    }

    private func addRoot(_ url: URL, persist: Bool) {
        guard !roots.contains(where: { $0.id == url.path }) else { return }
        let root = RootFolder(url: url)
        roots.append(root)
        let watcher = FolderWatcher(path: url.path) { [weak self] in
            Task { @MainActor in self?.handleFolderChange() }
        }
        watchers.append(watcher)
        if persist { persistRoots() }
    }

    /// Reorder roots by drag-and-drop in the sidebar.
    func moveRoot(from: Int, to: Int) {
        guard from != to, roots.indices.contains(from) else { return }
        roots.move(fromOffsets: IndexSet(integer: from), toOffset: to)
        persistRoots()
        persistRemotes()
    }

    func removeRoot(_ root: RootFolder) {
        // Clear the open file if it lived inside the folder being removed.
        if let file = selectedFile, file.url.path.hasPrefix(root.url.path + "/") {
            selectedFile = nil
            toc = []
            loadMarksForCurrentFile()
        }
        roots.removeAll { $0.id == root.id }
        rebuildWatchers()
        persistRoots()
        persistRemotes()
    }

    private func rebuildWatchers() {
        for w in watchers { w.stop() }
        watchers = roots.map { root in
            FolderWatcher(path: root.url.path) { [weak self] in
                Task { @MainActor in self?.handleFolderChange() }
            }
        }
    }

    private func handleFolderChange() {
        for root in roots { root.rescan() }
        objectWillChange.send()
        if let file = selectedFile {
            if FileManager.default.fileExists(atPath: file.url.path) {
                // Open file may have been edited on disk → force a re-read.
                reloadToken += 1
            } else {
                selectedFile = nil
                toc = []
                loadMarksForCurrentFile()
            }
        }
    }

    private func persistRoots() {
        Settings.saveFolderPaths(roots.filter { $0.remote == nil }.map { $0.url.path })
    }

    private func persistRemotes() {
        Settings.saveRemotes(roots.compactMap { $0.remote })
    }

    // MARK: - Remote folders

    private func loadSavedRemotes() {
        for spec in Settings.loadRemotes() {
            registerRemote(spec)
            Task { await syncRemote(spec) }   // background auto-sync; quiet on failure
        }
    }

    func addRemote(_ spec: RemoteSpec) {
        guard !roots.contains(where: { $0.id == spec.id }) else { return }
        registerRemote(spec)
        persistRemotes()
        Task { await syncRemote(spec, surfaceErrors: true) }
    }

    /// Edit an existing remote in place. The spec keeps its original `id`
    /// (so `cacheURL` — and thus marks — are unchanged); only name/host/path
    /// change. Persists and re-syncs (loud, user-initiated).
    func updateRemote(_ spec: RemoteSpec) {
        guard let root = roots.first(where: { $0.id == spec.id }) else { return }
        root.remote = spec
        persistRemotes()
        Task { await syncRemote(spec, surfaceErrors: true) }
    }

    /// Creates the cache dir, appends a remote-tagged root + FSEvents watcher.
    private func registerRemote(_ spec: RemoteSpec) {
        try? FileManager.default.createDirectory(at: spec.cacheURL, withIntermediateDirectories: true)
        roots.append(RootFolder(url: spec.cacheURL, remote: spec))
        let watcher = FolderWatcher(path: spec.cacheURL.path) { [weak self] in
            Task { @MainActor in self?.handleFolderChange() }
        }
        watchers.append(watcher)
    }

    func syncRemote(_ spec: RemoteSpec, surfaceErrors: Bool = false) async {
        guard let root = roots.first(where: { $0.id == spec.id }) else { return }
        guard root.syncStatus != .syncing else { return }
        root.syncStatus = .syncing
        let result = await RemoteSync.run(spec)
        if result.success {
            root.syncStatus = .idle
            root.rescan()
            if let file = selectedFile, file.url.path.hasPrefix(root.url.path + "/") {
                reloadToken += 1
            }
        } else {
            root.syncStatus = .failed(result.message)
            if surfaceErrors { syncAlertError = result.message }
        }
    }

    // MARK: - Theme / TOC persistence

    func toggleTheme() {
        theme = theme.toggled
        Settings.saveTheme(theme)
    }

    func setReadingTheme(_ theme: ReadingTheme) {
        readingTheme = theme
        Settings.saveReadingTheme(theme)
    }

    func setShowTOC(_ value: Bool) {
        showTOC = value
        Settings.saveShowTOC(value)
    }

    // MARK: - Layout

    func toggleSidebar() {
        showSidebar.toggle()
        Settings.saveShowSidebar(showSidebar)
    }

    func setSidebarWidth(_ w: Double) {
        sidebarWidth = min(460, max(180, w))
        Settings.saveSidebarWidth(sidebarWidth)
    }

    // MARK: - Typography

    func adjustFontScale(_ delta: Double) {
        setFontScale(fontScale + delta)
    }

    func setFontScale(_ value: Double) {
        fontScale = min(1.6, max(0.7, (value * 100).rounded() / 100))
        Settings.saveFontScale(fontScale)
    }

    func resetFontScale() { setFontScale(1.0) }

    func toggleWideReading() {
        wideReading.toggle()
        Settings.saveWideReading(wideReading)
    }

    // MARK: - Navigation & history

    /// Central entry point for opening a file — manages history + recents.
    func open(_ node: FileNode) {
        if let current = selectedFile {
            if current.id == node.id { return }
            backStack.append(current)
            forwardStack.removeAll()
        }
        setCurrent(node)
        pushRecent(node.url.path)
    }

    func openPath(_ path: String) {
        open(FileNode(url: URL(fileURLWithPath: path), isDirectory: false))
    }

    /// Open a bundled help document (FAQ / SHORTCUTS / CHANGELOG) in the reader.
    func openBundledDoc(_ name: String) {
        guard let url = Bundle.resources.url(forResource: name, withExtension: "md", subdirectory: "docs") else { return }
        open(FileNode(url: url, isDirectory: false))
    }

    /// Show the changelog once after the app updates to a new build. Skips the
    /// first launch (fresh install) so new users aren't nagged, and no-ops under
    /// `swift run` where there's no CFBundleVersion.
    func checkWhatsNew() {
        guard let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else { return }
        let seen = UserDefaults.standard.string(forKey: "lastSeenBuild")
        UserDefaults.standard.set(build, forKey: "lastSeenBuild")
        if let seen, seen != build { openBundledDoc("CHANGELOG") }
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let current = selectedFile { forwardStack.append(current) }
        setCurrent(previous)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current = selectedFile { backStack.append(current) }
        setCurrent(next)
    }

    private func setCurrent(_ node: FileNode) {
        selectedFile = node
        toc = []
        activeHeadingID = nil
        scrollProgress = 0
        loadMarksForCurrentFile()
    }

    private func pushRecent(_ path: String) {
        recentFiles.removeAll { $0 == path }
        recentFiles.insert(path, at: 0)
        if recentFiles.count > 12 { recentFiles = Array(recentFiles.prefix(12)) }
        Settings.saveRecents(recentFiles)
    }

    func removeRecent(_ path: String) {
        recentFiles.removeAll { $0 == path }
        Settings.saveRecents(recentFiles)
    }

    func clearRecents() {
        recentFiles = []
        Settings.saveRecents([])
    }

    /// Flat list of every markdown file across all roots, for quick-open.
    func allFiles() -> [FileNode] {
        var result: [FileNode] = []
        func walk(_ nodes: [FileNode]) {
            for n in nodes {
                if n.isDirectory { walk(n.children) } else { result.append(n) }
            }
        }
        for root in roots { walk(root.children) }
        return result
    }

    /// Every markdown file across all roots, each tagged with its owning root
    /// and its path relative to that root — powers path-aware quick-open.
    func allFilesIndexed() -> [IndexedFile] {
        var result: [IndexedFile] = []
        for root in roots {
            let rootPath = root.url.path
            func walk(_ nodes: [FileNode]) {
                for n in nodes {
                    if n.isDirectory {
                        walk(n.children)
                    } else {
                        var rel = n.url.path
                        if rel.hasPrefix(rootPath + "/") {
                            rel = String(rel.dropFirst(rootPath.count + 1))
                        }
                        result.append(IndexedFile(node: n, rootName: root.name, relativePath: rel))
                    }
                }
            }
            walk(root.children)
        }
        return result
    }

    /// Rank of a file path in the recents list (0 = most recent), or nil if unseen.
    func recentRank(_ path: String) -> Int? {
        recentFiles.firstIndex(of: path)
    }

    // MARK: - In-document triggers

    func triggerFindNext() { findNextToken += 1 }
    func triggerFindPrev() { findPrevToken += 1 }
    func triggerExport() { exportToken += 1 }
    func triggerReload() { reloadToken += 1 }

    // MARK: - Search helpers

    var normalizedQuery: String { searchQuery.trimmingCharacters(in: .whitespaces).lowercased() }

    var readingMinutes: Int { max(1, Int((Double(wordCount) / 220.0).rounded())) }

    // MARK: - Marks (highlighting / annotations / comments)

    private func loadMarksForCurrentFile() {
        guard let path = selectedFile?.url.path else {
            currentMarkDoc = nil
            marks = []
            orphanedMarkIDs = []
            return
        }
        if let doc = markStore.load(path: path) {
            currentMarkDoc = doc
            marks = doc.marks
        } else {
            let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            currentMarkDoc = MarkDocument(schemaVersion: 1, filePath: path,
                                           contentHash: MarkStore.sha256(content), marks: [])
            marks = []
        }
        orphanedMarkIDs = []
    }

    /// `note` is an optional convenience for creating an annotation (#2) in one
    /// step — a Mark with a note is exactly a Mark with one `comments` entry,
    /// there's no separate storage system for annotations.
    @discardableResult
    func createMark(anchor: TextAnchor, color: HighlightColor, note: String? = nil) -> Mark {
        var mark = Mark(anchor: anchor, color: color)
        if let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            mark.comments = [Comment(author: NSFullUserName(), text: trimmed, createdAt: Date())]
        }
        marks.append(mark)
        persistMarks()
        return mark
    }

    func setMarkColor(_ id: UUID, color: HighlightColor) {
        guard let idx = marks.firstIndex(where: { $0.id == id }) else { return }
        marks[idx].color = color
        marks[idx].updatedAt = Date()
        persistMarks()
    }

    func deleteMark(_ id: UUID) {
        marks.removeAll { $0.id == id }
        orphanedMarkIDs.remove(id)
        persistMarks()
    }

    /// Appends a message to the mark's thread — an append-only log, not
    /// editable in place. The first message makes it an annotation (#2); a
    /// second (or more) makes it a comment thread (#3). Empty text is a no-op.
    func addComment(_ id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = marks.firstIndex(where: { $0.id == id }) else { return }
        marks[idx].comments.append(Comment(author: NSFullUserName(), text: trimmed, createdAt: Date()))
        marks[idx].updatedAt = Date()
        persistMarks()
    }

    /// Clears every message, reverting the mark back to a plain highlight —
    /// the highlight itself is untouched.
    func deleteThread(_ id: UUID) {
        guard let idx = marks.firstIndex(where: { $0.id == id }) else { return }
        marks[idx].comments = []
        marks[idx].resolved = false
        marks[idx].updatedAt = Date()
        persistMarks()
    }

    /// Resolve collapses/de-emphasizes a thread's anchor without discarding
    /// it; reopen restores it. Meaningless (but harmless) on a bare highlight.
    func setResolved(_ id: UUID, resolved: Bool) {
        guard let idx = marks.firstIndex(where: { $0.id == id }) else { return }
        marks[idx].resolved = resolved
        marks[idx].updatedAt = Date()
        persistMarks()
    }

    func toggleShowResolvedThreads() {
        showResolvedThreads.toggle()
        Settings.saveShowResolvedThreads(showResolvedThreads)
    }

    func setOrphanedMarkIDs(_ ids: [String]) {
        orphanedMarkIDs = Set(ids.compactMap { UUID(uuidString: $0) })
    }

    private func persistMarks() {
        guard var doc = currentMarkDoc else { return }
        doc.marks = marks
        currentMarkDoc = doc
        markStore.save(doc)
    }

    /// Marks for the current document, serialized for `window.ReaderMd.applyMarks`.
    /// Resolved marks are still sent (and anchor-resolved, so orphan detection
    /// stays accurate) even when `showResolvedThreads` is off — `hidden` just
    /// tells the JS side to skip wrapping/rendering them.
    func marksJSON() -> String {
        struct Wire: Codable {
            let id: String
            let anchor: TextAnchor
            let color: String
            let note: String?
            let resolved: Bool
            let hidden: Bool
        }
        let wire = marks.map { m -> Wire in
            let preview: String?
            switch m.comments.count {
            case 0: preview = nil
            case 1: preview = m.comments[0].text
            default: preview = "\(m.comments.count) comments — \(m.comments.last?.text ?? "")"
            }
            return Wire(id: m.id.uuidString, anchor: m.anchor, color: m.color.rawValue,
                        note: preview, resolved: m.resolved, hidden: m.resolved && !showResolvedThreads)
        }
        guard let data = try? JSONEncoder().encode(wire), let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}
