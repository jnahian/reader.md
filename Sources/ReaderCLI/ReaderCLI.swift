import Foundation

@main
struct ReaderCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = Route.parse(args, cwd: FileManager.default.currentDirectoryPath)

        switch command {
        case .usage:
            print(usage)
        case .list:
            let roots = Prefs.roots()
            if roots.isEmpty {
                print("No folders. Add one with `reader <folder>`.")
            }
            for line in Prefs.lines(for: roots) {
                print(line)
            }
        default:
            FileHandle.standardError.write(Data("not implemented yet\n".utf8))
            exit(1)
        }
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
