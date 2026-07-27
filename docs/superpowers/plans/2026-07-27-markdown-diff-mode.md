# Markdown Diff Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GitHub-style side-by-side source diff mode to Reader.md, showing a markdown file's uncommitted changes against git HEAD, the index, or both.

**Architecture:** All git invocation and diff parsing live in one new pure-Swift file, `Sources/ReaderMd/Models/GitDiff.swift`, which produces a plain `DiffFile` model and is fully unit-testable against fixture strings. `AppState` gains a persisted `diffMode` / `diffScope` view mode and pushes the parsed model to `bridge.js`, which renders it as a split table. No new dependencies, no new JS libraries.

**Tech Stack:** Swift 6.2 / SwiftUI / AppKit, WKWebView + vanilla JS, XCTest, `/usr/bin/git` via `Process`.

**Spec:** `docs/superpowers/specs/2026-07-27-markdown-diff-mode-design.md`

## Global Constraints

- Deployment target is **macOS 13**. Any macOS 26-only API needs an availability guard with a pre-26 fallback. Nothing in this plan requires one.
- The app is **not sandboxed**. Direct absolute paths, no security-scoped bookmarks.
- **No new SwiftPM dependencies and no new vendored JS.** Everything here is stdlib Swift plus DOM APIs already in use.
- Every `git` invocation runs **off the main actor** and hops results back via `@MainActor`.
- `swift test` must pass after every task. Run `swift build` before claiming a task done.
- Match surrounding style: 4-space Swift indent, `///` doc comments on non-obvious declarations, `// ponytail:` comments on deliberate simplifications with their ceiling named.
- Diff colors are **CSS variables per theme**, never hardcoded hex in rules.

---

### Task 1: `GitDiff` foundation — process runner, repo discovery, scope argv

The git-facing shell of the module. No parsing yet. Establishes the exit-code contract that later tasks depend on.

**Files:**
- Create: `Sources/ReaderMd/Models/GitDiff.swift`
- Create: `Tests/ReaderMdTests/GitDiffTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum DiffScope: String, CaseIterable` with `.unstaged | .staged | .all`, properties `arguments: [String]`, `displayName: String`, `emptyMessage: String`. `enum GitOutcome { case output(String); case failure(String) }`. `GitDiff.classify(status:stdout:stderr:) -> GitOutcome`. `GitDiff.run(_ arguments: [String], in directory: URL) -> GitOutcome`. `GitDiff.repoRoot(for file: URL) -> URL?`. `GitDiff.isAvailable() -> Bool`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ReaderMdTests/GitDiffTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GitDiffScopeTests`
Expected: FAIL — compile error, `cannot find 'DiffScope' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/ReaderMd/Models/GitDiff.swift`:

```swift
import Foundation

/// Which pair of trees a diff compares. Raw values are persisted in UserDefaults.
enum DiffScope: String, CaseIterable {
    case unstaged
    case staged
    case all

    /// Argument vector after the program name. `.all` is `git diff HEAD` —
    /// everything changed since the last commit, staged or not.
    var arguments: [String] {
        switch self {
        case .unstaged: return ["diff"]
        case .staged:   return ["diff", "--cached"]
        case .all:      return ["diff", "HEAD"]
        }
    }

    var displayName: String {
        switch self {
        case .unstaged: return "Unstaged"
        case .staged:   return "Staged"
        case .all:      return "All"
        }
    }

    /// Shown in the diff pane when this scope has no changes for the open file.
    var emptyMessage: String {
        switch self {
        case .unstaged: return "No unstaged changes"
        case .staged:   return "No staged changes"
        case .all:      return "No changes since the last commit"
        }
    }
}

/// The result of one git invocation. Empty output is a legitimate success.
enum GitOutcome: Equatable {
    case output(String)
    case failure(String)
}

enum GitDiff {

    /// Git's exit codes are not uniform. `git diff` exits 0 whether or not it
    /// printed anything, while `git diff --no-index` exits 1 when the files
    /// differ — the success path for untracked files. So 0 and 1 are both
    /// output; 2 and above are real errors.
    static func classify(status: Int32, stdout: String, stderr: String) -> GitOutcome {
        guard status >= 2 else { return .output(stdout) }
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failure(trimmed.isEmpty ? "git exited with code \(status)" : trimmed)
    }

