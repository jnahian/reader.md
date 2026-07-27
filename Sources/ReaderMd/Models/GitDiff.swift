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
