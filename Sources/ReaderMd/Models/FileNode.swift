import Foundation

enum RemoteSyncStatus: Equatable {
    case idle
    case syncing
    case failed(String)
}

/// A node in the markdown file tree — either a directory or a markdown file.
final class FileNode: Identifiable, Hashable {
    let id: String          // full path, unique
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]

    init(url: URL, isDirectory: Bool, children: [FileNode] = []) {
        self.id = url.path
        self.name = url.lastPathComponent
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum FileScanner {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mdx", "mkd", "mkdn", "mdwn"]
    static let ignoredDirs: Set<String> = ["node_modules", ".git", ".svn", "dist", "build", ".next", ".cache"]

    /// Whether a changed path could alter the scanned tree. The tree only ever holds
    /// markdown, so a write to a log, a .jsonl or a shell snapshot can't change it —
    /// and rescanning for one is not free: it walks every root (off the main thread,
    /// but each scan still ends in a main-thread assignment that re-renders the
    /// sidebar). A root over a directory that churns in non-markdown files
    /// (~/.claude, a repo mid build) otherwise rescans continuously for nothing.
    /// Directories carry no extension, so they pass: a folder rename does change the tree.
    static func affectsTree(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        if parts.contains(where: { ignoredDirs.contains(String($0)) }) { return false }
        let ext = (path as NSString).pathExtension.lowercased()
        return ext.isEmpty || markdownExtensions.contains(ext)
    }

    /// Paths git ignores under `directory`, for `scan(_:ignoring:worktrees:)`. Empty when
    /// git is missing or the folder isn't a repo. Shells out — off the main actor.
    /// Each of `worktrees` is a nested repo the parent's `ls-files` never enters,
    /// so its own ignores are looked up in it and folded in under its path.
    static func ignoredPaths(under directory: URL, worktrees: Set<String> = []) -> Set<String> {
        // isDirectory: true because a URL rebuilt from a saved path doesn't always
        // know it's a folder, and git is run *in* this directory.
        guard GitDiff.available else { return [] }
        let folder = URL(fileURLWithPath: directory.path, isDirectory: true)
        var ignored = GitDiff.ignoredPaths(in: folder)
        for tree in worktrees {
            let inner = GitDiff.ignoredPaths(in: folder.appendingPathComponent(tree, isDirectory: true))
            ignored.formUnion(inner.map { tree + "/" + $0 })
        }
        return ignored
    }

    /// Linked worktrees inside `directory`, for `scan(_:ignoring:worktrees:)`.
    static func worktrees(under directory: URL) -> Set<String> {
        guard GitDiff.available else { return [] }
        return GitDiff.worktreePaths(in: URL(fileURLWithPath: directory.path, isDirectory: true))
    }

    /// Recursively build a pruned tree containing only markdown files.
    /// `ignoring` holds paths relative to the scanned root — git's ignores, so a
    /// repo's build output and vendored docs stay out of the tree the way
    /// `ignoredDirs` keeps node_modules out. ponytail: no "show ignored files"
    /// toggle, matching `ignoredDirs`, which has always pruned silently.
    /// `worktrees` are the exception: listed even when ignored (#105), along with
    /// the ignored folders on the way to them, but nothing else inside those.
    static func scan(_ directory: URL, ignoring: Set<String> = [], worktrees: Set<String> = [],
                     relativeTo prefix: String = "", insideIgnored: Bool = false,
                     depth: Int = 0) -> [FileNode] {
        guard depth <= 12 else { return [] }
        let fm = FileManager.default
        // Note: hidden (dot-prefixed) entries are included so folders like
        // `.github` are scanned; noisy dot-dirs are still pruned via ignoredDirs.
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        var nodes: [FileNode] = []
        for entry in entries {
            let name = entry.lastPathComponent
            let relative = prefix + name
            let ignored = !worktrees.contains(relative) && (insideIgnored || ignoring.contains(relative))
            if ignored && !worktrees.contains(where: { $0.hasPrefix(relative + "/") }) { continue }
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                if ignoredDirs.contains(name) { continue }
                let children = scan(entry, ignoring: ignoring, worktrees: worktrees,
                                    relativeTo: relative + "/", insideIgnored: ignored, depth: depth + 1)
                if !children.isEmpty {
                    nodes.append(FileNode(url: entry, isDirectory: true, children: children))
                }
            } else if markdownExtensions.contains(entry.pathExtension.lowercased()) {
                nodes.append(FileNode(url: entry, isDirectory: false))
            }
        }

        nodes.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return nodes
    }
}

/// One root folder shown in the sidebar. `remote` is non-nil when this root
/// is the local cache of a synced remote folder.
@MainActor
final class RootFolder: Identifiable, ObservableObject {
    let id: String
    let url: URL
    @Published var remote: RemoteSpec?
    @Published var children: [FileNode] = []
    @Published var syncStatus: RemoteSyncStatus = .idle

    /// Starts empty and fills in from a background scan. `FileScanner.scan` walks
    /// the whole subtree — measured at ~1.3s across seven roots — so it must never
    /// run on the main thread, not at launch and not on a folder change.
    init(url: URL, remote: RemoteSpec? = nil, onScan: (@MainActor () -> Void)? = nil) {
        self.id = remote?.id ?? url.path
        self.url = url
        self.remote = remote
        rescan(then: onScan)
    }

    var name: String { remote?.name ?? url.lastPathComponent }
    var isRemote: Bool { remote != nil }

    /// `onlyIfIgnored` is for the one caller that re-scans a root already scanned
    /// this launch: the git probe lands after `loadSavedRoots()`, so the first
    /// scan ran without git's ignores. Re-walking a root that turns out to have
    /// none is pure cost — and the walk is the expensive part, ~1.3s across seven
    /// roots — so the cheap git calls run first and decide.
    func rescan(onlyIfIgnored: Bool = false, then completion: (@MainActor () -> Void)? = nil) {
        let url = self.url
        Task.detached(priority: .userInitiated) {
            // `worktree list` and `ls-files` per scan, plus one `ls-files` per
            // worktree, alongside the walk. They double as the is-a-repo test, so
            // a root outside one pays two failed git calls.
            let worktrees = FileScanner.worktrees(under: url)
            let ignoring = FileScanner.ignoredPaths(under: url, worktrees: worktrees)
            if onlyIfIgnored && ignoring.isEmpty { return }
            let scanned = FileScanner.scan(url, ignoring: ignoring, worktrees: worktrees)
            await MainActor.run {
                self.children = scanned
                completion?()
            }
        }
    }
}
