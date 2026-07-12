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
}
