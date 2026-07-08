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
