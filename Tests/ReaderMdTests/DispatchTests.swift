import XCTest
@testable import ReaderCLI

final class DispatchTests: XCTestCase {
    private var tempDirToRemove: URL?

    override func tearDown() {
        if let dir = tempDirToRemove {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirToRemove = nil
        super.tearDown()
    }

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

    /// An .app two levels up is not enough — the intermediate directories must
    /// literally be named Contents/MacOS, or this isn't the layout we assume.
    func testAppAncestorWithWrongIntermediateDirsResolvesToNil() {
        let exe = URL(fileURLWithPath: "/x/Foo.app/WrongDir/AlsoWrong/reader")
        XCTAssertNil(Dispatch.appBundle(forExecutable: exe))
    }

    // MARK: - selfExecutable

    /// Regression test for the Critical bug: when argv0 is the bare word "reader"
    /// (what the shell passes when invoked via a Homebrew PATH symlink), the bundle
    /// executable URL must win rather than resolving "reader" against the cwd.
    func testSelfExecutablePrefersBundleExecutableOverGarbageArgv0() {
        let bundleExe = URL(fileURLWithPath: "/Applications/Reader.md.app/Contents/MacOS/reader")
        let resolved = Dispatch.selfExecutable(bundleExecutable: bundleExe, argv0: "reader")
        XCTAssertEqual(resolved.path, "/Applications/Reader.md.app/Contents/MacOS/reader")
    }

    func testSelfExecutableFallsBackToArgv0WhenBundleExecutableIsNil() {
        let resolved = Dispatch.selfExecutable(
            bundleExecutable: nil,
            argv0: "/Users/x/proj/.build/debug/reader"
        )
        XCTAssertEqual(resolved.path, "/Users/x/proj/.build/debug/reader")
    }

    func testSelfExecutableResolvesSymlinks() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("DispatchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        tempDirToRemove = tmp

        let real = tmp.appendingPathComponent("real-reader")
        try Data().write(to: real)
        let link = tmp.appendingPathComponent("reader")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let resolved = Dispatch.selfExecutable(bundleExecutable: link, argv0: "unused")
        XCTAssertEqual(resolved.path, real.resolvingSymlinksInPath().path)
    }
}
