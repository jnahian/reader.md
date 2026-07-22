import SwiftUI
import AppKit

/// ⌘P command palette. Three modes, chosen by a leading character in the query:
///   • (default) fuzzy-match files against their full "root/folder/file.md" path
///   • `>`       run an app command (toggle theme, export, add folder, …)
///   • `#`       jump to a heading in the current document
/// Matched characters are highlighted in each row; the footer shows hints and a
/// result count, and ⌘1–9 activates one of the first nine rows directly.
struct QuickOpenView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var model = QuickOpenModel()
    @State private var keyMonitor: Any?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search files —  > commands  ·  # headings", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($focused)
                        .onSubmit { activateSelected() }
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 14)

                Divider()

                let items = model.matches
                if items.isEmpty {
                    Text(emptyStateText)
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                                    QuickOpenRow(content: item.rowContent, index: idx, selected: idx == model.selection)
                                        .id(idx)
                                        .onTapGesture { activatePaletteItem(item, in: state) }
                                }
                            }
                            .padding(6)
                        }
                        .frame(maxHeight: 340)
                        .onChange(of: model.selection) { newValue in
                            withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(newValue, anchor: .center) }
                        }
                    }
                }

                Divider()
                footer(shown: items.count, total: model.totalCount)
            }
            .frame(width: 560)
            .background(GlassPanel(cornerRadius: 19, material: .hudWindow))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(Color.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.3), radius: 28, y: 12)
            .padding(.top, 90)
        }
        .onExitCommand { close() }
        // The focused TextField swallows arrow keys before .onMoveCommand can see
        // them, so intercept up/down (and ⌘1–9) with a local monitor while open.
        .onAppear {
            model.load(state)
            // Async, not direct: ⌘P arrives as a menu command, and AppKit restores the
            // window's first responder *after* the menu dismisses — clobbering a focus
            // set synchronously here. One runloop turn later, the restore has happened
            // and the field keeps focus.
            DispatchQueue.main.async { focused = true }
            // The monitor captures `model` and `state` (both references), never the
            // view's own @State: an escaping closure holding @State keeps reading the
            // query and list as they were when the palette opened, so the arrows
            // walked a stale list and Enter opened the wrong row.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model, state] event in
                // ⌘1–9 activates the Nth visible row directly.
                if event.modifierFlags.contains(.command),
                   let chars = event.charactersIgnoringModifiers,
                   let n = Int(chars), (1...9).contains(n) {
                    let items = model.matches
                    guard items.indices.contains(n - 1) else { return event }
                    activatePaletteItem(items[n - 1], in: state)
                    return nil
                }
                switch event.keyCode {
                case 125: model.move(1);  return nil   // down arrow
                case 126: model.move(-1); return nil   // up arrow
                default:  return event
                }
            }
        }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        }
    }

    /// Placeholder shown when the current mode has no results.
    private var emptyStateText: String {
        switch model.mode {
        case .commands: return "No matching commands"
        case .headings: return model.hasHeadings ? "No matching headings" : "No headings in this document"
        case .files:    return model.effectiveQuery.isEmpty ? "Type to search files" : "No files"
        }
    }

    /// Bottom bar: key hints on the left, result count on the right.
    private func footer(shown: Int, total: Int) -> some View {
        HStack(spacing: 12) {
            hint("↑↓", "navigate")
            hint("↩", "select")
            hint("⌘1–9", "jump")
            Spacer(minLength: 0)
            if shown > 0 {
                Text(total > shown ? "\(shown) of \(total)" : "\(total) result\(total == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func activateSelected() {
        guard let item = model.selected else { return }
        activatePaletteItem(item, in: state)
    }

    private func close() {
        state.showQuickOpen = false
    }
}

/// Which list the palette is showing, decided by the query's leading character.
enum PaletteMode { case files, commands, headings }

/// A single row in the palette — a file, a command, or a heading — each carrying
/// the character indices in its title that the query matched (for highlighting).
enum PaletteItem: Identifiable {
    case file(QuickOpenResult)
    case command(PaletteCommand, titleMatches: [Int])
    case heading(TOCEntry, titleMatches: [Int])

    var id: String {
        switch self {
        case .file(let r):       return "file:\(r.id)"
        case .command(let c, _): return "cmd:\(c.id)"
        case .heading(let h, _): return "head:\(h.id)"
        }
    }

    var rowContent: RowContent {
        switch self {
        case .file(let r):
            return RowContent(systemImage: "doc.text", title: r.file.node.name,
                              titleMatches: r.nameMatches, subtitle: r.file.locationLabel,
                              subtitleImage: "folder")
        case .command(let c, let m):
            return RowContent(systemImage: c.systemImage, title: c.title,
                              titleMatches: m, subtitle: c.subtitle, subtitleImage: nil)
        case .heading(let h, let m):
            return RowContent(systemImage: "number", title: h.text,
                              titleMatches: m, subtitle: nil, subtitleImage: nil)
        }
    }
}

/// Perform a palette row's action, then dismiss the palette. Shared by the
/// Enter key, mouse click, and ⌘1–9 paths so they can't drift apart.
@MainActor
func activatePaletteItem(_ item: PaletteItem, in state: AppState) {
    // Dismiss first: some commands (Add Folder, Open File) run a modal panel that
    // blocks synchronously, and we don't want the palette dimming behind it.
    state.showQuickOpen = false
    switch item {
    case .file(let r):       state.open(r.file.node)
    case .command(let c, _): c.run(state)
    case .heading(let h, _): state.requestScroll(to: h.id)
    }
}

/// An app action reachable from `>` command mode. `run` is `@MainActor` so its
/// body can call `AppState`'s main-actor methods directly.
struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let run: @MainActor (AppState) -> Void
}

/// The commands offered in `>` mode, in display order. Document-scoped commands
/// (export, copy path) appear only when a file is open, so they can't no-op.
@MainActor
func paletteCommands(_ state: AppState) -> [PaletteCommand] {
    var cmds: [PaletteCommand] = [
        PaletteCommand(id: "theme",
                       title: state.theme == .dark ? "Switch to Light Appearance" : "Switch to Dark Appearance",
                       subtitle: "Appearance",
                       systemImage: state.theme == .dark ? "sun.max" : "moon") { $0.toggleTheme() },
        PaletteCommand(id: "sidebar", title: "Toggle Sidebar", subtitle: "Layout",
                       systemImage: "sidebar.left") { $0.toggleSidebar() },
        PaletteCommand(id: "outline", title: "Toggle Outline", subtitle: "Layout",
                       systemImage: "list.bullet.indent") { $0.setShowTOC(!$0.showTOC) },
        PaletteCommand(id: "width", title: "Cycle Content Width", subtitle: "Layout",
                       systemImage: "arrow.left.and.right") { $0.cycleContentWidth() },
        PaletteCommand(id: "addFolder", title: "Add Folder…", subtitle: "Files",
                       systemImage: "folder.badge.plus") { $0.pickFolders() },
        PaletteCommand(id: "openFile", title: "Open File…", subtitle: "Files",
                       systemImage: "doc.badge.plus") { $0.pickFile() },
        PaletteCommand(id: "addRemote", title: "Add Remote Folder…", subtitle: "Files",
                       systemImage: "network") { $0.showAddRemote = true },
    ]
    if state.selectedFile != nil {
        cmds.append(PaletteCommand(id: "export", title: "Export as PDF…", subtitle: "Document",
                                   systemImage: "arrow.down.doc") { $0.exportToken += 1 })
        cmds.append(PaletteCommand(id: "copyPath", title: "Copy File Path", subtitle: "Document",
                                   systemImage: "doc.on.clipboard") { s in
            guard let file = s.selectedFile else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.url.path, forType: .string)
        })
    }
    return cmds
}

