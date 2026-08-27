import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

enum AppearanceMode: String, CaseIterable {
    case light, dark, system

    /// `nil` inherits the system appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    /// Icon reflects the *current* mode (three states don't fit "next mode").
    var symbol: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "circle.lefthalf.filled"
        }
    }

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    /// Names the current mode — the icon already implies it, so no verb.
    var tooltip: String { self == .system ? "System" : "\(displayName) Mode" }

    /// VoiceOver has no icon to read the current mode from, and a button's label
    /// has to say what pressing it does — so state *and* action, unlike `tooltip`.
    var accessibilityLabel: String {
        "Appearance: \(displayName). Switch to \(toggled.displayName)."
    }

    /// Light → Dark → System → Light.
    var toggled: AppearanceMode {
        switch self {
        case .light: return .dark
        case .dark: return .system
        case .system: return .light
        }
    }
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

/// Width of the reading column. `full` fills the pane — wide tables and code
/// blocks stop scrolling horizontally on a large display.
enum ContentWidth: String, CaseIterable {
    case narrow, wide, full

    var displayName: String {
        switch self {
        case .narrow: return "Narrow"
        case .wide:   return "Wide"
        case .full:   return "Full Width"
        }
    }

    /// CSS value for `--content-width`.
    var css: String {
        switch self {
        case .narrow: return "760px"
        case .wide:   return "1080px"
        case .full:   return "100%"
        }
    }
}

/// How ⌘E lays out the PDF: real pages via the print engine, or one
/// continuous page the height of the whole document.
enum ExportLayout: String, CaseIterable {
    case pageByPage, continuous

    var displayName: String {
        switch self {
        case .pageByPage: return "Page by Page"
        case .continuous: return "Continuous"
        }
    }

    /// Absent or unrecognized persisted values fall back to the default.
    static func named(_ raw: String?) -> ExportLayout {
        raw.flatMap(ExportLayout.init(rawValue:)) ?? .pageByPage
    }
}

/// A heading in the currently open document, used for the outline. In diff mode
/// the same type carries one entry per hunk instead, with `detail` holding the
/// hunk's counts.
struct TOCEntry: Identifiable, Equatable {
    let id: String   // heading element id, or "hunk-N" in diff mode
    let text: String
    let level: Int   // 1...4
    var detail: String?   // "+3 −1" in diff mode, nil otherwise
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
    @Published var searchQuery: String = "" {
        didSet { refreshSearchResults() }
    }

    /// Sidebar filter hits, flat. Recomputed once per keystroke instead of by the
    /// tree: filtering in place meant every directory row re-ran a recursive
    /// `matches()` over its subtree, and a non-empty query force-expanded every
    /// root — materializing ~3k rows into non-lazy VStacks on each edit.
    @Published private(set) var searchResults: [IndexedFile] = []

    /// Total markdown files across all roots, for the window subtitle. Stored, not
    /// computed: `children` fills in from a background scan and publishes on the
    /// RootFolder, which the toolbar doesn't observe — a computed walk would show
    /// the launch-time zero until some unrelated AppState publish redrew it.
    @Published private(set) var fileCount: Int = 0
    @Published var theme: AppearanceMode = .light
    /// Live system appearance, tracked so `.system` can resolve to a concrete
    /// scheme (see `colorScheme`). KVO'd in `init`.
    @Published private var systemIsDark: Bool = AppState.systemIsDark
    @Published var readingTheme: ReadingTheme = .standard
    @Published var showTOC: Bool = false
    @Published var focusSearch: Bool = false   // toggled to request focus

    // Outline state, populated by the web view.
    // didSet defaults every assignment to "document outline"; refreshDiff() flips
    // it back to true right after assigning the hunk outline. This lets the flag
    // stay correct even though the 'toc' web-view message assigns `state.toc`
    // directly (see MarkdownWebView.swift) rather than through a setter method.
    @Published var toc: [TOCEntry] = [] {
        didSet { tocIsDiffOutline = false }
    }
    /// True when `toc` currently holds hunk rows (diff mode) rather than document
    /// headings. TOCView compares this against `canShowDiff` to suppress rows left
    /// over from the mode just exited, until the fresh outline for the new mode arrives.
    @Published private(set) var tocIsDiffOutline: Bool = false
    @Published var pendingScroll: String?   // heading id the TOC asked to scroll to
    @Published var reloadToken: Int = 0      // bumped to force a re-read of the open file

    // Reading / typography
    @Published var fontScale: Double = 1.0     // 0.7 ... 1.6
    @Published var contentWidth: ContentWidth = .wide

    /// Default layout for ⌘E. The save panel's popup seeds from this and is a
    /// per-export override — it deliberately does not write back, or a one-off
    /// Continuous export would silently become the default.
    @Published private(set) var exportLayout: ExportLayout = .pageByPage

    // Chrome layout
    @Published var showSidebar: Bool = true
    @Published var sidebarWidth: Double = 260

    // MARK: - Focus mode

    @Published var focusMode: Bool = false

    @Published var focusFullscreen: Bool = Settings.loadFocusFullscreen()
    @Published var focusDimSections: Bool = Settings.loadFocusDimSections()
    @Published var focusNarrowCanvas: Bool = Settings.loadFocusNarrowCanvas()
    @Published var focusHideToolbar: Bool = Settings.loadFocusHideToolbar()

    /// What the web view is told. Dimming needs both the mode and its switch.
    var focusDimActive: Bool { focusMode && focusDimSections }

