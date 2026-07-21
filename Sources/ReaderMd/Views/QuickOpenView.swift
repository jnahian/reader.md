import SwiftUI
import AppKit

/// ⌘P command palette — file switcher across all roots. Matching is the same
/// rule the sidebar filter uses (`FileNode.matches`), so the two searches agree.
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
                                ForEach(Array(items.enumerated()), id: \.element.node.id) { idx, file in
                                    QuickOpenRow(file: file, selected: idx == model.selection)
                                        .id(idx)
                                        .onTapGesture { open(file.node) }
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
            model.load(state)
            // Async, not direct: ⌘P arrives as a menu command, and AppKit restores the
            // window's first responder *after* the menu dismisses — clobbering a focus
            // set synchronously here. One runloop turn later, the restore has happened
            // and the field keeps focus.
            DispatchQueue.main.async { focused = true }
            // The monitor captures `model` (a reference), never the view's own
            // @State: an escaping closure holding @State keeps reading the query
            // and list as they were when the palette opened, so the arrows walked
            // a stale list and Enter opened the wrong row.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model] event in
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

    private func openSelected() {
        guard let file = model.selected else { return }
        open(file.node)
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

    var matches: [IndexedFile] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let rank: (String) -> Int? = { [recents] path in recents.firstIndex(of: path) }
        let ordered = q.isEmpty
            ? quickOpenRecents(files, recentRank: rank)
            : quickOpenMatches(files, query: q, recentRank: rank)
        return Array(ordered.prefix(quickOpenResultLimit))
    }

    /// The selected row, clamped — the list shrinks as you type.
    var selected: IndexedFile? {
        let items = matches
        return items.indices.contains(selection) ? items[selection] : items.first
    }

    func move(_ delta: Int) {
        let count = matches.count
        selection = count > 0 ? min(max(0, selection + delta), count - 1) : 0
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

/// Max rows the palette shows — recents when the query is empty, matches
/// otherwise. Small on purpose: past ten rows you type instead of scrolling.
let quickOpenResultLimit = 10

/// Ordering for an empty query: the most recently opened files, newest first.
/// Browsing the whole corpus isn't useful in a 10-row list — type to search.
func quickOpenRecents(_ files: [IndexedFile], recentRank: (String) -> Int?) -> [IndexedFile] {
    files
        .compactMap { file in recentRank(file.node.url.path).map { (file, $0) } }
        .sorted { $0.1 < $1.1 }
        .map { $0.0 }
}

/// Matching for a typed query: the sidebar's own filter (`FileNode.matches` — a
/// case-insensitive substring of the filename), applied across every root.
/// Recently opened files float to the top, the rest sort by path.
func quickOpenMatches(
    _ files: [IndexedFile],
    query q: String,
    recentRank: (String) -> Int?
) -> [IndexedFile] {
    files
        .filter { $0.node.matches(q) }
        .sorted { a, b in
            switch (recentRank(a.node.url.path), recentRank(b.node.url.path)) {
            case let (.some(x), .some(y)): return x < y
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none):
                return a.searchText.localizedCaseInsensitiveCompare(b.searchText) == .orderedAscending
            }
        }
}
