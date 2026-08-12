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
        XCTAssertEqual(DiffScope.ref("main").arguments, ["diff", "main"])
    }

    /// Order matters — it's the order the scope menu offers them in.
    func testScopeOrder() {
        XCTAssertEqual(DiffScope.fixed, [.unstaged, .staged, .all])
    }

    func testEveryScopeHasDistinctCopy() {
        let names = Set(DiffScope.fixed.map(\.displayName))
        let messages = Set(DiffScope.fixed.map(\.emptyMessage))
        XCTAssertEqual(names.count, 3)
        XCTAssertEqual(messages.count, 3)
    }

    /// A ref scope names its ref everywhere the user sees it, or the menu shows
    /// three identical rows once a repo has branches.
    func testRefScopeCopyNamesTheRef() {
        XCTAssertEqual(DiffScope.ref("origin/main").displayName, "vs origin/main")
        XCTAssertEqual(DiffScope.ref("origin/main").emptyMessage, "No changes vs origin/main")
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

    /// CommonMark: a closing `#` sequence must be preceded by whitespace.
    /// "## Install ##" has a space before the trailing hashes, so it's a
    /// real closing sequence and gets stripped.
    func testClosingSequencePrecededByWhitespaceIsStripped() {
        XCTAssertEqual(GitDiff.headingBreadcrumb(beforeLine: 2, in: ["## Install ##", "body"]).text, "Install")
    }

    /// CommonMark: without whitespace before it, a trailing `#` run is not a
    /// closing sequence — it's just part of the heading text.
    func testHashWithNoPrecedingWhitespaceIsKeptAsHeadingText() {
        XCTAssertEqual(GitDiff.headingBreadcrumb(beforeLine: 2, in: ["## Intro to C#", "body"]).text, "Intro to C#")
    }

    /// CommonMark: only the whitespace-preceded run at the very end is a
    /// closing sequence; a `#` glued to preceding text is real content.
    func testOnlyTheWhitespacePrecededRunIsStripped() {
        XCTAssertEqual(GitDiff.headingBreadcrumb(beforeLine: 2, in: ["## C# ###", "body"]).text, "C#")
    }

    /// CommonMark: a heading whose text is entirely a closing sequence
    /// strips to empty text, which is not a heading.
    func testAllHashesStripsToEmptyAndIsNotAHeading() {
        XCTAssertEqual(GitDiff.headingBreadcrumb(beforeLine: 2, in: ["## ##", "body"]).text, "")
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

    /// The common case with git's default 3 lines of context: a hunk's first
    /// new-side line (`newStart`) IS a heading line. `headingBreadcrumb` is
    /// strictly "lines above", so the hunk must be labelled with THAT heading,
    /// not its parent — `annotateHeadings` has to look one line past `newStart`.
    func testAnnotateHeadingsWhenHunkStartsOnAHeadingLine() {
        let unified = """
        --- a/a.md
        +++ b/a.md
        @@ -3,1 +3,1 @@
        -## Install
        +## Install
        """
        let file = GitDiff.annotateHeadings(GitDiff.parse(unified), newSideLines: doc)
        XCTAssertEqual(file.hunks[0].heading, "Overview › Install")
    }
}

/// Porcelain paths are repo-root-relative, and git quotes plus C-escapes them
/// when they contain spaces or non-ASCII. The map is keyed by absolute path so
/// FileNode's URLs match without per-lookup conversion.
final class GitStatusParseTests: XCTestCase {

    private let root = URL(fileURLWithPath: "/repo")

    func testStatusLetters() {
        let out = """
         M docs/a.md
        A  docs/b.md
        ?? docs/c.md
        UU docs/d.md
        """
        let map = GitDiff.parseStatus(out, root: root)
        XCTAssertEqual(map["/repo/docs/a.md"], .modified)
        XCTAssertEqual(map["/repo/docs/b.md"], .added)
        XCTAssertEqual(map["/repo/docs/c.md"], .untracked)
        XCTAssertEqual(map["/repo/docs/d.md"], .conflicted)
    }

    /// Any unmerged combination counts as conflicted, not just UU.
    func testUnmergedCombinationsAreConflicted() {
        let map = GitDiff.parseStatus("AU a.md\nUD b.md\nDD c.md\nAA d.md", root: root)
        XCTAssertEqual(map["/repo/a.md"], .conflicted)
        XCTAssertEqual(map["/repo/b.md"], .conflicted)
        XCTAssertEqual(map["/repo/c.md"], .conflicted)
        XCTAssertEqual(map["/repo/d.md"], .conflicted)
    }

    /// Non-markdown files never get a badge; the sidebar doesn't show them.
    func testNonMarkdownIsFilteredOut() {
        let map = GitDiff.parseStatus(" M src/main.swift\n M docs/a.md", root: root)
        XCTAssertNil(map["/repo/src/main.swift"])
        XCTAssertEqual(map.count, 1)
    }

    func testEveryMarkdownExtensionIsKept() {
        let out = " M a.md\n M b.markdown\n M c.mdown\n M d.mdx"
        XCTAssertEqual(GitDiff.parseStatus(out, root: root).count, 4)
    }

    /// A path with a space arrives quoted.
    func testQuotedPathWithSpace() {
        let map = GitDiff.parseStatus("?? \"docs/my notes.md\"", root: root)
        XCTAssertEqual(map["/repo/docs/my notes.md"], .untracked)
    }

    /// Non-ASCII arrives as octal byte escapes inside the quotes.
    func testOctalEscapedPathDecodesToUTF8() {
        // "café.md" — é is C3 A9 → \303\251
        let map = GitDiff.parseStatus("?? \"caf\\303\\251.md\"", root: root)
        XCTAssertEqual(map["/repo/café.md"], .untracked)
    }

    func testBackslashEscapesDecode() {
        let map = GitDiff.parseStatus("?? \"a\\\"b.md\"", root: root)
        XCTAssertEqual(map["/repo/a\"b.md"], .untracked)
    }

    /// `\\` inside a quoted path is an escaped backslash, decoding to one literal `\`.
    func testEscapedBackslashDecodes() {
        let map = GitDiff.parseStatus("?? \"a\\\\b.md\"", root: root)
        XCTAssertEqual(map["/repo/a\\b.md"], .untracked)
    }

    /// git's C-quoting (quote.c) also emits \a \b \f \v for control characters,
    /// not just \n \t \r. Undecoded, these left the literal letters a/b/f/v in
    /// the path, so it never matched and the file got no sidebar badge.
    func testControlCharacterEscapesDecode() {
        let map = GitDiff.parseStatus("?? \"bell\\a.md\"", root: root)
        XCTAssertEqual(map["/repo/bell\u{07}.md"], .untracked)
    }

    /// A rename badges the destination — that's the file the sidebar shows.
    func testRenameUsesTheNewPath() {
        let map = GitDiff.parseStatus("R  old.md -> new.md", root: root)
        XCTAssertEqual(map["/repo/new.md"], .modified)
        XCTAssertNil(map["/repo/old.md"])
    }

    func testBlankAndShortLinesAreIgnored() {
        let map = GitDiff.parseStatus("\n M a.md\n\nxx\n", root: root)
        XCTAssertEqual(map.count, 1)
    }

    /// `-uall` is what makes this possible: without it a new folder collapses
    /// to a single "docs/" entry and its files get no badges at all.
    func testUallListsIndividualFilesInANewFolder() {
        let map = GitDiff.parseStatus("?? docs/new/a.md\n?? docs/new/b.md", root: root)
        XCTAssertEqual(map.count, 2)
        XCTAssertEqual(map["/repo/docs/new/b.md"], .untracked)
    }
}

/// The payload handed to bridge.js. Shape is a contract with loadDiff().
final class DiffPayloadTests: XCTestCase {

    private let unified = """
    --- a/a.md
    +++ b/a.md
    @@ -1,2 +1,2 @@
    -requires macOS 13
    +requires macOS 14
     unchanged
    """

    private func payload() throws -> [String: Any] {
        let file = GitDiff.annotateHeadings(
            GitDiff.annotateWords(GitDiff.parse(unified)),
            newSideLines: ["## Install", "unchanged"])
        let data = Data(file.jsonPayload().utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTopLevelCounts() throws {
        let json = try payload()
        XCTAssertEqual(json["additions"] as? Int, 1)
        XCTAssertEqual(json["deletions"] as? Int, 1)
    }

    func testHunkCarriesIDHeadingAndCounts() throws {
        let hunks = try XCTUnwrap(try payload()["hunks"] as? [[String: Any]])
        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks[0]["id"] as? String, "hunk-0")
        XCTAssertEqual(hunks[0]["heading"] as? String, "Install")
        XCTAssertEqual(hunks[0]["additions"] as? Int, 1)
    }

    func testRowCarriesKindAndBothCells() throws {
        let hunks = try XCTUnwrap(try payload()["hunks"] as? [[String: Any]])
        let rows = try XCTUnwrap(hunks[0]["rows"] as? [[String: Any]])
        XCTAssertEqual(rows[0]["kind"] as? String, "modified")
        let new = try XCTUnwrap(rows[0]["new"] as? [String: Any])
        XCTAssertEqual(new["n"] as? Int, 1)
        XCTAssertEqual(new["text"] as? String, "requires macOS 14")
        let spans = try XCTUnwrap(new["spans"] as? [[Int]])
        XCTAssertEqual(spans, [[15, 2]])
    }

    /// An absent side is JSON null, which the renderer draws as a filler cell.
    func testAbsentSideIsNull() throws {
        let file = GitDiff.parse("--- a/a.md\n+++ b/a.md\n@@ -1,1 +1,2 @@\n keep\n+added")
        let data = Data(file.jsonPayload().utf8)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hunks = try XCTUnwrap(json["hunks"] as? [[String: Any]])
        let rows = try XCTUnwrap(hunks[0]["rows"] as? [[String: Any]])
        XCTAssertTrue(rows[1]["old"] is NSNull)
    }

    /// The payload is embedded in an evaluateJavaScript string literal, so any
    /// character that could close it early must survive a round trip.
    func testTextWithQuotesAndBackslashesSurvives() throws {
        let file = GitDiff.parse("--- a/a.md\n+++ b/a.md\n@@ -1,1 +1,1 @@\n+say \"hi\\\" now")
        let data = Data(file.jsonPayload().utf8)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hunks = try XCTUnwrap(json["hunks"] as? [[String: Any]])
        let rows = try XCTUnwrap(hunks[0]["rows"] as? [[String: Any]])
        let new = try XCTUnwrap(rows[0]["new"] as? [String: Any])
        XCTAssertEqual(new["text"] as? String, "say \"hi\\\" now")
    }
}

/// The untracked-file `--no-index` fallback in `GitDiff.diff` must only fire
/// for `.unstaged`/`.all` — for `.staged`, an untracked file has nothing
/// staged, so the fallback would falsely render the whole file as staged.
/// Needs a real repo, so this shells out to git like `GitDiff` itself does.
final class GitDiffUntrackedFallbackTests: XCTestCase {
    private var repo: URL!

    override func setUpWithError() throws {
        repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("git-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        guard case .output = GitDiff.run(["init"], in: repo) else {
            throw XCTSkip("git init failed in this environment")
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repo)
    }

    func testStagedScopeReportsNoDiffForAnUntrackedFile() throws {
        let file = repo.appendingPathComponent("new.md")
        try "# New".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertNil(GitDiff.diff(file: file, scope: .staged, repoRoot: repo))
    }

    /// Unstaged/all are the scopes the fallback exists for — untouched by the fix.
    func testUnstagedScopeStillRendersAnUntrackedFileAsAdded() throws {
        let file = repo.appendingPathComponent("new.md")
        try "# New".write(to: file, atomically: true, encoding: .utf8)

        let diff = try XCTUnwrap(GitDiff.diff(file: file, scope: .unstaged, repoRoot: repo))
        XCTAssertGreaterThan(diff.additions, 0)
    }
}

/// Diffing against a branch, against a real repo: `parseBranches` and the scope's
/// argument vector can both be right while `for-each-ref`'s format string or the
/// `git diff <ref> -- <path>` invocation is wrong.
final class GitDiffRefScopeTests: XCTestCase {
    private var repo: URL!
    private var base: String!   // whatever git named the first branch

    override func setUpWithError() throws {
        let fm = FileManager.default
        repo = fm.temporaryDirectory.appendingPathComponent("git-ref-\(UUID().uuidString)")
        try fm.createDirectory(at: repo, withIntermediateDirectories: true)
        guard case .output = GitDiff.run(["init"], in: repo) else {
            throw XCTSkip("git init failed in this environment")
        }
        try "# One\n".write(to: repo.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        commit("one")
        // Not hardcoded "main": the default branch name is a git config setting.
        guard case .output(let name) = GitDiff.run(["rev-parse", "--abbrev-ref", "HEAD"], in: repo) else {
            throw XCTSkip("could not read the default branch name")
        }
        base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = GitDiff.run(["checkout", "-b", "feature"], in: repo)
        try "# One\n\nsecond line\n".write(to: repo.appendingPathComponent("a.md"),
                                           atomically: true, encoding: .utf8)
        commit("two")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repo)
    }

    private func commit(_ message: String) {
        _ = GitDiff.run(["add", "-A"], in: repo)
        _ = GitDiff.run(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", message], in: repo)
    }

    /// `.all` sees nothing — the change is committed — while the branch scope
    /// does, which is the whole point of the scope.
    func testRefScopeSeesWhatTheBranchChanged() throws {
        XCTAssertNil(GitDiff.diff(file: repo.appendingPathComponent("a.md"), scope: .all, repoRoot: repo))

        let diff = try XCTUnwrap(GitDiff.diff(file: repo.appendingPathComponent("a.md"),
                                              scope: .ref(base), repoRoot: repo))
        XCTAssertGreaterThan(diff.additions, 0)
    }

    /// Uncommitted edits count too — the scope diffs the working tree, not HEAD.
    func testRefScopeIncludesUncommittedEdits() throws {
        try "# One\n\nsecond line\nthird line\n".write(to: repo.appendingPathComponent("a.md"),
                                                       atomically: true, encoding: .utf8)
        let diff = try XCTUnwrap(GitDiff.diff(file: repo.appendingPathComponent("a.md"),
                                              scope: .ref(base), repoRoot: repo))
        XCTAssertGreaterThan(diff.additions, 1)
    }

    /// The menu's list comes from `for-each-ref`; a wrong format string yields
    /// nothing, and no parse test would notice.
    func testBranchesListsTheOtherBranchButNotTheCurrentOne() {
        let branches = GitDiff.branches(root: repo)
        XCTAssertTrue(branches.contains(base), "\(branches)")
        XCTAssertFalse(branches.contains("feature"), "\(branches)")
    }
}

/// A repo reached through a symlinked path — the shape of anything under /tmp
/// on macOS. `git rev-parse --show-toplevel` answers with every symlink already
/// resolved, while the open file and the sidebar are named the way the user
/// added them. The two namespaces have to be reconciled explicitly; nothing
/// does it for free.
final class GitDiffSymlinkedRepoTests: XCTestCase {
    private var base: URL!
    private var real: URL!
    private var link: URL!

    override func setUpWithError() throws {
        let fm = FileManager.default
        base = fm.temporaryDirectory.appendingPathComponent("git-symlink-\(UUID().uuidString)")
        real = base.appendingPathComponent("real")
        link = base.appendingPathComponent("link")
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        guard case .output = GitDiff.run(["init"], in: real) else {
            throw XCTSkip("git init failed in this environment")
        }
        try fm.createSymbolicLink(at: link, withDestinationURL: real)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func commit(_ file: URL, _ text: String) throws {
        try text.write(to: file, atomically: true, encoding: .utf8)
        _ = GitDiff.run(["add", "-A"], in: real)
        _ = GitDiff.run(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "x"], in: real)
    }

    /// The untracked check used to key the open file's URL into a `git status`
    /// map built in git's resolved namespace. The two never matched, so the
    /// `--no-index` fallback never fired and the pane read "no changes".
    func testUntrackedFileThroughASymlinkedPathStillDiffs() throws {
        // `.all` is `git diff HEAD`, so the repo needs a commit to have a HEAD.
        try commit(link.appendingPathComponent("seed.md"), "# Seed\n")
        let file = link.appendingPathComponent("note.md")
        try "# Hello\n\nbody\n".write(to: file, atomically: true, encoding: .utf8)
        let root = try XCTUnwrap(GitDiff.repoRoot(for: file))

        let diff = try XCTUnwrap(GitDiff.diff(file: file, scope: .all, repoRoot: root))
        XCTAssertGreaterThan(diff.additions, 0)
    }

    /// A tracked edit already worked, because git resolves an absolute pathspec
    /// itself. Pinned so making `relativePath` symlink-aware can't regress it.
    func testTrackedEditThroughASymlinkedPathStillDiffs() throws {
        let file = link.appendingPathComponent("note.md")
        try commit(file, "# Hello\n\nbody\n")
        try "# Hello\n\nBODY\n".write(to: file, atomically: true, encoding: .utf8)
        let root = try XCTUnwrap(GitDiff.repoRoot(for: file))

        let diff = try XCTUnwrap(GitDiff.diff(file: file, scope: .all, repoRoot: root))
        XCTAssertEqual(diff.deletions, 1)
    }

    /// Recents, Favorites and a file opened by path look the badge up under the
    /// folder as it was added — unresolved — so the map has to be keyed there
    /// as well as under git's top-level.
    func testStatusIsKeyedUnderTheFolderTheUserAdded() throws {
        let file = link.appendingPathComponent("note.md")
        try "# Hello\n".write(to: file, atomically: true, encoding: .utf8)
        let root = try XCTUnwrap(GitDiff.repoRoot(for: file))

        let map = GitDiff.status(root: root, displayedAs: link)
        XCTAssertEqual(map[file.path], .untracked)
    }

    /// And keyed under git's resolved top-level too. `contentsOfDirectory(at:)`
    /// hands back resolved URLs, so every row of the scanned tree below a root
    /// with a symlinked ancestor — `/tmp/notes`, a home folder that is a link —
    /// already holds the resolved path. Keying only the added-as form lost every
    /// badge in the sidebar, which is the one place they are meant to show.
    func testStatusIsAlsoKeyedUnderGitsResolvedTopLevel() throws {
        let file = link.appendingPathComponent("note.md")
        try "# Hello\n".write(to: file, atomically: true, encoding: .utf8)
        let root = try XCTUnwrap(GitDiff.repoRoot(for: file))

        let resolved = root.appendingPathComponent("note.md").path
        XCTAssertNotEqual(resolved, file.path, "the symlink fixture no longer resolves")
        XCTAssertEqual(GitDiff.status(root: root, displayedAs: link)[resolved], .untracked)
    }

    /// Without a display root the keys stay in git's namespace — the identity
    /// case every non-symlinked repo takes.
    func testAbsentDisplayRootKeepsGitsOwnNamespace() throws {
        let file = real.appendingPathComponent("note.md")
        try "# Hello\n".write(to: file, atomically: true, encoding: .utf8)
        let root = try XCTUnwrap(GitDiff.repoRoot(for: file))

        XCTAssertEqual(GitDiff.status(root: root)[file.standardizedFileURL.path], .untracked)
    }
}

final class DiffSettingsTests: XCTestCase {
    private var savedMode = false
    private var savedScope: DiffScope = .all

    /// These tests share the app's real UserDefaults — the same pattern as
    /// ReadingPositionTests. Put the user's own choices back afterwards, or
    /// running `swift test` silently flips their diff preference.
    override func setUp() async throws {
        savedMode = Settings.loadDiffMode()
        savedScope = Settings.loadDiffScope()
    }

    override func tearDown() async throws {
        Settings.saveDiffMode(savedMode)
        Settings.saveDiffScope(savedScope)
    }

    func testDiffModeDefaultsOff() {
        UserDefaults.standard.removeObject(forKey: "reader.md.diffMode")
        XCTAssertFalse(Settings.loadDiffMode())
    }

    func testDiffModeRoundTrips() {
        Settings.saveDiffMode(true)
        XCTAssertTrue(Settings.loadDiffMode())
        Settings.saveDiffMode(false)
        XCTAssertFalse(Settings.loadDiffMode())
    }

    func testDiffScopeDefaultsToAll() {
        UserDefaults.standard.removeObject(forKey: "reader.md.diffScope")
        XCTAssertEqual(Settings.loadDiffScope(), .all)
    }

    func testDiffScopeRoundTrips() {
        Settings.saveDiffScope(.staged)
        XCTAssertEqual(Settings.loadDiffScope(), .staged)
    }

    /// The ref has to survive a relaunch, not just the enum case.
    func testRefScopeRoundTrips() {
        Settings.saveDiffScope(.ref("origin/main"))
        XCTAssertEqual(Settings.loadDiffScope(), .ref("origin/main"))
    }

    /// A scope removed in some future version must not crash startup.
    func testUnknownScopeFallsBackToAll() {
        UserDefaults.standard.set("nonexistent", forKey: "reader.md.diffScope")
        XCTAssertEqual(Settings.loadDiffScope(), .all)
        UserDefaults.standard.removeObject(forKey: "reader.md.diffScope")
    }

    /// `arguments` hands the ref to git ahead of the `--` separator, so a ref
    /// starting with a dash would be read as an option. Git won't create one,
    /// but the defaults plist is user-writable.
    func testRefStartingWithADashIsRejected() {
        XCTAssertNil(DiffScope(persisted: "ref:--exec=rm"))
        XCTAssertNil(DiffScope(persisted: "ref:"))
    }
}

/// The scope menu is a Picker: a selection with no matching tag renders blank,
/// so the list has to contain whatever is selected.
final class DiffScopeChoiceTests: XCTestCase {

    func testBranchesFollowTheFixedScopes() {
        XCTAssertEqual(AppState.scopeChoices(branches: ["main", "dev"], selected: .all),
                       [.unstaged, .staged, .all, .ref("main"), .ref("dev")])
    }

    func testSelectedRefTheRepoNoLongerOffersIsKept() {
        let choices = AppState.scopeChoices(branches: ["main"], selected: .ref("gone"))
        XCTAssertEqual(choices.last, .ref("gone"))
    }

    func testSelectedRefIsNotListedTwice() {
        let choices = AppState.scopeChoices(branches: ["main"], selected: .ref("main"))
        XCTAssertEqual(choices.filter { $0 == .ref("main") }.count, 1)
    }
}

/// Refs offered by the scope menu.
final class GitBranchListTests: XCTestCase {

    func testDropsTheCheckedOutBranchAndOriginHEAD() {
        let out = "main\ndev\norigin/HEAD\norigin/main\n"
        XCTAssertEqual(GitDiff.parseBranches(out, current: "main"), ["dev", "origin/main"])
    }

    /// A detached HEAD reports "HEAD" as the current branch, which matches no ref.
    func testDetachedHeadKeepsEveryBranch() {
        XCTAssertEqual(GitDiff.parseBranches("main\ndev\n", current: "HEAD"), ["main", "dev"])
    }

    func testEmptyOutputYieldsNoBranches() {
        XCTAssertTrue(GitDiff.parseBranches("", current: nil).isEmpty)
    }

    /// The cap is silent — a branch past it is simply absent from the menu with no
    /// way to reach it — so it has to sit past where real repos land. Local and
    /// `origin/*` refs share the budget, and most branches have both.
    func testTheCapLeavesRoomForBothLocalAndRemoteRefs() {
        let many = (0..<40).flatMap { ["b\($0)", "origin/b\($0)"] }.joined(separator: "\n")
        let branches = GitDiff.parseBranches(many, current: nil)
        XCTAssertEqual(branches.count, 50)
        // 25 distinct branches survive, not 10.
        XCTAssertTrue(branches.contains("b24"), "\(branches.suffix(4))")
    }
}

/// The scope popover's branch filter. The list it narrows is capped at 50, so a
/// filter that drops the branch you typed is the difference between reaching a
/// ref and not.
final class GitBranchFilterTests: XCTestCase {
    private let branches = ["main", "origin/main", "feature/Login", "dev"]

    func testEmptyQueryKeepsEveryBranchInOrder() {
        XCTAssertEqual(GitDiff.filterBranches(branches, query: ""), branches)
        XCTAssertEqual(GitDiff.filterBranches(branches, query: "   "), branches)
    }

    /// Substring, not prefix: typing "main" has to reach `origin/main` too.
    func testMatchesAnywhereInTheRefName() {
        XCTAssertEqual(GitDiff.filterBranches(branches, query: "main"), ["main", "origin/main"])
    }

    func testMatchIsCaseInsensitive() {
        XCTAssertEqual(GitDiff.filterBranches(branches, query: "login"), ["feature/Login"])
        XCTAssertEqual(GitDiff.filterBranches(branches, query: "MAIN"), ["main", "origin/main"])
    }

    /// Typed mid-word, a slash still matches — branch names are full of them.
    func testMatchesOnASlash() {
        XCTAssertEqual(GitDiff.filterBranches(branches, query: "e/L"), ["feature/Login"])
    }

    func testNoMatchesYieldsAnEmptyList() {
        XCTAssertTrue(GitDiff.filterBranches(branches, query: "zzz").isEmpty)
    }
}

/// In diff mode the outline lists hunks, not headings. The ids must match the
/// element ids bridge.js stamps, or clicking a row scrolls nowhere.
final class DiffOutlineTests: XCTestCase {

    private func file() -> DiffFile {
        let unified = """
        --- a/a.md
        +++ b/a.md
        @@ -7,1 +7,1 @@
        -brew install x
        +brew install y
        @@ -11,2 +11,1 @@
        -one
        -two
        """
        let doc = ["# Overview", "", "## Install", "", "### Homebrew", "",
                   "brew install y", "", "## Configuration", "", "one"]
        return GitDiff.annotateHeadings(GitDiff.parse(unified), newSideLines: doc)
    }

    func testOneEntryPerHunk() {
        XCTAssertEqual(AppState.diffOutline(for: file()).count, 2)
    }

    /// The id is the contract with bridge.js: scrollToHeading is getElementById.
    func testEntryIDsMatchHunkElementIDs() {
        XCTAssertEqual(AppState.diffOutline(for: file()).map(\.id), ["hunk-0", "hunk-1"])
    }

    func testEntryTextIsTheHeadingBreadcrumb() {
        XCTAssertEqual(AppState.diffOutline(for: file())[0].text, "Overview › Install › Homebrew")
    }

    func testEntryLevelMatchesHeadingDepth() {
        let entries = AppState.diffOutline(for: file())
        XCTAssertEqual(entries[0].level, 3)
        XCTAssertEqual(entries[1].level, 2)
    }

    func testDetailCarriesTheCounts() {
        let entries = AppState.diffOutline(for: file())
        XCTAssertEqual(entries[0].detail, "+1 −1")
        XCTAssertEqual(entries[1].detail, "+0 −2")
    }

    /// A hunk above every heading still needs a readable label.
    func testHunkWithNoHeadingGetsAFallbackLabel() {
        let f = GitDiff.parse("--- a/a.md\n+++ b/a.md\n@@ -1,1 +1,1 @@\n-a\n+b")
        XCTAssertEqual(AppState.diffOutline(for: f)[0].text, "Top of file")
    }

    func testEmptyDiffProducesNoEntries() {
        XCTAssertTrue(AppState.diffOutline(for: DiffFile(hunks: [])).isEmpty)
    }
}
