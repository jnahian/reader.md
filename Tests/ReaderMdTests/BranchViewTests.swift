import XCTest
import CryptoKit
@testable import ReaderMd

/// The pure parts of branch view (#110): what a saved view may hold, where an
/// extraction lives, and how a path moves between trees.
final class BranchViewTests: XCTestCase {
    private let sha1 = String(repeating: "a", count: 40)

    func testAViewWithAFullShaIsValid() {
        XCTAssertTrue(BranchView(ref: "feature/x", sha: sha1).isValid)
        XCTAssertTrue(BranchView(ref: "origin/main", sha: String(repeating: "0", count: 64)).isValid)
    }

    /// The saved form is user-writable: a ref that reads as an option, or a sha
    /// that could climb out of the cache folder, must not restore.
    func testAViewThatCouldMisleadGitOrThePathIsInvalid() {
        XCTAssertFalse(BranchView(ref: "-x", sha: sha1).isValid)
        XCTAssertFalse(BranchView(ref: "", sha: sha1).isValid)
        XCTAssertFalse(BranchView(ref: "main", sha: "abc123").isValid)
        XCTAssertFalse(BranchView(ref: "main", sha: "../" + String(repeating: "a", count: 37)).isValid)
    }

    func testTreeishNamesTheRootsSubtree() {
        XCTAssertEqual(BranchCache.treeish(sha: "abc", prefix: ""), "abc:")
        XCTAssertEqual(BranchCache.treeish(sha: "abc", prefix: "docs/"), "abc:docs")
        XCTAssertEqual(BranchCache.treeish(sha: "abc", prefix: "a/b/"), "abc:a/b")
    }

    /// Two roots in one repository extract different trees, so they never share
    /// a folder.
    func testEachRootGetsItsOwnFolder() {
        let base = URL(fileURLWithPath: "/cache")
        XCTAssertNotEqual(BranchCache.folder(forRoot: "/repo/docs", in: base),
                          BranchCache.folder(forRoot: "/repo/guides", in: base))
        XCTAssertEqual(BranchCache.tree(forRoot: "/repo/docs", sha: "abc", in: base).lastPathComponent, "abc")
    }

    func testContainsOnlyPathsInsideTheCache() {
        let base = URL(fileURLWithPath: "/cache/branches")
        XCTAssertTrue(BranchCache.contains(URL(fileURLWithPath: "/cache/branches/k/abc/a.md"), in: base))
        XCTAssertFalse(BranchCache.contains(URL(fileURLWithPath: "/cache/branchesX/a.md"), in: base))
        XCTAssertFalse(BranchCache.contains(URL(fileURLWithPath: "/repo/a.md"), in: base))
    }

    func testRemapMovesAPathToTheSamePlaceInTheOtherTree() {
        let old = URL(fileURLWithPath: "/repo/docs")
        let new = URL(fileURLWithPath: "/cache/k/abc")
        XCTAssertEqual(BranchCache.remap("/repo/docs/guides/a.md", from: old, to: new), "/cache/k/abc/guides/a.md")
        XCTAssertEqual(BranchCache.remap("/cache/k/abc/a.md", from: new, to: old), "/repo/docs/a.md")
    }

    /// A sibling whose name only starts with the root's is not inside it.
    func testRemapLeavesPathsOutsideTheTreeAlone() {
        let old = URL(fileURLWithPath: "/repo/docs")
        let new = URL(fileURLWithPath: "/cache/k/abc")
        XCTAssertNil(BranchCache.remap("/repo/docs-old/a.md", from: old, to: new))
        XCTAssertNil(BranchCache.remap("/elsewhere/a.md", from: old, to: new))
    }

