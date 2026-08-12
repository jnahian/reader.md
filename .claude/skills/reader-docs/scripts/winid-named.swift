// Window id for an owner+exact title. One-off: the export panel is a separate
// modal window and winid.swift returns whichever titled window comes first.
import CoreGraphics
import Foundation
let owner = CommandLine.arguments[1], title = CommandLine.arguments[2]
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in windows {
    let o = w[kCGWindowOwnerName as String] as? String ?? ""
    let n = w[kCGWindowName as String] as? String ?? ""
    let l = w[kCGWindowLayer as String] as? Int ?? -1
    if o.contains(owner) { FileHandle.standardError.write("  layer \(l) '\(n)'\n".data(using: .utf8)!) }
    if o.contains(owner), n == title, let id = w[kCGWindowNumber as String] as? Int {
        print(id); exit(0)
    }
}
exit(1)
