import XCTest
@testable import ReaderCLI

final class StdinDocTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StdinDocTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// The .md extension is load-bearing: without it the app will not render the
    /// file as markdown, and the CLI's local validation would reject it too.
    func testWriteCreatesAMarkdownFileWithTheContent() throws {
        let url = try StdinDoc.write(Data("# hi".utf8), now: 1_700_000_000, into: tmp)
        XCTAssertEqual(url.pathExtension, "md")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# hi")
        XCTAssertTrue(url.path.hasPrefix(tmp.path))
    }

    func testReapDeletesOldTempsAndKeepsFreshOnes() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = try StdinDoc.write(Data("old".utf8), now: 1, into: tmp)
        let fresh = try StdinDoc.write(Data("fresh".utf8), now: 2, into: tmp)

        let fm = FileManager.default
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-2 * 86400)], ofItemAtPath: old.path)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: fresh.path)

        StdinDoc.reap(in: tmp, olderThan: 86400, now: now)

        XCTAssertFalse(fm.fileExists(atPath: old.path))
        XCTAssertTrue(fm.fileExists(atPath: fresh.path))
    }

    func testReapOnAMissingDirectoryIsNotAnError() {
        StdinDoc.reap(in: tmp.appendingPathComponent("nope"), olderThan: 86400, now: Date())
    }
}
