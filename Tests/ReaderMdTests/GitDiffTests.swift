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

/// Unified-diff text in, split-row model out. Pure string work — this is the
/// part of diff mode that can be tested without running the app.
final class GitDiffParseTests: XCTestCase {

    /// A `-` run followed by a `+` run pairs index-by-index into modified rows.
    private let simple = """
    diff --git a/README.md b/README.md
    index 1111111..2222222 100644
    --- a/README.md
    +++ b/README.md
    @@ -12,4 +12,5 @@
     Run the installer:
    \u{20}
    -brew install reader-md
    +brew install --cask reader-md
    +Requires macOS 13 or later.
     Then launch it.
    """

    func testHunkCountAndStarts() {
        let file = GitDiff.parse(simple)
        XCTAssertEqual(file.hunks.count, 1)
        XCTAssertEqual(file.hunks[0].oldStart, 12)
        XCTAssertEqual(file.hunks[0].newStart, 12)
    }

    func testHunkIDsAreSequential() {
        let file = GitDiff.parse(simple)
        XCTAssertEqual(file.hunks[0].id, "hunk-0")
    }

    func testRowKindsAndPairing() {
        let rows = GitDiff.parse(simple).hunks[0].rows
        XCTAssertEqual(rows.map(\.kind), [.context, .context, .modified, .added, .context])
    }

    /// A paired replacement carries both sides with their own line numbers.
    func testModifiedRowCarriesBothSides() {
        let row = GitDiff.parse(simple).hunks[0].rows[2]
        XCTAssertEqual(row.old?.lineNumber, 14)
        XCTAssertEqual(row.old?.text, "brew install reader-md")
        XCTAssertEqual(row.new?.lineNumber, 14)
        XCTAssertEqual(row.new?.text, "brew install --cask reader-md")
    }

    /// An unpaired `+` has no left-hand side at all — the cell is nil, which the
    /// renderer draws as an empty filler.
    func testAddedRowHasNoOldSide() {
        let row = GitDiff.parse(simple).hunks[0].rows[3]
        XCTAssertNil(row.old)
        XCTAssertEqual(row.new?.lineNumber, 15)
        XCTAssertEqual(row.new?.text, "Requires macOS 13 or later.")
    }

    func testCounts() {
        let file = GitDiff.parse(simple)
        XCTAssertEqual(file.additions, 2)
        XCTAssertEqual(file.deletions, 1)
    }

    func testMultipleHunks() {
        let text = """
        diff --git a/a.md b/a.md
        --- a/a.md
        +++ b/a.md
        @@ -1,2 +1,2 @@
        -one
        +ONE
         two
        @@ -40,2 +40,2 @@
        -forty
        +FORTY
         forty-one
        """
        let file = GitDiff.parse(text)
        XCTAssertEqual(file.hunks.count, 2)
        XCTAssertEqual(file.hunks.map(\.id), ["hunk-0", "hunk-1"])
        XCTAssertEqual(file.hunks[1].oldStart, 40)
    }

    /// A deletion with no replacement leaves the right-hand side empty.
    func testPureDeletion() {
        let text = """
        --- a/a.md
        +++ b/a.md
        @@ -1,3 +1,2 @@
         keep
        -gone
         keep2
        """
        let rows = GitDiff.parse(text).hunks[0].rows
        XCTAssertEqual(rows.map(\.kind), [.context, .removed, .context])
        XCTAssertNil(rows[1].new)
        XCTAssertEqual(rows[1].old?.text, "gone")
    }

    /// Three removed against one added: one pairs, two are left dangling.
    func testUnevenRunsLeaveRemainders() {
        let text = """
        --- a/a.md
        +++ b/a.md
        @@ -1,3 +1,1 @@
        -a
        -b
        -c
        +z
        """
        let rows = GitDiff.parse(text).hunks[0].rows
        XCTAssertEqual(rows.map(\.kind), [.modified, .removed, .removed])
        XCTAssertEqual(rows[0].new?.text, "z")
    }

    /// `\ No newline at end of file` is a marker, not content.
    func testNoNewlineMarkerIsIgnored() {
        let text = """
        --- a/a.md
        +++ b/a.md
        @@ -1,1 +1,1 @@
        -a
        \\ No newline at end of file
        +b
        """
        let rows = GitDiff.parse(text).hunks[0].rows
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].kind, .modified)
    }

    /// A hunk header may carry a trailing function-context string; it is not a row.
    func testHunkHeaderWithTrailingContextParses() {
        let text = """
        --- a/a.md
        +++ b/a.md
        @@ -5,2 +7,2 @@ ## Install
        -a
        +b
        """
        let file = GitDiff.parse(text)
        XCTAssertEqual(file.hunks[0].oldStart, 5)
        XCTAssertEqual(file.hunks[0].newStart, 7)
        XCTAssertEqual(file.hunks[0].rows.count, 1)
    }

    /// A single-line hunk header omits the count: `@@ -3 +3 @@`.
    func testHunkHeaderWithoutCounts() {
        let text = """
        --- a/a.md
        +++ b/a.md
        @@ -3 +3 @@
        -a
        +b
        """
        XCTAssertEqual(GitDiff.parse(text).hunks[0].oldStart, 3)
    }

    func testEmptyInputProducesEmptyFile() {
        let file = GitDiff.parse("")
        XCTAssertTrue(file.isEmpty)
        XCTAssertEqual(file.additions, 0)
    }

    /// Content lines that themselves start with +/-/@ must not be mistaken for
    /// markers — the first character is the marker, the rest is text.
    func testContentBeginningWithAMarkerCharacter() {
        let text = """
        --- a/a.md
        +++ b/a.md
        @@ -1,1 +1,1 @@
        --- old caption
        +++ new caption
        """
        let rows = GitDiff.parse(text).hunks[0].rows
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].old?.text, "-- old caption")
        XCTAssertEqual(rows[0].new?.text, "++ new caption")
    }

    /// Real `git diff` stdout always ends with a newline. The parser must not
    /// treat the trailing empty element from `components(separatedBy: "\n")` as a
    /// content row — it would create a phantom context row at the end of every hunk.
    func testTrailingNewlineDoesNotCreatePhantomRow() {
        let text = """
        --- a/a.md
        +++ b/a.md
        @@ -1,2 +1,2 @@
         keep
        -old
        +new
        """ + "\n"
        let rows = GitDiff.parse(text).hunks[0].rows
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.kind), [.context, .modified])
    }
}
