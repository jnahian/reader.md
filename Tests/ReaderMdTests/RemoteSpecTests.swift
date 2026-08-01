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

/// What the Add Remote sheet builds from its fields. `isGit` is derived from
/// `gitURL` being present, so a leftover value from the kind that isn't showing
/// silently sends the remote down the wrong sync path.
final class AddRemoteSpecTests: XCTestCase {

    func testSwitchingToGitDropsTheSSHFields() {
        let spec = AddRemoteView.spec(id: "keep", name: " Repo ", isGit: true,
                                      gitURL: " https://x/y.git ",
                                      destination: "me@vps", remotePath: "/srv")
        XCTAssertEqual(spec.id, "keep")           // cacheURL, and so marks, survive
        XCTAssertEqual(spec.name, "Repo")         // trimmed
        XCTAssertEqual(spec.gitURL, "https://x/y.git")
        XCTAssertEqual(spec.sshDestination, "")
        XCTAssertEqual(spec.remotePath, "")
    }

    func testSwitchingToSSHDropsTheGitURL() {
        let spec = AddRemoteView.spec(id: "keep", name: "Docs", isGit: false,
                                      gitURL: "https://x/y.git",
                                      destination: " me@vps ", remotePath: " /srv ")
        XCTAssertNil(spec.gitURL)
        XCTAssertFalse(spec.isGit)
        XCTAssertEqual(spec.sshDestination, "me@vps")
        XCTAssertEqual(spec.remotePath, "/srv")
    }

    /// A new remote gets an id, because `cacheURL` is built from it — and an
    /// empty one would point at the shared `remotes/` directory.
    func testANewSpecGetsAnID() {
        let spec = AddRemoteView.spec(id: nil, name: "R", isGit: true,
                                      gitURL: "u", destination: "", remotePath: "")
        XCTAssertFalse(spec.id.isEmpty)
    }
}
