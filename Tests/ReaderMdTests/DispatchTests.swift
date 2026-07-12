import XCTest
@testable import ReaderCLI

final class DispatchTests: XCTestCase {
    func testExecutableInsideAppBundleResolvesToTheApp() {
        let exe = URL(fileURLWithPath: "/Applications/Reader.md.app/Contents/MacOS/reader")
        XCTAssertEqual(
            Dispatch.appBundle(forExecutable: exe)?.path,
            "/Applications/Reader.md.app"
        )
    }

    /// Dev builds live in .build/debug — there is no bundle to find, and the caller
    /// must fall back rather than guess.
    func testExecutableOutsideAnyBundleResolvesToNil() {
        let exe = URL(fileURLWithPath: "/Users/x/proj/.build/debug/reader")
        XCTAssertNil(Dispatch.appBundle(forExecutable: exe))
    }

    /// Two levels up must actually be an .app — not merely any directory.
    func testNonAppAncestorResolvesToNil() {
        let exe = URL(fileURLWithPath: "/opt/homebrew/Cellar/x/Contents/MacOS/reader")
        XCTAssertNil(Dispatch.appBundle(forExecutable: exe))
    }

    func testShallowPathDoesNotCrash() {
        XCTAssertNil(Dispatch.appBundle(forExecutable: URL(fileURLWithPath: "/reader")))
    }
}