/// Palette state. A class, not view `@State`, so the key-event monitor reads the
/// live query and selection instead of a snapshot taken when it was installed.
@MainActor
final class QuickOpenModel: ObservableObject {
    @Published var query = "" { didSet { selection = 0 } }
    @Published private(set) var selection = 0

    private var files: [IndexedFile] = []
    private var recents: [String] = []
    private var commands: [PaletteCommand] = []
    private var headings: [TOCEntry] = []

    var hasHeadings: Bool { !headings.isEmpty }

    /// Index the roots (and snapshot commands + headings) once per open. Walking
    /// every root's tree on each keystroke is what made ⌘P feel slower than the
    /// sidebar filter; the palette is transient, so state that shifts while it's
    /// up can wait for the next open.
    func load(_ state: AppState) {
        files = state.allFilesIndexed()
        recents = state.recentFiles
        commands = paletteCommands(state)
        headings = state.toc
        query = ""
        selection = 0
    }

    /// Mode is chosen by the query's leading character: `>` commands, `#` headings.
    var mode: PaletteMode {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(">") { return .commands }
        if trimmed.hasPrefix("#") { return .headings }
        return .files
    }

    /// The query with any mode prefix stripped.
    var effectiveQuery: String {
        var trimmed = query.trimmingCharacters(in: .whitespaces)
        if mode != .files { trimmed.removeFirst() }
        return trimmed.trimmingCharacters(in: .whitespaces)
    }

