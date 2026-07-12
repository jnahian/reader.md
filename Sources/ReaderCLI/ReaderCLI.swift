import Foundation

@main
struct ReaderCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = Route.parse(args, cwd: FileManager.default.currentDirectoryPath)

        if case .open(let path) = command {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                fail("no such file or folder: \(path)")
            }
            if !isDirectory.boolValue, !Route.markdownExtensions.contains((path as NSString).pathExtension.lowercased()) {
                fail("not a markdown file: \(path)")
            }
        }

        switch command {
        case .help:
            print(usage)
        case .misuse(let problem):
            // stderr + exit 1: a script must be able to tell misuse from success.
            FileHandle.standardError.write(Data("reader: \(problem)\n\n\(usage)\n".utf8))
            exit(1)
        case .list:
            let roots = Prefs.roots()
            if roots.isEmpty {
                print("No folders. Add one with `reader <folder>`.")
            }
            for line in Prefs.lines(for: roots) {
                print(line)
            }
        case .open, .remote, .remove:
            guard let url = Route.url(for: command) else {
                fail("could not build a URL for that command")
            }
            guard Dispatch.send(url) else {
                fail("could not launch Reader.md")
            }
        case .stdin:
            let now = Date()
            StdinDoc.reap(in: StdinDoc.directory, olderThan: 86400, now: now)
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard !data.isEmpty else { fail("nothing on stdin") }
            guard let file = try? StdinDoc.write(data, now: now.timeIntervalSince1970, into: StdinDoc.directory),
                  let url = Route.url(for: .open(path: file.path))
            else { fail("could not write the piped document") }
            guard Dispatch.send(url) else { fail("could not launch Reader.md") }
        }
    }

    /// Message on stderr, exit 1 — the shell contract.
    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("reader: \(message)\n".utf8))
        exit(1)
    }

    static let usage = """
    reader — open markdown in Reader.md

      reader <file.md>          open a markdown file
      reader <folder>           add a folder to the sidebar
      reader .                  add the current directory
      reader remote <user@host:/path>
                                add a remote (SSH) folder
      reader ls                 list configured folders
      reader rm <name|path>     remove a folder
      cat x.md | reader -       open piped markdown
    """
}
