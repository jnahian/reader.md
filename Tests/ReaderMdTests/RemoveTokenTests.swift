import XCTest
@testable import ReaderMd

/// Roots are added via `Route.absolute`, which expands `~` and calls
/// `standardizingPath` (dropping a trailing slash). `removeRoot(matching:)` must
/// normalize a CLI `rm` token the same way, or `reader rm ~/docs/` won't match a
/// root added as `reader ~/docs/`. `normalizedRemoveToken` is the shared step.
final class RemoveTokenTests: XCTestCase {
    func testTrailingSlashIsStripped() {
        XCTAssertEqual(AppState.normalizedRemoveToken("/Users/x/docs/"), "/Users/x/docs")
    }

    func testTildeIsExpanded() {
        let home = NSHomeDirectory()
        XCTAssertEqual(AppState.normalizedRemoveToken("~/docs/"), "\(home)/docs")
    }

    /// A bare name token (how remote roots are addressed) has no `~` or trailing
    /// slash to normalize, so it passes through unchanged.
    func testNameTokenPassesThroughUnchanged() {
        XCTAssertEqual(AppState.normalizedRemoveToken("vps-docs"), "vps-docs")
    }
}
