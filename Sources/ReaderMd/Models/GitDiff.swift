import Foundation

/// Which pair of trees a diff compares. Persisted in UserDefaults via `persisted`.
enum DiffScope: Hashable {
    case unstaged
    case staged
    case all
    /// The working tree against a named ref — "what this branch changed vs main".
    case ref(String)

    /// The scopes that exist in every repo, in the order the scope menu lists
    /// them. Refs are appended per repo (see `GitDiff.branches`).
    static let fixed: [DiffScope] = [.unstaged, .staged, .all]

    /// Argument vector after the program name. `.all` is `git diff HEAD` —
    /// everything changed since the last commit, staged or not.
    var arguments: [String] {
        switch self {
        case .unstaged: return ["diff"]
        case .staged:   return ["diff", "--cached"]
        case .all:      return ["diff", "HEAD"]
        // ponytail: two-dot `git diff <ref>`, so uncommitted edits count. On a
        // branch that is behind the ref this also shows the ref's own commits
        // reversed; diff against `merge-base ref HEAD` if that noise matters.
        case .ref(let r): return ["diff", r]
        }
    }

    var displayName: String {
        switch self {
        case .unstaged: return "Unstaged"
        case .staged:   return "Staged"
        case .all:      return "All"
        case .ref(let r): return "vs \(r)"
        }
    }

    /// Shown in the diff pane when this scope has no changes for the open file.
    var emptyMessage: String {
        switch self {
        case .unstaged: return "No unstaged changes"
        case .staged:   return "No staged changes"
        case .all:      return "No changes since the last commit"
        case .ref(let r): return "No changes vs \(r)"
        }
    }

    /// UserDefaults form. Not `RawRepresentable`: an enum with an associated
    /// value can't carry a `String` raw type.
    var persisted: String {
        switch self {
        case .unstaged: return "unstaged"
        case .staged:   return "staged"
        case .all:      return "all"
        case .ref(let r): return "ref:\(r)"
        }
    }

