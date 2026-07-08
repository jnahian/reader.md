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
