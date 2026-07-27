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
    /// Filled by `annotate(headingsFor:)`; the parser leaves it blank.
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

        for line in unified.components(separatedBy: "\n") {
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
