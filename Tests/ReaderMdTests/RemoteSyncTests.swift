// Tests/ReaderMdTests/RemoteSyncTests.swift
import XCTest
@testable import ReaderMd

final class RemoteSyncTests: XCTestCase {
    private let spec = RemoteSpec(id: "t", name: "Docs", sshDestination: "me@vps", remotePath: "/srv/docs")

    func testStartsWithArchiveAndSSHTransport() {
        let a = RemoteSync.arguments(for: spec)
        XCTAssertEqual(Array(a.prefix(5)), ["-az", "--delete", "--prune-empty-dirs", "-e", "ssh"])
    }

    func testDirExcludesComeBeforeDescendInclude() {
        let a = RemoteSync.arguments(for: spec)
        let excludeNodeModules = try! XCTUnwrap(a.firstIndex(of: "--exclude=node_modules"))
        let descend = try! XCTUnwrap(a.firstIndex(of: "--include=*/"))
        XCTAssertLessThan(excludeNodeModules, descend, "dir excludes must precede --include=*/")
    }

    func testFileIncludesBetweenDescendAndFinalExclude() {
        let a = RemoteSync.arguments(for: spec)
        let descend = try! XCTUnwrap(a.firstIndex(of: "--include=*/"))
        let md = try! XCTUnwrap(a.firstIndex(of: "--include=*.md"))
        let png = try! XCTUnwrap(a.firstIndex(of: "--include=*.png"))
        let finalExclude = try! XCTUnwrap(a.firstIndex(of: "--exclude=*"))
        XCTAssertLessThan(descend, md)
        XCTAssertLessThan(md, finalExclude)
        XCTAssertLessThan(png, finalExclude)
    }

    func testSourceAndDestAreLastTwoWithTrailingSlashes() {
        let a = RemoteSync.arguments(for: spec)
        XCTAssertEqual(a[a.count - 2], "me@vps:/srv/docs/")
        XCTAssertEqual(a[a.count - 1], spec.cacheURL.path + "/")
    }

    func testRemotePathAlreadyTrailingSlashNotDoubled() {
        let s = RemoteSpec(id: "t", name: "D", sshDestination: "me@vps", remotePath: "/srv/docs/")
        let a = RemoteSync.arguments(for: s)
        XCTAssertEqual(a[a.count - 2], "me@vps:/srv/docs/")
    }
}

/// A git remote is cloned once and pulled after that.
final class GitRemoteSyncTests: XCTestCase {
    private let spec = RemoteSpec(id: "g", name: "Repo", gitURL: "https://example.com/docs.git")

    func testFirstSyncClones() {
        XCTAssertEqual(RemoteSync.gitArguments(for: spec, cloned: false),
                       ["clone", "--quiet", "--", "https://example.com/docs.git", spec.cacheURL.path])
    }

    /// `--` matters: a repository URL starting with a dash would otherwise reach
    /// git as an option.
    func testCloneSeparatesOptionsFromTheURL() {
        let a = RemoteSync.gitArguments(for: spec, cloned: false)
        XCTAssertLessThan(a.firstIndex(of: "--")!, a.firstIndex(of: spec.gitURL!)!)
    }

    /// `--ff-only`, so a sync never invents a merge commit in a cache the user
    /// didn't ask to own.
    func testLaterSyncsPullFastForwardOnly() {
        XCTAssertEqual(RemoteSync.gitArguments(for: spec, cloned: true),
                       ["-C", spec.cacheURL.path, "pull", "--ff-only", "--quiet"])
    }

    /// Replacing the environment instead of adding to it drops HOME, and git
    /// without HOME finds no ~/.gitconfig, no ~/.ssh and no credential helper.
    func testEnvironmentIsInheritedNotReplaced() {
        let env = RemoteSync.gitEnvironment()
        XCTAssertEqual(env["GIT_TERMINAL_PROMPT"], "0", "a prompt would hang the sync forever")
        XCTAssertEqual(env["HOME"], ProcessInfo.processInfo.environment["HOME"])
    }