    /// The full ordered result list, before the visible cap.
    private var ordered: [PaletteItem] {
        switch mode {
        case .commands:
            return quickOpenCommandItems(commands, query: effectiveQuery)
        case .headings:
            return quickOpenHeadingItems(headings, query: effectiveQuery)
        case .files:
            let q = effectiveQuery.lowercased()
            let rank: (String) -> Int? = { [recents] path in recents.firstIndex(of: path) }
            let results = q.isEmpty
                ? quickOpenRecents(files, recentRank: rank)
                : quickOpenMatches(files, query: q, recentRank: rank)
            return results.map { PaletteItem.file($0) }
        }
    }

    /// Rows actually shown — the ordered list clamped to `quickOpenResultLimit`.
    var matches: [PaletteItem] { Array(ordered.prefix(quickOpenResultLimit)) }

    /// Total matches found (may exceed what the capped list shows).
    var totalCount: Int { ordered.count }

    /// The selected row, clamped — the list shrinks as you type.
    var selected: PaletteItem? {
        let items = matches
        return items.indices.contains(selection) ? items[selection] : items.first
    }

    func move(_ delta: Int) {
        let count = matches.count
        selection = count > 0 ? min(max(0, selection + delta), count - 1) : 0
    }
}

/// The pieces a palette row draws: an icon, a title with matched runs to bold,
/// and an optional subtitle (with its own optional leading icon).
struct RowContent {
    let systemImage: String
    let title: String
    let titleMatches: [Int]
    let subtitle: String?
    let subtitleImage: String?
}

