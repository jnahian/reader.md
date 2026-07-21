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

    /// `id` defaults to the root name; pass it explicitly to model two added
    /// folders that happen to share a display name.
    private func file(root: String, path: String, id: String? = nil) -> IndexedFile {
        let url = URL(fileURLWithPath: "/\(id ?? root)/\(path)")
        return IndexedFile(node: FileNode(url: url, isDirectory: false),
                           rootID: id ?? root, rootName: root, relativePath: path)
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

    /// Two added folders can share a display name ("~/a/docs" and "~/b/docs").
    /// They must stay separate buckets: no file repeated, and both roots
    /// represented — bucketing by name would do neither.
    func testSameNamedRootsAreNotMerged() {
        var files = [file(root: "docs", path: "b.md", id: "/y/docs")]
        for i in 0..<50 { files.append(file(root: "docs", path: "a\(i).md", id: "/x/docs")) }

        let ordered = quickOpenBrowseOrder(files, rootOrder: ["/x/docs", "/y/docs"],
                                           limit: files.count, recentRank: { _ in nil })

        XCTAssertEqual(ordered.count, files.count)
        XCTAssertEqual(Set(ordered.map { $0.node.url.path }).count, files.count)   // no duplicates
        XCTAssertEqual(Array(ordered.prefix(2)).map { $0.rootID }, ["/x/docs", "/y/docs"])
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
