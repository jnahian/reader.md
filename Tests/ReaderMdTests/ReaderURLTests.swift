import XCTest
@testable import ReaderMd

/// The router is the app's trust boundary: these URLs can arrive from a web page,
/// not just from our CLI.
final class ReaderURLTests: XCTestCase {
    private func action(_ string: String) -> ReaderURL.Action? {
        ReaderURL.action(for: URL(string: string)!)
    }

    func testOpen() {
        XCTAssertEqual(action("readermd://open?path=/tmp/a.md"), .open("/tmp/a.md"))
    }

    func testOpenDecodesPercentEncoding() {
        XCTAssertEqual(action("readermd://open?path=/tmp/a%20%26%20b.md"), .open("/tmp/a & b.md"))
    }

    func testRemove() {
        XCTAssertEqual(action("readermd://remove?match=docs"), .remove("docs"))
    }

    func testAddRemote() {
        guard case .addRemote(let spec)? = action("readermd://add-remote?dest=me@vps&path=/srv/docs&name=docs") else {
            return XCTFail("expected an addRemote action")
        }
        XCTAssertEqual(spec.sshDestination, "me@vps")
        XCTAssertEqual(spec.remotePath, "/srv/docs")
        XCTAssertEqual(spec.name, "docs")
    }

    func testUnknownVerbsAndMissingParamsAreRejected() {
        XCTAssertNil(action("readermd://sync?path=/tmp"))
        XCTAssertNil(action("readermd://open"))
        XCTAssertNil(action("readermd://open?path="))
        XCTAssertNil(action("readermd://remove"))
        XCTAssertNil(action("readermd://add-remote?dest=me@vps"))   // no path
        XCTAssertNil(action("https://example.com/open?path=/tmp/a.md"))  // wrong scheme
    }

    /// A relative or empty remote path is nonsense and must not reach the sheet.
    func testAddRemoteRequiresAnAbsoluteRemotePath() {
        XCTAssertNil(action("readermd://add-remote?dest=me@vps&path=srv/docs&name=docs"))
    }
}
