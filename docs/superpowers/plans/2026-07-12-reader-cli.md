# `reader` CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `reader` command that opens files, adds local and remote folders, lists and removes roots, and pipes stdin into the Reader.md app.

**Architecture:** A second SwiftPM executable target (`ReaderCLI`) that never writes preferences. It turns arguments into a `readermd://` URL and hands that URL to the app bundle it lives inside; the app routes it through `.onOpenURL` and performs the mutation. Only `reader ls` bypasses the app, reading `UserDefaults` directly (read-only, no race).

**Tech Stack:** Swift 6.2+ / SwiftPM, AppKit (`NSWorkspace`), CoreFoundation (`CFPreferences`), SwiftUI (`.onOpenURL`), Homebrew cask.

**Spec:** `docs/superpowers/specs/2026-07-12-cli-tool-design.md`

## Global Constraints

- Deployment target stays **macOS 13**. Any macOS 26-only API needs an availability guard with a pre-26 fallback. (Nothing in this plan needs one.)
- The app is the **single writer** of preferences. The CLI reads prefs but never writes them.
- Preferences domain is `com.nahian.reader-md`; keys are `reader.md.folders` (string array) and `reader.md.remotes` (JSON `Data`).
- The URL scheme is `readermd`. Verbs: `open`, `add-remote`, `remove`. No other verb exists.
- `add-remote` from a URL **never syncs directly** — it opens the Add Remote sheet for confirmation.
- Existing behaviour of `.onOpenURL` for `file://` URLs (Finder open) must not change.
- Tests use XCTest and `@testable import`, matching `Tests/ReaderMdTests/`.

---

### Task 1: CLI target with pure argument → URL mapping

The whole risk surface of the CLI is here: path resolution and percent-encoding. Both are pure functions, so both get tests. Nothing in this task touches the app or the filesystem.

**Files:**
- Create: `Sources/ReaderCLI/ReaderCLI.swift`
- Create: `Sources/ReaderCLI/Route.swift`
- Modify: `Package.swift`
- Test: `Tests/ReaderMdTests/RouteTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum Command: Equatable` — `.open(path: String)`, `.remote(dest: String, path: String, name: String)`, `.remove(token: String)`, `.list`, `.stdin`, `.usage`
  - `enum Route` with `static func parse(_ args: [String], cwd: String) -> Command` and `static func url(for: Command) -> URL?`
  - `Route.scheme` = `"readermd"`, `Route.appDomain` = `"com.nahian.reader-md"`

- [ ] **Step 1: Add the executable target to `Package.swift`**

Replace the `targets:` array. `ReaderCLI` is a plain executable with no dependencies. `ReaderMdTests` gains a dependency on it so the CLI's pure logic is testable — the same `@testable import` of an executable target that `ReaderMdTests` already does for `ReaderMd`.

```swift
    products: [
        .executable(name: "reader", targets: ["ReaderCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "ReaderMd",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/ReaderMd",
            resources: [
                .copy("Resources/web"),
                .copy("Resources/docs"),
                .copy("Resources/AppIcon.png")
            ]
        ),
        .executableTarget(
            name: "ReaderCLI",
            path: "Sources/ReaderCLI"
        ),
        .testTarget(
            name: "ReaderMdTests",
            dependencies: ["ReaderMd", "ReaderCLI"],
            path: "Tests/ReaderMdTests"
        )
    ]
```

Add the `products:` block above `dependencies:` if the manifest has none (it currently does not).

- [ ] **Step 2: Write the failing tests**

Create `Tests/ReaderMdTests/RouteTests.swift`:

