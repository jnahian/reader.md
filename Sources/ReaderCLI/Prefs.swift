import Foundation

/// Read-only view of the app's preferences. The app is the only writer; `ls` just
/// looks. Keys are duplicated from `Settings.swift` on purpose — a shared library
/// target for two string constants would cost more than it saves.
// ponytail: two duplicated key strings; extract a shared target if a third consumer appears.
enum Prefs {
    private static let foldersKey = "reader.md.folders"
    private static let remotesKey = "reader.md.remotes"

    struct Root: Equatable {
        let name: String
        let detail: String
    }

    static func roots() -> [Root] {
        let domain = Route.appDomain as CFString
        // cfprefsd hands each process a cached snapshot. Without this, a freshly
        // spawned `reader ls` can miss what the app wrote a moment ago.
        CFPreferencesAppSynchronize(domain)

        let folders = CFPreferencesCopyAppValue(foldersKey as CFString, domain) as? [String] ?? []
        let remotes = CFPreferencesCopyAppValue(remotesKey as CFString, domain) as? Data
        return format(folders: folders, remotesJSON: remotes)
    }

    /// Pure: the shaping the tests drive.
    static func format(folders: [String], remotesJSON: Data?) -> [Root] {
        let local = folders.map { Root(name: ($0 as NSString).lastPathComponent, detail: $0) }

        let remotes: [Root] = {
            guard let data = remotesJSON,
                  let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return [] }
            return array.compactMap { entry in
                guard let name = entry["name"] as? String,
                      let dest = entry["sshDestination"] as? String,
                      let path = entry["remotePath"] as? String
                else { return nil }
                return Root(name: name, detail: "\(dest):\(path)")
            }
        }()

        return local + remotes
    }

    /// Left-aligned name column. Padding is built from the same unit the width is
    /// measured in — `padding(toLength:)` counts UTF-16, so an NFD name like
    /// "cafe\u{0301}" (how macOS hands back "café") would be truncated, not padded.
    static func lines(for roots: [Root]) -> [String] {
        let width = roots.map(\.name.count).max() ?? 0
        return roots.map { root in
            let pad = String(repeating: " ", count: width - root.name.count)
            return "\(root.name)\(pad)  \(root.detail)"
        }
    }
}