private struct QuickOpenRow: View {
    let content: RowContent
    let index: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: content.systemImage)
                .font(.system(size: 12))
                .frame(width: 16)
                .foregroundStyle(selected ? Color.white : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                highlightedText(content.title, matches: content.titleMatches)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                if let subtitle = content.subtitle {
                    HStack(spacing: 5) {
                        if let image = content.subtitleImage {
                            Image(systemName: image).font(.system(size: 9))
                        }
                        Text(subtitle)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            Spacer(minLength: 0)
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(selected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
    }
}

/// A title with the fuzzy-matched characters drawn bold; the rest keeps the
/// row's medium weight. Size + weight are baked per run so an outer `.font`
/// can't reset the per-character bold back to a uniform weight.
func highlightedText(_ string: String, matches: [Int]) -> Text {
    guard !matches.isEmpty else {
        return Text(string).font(.system(size: 13, weight: .medium))
    }
    let matched = Set(matches)
    var text = Text("")
    for (i, char) in string.enumerated() {
        text = text + Text(String(char)).font(.system(size: 13, weight: matched.contains(i) ? .bold : .medium))
    }
    return text
}

/// Max rows the palette shows — recents when the query is empty, matches
/// otherwise. Small on purpose: past ten rows you type instead of scrolling.
let quickOpenResultLimit = 10

/// A file plus the indices in its filename that a query matched, so the row
/// can highlight them. `nameMatches` is empty for recents (no active query).
struct QuickOpenResult: Identifiable {
    let file: IndexedFile
    let nameMatches: [Int]
    var id: String { file.id }
}

/// Ordering for an empty query: the most recently opened files, newest first.
/// Browsing the whole corpus isn't useful in a 10-row list — type to search.
func quickOpenRecents(_ files: [IndexedFile], recentRank: (String) -> Int?) -> [QuickOpenResult] {
    files
        .compactMap { file in recentRank(file.node.url.path).map { (file, $0) } }
        .sorted { $0.1 < $1.1 }
        .map { QuickOpenResult(file: $0.0, nameMatches: []) }
}

/// Matching for a typed query: a case-insensitive fuzzy (subsequence) match
/// against each file's full "root/folder/file.md" path, so folder names narrow
/// the list too (e.g. "docsintro" finds "docs/intro.md"). Recently opened files
/// still float to the top; the rest sort by match quality, then path.
func quickOpenMatches(
    _ files: [IndexedFile],
    query q: String,
    recentRank: (String) -> Int?
) -> [QuickOpenResult] {
    let pattern = q.lowercased().filter { !$0.isWhitespace }
    guard !pattern.isEmpty else { return [] }

    struct Scored {
        let result: QuickOpenResult
        let score: Int
        let rank: Int?
    }

    let scored: [Scored] = files.compactMap { file in
        let candidate = file.searchText
        guard let match = fuzzyMatch(pattern, in: candidate) else { return nil }
        // Map the matched positions that fall inside the filename (a contiguous
        // suffix of `candidate`) back to filename-relative indices for the row.
        let nameStart = candidate.count - file.node.name.count
        let nameMatches = match.indices.filter { $0 >= nameStart }.map { $0 - nameStart }
        // Weight filename hits over folder-only hits.
        let score = match.score + nameMatches.count * 4
        return Scored(result: QuickOpenResult(file: file, nameMatches: nameMatches),
                      score: score,
                      rank: recentRank(file.node.url.path))
    }

    return scored.sorted { a, b in
        switch (a.rank, b.rank) {
        case let (.some(x), .some(y)): return x < y
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none):
            if a.score != b.score { return a.score > b.score }
            return a.result.file.searchText.localizedCaseInsensitiveCompare(b.result.file.searchText) == .orderedAscending
        }
    }.map { $0.result }
}

/// Commands filtered by a `>`-mode query. An empty query lists every command in
/// display order; otherwise fuzzy-match the title and sort by match quality.
func quickOpenCommandItems(_ commands: [PaletteCommand], query: String) -> [PaletteItem] {
    let pattern = query.lowercased().filter { !$0.isWhitespace }
    guard !pattern.isEmpty else { return commands.map { .command($0, titleMatches: []) } }

    return commands
        .compactMap { cmd -> (command: PaletteCommand, match: FuzzyMatch)? in
            fuzzyMatch(pattern, in: cmd.title).map { (command: cmd, match: $0) }
        }
        .sorted { a, b in
            a.match.score != b.match.score ? a.match.score > b.match.score : a.command.title < b.command.title
        }
        .map { .command($0.command, titleMatches: $0.match.indices) }
}

/// Headings filtered by a `#`-mode query. An empty query lists every heading in
/// document order; otherwise fuzzy-match the heading text by match quality.
func quickOpenHeadingItems(_ headings: [TOCEntry], query: String) -> [PaletteItem] {
    let pattern = query.lowercased().filter { !$0.isWhitespace }
    guard !pattern.isEmpty else { return headings.map { .heading($0, titleMatches: []) } }

    return headings
        .compactMap { entry -> (entry: TOCEntry, match: FuzzyMatch)? in
            fuzzyMatch(pattern, in: entry.text).map { (entry: entry, match: $0) }
        }
        .sorted { a, b in
            a.match.score != b.match.score ? a.match.score > b.match.score : a.entry.text < b.entry.text
        }
        .map { .heading($0.entry, titleMatches: $0.match.indices) }
}

/// A scored fuzzy match: the character positions in the candidate that the
/// query matched, and a quality score (higher is better).
struct FuzzyMatch {
    let score: Int
    let indices: [Int]
}

/// Case-insensitive subsequence match of `pattern` (assumed lowercased, no
/// whitespace) against `candidate`. Returns nil when `pattern` isn't a
/// subsequence. The greedy left-to-right walk rewards matches that start a word
/// (string start or after a separator), continue a run, or hit a camelCase
/// boundary — so contiguous, word-aligned matches rank above scattered ones.
func fuzzyMatch(_ pattern: String, in candidate: String) -> FuzzyMatch? {
    if pattern.isEmpty { return FuzzyMatch(score: 0, indices: []) }
    let separators: Set<Character> = ["/", "\\", "-", "_", " ", ".", "›", "(", ")", "[", "]"]
    let cand = Array(candidate)
    let pat = Array(pattern)

    var indices: [Int] = []
    indices.reserveCapacity(pat.count)
    var score = 0
    var pi = 0
    var lastMatched = -1
    var ci = 0
    while ci < cand.count && pi < pat.count {
        if cand[ci].lowercased() == String(pat[pi]) {
            var points = 1
            let prev = ci > 0 ? cand[ci - 1] : nil
            if ci == 0 || (prev.map { separators.contains($0) } ?? false) {
                points += 12                                   // start of a word
            } else if let p = prev, p.isLowercase, cand[ci].isUppercase {
                points += 8                                    // camelCase boundary
            }
            if lastMatched == ci - 1 { points += 10 }          // contiguous run
            score += points
            indices.append(ci)
            lastMatched = ci
            pi += 1
        }
        ci += 1
    }
    return pi == pat.count ? FuzzyMatch(score: score, indices: indices) : nil
}
