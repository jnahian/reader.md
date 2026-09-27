import XCTest
@testable import ReaderMd

/// `FolderWatcher` fires a rescan of every root, so what it lets through is
/// load-bearing: a root over a directory that churns in non-markdown files (a
/// `~/.claude` full of .jsonl transcripts, a repo mid build) rescans continuously
/// for nothing, and each scan ends in a main-thread tree swap that re-renders the
/// sidebar. Before the scan moved off the main thread this pinned it outright and
/// the window stopped delivering mouse events — no `:hover`, so no on-hover chrome.
final class WatchFilterTests: XCTestCase {

    func testMarkdownWritesRescan() {
        XCTAssertTrue(FileScanner.affectsTree("/Users/x/docs/notes.md"))
        XCTAssertTrue(FileScanner.affectsTree("/Users/x/docs/NOTES.MARKDOWN"))
    }

    func testNonMarkdownWritesDoNot() {
        XCTAssertFalse(FileScanner.affectsTree("/Users/x/.claude/projects/a/session.jsonl"))
        XCTAssertFalse(FileScanner.affectsTree("/Users/x/.claude/shell-snapshots/snap.sh"))
    }

    /// Extensionless paths are directories, and a folder rename does change the tree.
    func testDirectoriesRescan() {
        XCTAssertTrue(FileScanner.affectsTree("/Users/x/docs/guides"))
    }

    /// Pruned dirs never appear in the tree, so nothing inside one is worth a walk.
    func testPrunedDirsAreIgnoredEvenForMarkdown() {
        XCTAssertFalse(FileScanner.affectsTree("/Users/x/repo/node_modules/pkg/README.md"))
        XCTAssertFalse(FileScanner.affectsTree("/Users/x/repo/.git/index"))
    }

    /// Only the path inside the root counts: a root under a folder named like a
    /// pruned one (`~/work/build/notes`) still reloads on its own edits.
    func testPrunedNameAboveTheRootDoesNotMatter() {
        XCTAssertTrue(FolderWatcher.affectsTree("/Users/x/build/notes/a.md", under: "/Users/x/build/notes"))
        XCTAssertFalse(FolderWatcher.affectsTree("/Users/x/build/notes/dist/a.md", under: "/Users/x/build/notes"))
    }
}