```swift
import XCTest
@testable import ReaderCLI

/// The CLI's whole risk surface is turning argv into a URL: path resolution and
/// percent-encoding. Both are pure, so both are pinned here.
final class RouteTests: XCTestCase {
    private let cwd = "/Users/x/proj"

    // MARK: - parse

    func testNoArgsIsUsage() {
        XCTAssertEqual(Route.parse([], cwd: cwd), .usage)
    }

    func testRelativePathResolvesAgainstCwd() {
        XCTAssertEqual(Route.parse(["notes.md"], cwd: cwd), .open(path: "/Users/x/proj/notes.md"))
    }

    func testDotResolvesToCwd() {
        XCTAssertEqual(Route.parse(["."], cwd: cwd), .open(path: "/Users/x/proj"))
    }

    func testAbsolutePathIsKept() {
        XCTAssertEqual(Route.parse(["/tmp/a.md"], cwd: cwd), .open(path: "/tmp/a.md"))
    }

    func testTrailingSlashIsStripped() {
        XCTAssertEqual(Route.parse(["/tmp/docs/"], cwd: cwd), .open(path: "/tmp/docs"))
    }

    func testTildeIsExpanded() {
        let home = NSHomeDirectory()
        XCTAssertEqual(Route.parse(["~/docs"], cwd: cwd), .open(path: "\(home)/docs"))
    }

    func testListAndStdinAndRemove() {
        XCTAssertEqual(Route.parse(["ls"], cwd: cwd), .list)
        XCTAssertEqual(Route.parse(["-"], cwd: cwd), .stdin)
        XCTAssertEqual(Route.parse(["rm", "docs"], cwd: cwd), .remove(token: "docs"))
    }

    func testRmWithoutTokenIsUsage() {
        XCTAssertEqual(Route.parse(["rm"], cwd: cwd), .usage)
    }

    func testRemoteParsesDestinationAndPathAndDerivesName() {
        XCTAssertEqual(
            Route.parse(["remote", "me@vps:/srv/docs"], cwd: cwd),
            .remote(dest: "me@vps", path: "/srv/docs", name: "docs")
        )
    }

    func testMalformedRemotesAreUsage() {
        // No colon, no user@, and a relative remote path are all unusable.
        XCTAssertEqual(Route.parse(["remote", "me@vps"], cwd: cwd), .usage)
        XCTAssertEqual(Route.parse(["remote", "vps:/srv/docs"], cwd: cwd), .usage)
        XCTAssertEqual(Route.parse(["remote", "me@vps:srv/docs"], cwd: cwd), .usage)
        XCTAssertEqual(Route.parse(["remote"], cwd: cwd), .usage)
    }

    func testUnknownFlagIsUsage() {
        XCTAssertEqual(Route.parse(["--wat"], cwd: cwd), .usage)
    }

    // MARK: - url

    func testOpenURL() {
        XCTAssertEqual(
            Route.url(for: .open(path: "/tmp/a.md"))?.absoluteString,
            "readermd://open?path=/tmp/a.md"
        )
    }

    /// The reason we hand-encode: URLComponents leaves `&` and `+` alone inside a
    /// query value (they are legal query delimiters), which would truncate the path.
    func testAmpersandAndSpaceInPathAreEncoded() {
        let url = Route.url(for: .open(path: "/tmp/a & b/n +1.md"))
        XCTAssertEqual(
            url?.absoluteString,
            "readermd://open?path=/tmp/a%20%26%20b/n%20%2B1.md"
        )
        // And it round-trips back to the original path.
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first(where: { $0.name == "path" })?.value, "/tmp/a & b/n +1.md")
    }

    func testRemoteURL() {
        let url = Route.url(for: .remote(dest: "me@vps", path: "/srv/docs", name: "docs"))
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(url?.host, "add-remote")
        XCTAssertEqual(items.first(where: { $0.name == "dest" })?.value, "me@vps")
        XCTAssertEqual(items.first(where: { $0.name == "path" })?.value, "/srv/docs")
        XCTAssertEqual(items.first(where: { $0.name == "name" })?.value, "docs")
    }

    func testRemoveURL() {
        XCTAssertEqual(
            Route.url(for: .remove(token: "docs"))?.absoluteString,
            "readermd://remove?match=docs"
        )
    }

    func testCommandsWithNoURL() {
        XCTAssertNil(Route.url(for: .list))
        XCTAssertNil(Route.url(for: .usage))
        XCTAssertNil(Route.url(for: .stdin))   // resolved to .open once the temp file exists
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter RouteTests`
Expected: FAIL — `no such module 'ReaderCLI'` (or `cannot find 'Route' in scope`) until Step 4 lands.

- [ ] **Step 4: Write the implementation**

Create `Sources/ReaderCLI/Route.swift`:

```swift
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
```

Create `Sources/ReaderCLI/ReaderCLI.swift` — the entry point. It must be `@main` in a file that is **not** named `main.swift`, or the target cannot be `@testable import`ed. Dispatch is a stub for now; Task 3 fills it in.

```swift
import Foundation

@main
struct ReaderCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = Route.parse(args, cwd: FileManager.default.currentDirectoryPath)

        switch command {
        case .usage:
            print(usage)
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
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter RouteTests`
Expected: PASS (17 tests).

Also run `swift build` and confirm both `ReaderMd` and `reader` link.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/ReaderCLI Tests/ReaderMdTests/RouteTests.swift
git commit -m "feat(cli): reader executable target with argv → readermd:// mapping"
```

---

### Task 2: `reader ls` — read the app's preferences

The bug this task exists to avoid: reading the *wrong preferences domain* and printing nothing, forever, while looking like it works. See the spec's "The CLI binary" section.

**Files:**
- Create: `Sources/ReaderCLI/Prefs.swift`
- Modify: `Sources/ReaderCLI/ReaderCLI.swift`
- Test: `Tests/ReaderMdTests/PrefsTests.swift`

**Interfaces:**
- Consumes: `Route.appDomain` (Task 1).
- Produces: `enum Prefs` with
  - `static func roots() -> [Root]` (hits `CFPreferences`)
  - `struct Root: Equatable { let name: String; let detail: String }`
  - `static func format(folders: [String], remotesJSON: Data?) -> [Root]` (pure — this is what the tests drive)

- [ ] **Step 1: Write the failing test**

Create `Tests/ReaderMdTests/PrefsTests.swift`:

```swift
import XCTest
@testable import ReaderCLI

