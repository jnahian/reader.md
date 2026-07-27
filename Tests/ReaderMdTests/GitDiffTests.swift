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

/// Word-level spans within a paired row. A markdown paragraph is one long line,
/// so line-level shading alone makes prose diffs unreadable.
final class GitDiffWordSpanTests: XCTestCase {

    /// Slices by Unicode scalar offset, mirroring the JS renderer's `[...text]`
    /// spread (which iterates code points) rather than Swift's `Character`
    /// (grapheme cluster) view. This is what actually verifies the contract —
    /// slicing via `Array(string)` would hide the Character/scalar divergence.
    private func text(_ s: String, _ spans: [WordSpan]) -> [String] {
        let scalars = s.unicodeScalars
        return spans.map {
            let start = scalars.index(scalars.startIndex, offsetBy: $0.start)
            let end = scalars.index(start, offsetBy: $0.length)
            return String(scalars[start..<end])
        }
    }

    func testSingleWordInsertion() {
        let (old, new) = GitDiff.wordSpans(old: "brew install reader-md",
                                           new: "brew install --cask reader-md")
        XCTAssertTrue(old.isEmpty)
        XCTAssertEqual(text("brew install --cask reader-md", new), ["--cask "])
    }

    func testSingleWordDeletion() {
        let (old, new) = GitDiff.wordSpans(old: "the quick brown fox",
                                           new: "the quick fox")
        XCTAssertEqual(text("the quick brown fox", old), ["brown "])
        XCTAssertTrue(new.isEmpty)
    }

    func testSingleWordReplacement() {
        let (old, new) = GitDiff.wordSpans(old: "requires macOS 13",
                                           new: "requires macOS 14")
        XCTAssertEqual(text("requires macOS 13", old), ["13"])
        XCTAssertEqual(text("requires macOS 14", new), ["14"])
    }

    /// Nothing in common: both sides span the whole line, and the renderer's
    /// row shading already says the same thing. Still correct, not special-cased.
    func testWholeLineReplacement() {
        let (old, new) = GitDiff.wordSpans(old: "alpha", new: "beta")
        XCTAssertEqual(old, [WordSpan(start: 0, length: 5)])
        XCTAssertEqual(new, [WordSpan(start: 0, length: 4)])
    }

    func testIdenticalLinesProduceNoSpans() {
        let (old, new) = GitDiff.wordSpans(old: "same text", new: "same text")
        XCTAssertTrue(old.isEmpty)
        XCTAssertTrue(new.isEmpty)
    }

    func testEmptyOldSide() {
        let (old, new) = GitDiff.wordSpans(old: "", new: "added line")
        XCTAssertTrue(old.isEmpty)
        XCTAssertEqual(new, [WordSpan(start: 0, length: 10)])
    }

    func testEmptyNewSide() {
        let (old, new) = GitDiff.wordSpans(old: "removed line", new: "")
        XCTAssertEqual(old, [WordSpan(start: 0, length: 12)])
        XCTAssertTrue(new.isEmpty)
    }

    /// Leading indentation is a token like any other; changing it is a real change.
    func testLeadingWhitespaceChangeIsSpanned() {
        let (old, new) = GitDiff.wordSpans(old: "  indented", new: "    indented")
        XCTAssertEqual(text("  indented", old), ["  "])
        XCTAssertEqual(text("    indented", new), ["    "])
    }

    /// Non-ASCII must be measured in Unicode scalars, not bytes, or spans land
    /// mid-codepoint and the renderer slices a word in half.
    func testMultibyteOffsetsCountUnicodeScalars() {
        let (_, new) = GitDiff.wordSpans(old: "café is open", new: "café is closed")
        XCTAssertEqual(text("café is closed", new), ["closed"])
    }

    /// A ZWJ emoji sequence is one Swift `Character` but five Unicode scalars
    /// (man + ZWJ + woman + ZWJ + girl). Character-counted offsets would land
    /// four scalars short of where JS's `[...text]` spread expects them.
    func testZWJEmojiSequenceBeforeChangedWordUsesScalarOffsets() {
        let (_, new) = GitDiff.wordSpans(old: "👨‍👩‍👧 family photo is here",
                                         new: "👨‍👩‍👧 family photo is gone")
        XCTAssertEqual(text("👨‍👩‍👧 family photo is gone", new), ["gone"])
    }

    /// A decomposed accent (`e` + combining acute) is one grapheme cluster but
    /// two Unicode scalars — the same divergence as the ZWJ case, smaller.
    func testDecomposedAccentBeforeChangedWordUsesScalarOffsets() {
        let combining = "e\u{0301}"
        let (_, new) = GitDiff.wordSpans(old: "\(combining) status is old",
                                         new: "\(combining) status is new")
        XCTAssertEqual(text("\(combining) status is new", new), ["new"])
    }

    /// A line that's whitespace on both sides but a different amount of it —
    /// still a real, fully-spanned change, not an edge case that should vanish.
    func testWhitespaceOnlyLineOnBothSides() {
        let (old, new) = GitDiff.wordSpans(old: " ", new: "  ")
        XCTAssertEqual(text(" ", old), [" "])
        XCTAssertEqual(text("  ", new), ["  "])
    }

    /// A pathological single line (a minified table row, a base64 blob) would
    /// make the O(n*m) table enormous. Above the cap both sides span fully.
    func testVeryLongLinesFallBackToFullSpan() {
        let a = String(repeating: "word ", count: 500)
        let b = String(repeating: "term ", count: 500)
        let (old, new) = GitDiff.wordSpans(old: a, new: b)
        XCTAssertEqual(old, [WordSpan(start: 0, length: a.count)])
        XCTAssertEqual(new, [WordSpan(start: 0, length: b.count)])
    }

