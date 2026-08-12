// Prints the CGWindowID of the first on-screen, layer-0 window whose owning
// application name contains the given substring. Layer 0 excludes menus,
// tooltips, and other floating chrome — we want the document window.
import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: winid.swift <owner-substring>\n".data(using: .utf8)!)
    exit(2)
}
let needle = CommandLine.arguments[1]

let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
) as? [[String: Any]] ?? []

// The app also exposes a small unnamed system dialog at layer 0. Prefer a
// window with a title — that is the document window. Fall back to any layer-0
// window only if nothing is titled.
var fallback: Int?

for w in windows {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let name = w[kCGWindowName as String] as? String ?? ""
    let layer = w[kCGWindowLayer as String] as? Int ?? -1
    guard owner.contains(needle), layer == 0,
          let number = w[kCGWindowNumber as String] as? Int else { continue }
    if !name.isEmpty {
        print(number)
        exit(0)
    }
    if fallback == nil { fallback = number }
}

if let number = fallback {
    print(number)
    exit(0)
}

FileHandle.standardError.write("winid: no on-screen window for '\(needle)'\n".data(using: .utf8)!)
exit(1)
