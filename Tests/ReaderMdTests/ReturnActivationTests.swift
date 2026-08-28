import XCTest
@testable import ReaderMd

/// Return means "press the thing that has focus" — but only outside the places
/// Return already meant something else. Each of those carve-outs was a working
/// behaviour before this existed (Find Next, submitting quick open, sending a
/// comment, confirming a sheet), so they are what the rule is really about.
final class ReturnActivationTests: XCTestCase {
    func testFocusedControlIsActivated() {
        XCTAssertEqual(returnKeyAction(focus: .appChrome, inSheetOrModal: false), .activateFocused)
    }

    /// The find field, the sidebar filter, quick open, and the comment reply box
    /// all own Return themselves.
    func testTextEntryKeepsReturn() {
        XCTAssertEqual(returnKeyAction(focus: .textEntry, inSheetOrModal: false), .passThrough)
    }

    /// Return does nothing in the page, and the event is passed on rather than
    /// translated — a Space handed to the web view would scroll it instead.
    func testDocumentContentKeepsReturn() {
        XCTAssertEqual(returnKeyAction(focus: .documentContent, inSheetOrModal: false), .passThrough)
    }

    /// A sheet has a real default button (Add Remote Folder's Save). Return
    /// confirms the sheet there no matter which button holds focus, which is
    /// stock macOS and not ours to override.
    func testSheetsKeepTheirDefaultButton() {
        XCTAssertEqual(returnKeyAction(focus: .appChrome, inSheetOrModal: true), .passThrough)
        XCTAssertEqual(returnKeyAction(focus: .textEntry, inSheetOrModal: true), .passThrough)
        XCTAssertEqual(returnKeyAction(focus: .documentContent, inSheetOrModal: true), .passThrough)
    }
}
