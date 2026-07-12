import Foundation

/// Piped markdown becomes a real file — the app renders files, not streams. The
/// CLI cannot delete it (the app may not have read it yet), so cleanup is a reap
/// of old temps on the next run.
enum StdinDoc {
    static let directory: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.nahian.reader-md/stdin", isDirectory: true)

    /// The `.md` extension is required: without it the app will not render the
    /// file as markdown.
    static func write(_ data: Data, now: TimeInterval, into directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(Int(now))-\(UUID().uuidString).md")
        try data.write(to: url)
        return url
    }

    static func reap(in directory: URL, olderThan age: TimeInterval, now: Date) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for entry in entries {
            guard let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate else { continue }
            if now.timeIntervalSince(modified) > age {
                try? fm.removeItem(at: entry)
            }
        }
    }
}
