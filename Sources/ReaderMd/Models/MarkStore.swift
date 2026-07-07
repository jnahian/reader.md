import Foundation
import CryptoKit

/// Persists per-document `Mark` data to
/// `~/Library/Application Support/Reader.md/marks/<sha256(absolutePath)>.json`.
///
/// Keyed by path (survives content edits, lost on rename/move); `contentHash` is
/// stored alongside so callers can detect "file changed since marks were made."
final class MarkStore {
    private let baseDir: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        baseDir = support.appendingPathComponent("Reader.md/marks", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    func load(path: String) -> MarkDocument? {
        guard let data = try? Data(contentsOf: fileURL(for: path)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MarkDocument.self, from: data)
    }

    func save(_ doc: MarkDocument) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(doc) else { return }
        try? data.write(to: fileURL(for: doc.filePath), options: .atomic)
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func fileURL(for path: String) -> URL {
        baseDir.appendingPathComponent("\(Self.sha256(path)).json")
    }
}
