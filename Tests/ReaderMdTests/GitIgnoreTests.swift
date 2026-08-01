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

    /// A folder that is itself ignored reports "./" — git's way of saying "all of
    /// this". Pruning it would blank the sidebar for a root the user explicitly
    /// added, so it must not become a key.
    func testTheScannedFolderBeingIgnoredPrunesNothing() {
        XCTAssertTrue(GitDiff.parseIgnored("./\n").isEmpty)
    }

    /// Nested paths stay nested: `scan` matches against `prefix + name`, so a key
    /// has to keep the shape git printed.
    func testNestedPathsKeepTheirShape() {
        XCTAssertEqual(GitDiff.parseIgnored("docs/build/\nn.md\n"), ["docs/build", "n.md"])
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
        // Under the temp dir on purpose: it is /var/… symlinked to /private/var/…,
        // the shape that used to make git's paths and FileManager's disagree.
        repo = fm.temporaryDirectory.appendingPathComponent("git-ignore-\(UUID().uuidString)")
        for dir in ["vendor", "docs/build"] {
            try fm.createDirectory(at: repo.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        guard case .output = GitDiff.run(["init"], in: repo) else {
            throw XCTSkip("git init failed in this environment")
        }
        try "vendor/\nskip.md\ndocs/build/\n".write(to: repo.appendingPathComponent(".gitignore"),
                                                    atomically: true, encoding: .utf8)
        for path in ["keep.md", "skip.md", "vendor/v.md", "docs/d.md", "docs/build/b.md"] {
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
        XCTAssertEqual(FileScanner.scan(repo, ignoring: ignored).map(\.name), ["docs", "keep.md"])
    }

    /// A root added *below* the repo root — the case that only had synthetic
    /// coverage. Git is run in the folder, so its paths already start there:
    /// "build", not "docs/build".
    func testARootBelowTheRepoRootPrunesItsOwnIgnores() {
        let docs = repo.appendingPathComponent("docs")
        XCTAssertEqual(FileScanner.ignoredPaths(under: docs), ["build"])
        XCTAssertEqual(FileScanner.scan(docs, ignoring: FileScanner.ignoredPaths(under: docs)).map(\.name),
                       ["d.md"])
    }

    /// A root added *at* an ignored folder still shows its files. Git answers
    /// "./" — everything — and pruning the root the user explicitly added would
    /// leave them staring at an empty sidebar with no explanation.
    func testARootAtAnIgnoredFolderStillShowsItsFiles() {
        let vendor = repo.appendingPathComponent("vendor")
        XCTAssertTrue(FileScanner.ignoredPaths(under: vendor).isEmpty)
        XCTAssertEqual(FileScanner.scan(vendor, ignoring: FileScanner.ignoredPaths(under: vendor)).map(\.name),
                       ["v.md"])
    }

    /// Git is run in the scanned folder, not the repo root, so it never walks
    /// outside it — the reason a root inside a monorepo (or under a $HOME that is
    /// itself a repo) doesn't re-enumerate the whole thing on every rescan.
    func testIgnoresOutsideTheScannedFolderAreNeverReported() {
        XCTAssertFalse(FileScanner.ignoredPaths(under: repo.appendingPathComponent("docs"))
            .contains { $0.contains("skip.md") || $0.contains("vendor") })
    }

    /// Without the probe having run, the scan must not shell out to git at all —
    /// /usr/bin/git is an xcode-select shim that can raise an install dialog.
    func testNoIgnoresAreLookedUpWhileGitIsUnavailable() {
        GitDiff.available = false
        XCTAssertTrue(FileScanner.ignoredPaths(under: repo).isEmpty)
    }

    /// A folder outside any repo answers with a git failure, which is also how
    /// "not a repo" is detected now that there's no separate `rev-parse`.
    func testAFolderOutsideAnyRepoHasNoIgnores() throws {
        let plain = FileManager.default.temporaryDirectory
            .appendingPathComponent("plain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plain) }
        XCTAssertTrue(FileScanner.ignoredPaths(under: plain).isEmpty)
    }
}