    func testAnSSHSpecStillGetsRsyncArguments() {
        let ssh = RemoteSpec(id: "s", name: "D", sshDestination: "me@vps", remotePath: "/srv")
        XCTAssertFalse(ssh.isGit)
        XCTAssertTrue(RemoteSync.gitArguments(for: ssh, cloned: false).isEmpty)
    }
}

/// Cloning for real, from a local repo. The argument tests above can all pass
/// while the sync still hangs on a prompt or clones into a directory git
/// refuses — only running it proves otherwise.
final class GitRemoteSyncRunTests: XCTestCase {
    private var origin: URL!
    private var spec: RemoteSpec!

    override func setUpWithError() throws {
        let fm = FileManager.default
        origin = fm.temporaryDirectory.appendingPathComponent("git-origin-\(UUID().uuidString)")
        try fm.createDirectory(at: origin, withIntermediateDirectories: true)
        guard case .output = GitDiff.run(["init"], in: origin) else {
            throw XCTSkip("git init failed in this environment")
        }
        try "# One\n".write(to: origin.appendingPathComponent("one.md"), atomically: true, encoding: .utf8)
        _ = GitDiff.run(["add", "-A"], in: origin)
        _ = GitDiff.run(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", "one"], in: origin)
        spec = RemoteSpec(id: "clone-test-\(UUID().uuidString)", name: "Repo", gitURL: origin.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: origin)
        try? FileManager.default.removeItem(at: spec.cacheURL)
    }

    func testCloneThenPull() async throws {
        let cloned = await RemoteSync.run(spec)
        XCTAssertTrue(cloned.success, cloned.message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: spec.cacheURL.appendingPathComponent("one.md").path))

        try "# Two\n".write(to: origin.appendingPathComponent("two.md"), atomically: true, encoding: .utf8)
        _ = GitDiff.run(["add", "-A"], in: origin)
        _ = GitDiff.run(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", "two"], in: origin)

        let pulled = await RemoteSync.run(spec)
        XCTAssertTrue(pulled.success, pulled.message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: spec.cacheURL.appendingPathComponent("two.md").path))
    }

    /// The cache already holds rsynced files when an SSH remote is edited into a
    /// git one; git refuses to clone into a non-empty directory, so the sync
    /// clears it first or the remote is wedged for good.
    func testClonesIntoACacheLeftOverFromAnRsyncRemote() async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: spec.cacheURL, withIntermediateDirectories: true)
        try "stale".write(to: spec.cacheURL.appendingPathComponent("old.md"), atomically: true, encoding: .utf8)

        let result = await RemoteSync.run(spec)
        XCTAssertTrue(result.success, result.message)
        XCTAssertFalse(fm.fileExists(atPath: spec.cacheURL.appendingPathComponent("old.md").path))
    }

    /// `cacheURL` with an empty id is the shared `remotes/` parent, and the clone
    /// path wipes its destination first — so this would delete every other
    /// remote's cache. Reachable only from a hand-edited defaults plist, which is
    /// exactly why it can't be left to the callers.
    func testAnEmptyIDIsRefusedRatherThanWipingEveryCache() async throws {
        let fm = FileManager.default
        let sibling = RemoteSpec(id: "bystander-\(UUID().uuidString)", name: "Other",
                                 gitURL: origin.path)
        try fm.createDirectory(at: sibling.cacheURL, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: sibling.cacheURL) }

        let result = await RemoteSync.run(RemoteSpec(id: "", name: "Broken", gitURL: origin.path))
        XCTAssertFalse(result.success)
        XCTAssertTrue(fm.fileExists(atPath: sibling.cacheURL.path), "a sibling remote's cache was deleted")
    }

    func testAFailedCloneReportsGitsOwnError() async {
        let bad = RemoteSpec(id: "clone-fail-\(UUID().uuidString)", name: "Nope",
                             gitURL: "/nonexistent-\(UUID().uuidString)")
        let result = await RemoteSync.run(bad)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("does not exist"), result.message)
    }
}
