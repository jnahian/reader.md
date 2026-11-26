import Foundation

/// A git root shown as it is on another branch (#110): the ref that was picked,
/// and the commit it named when that commit was extracted. The root's tree is
/// read from that extraction in `BranchCache`, never from the working tree, so
/// nothing in the repository or its `.git` is written.
struct BranchView: Codable, Equatable {
    let ref: String
    let sha: String

    /// Persisted views are user-writable, as `DiffScope(persisted:)` notes. A ref
    /// starting with `-` would read as an option to git, and a sha that isn't
    /// plain hex would let the cache path climb out of its folder. 40 for a
    /// SHA-1 repository, 64 for a SHA-256 one.
    var isValid: Bool {
        !ref.isEmpty && !ref.hasPrefix("-")
            && [40, 64].contains(sha.count) && sha.allSatisfy(\.isHexDigit)
    }
}

/// Where branch views are extracted: `<Caches>/com.nahian.reader-md/branches/
/// <sha256(root id)>/<sha>/`. Keyed by root rather than by repository, because
/// two roots in one repository at different subfolders extract different trees.
/// Keyed by commit inside that, so an extraction never changes: if the folder is
/// there it is complete, and a branch that moves gets a new folder.
enum BranchCache {
    static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("com.nahian.reader-md/branches", isDirectory: true)
    }

    /// The same types a synced remote keeps (`RemoteSync.arguments`): the tree
    /// only ever lists markdown, and the images are what its pages reference.
    static let keptExtensions = FileScanner.markdownExtensions.union(RemoteSync.imageExtensions)

    static func folder(forRoot id: String, in base: URL = directory) -> URL {
        base.appendingPathComponent(MarkStore.sha256(id), isDirectory: true)
    }

    static func tree(forRoot id: String, sha: String, in base: URL = directory) -> URL {
        folder(forRoot: id, in: base).appendingPathComponent(sha, isDirectory: true)
    }

    /// True for a file read from a branch view. Such a file is a copy of a
    /// commit, not the user's document: it stays out of Recents, Favorites and
    /// saved positions, can't be handed to an editor, and takes no marks.
    static func contains(_ url: URL, in base: URL = directory) -> Bool {
        url.standardizedFileURL.path.hasPrefix(base.standardizedFileURL.path + "/")
    }

    /// `<sha>:<prefix>` names the root's own subtree, so the archive's entries
    /// start at the root, where `FileScanner` expects them, rather than at the
    /// repository's top. `rev-parse --show-prefix` prints "docs/" for a root in a
    /// subfolder and nothing at the top; `<sha>:` alone is the whole tree.
    static func treeish(sha: String, prefix: String) -> String {
        sha + ":" + (prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix)
    }

    /// `path` moved from the tree at `old` to the same place in the tree at
    /// `new`, or nil when it isn't inside `old`. One function for every move —
    /// working copy to branch, one commit to the next, branch back to working
    /// copy — so the open document and the history all follow the same way.
    static func remap(_ path: String, from old: URL, to new: URL) -> String? {
        let base = old.standardizedFileURL.path
        let file = URL(fileURLWithPath: path).standardizedFileURL.path
        guard file.hasPrefix(base + "/") else { return nil }
        return new.standardizedFileURL.path + String(file.dropFirst(base.count))
    }

    /// Deletes the root's extractions other than `sha`, and the root's folder
    /// once nothing is kept. In-progress extractions are left alone: a newer pick
    /// may be unpacking one while an older pick prunes.
    static func prune(root id: String, keeping sha: String?, in base: URL = directory) {
        let fm = FileManager.default
        let folder = folder(forRoot: id, in: base)
        guard let entries = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        for name in entries where name != sha && !name.contains(".partial-") {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
        if sha == nil, (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? fm.removeItem(at: folder)
        }
    }
}

// MARK: - Git

extension BranchCache {

