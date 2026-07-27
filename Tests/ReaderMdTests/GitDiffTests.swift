import XCTest
@testable import ReaderMd

/// Git's exit codes are not uniform: `git diff --no-index` exits 1 when the files
/// DIFFER, which is the success path for untracked files. Treating any nonzero
/// status as failure would silently drop every new file from diff mode.
final class GitDiffScopeTests: XCTestCase {

    func testScopeArguments() {
        XCTAssertEqual(DiffScope.unstaged.arguments, ["diff"])
        XCTAssertEqual(DiffScope.staged.arguments, ["diff", "--cached"])
        XCTAssertEqual(DiffScope.all.arguments, ["diff", "HEAD"])
    }

    /// Order matters — it's the order the segmented control offers them in.
    func testScopeOrder() {
        XCTAssertEqual(DiffScope.allCases, [.unstaged, .staged, .all])
    }

    func testEveryScopeHasDistinctCopy() {
        let names = Set(DiffScope.allCases.map(\.displayName))
        let messages = Set(DiffScope.allCases.map(\.emptyMessage))
        XCTAssertEqual(names.count, 3)
        XCTAssertEqual(messages.count, 3)
    }

    func testExitZeroIsOutputEvenWhenEmpty() {
        guard case .output(let s) = GitDiff.classify(status: 0, stdout: "", stderr: "") else {
            return XCTFail("exit 0 must be output")
        }
        XCTAssertEqual(s, "")
    }

    /// The --no-index case. Exit 1 means "the files differ", not "something broke".
    func testExitOneIsOutputNotFailure() {
        guard case .output(let s) = GitDiff.classify(status: 1, stdout: "diff --git a/x b/x\n", stderr: "") else {
            return XCTFail("exit 1 must be output")
        }
        XCTAssertEqual(s, "diff --git a/x b/x\n")
    }

    func testExitTwoIsFailureAndCarriesStderr() {
        guard case .failure(let m) = GitDiff.classify(status: 2, stdout: "", stderr: "fatal: bad revision\n") else {
            return XCTFail("exit 2 must be failure")
        }
        XCTAssertTrue(m.contains("fatal: bad revision"))
    }

    func testFailureWithEmptyStderrStillReportsTheCode() {
        guard case .failure(let m) = GitDiff.classify(status: 128, stdout: "", stderr: "") else {
            return XCTFail("exit 128 must be failure")
        }
        XCTAssertTrue(m.contains("128"))
    }
}
