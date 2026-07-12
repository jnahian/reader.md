import Foundation

/// Parses the `readermd://` URLs the CLI sends. Pure — the trust boundary is here,
/// because these URLs can also be fired by any web page.
enum ReaderURL {
    enum Action: Equatable {
        case open(String)               // absolute path: a markdown file, or a folder to add
        case addRemote(RemoteSpec)      // never synced directly — opens the confirmation sheet
        case remove(String)             // a name or a path; the app matches it against its roots
    }

    static func action(for url: URL) -> Action? {
        guard url.scheme == "readermd",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        func value(_ name: String) -> String? {
            let found = components.queryItems?.first { $0.name == name }?.value
            return (found?.isEmpty ?? true) ? nil : found
        }

        switch url.host {
        case "open":
            guard let path = value("path") else { return nil }
            return .open(path)

        case "add-remote":
            guard let dest = value("dest"),
                  let path = value("path"), path.hasPrefix("/"),
                  dest.contains("@")
            else { return nil }
            let name = value("name") ?? (path as NSString).lastPathComponent
            return .addRemote(RemoteSpec(name: name, sshDestination: dest, remotePath: path))

        case "remove":
            guard let match = value("match") else { return nil }
            return .remove(match)

        default:
            return nil
        }
    }
}