final class PrefsTests: XCTestCase {
    func testLocalFoldersAreListedByBasename() {
        let roots = Prefs.format(folders: ["/Users/x/docs", "/tmp/notes"], remotesJSON: nil)
        XCTAssertEqual(roots, [
            Prefs.Root(name: "docs", detail: "/Users/x/docs"),
            Prefs.Root(name: "notes", detail: "/tmp/notes"),
        ])
    }

    func testRemotesAreListedWithTheirSSHTarget() {
        // Shape written by AppState.persistRemotes -> JSONEncoder on [RemoteSpec].
        let json = Data("""
        [{"id":"A1","name":"vps-docs","sshDestination":"me@vps","remotePath":"/srv/docs"}]
        """.utf8)
        let roots = Prefs.format(folders: [], remotesJSON: json)
        XCTAssertEqual(roots, [Prefs.Root(name: "vps-docs", detail: "me@vps:/srv/docs")])
    }

    func testFoldersAndRemotesTogether() {
        let json = Data("""
        [{"id":"A1","name":"vps-docs","sshDestination":"me@vps","remotePath":"/srv/docs"}]
        """.utf8)
        let roots = Prefs.format(folders: ["/tmp/notes"], remotesJSON: json)
        XCTAssertEqual(roots.count, 2)
        XCTAssertEqual(roots.last, Prefs.Root(name: "vps-docs", detail: "me@vps:/srv/docs"))
    }

    func testGarbageRemotesJSONIsIgnoredRatherThanCrashing() {
        XCTAssertEqual(Prefs.format(folders: [], remotesJSON: Data("not json".utf8)), [])
        XCTAssertEqual(Prefs.format(folders: [], remotesJSON: Data("[{}]".utf8)), [])
    }

    func testEmptyIsEmpty() {
        XCTAssertEqual(Prefs.format(folders: [], remotesJSON: nil), [])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter PrefsTests`
Expected: FAIL — `cannot find 'Prefs' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/ReaderCLI/Prefs.swift`:

```swift
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
}
```

Wire `.list` into `Sources/ReaderCLI/ReaderCLI.swift` — replace the `switch command` block:

```swift
        switch command {
        case .usage:
            print(usage)
        case .list:
            let roots = Prefs.roots()
            if roots.isEmpty {
                print("No folders. Add one with `reader <folder>`.")
            }
            let width = roots.map(\.name.count).max() ?? 0
            for root in roots {
                print("\(root.name.padding(toLength: width, withPad: " ", startingAt: 0))  \(root.detail)")
            }
        default:
            FileHandle.standardError.write(Data("not implemented yet\n".utf8))
            exit(1)
        }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter PrefsTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderCLI/Prefs.swift Sources/ReaderCLI/ReaderCLI.swift Tests/ReaderMdTests/PrefsTests.swift
git commit -m "feat(cli): reader ls — read roots from the app's preferences domain"
```

---

### Task 3: Dispatch — launch the app you came from, and wait for it

Two bugs are being designed out here, both silent-failure shaped: routing the URL to a *different* installed copy of the app, and exiting before the asynchronous launch has dispatched (a no-op that still exits 0).

**Files:**
- Create: `Sources/ReaderCLI/Dispatch.swift`
- Modify: `Sources/ReaderCLI/ReaderCLI.swift`
- Test: `Tests/ReaderMdTests/DispatchTests.swift`

**Interfaces:**
- Consumes: `Command`, `Route.url(for:)` (Task 1).
- Produces: `enum Dispatch` with
  - `static func appBundle(forExecutable: URL) -> URL?` (pure)
  - `static func send(_ url: URL) -> Bool` (side-effecting; blocks until the launch completes)

- [ ] **Step 1: Write the failing test**

Create `Tests/ReaderMdTests/DispatchTests.swift`. Only the bundle-resolution half is unit-testable; the `NSWorkspace` half is covered by the manual checks in Task 7.

```swift
import XCTest
@testable import ReaderCLI

final class DispatchTests: XCTestCase {
    func testExecutableInsideAppBundleResolvesToTheApp() {
        let exe = URL(fileURLWithPath: "/Applications/Reader.md.app/Contents/MacOS/reader")
        XCTAssertEqual(
            Dispatch.appBundle(forExecutable: exe)?.path,
            "/Applications/Reader.md.app"
        )
    }

    /// Dev builds live in .build/debug — there is no bundle to find, and the caller
    /// must fall back rather than guess.
    func testExecutableOutsideAnyBundleResolvesToNil() {
        let exe = URL(fileURLWithPath: "/Users/x/proj/.build/debug/reader")
        XCTAssertNil(Dispatch.appBundle(forExecutable: exe))
    }

