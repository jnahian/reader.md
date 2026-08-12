// Right-click at a global screen point. AppleScript's `click at` is left-only,
// and a context menu is the one state several manual shots need.
import CoreGraphics
import Foundation
let x = Double(CommandLine.arguments[1])!, y = Double(CommandLine.arguments[2])!
let p = CGPoint(x: x, y: y)
CGWarpMouseCursorPosition(p)
usleep(200_000)
for t in [CGEventType.rightMouseDown, .rightMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .right)?
        .post(tap: .cghidEventTap)
    usleep(120_000)
}