    /// Runs git synchronously. Callers must be off the main actor.
    static func run(_ arguments: [String], in directory: URL) -> GitOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return .failure("Could not launch git: \(error.localizedDescription)")
        }
        // Drain before waiting: a diff easily exceeds the 64KB pipe buffer, and
        // reading after waitUntilExit would deadlock on a large file.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return classify(status: process.terminationStatus,
                        stdout: String(decoding: outData, as: UTF8.self),
                        stderr: String(decoding: errData, as: UTF8.self))
    }

    /// The repository containing `file`, or nil if it isn't in one.
    /// Callers must be off the main actor.
    static func repoRoot(for file: URL) -> URL? {
        let dir = file.hasDirectoryPath ? file : file.deletingLastPathComponent()
        guard case .output(let path) = run(["rev-parse", "--show-toplevel"], in: dir) else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed)
    }

    /// Probed once at launch and cached by the caller. On a Mac without Command
    /// Line Tools this is the call that can raise Apple's install dialog, because
    /// /usr/bin/git is an xcode-select shim — once, at startup, and only there.
    static func isAvailable() -> Bool {
        if case .output = run(["--version"], in: URL(fileURLWithPath: "/")) { return true }
        return false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GitDiffScopeTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderMd/Models/GitDiff.swift Tests/ReaderMdTests/GitDiffTests.swift
git commit -m "feat(diff): git process runner, repo discovery, scope argv

Exit codes 0 and 1 are both output: git diff --no-index exits 1 when
files differ, which is the success path for untracked files."
```

---

### Task 2: Unified diff parsing into the split-row model

Turns `git diff` text into the `DiffFile` the web view renders. The structs are defined in full here — including `spans`, `heading`, and `headingLevel`, which this task leaves empty and later tasks fill — so no signature changes downstream.

**Files:**
- Modify: `Sources/ReaderMd/Models/GitDiff.swift` (append)
- Modify: `Tests/ReaderMdTests/GitDiffTests.swift` (append a new test class)

**Interfaces:**
- Consumes: nothing from Task 1 (parsing is independent of the runner).
- Produces: `struct WordSpan`, `struct DiffCell`, `enum DiffRowKind`, `struct DiffRow`, `struct Hunk`, `struct DiffFile`, and `GitDiff.parse(_ unified: String) -> DiffFile`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ReaderMdTests/GitDiffTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GitDiffParseTests`
Expected: FAIL — `cannot find 'GitDiff.parse' in scope`.

- [ ] **Step 3: Write the implementation**

Append to `Sources/ReaderMd/Models/GitDiff.swift`:

```swift
// MARK: - Model

/// A character range within one line that actually changed, used to shade the
/// changed words more strongly than the row. Offsets count Characters, not bytes.
struct WordSpan: Equatable {
    let start: Int
    let length: Int
}

/// One side of a split-diff row. `nil` where that side has no line at all.
struct DiffCell: Equatable {
    let lineNumber: Int
    let text: String
    var spans: [WordSpan] = []
}

enum DiffRowKind: String, Equatable {
    case context   // unchanged, shown on both sides
    case added     // right side only
    case removed   // left side only
    case modified  // a `-` paired with a `+`
}

struct DiffRow: Equatable {
    let kind: DiffRowKind
    var old: DiffCell?
    var new: DiffCell?
}

struct Hunk: Equatable, Identifiable {
    let index: Int
    let oldStart: Int
    let newStart: Int
    var rows: [DiffRow]
    /// Breadcrumb of the markdown headings this hunk sits under, e.g.
    /// "Install › Homebrew". Empty when the hunk precedes every heading.
    /// Filled by `annotateHeadings(_:newSideLines:)`; the parser leaves it blank.
    var heading: String = ""
    var headingLevel: Int = 1

    /// Element id stamped on the hunk container, and the id of its outline row.
    var id: String { "hunk-\(index)" }

    var additions: Int { rows.filter { $0.kind == .added || $0.kind == .modified }.count }
    var deletions: Int { rows.filter { $0.kind == .removed || $0.kind == .modified }.count }
}

struct DiffFile: Equatable {
    var hunks: [Hunk]
    var isEmpty: Bool { hunks.isEmpty }
    var additions: Int { hunks.reduce(0) { $0 + $1.additions } }
    var deletions: Int { hunks.reduce(0) { $0 + $1.deletions } }
}

// MARK: - Unified diff parsing

extension GitDiff {

    /// Parses `git diff` output for a single file into split rows.
    ///
    /// Runs of `-` lines followed by runs of `+` lines are paired index-by-index
    /// into `.modified` rows; whichever run is longer contributes `.removed` or
    /// `.added` remainders. That pairing is what makes a side-by-side view line up.
    static func parse(_ unified: String) -> DiffFile {
        var hunks: [Hunk] = []
        var oldLine = 0, newLine = 0
        var rows: [DiffRow] = []
        var pendingOld: [DiffCell] = [], pendingNew: [DiffCell] = []
        var current: (oldStart: Int, newStart: Int)?

        /// Flush a -/+ run into paired rows plus remainders.
        func flushRun() {
            let paired = min(pendingOld.count, pendingNew.count)
            for i in 0..<paired {
                rows.append(DiffRow(kind: .modified, old: pendingOld[i], new: pendingNew[i]))
            }
            for cell in pendingOld.dropFirst(paired) {
                rows.append(DiffRow(kind: .removed, old: cell, new: nil))
            }
            for cell in pendingNew.dropFirst(paired) {
                rows.append(DiffRow(kind: .added, old: nil, new: cell))
            }
            pendingOld.removeAll()
            pendingNew.removeAll()
        }

        func closeHunk() {
            guard let c = current else { return }
            flushRun()
            hunks.append(Hunk(index: hunks.count, oldStart: c.oldStart, newStart: c.newStart, rows: rows))
            rows.removeAll()
            current = nil
        }

        // Real git output ends with \n, which leaves a trailing empty element.
        // Without dropping it, that empty string parses as a context row and
        // every rendered hunk gains a phantom blank line at the end.
        let lines = unified.components(separatedBy: "\n")
        for line in (lines.last == "" ? Array(lines.dropLast()) : lines) {
            if line.hasPrefix("@@") {
                closeHunk()
                guard let starts = hunkStarts(line) else { continue }
                current = starts
                oldLine = starts.oldStart
                newLine = starts.newStart
                continue
            }
            guard current != nil else { continue }   // file headers before the first @@

            // "\ No newline at end of file" is a marker, not content.
            if line.hasPrefix("\\") { continue }

            let marker = line.first
            let text = line.isEmpty ? "" : String(line.dropFirst())
            switch marker {
            case "-":
                pendingOld.append(DiffCell(lineNumber: oldLine, text: text))
                oldLine += 1
            case "+":
                pendingNew.append(DiffCell(lineNumber: newLine, text: text))
                newLine += 1
            case " ", nil:
                flushRun()
                rows.append(DiffRow(kind: .context,
                                    old: DiffCell(lineNumber: oldLine, text: text),
                                    new: DiffCell(lineNumber: newLine, text: text)))
                oldLine += 1
                newLine += 1
            default:
                continue   // "diff --git", "index", "--- a/", "+++ b/" and friends
            }
        }
        closeHunk()
        return DiffFile(hunks: hunks)
    }

    /// `@@ -12,4 +12,5 @@ optional context` → (12, 12). The counts are omitted
    /// for single-line ranges (`@@ -3 +3 @@`), so only the start is read.
    private static func hunkStarts(_ header: String) -> (oldStart: Int, newStart: Int)? {
        let fields = header.split(separator: " ")
        guard fields.count >= 3 else { return nil }
        func start(_ field: Substring) -> Int? {
            Int(field.dropFirst().split(separator: ",").first ?? "")
        }
        guard let old = start(fields[1]), let new = start(fields[2]) else { return nil }
        return (old, new)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GitDiffParseTests`
Expected: PASS, 13 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderMd/Models/GitDiff.swift Tests/ReaderMdTests/GitDiffTests.swift
git commit -m "feat(diff): parse unified diff into split-row model

Runs of -/+ lines pair index-by-index into modified rows so the
side-by-side view lines up; remainders become removed/added."
```

---

### Task 3: Word-level intra-line spans

Without this, a one-word edit in a markdown paragraph paints the whole paragraph red and green — the common case for prose, and the reason split mode alone is not enough.

**Files:**
- Modify: `Sources/ReaderMd/Models/GitDiff.swift` (append)
- Modify: `Tests/ReaderMdTests/GitDiffTests.swift` (append a new test class)

**Interfaces:**
- Consumes: `WordSpan`, `DiffCell`, `DiffRow`, `DiffFile` from Task 2.
- Produces: `GitDiff.wordSpans(old:new:) -> (old: [WordSpan], new: [WordSpan])` and `GitDiff.annotateWords(_ file: DiffFile) -> DiffFile`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ReaderMdTests/GitDiffTests.swift`:

```swift
/// Word-level spans within a paired row. A markdown paragraph is one long line,
/// so line-level shading alone makes prose diffs unreadable.
final class GitDiffWordSpanTests: XCTestCase {

    private func text(_ s: String, _ spans: [WordSpan]) -> [String] {
        let chars = Array(s)
        return spans.map { String(chars[$0.start..<($0.start + $0.length)]) }
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

    /// Non-ASCII must be measured in Characters, not bytes, or spans land
    /// mid-grapheme and the renderer slices a word in half.
    func testMultibyteOffsetsCountCharacters() {
        let (_, new) = GitDiff.wordSpans(old: "café is open", new: "café is closed")
        XCTAssertEqual(text("café is closed", new), ["closed"])
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GitDiffWordSpanTests`
Expected: FAIL — `cannot find 'GitDiff.wordSpans' in scope`.

- [ ] **Step 3: Write the implementation**

Append to `Sources/ReaderMd/Models/GitDiff.swift`:

```swift
// MARK: - Word-level intra-line diff

extension GitDiff {

    /// Above this many tokens per line the O(n*m) table stops being free.
    /// ponytail: fixed cap, both sides span fully past it. Swap in a Myers diff
    /// only if someone actually reads minified single-line tables.
    private static let wordDiffTokenCap = 400

    /// Character ranges that differ between two versions of one line.
    /// Offsets count Characters so multibyte text can't split a grapheme.
    static func wordSpans(old: String, new: String) -> (old: [WordSpan], new: [WordSpan]) {
        if old == new { return ([], []) }
        let a = tokenize(old), b = tokenize(new)

        guard a.count <= wordDiffTokenCap, b.count <= wordDiffTokenCap else {
            return (fullSpan(old), fullSpan(new))
        }

        // dp[i][j] = length of the longest common token subsequence of a[i...], b[j...]
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1
                                        : max(dp[i + 1][j], dp[i][j + 1])
            }
        }

        var matchedA = Array(repeating: false, count: a.count)
        var matchedB = Array(repeating: false, count: b.count)
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                matchedA[i] = true
                matchedB[j] = true
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return (spans(a, matched: matchedA), spans(b, matched: matchedB))
    }

    /// Fills `spans` on every `.modified` row. Wholly added or removed rows are
    /// already fully shaded by their row background, so they're left alone.
    static func annotateWords(_ file: DiffFile) -> DiffFile {
        var result = file
        for h in result.hunks.indices {
            for r in result.hunks[h].rows.indices where result.hunks[h].rows[r].kind == .modified {
                guard var old = result.hunks[h].rows[r].old,
                      var new = result.hunks[h].rows[r].new else { continue }
                let (oldSpans, newSpans) = wordSpans(old: old.text, new: new.text)
                old.spans = oldSpans
                new.spans = newSpans
                result.hunks[h].rows[r].old = old
                result.hunks[h].rows[r].new = new
            }
        }
        return result
    }

    /// Runs of whitespace and runs of non-whitespace, in order. Keeping the
    /// whitespace as its own token means spans stay aligned to the original
    /// string without a separate offset table.
    private static func tokenize(_ s: String) -> [String] {
        var out: [String] = []
        var current = ""
        var currentIsSpace: Bool?
        for ch in s {
            let isSpace = ch.isWhitespace
            if currentIsSpace == nil || currentIsSpace == isSpace {
                current.append(ch)
            } else {
                out.append(current)
                current = String(ch)
            }
            currentIsSpace = isSpace
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private static func fullSpan(_ s: String) -> [WordSpan] {
        s.isEmpty ? [] : [WordSpan(start: 0, length: s.count)]
    }

    /// Merges consecutive unmatched tokens into one span each.
    private static func spans(_ tokens: [String], matched: [Bool]) -> [WordSpan] {
        var out: [WordSpan] = []
        var offset = 0
        var runStart: Int?
        for (k, token) in tokens.enumerated() {
            if matched[k] {
                if let start = runStart {
                    out.append(WordSpan(start: start, length: offset - start))
                    runStart = nil
                }
            } else if runStart == nil {
                runStart = offset
            }
            offset += token.count
        }
        if let start = runStart {
            out.append(WordSpan(start: start, length: offset - start))
        }
        return out
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GitDiffWordSpanTests`
Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderMd/Models/GitDiff.swift Tests/ReaderMdTests/GitDiffTests.swift
git commit -m "feat(diff): word-level intra-line spans via token LCS

A markdown paragraph is one long line, so line-level shading alone
makes a one-word prose edit unreadable."
```

---

### Task 4: Hunk-to-heading resolution

Supplies the outline. Each hunk is labelled by the breadcrumb of markdown headings it sits under.

**Files:**
- Modify: `Sources/ReaderMd/Models/GitDiff.swift` (append)
- Modify: `Tests/ReaderMdTests/GitDiffTests.swift` (append a new test class)

**Interfaces:**
- Consumes: `Hunk`, `DiffFile` from Task 2.
- Produces: `GitDiff.headingBreadcrumb(beforeLine:in:) -> (text: String, level: Int)` and `GitDiff.annotateHeadings(_ file: DiffFile, newSideLines: [String]) -> DiffFile`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ReaderMdTests/GitDiffTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GitDiffHeadingTests`
Expected: FAIL — `cannot find 'GitDiff.headingBreadcrumb' in scope`.

- [ ] **Step 3: Write the implementation**

Append to `Sources/ReaderMd/Models/GitDiff.swift`:

```swift
// MARK: - Hunk → heading

extension GitDiff {

    /// The breadcrumb of markdown headings in effect just above `line`
    /// (1-based), e.g. "Install › Homebrew". Empty when nothing precedes it.
    ///
    /// Fenced code is skipped: a `# comment` in a bash block is not a heading,
    /// and mislabelling one would send the outline to the wrong place.
    static func headingBreadcrumb(beforeLine line: Int, in lines: [String]) -> (text: String, level: Int) {
        var stack: [(level: Int, text: String)] = []
        var fence: String?

        for raw in lines.prefix(max(0, line - 1)) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                continue
            }
            if trimmed.hasPrefix("```") { fence = "```"; continue }
            if trimmed.hasPrefix("~~~") { fence = "~~~"; continue }

            guard let heading = atxHeading(trimmed) else { continue }
            stack.removeAll { $0.level >= heading.level }
            stack.append(heading)
        }

        guard let deepest = stack.last else { return ("", 1) }
        return (stack.map(\.text).joined(separator: " › "), deepest.level)
    }

    /// Labels every hunk with the heading it falls under, resolved against the
    /// new side's full text.
    static func annotateHeadings(_ file: DiffFile, newSideLines: [String]) -> DiffFile {
        var result = file
        for h in result.hunks.indices {
            let found = headingBreadcrumb(beforeLine: result.hunks[h].newStart, in: newSideLines)
            result.hunks[h].heading = found.text
            result.hunks[h].headingLevel = found.level
        }
        return result
    }

    /// An ATX heading of level 1...4. CommonMark requires a space after the
    /// hashes, so "#nothing" is a paragraph. Levels 5 and 6 are ignored to match
    /// the outline's existing 1...4 range.
    private static func atxHeading(_ trimmed: String) -> (level: Int, text: String)? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...4).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // CommonMark: a CLOSING hash sequence must be preceded by whitespace.
        // Stripping unconditionally would turn "## Intro to C#" into "Intro to C"
        // — silently mangling real heading text in the outline.
        let closing = text.reversed().prefix { $0 == "#" }.count
        if closing > 0, closing < text.count,
           text[text.index(text.endIndex, offsetBy: -closing - 1)].isWhitespace {
            text.removeLast(closing)
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return text.isEmpty ? nil : (hashes, text)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GitDiffHeadingTests`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderMd/Models/GitDiff.swift Tests/ReaderMdTests/GitDiffTests.swift
git commit -m "feat(diff): label each hunk with its enclosing heading

Feeds the diff-mode outline. Skips fenced code so a bash comment
is never mistaken for a heading."
```

---

### Task 5: `git status --porcelain` parsing for sidebar badges

**Files:**
- Modify: `Sources/ReaderMd/Models/GitDiff.swift` (append)
- Modify: `Tests/ReaderMdTests/GitDiffTests.swift` (append a new test class)

**Interfaces:**
- Consumes: `FileScanner.markdownExtensions` from `Sources/ReaderMd/Models/FileNode.swift`.
- Produces: `enum GitFileStatus: String` with `.modified = "M"`, `.added = "A"`, `.conflicted = "U"`, `.untracked = "?"`; `GitDiff.parseStatus(_ output: String, root: URL) -> [String: GitFileStatus]` keyed by **absolute path**; `GitDiff.status(root: URL) -> [String: GitFileStatus]`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ReaderMdTests/GitDiffTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GitStatusParseTests`
Expected: FAIL — `cannot find 'GitFileStatus' in scope`.

- [ ] **Step 3: Write the implementation**

Append to `Sources/ReaderMd/Models/GitDiff.swift`:

```swift
// MARK: - Repository status

/// The badge shown after a changed markdown file in the sidebar.
enum GitFileStatus: String, Equatable {
    case modified = "M"
    case added = "A"
    case conflicted = "U"
    case untracked = "?"
}

extension GitDiff {

    /// Markdown files with uncommitted changes, keyed by absolute path.
    /// Callers must be off the main actor.
    ///
    /// `-uall` is required: without it a newly created folder collapses to a
    /// single `docs/` entry and none of its files get badges.
    static func status(root: URL) -> [String: GitFileStatus] {
        guard case .output(let out) = run(["status", "--porcelain", "-uall"], in: root) else { return [:] }
        return parseStatus(out, root: root)
    }

    static func parseStatus(_ output: String, root: URL) -> [String: GitFileStatus] {
        var map: [String: GitFileStatus] = [:]
        for line in output.components(separatedBy: "\n") {
            guard line.count > 3 else { continue }
            let code = String(line.prefix(2))
            var path = String(line.dropFirst(3))

            // "R  old.md -> new.md" — badge the destination, that's what's on disk.
            if let arrow = path.range(of: " -> ") {
                path = String(path[arrow.upperBound...])
            }
            path = unquote(path)

            let ext = (path as NSString).pathExtension.lowercased()
            guard FileScanner.markdownExtensions.contains(ext) else { continue }

            let absolute = root.appendingPathComponent(path).standardizedFileURL.path
            map[absolute] = status(forCode: code)
        }
        return map
    }

    private static func status(forCode code: String) -> GitFileStatus {
        if code == "??" { return .untracked }
        // Any unmerged combination, per git-status(1): DD AU UD UA DU AA UU.
        if code.contains("U") || code == "DD" || code == "AA" { return .conflicted }
        if code.hasPrefix("A") { return .added }
        return .modified
    }

    /// Git wraps a path in quotes and C-escapes it when it holds a space, a
    /// quote, or non-ASCII. Escapes are decoded as BYTES and then read as UTF-8,
    /// because "\303\251" is one é, not two characters.
    private static func unquote(_ path: String) -> String {
        guard path.hasPrefix("\""), path.hasSuffix("\""), path.count >= 2 else { return path }
        var bytes: [UInt8] = []
        var chars = Array(path.dropFirst().dropLast())
        var i = 0
        while i < chars.count {
            guard chars[i] == "\\", i + 1 < chars.count else {
                bytes.append(contentsOf: Array(String(chars[i]).utf8))
                i += 1
                continue
            }
            let next = chars[i + 1]
            if let octal = octalByte(chars, at: i + 1) {
                bytes.append(octal)
                i += 4
                continue
            }
            switch next {
            case "n": bytes.append(0x0A)
            case "t": bytes.append(0x09)
            case "r": bytes.append(0x0D)
            default:  bytes.append(contentsOf: Array(String(next).utf8))
            }
            i += 2
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func octalByte(_ chars: [Character], at index: Int) -> UInt8? {
        guard index + 2 < chars.count else { return nil }
        let digits = String(chars[index...(index + 2)])
        guard digits.allSatisfy({ $0.isNumber && $0 != "8" && $0 != "9" }),
              let value = UInt8(digits, radix: 8) else { return nil }
        return value
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GitStatusParseTests`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderMd/Models/GitDiff.swift Tests/ReaderMdTests/GitDiffTests.swift
git commit -m "feat(diff): parse git status --porcelain for sidebar badges

-uall so new folders list their files; octal escapes decode as bytes
then UTF-8 so non-ASCII names key correctly."
```

---

### Task 6: The end-to-end read path — `GitDiff.diff`, JSON payload, and `AppState` wiring

Everything above becomes reachable: pick a file, compute a diff, hold it in state. Nothing renders yet.

**Files:**
- Modify: `Sources/ReaderMd/Models/GitDiff.swift` (append)
- Modify: `Sources/ReaderMd/Models/Settings.swift`
- Modify: `Sources/ReaderMd/Models/AppState.swift`
- Modify: `Tests/ReaderMdTests/GitDiffTests.swift` (append a new test class)

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: `GitDiff.diff(file:scope:repoRoot:) -> DiffFile?`, `DiffFile.jsonPayload() -> String`. On `AppState`: `@Published var diffMode: Bool`, `@Published var diffScope: DiffScope`, `@Published var diffFile: DiffFile?`, `@Published var diffAvailable: Bool`, `@Published var gitStatuses: [String: GitFileStatus]`, `@Published var diffToken: Int`, and the methods `toggleDiffMode()`, `setDiffScope(_:)`, `refreshDiff()`, `refreshGitStatus()`, `gitStatus(for path: String) -> GitFileStatus?`, `canShowDiff: Bool`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ReaderMdTests/GitDiffTests.swift`:

```swift
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

    /// A scope removed in some future version must not crash startup.
    func testUnknownScopeFallsBackToAll() {
        UserDefaults.standard.set("nonexistent", forKey: "reader.md.diffScope")
        XCTAssertEqual(Settings.loadDiffScope(), .all)
        UserDefaults.standard.removeObject(forKey: "reader.md.diffScope")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DiffPayloadTests`
Expected: FAIL — `value of type 'DiffFile' has no member 'jsonPayload'`.

- [ ] **Step 3a: Add `diff` and the JSON payload to `GitDiff.swift`**

Append to `Sources/ReaderMd/Models/GitDiff.swift`:

```swift
// MARK: - Assembling a file's diff

extension GitDiff {

    /// The parsed, annotated diff for one file, or nil when the scope has no
    /// changes for it. Callers must be off the main actor.
    static func diff(file: URL, scope: DiffScope, repoRoot: URL) -> DiffFile? {
        let relative = relativePath(of: file, under: repoRoot)
        var raw: String

        switch run(scope.arguments + ["--", relative], in: repoRoot) {
        case .failure: return nil
        case .output(let text): raw = text
        }

        // An untracked file is invisible to `git diff`, so compare it against
        // nothing and let the whole file render as added.
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard status(root: repoRoot)[file.standardizedFileURL.path] == .untracked,
                  case .output(let text) = run(["diff", "--no-index", "--", "/dev/null", relative], in: repoRoot),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            raw = text
        }

        let parsed = annotateWords(parse(raw))
        guard !parsed.isEmpty else { return nil }
        return annotateHeadings(parsed, newSideLines: newSideLines(file: file, scope: scope, repoRoot: repoRoot))
    }

    /// The post-change text the outline's headings are resolved against. For
    /// `.staged` the new side is the index, not the working tree, so it comes
    /// from `git show :path` rather than from disk.
    private static func newSideLines(file: URL, scope: DiffScope, repoRoot: URL) -> [String] {
        if scope == .staged {
            let relative = relativePath(of: file, under: repoRoot)
            if case .output(let text) = run(["show", ":\(relative)"], in: repoRoot), !text.isEmpty {
                return text.components(separatedBy: "\n")
            }
        }
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return text.components(separatedBy: "\n")
    }

    private static func relativePath(of file: URL, under root: URL) -> String {
        let filePath = file.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return filePath }
        return String(filePath.dropFirst(rootPath.count + 1))
    }
}

// MARK: - JSON payload for bridge.js

extension DiffFile {

    /// Shape consumed by `window.ReaderMd.loadDiff`. Keys are short because a
    /// large diff serializes one object per row.
    func jsonPayload() -> String {
        func cell(_ c: DiffCell?) -> Any {
            guard let c else { return NSNull() }
            return ["n": c.lineNumber,
                    "text": c.text,
                    "spans": c.spans.map { [$0.start, $0.length] }]
        }
        let payload: [String: Any] = [
            "additions": additions,
            "deletions": deletions,
            "hunks": hunks.map { h in
                [
                    "id": h.id,
                    "heading": h.heading,
                    "additions": h.additions,
                    "deletions": h.deletions,
                    "rows": h.rows.map { r in
                        ["kind": r.kind.rawValue, "old": cell(r.old), "new": cell(r.new)]
                    },
                ] as [String: Any]
            },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return "{\"hunks\":[]}" }
        return String(decoding: data, as: UTF8.self)
    }
}
```

- [ ] **Step 3b: Add the Settings keys**

In `Sources/ReaderMd/Models/Settings.swift`, add to the key block after `positionsKey`:

```swift
    private static let diffModeKey = "reader.md.diffMode"
    private static let diffScopeKey = "reader.md.diffScope"
```

And append before the closing brace of `enum Settings`:

```swift
    // Diff mode: a sticky view mode, remembered across launches like the
    // other view preferences.
    static func loadDiffMode() -> Bool {
        defaults.object(forKey: diffModeKey) as? Bool ?? false
    }
    static func saveDiffMode(_ value: Bool) {
        defaults.set(value, forKey: diffModeKey)
    }

    /// Falls back to `.all` for an absent or unrecognized value, so a scope
    /// removed in a future version can't break startup.
    static func loadDiffScope() -> DiffScope {
        DiffScope(rawValue: defaults.string(forKey: diffScopeKey) ?? "") ?? .all
    }
    static func saveDiffScope(_ value: DiffScope) {
        defaults.set(value.rawValue, forKey: diffScopeKey)
    }
```

- [ ] **Step 3c: Wire `AppState`**

In `Sources/ReaderMd/Models/AppState.swift`, add after the `exportToken` declaration:

```swift
    // Diff mode — a sticky VIEW MODE, not a one-shot, so it is persisted state
    // rather than a bump token. `diffToken` is the one-shot: it's bumped after
    // each recompute so the web view knows to push the new model.
    @Published var diffMode: Bool = false
    @Published var diffScope: DiffScope = .all
    @Published var diffFile: DiffFile?
    @Published var diffAvailable: Bool = false          // open file is inside a repo
    @Published var gitStatuses: [String: GitFileStatus] = [:]
    @Published var diffToken: Int = 0

    /// Probed once, off the main actor, because /usr/bin/git is an xcode-select
    /// shim: on a Mac with no Command Line Tools that call can raise Apple's
    /// install dialog, and it must not run on the launch path.
    @Published private(set) var gitAvailable = false

    /// Repo root per root folder. Roots may be different repos, or not repos.
    private var repoRootCache: [String: URL] = [:]
```

Add to the end of `init()`:

```swift
        diffMode = Settings.loadDiffMode()
        diffScope = Settings.loadDiffScope()
        // Probe git off the launch path, then do the first refresh once the
        // answer is in — every git call in this class is gated on it.
        Task.detached(priority: .utility) { [weak self] in
            let available = GitDiff.isAvailable()
            await MainActor.run {
                guard let self, available else { return }
                self.gitAvailable = true
                self.refreshDiff()
                self.refreshGitStatus()
            }
        }
```

Add a new `// MARK: - Diff mode` section before `// MARK: - Folder management`:

```swift
    // MARK: - Diff mode

    /// True when the diff pane should be showing instead of rendered markdown.
    /// A file with no repo renders normally even while `diffMode` is on, so
    /// opening a remote folder mid-session isn't a dead end.
    var canShowDiff: Bool { diffMode && diffAvailable }

    func toggleDiffMode() {
        diffMode.toggle()
        Settings.saveDiffMode(diffMode)
        refreshDiff()
    }

    func setDiffScope(_ scope: DiffScope) {
        guard scope != diffScope else { return }
        diffScope = scope
        Settings.saveDiffScope(scope)
        refreshDiff()
    }

    func gitStatus(for path: String) -> GitFileStatus? { gitStatuses[path] }

    /// Recomputes the open file's diff and its repo membership. Safe to call
    /// when diff mode is off — it still refreshes `diffAvailable` so the
    /// toolbar button knows whether to appear.
    func refreshDiff() {
        guard gitAvailable, let file = selectedFile else {
            diffAvailable = false
            diffFile = nil
            diffToken += 1
            return
        }
        let url = file.url
        let scope = diffScope
        let wantDiff = diffMode
        let cached = repoRootCache[url.deletingLastPathComponent().path]

        Task.detached(priority: .userInitiated) {
            let root = cached ?? GitDiff.repoRoot(for: url)
            var computed: DiffFile?
            if wantDiff, let root {
                computed = GitDiff.diff(file: url, scope: scope, repoRoot: root)
            }
            await MainActor.run { [weak self] in
                guard let self, self.selectedFile?.url == url else { return }
                if let root { self.repoRootCache[url.deletingLastPathComponent().path] = root }
                self.diffAvailable = root != nil
                self.diffFile = computed
                self.diffToken += 1
            }
        }
    }

    /// Refreshes the badge map for every root that is a git repo.
    func refreshGitStatus() {
        guard gitAvailable else { return }
        let urls = roots.map(\.url)
        Task.detached(priority: .utility) {
            var merged: [String: GitFileStatus] = [:]
            for url in urls {
                guard let root = GitDiff.repoRoot(for: url) else { continue }
                merged.merge(GitDiff.status(root: root)) { current, _ in current }
            }
            await MainActor.run { [weak self] in self?.gitStatuses = merged }
        }
    }
```

Then hook the refreshes. In `handleFolderChange()`, after `reloadToken += 1`, add:

```swift
                refreshDiff()
```

and at the end of `handleFolderChange()`, after the `if let file = selectedFile { ... }` block, add:

```swift
        refreshGitStatus()
```

- [ ] **Step 3d: Refresh on file change and on app activation**

`selectedFile` is assigned in four places, but three of them — `open(_:)`, `goBack()`, and `goForward()` — funnel through one private method. Hook that, not `open`, or navigating history with ⌘[ would leave a stale diff on screen.

In `Sources/ReaderMd/Models/AppState.swift`, add `refreshDiff()` as the final statement of `setCurrent(_ node: FileNode)`:

```swift
    private func setCurrent(_ node: FileNode) {
        selectedFile = node
        toc = []
        activeHeadingID = nil
        scrollProgress = 0
        loadMarksForCurrentFile()
        refreshDiff()
    }
```

The fourth site clears the selection rather than setting it, so `diffAvailable` has to fall back to false. Add `refreshDiff()` as the final statement of `closeFile()`, and inside `removeRoot(_:)`'s `if let file = selectedFile, ...` block after `selectedFile = nil`.

In `Sources/ReaderMd/ReaderMdApp.swift`, inside the `WindowGroup`'s content view modifiers, add:

```swift
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)) { _ in
                    // Staging a file doesn't touch the working tree, and .git is
                    // in ignoredDirs — so FSEvents never fires for it. Coming back
                    // to the window is the signal that the index may have moved.
                    state.refreshDiff()
                    state.refreshGitStatus()
                }
```

- [ ] **Step 4: Run tests and build**

Run: `swift test --filter DiffPayloadTests && swift test --filter DiffSettingsTests && swift build`
Expected: PASS, 10 tests; build succeeds with no warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderMd/Models/GitDiff.swift Sources/ReaderMd/Models/Settings.swift \
        Sources/ReaderMd/Models/AppState.swift Sources/ReaderMd/ReaderMdApp.swift \
        Tests/ReaderMdTests/GitDiffTests.swift
git commit -m "feat(diff): compute diffs off-main and hold them in AppState

Untracked files fall back to --no-index. Staged scope resolves headings
against the index via git show. Recompute on app activation because
staging never fires FSEvents."
```

---

### Task 7: Render the split table in `bridge.js` and theme it

**Files:**
- Modify: `Sources/ReaderMd/Resources/web/bridge.js`
- Modify: `Sources/ReaderMd/Resources/web/template.html`

**Interfaces:**
- Consumes: the JSON payload shape from Task 6 (`{additions, deletions, hunks: [{id, heading, additions, deletions, rows: [{kind, old, new}]}]}`, each cell `{n, text, spans: [[start, length]]}` or `null`).
- Produces: `window.ReaderMd.loadDiff(json)`, `window.ReaderMd.clearDiff()`, and a `diffMode` module flag that `reportActiveHeading` and `reportSelection` branch on.

- [ ] **Step 1: Add the diff CSS variables and rules to `template.html`**

In `Sources/ReaderMd/Resources/web/template.html`, add eight variables to each of the six theme blocks. Values are per-theme, not shared — sepia must not get neon rows.

`:root` (after `--content-width: 760px; --content-size: 16px;`):

```css
      --diff-add-bg: #e6ffec; --diff-del-bg: #ffebe9;
      --diff-add-word: #abf2bc; --diff-del-word: #ffc1c0;
      --diff-add-fg: #1a7f37; --diff-del-fg: #cf222e;
      --diff-gutter-fg: #59636e; --diff-gutter-bg: #f6f8fa;
```

`html.dark`:

```css
      --diff-add-bg: #12261e; --diff-del-bg: #25171c;
      --diff-add-word: #1f572f; --diff-del-word: #6d2129;
      --diff-add-fg: #3fb950; --diff-del-fg: #f85149;
      --diff-gutter-fg: #9198a1; --diff-gutter-bg: #151b23;
```

`html[data-theme="editorial"]` — warm, desaturated to sit on paper:

```css
      --diff-add-bg: #edf2e2; --diff-del-bg: #f8e8e0;
      --diff-add-word: #cfe0b4; --diff-del-word: #f0c9bb;
      --diff-add-fg: #4a7a2e; --diff-del-fg: #a83b2a;
      --diff-gutter-fg: #6f6558; --diff-gutter-bg: #f2eadd;
```

`html[data-theme="editorial"].dark`:

```css
      --diff-add-bg: #1e2a1c; --diff-del-bg: #2e211d;
      --diff-add-word: #35502e; --diff-del-word: #66332a;
      --diff-add-fg: #8fbf6a; --diff-del-fg: #e08070;
      --diff-gutter-fg: #a89e8d; --diff-gutter-bg: #2a2723;
```

`html[data-theme="terminal"]`:

```css
      --diff-add-bg: #eaf6ec; --diff-del-bg: #fdecea;
      --diff-add-word: #b7e2c0; --diff-del-word: #f7c3bd;
      --diff-add-fg: #0a7a33; --diff-del-fg: #c0392b;
      --diff-gutter-fg: #5a655a; --diff-gutter-bg: #f4f6f4;
```

`html[data-theme="terminal"].dark`:

```css
      --diff-add-bg: #0e1f14; --diff-del-bg: #1f1113;
      --diff-add-word: #1c4a2a; --diff-del-word: #5d2129;
      --diff-add-fg: #3fb950; --diff-del-fg: #f0645a;
      --diff-gutter-fg: #6b786b; --diff-gutter-bg: #12171b;
```

Then add these rules just before `</style>`:

```css
    /* ---- Diff mode ---- */
    .diff-hunk { margin: 0 0 22px; border: 1px solid var(--border); border-radius: 8px; overflow: hidden; }
    .diff-hunk-head {
      display: flex; align-items: baseline; gap: 10px;
      padding: 6px 12px; background: var(--diff-gutter-bg);
      border-bottom: 1px solid var(--border);
      font: 12px var(--font-mono); color: var(--diff-gutter-fg);
    }
    .diff-hunk-head .add { color: var(--diff-add-fg); }
    .diff-hunk-head .del { color: var(--diff-del-fg); }
    /* Wide content scrolls inside its own box; the page never scrolls sideways. */
    .diff-scroll { overflow-x: auto; }
    table.diff { border-collapse: collapse; width: 100%; table-layout: fixed; }
    table.diff td { vertical-align: top; padding: 0; }
    td.diff-num {
      width: 1%; min-width: 42px; text-align: right; user-select: none;
      padding: 1px 8px; background: var(--diff-gutter-bg); color: var(--diff-gutter-fg);
      font: 12px var(--font-mono); border-right: 1px solid var(--border);
    }
    td.diff-text {
      width: 49%; padding: 1px 10px; font: 12.5px/1.55 var(--font-mono);
      white-space: pre-wrap; overflow-wrap: anywhere;
    }
    tr.added   td.diff-text.new, tr.modified td.diff-text.new { background: var(--diff-add-bg); }
    tr.removed td.diff-text.old, tr.modified td.diff-text.old { background: var(--diff-del-bg); }
    tr.added   td.diff-text.old, tr.removed  td.diff-text.new { background: var(--diff-gutter-bg); }
    td.diff-text.new .w { background: var(--diff-add-word); border-radius: 2px; }
    td.diff-text.old .w { background: var(--diff-del-word); border-radius: 2px; }
    .diff-empty { padding: 60px 0; text-align: center; color: var(--blockquote); font-size: 14px; }
```

- [ ] **Step 2: Add `loadDiff` to `bridge.js`**

In `Sources/ReaderMd/Resources/web/bridge.js`, add near the top after `const contentEl = ...`:

```js
let diffMode = false;
```

Add these two methods to the `window.ReaderMd` object, right after `reloadMarkdown`:

```js
  // Diff mode replaces the rendered document wholesale. It deliberately does
  // NOT post toc/wordCount — Swift owns the outline here (one row per hunk),
  // and a word count of a diff means nothing.
  loadDiff(json) {
    diffMode = true;
    renderDiff(JSON.parse(json));
  },

  clearDiff() {
    diffMode = false;
  },
```

Add the renderer in the `// ---- Rendering ----` section, after `render()`:

```js
function renderDiff(payload) {
  window.scrollTo(0, 0);
  if (!payload.hunks || !payload.hunks.length) {
    contentEl.innerHTML = `<p class="diff-empty">${esc(payload.empty || 'No changes')}</p>`;
    return;
  }
  contentEl.innerHTML = payload.hunks.map(diffHunkHTML).join('');
  reportActiveHeading();
  reportProgress();
  post('rendered', true);
}

function diffHunkHTML(hunk) {
  const rows = hunk.rows.map(diffRowHTML).join('');
  const label = hunk.heading || 'Top of file';
  return `<section class="diff-hunk" id="${esc(hunk.id)}">
    <div class="diff-hunk-head">
      <span>${esc(label)}</span>
      <span class="add">+${hunk.additions}</span>
      <span class="del">−${hunk.deletions}</span>
    </div>
    <div class="diff-scroll"><table class="diff"><tbody>${rows}</tbody></table></div>
  </section>`;
}

function diffRowHTML(row) {
  return `<tr class="${row.kind}">${diffCellHTML(row.old, 'old')}${diffCellHTML(row.new, 'new')}</tr>`;
}

/// A null cell is a filler: the other side gained or lost a line here.
function diffCellHTML(cell, side) {
  if (!cell) return `<td class="diff-num"></td><td class="diff-text ${side}"></td>`;
  return `<td class="diff-num">${cell.n}</td>` +
         `<td class="diff-text ${side}">${spannedText(cell.text, cell.spans)}</td>`;
}

// Wraps the changed ranges in <span class="w">. Offsets count UNICODE SCALARS,
// which is exactly what the spread operator below iterates — [...text] yields
// code points, not UTF-16 units and not grapheme clusters. Swift emits scalar
// offsets for this reason (see WordSpan). Do not switch either side to
// Characters/graphemes alone: "👨‍👩‍👧" is 1 Swift Character but 5 elements here,
// and every span after such a cluster would land on the wrong text.
function spannedText(text, spans) {
  if (!spans || !spans.length) return esc(text);
  const chars = [...text];
  let out = '', cursor = 0;
  for (const [start, length] of spans) {
    out += esc(chars.slice(cursor, start).join(''));
    out += `<span class="w">${esc(chars.slice(start, start + length).join(''))}</span>`;
    cursor = start + length;
  }
  return out + esc(chars.slice(cursor).join(''));
}
```

- [ ] **Step 3: Branch the scroll-spy and gate selection**

Replace the body of `reportActiveHeading()` in `bridge.js` with:

```js
function reportActiveHeading() {
  // In diff mode the outline is hunks, not headings, so the spy scans hunk
  // containers instead. Same "topmost element above 100px" rule, same
  // activeHeading channel — AppState can't tell the difference.
  const els = diffMode
    ? [...contentEl.querySelectorAll('section.diff-hunk')]
    // Same exclusion as assignHeadingIds/postTOC/addHeadingAnchors: the footnote
    // extension's sr-only <h2> is a real h2. Without this, scrolling into the
    // footnotes posts activeHeading:"footnote-label", which matches no TOC row, so
    // the outline's active-row highlight silently vanishes.
    : [...contentEl.querySelectorAll('h1,h2,h3,h4')].filter((h) => !h.closest('section[data-footnotes]'));
  if (!els.length) return;
  let activeId = els[0].id;
  for (const el of els) {
    if (el.getBoundingClientRect().top <= 100) activeId = el.id;
    else break;
  }
  post('activeHeading', activeId);
}
```

Add as the first line inside `reportSelection()`:

```js
  // Marks anchor by character offset into the RENDERED DOM; against diff rows
  // they would resolve to the wrong text, so no selection is reported here.
  if (diffMode) return;
```

Add as the first line inside `render()` (so switching back out of diff mode clears the flag):

```js
  diffMode = false;
```

- [ ] **Step 4: Verify by hand**

Run: `swift build`
Expected: build succeeds. Nothing is visible yet — Task 8 wires the toggle. Confirm only that `bridge.js` parses by running `swift run ReaderMd`, opening any file, and checking the Web Inspector console is free of syntax errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderMd/Resources/web/bridge.js Sources/ReaderMd/Resources/web/template.html
git commit -m "feat(diff): split-table renderer and per-theme diff colors

Scroll-spy branches to hunk containers so the existing activeHeading
channel drives the outline unchanged. Selection is gated off: marks
anchor into the rendered DOM and would mis-resolve against diff rows."
```

---

### Task 8: Toolbar toggle, scope control, shortcut, quick-open command — first runnable end-to-end

After this task diff mode is usable.

**Files:**
- Modify: `Sources/ReaderMd/Views/MarkdownWebView.swift`
- Modify: `Sources/ReaderMd/Views/Toolbar.swift`
- Modify: `Sources/ReaderMd/ReaderMdApp.swift`
- Modify: `Sources/ReaderMd/Views/QuickOpenView.swift`

**Interfaces:**
- Consumes: `AppState.canShowDiff`, `diffMode`, `diffScope`, `diffFile`, `diffAvailable`, `diffToken`, `toggleDiffMode()`, `setDiffScope(_:)`, `gitStatus(for:)` from Task 6; `window.ReaderMd.loadDiff/clearDiff` from Task 7.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Branch the web view on diff mode**

In `Sources/ReaderMd/Views/MarkdownWebView.swift`, replace the load block in `updateNSView` with:

```swift
        if state.canShowDiff {
            if state.diffToken != coord.lastDiffToken || coord.loadedPath != state.selectedFile?.url.path {
                coord.loadedPath = state.selectedFile?.url.path
                coord.pushDiff(state.diffFile, empty: state.diffScope.emptyMessage)
            }
        } else if let file = state.selectedFile, file.url.path != coord.loadedPath || coord.showingDiff {
            coord.load(file: file, resume: state.savedProgress(for: file.url.path))
        } else if state.selectedFile == nil {
            coord.clear()
        } else if state.reloadToken != coord.lastReloadToken {
            coord.reloadCurrent()
        }
        coord.lastReloadToken = state.reloadToken
        coord.lastDiffToken = state.diffToken
```

Add to the `Coordinator`'s stored properties (next to `lastReloadToken`):

```swift
        var lastDiffToken = 0
        /// True while the web view is showing a diff, so leaving diff mode
        /// forces a re-render even though the path didn't change.
        var showingDiff = false
```

Add these methods to the `Coordinator`, next to `reloadCurrent()`:

```swift
        func pushDiff(_ file: DiffFile?, empty: String) {
            guard isReady else { return }
            showingDiff = true
            let json = file?.jsonPayload() ?? "{\"hunks\":[],\"empty\":\(Self.encode(empty))}"
            webView?.evaluateJavaScript("window.ReaderMd.loadDiff(\(Self.encode(json)));")
        }
```

And add as the first line of `pushCurrentFile(keepScroll:)`:

```swift
            if showingDiff {
                showingDiff = false
                webView?.evaluateJavaScript("window.ReaderMd.clearDiff();")
            }
```

Guard the marks push — add as the first line of `applyMarks(json:)`:

```swift
            guard !showingDiff else { return }
```

- [ ] **Step 2: Add the toolbar toggle and scope control**

In `Sources/ReaderMd/Views/Toolbar.swift`, add a new `ToolbarItemGroup` immediately before the `// Document actions.` group:

```swift
                // Diff: hidden entirely outside a git repo, disabled when the
                // file is tracked but unchanged.
                ToolbarItemGroup(placement: .primaryAction) {
                    if state.diffAvailable {
                        Button { state.toggleDiffMode() } label: {
                            Image(systemName: state.diffMode
                                  ? "plusminus.circle.fill" : "plusminus.circle")
                        }
                        .disabled(!state.diffMode && unchanged)
                        .dockTooltip(diffTooltip)

                        if state.canShowDiff {
                            Picker("", selection: Binding(
                                get: { state.diffScope },
                                set: { state.setDiffScope($0) }
                            )) {
                                ForEach(DiffScope.allCases, id: \.self) { scope in
                                    Text(scope.displayName).tag(scope)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 210)
                        }
                    }
                }
```

Add these computed properties next to `subtitle`:

```swift
    /// Tracked but with no uncommitted changes — nothing to diff.
    private var unchanged: Bool {
        guard let path = state.selectedFile?.url.path else { return true }
        return state.gitStatus(for: path) == nil
    }

    private var diffTooltip: String {
        if unchanged && !state.diffMode { return "No changes to show" }
        return state.diffMode ? "Show rendered view (⇧⌘D)" : "Show diff (⇧⌘D)"
    }
```

Change the word-count subtitle so it disappears in diff mode. Replace line 161's condition with:

```swift
        if state.selectedFile != nil, state.wordCount > 0, !state.canShowDiff {
```

Disable PDF export in diff mode — change the export button's modifier to:

```swift
                    .disabled(state.selectedFile == nil || state.canShowDiff)
```

- [ ] **Step 3: Add the menu command and shortcut**

In `Sources/ReaderMd/ReaderMdApp.swift`, inside `CommandGroup(after: .toolbar)`, after the "Toggle Outline" button:

```swift
                Button("Toggle Diff") { state.toggleDiffMode() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .disabled(!state.diffAvailable)
```

Also disable the "Export as PDF…" menu item in diff mode — change its modifier chain to end with:

```swift
                    .disabled(state.canShowDiff)
```

- [ ] **Step 4: Add the quick-open command**

In `Sources/ReaderMd/Views/QuickOpenView.swift`, inside `paletteCommands(_:)`, add to the conditional block that appends document-scoped commands (next to `export` and `copyPath`):

```swift
    if state.diffAvailable {
        cmds.append(PaletteCommand(id: "diff",
                                   title: state.diffMode ? "Show Rendered View" : "Show Diff",
                                   subtitle: "Document",
                                   action: { state.toggleDiffMode() }))
    }
```

- [ ] **Step 5: Verify by hand, then commit**

Run: `swift build && swift test && swift run ReaderMd`

Verify in the running app:
1. Add this repo as a folder. Open `README.md`, edit and save it in another editor — the diff button appears.
2. Press ⇧⌘D. The split table renders with red/green rows and a stronger shade on the changed words only.
3. Switch the segmented control to Staged with nothing staged — "No staged changes" appears.
4. `git add` the file in a terminal, switch back to the window — the Staged pane now shows the change without a manual reload.
5. Press ⇧⌘D again — the rendered markdown comes back, and the word count returns to the subtitle.
6. Open a file in a folder that is not a repo — the button is absent and the file renders normally.

```bash
git add Sources/ReaderMd/Views/MarkdownWebView.swift Sources/ReaderMd/Views/Toolbar.swift \
        Sources/ReaderMd/ReaderMdApp.swift Sources/ReaderMd/Views/QuickOpenView.swift
git commit -m "feat(diff): toolbar toggle, scope control, ⇧⌘D, quick-open command

Diff mode is now reachable end to end. Export and the word count go
quiet while it's on."
```

---

### Task 9: Outline becomes a hunk navigator; suppress the remaining sidecars

**Files:**
- Modify: `Sources/ReaderMd/Models/AppState.swift`
- Modify: `Sources/ReaderMd/Views/TOCView.swift`
- Modify: `Sources/ReaderMd/ContentView.swift`
- Modify: `Tests/ReaderMdTests/GitDiffTests.swift` (append a new test class)

**Interfaces:**
- Consumes: `TOCEntry` (`id`, `text`, `level`) from `AppState.swift`; `DiffFile`, `Hunk` from Task 2.
- Produces: `AppState.diffOutline(for file: DiffFile) -> [TOCEntry]` (static, so it's testable off the main actor) and `TOCEntry.detail: String?`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ReaderMdTests/GitDiffTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DiffOutlineTests`
Expected: FAIL — `type 'AppState' has no member 'diffOutline'`.

- [ ] **Step 3a: Add `detail` to `TOCEntry` and the outline builder**

First confirm no call site breaks. Run `grep -rn "TOCEntry(" Sources/` — the only construction should be in `MarkdownWebView`'s `toc` message handler. `detail` is a `var` Optional, so it gets an implicit `nil` in the memberwise init and existing labeled calls keep compiling; if the grep turns up a *positional* construction, add the file to this task's **Files:** list and update it too.

Then, in `Sources/ReaderMd/Models/AppState.swift`, replace the `TOCEntry` declaration with:

```swift
/// A heading in the currently open document, used for the outline. In diff mode
/// the same type carries one entry per hunk instead, with `detail` holding the
/// hunk's counts.
struct TOCEntry: Identifiable, Equatable {
    let id: String   // heading element id, or "hunk-N" in diff mode
    let text: String
    let level: Int   // 1...4
    var detail: String?   // "+3 −1" in diff mode, nil otherwise
}
```

Add to the `// MARK: - Diff mode` section:

```swift
    /// The outline in diff mode: one row per hunk, labelled by its enclosing
    /// heading. `id` must be the hunk's element id — TOCView taps route through
    /// `requestScroll(to:)`, and bridge.js resolves that with getElementById.
    ///
    /// nonisolated static so it can be unit-tested without the main actor.
    nonisolated static func diffOutline(for file: DiffFile) -> [TOCEntry] {
        file.hunks.map { hunk in
            TOCEntry(id: hunk.id,
                     text: hunk.heading.isEmpty ? "Top of file" : hunk.heading,
                     level: hunk.headingLevel,
                     detail: "+\(hunk.additions) −\(hunk.deletions)")
        }
    }
```

In `refreshDiff()`, inside the `await MainActor.run` block, after `self.diffFile = computed`, add:

```swift
                if wantDiff, let computed {
                    self.toc = Self.diffOutline(for: computed)
                    self.wordCount = 0        // meaningless for a diff
                } else if wantDiff {
                    self.toc = []
                    self.wordCount = 0
                }
```

- [ ] **Step 3b: Show the detail column in `TOCView`**

In `Sources/ReaderMd/Views/TOCView.swift`, inside `TOCRow`'s `HStack`, replace `Spacer(minLength: 0)` with:

```swift
            Spacer(minLength: 6)

            if let detail = entry.detail {
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 8)
            }
```

- [ ] **Step 3c: Hide the progress bar in diff mode**

In `Sources/ReaderMd/ContentView.swift`, wrap the progress-bar view (the one at line 185 using `state.scrollProgress`) in:

```swift
                    if !state.canShowDiff {
                        // ... existing progress bar view unchanged ...
                    }
```

- [ ] **Step 4: Run tests and verify by hand**

Run: `swift test --filter DiffOutlineTests && swift build && swift run ReaderMd`
Expected: PASS, 7 tests.

Verify in the running app: with a changed file open, press ⇧⌘D then ⇧⌘B. The outline lists one row per hunk with its heading and counts; clicking a row scrolls to that hunk; scrolling highlights the row for the hunk you're looking at. The progress bar is gone. Selecting text in the diff shows no mark popover.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderMd/Models/AppState.swift Sources/ReaderMd/Views/TOCView.swift \
        Sources/ReaderMd/ContentView.swift Tests/ReaderMdTests/GitDiffTests.swift
git commit -m "feat(diff): outline becomes a hunk navigator

Reuses TOCEntry with hunk-N ids so the existing scrollToHeading click
path works unchanged. Progress bar and word count go quiet."
```

---

### Task 10: Sidebar git status badges

**Files:**
- Modify: `Sources/ReaderMd/Views/FileTreeRow.swift`
- Modify: `Sources/ReaderMd/Models/AppState.swift`

**Interfaces:**
- Consumes: `AppState.gitStatus(for:)` and `refreshGitStatus()` from Task 6; `GitFileStatus` from Task 5.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Refresh the status map when roots are added**

In `Sources/ReaderMd/Models/AppState.swift`, add `refreshGitStatus()` as the final statement of `loadSavedRoots()` and of `addRoot(_:persist:)`.

- [ ] **Step 2: Draw the badge**

In `Sources/ReaderMd/Views/FileTreeRow.swift`, add these to the struct:

```swift
    /// Uncommitted-change badge, files only. Directories stay unmarked — a
    /// rolled-up count would compete with the folder chevron for the same space.
    private var badge: GitFileStatus? {
        node.isDirectory ? nil : state.gitStatus(for: node.url.path)
    }

    private func badgeColor(_ status: GitFileStatus, selected: Bool) -> Color {
        if selected { return .white }
        switch status {
        case .modified:   return .orange
        case .added:      return .green
        case .untracked:  return .secondary
        case .conflicted: return .red
        }
    }
```

In `row(icon:chevron:selected:)`, replace `Spacer(minLength: 0)` with:

```swift
            Spacer(minLength: 4)

            if let badge {
                Text(badge.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(badgeColor(badge, selected: selected))
                    .help(badgeHelp(badge))
            }
```

And add:

```swift
    private func badgeHelp(_ status: GitFileStatus) -> String {
        switch status {
        case .modified:   return "Modified"
        case .added:      return "Added"
        case .untracked:  return "Untracked"
        case .conflicted: return "Conflicted"
        }
    }
```

- [ ] **Step 3: Verify by hand**

Run: `swift build && swift run ReaderMd`

Verify in the running app:
1. With this repo added as a folder, edit a markdown file in another editor — an orange `M` appears next to it within a second (FSEvents → `handleFolderChange` → `refreshGitStatus`).
2. Create a new markdown file in a brand-new subfolder — a grey `?` appears on the file itself, not just the folder. This is what `-uall` buys.
3. `git add` it — the badge becomes a green `A` after switching away from and back to the window.
4. Add a folder that is not a git repo — no badges anywhere, no errors.
5. Add two roots, one a repo and one not — the repo's files get badges, the other's don't.

- [ ] **Step 4: Run the full suite**

Run: `swift test`
Expected: PASS, all tests including the pre-existing ones.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderMd/Views/FileTreeRow.swift Sources/ReaderMd/Models/AppState.swift
git commit -m "feat(diff): git status badges in the sidebar

Files only — a rolled-up directory count would compete with the folder
chevron for the same space."
```

---

## Conflicted files

Task 5 already maps every unmerged code to `.conflicted`. The spec calls for the diff pane to render a notice rather than git's combined-diff format, which `GitDiff.parse` does not understand. Handle it inside Task 8's Step 1 by checking the status before pushing:

```swift
        // A conflicted file's `git diff` is a combined diff (`@@@`), which the
        // parser doesn't read. Say so plainly instead of rendering nonsense.
        if state.gitStatus(for: file.url.path) == .conflicted {
            coord.pushDiff(nil, empty: "This file has unresolved merge conflicts")
        }
```

placed as the first branch inside the `state.canShowDiff` block.

## Not in this plan

Per the spec's non-goals: a `reader diff` CLI verb, arbitrary-ref comparison, two-file compare, a unified/split toggle, and a rich rendered diff.

Two deferrals beyond the spec's list, both deliberate:

- **The rename header.** The spec's edge-case table says a renamed file's header shows `old.md → new.md`. Git already detects the rename and produces a correct diff against the old path, so the *content* is right — only the label is missing. Showing it means threading a filename pair from `git diff`'s `diff --git` line through the payload into the hunk header, for a case the sidebar already badges. Add it if renames turn out to be common in practice.
- **Collapsed-context expansion** (GitHub's `⋯`). Git's default 3 lines of context are already narrow enough that there is nothing to collapse; worth adding only if the context count is ever made configurable.