    /// Two levels up must actually be an .app — not merely any directory.
    func testNonAppAncestorResolvesToNil() {
        let exe = URL(fileURLWithPath: "/opt/homebrew/Cellar/x/Contents/MacOS/reader")
        XCTAssertNil(Dispatch.appBundle(forExecutable: exe))
    }

    func testShallowPathDoesNotCrash() {
        XCTAssertNil(Dispatch.appBundle(forExecutable: URL(fileURLWithPath: "/reader")))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter DispatchTests`
Expected: FAIL — `cannot find 'Dispatch' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/ReaderCLI/Dispatch.swift`:

```swift
import Foundation
import AppKit

enum Dispatch {
    /// The .app this binary lives inside, derived from its own location:
    /// <app>/Contents/MacOS/reader -> <app>.
    ///
    /// Deliberately not `Bundle.main.bundleURL`: `reader` is not the bundle's
    /// CFBundleExecutable (that is `Reader.md`), so whether Bundle climbs to the
    /// enclosing .app from a *secondary* executable is an assumption. The path is
    /// something we control.
    static func appBundle(forExecutable executable: URL) -> URL? {
        let macOS = executable.deletingLastPathComponent()      // .../Contents/MacOS
        let contents = macOS.deletingLastPathComponent()        // .../Contents
        let app = contents.deletingLastPathComponent()          // .../Reader.md.app
        guard macOS.lastPathComponent == "MacOS",
              contents.lastPathComponent == "Contents",
              app.pathExtension == "app"
        else { return nil }
        return app
    }

    /// Hand the URL to the app. Returns false if no Reader.md could be launched.
    static func send(_ url: URL) -> Bool {
        // Homebrew's `binary` stanza puts a symlink on PATH, so resolve it before
        // walking up to the bundle.
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()

        guard let app = appBundle(forExecutable: executable) else {
            // Dev build outside any bundle: fall back to Launch Services, which
            // needs a packaged build to have been launched at least once.
            return NSWorkspace.shared.open(url)
        }

        // openURLs(...withApplicationAt:) is asynchronous. Returning from main()
        // before the completion handler fires means the launch never happens and
        // the command silently no-ops with exit 0 — so block on it.
        let semaphore = DispatchSemaphore(value: 0)
        var ok = false
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: app,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            ok = (error == nil)
            semaphore.signal()
        }
        return semaphore.wait(timeout: .now() + 20) == .success && ok
    }
}
```

Wire it into `Sources/ReaderCLI/ReaderCLI.swift` — replace the `default:` arm of the switch:

```swift
        case .open, .remote, .remove:
            guard let url = Route.url(for: command) else { exit(1) }
            guard Dispatch.send(url) else {
                fail("could not launch Reader.md")
            }
        case .stdin:
            FileHandle.standardError.write(Data("not implemented yet\n".utf8))
            exit(1)
        }
    }

    /// Message on stderr, exit 1 — the shell contract.
    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("reader: \(message)\n".utf8))
        exit(1)
    }
```

- [ ] **Step 4: Add local validation so bad paths get feedback, not silence**

The app ignores a `readermd://open` for a path that does not exist or is not markdown (it must — URLs also arrive from web pages). Without a local check the user would just see nothing happen. In `ReaderCLI.main()`, before the dispatch switch:

```swift
        if case .open(let path) = command {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                fail("no such file or folder: \(path)")
            }
            let markdown = ["md", "markdown", "mdown", "mdx"]
            if !isDirectory.boolValue, !markdown.contains((path as NSString).pathExtension.lowercased()) {
                fail("not a markdown file: \(path)")
            }
        }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter DispatchTests`
Expected: PASS (4 tests).

Run: `swift build && .build/debug/reader /nonexistent.md; echo "exit=$?"`
Expected: `reader: no such file or folder: /nonexistent.md` on stderr, `exit=1`.

- [ ] **Step 6: Commit**

```bash
git add Sources/ReaderCLI Tests/ReaderMdTests/DispatchTests.swift
git commit -m "feat(cli): dispatch readermd:// to the enclosing app bundle, blocking on the async launch"
```

---

### Task 4: `reader -` — pipe stdin into the app

**Files:**
- Create: `Sources/ReaderCLI/StdinDoc.swift`
- Modify: `Sources/ReaderCLI/ReaderCLI.swift`
- Test: `Tests/ReaderMdTests/StdinDocTests.swift`

**Interfaces:**
- Consumes: `Command.stdin` (Task 1), `Dispatch.send` (Task 3).
- Produces: `enum StdinDoc` with
  - `static let directory: URL` — `~/Library/Caches/com.nahian.reader-md/stdin`
  - `static func write(_ data: Data, now: TimeInterval, into: URL) throws -> URL`
  - `static func reap(in: URL, olderThan: TimeInterval, now: Date)`

- [ ] **Step 1: Write the failing test**

Create `Tests/ReaderMdTests/StdinDocTests.swift`:

