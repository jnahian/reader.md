import SwiftUI
import AppKit

/// ⌘P command palette — file switcher across all roots. A typed query is
/// fuzzy-matched against each file's full "root/folder/file.md" path, so both
/// filename and folder narrow the list; matched characters are highlighted in
/// the row and the result count/hints show in the footer.
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
                    TextField("Search files and folders…", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($focused)
                        .onSubmit { openSelected() }
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 14)

                Divider()

                let items = model.matches
                if items.isEmpty {
                    Text(model.query.isEmpty ? "Type to search files" : "No files")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { idx, result in
                                    QuickOpenRow(result: result, index: idx, selected: idx == model.selection)
                                        .id(idx)
                                        .onTapGesture { open(result.file.node) }
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
                // ⌘1–9 opens the Nth visible row directly.
                if event.modifierFlags.contains(.command),
                   let chars = event.charactersIgnoringModifiers,
                   let n = Int(chars), (1...9).contains(n) {
                    let items = model.matches
                    guard items.indices.contains(n - 1) else { return event }
                    state.open(items[n - 1].file.node)
                    state.showQuickOpen = false
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

    /// Bottom bar: key hints on the left, result count on the right.
    private func footer(shown: Int, total: Int) -> some View {
        HStack(spacing: 12) {
            hint("↑↓", "navigate")
            hint("↩", "open")
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

    private func openSelected() {
        guard let result = model.selected else { return }
        open(result.file.node)
    }

    private func open(_ node: FileNode) {
        state.open(node)
        close()
    }

    private func close() {
        state.showQuickOpen = false
    }
}

/// Palette state. A class, not view `@State`, so the key-event monitor reads the
/// live query and selection instead of a snapshot taken when it was installed.
@MainActor
final class QuickOpenModel: ObservableObject {
    @Published var query = "" { didSet { selection = 0 } }
    @Published private(set) var selection = 0

    private var files: [IndexedFile] = []
    private var recents: [String] = []

    /// Index the roots once per open. Walking every root's tree on each
    /// keystroke is what made ⌘P feel slower than the sidebar filter; the
    /// palette is transient, so a file that appears while it's up can wait.
    func load(_ state: AppState) {
        files = state.allFilesIndexed()
        recents = state.recentFiles
        query = ""
        selection = 0
    }

    /// The full ordered result list, before the visible cap.
    private var ordered: [QuickOpenResult] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let rank: (String) -> Int? = { [recents] path in recents.firstIndex(of: path) }
        return q.isEmpty
            ? quickOpenRecents(files, recentRank: rank)
            : quickOpenMatches(files, query: q, recentRank: rank)
    }

    /// Rows actually shown — the ordered list clamped to `quickOpenResultLimit`.
    var matches: [QuickOpenResult] { Array(ordered.prefix(quickOpenResultLimit)) }

    /// Total matches found (may exceed what the capped list shows).
    var totalCount: Int { ordered.count }

    /// The selected row, clamped — the list shrinks as you type.
    var selected: QuickOpenResult? {
        let items = matches
        return items.indices.contains(selection) ? items[selection] : items.first
    }

    func move(_ delta: Int) {
        let count = matches.count
        selection = count > 0 ? min(max(0, selection + delta), count - 1) : 0
    }
}

private struct QuickOpenRow: View {
    let result: QuickOpenResult
    let index: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(selected ? Color.white : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                highlightedName
                    .foregroundStyle(selected ? Color.white : Color.primary)
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                    Text(result.file.locationLabel)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
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

    /// Filename with the fuzzy-matched characters drawn bold; everything else
    /// keeps the row's medium weight.
    private var highlightedName: Text {
        let name = result.file.node.name
        guard !result.nameMatches.isEmpty else {
            return Text(name).font(.system(size: 13, weight: .medium))
        }
        // Bake size + weight into each run so an outer .font can't reset the
        // per-character bold back to a uniform weight.
        let matched = Set(result.nameMatches)
        var text = Text("")
        for (i, char) in name.enumerated() {
            text = text + Text(String(char)).font(.system(size: 13, weight: matched.contains(i) ? .bold : .medium))
        }
        return text
    }
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
