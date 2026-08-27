import Foundation

/// Where a rendered PDF is staged on its way to the system share picker.
///
/// A per-share subdirectory rather than a unique filename: AirDrop shows the
/// receiver the file's name and saves it under that name, so the document's
/// basename has to survive while two concurrent shares still get separate files.
enum ShareTemp {
    /// The staging root. Emptied at launch and never during a session — an
    /// AirDrop transfer is still reading the file after the picker closes.
    static let directory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("Reader.md-Share", isDirectory: true)

    /// A PDF path named after `path`, inside a fresh directory that already
    /// exists. `nil` — nothing loaded — falls back to "document", the same
    /// default the export save panel uses.
    static func url(for path: String?) -> URL {
        let base = (path as NSString?)?.lastPathComponent ?? "document"
        let dir = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent((base as NSString).deletingPathExtension + ".pdf")
    }

    /// Drops everything previous launches staged.
    static func purge() {
        try? FileManager.default.removeItem(at: directory)
    }
}
