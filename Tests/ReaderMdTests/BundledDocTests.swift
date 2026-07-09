import XCTest
@testable import ReaderMd

/// `open()` records every file it opens into recents, but the Help menu routes the
/// bundled FAQ / SHORTCUTS / CHANGELOG through that same entry point. `isBundledDoc`
/// is the guard that keeps app resources out of the user's recent-files list.
final class BundledDocTests: XCTestCase {
    func testBundledHelpDocIsRecognized() throws {
        let url = try XCTUnwrap(
            Bundle.resources.url(forResource: "FAQ", withExtension: "md", subdirectory: "docs"),
            "the FAQ should be bundled — if this fails, the resource copy broke"
        )
        XCTAssertTrue(AppState.isBundledDoc(url))
    }

    func testAUserFileIsNotABundledDoc() {
        XCTAssertFalse(AppState.isBundledDoc(URL(fileURLWithPath: "/Users/someone/notes/FAQ.md")))
    }

    /// Path traversal out of the resource root must not be treated as bundled.
    func testTraversalOutOfTheBundleIsNotABundledDoc() throws {
        let root = try XCTUnwrap(Bundle.resources.resourceURL)
        let escaped = root.appendingPathComponent("../../../Documents/FAQ.md")
        XCTAssertFalse(AppState.isBundledDoc(escaped))
    }
}
