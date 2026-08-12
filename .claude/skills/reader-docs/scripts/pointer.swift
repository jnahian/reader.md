// Mouse input at global screen points. AppleScript can only left-click, and a
// WKWebView needs real mouseDragged events to extend a text selection — so
// selecting a phrase, the one gesture the markup popover needs, is unreachable
// without this.
//
//   pointer.swift click  <x> <y>
//   pointer.swift rclick <x> <y>
//   pointer.swift drag   <x1> <y1> <x2> <y2>
import CoreGraphics
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("pointer: \(message)\n".data(using: .utf8)!)
    exit(2)
}

let args = CommandLine.arguments
guard args.count >= 4 else {
    fail("usage: pointer.swift click|rclick <x> <y> | drag <x1> <y1> <x2> <y2>")
}
let verb = args[1]
let numbers = args.dropFirst(2).map { Double($0) ?? Double.nan }
guard !numbers.contains(where: { $0.isNaN }) else { fail("coordinates must be numbers") }

func post(_ type: CGEventType, _ point: CGPoint, _ button: CGMouseButton = .left) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)?
        .post(tap: .cghidEventTap)
}

/// Warp, then a real mouseMoved: warping alone updates no hover state, so a
/// control can stay unhighlighted under a pointer that is standing on it.
func settle(at point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    CGAssociateMouseAndMouseCursorPosition(1)
    post(.mouseMoved, point)
    usleep(150_000)
}

switch verb {
case "click", "rclick":
    guard numbers.count == 2 else { fail("\(verb) takes 2 coordinates") }
    let p = CGPoint(x: numbers[0], y: numbers[1])
    settle(at: p)
    let (down, up, button): (CGEventType, CGEventType, CGMouseButton) =
        verb == "click" ? (.leftMouseDown, .leftMouseUp, .left)
                        : (.rightMouseDown, .rightMouseUp, .right)
    post(down, p, button)
    usleep(120_000)
    post(up, p, button)

case "drag":
    guard numbers.count == 4 else { fail("drag takes 4 coordinates") }
    let a = CGPoint(x: numbers[0], y: numbers[1])
    let b = CGPoint(x: numbers[2], y: numbers[3])
    settle(at: a)
    post(.leftMouseDown, a)
    usleep(180_000)
    // Intermediate moves, not one jump: a single dragged event to the far end
    // selects nothing in a web view, which reads as the feature being broken.
    for i in 1...12 {
        let t = Double(i) / 12
        post(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        usleep(45_000)
    }
    post(.leftMouseUp, b)

default:
    fail("unknown verb '\(verb)'")
}
exit(0)
