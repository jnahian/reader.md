import XCTest
@testable import ReaderMd

/// `FolderWatcher` fires a main-thread rescan of every root, so what it lets through
/// is load-bearing: a root over a directory that churns in non-markdown files (a
/// `~/.claude` full of .jsonl transcripts, a repo mid build) pinned that thread and
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
}
