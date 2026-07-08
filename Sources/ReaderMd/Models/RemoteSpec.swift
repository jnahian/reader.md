import Foundation

/// A saved remote (SSH) folder: an ssh destination plus a path on that host.
/// Reader.md syncs it read-only into a stable local cache directory.
struct RemoteSpec: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var sshDestination: String   // "user@host"
    var remotePath: String       // absolute path on the remote

    init(id: String = UUID().uuidString, name: String, sshDestination: String, remotePath: String) {
        self.id = id
        self.name = name
        self.sshDestination = sshDestination
        self.remotePath = remotePath
    }

    /// Stable per-remote local cache directory. Depends only on `id` so it is
    /// unchanged across re-syncs — marks (keyed by sha256(path)) then survive.
    var cacheURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Reader.md/remotes/\(id)", isDirectory: true)
    }
}