    func testPruneKeepsTheViewedCommitAndAnyExtractionInProgress() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("prune-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let folder = BranchCache.folder(forRoot: "r", in: base)
        for name in ["keep", "old", "new.partial-1"] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(name),
                                                    withIntermediateDirectories: true)
        }
        BranchCache.prune(root: "r", keeping: "keep", in: base)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)),
                       ["keep", "new.partial-1"])
    }

    func testPruningEverythingRemovesTheRootsFolder() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("prune-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let folder = BranchCache.folder(forRoot: "r", in: base)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("abc"),
                                                withIntermediateDirectories: true)
        BranchCache.prune(root: "r", keeping: nil, in: base)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    /// The branch picker lists the checked-out branch too; only `origin/HEAD`,
    /// an alias, goes.
    func testBranchListWithoutACurrentBranchKeepsEveryRef() {
        XCTAssertEqual(GitDiff.parseBranches("main\nfeature\norigin/HEAD\norigin/main\n", current: nil),
                       ["main", "feature", "origin/main"])
    }

    /// Commit to commit: nothing in the working tree or the index can leak in.
    func testBranchDiffComparesTwoCommits() {
        XCTAssertEqual(GitDiff.branchDiffArguments(from: "base", tip: "tip", relative: "a.md"),
                       ["diff", "base", "tip", "--", "a.md"])
    }
}

/// Branch view against a real repository: extraction, ref resolution and the
/// fork-point diff, and that none of it writes to `.git`.
final class BranchViewGitTests: XCTestCase {
    private var repo: URL!
    private var cache: URL!
    private var main: String!   // whatever git named the first branch

