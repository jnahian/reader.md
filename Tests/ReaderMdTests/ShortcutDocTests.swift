import XCTest
@testable import ReaderMd

/// The shortcut list exists three times: the `.keyboardShortcut` bindings in
/// `ReaderMdApp.swift` (the authority), the bundled `SHORTCUTS.md` the app opens
/// at ⌘/, and the table in `docs/features.md` the site publishes. The first two
/// are shipped together; the third has drifted before — it was missing ⎋,
/// ⌘1–⌘9, ↑ ↓ and ⏎ for as long as it existed.
///
/// This pins the two documents to each other. It cannot reach the bindings —
/// they are a SwiftUI view tree, not data — so a shortcut that exists only in
/// the app still has to be added by hand. What it does catch is the common
/// case: a shortcut documented for users but missing from the site.
final class ShortcutDocTests: XCTestCase {
    /// Runs of modifier glyphs with whatever key follows, plus keys that stand
    /// alone. `⌘1–⌘9` stays one token; both files write it that way.
    ///
    /// The standalone set has to list every unmodified key either file uses: a
    /// glyph missing from it parses as nothing, so a row carrying it would be
    /// compared against nothing and drift between the two documents unnoticed.
    private static let tokenPattern = "[⌃⌥⇧⌘]+[^\\s|]*|[⎋⏎↑↓⇥␣]"

    /// The first cell of every table row, minus separators and headers.
    private func shortcutTokens(in markdown: String) -> Set<String> {
        let regex = try! NSRegularExpression(pattern: Self.tokenPattern)
        var found: Set<String> = []

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") else { continue }
            let cells = trimmed.split(separator: "|", omittingEmptySubsequences: false)
            guard cells.count > 1 else { continue }
            // `\\` is how a literal backslash is written for Reader.md's own
            // renderer; the site's source carries the same escape. Compare the
            // character, not the escape.
            let cell = cells[1]
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\\\\", with: "\\")
            guard cell != "Shortcut", !cell.allSatisfy({ $0 == "-" || $0 == ":" }) else { continue }

            let range = NSRange(cell.startIndex..., in: cell)
            for match in regex.matches(in: cell, range: range) {
                if let r = Range(match.range, in: cell) { found.insert(String(cell[r])) }
            }
        }
        return found
    }

    private func bundledShortcuts() throws -> String {
        let url = try XCTUnwrap(
            Bundle.resources.url(forResource: "SHORTCUTS", withExtension: "md", subdirectory: "docs"),
            "SHORTCUTS.md should be bundled — if this fails, the resource copy broke"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// `docs/features.md` is repo content, not a bundled resource, so it is
    /// reached from this file's own path rather than from a Bundle.
    private func publishedFeatures() throws -> String {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ReaderMdTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        return try String(contentsOf: repo.appendingPathComponent("docs/features.md"), encoding: .utf8)
    }

    /// Guards the comparison below from passing vacuously: a parser that
    /// suddenly finds nothing would make every subset assertion true.
    func testTheParserFindsTheShortcutsAtAll() throws {
        let bundled = shortcutTokens(in: try bundledShortcuts())
        XCTAssertGreaterThan(bundled.count, 25, "parsed only \(bundled.count) shortcuts out of SHORTCUTS.md")
        for expected in ["⌘O", "⇧⌘A", "⌥⌘A", "⌘1–⌘9", "⎋", "⏎", "↑", "↓", "⇧⌘\\", "⇥", "⇧⇥", "␣"] {
            XCTAssertTrue(bundled.contains(expected), "SHORTCUTS.md parse is missing \(expected)")
        }
    }

    func testEveryBundledShortcutIsPublished() throws {
        let bundled = shortcutTokens(in: try bundledShortcuts())
        let published = shortcutTokens(in: try publishedFeatures())
        let missing = bundled.subtracting(published).sorted()
        XCTAssertTrue(missing.isEmpty, """
            docs/features.md is missing \(missing.joined(separator: ", ")).
            The app shows these at ⌘/, so the site has to list them too.
            """)
    }

    /// The other direction is a weaker claim — the site may add a shortcut the
    /// bundled list forgot — but a shortcut published to users and absent from
    /// the app's own help is just as much a drift, so it fails too.
    func testNothingIsPublishedThatTheAppDoesNotShow() throws {
        let bundled = shortcutTokens(in: try bundledShortcuts())
        let published = shortcutTokens(in: try publishedFeatures())
        let extra = published.subtracting(bundled).sorted()
        XCTAssertTrue(extra.isEmpty, """
            docs/features.md lists \(extra.joined(separator: ", ")), which SHORTCUTS.md does not.
            Add them to the bundled list, or drop them from the site.
            """)
    }
}
