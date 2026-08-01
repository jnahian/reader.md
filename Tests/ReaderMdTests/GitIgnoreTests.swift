import XCTest
@testable import ReaderMd

/// `git ls-files --others --ignored --exclude-standard --directory` output, as
/// consumed by the folder scan.
final class GitIgnoreParseTests: XCTestCase {

    func testFilesAndDirectoriesBothSurvive() {
        XCTAssertEqual(GitDiff.parseIgnored("skip.md\nvendor/\n"), ["skip.md", "vendor"])
    }

    /// The trailing slash marks a directory; it must not survive into the key,
    /// or it matches no entry and the subtree is never pruned.
    func testDirectoryEntriesLoseTheirTrailingSlash() {
        XCTAssertEqual(GitDiff.parseIgnored("build/\n"), ["build"])
    }

    /// Git C-quotes a path with a space, exactly as it does in `status --porcelain`.
    func testQuotedPathIsDecoded() {
        XCTAssertEqual(GitDiff.parseIgnored("\"my notes/\"\n"), ["my notes"])
    }

    func testNoIgnoresYieldsAnEmptySet() {
        XCTAssertTrue(GitDiff.parseIgnored("").isEmpty)
    }

    /// A root added below the repo root: git's paths are relative to the repo,
    /// the scan's are relative to the folder, and everything outside that folder
    /// is none of its business.
    func testPathsAreRebasedOntoTheScannedFolder() {
        XCTAssertEqual(GitDiff.parseIgnored("docs/build/\nsrc/x.md\ndocs/n.md\n", prefix: "docs/"),
                       ["build", "n.md"])
    }

    func testTheScannedFolderItselfIsNotAnEntry() {
        XCTAssertTrue(GitDiff.parseIgnored("docs\n", prefix: "docs/").isEmpty)
    }

    func testPrefixIsEmptyAtTheRepoRoot() {
        let repo = URL(fileURLWithPath: "/repo")
        XCTAssertEqual(GitDiff.relativePrefix(of: repo, under: repo), "")
        XCTAssertEqual(GitDiff.relativePrefix(of: repo.appendingPathComponent("docs"), under: repo), "docs/")
    }
}

/// The scan prunes what it is handed, whether or not git is around.
final class ScanIgnoringTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-ignore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("vendor"),
                                                withIntermediateDirectories: true)
        try "a".write(to: dir.appendingPathComponent("keep.md"), atomically: true, encoding: .utf8)
        try "b".write(to: dir.appendingPathComponent("skip.md"), atomically: true, encoding: .utf8)
        try "c".write(to: dir.appendingPathComponent("vendor/v.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testAnIgnoredFileIsLeftOut() {
        XCTAssertEqual(FileScanner.scan(dir, ignoring: ["skip.md"]).map(\.name), ["vendor", "keep.md"])
    }

    /// One entry prunes the whole subtree — that's what `--directory` buys.
    func testAnIgnoredDirectoryTakesItsChildrenWithIt() {
        XCTAssertEqual(FileScanner.scan(dir, ignoring: ["vendor"]).map(\.name), ["keep.md", "skip.md"])
    }

    /// Entries match by path, not by basename: "v.md" names no top-level entry,
    /// so `vendor/v.md` — and with it `vendor` — has to survive.
    func testMatchingIsByPathNotByName() {
        XCTAssertEqual(FileScanner.scan(dir, ignoring: ["v.md"]).map(\.name),
                       ["vendor", "keep.md", "skip.md"])
        XCTAssertEqual(FileScanner.scan(dir, ignoring: ["vendor/v.md"]).map(\.name),
                       ["keep.md", "skip.md"])
    }

    func testNothingIgnoredKeepsEverything() {
        XCTAssertEqual(FileScanner.scan(dir).map(\.name), ["vendor", "keep.md", "skip.md"])
    }
}

/// End to end against a real repo: the flag combination is the part that can
/// silently be wrong, and no parse test would catch it.
final class GitIgnoreRepoTests: XCTestCase {
    private var repo: URL!
    private var wasAvailable = false

    override func setUpWithError() throws {
        let fm = FileManager.default
        repo = fm.temporaryDirectory.appendingPathComponent("git-ignore-\(UUID().uuidString)")
        try fm.createDirectory(at: repo.appendingPathComponent("vendor"), withIntermediateDirectories: true)
        guard case .output = GitDiff.run(["init"], in: repo) else {
            throw XCTSkip("git init failed in this environment")
        }
        try "vendor/\nskip.md\n".write(to: repo.appendingPathComponent(".gitignore"),
                                       atomically: true, encoding: .utf8)
        for path in ["keep.md", "skip.md", "vendor/v.md"] {
            try "x".write(to: repo.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        wasAvailable = GitDiff.available
        GitDiff.available = true
    }

    override func tearDownWithError() throws {
        GitDiff.available = wasAvailable
        try? FileManager.default.removeItem(at: repo)
    }

    func testIgnoredMarkdownStaysOutOfTheTree() {
        let ignored = FileScanner.ignoredPaths(under: repo)
        XCTAssertEqual(FileScanner.scan(repo, ignoring: ignored).map(\.name), ["keep.md"])
    }

    /// Without the probe having run, the scan must not shell out to git at all —
    /// /usr/bin/git is an xcode-select shim that can raise an install dialog.
    func testNoIgnoresAreLookedUpWhileGitIsUnavailable() {
        GitDiff.available = false
        XCTAssertTrue(FileScanner.ignoredPaths(under: repo).isEmpty)
    }
}