    /// Every switch off makes ⌥⌘F a no-op. Settings shows a note when this is true.
    var focusModeDoesNothing: Bool {
        !focusFullscreen && !focusDimSections && !focusNarrowCanvas && !focusHideToolbar
    }

    /// The layout as it was before focus mode took it over.
    ///
    /// Deliberately not `@Published` — nothing renders from it. Deliberately not
    /// written through `toggleSidebar()` / `setShowTOC()` / `setContentWidth()`
    /// either: those persist to UserDefaults, and focus mode's values must never
    /// become the user's saved preferences.
    struct FocusStash {
        var showSidebar: Bool
        var showTOC: Bool
        var contentWidth: ContentWidth
        var wasAlreadyFullscreen: Bool
    }
    private(set) var focusStash: FocusStash?

    /// Observes `didExitFullScreenNotification` for as long as focus mode is
    /// running in fullscreen. The green traffic-light button and the native
    /// ⌃⌘F are ordinary, always-available ways to leave fullscreen that focus
    /// mode doesn't disable — without this, the window would drop back to
    /// windowed mode (toolbar included, since auto-hide only applies in
    /// fullscreen) while `focusMode` stayed true, stranding the sidebar,
    /// outline, narrow canvas and dimming suppressed with nothing left to
    /// resync them. Firing this exits focus mode the same way ⌥⌘F would, so
    /// leaving fullscreen by any route lands in one coherent state.
    private var fullScreenExitObserver: NSObjectProtocol?

    private func clearFullScreenExitObserver() {
        if let fullScreenExitObserver { NotificationCenter.default.removeObserver(fullScreenExitObserver) }
        fullScreenExitObserver = nil
    }

    /// Sticky until focus mode is left: ⌘F sets this to bring the toolbar back
    /// without costing the mode, and re-hiding it the moment the search field
    /// clears would yank the field out from under someone stepping through
    /// matches with ⌘G. `@Published` because `AppState.focusToolbarHidden`
    /// reads it and the `.toolbar(_:for:)` modifier needs to react.
    @Published private var focusToolbarRevealed = false

    /// Whether the SwiftUI toolbar modifier should hide the window's toolbar
    /// right now. See `focusToolbarHidden(focusMode:hideToolbar:toolbarRevealed:)`.
    var focusToolbarHidden: Bool {
        ReaderMd.focusToolbarHidden(focusMode: focusMode, hideToolbar: focusHideToolbar,
                                     toolbarRevealed: focusToolbarRevealed)
    }

    /// The WindowGroup's window, tagged by `WindowAccessor` on ContentView.
    /// Deliberately not @Published — nothing renders from it, and republishing
    /// on every window change would churn the view tree. Weak so closing the
    /// window doesn't keep it alive.
    ///
    /// AppDelegate's ⌘W path uses it to tell the document window apart from the
    /// Settings window. Read it together with `documentWindowWasTagged` below —
    /// a nil on its own is ambiguous, and `shouldCloseDocument` needs both.
    ///
    /// One slot, deliberately: the app is single-window by construction — the
    /// WindowGroup routes every `readermd://` URL to the existing window
    /// (`handlesExternalEvents`) and `CommandGroup(replacing: .newItem)` drops
    /// New Window. If a second document window ever becomes reachable, this
    /// becomes last-writer-wins and ⌘W in the other window closes it instead of
    /// the document.
    private(set) weak var documentWindow: NSWindow?

    /// Whether `documentWindow` has ever been set. A weak reference can't tell
    /// "not tagged yet" (the tick before ContentView's first update) from
    /// "tagged, then closed" once it reads nil, and ⌘W has to treat those
    /// opposite ways.
    private(set) var documentWindowWasTagged = false

    func setDocumentWindow(_ window: NSWindow) {
        documentWindow = window
        documentWindowWasTagged = true
    }

    // Reading feedback (posted from the web view). Scroll-rate values live on
    // `reading`, NOT here — see ReadingState. A plain `let`, so mutating it
    // never fires AppState's objectWillChange.
    let reading = ReadingState()
    @Published var wordCount: Int = 0

    // Overlays
    @Published var showQuickOpen: Bool = false

    /// True while a Mermaid diagram is open fullscreen in the web view. The overlay
    /// is CSS inside the web view, so it can't cover native chrome drawn on top of
    /// it — the close-doc ✕ hides itself for the duration.
    @Published var diagramFullscreen: Bool = false

    /// True while a file drag is over the web view. The web view consumes the drag
    /// before SwiftUI's `.onDrop` sees it, so it reports targeting separately from
    /// the chrome's `isTargeted`; ContentView shows the overlay when either is set.
    @Published var webDropTargeted: Bool = false
    @Published var focusFind: Bool = false   // toggled to focus the topbar search field
    @Published var findQuery: String = ""
    @Published var findCount: Int = 0
    @Published var findIndex: Int = 0
    @Published var showAddRemote: Bool = false
    @Published var editingRemote: RemoteSpec? = nil
    @Published var pendingRemote: RemoteSpec? = nil   // seeds the Add Remote sheet when it came from a URL
    @Published var syncAlertError: String? = nil

    // One-shot triggers consumed by the web view
    @Published var findNextToken: Int = 0
    @Published var findPrevToken: Int = 0
    @Published var exportToken: Int = 0

