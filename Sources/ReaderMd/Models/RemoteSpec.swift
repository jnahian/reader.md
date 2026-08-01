import Foundation

/// A saved remote folder — either an ssh destination plus a path on that host
/// (rsync'd), or a git repository (cloned). Either way Reader.md syncs it
/// read-only into a stable local cache directory.
struct RemoteSpec: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var sshDestination: String   // "user@host"; empty for a git remote
    var remotePath: String       // absolute path on the remote; empty for a git remote
    /// Clone URL. Optional because specs saved before git remotes existed have
    /// no such key, and a synthesized decoder throws on a missing non-optional
    /// one — which would drop every saved remote on upgrade.
    var gitURL: String?

    var isGit: Bool { gitURL != nil }

    init(id: String = UUID().uuidString, name: String,
         sshDestination: String = "", remotePath: String = "", gitURL: String? = nil) {
        self.id = id
        self.name = name
        self.sshDestination = sshDestination
        self.remotePath = remotePath
        self.gitURL = gitURL
    }

    /// Stable per-remote local cache directory. Depends only on `id` so it is
    /// unchanged across re-syncs — marks (keyed by sha256(path)) then survive.
    var cacheURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Reader.md/remotes/\(id)", isDirectory: true)
    }
}