    /// Only paired rows get spans; a wholly added or removed line is already
    /// fully shaded by its row.
    func testAnnotateFillsModifiedRowsOnly() {
        let unified = """
        --- a/a.md
        +++ b/a.md
        @@ -1,3 +1,3 @@
        -requires macOS 13
        +requires macOS 14
        +brand new line
         unchanged
        """
        let file = GitDiff.annotateWords(GitDiff.parse(unified))
        let rows = file.hunks[0].rows
        XCTAssertEqual(rows[0].kind, .modified)
        XCTAssertFalse(rows[0].old?.spans.isEmpty ?? true)
        XCTAssertFalse(rows[0].new?.spans.isEmpty ?? true)
        XCTAssertEqual(rows[1].kind, .added)
        XCTAssertTrue(rows[1].new?.spans.isEmpty ?? false)
        XCTAssertEqual(rows[2].kind, .context)
        XCTAssertTrue(rows[2].new?.spans.isEmpty ?? false)
    }

    /// A wholly removed row is already fully shaded by its row background;
    /// annotateWords must leave its spans empty rather than diffing it against nothing.
    func testAnnotateLeavesRemovedRowSpansEmpty() {
        let unified = """
        --- a/a.md
        +++ b/a.md
        @@ -1,2 +1,1 @@
        -gone
         keep
        """
        let file = GitDiff.annotateWords(GitDiff.parse(unified))
        let rows = file.hunks[0].rows
        XCTAssertEqual(rows[0].kind, .removed)
        XCTAssertTrue(rows[0].old?.spans.isEmpty ?? false)
    }
}

/// The outline in diff mode is one row per hunk, labelled by the heading the
/// hunk falls under. Resolution walks the new side's lines above the hunk.
final class GitDiffHeadingTests: XCTestCase {

    private let doc = [
        "# Overview",          // line 1
        "",                    // 2
        "## Install",          // 3
        "",                    // 4
        "### Homebrew",        // 5
        "",                    // 6
        "brew install x",      // 7
        "",                    // 8
        "## Configuration",    // 9
        "",                    // 10
        "settings live here",  // 11
    ]

    func testNestedHeadingsBecomeABreadcrumb() {
        let h = GitDiff.headingBreadcrumb(beforeLine: 7, in: doc)
        XCTAssertEqual(h.text, "Overview › Install › Homebrew")
        XCTAssertEqual(h.level, 3)
    }

    /// A sibling heading pops the deeper ones off the stack.
    func testSiblingHeadingPopsDeeperLevels() {
        let h = GitDiff.headingBreadcrumb(beforeLine: 11, in: doc)
        XCTAssertEqual(h.text, "Overview › Configuration")
        XCTAssertEqual(h.level, 2)
    }

    func testHeadingLineItselfResolvesToItsParent() {
        let h = GitDiff.headingBreadcrumb(beforeLine: 3, in: doc)
        XCTAssertEqual(h.text, "Overview")
    }

    func testBeforeAnyHeadingIsEmpty() {
        let h = GitDiff.headingBreadcrumb(beforeLine: 1, in: ["intro text", "# Later"])
        XCTAssertEqual(h.text, "")
        XCTAssertEqual(h.level, 1)
    }

    /// `#` inside a fenced code block is a shell comment, not a heading.
    func testHashInsideFencedCodeIsNotAHeading() {
        let lines = ["# Real", "", "```bash", "# not a heading", "```", "", "body"]
        let h = GitDiff.headingBreadcrumb(beforeLine: 7, in: lines)
        XCTAssertEqual(h.text, "Real")
    }

    /// Tilde fences are equally valid in CommonMark.
    func testHashInsideTildeFenceIsNotAHeading() {
        let lines = ["# Real", "~~~", "# not a heading", "~~~", "body"]
        XCTAssertEqual(GitDiff.headingBreadcrumb(beforeLine: 5, in: lines).text, "Real")
    }

    /// A `#` with no space is not an ATX heading in CommonMark.
    func testHashWithoutSpaceIsNotAHeading() {
        XCTAssertEqual(GitDiff.headingBreadcrumb(beforeLine: 3, in: ["#nothing", "", "body"]).text, "")
    }

    func testTrailingHashesAreStripped() {
        XCTAssertEqual(GitDiff.headingBreadcrumb(beforeLine: 2, in: ["## Install ##", "body"]).text, "Install")
    }

    /// Levels 5 and 6 are ignored, matching the outline's 1...4 range.
    func testDeepHeadingsAreIgnored() {
        let lines = ["## Install", "##### Tiny", "body"]
        XCTAssertEqual(GitDiff.headingBreadcrumb(beforeLine: 3, in: lines).text, "Install")
    }

    func testAnnotateFillsEveryHunk() {
        let unified = """
        --- a/a.md
        +++ b/a.md
        @@ -7,1 +7,1 @@
        -brew install x
        +brew install y
        @@ -11,1 +11,1 @@
        -settings live here
        +settings live there
        """
        let file = GitDiff.annotateHeadings(GitDiff.parse(unified), newSideLines: doc)
        XCTAssertEqual(file.hunks[0].heading, "Overview › Install › Homebrew")
        XCTAssertEqual(file.hunks[0].headingLevel, 3)
        XCTAssertEqual(file.hunks[1].heading, "Overview › Configuration")
    }
}
