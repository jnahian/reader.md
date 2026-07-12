import XCTest
@testable import ReaderMd
@testable import ReaderCLI

/// `Route.url(for:)` (the CLI's hand-rolled encoder) and `ReaderURL.action(for:)`
/// (the app's decoder) are two independent implementations of one wire protocol.
/// Nothing else proves they agree — a regression in either side would silently
/// corrupt paths, and these tests exist to catch that.
final class ProtocolRoundTripTests: XCTestCase {
    /// Characters `URLComponents` treats as query delimiters (and so would corrupt
    /// an unescaped value), plus a literal `%` and an NFD-accented path — exactly
    /// what the CLI's hand-rolled encoder exists to protect.
    private let adversarialPaths = [
        "/tmp/a b.md",
        "/tmp/a&b.md",
        "/tmp/a+b.md",
        "/tmp/a=b.md",
        "/tmp/a?b.md",
        "/tmp/a%b.md",
        "/tmp/a#b.md",
        "/tmp/cafe\u{0301}/a.md",
    ]

    func testOpenRoundTrip() {
        for path in adversarialPaths {
            guard let url = Route.url(for: .open(path: path)) else {
                return XCTFail("Route.url produced nil for \(path)")
            }
            XCTAssertEqual(ReaderURL.action(for: url), .open(path), "round trip failed for \(path)")
        }
    }

    func testAddRemoteRoundTrip() {
        let dest = "me@vps"
        let path = "/srv/docs & more"
        let name = "docs?name=weird"
        guard let url = Route.url(for: .remote(dest: dest, path: path, name: name)) else {
            return XCTFail("Route.url produced nil")
        }
        guard case .addRemote(let spec)? = ReaderURL.action(for: url) else {
            return XCTFail("expected an addRemote action")
        }
        XCTAssertEqual(spec.sshDestination, dest)
        XCTAssertEqual(spec.remotePath, path)
        XCTAssertEqual(spec.name, name)
    }

    func testRemoveRoundTrip() {
        for token in ["docs", "a token with spaces", "a&b"] {
            guard let url = Route.url(for: .remove(token: token)) else {
                return XCTFail("Route.url produced nil for \(token)")
            }
            XCTAssertEqual(ReaderURL.action(for: url), .remove(token), "round trip failed for \(token)")
        }
    }
}
