import XCTest
@testable import ReaderMd

/// `syncHover` re-derives hover from geometry, so the rect it tests against has
/// to be the control itself. The numbers here are the ones a running build
/// logged while five unrelated bubbles appeared on opening a file.
final class TooltipHoverRectTests: XCTestCase {
    /// A tracker's `visibleRect` reports the enclosing panel, in the tracker's
    /// own coordinates — not a subrect of its bounds. Untouched, it answers
    /// "yes" for a pointer anywhere in the sidebar.
    func testPointerElsewhereInThePanelIsNotOverTheControl() {
        let clearRecents = CGRect(x: 0, y: 0, width: 40, height: 14)
        let sidebarInLocalCoords = CGRect(x: -212, y: -349, width: 260, height: 365)
        let pointer = CGPoint(x: -62, y: -299)

        XCTAssertTrue(sidebarInLocalCoords.contains(pointer))
        XCTAssertFalse(
            TrackerNSView.hoverRect(bounds: clearRecents, visibleRect: sidebarInLocalCoords)
                .contains(pointer)
        )
    }

    func testPointerOnTheControlIsOverIt() {
        let row = CGRect(x: 0, y: 0, width: 244, height: 24)
        let sidebarInLocalCoords = CGRect(x: -8, y: -267, width: 260, height: 365)

        XCTAssertTrue(
            TrackerNSView.hoverRect(bounds: row, visibleRect: sidebarInLocalCoords)
                .contains(CGPoint(x: 120, y: 12))
        )
    }

    /// The clip still counts: a row scrolled half out of the sidebar is only
    /// hoverable over the part still on screen.
    func testClippedPartOfTheControlIsNotHoverable() {
        let row = CGRect(x: 0, y: 0, width: 244, height: 24)
        let clipCuttingTheRowInHalf = CGRect(x: 0, y: 12, width: 260, height: 365)
        let rect = TrackerNSView.hoverRect(bounds: row, visibleRect: clipCuttingTheRowInHalf)

        XCTAssertTrue(rect.contains(CGPoint(x: 120, y: 18)))
        XCTAssertFalse(rect.contains(CGPoint(x: 120, y: 6)))
    }
}