```swift
import XCTest
@testable import ReaderCLI

final class StdinDocTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StdinDocTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// The .md extension is load-bearing: without it the app will not render the
    /// file as markdown, and the CLI's local validation would reject it too.
    func testWriteCreatesAMarkdownFileWithTheContent() throws {
        let url = try StdinDoc.write(Data("# hi".utf8), now: 1_700_000_000, into: tmp)
        XCTAssertEqual(url.pathExtension, "md")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# hi")
        XCTAssertTrue(url.path.hasPrefix(tmp.path))
    }

    func testReapDeletesOldTempsAndKeepsFreshOnes() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = try StdinDoc.write(Data("old".utf8), now: 1, into: tmp)
        let fresh = try StdinDoc.write(Data("fresh".utf8), now: 2, into: tmp)

        let fm = FileManager.default
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-2 * 86400)], ofItemAtPath: old.path)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: fresh.path)

        StdinDoc.reap(in: tmp, olderThan: 86400, now: now)

        XCTAssertFalse(fm.fileExists(atPath: old.path))
        XCTAssertTrue(fm.fileExists(atPath: fresh.path))
    }

    func testReapOnAMissingDirectoryIsNotAnError() {
        StdinDoc.reap(in: tmp.appendingPathComponent("nope"), olderThan: 86400, now: Date())
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter StdinDocTests`
Expected: FAIL — `cannot find 'StdinDoc' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/ReaderCLI/StdinDoc.swift`:

```swift
import Foundation

/// Piped markdown becomes a real file — the app renders files, not streams. The
/// CLI cannot delete it (the app may not have read it yet), so cleanup is a reap
/// of old temps on the next run.
enum StdinDoc {
    static let directory: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.nahian.reader-md/stdin", isDirectory: true)

    /// The `.md` extension is required: without it the app will not render the
    /// file as markdown.
    static func write(_ data: Data, now: TimeInterval, into directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(Int(now)).md")
        try data.write(to: url)
        return url
    }

    static func reap(in directory: URL, olderThan age: TimeInterval, now: Date) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for entry in entries {
            guard let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate else { continue }
            if now.timeIntervalSince(modified) > age {
                try? fm.removeItem(at: entry)
            }
        }
    }
}
```

Wire `.stdin` into `Sources/ReaderCLI/ReaderCLI.swift`, replacing its `not implemented yet` arm:

```swift
        case .stdin:
            let now = Date()
            StdinDoc.reap(in: StdinDoc.directory, olderThan: 86400, now: now)
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard !data.isEmpty else { fail("nothing on stdin") }
            guard let file = try? StdinDoc.write(data, now: now.timeIntervalSince1970, into: StdinDoc.directory),
                  let url = Route.url(for: .open(path: file.path))
            else { fail("could not write the piped document") }
            guard Dispatch.send(url) else { fail("could not launch Reader.md") }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter StdinDocTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderCLI Tests/ReaderMdTests/StdinDocTests.swift
git commit -m "feat(cli): pipe stdin into the app via a reaped cache temp"
```

---

### Task 5: App side — the `readermd://` router

The app learns the three verbs. Parsing is a pure function so it can be tested; the dispatch into `AppState` is three lines.

**Files:**
- Create: `Sources/ReaderMd/Models/ReaderURL.swift`
- Modify: `Sources/ReaderMd/ReaderMdApp.swift:23-25` (the `.onOpenURL` block)
- Modify: `Sources/ReaderMd/Models/AppState.swift` (add `pendingRemote`, `removeRoot(matching:)`, stdin-temp recents exclusion)
- Modify: `Sources/ReaderMd/Views/AddRemoteView.swift:11-16` (accept a prefill)
- Modify: `Sources/ReaderMd/Views/SidebarView.swift:130-132` (pass the prefill)
- Test: `Tests/ReaderMdTests/ReaderURLTests.swift`

**Interfaces:**
- Consumes: the URL shapes produced by `Route.url(for:)` (Task 1).
- Produces:
  - `enum ReaderURL` with `static func action(for url: URL) -> Action?`
  - `enum ReaderURL.Action: Equatable` — `.open(String)`, `.addRemote(RemoteSpec)`, `.remove(String)`
  - `AppState.pendingRemote: RemoteSpec?`, `AppState.removeRoot(matching token: String)`, `AppState.isStdinTemp(_:) -> Bool`

- [ ] **Step 1: Write the failing test**

Create `Tests/ReaderMdTests/ReaderURLTests.swift`:

```swift
import XCTest
@testable import ReaderMd

/// The router is the app's trust boundary: these URLs can arrive from a web page,
/// not just from our CLI.
final class ReaderURLTests: XCTestCase {
    private func action(_ string: String) -> ReaderURL.Action? {
        ReaderURL.action(for: URL(string: string)!)
    }

    func testOpen() {
        XCTAssertEqual(action("readermd://open?path=/tmp/a.md"), .open("/tmp/a.md"))
    }

    func testOpenDecodesPercentEncoding() {
        XCTAssertEqual(action("readermd://open?path=/tmp/a%20%26%20b.md"), .open("/tmp/a & b.md"))
    }

    func testRemove() {
        XCTAssertEqual(action("readermd://remove?match=docs"), .remove("docs"))
    }

    func testAddRemote() {
        guard case .addRemote(let spec)? = action("readermd://add-remote?dest=me@vps&path=/srv/docs&name=docs") else {
            return XCTFail("expected an addRemote action")
        }
        XCTAssertEqual(spec.sshDestination, "me@vps")
        XCTAssertEqual(spec.remotePath, "/srv/docs")
        XCTAssertEqual(spec.name, "docs")
    }

    func testUnknownVerbsAndMissingParamsAreRejected() {
        XCTAssertNil(action("readermd://sync?path=/tmp"))
        XCTAssertNil(action("readermd://open"))
        XCTAssertNil(action("readermd://open?path="))
        XCTAssertNil(action("readermd://remove"))
        XCTAssertNil(action("readermd://add-remote?dest=me@vps"))   // no path
        XCTAssertNil(action("https://example.com/open?path=/tmp/a.md"))  // wrong scheme
    }

    /// A relative or empty remote path is nonsense and must not reach the sheet.
    func testAddRemoteRequiresAnAbsoluteRemotePath() {
        XCTAssertNil(action("readermd://add-remote?dest=me@vps&path=srv/docs&name=docs"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ReaderURLTests`
Expected: FAIL — `cannot find 'ReaderURL' in scope`.

- [ ] **Step 3: Write the router**

Create `Sources/ReaderMd/Models/ReaderURL.swift`:

```swift
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
```

- [ ] **Step 4: Add the `AppState` entry points**

In `Sources/ReaderMd/Models/AppState.swift`, next to the other remote properties (`showAddRemote`, `editingRemote`):

```swift
    @Published var pendingRemote: RemoteSpec? = nil   // seeds the Add Remote sheet when it came from a URL
```

Below the existing `removeRoot(_:)`:

```swift
    /// Remove by whatever the user typed at the CLI: an absolute path, or a root's
    /// name. Remote roots can only be addressed by name — their `url` is an opaque
    /// cache directory keyed by UUID.
    func removeRoot(matching token: String) {
        let path = (token as NSString).expandingTildeInPath
        guard let root = roots.first(where: { $0.url.path == path })
                ?? roots.first(where: { $0.name == token })
        else { return }
        removeRoot(root)
    }
```

Next to `isBundledDoc`:

```swift
    /// Documents piped in with `reader -`. They live in a cache directory that gets
    /// reaped after a day, so keeping them out of recents avoids a list of dead paths.
    nonisolated static func isStdinTemp(_ url: URL) -> Bool {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return false
        }
        let dir = caches.appendingPathComponent("com.nahian.reader-md/stdin").standardizedFileURL.path
        return url.standardizedFileURL.path.hasPrefix(dir + "/")
    }
```

And in `open(_:)`, replace the recents line (currently `if !Self.isBundledDoc(node.url) { pushRecent(node.url.path) }`):

```swift
        if !Self.isBundledDoc(node.url), !Self.isStdinTemp(node.url) { pushRecent(node.url.path) }
```

- [ ] **Step 5: Route the URLs in `ReaderMdApp`**

In `Sources/ReaderMd/ReaderMdApp.swift`, replace the `.onOpenURL` modifier:

```swift
                .onOpenURL { url in
                    if url.isFileURL {
                        state.open(FileNode(url: url, isDirectory: false))
                        return
                    }
                    switch ReaderURL.action(for: url) {
                    case .open(let path):
                        // openDropped does the routing (folder -> root, markdown -> open)
                        // AND rejects non-markdown files — which is what keeps a hostile
                        // `readermd://open?path=/etc/passwd` from rendering.
                        state.openDropped(URL(fileURLWithPath: path))
                    case .addRemote(let spec):
                        // Never sync straight from a URL: rsync-over-ssh needs a human.
                        state.pendingRemote = spec
                        state.showAddRemote = true
                    case .remove(let token):
                        state.removeRoot(matching: token)
                    case nil:
                        break
                    }
                }
```

- [ ] **Step 6: Prefill the Add Remote sheet**

In `Sources/ReaderMd/Views/AddRemoteView.swift`, extend the initializer. `existing` still means *edit* (it saves with `updateRemote` and keeps the id); `prefill` seeds the fields of an ordinary *add*.

```swift
    init(existing: RemoteSpec? = nil, prefill: RemoteSpec? = nil) {
        self.existing = existing
        let seed = existing ?? prefill
        _name = State(initialValue: seed?.name ?? "")
        _destination = State(initialValue: seed?.sshDestination ?? "")
        _remotePath = State(initialValue: seed?.remotePath ?? "")
    }
