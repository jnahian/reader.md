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

    /// True if this file's name matches the query, or (for dirs) any descendant matches.
    func matches(_ query: String) -> Bool {
        if query.isEmpty { return true }
        if isDirectory {
            return children.contains { $0.matches(query) }
        }
        return name.lowercased().contains(query)
    }
}

enum FileScanner {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mdx"]
    static let ignoredDirs: Set<String> = ["node_modules", ".git", ".svn", "dist", "build", ".next", ".cache"]

    /// Recursively build a pruned tree containing only markdown files.
    static func scan(_ directory: URL, depth: Int = 0) -> [FileNode] {
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
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                if ignoredDirs.contains(name) { continue }
                let children = scan(entry, depth: depth + 1)
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
final class RootFolder: Identifiable, ObservableObject {
    let id: String
    let url: URL
    let remote: RemoteSpec?
    @Published var children: [FileNode]
    @Published var syncStatus: RemoteSyncStatus = .idle

    init(url: URL, remote: RemoteSpec? = nil) {
        self.id = remote?.id ?? url.path
        self.url = url
        self.remote = remote
        self.children = FileScanner.scan(url)
    }

    var name: String { remote?.name ?? url.lastPathComponent }
    var isRemote: Bool { remote != nil }

    func rescan() {
        children = FileScanner.scan(url)
    }
}
