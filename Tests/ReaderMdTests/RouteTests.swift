import XCTest
@testable import ReaderMd
@testable import ReaderCLI

/// The CLI's whole risk surface is turning argv into a URL: path resolution and
/// percent-encoding. Both are pure, so both are pinned here.
final class RouteTests: XCTestCase {
    private let cwd = "/Users/x/proj"

    // MARK: - parse

    func testNoArgsIsUsage() {
        XCTAssertEqual(Route.parse([], cwd: cwd), .usage)
    }

    func testRelativePathResolvesAgainstCwd() {
        XCTAssertEqual(Route.parse(["notes.md"], cwd: cwd), .open(path: "/Users/x/proj/notes.md"))
    }

    func testDotResolvesToCwd() {
        XCTAssertEqual(Route.parse(["."], cwd: cwd), .open(path: "/Users/x/proj"))
    }

    func testAbsolutePathIsKept() {
        XCTAssertEqual(Route.parse(["/tmp/a.md"], cwd: cwd), .open(path: "/tmp/a.md"))
    }

    func testTrailingSlashIsStripped() {
        XCTAssertEqual(Route.parse(["/tmp/docs/"], cwd: cwd), .open(path: "/tmp/docs"))
    }

    func testTildeIsExpanded() {
        let home = NSHomeDirectory()
        XCTAssertEqual(Route.parse(["~/docs"], cwd: cwd), .open(path: "\(home)/docs"))
    }

    func testListAndStdinAndRemove() {
        XCTAssertEqual(Route.parse(["ls"], cwd: cwd), .list)
        XCTAssertEqual(Route.parse(["-"], cwd: cwd), .stdin)
        XCTAssertEqual(Route.parse(["rm", "docs"], cwd: cwd), .remove(token: "docs"))
    }

    func testRmWithoutTokenIsUsage() {
        XCTAssertEqual(Route.parse(["rm"], cwd: cwd), .usage)
    }

    func testRemoteParsesDestinationAndPathAndDerivesName() {
        XCTAssertEqual(
            Route.parse(["remote", "me@vps:/srv/docs"], cwd: cwd),
            .remote(dest: "me@vps", path: "/srv/docs", name: "docs")
        )
    }

    func testMalformedRemotesAreUsage() {
        // No colon, no user@, and a relative remote path are all unusable.
        XCTAssertEqual(Route.parse(["remote", "me@vps"], cwd: cwd), .usage)
        XCTAssertEqual(Route.parse(["remote", "vps:/srv/docs"], cwd: cwd), .usage)
        XCTAssertEqual(Route.parse(["remote", "me@vps:srv/docs"], cwd: cwd), .usage)
        XCTAssertEqual(Route.parse(["remote"], cwd: cwd), .usage)
    }

    func testUnknownFlagIsUsage() {
        XCTAssertEqual(Route.parse(["--wat"], cwd: cwd), .usage)
    }

    // MARK: - url

    func testOpenURL() {
        XCTAssertEqual(
            Route.url(for: .open(path: "/tmp/a.md"))?.absoluteString,
            "readermd://open?path=/tmp/a.md"
        )
    }

    /// The reason we hand-encode: URLComponents leaves `&`, `=`, `?`, and `+` alone inside a
    /// query value (they are legal query delimiters), which would truncate the path.
    func testAmpersandAndSpaceInPathAreEncoded() {
        let url = Route.url(for: .open(path: "/tmp/a & b/n +1?test=value.md"))
        XCTAssertEqual(
            url?.absoluteString,
            "readermd://open?path=/tmp/a%20%26%20b/n%20%2B1%3Ftest%3Dvalue.md"
        )
        // And it round-trips back to the original path.
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first(where: { $0.name == "path" })?.value, "/tmp/a & b/n +1?test=value.md")
    }

    func testRemoteURL() {
        let url = Route.url(for: .remote(dest: "me@vps", path: "/srv/docs", name: "docs"))
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(url?.host, "add-remote")
        XCTAssertEqual(items.first(where: { $0.name == "dest" })?.value, "me@vps")
        XCTAssertEqual(items.first(where: { $0.name == "path" })?.value, "/srv/docs")
        XCTAssertEqual(items.first(where: { $0.name == "name" })?.value, "docs")
    }

    func testRemoveURL() {
        XCTAssertEqual(
            Route.url(for: .remove(token: "docs"))?.absoluteString,
            "readermd://remove?match=docs"
        )
    }

    func testCommandsWithNoURL() {
        XCTAssertNil(Route.url(for: .list))
        XCTAssertNil(Route.url(for: .usage))
        XCTAssertNil(Route.url(for: .stdin))   // resolved to .open once the temp file exists
    }

    // MARK: - markdown extensions

    /// `Route.markdownExtensions` (what the CLI accepts) and `FileScanner.markdownExtensions`
    /// (what the app renders) are independently declared. If they drift, the CLI could reject
    /// a file the app would happily open, or vice versa.
    func testMarkdownExtensionsAgreeWithTheApp() {
        XCTAssertEqual(Route.markdownExtensions, FileScanner.markdownExtensions)
    }
}
