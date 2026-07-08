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
}