    // Diff mode — a sticky VIEW MODE, not a one-shot, so it is persisted state
    // rather than a bump token. `diffToken` is the one-shot: it's bumped after
    // each recompute so the web view knows to push the new model.
    @Published var diffMode: Bool = false
    @Published var diffScope: DiffScope = .all
    @Published var diffFile: DiffFile?
    @Published var diffAvailable: Bool = false          // open file is inside a repo
    /// Refs the open file's repo offers as diff scopes. Only filled while diff
    /// mode is on — the menu that reads it can't be reached otherwise.
    @Published var diffBranches: [String] = []
    @Published var gitStatuses: [String: GitFileStatus] = [:]
    @Published var diffToken: Int = 0

    /// Probed once, off the main actor, because /usr/bin/git is an xcode-select
    /// shim: on a Mac with no Command Line Tools that call can raise Apple's
    /// install dialog, and it must not run on the launch path.
    @Published private(set) var gitAvailable = false

    /// Repo root per root folder. Roots may be different repos, or not repos.
    private var repoRootCache: [String: URL] = [:]

    /// Branch list per repo root. `refreshDiff` runs on every file open and every
    /// window activation, and `diffMode` persists across launches, so without this
    /// merely clicking back into the window costs two git subprocesses. Branches
    /// change rarely; toggling diff mode off and on clears it.
    private var branchCache: [String: [String]] = [:]

    /// Generation counters guarding against out-of-order async completions:
    /// bumped at dispatch, captured by the in-flight task, checked back before
    /// the result is applied — a stale completion (an older refresh landing
    /// after a newer one) is dropped rather than overwriting fresher state.
    private var diffRequest = 0
    private var statusRequest = 0

    // Highlights/annotations/comments (#1/#2/#3) for the current document.
    @Published var marks: [Mark] = []
    @Published var orphanedMarkIDs: Set<UUID> = []
    @Published var showResolvedThreads: Bool = true
    private let markStore = MarkStore()
    private var currentMarkDoc: MarkDocument?

    /// The editor ⇧⌘E hands files to. Stored as a bundle id; the name is kept
    /// alongside it so menu labels don't have to resolve it.
    @Published private(set) var editorBundleID: String?
    @Published private(set) var editorDisplayName: String?

    // Navigation history
    @Published private(set) var recentFiles: [String] = []

    /// Pinned files, newest last — Recents churns as you read, Favorites don't.
    @Published private(set) var favoriteFiles: [String] = []

    /// Saved scroll fraction per file path. Not @Published — nothing in the UI
    /// renders it; it's read once at load time to resume the document.
    private var positions: [String: Double] = [:]
    private var backStack: [FileNode] = []
    private var forwardStack: [FileNode] = []
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func requestScroll(to id: String) {
        reading.activeHeadingID = id
        pendingScroll = id
    }

    private var watchers: [FolderWatcher] = []

    // MARK: - Appearance