```

In `Sources/ReaderMd/Views/SidebarView.swift`, pass it and clear it on dismiss:

```swift
        .sheet(isPresented: $state.showAddRemote, onDismiss: { state.pendingRemote = nil }) {
            AddRemoteView(prefill: state.pendingRemote).environmentObject(state)
        }
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test`
Expected: PASS — all suites, including the 7 new `ReaderURLTests`.

- [ ] **Step 8: Commit**

```bash
git add Sources/ReaderMd Tests/ReaderMdTests/ReaderURLTests.swift
git commit -m "feat(app): route readermd:// URLs to open, add-remote (confirmed), and remove"
```

---

### Task 6: Package the CLI into the `.app`

**Files:**
- Modify: `make-app.sh` (Info.plist `CFBundleURLTypes`; copy the `reader` binary before signing)

**Interfaces:**
- Consumes: the `reader` product (Task 1).
- Produces: `Reader.md.app/Contents/MacOS/reader`, and a bundle that declares the `readermd` scheme.

- [ ] **Step 1: Copy the CLI binary into the bundle**

In `make-app.sh`, directly after the line that copies the app executable (`cp "${EXE}" "${APP}/Contents/MacOS/${APP_NAME}"`):

```bash
# The `reader` CLI ships inside the bundle. It finds the app by walking up from
# its own path, so it must live at Contents/MacOS/reader — and it must be copied
# before codesign runs, since it is nested code that has to be sealed.
cp "${BIN_DIR}/reader" "${APP}/Contents/MacOS/reader"
```

- [ ] **Step 2: Declare the URL scheme**

In the `Info.plist` heredoc in `make-app.sh`, add this entry after the `UTImportedTypeDeclarations` array (before the closing `</dict>`):

```xml
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>${BUNDLE_ID}</string>
      <key>CFBundleURLSchemes</key>
      <array><string>readermd</string></array>
    </dict>
  </array>
```

- [ ] **Step 3: Build the app and verify the bundle**

Run: `./make-app.sh`

Then verify all three properties the CLI depends on:

```bash
test -x "build/Reader.md.app/Contents/MacOS/reader" && echo "binary: ok"
/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" build/Reader.md.app/Contents/Info.plist
codesign --verify --deep --strict build/Reader.md.app && echo "signature: ok"
```

Expected: `binary: ok`, `readermd`, `signature: ok`. The signature check is the one that matters — `reader` is a *second* Mach-O in `Contents/MacOS`, i.e. nested code that must be sealed rather than treated as a resource.

- [ ] **Step 4: Smoke-test the real thing**

```bash
open build/Reader.md.app          # launch once so Launch Services registers the scheme
build/Reader.md.app/Contents/MacOS/reader ls
build/Reader.md.app/Contents/MacOS/reader ~/Documents
build/Reader.md.app/Contents/MacOS/reader ls
```

Expected: the folder appears in the app's sidebar, and the second `ls` lists it. **If `ls` prints nothing after the folder is visibly in the sidebar, the preferences domain is wrong** — that is the exact failure the `CFPreferences` code in Task 2 exists to prevent, and it cannot reproduce under `swift run`.

- [ ] **Step 5: Commit**

```bash
git add make-app.sh
git commit -m "build: ship the reader CLI in the app bundle and register readermd://"
```

---

### Task 7: Install paths, docs, and end-to-end verification

**Files:**
- Modify: `Sources/ReaderMd/ReaderMdApp.swift` (the `.newItem` command group — add the install menu item)
- Create: `Sources/ReaderMd/Views/InstallCLI.swift`
- Modify: `Casks/reader-md.rb`
- Modify: `README.md`

**Interfaces:**
- Consumes: `Dispatch.appBundle`-style layout — the binary at `Contents/MacOS/reader` (Task 6).
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Write the install helper**

Create `Sources/ReaderMd/Views/InstallCLI.swift`. `/usr/local/bin` is `root:wheel drwxr-xr-x` on a stock macOS install, so the symlink usually *fails* — that is the expected path, not an edge case. The app does not escalate; it hands the user the one line to paste.

```swift
import AppKit

/// Puts `reader` on the user's PATH. Homebrew users get this for free (the cask's
/// `binary` stanza); this is for people who installed from the DMG.
enum InstallCLI {
    private static let target = "/usr/local/bin/reader"

    static func run() {
        // `URL.path` is already percent-decoded — do not decode it again, or a path
        // containing a literal `%` would be mangled.
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/reader").path
        let fm = FileManager.default

        if fm.fileExists(atPath: target) {
            alert(
                "`reader` is already installed",
                "\(target) already exists. Remove it first if you want to replace it."
            )
            return
        }

        do {
            try fm.createSymbolicLink(atPath: target, withDestinationPath: source)
            alert("Installed", "`reader` is on your PATH. Try `reader --help` in a terminal.")
        } catch {
            // The normal outcome: /usr/local/bin is root-owned. Don't escalate —
            // hand over the command instead.
            let command = "sudo ln -s \"\(source)\" \(target)"
            alertWithCopy(
                "Needs administrator access",
                "/usr/local/bin isn't writable by your user. Run this in a terminal:\n\n\(command)",
                copy: command
            )
        }
    }

