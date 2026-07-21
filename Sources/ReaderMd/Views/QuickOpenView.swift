import SwiftUI
import AppKit

/// ⌘P command palette — fuzzy file switcher across all roots.
struct QuickOpenView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var selection = 0
    @State private var keyMonitor: Any?
    @FocusState private var focused: Bool

    /// Re-ranking walks every indexed file, so the list follows the debounced
    /// query rather than each keystroke. Enter still uses the live query (see
    /// `openSelected`) so a fast type-then-return can't open a stale row.
    private var matches: [IndexedFile] { matches(for: debouncedQuery) }

    private func matches(for text: String) -> [IndexedFile] {
        let files = state.allFilesIndexed()
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        let rootOrder = state.roots.map { $0.id }
        let ordered = q.isEmpty
            ? quickOpenBrowseOrder(files, rootOrder: rootOrder, recentRank: { state.recentRank($0) })
            : quickOpenRankedMatches(files, query: q, recentRank: { state.recentRank($0) })
        return Array(ordered.prefix(quickOpenResultLimit))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search files and folders…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($focused)
                        .onSubmit { openSelected() }
                        .onChange(of: query) { _ in selection = 0 }
                        // 120ms idle before re-ranking; the task is cancelled and
                        // restarted on every keystroke.
                        .task(id: query) {
                            try? await Task.sleep(nanoseconds: 120_000_000)
                            guard !Task.isCancelled else { return }
                            debouncedQuery = query
                        }
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 14)

                Divider()

                let items = matches
                if items.isEmpty {
                    Text("No files")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(Array(items.enumerated()), id: \.element.node.id) { idx, file in
                                    QuickOpenRow(file: file, selected: idx == selection)
                                        .id(idx)
                                        .onTapGesture { open(file.node) }
                                }
                            }
                            .padding(6)
                        }
                        .frame(maxHeight: 340)
                        .onChange(of: selection) { newValue in
                            withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(newValue, anchor: .center) }
                        }
                    }
                }
            }
            .frame(width: 560)
            .background(GlassPanel(cornerRadius: 19, material: .hudWindow))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(Color.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.3), radius: 28, y: 12)
            .padding(.top, 90)
        }
        .onExitCommand { close() }
        // The focused TextField swallows arrow keys before .onMoveCommand can see
        // them, so intercept up/down with a local monitor while the palette is open.
        .onAppear {
            // Async, not direct: ⌘P arrives as a menu command, and AppKit restores the
            // window's first responder *after* the menu dismisses — clobbering a focus
            // set synchronously here. One runloop turn later, the restore has happened
            // and the field keeps focus.
            DispatchQueue.main.async { focused = true }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let count = matches.count
                switch event.keyCode {
                case 125: // down arrow
                    if count > 0 { selection = min(selection + 1, count - 1) }
                    return nil
                case 126: // up arrow
                    if count > 0 { selection = max(selection - 1, 0) }
                    return nil
                default:
                    return event
                }
            }
        }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        }
    }

    private func openSelected() {
        let items = matches(for: query)
        guard selection < items.count else { return }
        open(items[selection].node)
    }

    private func open(_ node: FileNode) {
        state.open(node)
        close()
    }

    private func close() {
        state.showQuickOpen = false
    }
}

private struct QuickOpenRow: View {
    let file: IndexedFile
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(selected ? Color.white : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.node.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                    Text(file.locationLabel)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
    }
}

/// Max rows the palette shows. A cap keeps the list snappy; the ordering below
/// makes sure that within it every added folder/server is represented rather than
/// the first root monopolizing all the slots.
let quickOpenResultLimit = 100

/// Ordering for an empty query (browse mode): recently opened files first (in
/// recency order), then every other file interleaved across roots round-robin.
///
/// The interleave is the fix for "⌘P can't find files from all added
/// folders/servers": a flat alphabetical sort front-loads whichever root sorts
/// first, so once one folder has more files than the visible cap, no other
/// folder's files ever appear. Round-robin guarantees each root gets slots.
func quickOpenBrowseOrder(
    _ files: [IndexedFile],
    rootOrder: [String],
    limit: Int = quickOpenResultLimit,
    recentRank: (String) -> Int?
) -> [IndexedFile] {
    let recents = files
        .filter { recentRank($0.node.url.path) != nil }
        .sorted { (recentRank($0.node.url.path) ?? 0) < (recentRank($1.node.url.path) ?? 0) }
    let recentPaths = Set(recents.map { $0.node.url.path })

    // Bucket the remaining files by owning root, each bucket sorted by path.
    // Keyed by root *id*, not display name — two added folders can share a name
    // ("docs" and "docs"), and merging them would both starve one of its slots
    // and emit each file once per same-named root.
    var byRoot: [String: [IndexedFile]] = [:]
    for file in files where !recentPaths.contains(file.node.url.path) {
        byRoot[file.rootID, default: []].append(file)
    }
    for id in byRoot.keys {
        byRoot[id]?.sort { $0.searchText.localizedCaseInsensitiveCompare($1.searchText) == .orderedAscending }
    }

    // Visit roots in sidebar order first, then any bucket not covered by rootOrder.
    var seen = Set<String>()
    var orderedIDs = rootOrder.filter { byRoot[$0] != nil && seen.insert($0).inserted }
    orderedIDs += byRoot.keys.filter { !seen.contains($0) }.sorted()

    // Stop at the visible cap: with lopsided roots the round-robin would otherwise
    // walk roots × largest-bucket passes to build rows nobody sees.
    var interleaved: [IndexedFile] = []
    var depth = 0
    var addedAny = true
    while addedAny && recents.count + interleaved.count < limit {
        addedAny = false
        for id in orderedIDs {
            if let bucket = byRoot[id], depth < bucket.count {
                interleaved.append(bucket[depth])
                addedAny = true
            }
        }
        depth += 1
    }
    return recents + interleaved
}

/// Ranking for a non-empty query: fuzzy match against both the filename and the
/// whole "root/folder/file" path. Filename hits outrank folder-only hits, and
/// recently opened files break ties. Score is global (across every root), so a
/// good match in any added folder/server survives the visible cap.
func quickOpenRankedMatches(
    _ files: [IndexedFile],
    query q: String,
    recentRank: (String) -> Int?
) -> [IndexedFile] {
    files
        .compactMap { file -> (file: IndexedFile, score: Int)? in
            let nameScore = fuzzyScore(q, file.node.name.lowercased())
            let pathScore = fuzzyScore(q, file.searchText.lowercased())
            guard nameScore != nil || pathScore != nil else { return nil }
            var score = max(nameScore ?? Int.min, pathScore ?? Int.min)
            if nameScore != nil { score += 40 }   // prefer filename matches
            if let rank = recentRank(file.node.url.path) {
                score += max(0, 30 - rank * 2)     // gentle recency nudge
            }
            return (file, score)
        }
        .sorted { $0.score > $1.score }
        .map { $0.file }
}

/// Simple fuzzy subsequence scorer. Returns nil if `query` isn't a subsequence of `text`.
func fuzzyScore(_ query: String, _ text: String) -> Int? {
    let q = Array(query), t = Array(text)
    guard !q.isEmpty else { return 0 }
    var qi = 0, score = 0, streak = 0
    for (ti, ch) in t.enumerated() {
        if qi < q.count && ch == q[qi] {
            streak += 1
            score += 5 + streak * 3          // reward contiguous runs
            if ti == 0 { score += 15 }       // prefix bonus
            qi += 1
        } else {
            streak = 0
        }
    }
    guard qi == q.count else { return nil }
    score -= (t.count - q.count)             // prefer shorter, tighter names
    return score
}