    static var systemIsDark: Bool {
        NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// The scheme to hand `.preferredColorScheme` — never `nil`. Passing `nil`
    /// for `.system` clears the window's appearance (so the native toolbar
    /// repaints) but doesn't invalidate SwiftUI content, leaving the sidebar,
    /// outline and web view on the old scheme until an unrelated redraw. So we
    /// resolve `.system` ourselves and follow the system with KVO.
    var colorScheme: ColorScheme {
        theme.colorScheme ?? (systemIsDark ? .dark : .light)
    }

    private var appearanceObserver: NSKeyValueObservation?

    init() {
        appearanceObserver = NSApp?.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.systemIsDark = AppState.systemIsDark }
        }
        theme = Settings.loadTheme()
        readingTheme = Settings.loadReadingTheme()
        showTOC = Settings.loadShowTOC()
        fontScale = Settings.loadFontScale()
        contentWidth = Settings.loadContentWidth()
        exportLayout = Settings.loadExportLayout()
        showSidebar = Settings.loadShowSidebar()
        sidebarWidth = Settings.loadSidebarWidth()
        // Drop help-doc paths and directories. Folder paths land in both lists when
        // a file-URL open (`open -a`) used to treat them as documents — clicking one
        // then opened a blank pane. See `openPath` / `onOpenURL`. Neither list is
        // pruned to files that still exist, unlike positions: an entry on an
        // unmounted volume should come back with the volume, not vanish silently.
        recentFiles = Settings.loadRecents().filter { Self.shouldKeepListed($0) }
        favoriteFiles = Settings.loadFavorites().filter { Self.shouldKeepListed($0) }
        showResolvedThreads = Settings.loadShowResolvedThreads()
        editorBundleID = Settings.loadEditorBundleID()
        editorDisplayName = editorBundleID
            .flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .map { FileManager.default.displayName(atPath: $0.path) }
        // Drop positions for files that are gone, so the dictionary can't grow forever.
        positions = Settings.loadPositions().filter { FileManager.default.fileExists(atPath: $0.key) }
        loadSavedRoots()
        loadSavedRemotes()
        diffMode = Settings.loadDiffMode()
        diffScope = Settings.loadDiffScope()
        // Probe git off the launch path, then do the first refresh once the
        // answer is in — every git call in this class is gated on it.
        // The first git status refresh (below) only runs after gitAvailable is set,
        // so it can't run during loadSavedRoots() in the init body above.
        Task.detached(priority: .utility) {
            guard GitDiff.isAvailable() else { return }
            GitDiff.available = true
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.gitAvailable = true
                self.refreshDiff()
                self.refreshGitStatus()
                // The roots above scanned before this answer landed, so they were
                // built without git's ignores. Rescan once, now that they apply —
                // `onlyIfIgnored` so a root with nothing to prune (most of them)
                // doesn't pay a second full walk at launch.
                for root in self.roots {
                    root.rescan(onlyIfIgnored: true) { [weak self] in self?.didRescan() }
                }
            }
        }
    }

    // MARK: - Diff mode

    /// True when the diff pane should be showing instead of rendered markdown.
    /// A file with no repo renders normally even while `diffMode` is on, so
    /// opening a remote folder mid-session isn't a dead end.
    var canShowDiff: Bool { diffMode && diffAvailable }

    func toggleDiffMode() {
        diffMode.toggle()
        Settings.saveDiffMode(diffMode)
        // Turning diff mode on is the branch list's refresh affordance — see
        // `branchCache`. Cheap: the very next refreshDiff repopulates it.
        if diffMode { branchCache.removeAll() }
        refreshDiff()
    }

    func setDiffScope(_ scope: DiffScope) {
        guard scope != diffScope else { return }
        diffScope = scope
        Settings.saveDiffScope(scope)
        refreshDiff()
    }

    func gitStatus(for path: String) -> GitFileStatus? { gitStatuses[path] }

    /// What the scope menu lists: the three fixed scopes, then one per branch.
    /// A selected ref that the repo no longer offers (the open file moved to
    /// another repo) is kept in the list — a Picker whose selection has no
    /// matching tag renders blank.
    var diffScopeChoices: [DiffScope] {
        Self.scopeChoices(branches: diffBranches, selected: diffScope)
    }

    nonisolated static func scopeChoices(branches: [String], selected: DiffScope) -> [DiffScope] {
        var choices = DiffScope.fixed + branches.map { DiffScope.ref($0) }
        if !choices.contains(selected) { choices.append(selected) }
        return choices
    }

    /// The outline in diff mode: one row per hunk, labelled by its enclosing
    /// heading. `id` must be the hunk's element id — TOCView taps route through
    /// `requestScroll(to:)`, and bridge.js resolves that with getElementById.
    ///
    /// nonisolated static so it can be unit-tested without the main actor.
    nonisolated static func diffOutline(for file: DiffFile) -> [TOCEntry] {
        file.hunks.map { hunk in
            TOCEntry(id: hunk.id,
                     text: hunk.heading.isEmpty ? "Top of file" : hunk.heading,
                     level: hunk.headingLevel,
                     detail: "+\(hunk.additions) −\(hunk.deletions)")
        }
    }

    /// Recomputes the open file's diff and its repo membership. Safe to call
    /// when diff mode is off — it still refreshes `diffAvailable` so the
    /// toolbar button knows whether to appear.
    func refreshDiff() {
        guard gitAvailable, let file = selectedFile else {
            diffAvailable = false
            diffFile = nil
            diffToken += 1
            return
        }
        let url = file.url
        let scope = diffScope
        let wantDiff = diffMode
        let cached = repoRootCache[url.deletingLastPathComponent().path]
        let cachedBranches = cached.flatMap { branchCache[$0.path] }
        diffRequest += 1
        let generation = diffRequest

        Task.detached(priority: .userInitiated) {
            let root = cached ?? GitDiff.repoRoot(for: url)
            let computed: DiffFile?
            let branches: [String]
            if wantDiff, let root {
                computed = GitDiff.diff(file: url, scope: scope, repoRoot: root)
                // Inside the `wantDiff` branch on purpose: refreshDiff also runs
                // on every file open and every window activation, and the menu
                // these fill only exists in diff mode. Cached beyond that, since
                // even in diff mode those two triggers are far more frequent than
                // a branch ever appearing.
                branches = cachedBranches ?? GitDiff.branches(root: root)
            } else {
                computed = nil
                branches = []
            }
            await MainActor.run { [weak self] in
                // Both checks matter: the URL check catches navigation to a
                // different file, the generation check catches two in-flight
                // refreshes for the SAME file completing out of order.
                guard let self, self.diffRequest == generation, self.selectedFile?.url == url else { return }
                if let root { self.repoRootCache[url.deletingLastPathComponent().path] = root }
                if wantDiff, let root { self.branchCache[root.path] = branches }
                self.diffAvailable = root != nil
                self.diffBranches = branches
                self.diffFile = computed
                self.diffToken += 1
                if wantDiff {
                    // A conflicted file renders the "unresolved merge conflicts" notice
                    // (see MarkdownWebView) instead of hunk rows — and `git diff` on an
                    // unmerged path emits combined-diff format GitDiff.parse() doesn't
                    // understand, so any hunks here would likely be garbled anyway. Keep
                    // the outline empty rather than listing rows absent from the rendered DOM.
                    if let computed, self.gitStatus(for: url.path) != .conflicted {
                        self.toc = Self.diffOutline(for: computed)
                        self.tocIsDiffOutline = true
                    } else {
                        self.toc = []
                    }
                    self.wordCount = 0        // meaningless for a diff
                }
            }
        }
    }

    /// Refreshes the badge map for every root that is a git repo.
    func refreshGitStatus() {
        guard gitAvailable else { return }
        let urls = roots.map(\.url)
        statusRequest += 1
        let generation = statusRequest
        Task.detached(priority: .utility) {
            let merged: [String: GitFileStatus] = urls.reduce(into: [:]) { acc, url in
                guard let root = GitDiff.repoRoot(for: url) else { return }
                // `url` is the folder the user added; `root` is git's resolved
                // top-level. Keys must come back in the former's namespace or
                // they match no FileNode path.
                acc.merge(GitDiff.status(root: root, displayedAs: url)) { current, _ in current }
            }
            await MainActor.run { [weak self] in
                guard let self, self.statusRequest == generation else { return }
                self.gitStatuses = merged
            }
        }
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
        // Reveal the sidebar first: `addRoot` no-ops on a folder that's already a
        // root, so with the sidebar collapsed the whole gesture would look inert.
        // Persisted like the toggle, or the state would silently revert next launch.
        showSidebar = true
        Settings.saveShowSidebar(true)
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
        let root = RootFolder(url: url) { [weak self] in self?.didRescan() }
        roots.append(root)
        let watcher = FolderWatcher(path: url.path) { [weak self] in
            Task { @MainActor in self?.handleFolderChange() }
        }
        watchers.append(watcher)
        if persist { persistRoots() }
        refreshGitStatus()
    }

    /// Reorder roots by drag-and-drop in the sidebar.
    func moveRoot(from: Int, to: Int) {
        guard from != to, roots.indices.contains(from) else { return }
        roots.move(fromOffsets: IndexSet(integer: from), toOffset: to)
        didRescan()   // search results are ordered by root
        persistRoots()
        persistRemotes()
    }

    func removeRoot(_ root: RootFolder) {
        // Clear the open file if it lived inside the folder being removed.
        if let file = selectedFile, file.url.path.hasPrefix(root.url.path + "/") {
            selectedFile = nil
            toc = []
            loadMarksForCurrentFile()
            refreshDiff()
        }
        roots.removeAll { $0.id == root.id }
        didRescan()
        rebuildWatchers()
        persistRoots()
        persistRemotes()
    }

    /// Remove by whatever the user typed at the CLI: an absolute path, or a root's
    /// name. Remote roots can only be addressed by name — their `url` is an opaque
    /// cache directory keyed by UUID.
    func removeRoot(matching token: String) {
        let path = Self.normalizedRemoveToken(token)
        guard let root = roots.first(where: { $0.url.path == path })
                ?? roots.first(where: { $0.name == token })
        else { return }
        removeRoot(root)
    }

    /// Normalizes a `rm` token the same way `Route.absolute` normalized it when the
    /// root was added — tilde expansion, then `standardizingPath` (which also drops
    /// a trailing slash) — so `reader rm ~/docs/` matches a root added as `reader ~/docs/`.
    /// A relative token can't be resolved here (the app's cwd isn't the user's); it
    /// passes through unchanged and falls through to the name match.
    nonisolated static func normalizedRemoveToken(_ token: String) -> String {
        let expanded = (token as NSString).expandingTildeInPath
        return (expanded as NSString).standardizingPath
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
        // No objectWillChange.send() here: each RootFolder publishes its own
        // children, and only its own RootSectionView observes them. Sending on
        // AppState re-rendered the entire window instead.
        for root in roots { root.rescan { [weak self] in self?.didRescan() } }
        if let file = selectedFile {
            if FileManager.default.fileExists(atPath: file.url.path) {
                // Open file may have been edited on disk → force a re-read.
                reloadToken += 1
                refreshDiff()
            } else {
                selectedFile = nil
                toc = []
                loadMarksForCurrentFile()
                refreshDiff()
            }
        }
        refreshGitStatus()
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
        roots.append(RootFolder(url: spec.cacheURL, remote: spec) { [weak self] in
            self?.didRescan()
        })
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
            root.rescan { [weak self] in self?.didRescan() }
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
        setTheme(theme.toggled)
    }

    /// Settings picks a mode outright; the toolbar button cycles. Both persist.
    func setTheme(_ value: AppearanceMode) {
        theme = value
        Settings.saveTheme(value)
    }

    func setReadingTheme(_ theme: ReadingTheme) {
        readingTheme = theme
        Settings.saveReadingTheme(theme)
    }

    func setShowTOC(_ value: Bool) {
        showTOC = value
        Settings.saveShowTOC(value)
        focusStash?.showTOC = value
    }

    // MARK: - Layout

    func toggleSidebar() {
        showSidebar.toggle()
        Settings.saveShowSidebar(showSidebar)
        focusStash?.showSidebar = showSidebar
    }

    func toggleFocusMode() {
        focusMode ? exitFocusMode() : enterFocusMode()
    }

    private func enterFocusMode() {
        let alreadyFullscreen = documentWindow?.styleMask.contains(.fullScreen) ?? false
        focusStash = FocusStash(showSidebar: showSidebar,
                                showTOC: showTOC,
                                contentWidth: contentWidth,
                                wasAlreadyFullscreen: alreadyFullscreen)
        focusMode = true
        focusToolbarRevealed = false

        // Direct writes, not the setters — see FocusStash.
        showSidebar = false
        showTOC = false
        if focusNarrowCanvas { contentWidth = .narrow }
        applyFocusWindowChrome()
    }

    private func exitFocusMode() {
        focusMode = false
        focusToolbarRevealed = false
        guard let stash = focusStash else { return }
        focusStash = nil
        restoreWindowChrome(wasAlreadyFullscreen: stash.wasAlreadyFullscreen)
        showSidebar = stash.showSidebar
        showTOC = stash.showTOC
        contentWidth = stash.contentWidth
    }

    private func applyFocusWindowChrome() {
        guard let window = documentWindow, focusFullscreen else { return }
        observeFullScreenExit()
        if !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    /// See `fullScreenExitObserver` for why this exists: leaving fullscreen by an
    /// ordinary gesture focus mode doesn't own must still exit focus mode.
    private func observeFullScreenExit() {
        guard let window = documentWindow else { return }
        clearFullScreenExitObserver()
        fullScreenExitObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.clearFullScreenExitObserver()
                guard self.focusMode else { return }
                self.exitFocusMode()
            }
        }
    }

    private func restoreWindowChrome(wasAlreadyFullscreen: Bool) {
        clearFullScreenExitObserver()
        guard let window = documentWindow else { return }
        window.toolbar?.isVisible = true
        // Entering focus mode from a window that was already in fullscreen leaves
        // it there — focus mode did not put it in fullscreen, so it does not take
        // it out.
        if window.styleMask.contains(.fullScreen) && !wasAlreadyFullscreen {
            window.toggleFullScreen(nil)
        }
    }

    /// ⌘F in focus mode: bring the toolbar back rather than leaving the mode, so a
    /// search does not cost it. Un-suspended on exit via `restoreWindowChrome()`.
    func revealToolbarForFind() {
        guard focusMode else { return }
        focusToolbarRevealed = true
    }

    func setFocusFullscreen(_ value: Bool) {
        focusFullscreen = value
        Settings.saveFocusFullscreen(value)
    }

    func setFocusDimSections(_ value: Bool) {
        focusDimSections = value
        Settings.saveFocusDimSections(value)
    }

    func setFocusNarrowCanvas(_ value: Bool) {
        focusNarrowCanvas = value
        Settings.saveFocusNarrowCanvas(value)
    }

    func setFocusHideToolbar(_ value: Bool) {
        focusHideToolbar = value
        Settings.saveFocusHideToolbar(value)
    }

    /// Escape, arriving from the web view. See `escapeAction` for the ordering.
    func handleEscapeFromPage() {
        switch escapeAction(findQuery: findQuery,
                            showQuickOpen: showQuickOpen,
                            focusMode: focusMode) {
        case .clearFind: findQuery = ""
        case .dismissQuickOpen: showQuickOpen = false
        case .exitFocusMode: toggleFocusMode()
        case .ignore: break
        }
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

    func setContentWidth(_ value: ContentWidth) {
        contentWidth = value
        Settings.saveContentWidth(value)
        focusStash?.contentWidth = value
    }

    func setExportLayout(_ value: ExportLayout) {
        exportLayout = value
        Settings.saveExportLayout(value)
    }

    func cycleContentWidth() {
        let all = ContentWidth.allCases
        let next = all[(all.firstIndex(of: contentWidth)! + 1) % all.count]
        setContentWidth(next)
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
        // Help docs / stdin temps / directories aren't documents worth remembering.
        if !node.isDirectory, !Self.isBundledDoc(node.url), !Self.isStdinTemp(node.url) {
            pushRecent(node.url.path)
        }
    }

    /// Recents and Favorites are file lists. Bundled help docs and directories (left
    /// over from an older file-URL open path) don't belong in either.
    nonisolated static func shouldKeepListed(_ path: String) -> Bool {
        if isBundledDoc(URL(fileURLWithPath: path)) { return false }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return false
        }
        return true
    }

    /// True for anything inside the app's own resource bundle — the help docs
    /// (FAQ / SHORTCUTS / CHANGELOG) and any internal doc added later.
    nonisolated static func isBundledDoc(_ url: URL) -> Bool {
        guard let root = Bundle.resources.resourceURL?.standardizedFileURL.path else { return false }
        return url.standardizedFileURL.path.hasPrefix(root)
    }

    /// Documents piped in with `reader -`. They live in a cache directory that gets
    /// reaped after a day, so keeping them out of recents avoids a list of dead paths.
    nonisolated static func isStdinTemp(_ url: URL) -> Bool {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return false
        }
        let dir = caches.appendingPathComponent("com.nahian.reader-md/stdin").standardizedFileURL.path
        return url.standardizedFileURL.path.hasPrefix(dir + "/")
    }

    /// Back to the empty state. History stacks survive, so ⌘[ still works.
    func closeFile() {
        selectedFile = nil
        toc = []
        reading.reset()
        loadMarksForCurrentFile()
        refreshDiff()
    }

    /// Open a path from Recents, a relative link, or a file URL. Folders become
    /// roots (same as a drop) instead of opening as a blank document; everything
    /// else opens as a file — including paths that no longer exist, so a stale
    /// recent still selects and can be removed rather than silently doing nothing.
    func openPath(_ path: String) {
        let resolved = Self.resolvedPath(path)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue {
            addDroppedFolder(URL(fileURLWithPath: resolved))
        } else {
            open(FileNode(url: URL(fileURLWithPath: resolved), isDirectory: false))
        }
    }

    /// marked runs `encodeURI` on hrefs, so a link to `My Note.md` reaches us as
    /// `My%20Note.md`. Try the literal path first: that encoding isn't reversible
    /// (it leaves a real `%` alone), so a file actually named `a%20b.md` has to win
    /// over the decoded spelling. Recents and file URLs arrive decoded already.
    nonisolated static func resolvedPath(_ path: String) -> String {
        let fm = FileManager.default
        if !fm.fileExists(atPath: path), let decoded = path.removingPercentEncoding,
           decoded != path, fm.fileExists(atPath: decoded) {
            return decoded
        }
        return path
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
        reading.reset()
        loadMarksForCurrentFile()
        refreshDiff()
    }

    // MARK: - Reading position

    /// Live scroll fraction from the web view, persisted per file so reopening a
    /// long document resumes where you left off. The web view posts on every
    /// scroll event, so only meaningful moves are written back.
    func recordProgress(_ fraction: Double) {
        // The diff pane posts its own scroll fraction through this same message —
        // on render (renderDiff → reportProgress) and on every subsequent scroll
        // event. Never let that overwrite the document's saved reading position.
        guard !canShowDiff else { return }
        reading.progress = fraction
        guard let url = selectedFile?.url,
              !Self.isBundledDoc(url), !Self.isStdinTemp(url) else { return }
        let path = url.path
        guard abs((positions[path] ?? 0) - fraction) >= 0.01 else { return }
        positions[path] = fraction
        Settings.savePositions(positions)
    }

    /// Where the reader left off. A document barely started or already finished
    /// opens at the top — resuming into the last screen of something you've read
    /// is worse than not resuming at all.
    func savedProgress(for path: String) -> Double {
        let fraction = positions[path] ?? 0
        return (0.02...0.98).contains(fraction) ? fraction : 0
    }

    private func pushRecent(_ path: String) {
        recentFiles.removeAll { $0 == path }
        recentFiles.insert(path, at: 0)
        if recentFiles.count > 12 { recentFiles = Array(recentFiles.prefix(12)) }
        Settings.saveRecents(recentFiles)
    }

    /// What the sidebar's Recents section lists. A pinned file still records its
    /// recency (⌘P ranks by it), but showing it in both sections — with Recents
    /// above Favorites — reads as opening a favorite having moved it out.
    var unpinnedRecents: [String] {
        recentFiles.filter { !favoriteFiles.contains($0) }
    }

    func removeRecent(_ path: String) {
        recentFiles.removeAll { $0 == path }
        Settings.saveRecents(recentFiles)
    }

    func clearRecents() {
        recentFiles = []
        Settings.saveRecents([])
    }

    // MARK: - Favorites

    func isFavorite(_ path: String) -> Bool {
        favoriteFiles.contains(path)
    }

    /// A file can be pinned unless it isn't really the user's document: the
    /// bundled help docs and piped `reader -` temporaries are both transient in a
    /// way a pin implies they aren't — same rule that keeps them out of Recents,
    /// which also rules out folders (a pinned row opens as a document).
    nonisolated static func canFavorite(_ url: URL) -> Bool {
        shouldKeepListed(url.path) && !isStdinTemp(url)
    }

    /// New favorites append rather than insert: a pinned list that reshuffled on
    /// every pin would lose the order the user arranged it in.
    func addFavorite(_ path: String) {
        guard Self.canFavorite(URL(fileURLWithPath: path)), !favoriteFiles.contains(path) else { return }
        favoriteFiles.append(path)
        Settings.saveFavorites(favoriteFiles)
    }

    func removeFavorite(_ path: String) {
        guard favoriteFiles.contains(path) else { return }
        favoriteFiles.removeAll { $0 == path }
        Settings.saveFavorites(favoriteFiles)
    }

    func toggleFavorite(_ path: String) {
        isFavorite(path) ? removeFavorite(path) : addFavorite(path)
    }

    /// Drag-reorder, matching how roots move. `to` is an insertion index in the
    /// pre-move list, the way SwiftUI's `move(fromOffsets:toOffset:)` counts.
    func moveFavorite(from: Int, to: Int) {
        guard from != to, favoriteFiles.indices.contains(from),
              to >= 0, to <= favoriteFiles.count else { return }
        favoriteFiles.move(fromOffsets: IndexSet(integer: from), toOffset: to)
        Settings.saveFavorites(favoriteFiles)
    }

    /// The open document, for the menu item and the ⌘P command.
    var canFavoriteCurrentFile: Bool {
        guard let url = selectedFile?.url else { return false }
        return Self.canFavorite(url)
    }

    var currentFileIsFavorite: Bool {
        guard let path = selectedFile?.url.path else { return false }
        return isFavorite(path)
    }

    var favoriteMenuTitle: String {
        currentFileIsFavorite ? "Remove from Favorites" : "Add to Favorites"
    }

    func toggleFavoriteCurrentFile() {
        guard let path = selectedFile?.url.path else { return }
        toggleFavorite(path)
    }

    // MARK: - External editor

    /// Reader.md stays a reader: editing is handed off to the editor the user
    /// picks from Always Open With. `FolderWatcher` re-renders on save, so the pair
    /// behaves like a split editor/preview without this app owning an editor.
    ///
    /// There is deliberately no LaunchServices fallback. We register as a `.md`
    /// handler ourselves, so we're usually *the* default and the runner-up is
    /// whatever ranks next (Xcode on the author's Mac) — an arbitrary choice
    /// worse than none. Until an editor has been chosen, ⇧⌘E stays disabled.
    func openInEditor(_ url: URL) {
        guard let editor = resolvedEditor() else {
            // The editor is gone. `canOpenInEditor` can't catch that — it stays off
            // LaunchServices by design — so the menu item was enabled and ⇧⌘E would
            // otherwise be a dead keystroke. Ask for a replacement instead.
            // ponytail: no auto-retry of the open — the user presses ⇧⌘E again.
            // Re-entering here on a bundle id LaunchServices won't resolve would loop.
            pickDefaultEditor()
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: editor,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    /// The stored editor, or `nil` after clearing a bundle id that no longer
    /// resolves (the editor was uninstalled). Split from `openInEditor` so the
    /// clearing is reachable in tests without `pickDefaultEditor`'s modal panel.
    func resolvedEditor() -> URL? {
        guard let id = editorBundleID,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            editorBundleID = nil
            editorDisplayName = nil
            Settings.saveEditorBundleID(nil)
            return nil
        }
        return app
    }

    /// Opens in `app` and remembers it as the editor for ⇧⌘E.
    func openInEditor(_ url: URL, using app: URL) {
        rememberEditor(app)
        NSWorkspace.shared.open([url], withApplicationAt: app,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    /// Set the editor outright, without a document open — File → Set Default
    /// Editor…. Restricted to applications, starting in /Applications.
    func pickDefaultEditor() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        panel.message = "Choose the editor Reader.md hands markdown files to."
        if panel.runModal() == .OK, let app = panel.url { rememberEditor(app) }
    }

    /// The display name is resolved here, once per change, rather than in the
    /// menu label — that would be a LaunchServices hit on every render.
    private func rememberEditor(_ app: URL) {
        guard let id = Bundle(url: app)?.bundleIdentifier else { return }
        editorBundleID = id
        editorDisplayName = FileManager.default.displayName(atPath: app.path)
        Settings.saveEditorBundleID(id)
    }

    /// Forget the editor entirely — the inverse of `pickDefaultEditor`, offered
    /// in Settings. Same three lines `resolvedEditor()` runs when a stored
    /// bundle id stops resolving.
    func clearEditor() {
        editorBundleID = nil
        editorDisplayName = nil
        Settings.saveEditorBundleID(nil)
    }

    /// "Open in Cursor" once an editor is set, so the menu says which one.
    var openInEditorTitle: String {
        editorDisplayName.map { "Open in \($0)" } ?? "Open in Editor"
    }

    /// Our own bundle id. The literal is the `swift run` fallback — a bare
    /// executable has no Info.plist — and must match `BUNDLE_ID` in make-app.sh.
    nonisolated static var ownBundleID: String {
        Bundle.main.bundleIdentifier ?? "com.nahian.reader-md"
    }

    /// Apps that can open this file, minus ourselves and minus duplicate
    /// registrations (LaunchServices lists VS Code once per installed copy).
    /// A LaunchServices query — call it when a menu opens, never from a row body.
    nonisolated func editorCandidates(for url: URL) -> [URL] {
        Self.editorCandidates(from: NSWorkspace.shared.urlsForApplications(toOpen: url),
                              excluding: Self.ownBundleID)
    }

    /// The filtering half, split from the query above: what LaunchServices
    /// returns depends on what's installed, so only this part can be tested.
    nonisolated static func editorCandidates(from apps: [URL], excluding mine: String) -> [URL] {
        var seen = Set<String>()
        return apps
            .filter { app in
                guard let id = Bundle(url: app)?.bundleIdentifier, id != mine else { return false }
                return seen.insert(id).inserted
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func editorName(_ app: URL) -> String {
        FileManager.default.displayName(atPath: app.path)
    }

    /// Files worth handing to an editor. Bundled help docs are app resources,
    /// stdin docs are reaped temp files, and remote roots are sync caches whose
    /// edits the next pull would overwrite.
    /// ponytail: no writability probe — the editor reports read-only itself.
    func isEditable(_ url: URL) -> Bool {
        guard !Self.isBundledDoc(url), !Self.isStdinTemp(url) else { return false }
        let path = url.standardizedFileURL.path
        return !roots.contains {
            $0.remote != nil && path.hasPrefix($0.url.standardizedFileURL.path + "/")
        }
    }

    /// Enabled state for the ⇧⌘E menu item — cheap by design, no LaunchServices.
    var canOpenInEditor: Bool {
        guard let url = selectedFile?.url else { return false }
        return editorBundleID != nil && isEditable(url)
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

    /// The tree changed: refresh everything derived from it. Called when a scan
    /// lands and when roots are added, removed or reordered.
    func didRescan() {
        fileCount = allFiles().count
        refreshSearchResults()
    }

    /// Rebuilds `searchResults`. Called on each keystroke and after a rescan.
    func refreshSearchResults() {
        let q = normalizedQuery
        guard !q.isEmpty else {
            if !searchResults.isEmpty { searchResults = [] }   // no publish while idle
            return
        }
        searchResults = allFilesIndexed().filter { $0.node.name.lowercased().contains(q) }
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

/// What Escape should do when it arrives from the page.
///
/// A free function over three booleans rather than a method, so the ordering — the
/// only part of this that can silently regress — is testable without a window.
/// The in-page overlays (Mermaid fullscreen, the image lightbox) never reach here:
/// `bridge.js` resolves them before posting.
enum EscapeAction: Equatable {
    case clearFind
    case dismissQuickOpen
    case exitFocusMode
    /// Not `none` — `XCTAssertEqual(x, .none)` would resolve against
    /// `Optional.none` instead of this case.
    case ignore
}

func escapeAction(findQuery: String, showQuickOpen: Bool, focusMode: Bool) -> EscapeAction {
    if !findQuery.isEmpty { return .clearFind }
    if showQuickOpen { return .dismissQuickOpen }
    if focusMode { return .exitFocusMode }
    return .ignore
}

/// Whether the SwiftUI toolbar modifier should hide the window's toolbar.
///
/// A free function over three booleans, same reasoning as `escapeAction`: the
/// matrix is small but not obvious, and testable without a window is worth more
/// than a method would be. See `FocusToolbarTests` for why `toolbarRevealed`
/// exists at all.
func focusToolbarHidden(focusMode: Bool, hideToolbar: Bool, toolbarRevealed: Bool) -> Bool {
    focusMode && hideToolbar && !toolbarRevealed
}
