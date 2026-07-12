import Foundation

/// What the user asked for. Pure data — no filesystem, no side effects.
enum Command: Equatable {
    case open(path: String)
    case remote(dest: String, path: String, name: String)
    case remove(token: String)
    case list
    case stdin
    case usage
}

enum Route {
    static let scheme = "readermd"
    static let appDomain = "com.nahian.reader-md"

    // MARK: - argv -> Command

    static func parse(_ args: [String], cwd: String) -> Command {
        guard let first = args.first else { return .usage }

        switch first {
        case "-":
            return .stdin
        case "ls":
            return .list
        case "rm":
            guard args.count == 2, !args[1].isEmpty else { return .usage }
            return .remove(token: args[1])
        case "remote":
            guard args.count == 2, let spec = parseRemote(args[1]) else { return .usage }
            return spec
        default:
            // A leading dash that isn't the stdin "-" is a flag we don't have.
            guard !first.hasPrefix("-") else { return .usage }
            return .open(path: absolute(first, cwd: cwd))
        }
    }

    /// "me@vps:/srv/docs" -> destination, absolute remote path, and a name from the
    /// last path component. Anything else is unusable.
    private static func parseRemote(_ arg: String) -> Command? {
        let parts = arg.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let dest = String(parts[0])
        let path = String(parts[1])
        guard dest.contains("@"), path.hasPrefix("/") else { return nil }
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }
        return .remote(dest: dest, path: path, name: name)
    }

    /// Expand `~`, make relative paths absolute against the cwd, and collapse
    /// `.`/`..`/trailing slashes. Symlinks are resolved later, by the caller that
    /// touches the disk — this stays pure.
    static func absolute(_ path: String, cwd: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let joined = expanded.hasPrefix("/")
            ? expanded
            : (cwd as NSString).appendingPathComponent(expanded)
        return (joined as NSString).standardizingPath
    }

    // MARK: - Command -> URL

    /// `URLComponents` will NOT escape `&`, `+`, `=`, `?` or `#` inside a query
    /// value — they are legal query delimiters — so a path containing one would
    /// silently truncate. Encode the values ourselves.
    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?#")
        return set
    }()

    static func url(for command: Command) -> URL? {
        var components = URLComponents()
        components.scheme = scheme

        switch command {
        case .open(let path):
            components.host = "open"
            components.percentEncodedQueryItems = encoded(["path": path])
        case .remote(let dest, let path, let name):
            components.host = "add-remote"
            components.percentEncodedQueryItems = encoded(["dest": dest, "path": path, "name": name])
        case .remove(let token):
            components.host = "remove"
            components.percentEncodedQueryItems = encoded(["match": token])
        case .list, .stdin, .usage:
            return nil
        }
        return components.url
    }

    private static func encoded(_ pairs: KeyValuePairs<String, String>) -> [URLQueryItem] {
        pairs.map { key, value in
            URLQueryItem(name: key, value: value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed))
        }
    }
}