    /// Rejects a ref starting with `-`: `arguments` passes it to git before the
    /// `--` separator, where it would read as an option. Git won't create such a
    /// branch, but the persisted string is user-writable.
    init?(persisted raw: String) {
        switch raw {
        case "unstaged": self = .unstaged
        case "staged":   self = .staged
        case "all":      self = .all
        default:
            guard raw.hasPrefix("ref:") else { return nil }
            let ref = String(raw.dropFirst(4))
            guard !ref.isEmpty, !ref.hasPrefix("-") else { return nil }
            self = .ref(ref)
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

    /// A path with every symlink resolved — the namespace git answers in.
    /// `rev-parse --show-toplevel` and `status --porcelain` both report resolved
    /// paths, while the folders the user added and the URLs in the file tree are
    /// whatever they were typed or picked as. Comparing the two forms directly is
    /// the bug this exists to prevent.
    static func canonical(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Probed once at launch and cached by the caller. On a Mac without Command
    /// Line Tools this is the call that can raise Apple's install dialog, because
    /// /usr/bin/git is an xcode-select shim — once, at startup, and only there.
    static func isAvailable() -> Bool {
        if case .output = run(["--version"], in: URL(fileURLWithPath: "/")) { return true }
        return false
    }

    /// The cached answer, for callers that aren't on the main actor and so can't
    /// read `AppState.gitAvailable` — the folder scan. Written once by the launch
    /// probe, never again.
    ///
    /// `nonisolated(unsafe)` and genuinely racy: `loadSavedRoots()` runs earlier in
    /// the same `init` and starts detached scans that read this while the probe is
    /// writing it. Benign in the one direction it can go — a scan that reads a
    /// stale `false` just skips git's ignores, and the probe rescans every affected
    /// root once it lands. Do not add a second writer; this only holds because
    /// `false → true` happens once.
    nonisolated(unsafe) static var available = false
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
            // headingBreadcrumb is strictly "lines above the given line", so when
            // the hunk's first new-side line IS itself a heading (the common case
            // with git's default 3 lines of context), passing newStart unchanged
            // would resolve to that heading's PARENT. Look one line past it.
            let found = headingBreadcrumb(beforeLine: result.hunks[h].newStart + 1, in: newSideLines)
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

    /// Tooltip for the one-letter badge shown on a sidebar row.
    var help: String {
        switch self {
        case .modified:   return "Modified"
        case .added:      return "Added"
        case .untracked:  return "Untracked"
        case .conflicted: return "Conflicted"
        }
    }
}

extension GitDiff {

    /// Markdown files with uncommitted changes, keyed by absolute path.
    /// Callers must be off the main actor.
    ///
    /// `-uall` is required: without it a newly created folder collapses to a
    /// single `docs/` entry and none of its files get badges.
    ///
    /// Pass `displayedAs` the root folder the user actually added — see
    /// `pathKeyer` for why the keys have to live in that namespace.
    static func status(root: URL, displayedAs displayRoot: URL? = nil) -> [String: GitFileStatus] {
        guard case .output(let out) = run(["status", "--porcelain", "-uall"], in: root) else { return [:] }
        return parseStatus(out, root: root, displayedAs: displayRoot)
    }

    /// Porcelain paths are relative to git's own top-level, which has every
    /// symlink resolved. Badge lookups arrive in more than one namespace, so a
    /// repo reached through a symlink — anything under `/tmp`, or a folder
    /// added through a link to another volume — needs a key in each:
    ///
    /// - tree rows use `FileNode.url.path`, and the scan comes from
    ///   `contentsOfDirectory(at:)`, which hands back *resolved* URLs, exactly
    ///   as git reports them and whatever the root was added as;
    /// - Recents, Favorites and a file opened by path use the string as it was
    ///   stored or typed, which is not resolved.
    ///
    /// `/private` is a third form rather than a detail of the second:
    /// `standardizedFileURL` and `resolvingSymlinksInPath` both drop a leading
    /// `/private`, while git and `contentsOfDirectory` both keep it. So git's
    /// answer verbatim and git's answer canonicalised are different strings, and
    /// a lookup can arrive as either.
    ///
    /// Keying every form here costs a dictionary entry or two per changed file.
    /// Resolving at lookup time instead would mean a realpath syscall per
    /// visible row on every SwiftUI render pass.
    private static func pathKeyer(root: URL, displayRoot: URL?) -> (String) -> [String] {
        let literalRoot = root.path             // git's own answer: /private/tmp/notes
        let canonicalRoot = canonical(root)     // the same folder, minus /private: /tmp/notes
        // `.path` verbatim: this is the form the folder was added as, and so the
        // form a stored path is written in.
        let displayPath = displayRoot?.path
        let canonicalDisplay = displayRoot.map(canonical)

        return { relative in
            let literal = (literalRoot as NSString).appendingPathComponent(relative)
            let canonicalPath = (canonicalRoot as NSString).appendingPathComponent(relative)
            var keys = [literal]
            if canonicalPath != literal { keys.append(canonicalPath) }
            // Outside the added folder — not in the tree, so no badge needs it.
            if let displayPath, let canonicalDisplay, canonicalDisplay != displayPath,
               canonicalPath.hasPrefix(canonicalDisplay + "/") {
                keys.append(displayPath + canonicalPath.dropFirst(canonicalDisplay.count))
            }
            return keys
        }
    }

    static func parseStatus(_ output: String, root: URL,
                            displayedAs displayRoot: URL? = nil) -> [String: GitFileStatus] {
        let key = pathKeyer(root: root, displayRoot: displayRoot)
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

            for k in key(path) { map[k] = status(forCode: code) }
        }
        return map
    }

    /// Refs the diff scope menu offers, most recently committed first. Two git
    /// calls, so it is only run when diff mode is actually on.
    /// Callers must be off the main actor.
    static func branches(root: URL) -> [String] {
        guard case .output(let refs) = run(
            ["for-each-ref", "--sort=-committerdate", "--format=%(refname:short)",
             "refs/heads", "refs/remotes/origin"], in: root) else { return [] }
        var current: String?
        if case .output(let name) = run(["rev-parse", "--abbrev-ref", "HEAD"], in: root) {
            current = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return parseBranches(refs, current: current)
    }

    /// `origin/HEAD` is a symbolic alias for whatever `origin`'s default branch
    /// is, already listed under its real name; the checked-out branch is dropped
    /// because diffing the working tree against its own tip is what `.all` is.
    /// ponytail: capped at 50 — a menu, not a branch browser. The cap is silent,
    /// so it has to sit past where real repos land: `origin/*` shares the budget,
    /// and most branches have a matching remote ref, so 20 was ~10 distinct
    /// branches and a repo could hide the one you wanted with no way to reach it.
    /// A 50-row pull-down still scrolls fine.
    static func parseBranches(_ output: String, current: String?) -> [String] {
        Array(output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != current && $0 != "origin/HEAD" }
            .prefix(50))
    }

    /// The branch rows the scope popover shows for `query`. Case-insensitive
    /// substring, so "main" finds both `main` and `origin/main` — a fuzzy
    /// subsequence match would also return every branch containing those
    /// letters in order, which on a 50-ref list is noise rather than help.
    static func filterBranches(_ branches: [String], query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return branches }
        return branches.filter { $0.range(of: trimmed, options: .caseInsensitive) != nil }
    }

    /// Paths git ignores under `folder`, named relative to it. `--directory`
    /// collapses a wholly ignored directory to one entry, so the scan prunes the
    /// subtree instead of testing every file in it. Callers must be off the main
    /// actor.
    ///
    /// Run *in `folder`*, not in the repo root, for two reasons: git limits the
    /// walk to the working directory — a root added inside a monorepo, or under a
    /// `$HOME` that is itself a repo, otherwise re-enumerates the whole thing on
    /// every rescan — and it already names its output relative to that directory,
    /// so nothing has to re-base repo-relative paths onto the scanned folder.
    /// That re-basing was the one place absolute paths from the two sides could
    /// meet: `FileManager` hands the scan fully resolved URLs (`/private/var/…`)
    /// while `canonical` maps the same path the other way (`/var/…`).
    ///
    /// Empty (git exits non-zero) when `folder` isn't in a repo, so this doubles
    /// as the is-a-repo test — no separate `rev-parse`.
    static func ignoredPaths(in folder: URL) -> Set<String> {
        guard case .output(let out) = run(
            ["ls-files", "--others", "--ignored", "--exclude-standard", "--directory"], in: folder)
        else { return [] }
        return parseIgnored(out)
    }

    static func parseIgnored(_ output: String) -> Set<String> {
        var paths: Set<String> = []
        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            // Unquote first: git wraps the whole entry, trailing slash included.
            var path = unquote(line)
            if path.hasSuffix("/") { path.removeLast() }
            // "." is what a folder that is *itself* ignored reports. Pruning the
            // root the user explicitly added would blank the sidebar; `ignoredDirs`
            // doesn't do that either.
            guard !path.isEmpty, path != "." else { continue }
            paths.insert(path)
        }
        return paths
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
            case "a": bytes.append(0x07)
            case "b": bytes.append(0x08)
            case "f": bytes.append(0x0C)
            case "v": bytes.append(0x0B)
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
        // nothing and let the whole file render as added. Excluded for `.staged`:
        // an untracked file has nothing staged, so `git diff --cached` correctly
        // returning empty means "not staged" — falling back here would render
        // the whole file as added, falsely implying it is staged.
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard scope != .staged,
                  isUntracked(relative, in: repoRoot),
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

    /// True for a path git neither tracks nor ignores — exactly the case
    /// `git diff` has nothing to say about, so the caller falls back to
    /// `--no-index`. One targeted `ls-files` rather than keying the file's URL
    /// into a whole-repo `status` scan: that scan ran on every unchanged-file
    /// open, and its keys are in git's resolved namespace while the URL is not.
    /// `--exclude-standard` keeps an ignored file reading as "no changes"
    /// instead of rendering wholesale as an addition.
    static func isUntracked(_ relative: String, in repoRoot: URL) -> Bool {
        guard case .output(let text) = run(["ls-files", "--others", "--exclude-standard", "--", relative],
                                           in: repoRoot) else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Only the containing directory is resolved, never the last component: a
    /// symlinked *file* is its own entry in git's index, so resolving it would
    /// hand git the target's path and lose the file it was asked about.
    private static func relativePath(of file: URL, under root: URL) -> String {
        let filePath = canonical(file.deletingLastPathComponent()) + "/" + file.lastPathComponent
        let rootPath = canonical(root)
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
