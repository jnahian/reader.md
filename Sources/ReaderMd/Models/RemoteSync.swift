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
}

struct RemoteSyncResult {
    let success: Bool
    let message: String   // "" on success; tail of rsync stderr on failure
}

extension RemoteSync {
    /// Runs rsync for `spec`, creating the cache dir first. Never throws;
    /// failures are returned as `RemoteSyncResult(success: false, ...)`.
    static func run(_ spec: RemoteSpec) async -> RemoteSyncResult {
        try? FileManager.default.createDirectory(at: spec.cacheURL, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = arguments(for: spec)
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: data, encoding: .utf8) ?? ""
                let tail = stderr.split(separator: "\n").suffix(4).joined(separator: "\n")
                let ok = proc.terminationStatus == 0
                continuation.resume(returning: RemoteSyncResult(
                    success: ok,
                    message: ok ? "" : (tail.isEmpty ? "rsync exited with code \(proc.terminationStatus)" : tail)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: RemoteSyncResult(
                    success: false, message: "Could not launch rsync: \(error.localizedDescription)"))
            }
        }
    }
}
