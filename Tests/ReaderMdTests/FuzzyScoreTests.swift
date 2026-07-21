import XCTest
@testable import ReaderMd

/// Tests for the ⌘P quick-open ranker (`fuzzyScore`). These encode the ordering
/// properties the palette relies on when it sorts matches — the actual scores
/// are implementation detail, only their relative order matters.
final class FuzzyScoreTests: XCTestCase {

    func testNonSubsequenceReturnsNil() {
        XCTAssertNil(fuzzyScore("xyz", "readme"))
        XCTAssertNil(fuzzyScore("rdx", "readme"))   // out of order
    }

    func testEmptyQueryScoresZero() {
        XCTAssertEqual(fuzzyScore("", "anything"), 0)
    }

    func testSubsequenceMatches() {
        XCTAssertNotNil(fuzzyScore("rdm", "readme"))
        XCTAssertNotNil(fuzzyScore("readme", "readme"))
    }

    func testPrefixBeatsMidStringMatch() throws {
        let prefix = try XCTUnwrap(fuzzyScore("read", "readme"))
        let mid = try XCTUnwrap(fuzzyScore("read", "unreadme"))
        XCTAssertGreaterThan(prefix, mid)
    }

    func testContiguousBeatsScattered() throws {
        let contiguous = try XCTUnwrap(fuzzyScore("abc", "abcxyz"))
        let scattered = try XCTUnwrap(fuzzyScore("abc", "axbxc"))
        XCTAssertGreaterThan(contiguous, scattered)
    }

    func testShorterTextBeatsLongerForSameMatch() throws {
        let short = try XCTUnwrap(fuzzyScore("cfg", "config.md"))
        let long = try XCTUnwrap(fuzzyScore("cfg", "config-defaults.md"))
        XCTAssertGreaterThan(short, long)
    }
}

/// Tests for the ⌘P ordering that spans every added folder/server.
final class QuickOpenOrderingTests: XCTestCase {

    private func file(root: String, path: String) -> IndexedFile {
        let url = URL(fileURLWithPath: "/\(root)/\(path)")
        return IndexedFile(node: FileNode(url: url, isDirectory: false),
                           rootName: root, relativePath: path)
    }

    /// The bug: a root with many files must not starve out other roots in browse
    /// mode. Every root should surface a file near the top, not after the first
    /// root's entire (possibly huge) listing.
    func testBrowseOrderRepresentsEveryRoot() {
        var files: [IndexedFile] = []
        for i in 0..<200 { files.append(file(root: "Big", path: String(format: "doc%03d.md", i))) }
        files.append(file(root: "Small", path: "readme.md"))
        files.append(file(root: "server", path: "notes.md"))

        let ordered = quickOpenBrowseOrder(files, rootOrder: ["Big", "Small", "server"],
                                           recentRank: { _ in nil })

        // Round-robin: Big, Small, server appear in the first three slots.
        XCTAssertEqual(Array(ordered.prefix(3)).map { $0.rootName }, ["Big", "Small", "server"])

        // And within the visible cap, no root is missing.
        let visibleRoots = Set(ordered.prefix(quickOpenResultLimit).map { $0.rootName })
        XCTAssertEqual(visibleRoots, ["Big", "Small", "server"])
    }

    func testBrowseOrderPutsRecentsFirst() {
        let recent = file(root: "Big", path: "doc100.md")
        var files: [IndexedFile] = []
        for i in 0..<50 { files.append(file(root: "Big", path: "doc\(i).md")) }
        files.append(recent)
        files.append(file(root: "Small", path: "readme.md"))

        let ordered = quickOpenBrowseOrder(files, rootOrder: ["Big", "Small"],
                                           recentRank: { $0 == recent.node.url.path ? 0 : nil })

        XCTAssertEqual(ordered.first?.node.url.path, recent.node.url.path)
    }

    /// A specific filename typed into the palette is found regardless of which
    /// root it lives in.
    func testRankedMatchesFindFilesInAnyRoot() {
        let files = [
            file(root: "Big", path: "index.md"),
            file(root: "Small", path: "guides/config.md"),
            file(root: "server", path: "deploy/config.md"),
        ]
        let ranked = quickOpenRankedMatches(files, query: "config", recentRank: { _ in nil })
        let roots = Set(ranked.map { $0.rootName })
        XCTAssertTrue(roots.contains("Small"))
        XCTAssertTrue(roots.contains("server"))
    }
}
