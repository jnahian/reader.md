import AppKit
import WebKit

/// Return-to-activate.
///
/// macOS splits activation in two: Space presses the focused control, Return
/// presses the window's *default* button. The document window has no default
/// button, so tabbing to a control and pressing Return did nothing at all —
/// the one key most people reach for first. The rule here is simply that
/// **Return does what Space does**, everywhere Space already means "press
/// this": the shell's buttons, rows, and menus.
///
/// Split the way `escapeAction(...)` is — a pure rule that decides, and the
/// AppKit plumbing that feeds it. The rule is what the tests pin.

/// Where keyboard focus is, reduced to the three cases the rule separates.
enum FocusTarget: Equatable {
    /// A text field or the field editor inside one. Return belongs to the
    /// field: Find Next, submit the quick-open row, send a comment.
    case textEntry
    /// The `WKWebView` showing the document. Return has no meaning in the page,
    /// and translating it to Space would page-scroll instead.
    case documentContent
    /// Anything else the shell can focus — a toolbar button, a sidebar row, a
    /// Settings control. This is where Space presses, so Return should too.
    case appChrome
}

enum ReturnAction: Equatable {
    case activateFocused
    case passThrough
}

/// A bare Return activates the focused control, and nothing else.
///
/// Sheets are excluded because they have a real default button
/// (`AddRemoteView`'s Save): there Return means "confirm the sheet" whichever
/// button holds focus, and stealing it would be a regression.
func returnKeyAction(focus: FocusTarget, inSheetOrModal: Bool) -> ReturnAction {
    guard !inSheetOrModal else { return .passThrough }
    return focus == .appChrome ? .activateFocused : .passThrough
}

extension NSWindow {
    /// Classified from the first responder, not from accessibility: SwiftUI
    /// serves its accessibility tree out of process, so in-process AX only ever
    /// names a container (`AXToolbar`, `AXScrollArea`) and never the focused
    /// button. The first responder does distinguish the three cases — SwiftUI
    /// parks a proxy view there whenever one of its own elements has focus.
    var focusTarget: FocusTarget {
        guard let responder = firstResponder else { return .appChrome }
        // Covers every text field: the responder is the shared field editor,
        // an NSText, rather than the field itself.
        if responder is NSText { return .textEntry }
        if let view = responder as? NSView, view.isInsideWebView { return .documentContent }
        return .appChrome
    }

    var isSheetOrModal: Bool {
        NSApp.modalWindow != nil || sheetParent != nil || !sheets.isEmpty
    }
}

private extension NSView {
    /// Walks up rather than testing the responder itself — which view inside a
    /// `WKWebView` takes first responder is WebKit's business, not ours.
    var isInsideWebView: Bool {
        var view: NSView? = self
        while let current = view {
            if current is WKWebView { return true }
            view = current.superview
        }
        return false
    }
}

enum ReturnKeyMonitor {
    /// keyCode 36 — Return. `⌘↩` / `⇧⌘↩` are already Find Next / Previous, so
    /// this only ever looks at Return with no modifiers.
    private static let returnKeyCode: UInt16 = 36
    private static let spaceKeyCode: UInt16 = 49

    static func install() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == returnKeyCode,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  let window = NSApp.keyWindow,
                  returnKeyAction(
                      focus: window.focusTarget,
                      inSheetOrModal: window.isSheetOrModal
                  ) == .activateFocused
            else { return event }
            // Hand AppKit a Space in Return's place rather than trying to press
            // the control ourselves: SwiftUI keeps focus in its own layer and
            // exposes no in-process handle on the focused view, but it already
            // activates on Space. Substituting the event reuses that path whole.
            return spaceEquivalent(of: event) ?? event
        }
    }

    private static func spaceEquivalent(of event: NSEvent) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: event.locationInWindow,
            modifierFlags: [],
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: event.isARepeat,
            keyCode: spaceKeyCode
        )
    }
}