    override func setUpWithError() throws {
        let fm = FileManager.default
        repo = fm.temporaryDirectory.appendingPathComponent("branch-view-\(UUID().uuidString)")
        cache = fm.temporaryDirectory.appendingPathComponent("branch-cache-\(UUID().uuidString)")
        try fm.createDirectory(at: repo.appendingPathComponent("docs/img"), withIntermediateDirectories: true)
        guard case .output = GitDiff.run(["init"], in: repo) else {
            throw XCTSkip("git init failed in this environment")
        }
        try write("docs/a.md", "# A\n\none\n")
        try write("docs/img/p.png", "png")
        try write("docs/notes.txt", "not markdown")
        try write("top.md", "# Top\n")
        commit("one")
        guard case .output(let name) = GitDiff.run(["rev-parse", "--abbrev-ref", "HEAD"], in: repo) else {
            throw XCTSkip("could not read the default branch name")
        }
        main = name.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = GitDiff.run(["checkout", "-q", "-b", "feature"], in: repo)
        try write("docs/a.md", "# A\n\none\n\nfeature line\n")
        try write("docs/b.md", "# B\n")
        commit("feature")
        _ = GitDiff.run(["checkout", "-q", main], in: repo)
        // main moves on after the fork: the branch's diff must not show this.
        try write("top.md", "# Top\n\nmain later\n")
        commit("main later")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repo)
        try? FileManager.default.removeItem(at: cache)
    }

    private func write(_ path: String, _ text: String) throws {
        try text.write(to: repo.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    private func commit(_ message: String) {
        _ = GitDiff.run(["add", "-A"], in: repo)
        _ = GitDiff.run(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", message], in: repo)
    }

    private func resolve(_ ref: String) throws -> String {
        try XCTUnwrap(BranchCache.resolve(ref, in: repo))
    }

    /// Every file under `.git` with its contents, so a write of any kind shows.
    private func gitDirDigest() throws -> [String: String] {
        let git = repo.appendingPathComponent(".git")
        var digest: [String: String] = [:]
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: git, includingPropertiesForKeys: nil))
        for case let url as URL in walker {
            guard let data = try? Data(contentsOf: url) else { continue }   // directories
            digest[url.path] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return digest
    }

    func testResolveNamesACommitOrNothing() throws {
        XCTAssertEqual(try resolve("feature").count, 40)
        XCTAssertNil(BranchCache.resolve("no-such-branch", in: repo))
        XCTAssertNil(BranchCache.resolve("-h", in: repo))
    }

    func testHeadIsTheBranchOrADetachedSha() throws {
        XCTAssertEqual(BranchCache.head(in: repo), main)
        _ = GitDiff.run(["checkout", "-q", "--detach"], in: repo)
        let detached = try XCTUnwrap(BranchCache.head(in: repo))
        XCTAssertTrue(try resolve("HEAD").hasPrefix(detached))
        XCTAssertNil(BranchCache.head(in: cache.deletingLastPathComponent().appendingPathComponent("/")))
    }

    func testBranchListCanKeepTheCheckedOutBranch() {
        XCTAssertTrue(GitDiff.branches(root: repo, keepCurrent: true).contains(main))
        XCTAssertFalse(GitDiff.branches(root: repo).contains(main))
    }

    /// A root in a subfolder extracts only that subfolder, starting at its top,
    /// and only markdown and images.
    func testExtractingASubfolderRootKeepsItsLayout() throws {
        let docs = repo.appendingPathComponent("docs")
        let sha = try resolve("feature")
        XCTAssertNil(BranchCache.extract(sha: sha, ofRoot: docs.path, from: docs, in: cache))

        let tree = BranchCache.tree(forRoot: docs.path, sha: sha, in: cache)
        let a = try String(contentsOf: tree.appendingPathComponent("a.md"), encoding: .utf8)
        XCTAssertTrue(a.contains("feature line"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tree.appendingPathComponent("b.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tree.appendingPathComponent("img/p.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tree.appendingPathComponent("notes.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tree.appendingPathComponent("top.md").path))
        // Nothing left half-done beside it.
        let folder = BranchCache.folder(forRoot: docs.path, in: cache)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [sha])
    }

    /// The promise in docs/features/git.md: picking and reading a branch never
    /// writes to the repository.
    func testExtractingAndDiffingWriteNothingToGit() throws {
        let before = try gitDirDigest()
        let sha = try resolve("feature")
        XCTAssertNil(BranchCache.extract(sha: sha, ofRoot: repo.path, from: repo, in: cache))
        _ = BranchCache.head(in: repo)
        _ = GitDiff.branches(root: repo, keepCurrent: true)
        let tree = BranchCache.tree(forRoot: repo.path, sha: sha, in: cache)
        _ = GitDiff.branchDiff(file: tree.appendingPathComponent("docs/a.md"), relative: "docs/a.md",
                               base: "HEAD", tip: sha, root: repo)
        XCTAssertEqual(try gitDirDigest(), before)
    }

    func testAPathTheCommitLacksFailsWithoutLeavingATree() throws {
        let sha = try resolve("feature")
        let gone = repo.appendingPathComponent("gone")
        try FileManager.default.createDirectory(at: gone, withIntermediateDirectories: true)
        XCTAssertNotNil(BranchCache.extract(sha: sha, ofRoot: gone.path, from: gone, in: cache))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: BranchCache.tree(forRoot: gone.path, sha: sha, in: cache).path))
    }

    /// What the branch changed since it forked — not main's later commit, which
    /// a two-dot diff against main would show reversed.
    func testBranchDiffStartsAtTheForkPoint() throws {
        let sha = try resolve("feature")
        XCTAssertNil(BranchCache.extract(sha: sha, ofRoot: repo.path, from: repo, in: cache))
        let tree = BranchCache.tree(forRoot: repo.path, sha: sha, in: cache)

        let a = try XCTUnwrap(GitDiff.branchDiff(file: tree.appendingPathComponent("docs/a.md"),
                                                 relative: "docs/a.md", base: main, tip: sha, root: repo))
        XCTAssertEqual(a.additions, 2)
        XCTAssertEqual(a.deletions, 0)
        XCTAssertNil(GitDiff.branchDiff(file: tree.appendingPathComponent("top.md"),
                                        relative: "top.md", base: main, tip: sha, root: repo))
    }

    /// Run from a subfolder root, the path is relative to that root.
    func testBranchDiffPathsAreRelativeToTheRoot() throws {
        let docs = repo.appendingPathComponent("docs")
        let sha = try resolve("feature")
        XCTAssertNil(BranchCache.extract(sha: sha, ofRoot: docs.path, from: docs, in: cache))
        let tree = BranchCache.tree(forRoot: docs.path, sha: sha, in: cache)
        let b = try XCTUnwrap(GitDiff.branchDiff(file: tree.appendingPathComponent("b.md"),
                                                 relative: "b.md", base: "HEAD", tip: sha, root: docs))
        XCTAssertEqual(b.additions, 1)
    }
}
