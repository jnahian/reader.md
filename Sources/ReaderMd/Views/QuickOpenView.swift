import SwiftUI

/// ⌘P command palette — fuzzy file switcher across all roots.
struct QuickOpenView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var matches: [QuickMatch] {
        let files = state.allFilesIndexed()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()

        // Empty query → recents first (in recency order), then everything else.
        if q.isEmpty {
            let ordered = files.sorted { a, b in
                let ra = state.recentRank(a.node.url.path)
                let rb = state.recentRank(b.node.url.path)
                switch (ra, rb) {
                case let (.some(x), .some(y)): return x < y
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none):
                    return a.searchText.localizedCaseInsensitiveCompare(b.searchText) == .orderedAscending
                }
            }
            return Array(ordered.prefix(60)).map { QuickMatch(file: $0, score: 0) }
        }

        // Non-empty query → fuzzy match against the whole "root/folder/file" path.
        // Filename hits outrank folder-only hits, and recently opened files break ties.
        return files
            .compactMap { file -> QuickMatch? in
                let nameScore = fuzzyScore(q, file.node.name.lowercased())
                let pathScore = fuzzyScore(q, file.searchText.lowercased())
                guard nameScore != nil || pathScore != nil else { return nil }
                var score = max(nameScore ?? Int.min, (pathScore ?? Int.min))
                if nameScore != nil { score += 40 }   // prefer filename matches
                if let rank = state.recentRank(file.node.url.path) {
                    score += max(0, 30 - rank * 2)     // gentle recency nudge
                }
                return QuickMatch(file: file, score: score)
            }
            .sorted { $0.score > $1.score }
            .prefix(60)
            .map { $0 }
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
                                ForEach(Array(items.enumerated()), id: \.element.file.node.id) { idx, match in
                                    QuickOpenRow(match: match, selected: idx == selection)
                                        .id(idx)
                                        .onTapGesture { open(match.file.node) }
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
        .onMoveCommand { direction in
            let count = matches.count
            guard count > 0 else { return }
            if direction == .down { selection = min(selection + 1, count - 1) }
            else if direction == .up { selection = max(selection - 1, 0) }
        }
        .onExitCommand { close() }
        .onAppear { focused = true }
    }

    private func openSelected() {
        let items = matches
        guard selection < items.count else { return }
        open(items[selection].file.node)
    }

    private func open(_ node: FileNode) {
        state.open(node)
        close()
    }

    private func close() {
        state.showQuickOpen = false
    }
}

private struct QuickMatch {
    let file: IndexedFile
    let score: Int
}

private struct QuickOpenRow: View {
    let match: QuickMatch
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(selected ? Color.white : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(match.file.node.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                    Text(match.file.locationLabel)
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
