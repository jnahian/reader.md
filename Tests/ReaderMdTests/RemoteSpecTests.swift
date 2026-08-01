import XCTest
@testable import ReaderMd

final class RemoteSpecTests: XCTestCase {
    func testCacheURLIsStableForSameID() {
        let a = RemoteSpec(id: "abc", name: "One", sshDestination: "u@h", remotePath: "/srv")
        let b = RemoteSpec(id: "abc", name: "Renamed", sshDestination: "x@y", remotePath: "/other")
        XCTAssertEqual(a.cacheURL, b.cacheURL, "cacheURL must depend only on id")
    }

    func testCacheURLContainsRemotesAndID() {
        let s = RemoteSpec(id: "xyz", name: "N", sshDestination: "u@h", remotePath: "/srv")
        XCTAssertTrue(s.cacheURL.path.hasSuffix("Reader.md/remotes/xyz"), s.cacheURL.path)
    }

    func testCodableRoundTrip() throws {
        let s = RemoteSpec(id: "id1", name: "Docs", sshDestination: "me@vps", remotePath: "/srv/docs")
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(RemoteSpec.self, from: data)
        XCTAssertEqual(s, back)
    }

    func testGitSpecRoundTrips() throws {
        let s = RemoteSpec(id: "id2", name: "Repo", gitURL: "https://example.com/docs.git")
        let back = try JSONDecoder().decode(RemoteSpec.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(s, back)
        XCTAssertTrue(back.isGit)
    }

    /// Specs saved before git remotes existed have no `gitURL` key. If decoding
    /// one threw, the whole saved array would fail and every remote would vanish
    /// on upgrade — which is why the field is optional.
    func testSpecSavedBeforeGitRemotesStillDecodes() throws {
        let json = Data(#"{"id":"old","name":"Docs","sshDestination":"me@vps","remotePath":"/srv"}"#.utf8)
        let back = try JSONDecoder().decode(RemoteSpec.self, from: json)
        XCTAssertFalse(back.isGit)
        XCTAssertEqual(back.sshDestination, "me@vps")
    }
}