    /// The commit `ref` names now, or nil when it names none. Callers must be off
    /// the main actor.
    static func resolve(_ ref: String, in root: URL) -> String? {
        guard !ref.hasPrefix("-"),
              case .output(let out) = GitDiff.run(["rev-parse", "--verify", "--quiet", ref + "^{commit}"], in: root)
        else { return nil }
        let sha = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
    }

    /// What the working copy has checked out: the branch, or a short sha when
    /// HEAD is detached. Nil outside a repository. `--quiet` makes a detached
    /// HEAD exit 1 with no output, which `GitDiff.run` reports as empty output.
    /// Callers must be off the main actor.
    static func head(in root: URL) -> String? {
        for args in [["symbolic-ref", "--quiet", "--short", "HEAD"], ["rev-parse", "--short", "HEAD"]] {
            if case .output(let out) = GitDiff.run(args, in: root) {
                let name = out.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { return name }
            }
        }
        return nil
    }

    /// Extracts the root's subtree at `sha` into `tree(forRoot:sha:)`. Returns nil
    /// once the tree is there, or git's or tar's complaint. Callers must be off
    /// the main actor.
    ///
    /// Atomic: the tree is unpacked beside its final name and renamed into place,
    /// so a folder at that name always holds a whole extraction — restoring a
    /// branch view at launch trusts exactly that. `--output` rather than a pipe,
    /// because `GitDiff.run` buffers and decodes stdout as text, which corrupts a
    /// tarball. Reads only: `git archive` writes nothing to the repository.
    static func extract(sha: String, ofRoot id: String, from root: URL, in base: URL = directory) -> String? {
        let fm = FileManager.default
        let final = tree(forRoot: id, sha: sha, in: base)
        if fm.fileExists(atPath: final.path) { return nil }

        // Run at the top: from a subfolder, `git archive` keeps only the paths
        // under that subfolder *inside* the tree it's given, so `<sha>:docs` run
        // from docs/ looks for docs/docs/ and archives nothing.
        guard case .output(let out) = GitDiff.run(["rev-parse", "--show-toplevel", "--show-prefix"], in: root),
              let top = out.components(separatedBy: "\n").first, !top.isEmpty else {
            return "\(root.lastPathComponent) is not in a git repository."
        }
        let prefix = out.components(separatedBy: "\n").dropFirst().first ?? ""
        let folder = folder(forRoot: id, in: base)
        let partial = folder.appendingPathComponent("\(sha).partial-\(UUID().uuidString)", isDirectory: true)
        let archive = partial.appendingPathExtension("tar")
        defer {
            try? fm.removeItem(at: archive)
            try? fm.removeItem(at: partial)
        }
        do {
            try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        } catch {
            return error.localizedDescription
        }

        let treeish = treeish(sha: sha, prefix: prefix.trimmingCharacters(in: .whitespacesAndNewlines))
        if case .failure(let message) = GitDiff.run(
            ["archive", "--format=tar", "--output=\(archive.path)", treeish],
            in: URL(fileURLWithPath: top, isDirectory: true)) {
            return message
        }
        if let message = untar(archive, into: partial) { return message }
        keepOnlyReadable(in: partial)

        do {
            try fm.moveItem(at: partial, to: final)
        } catch {
            // Two picks of the same commit raced, and the other one won.
            if fm.fileExists(atPath: final.path) { return nil }
            return error.localizedDescription
        }
        return nil
    }

    /// Drops every file but `keptExtensions`, compared the way `FileScanner`
    /// compares them, ignoring case. After extraction rather than as a filter on
    /// it: git fails the whole archive when any one pathspec matches nothing, and
    /// tar does the same with an `--include` pattern.
    private static func keepOnlyReadable(in directory: URL) {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let url as URL in walker
        where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            && !keptExtensions.contains(url.pathExtension.lowercased()) {
            try? fm.removeItem(at: url)
        }
    }

    private static func untar(_ archive: URL, into directory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-x", "-f", archive.path, "-C", directory.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return "Could not launch tar: \(error.localizedDescription)"
        }
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        let message = String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "tar exited with code \(process.terminationStatus)" : message
    }
}
