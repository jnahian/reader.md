import Foundation

enum RemoteSync {
    /// Image types included so markdown-referenced local images resolve via
    /// the WebView's file:// access.
    static let imageExtensions = ["png", "jpg", "jpeg", "gif", "svg", "webp"]

    /// The rsync argument vector (excluding the "rsync" program name).
    /// Include-filter mirrors `FileScanner.markdownExtensions` + images;
    /// excludes mirror `FileScanner.ignoredDirs`.
    static func arguments(for spec: RemoteSpec) -> [String] {
        var args = ["-az", "--delete", "--prune-empty-dirs", "-e", "ssh"]
        // Dir excludes FIRST so pruned dirs are matched before "descend".
        for dir in FileScanner.ignoredDirs.sorted() {
            args.append("--exclude=\(dir)")
        }
        args.append("--include=*/")                      // descend into remaining dirs
        for ext in FileScanner.markdownExtensions.sorted() {
            args.append("--include=*.\(ext)")
        }
        for ext in imageExtensions {
            args.append("--include=*.\(ext)")
        }
        args.append("--exclude=*")                        // drop everything else
        args.append("\(spec.sshDestination):\(trailingSlash(spec.remotePath))")
        args.append(trailingSlash(spec.cacheURL.path))
        return args
    }

    private static func trailingSlash(_ p: String) -> String {
        p.hasSuffix("/") ? p : p + "/"
    }

    /// The git argument vector for a repo remote: clone the first time, pull
    /// after that. `--` keeps a repository URL starting with `-` from reading as
    /// an option. `--quiet` keeps git off stderr, which `run` only drains after
    /// the process exits.
    ///
    /// ponytail: a full clone, not `--depth 1` — a shallow one has no history to
    /// compare against, which is exactly what the "vs <branch>" diff scope needs.
    /// `--ff-only` refuses to merge rather than inventing a commit in a cache the
    /// user never asked to own.
    static func gitArguments(for spec: RemoteSpec, cloned: Bool) -> [String] {
        guard let url = spec.gitURL else { return [] }
        return cloned
            ? ["-C", spec.cacheURL.path, "pull", "--ff-only", "--quiet"]
            : ["clone", "--quiet", "--", url, spec.cacheURL.path]
    }

    /// Never let git block on a prompt: an unauthenticated clone would hang the
    /// sync forever instead of failing. The environment is inherited and *then*
    /// added to — assigning a fresh dictionary drops HOME, and git without HOME
    /// finds no ~/.gitconfig, no ~/.ssh and no credential helper.
    static func gitEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_SSH_COMMAND"] = "ssh -oBatchMode=yes"
        return env
    }
}

struct RemoteSyncResult {
    let success: Bool
    let message: String   // "" on success; tail of rsync stderr on failure
}

extension RemoteSync {
    /// Runs rsync (or git, for a repo remote) for `spec`, creating the cache dir
    /// first. Never throws; failures are returned as
    /// `RemoteSyncResult(success: false, ...)`.
    static func run(_ spec: RemoteSpec) async -> RemoteSyncResult {
        let fm = FileManager.default
        let process = Process()

        if spec.isGit {
            // The id is what makes cacheURL a per-remote directory; with an empty
            // one it is the shared `remotes/` parent, and the wipe below would take
            // every other remote's cache with it. In-app ids are UUIDs, but the
            // defaults plist this is decoded from is user-writable.
            guard !spec.id.isEmpty else {
                return RemoteSyncResult(success: false, message: "Remote has no id")
            }
            let cloned = fm.fileExists(atPath: spec.cacheURL.appendingPathComponent(".git").path)
            // `git clone` demands an empty directory, and creates it itself. The
            // cache is non-empty and not a repo when an rsync remote was edited
            // into a git one — without this the remote would be wedged for good.
            // Only ever our own cache directory, keyed by the spec's UUID.
            if !cloned { try? fm.removeItem(at: spec.cacheURL) }
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = gitArguments(for: spec, cloned: cloned)
            process.environment = gitEnvironment()
        } else {
            try? fm.createDirectory(at: spec.cacheURL, withIntermediateDirectories: true)
            process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
            process.arguments = arguments(for: spec)
        }
        let errPipe = Pipe()
        // ponytail: stderr on failure is a few lines — well under the pipe buffer,
        // which is why draining it after exit is safe (git is run `--quiet` to keep
        // it that way); drain incrementally if verbose flags are ever added
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        let tool = spec.isGit ? "git" : "rsync"
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: data, encoding: .utf8) ?? ""
                let tail = stderr.split(separator: "\n").suffix(4).joined(separator: "\n")
                let ok = proc.terminationStatus == 0
                continuation.resume(returning: RemoteSyncResult(
                    success: ok,
                    message: ok ? "" : (tail.isEmpty ? "\(tool) exited with code \(proc.terminationStatus)" : tail)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: RemoteSyncResult(
                    success: false, message: "Could not launch \(tool): \(error.localizedDescription)"))
            }
        }
    }
}
