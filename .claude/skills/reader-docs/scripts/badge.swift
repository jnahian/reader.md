// Renders a keystroke badge — a rounded dark pill with the shortcut centred —
// as a transparent PNG, for overlaying onto a clip.
//
// Done here rather than with ffmpeg's drawtext for two reasons: drawtext draws
// square boxes only, and getting a literal backslash (⇧⌘\) through the filter
// parser is a quoting fight. AppKit also gives us the real SF Pro glyphs for
// ⌘ ⇧ ⌥ ⌃.
import AppKit
import Foundation

guard CommandLine.arguments.count > 2 else {
    FileHandle.standardError.write("usage: badge.swift <text> <out.png> [fontSize]\n".data(using: .utf8)!)
    exit(2)
}
let text = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
let fontSize = CommandLine.arguments.count > 3 ? (Double(CommandLine.arguments[3]) ?? 30) : 30

// Deliberately a LIGHT pill with dark text. The app is screenshotted in dark
// mode, so a dark badge sinks into the UI; a near-white one reads instantly at
// any size and survives h264 compression.
let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(calibratedWhite: 0.07, alpha: 1.0),
    // A touch of tracking keeps ⇧⌘\ from reading as one blob.
    .kern: fontSize * 0.04,
]
let string = NSAttributedString(string: text, attributes: attrs)
let textSize = string.size()

let padX = fontSize * 0.85
let padY = fontSize * 0.45
// Room around the pill for the drop shadow, which is what separates it from a
// busy screenshot behind it.
let margin = fontSize * 0.5
let pillW = ceil(textSize.width + padX * 2)
let pillH = ceil(textSize.height + padY * 2)
let w = pillW + margin * 2
let h = pillH + margin * 2

let image = NSImage(size: NSSize(width: w, height: h))
image.lockFocus()

NSGraphicsContext.current?.imageInterpolation = .high
let rect = NSRect(x: margin, y: margin, width: pillW, height: pillH)
let pill = NSBezierPath(roundedRect: rect, xRadius: pillH / 2, yRadius: pillH / 2)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.55)
shadow.shadowBlurRadius = fontSize * 0.42
shadow.shadowOffset = NSSize(width: 0, height: -fontSize * 0.10)
shadow.set()
NSColor(calibratedWhite: 0.97, alpha: 0.97).setFill()
pill.fill()
NSGraphicsContext.restoreGraphicsState()

string.draw(at: NSPoint(x: (w - textSize.width) / 2, y: (h - textSize.height) / 2))
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("badge: could not encode PNG\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
