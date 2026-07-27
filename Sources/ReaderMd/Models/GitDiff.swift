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

// MARK: - Model

/// A character range within one line that actually changed, used to shade the
/// changed words more strongly than the row. Offsets count Unicode scalars
/// (code points), NOT Swift `Character`s (grapheme clusters) or bytes — because
/// the JS renderer slices with `const chars = [...text]`, and the spread
/// operator iterates code points. `String.unicodeScalars.count` in Swift
/// equals `[...str].length` in JS; that identity is the contract. A ZWJ emoji
/// sequence or a decomposed accent is one Character but several scalars, so
/// switching this back to Character-based counting silently breaks JS-side
/// slicing on any such text. Do not revert.
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

        // ponytail: real git output ends with \n, which produces a trailing empty
        // element; drop it to avoid parsing the empty string as a context row.
        let lines = unified.components(separatedBy: "\n")
        let trimmed = lines.last == "" ? Array(lines.dropLast()) : lines
        for line in trimmed {
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

// MARK: - Word-level intra-line diff

extension GitDiff {

    /// Above this many tokens per line the O(n*m) table stops being free.
    /// ponytail: fixed cap, both sides span fully past it. Swap in a Myers diff
    /// only if someone actually reads minified single-line tables.
    private static let wordDiffTokenCap = 400

    /// Character ranges that differ between two versions of one line.
    /// Offsets count Unicode scalars — see the doc comment on `WordSpan`.
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
        s.isEmpty ? [] : [WordSpan(start: 0, length: s.unicodeScalars.count)]
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
            offset += token.unicodeScalars.count
        }
        if let start = runStart {
            out.append(WordSpan(start: start, length: offset - start))
        }
        return out
    }
}

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
        // CommonMark: a closing `#` sequence must be preceded by whitespace
        // (or be the whole remaining text, since the mandatory space after
        // the opening hashes was already trimmed above). Without that, a
        // trailing `#` is just heading text, e.g. "Intro to C#".
        let closingRun = text.reversed().prefix { $0 == "#" }.count
        if closingRun > 0 {
            let runStart = text.index(text.endIndex, offsetBy: -closingRun)
            if runStart == text.startIndex || text[text.index(before: runStart)].isWhitespace {
                text = text[..<runStart].trimmingCharacters(in: .whitespaces)
            }
        }
        return text.isEmpty ? nil : (hashes, text)
    }
}

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
        let chars = Array(path.dropFirst().dropLast())
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