    private static func alert(_ title: String, _ message: String) {
        let panel = NSAlert()
        panel.messageText = title
        panel.informativeText = message
        panel.runModal()
    }

    private static func alertWithCopy(_ title: String, _ message: String, copy command: String) {
        let panel = NSAlert()
        panel.messageText = title
        panel.informativeText = message
        panel.addButton(withTitle: "Copy Command")
        panel.addButton(withTitle: "Cancel")
        if panel.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }
}
```

- [ ] **Step 2: Add the menu item**

In `Sources/ReaderMd/ReaderMdApp.swift`, inside `CommandGroup(replacing: .newItem)`, after the `Reload` button:

```swift
                Divider()
                Button("Install `reader` Command Line Tool…") { InstallCLI.run() }
```

- [ ] **Step 3: Add the Homebrew `binary` stanza**

In `Casks/reader-md.rb`, after the `app` stanza:

```ruby
  app "Reader.md.app"
  binary "#{appdir}/Reader.md.app/Contents/MacOS/reader"
```

- [ ] **Step 4: Document the CLI in the README**

In `README.md`, add a `## Command line` section after "Keyboard shortcuts":

````markdown
## Command line

```
reader <file.md>                   open a markdown file
reader <folder>                    add a folder to the sidebar
reader .                           add the current directory
reader remote me@vps:/srv/docs     add a remote (SSH) folder — opens a confirmation sheet
reader ls                          list configured folders
reader rm <name|path>              remove a folder
git diff | reader -                open piped markdown
```

Homebrew puts `reader` on your PATH automatically. If you installed from the DMG, use
**File → Install `reader` Command Line Tool…**, and launch the app once first so macOS clears
quarantine from the bundle.

`reader` drives the app rather than replacing it: each command hands a `readermd://` URL to
Reader.md, which does the work. `reader ls` reads the app's saved folders directly, so a folder
added a moment ago may take a beat to appear.
````

- [ ] **Step 5: Full verification**

```bash
swift test                       # all suites green
./make-app.sh
```

Then, by hand — these are the checks no unit test reaches:

1. `open build/Reader.md.app`, add a folder in the GUI, then
   `build/Reader.md.app/Contents/MacOS/reader ls` → it lists that folder.
   *(Catches a wrong preferences domain and a stale `cfprefsd` cache.)*
2. `reader ~/some/folder` with the app **running** → the folder appears immediately.
3. Quit the app, then `reader ~/some/folder` again → the app launches and the folder appears.
4. With both `build/Reader.md.app` and an installed `/Applications/Reader.md.app` present, run the
   binary from *inside* `build/` → the **build** copy must come to the front, not the installed one.
   *(Catches Launch Services routing the URL to the wrong copy.)*
5. `reader ~/docs; echo "exit=$?"` → `exit=0`, and the folder actually appears.
   *(An exit before the async launch dispatches would print `exit=0` while doing nothing — check both.)*
6. `echo '# hi' | reader -` → renders, and the document does **not** show up in the sidebar's RECENTS.
7. `reader remote me@vps:/srv/docs` → the Add Remote sheet opens **prefilled**, and nothing syncs
   until it is accepted.
8. `reader rm <name>` for both a local folder and a remote → both disappear from the sidebar.
9. `reader /etc/passwd` → `reader: not a markdown file: /etc/passwd`, exit 1.

- [ ] **Step 6: Commit**

```bash
git add Sources/ReaderMd Casks/reader-md.rb README.md
git commit -m "feat(cli): install menu item, Homebrew binary stanza, and docs"
```

---

## Notes for the implementer

- **Do not** make the CLI write preferences, even though it would be easy. A running app holds `roots` in memory and re-persists the whole array on its next change — it would silently erase anything the CLI wrote.
- **Do not** replace `Route.url`'s hand-rolled percent-encoding with `URLComponents.queryItems`. `URLComponents` leaves `&`, `+` and `=` unescaped inside a query value, so a path containing one would truncate. `RouteTests.testAmpersandAndSpaceInPathAreEncoded` fails if this regresses.
- **Do not** switch `Dispatch` to `Bundle.main.bundleURL` or to shelling out to `/usr/bin/open`. The first assumes `Bundle` climbs correctly from a secondary executable; the second lets Launch Services choose which installed copy of Reader.md answers.
- `readermd://open?path=/` from a hostile web page will add `/` as a root, which means a whole-disk scan and a persistent watcher. This is a known, accepted cost (see the spec's Security section) — folder-add is deliberately **not** gated, because a confirmation prompt on every `reader .` would ruin the tool's main use. Do not "fix" it without revisiting the spec.
