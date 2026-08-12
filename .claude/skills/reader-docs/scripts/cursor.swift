// Parks the mouse pointer at a fixed global screen point. Video capture always
// records the cursor and has no flag to hide it, so the harness moves it out of
// frame before recording — otherwise it drifts through clips and varies between
// sweeps.
import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 2,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]) else {
    FileHandle.standardError.write("usage: cursor.swift <x> <y>\n".data(using: .utf8)!)
    exit(2)
}

// Warping alone is not enough: it moves the pointer WITHOUT delivering a
// mouse-moved event, so an app never learns the cursor left and any tooltip it
// was showing stays up — which then photobombs the clip. Post real
// mouseMoved events so hover state actually updates.
let target = CGPoint(x: x, y: y)
CGWarpMouseCursorPosition(target)
CGAssociateMouseAndMouseCursorPosition(1)

for _ in 0..<3 {
    CGEvent(
        mouseEventSource: nil,
        mouseType: .mouseMoved,
        mouseCursorPosition: target,
        mouseButton: .left
    )?.post(tap: .cghidEventTap)
    usleep(60_000)
}
exit(0)
