import XCTest
import AppKit
import WebKit
@testable import ReaderMd

/// `DropWebView` sits in the one place a GUI test can't reach, but its drag-destination
/// answers are pure functions of the pasteboard — so they are testable with a stub.
///
/// These cover our own overrides: that a file-URL drag is claimed, reported to the overlay,
/// delivered, and that targeting clears afterwards. They do NOT cover whether AppKit routes
/// a real drag to this view in the first place — that needs a real drag session.
final class DropWebViewTests: XCTestCase {

    private func makeDraggingInfo(pasteboardItems: [Any]) -> StubDraggingInfo {
        let pb = NSPasteboard(name: .init("ReaderMdTest-\(UUID().uuidString)"))
        pb.clearContents()
        if !pasteboardItems.isEmpty {
            pb.writeObjects(pasteboardItems as! [NSPasteboardWriting])
        }
        return StubDraggingInfo(pasteboard: pb)
    }

    func testDraggingEnteredReportsTargetedAndReturnsCopy() {
        let view = DropWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var targeted: Bool?
        view.onDragTargeted = { targeted = $0 }
        let info = makeDraggingInfo(pasteboardItems: [NSURL(fileURLWithPath: "/tmp/note.md")])

        XCTAssertEqual(view.draggingEntered(info), .copy)
        XCTAssertEqual(targeted, true, "The drop overlay never appears if targeting isn't reported.")
    }

    func testPerformDragOperationDeliversURLAndClearsTargeting() {
        let view = DropWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var delivered: [URL] = []
        var targeted: Bool?
        view.onDrop = { delivered.append($0) }
        view.onDragTargeted = { targeted = $0 }
        let info = makeDraggingInfo(pasteboardItems: [NSURL(fileURLWithPath: "/tmp/note.md")])

        XCTAssertTrue(view.performDragOperation(info))
        XCTAssertEqual(delivered.map(\.lastPathComponent), ["note.md"])
        XCTAssertEqual(targeted, false, "Targeting must clear on drop or the overlay stays up.")
    }

    func testDraggingUpdatedKeepsTheCopyOperation() {
        let view = DropWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let info = makeDraggingInfo(pasteboardItems: [NSURL(fileURLWithPath: "/tmp/note.md")])

        XCTAssertEqual(view.draggingUpdated(info), .copy,
                       "Without this the copy cursor reverts to WebKit's answer mid-drag.")
    }
}

/// Minimal `NSDraggingInfo`; only `draggingPasteboard` is consulted by `DropWebView`.
private final class StubDraggingInfo: NSObject, NSDraggingInfo {
    private let pasteboard: NSPasteboard
    init(pasteboard: NSPasteboard) { self.pasteboard = pasteboard }

    var draggingPasteboard: NSPasteboard { pasteboard }

    var draggedImage: NSImage? { nil }  // deprecated, but still a protocol requirement
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 0 }
    var draggingFormation: NSDraggingFormation {
        get { .default }
        set { _ = newValue }
    }
    var animatesToDestination: Bool {
        get { false }
        set { _ = newValue }
    }
    var numberOfValidItemsForDrop: Int {
        get { 1 }
        set { _ = newValue }
    }
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions,
                                for view: NSView?,
                                classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}
