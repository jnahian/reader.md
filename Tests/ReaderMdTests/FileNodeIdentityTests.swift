import XCTest
@testable import ReaderMd

/// SwiftUI skips a row whose stored values compare equal. `FileNode` used to be
/// Equatable by path alone, so after a rescan an expanded folder looked unchanged
/// and kept its old children, and a new file in it never appeared (#107). Without
/// the conformance SwiftUI compares the reference, and every scan builds new nodes.
final class FileNodeIdentityTests: XCTestCase {
    func testNodesAreNotEquatable() {
        let type: Any.Type = FileNode.self
        XCTAssertFalse(type is any Equatable.Type)
    }
}
