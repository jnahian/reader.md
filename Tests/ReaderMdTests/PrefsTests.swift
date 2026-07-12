import XCTest
@testable import ReaderCLI

final class PrefsTests: XCTestCase {
    func testLocalFoldersAreListedByBasename() {
        let roots = Prefs.format(folders: ["/Users/x/docs", "/tmp/notes"], remotesJSON: nil)
        XCTAssertEqual(roots, [
            Prefs.Root(name: "docs", detail: "/Users/x/docs"),
            Prefs.Root(name: "notes", detail: "/tmp/notes"),
        ])
    }

    func testRemotesAreListedWithTheirSSHTarget() {
        // Shape written by AppState.persistRemotes -> JSONEncoder on [RemoteSpec].
        let json = Data("""
        [{"id":"A1","name":"vps-docs","sshDestination":"me@vps","remotePath":"/srv/docs"}]
        """.utf8)
        let roots = Prefs.format(folders: [], remotesJSON: json)
        XCTAssertEqual(roots, [Prefs.Root(name: "vps-docs", detail: "me@vps:/srv/docs")])
    }

    func testFoldersAndRemotesTogether() {
        let json = Data("""
        [{"id":"A1","name":"vps-docs","sshDestination":"me@vps","remotePath":"/srv/docs"}]
        """.utf8)
        let roots = Prefs.format(folders: ["/tmp/notes"], remotesJSON: json)
        XCTAssertEqual(roots.count, 2)
        XCTAssertEqual(roots.last, Prefs.Root(name: "vps-docs", detail: "me@vps:/srv/docs"))
    }

    func testGarbageRemotesJSONIsIgnoredRatherThanCrashing() {
        XCTAssertEqual(Prefs.format(folders: [], remotesJSON: Data("not json".utf8)), [])
        XCTAssertEqual(Prefs.format(folders: [], remotesJSON: Data("[{}]".utf8)), [])
    }

    func testEmptyIsEmpty() {
        XCTAssertEqual(Prefs.format(folders: [], remotesJSON: nil), [])
    }

    func testLinesPreservesNFDAccentedNamesAndAlignsColumns() {
        // NFD form (café as "cafe\u{0301}") has more UTF-16 code units than grapheme
        // clusters. padding(toLength:) counts UTF-16 units, causing truncation;
        // lines(for:) must preserve the full name and align columns correctly.
        let roots = [
            Prefs.Root(name: "docs", detail: "/tmp/docs"),
            Prefs.Root(name: "cafe\u{0301}", detail: "/home/user/café"),  // NFD form
            Prefs.Root(name: "x", detail: "/x"),
        ]
        let lines = Prefs.lines(for: roots)

        XCTAssertEqual(lines.count, 3)

        // The full NFD name (with accent) must appear in the output untruncated.
        // Before the fix, padding(toLength: count) on an NFD name would truncate
        // because count is grapheme clusters but padding uses UTF-16 code units.
        let cafeLineHasFullName = lines[1].prefix(10).contains("cafe\u{0301}")
        XCTAssert(cafeLineHasFullName, "NFD name with accent must be preserved: \(lines[1])")

        // All detail columns must be aligned regardless of the name width calculations.
        let detailStarts = lines.map { line -> Int in
            guard let idx = line.firstIndex(of: "/") else { return -1 }
            return line.distance(from: line.startIndex, to: idx)
        }
        XCTAssertEqual(detailStarts[0], detailStarts[1], "Detail columns aligned for docs/café")
        XCTAssertEqual(detailStarts[1], detailStarts[2], "Detail columns aligned for café/x")
    }
}
