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

CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
CGAssociateMouseAndMouseCursorPosition(1)
exit(0)
