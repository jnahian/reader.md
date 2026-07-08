# Remote Folders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user add a remote (SSH) folder to Reader.md and read its markdown as if local, by rsync-ing the tree down to a stable local cache that registers as an ordinary root.

**Architecture:** A saved `RemoteSpec` (ssh destination + remote path) is synced via `rsync -e ssh` into `~/Library/Application Support/Reader.md/remotes/<id>/`. That cache dir is added as a normal `RootFolder` tagged with its `RemoteSpec`, so `FileScanner`, file reads, image `file://` resolution, `FolderWatcher`, quick-open, and marks all work unchanged. Read-only; credentials come from the user's `~/.ssh` setup, never in-app.

**Tech Stack:** Swift 6.2 / SwiftUI / AppKit, `Foundation.Process` shelling out to `/usr/bin/rsync` (Apple openrsync), `UserDefaults` persistence, `XCTest`.

**Spec:** `docs/superpowers/specs/2026-07-08-remote-folders-design.md`

## Global Constraints

- Deployment target macOS 13; any macOS 26-only API needs an availability guard. **None of the new code uses 26-only APIs, so no guards are required** — do not add them.
- App is **not sandboxed**; use direct paths, no security-scoped bookmarks.
- rsync binary is `/usr/bin/rsync` (Apple openrsync, protocol 29). Confirmed to support `-a -z --delete --prune-empty-dirs --include --exclude -e`.
- Cache path per remote must be **stable** (derived only from `RemoteSpec.id`) — marks are keyed by `sha256(absolute path)` and must survive re-syncs.
- Read-only: never write back to the remote.
- Match existing style: `Settings` enum for persistence, `@Published` on `AppState`/`RootFolder`, small focused SwiftUI views.

---

### Task 1: `RemoteSpec` model

**Files:**
- Create: `Sources/ReaderMd/Models/RemoteSpec.swift`
- Test: `Tests/ReaderMdTests/RemoteSpecTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct RemoteSpec: Codable, Identifiable, Equatable` with `let id: String`, `var name: String`, `var sshDestination: String`, `var remotePath: String`.
  - `init(id: String = UUID().uuidString, name: String, sshDestination: String, remotePath: String)`
  - `var cacheURL: URL` — `~/Library/Application Support/Reader.md/remotes/<id>` (stable per id).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ReaderMdTests/RemoteSpecTests.swift
import XCTest
@testable import ReaderMd

final class RemoteSpecTests: XCTestCase {
    func testCacheURLIsStableForSameID() {
        let a = RemoteSpec(id: "abc", name: "One", sshDestination: "u@h", remotePath: "/srv")
        let b = RemoteSpec(id: "abc", name: "Renamed", sshDestination: "x@y", remotePath: "/other")
        XCTAssertEqual(a.cacheURL, b.cacheURL, "cacheURL must depend only on id")
    }

    func testCacheURLContainsRemotesAndID() {
        let s = RemoteSpec(id: "xyz", name: "N", sshDestination: "u@h", remotePath: "/srv")
        XCTAssertTrue(s.cacheURL.path.hasSuffix("Reader.md/remotes/xyz"), s.cacheURL.path)
    }

    func testCodableRoundTrip() throws {
        let s = RemoteSpec(id: "id1", name: "Docs", sshDestination: "me@vps", remotePath: "/srv/docs")
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(RemoteSpec.self, from: data)
        XCTAssertEqual(s, back)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RemoteSpecTests`
Expected: FAIL — `cannot find 'RemoteSpec' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ReaderMd/Models/RemoteSpec.swift
import Foundation

/// A saved remote (SSH) folder: an ssh destination plus a path on that host.
/// Reader.md syncs it read-only into a stable local cache directory.
struct RemoteSpec: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var sshDestination: String   // "user@host"
    var remotePath: String       // absolute path on the remote

    init(id: String = UUID().uuidString, name: String, sshDestination: String, remotePath: String) {
        self.id = id
        self.name = name
        self.sshDestination = sshDestination
        self.remotePath = remotePath
    }

    /// Stable per-remote local cache directory. Depends only on `id` so it is
    /// unchanged across re-syncs — marks (keyed by sha256(path)) then survive.
    var cacheURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Reader.md/remotes/\(id)", isDirectory: true)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RemoteSpecTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderMd/Models/RemoteSpec.swift Tests/ReaderMdTests/RemoteSpecTests.swift
git commit -m "feat: RemoteSpec model with stable cache path"
```

---

### Task 2: `RemoteSync.arguments` — rsync argument builder

**Files:**
- Create: `Sources/ReaderMd/Models/RemoteSync.swift`
- Test: `Tests/ReaderMdTests/RemoteSyncTests.swift`

**Interfaces:**
- Consumes: `RemoteSpec` (Task 1); `FileScanner.markdownExtensions`, `FileScanner.ignoredDirs` (existing, in `FileNode.swift`).
- Produces:
  - `enum RemoteSync` with `static func arguments(for spec: RemoteSpec) -> [String]`
  - `static let imageExtensions: [String]` = `["png","jpg","jpeg","gif","svg","webp"]`

**Filter ordering (critical for rsync):** directory excludes must come **before** `--include=*/`, then file includes, then a final `--exclude=*`. rsync applies the first matching rule, so pruning `node_modules` etc. must be matched before the "descend into all dirs" rule.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ReaderMdTests/RemoteSyncTests.swift
import XCTest
@testable import ReaderMd

final class RemoteSyncTests: XCTestCase {
    private let spec = RemoteSpec(id: "t", name: "Docs", sshDestination: "me@vps", remotePath: "/srv/docs")

    func testStartsWithArchiveAndSSHTransport() {
        let a = RemoteSync.arguments(for: spec)
        XCTAssertEqual(Array(a.prefix(5)), ["-az", "--delete", "--prune-empty-dirs", "-e", "ssh"])
    }

    func testDirExcludesComeBeforeDescendInclude() {
        let a = RemoteSync.arguments(for: spec)
        let excludeNodeModules = try! XCTUnwrap(a.firstIndex(of: "--exclude=node_modules"))
        let descend = try! XCTUnwrap(a.firstIndex(of: "--include=*/"))
        XCTAssertLessThan(excludeNodeModules, descend, "dir excludes must precede --include=*/")
    }

    func testFileIncludesBetweenDescendAndFinalExclude() {
        let a = RemoteSync.arguments(for: spec)
        let descend = try! XCTUnwrap(a.firstIndex(of: "--include=*/"))
        let md = try! XCTUnwrap(a.firstIndex(of: "--include=*.md"))
        let png = try! XCTUnwrap(a.firstIndex(of: "--include=*.png"))
        let finalExclude = try! XCTUnwrap(a.firstIndex(of: "--exclude=*"))
        XCTAssertLessThan(descend, md)
        XCTAssertLessThan(md, finalExclude)
        XCTAssertLessThan(png, finalExclude)
    }

    func testSourceAndDestAreLastTwoWithTrailingSlashes() {
        let a = RemoteSync.arguments(for: spec)
        XCTAssertEqual(a[a.count - 2], "me@vps:/srv/docs/")
        XCTAssertEqual(a[a.count - 1], spec.cacheURL.path + "/")
    }

    func testRemotePathAlreadyTrailingSlashNotDoubled() {
        let s = RemoteSpec(id: "t", name: "D", sshDestination: "me@vps", remotePath: "/srv/docs/")
        let a = RemoteSync.arguments(for: s)
        XCTAssertEqual(a[a.count - 2], "me@vps:/srv/docs/")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RemoteSyncTests`
Expected: FAIL — `cannot find 'RemoteSync' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ReaderMd/Models/RemoteSync.swift
import Foundation

enum RemoteSync {
    /// Image types included so markdown-referenced local images resolve via
    /// the WebView's file:// access.
    static let imageExtensions = ["png", "jpg", "jpeg", "gif", "svg", "webp"]

    /// The rsync argument vector (excluding the "rsync" program name).
    /// Include-filter mirrors `FileScanner.markdownExtensions` + images;
    /// excludes mirror `FileScanner.ignoredDirs`.
    static func arguments(for spec: RemoteSpec) -> [String] {
        var args = ["-az", "--delete", "--prune-empty-dirs", "-e", "ssh"]
        // Dir excludes FIRST so pruned dirs are matched before "descend".
        for dir in FileScanner.ignoredDirs.sorted() {
            args.append("--exclude=\(dir)")
        }
        args.append("--include=*/")                      // descend into remaining dirs
        for ext in FileScanner.markdownExtensions.sorted() {
            args.append("--include=*.\(ext)")
        }
        for ext in imageExtensions {
            args.append("--include=*.\(ext)")
        }
        args.append("--exclude=*")                        // drop everything else
        args.append("\(spec.sshDestination):\(trailingSlash(spec.remotePath))")
        args.append(trailingSlash(spec.cacheURL.path))
        return args
    }

    private static func trailingSlash(_ p: String) -> String {
        p.hasSuffix("/") ? p : p + "/"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RemoteSyncTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderMd/Models/RemoteSync.swift Tests/ReaderMdTests/RemoteSyncTests.swift
git commit -m "feat: RemoteSync rsync argument builder"
```

---

### Task 3: `RemoteSync.run` — async rsync runner

**Files:**
- Modify: `Sources/ReaderMd/Models/RemoteSync.swift`

**Interfaces:**
- Consumes: `RemoteSync.arguments(for:)` (Task 2), `RemoteSpec.cacheURL` (Task 1).
- Produces:
  - `struct RemoteSyncResult { let success: Bool; let message: String }`
  - `static func run(_ spec: RemoteSpec) async -> RemoteSyncResult`

This step is I/O (Process + SSH), not unit-testable without a live remote — verified by running the app in Task 6/8. No new test file.

- [ ] **Step 1: Add the result type and runner**

Append to `Sources/ReaderMd/Models/RemoteSync.swift`:

```swift
struct RemoteSyncResult {
    let success: Bool
    let message: String   // "" on success; tail of rsync stderr on failure
}

extension RemoteSync {
    /// Runs rsync for `spec`, creating the cache dir first. Never throws;
    /// failures are returned as `RemoteSyncResult(success: false, ...)`.
    static func run(_ spec: RemoteSpec) async -> RemoteSyncResult {
        try? FileManager.default.createDirectory(at: spec.cacheURL, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = arguments(for: spec)
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: data, encoding: .utf8) ?? ""
                let tail = stderr.split(separator: "\n").suffix(4).joined(separator: "\n")
                let ok = proc.terminationStatus == 0
                continuation.resume(returning: RemoteSyncResult(
                    success: ok,
                    message: ok ? "" : (tail.isEmpty ? "rsync exited with code \(proc.terminationStatus)" : tail)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: RemoteSyncResult(
                    success: false, message: "Could not launch rsync: \(error.localizedDescription)"))
            }
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/ReaderMd/Models/RemoteSync.swift
git commit -m "feat: RemoteSync async rsync runner"
```

---

### Task 4: Persist remotes in `Settings`

**Files:**
- Modify: `Sources/ReaderMd/Models/Settings.swift`

**Interfaces:**
- Consumes: `RemoteSpec` (Task 1).
- Produces:
  - `static func loadRemotes() -> [RemoteSpec]`
  - `static func saveRemotes(_ specs: [RemoteSpec])`

- [ ] **Step 1: Add the key and accessors**

In `Sources/ReaderMd/Models/Settings.swift`, add the key next to `foldersKey`:

```swift
    private static let remotesKey = "reader.md.remotes"
```

And add these methods after the existing Folders section (after `saveFolderPaths`):

```swift
    // Remotes
    static func loadRemotes() -> [RemoteSpec] {
        guard let data = defaults.data(forKey: remotesKey),
              let specs = try? JSONDecoder().decode([RemoteSpec].self, from: data) else { return [] }
        return specs
    }
    static func saveRemotes(_ specs: [RemoteSpec]) {
        guard let data = try? JSONEncoder().encode(specs) else { return }
        defaults.set(data, forKey: remotesKey)
    }
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/ReaderMd/Models/Settings.swift
git commit -m "feat: persist remote specs in Settings"
```

---

### Task 5: Tag `RootFolder` as remote + sync status

**Files:**
- Modify: `Sources/ReaderMd/Models/FileNode.swift:71-88` (the `RootFolder` class)

**Interfaces:**
- Consumes: `RemoteSpec` (Task 1).
- Produces:
  - `enum RemoteSyncStatus: Equatable { case idle; case syncing; case failed(String) }`
  - `RootFolder` gains `let remote: RemoteSpec?`, `@Published var syncStatus: RemoteSyncStatus`, `var isRemote: Bool`, and `init(url:remote:)`. `id` = `remote?.id ?? url.path`; `name` = `remote?.name ?? url.lastPathComponent`.

Existing callers use `RootFolder(url:)` — the `remote` parameter defaults to `nil`, so they are unaffected.

- [ ] **Step 1: Add the status enum**

At the top of `Sources/ReaderMd/Models/FileNode.swift` (after `import Foundation`):

```swift
enum RemoteSyncStatus: Equatable {
    case idle
    case syncing
    case failed(String)
}
```

- [ ] **Step 2: Modify `RootFolder`**

Replace the `RootFolder` class body (lines 71-88) with:

```swift
/// One root folder shown in the sidebar. `remote` is non-nil when this root
/// is the local cache of a synced remote folder.
final class RootFolder: Identifiable, ObservableObject {
    let id: String
    let url: URL
    let remote: RemoteSpec?
    @Published var children: [FileNode]
    @Published var syncStatus: RemoteSyncStatus = .idle

    init(url: URL, remote: RemoteSpec? = nil) {
        self.id = remote?.id ?? url.path
        self.url = url
        self.remote = remote
        self.children = FileScanner.scan(url)
    }

    var name: String { remote?.name ?? url.lastPathComponent }
    var isRemote: Bool { remote != nil }

    func rescan() {
        children = FileScanner.scan(url)
    }
}
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: Builds with no errors (existing `RootFolder(url:)` calls still compile).

- [ ] **Step 4: Commit**

```bash
git add Sources/ReaderMd/Models/FileNode.swift
git commit -m "feat: tag RootFolder with RemoteSpec and sync status"
```

---

### Task 6: `AppState` remote wiring (add / sync / load-on-launch)

**Files:**
- Modify: `Sources/ReaderMd/Models/AppState.swift`

**Interfaces:**
- Consumes: `RemoteSpec` (Task 1), `RemoteSync.run` (Task 3), `Settings.loadRemotes`/`saveRemotes` (Task 4), `RootFolder(url:remote:)` + `syncStatus` (Task 5).
- Produces on `AppState`:
  - `@Published var showAddRemote: Bool`
  - `func addRemote(_ spec: RemoteSpec)`
  - `func syncRemote(_ spec: RemoteSpec) async`
  - existing `removeRoot(_:)` extended to also persist remotes; existing `persistRoots()` fixed to persist only local roots.

**Behavior:** `addRemote` registers the root + FSEvents watcher and kicks off a user-initiated sync. On launch, `loadSavedRemotes` registers each saved remote and kicks off a **background** sync (quiet on failure). `syncRemote` sets `syncStatus` and, on success, rescans the root and reloads the open doc if it lives under this root.

- [ ] **Step 1: Add the sheet-trigger property**

In the Overlays section of `AppState` (near `@Published var showQuickOpen`), add:

```swift
    @Published var showAddRemote: Bool = false
```

- [ ] **Step 2: Load saved remotes on launch**

In `init()`, add after `loadSavedRoots()`:

```swift
        loadSavedRemotes()
```

- [ ] **Step 3: Fix `persistRoots` to exclude remotes, and add remote methods**

Replace `persistRoots()` (currently lines ~232-234) with:

```swift
    private func persistRoots() {
        Settings.saveFolderPaths(roots.filter { $0.remote == nil }.map { $0.url.path })
    }

    private func persistRemotes() {
        Settings.saveRemotes(roots.compactMap { $0.remote })
    }

    // MARK: - Remote folders

    private func loadSavedRemotes() {
        for spec in Settings.loadRemotes() {
            registerRemote(spec)
            Task { await syncRemote(spec) }   // background auto-sync; quiet on failure
        }
    }

    func addRemote(_ spec: RemoteSpec) {
        guard !roots.contains(where: { $0.id == spec.id }) else { return }
        registerRemote(spec)
        persistRemotes()
        Task { await syncRemote(spec) }
    }

    /// Creates the cache dir, appends a remote-tagged root + FSEvents watcher.
    private func registerRemote(_ spec: RemoteSpec) {
        try? FileManager.default.createDirectory(at: spec.cacheURL, withIntermediateDirectories: true)
        roots.append(RootFolder(url: spec.cacheURL, remote: spec))
        let watcher = FolderWatcher(path: spec.cacheURL.path) { [weak self] in
            Task { @MainActor in self?.handleFolderChange() }
        }
        watchers.append(watcher)
    }

    func syncRemote(_ spec: RemoteSpec) async {
        guard let root = roots.first(where: { $0.id == spec.id }) else { return }
        root.syncStatus = .syncing
        let result = await RemoteSync.run(spec)
        if result.success {
            root.syncStatus = .idle
            root.rescan()
            if let file = selectedFile, file.url.path.hasPrefix(root.url.path + "/") {
                reloadToken += 1
            }
        } else {
            root.syncStatus = .failed(result.message)
        }
    }
```

- [ ] **Step 4: Persist remotes on removal and reorder**

In `removeRoot(_:)`, after the existing `persistRoots()` line, add:

```swift
        persistRemotes()
```

In `moveRoot(from:to:)`, after the existing `persistRoots()` line, add:

```swift
        persistRemotes()
```

- [ ] **Step 5: Verify it builds**

Run: `swift build`
Expected: Builds with no errors.

- [ ] **Step 6: Manual smoke test (real remote)**

Set up a reachable SSH target first (any host in `~/.ssh/config` you can `ssh` into passwordless, or `localhost` with Remote Login enabled and a folder of `.md` files). Then temporarily add a call in a scratch spot or wait for Task 7's UI. For now just confirm the app launches:

Run: `swift run`
Expected: App launches, existing local folders behave exactly as before (no remotes saved yet).

- [ ] **Step 7: Commit**

```bash
git add Sources/ReaderMd/Models/AppState.swift
git commit -m "feat: AppState add/sync/persist remote folders, auto-sync on launch"
```

---

### Task 7: Add Remote Folder sheet + sidebar trigger

**Files:**
- Create: `Sources/ReaderMd/Views/AddRemoteView.swift`
- Modify: `Sources/ReaderMd/Views/SidebarView.swift:82-100` (footer button → menu; add sheet)

**Interfaces:**
- Consumes: `AppState.addRemote` + `showAddRemote` (Task 6), `RemoteSpec` (Task 1).
- Produces: `struct AddRemoteView: View`.

- [ ] **Step 1: Create the sheet view**

```swift
// Sources/ReaderMd/Views/AddRemoteView.swift
import SwiftUI

struct AddRemoteView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var destination = ""
    @State private var remotePath = ""

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        destination.contains("@") &&
        remotePath.hasPrefix("/")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Remote Folder").font(.headline)
            Form {
                TextField("Name", text: $name)
                TextField("SSH  (user@host)", text: $destination)
                TextField("Remote path  (/srv/docs)", text: $remotePath)
            }
            Text("Uses your ~/.ssh config and keys. Read-only; synced to a local cache.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    state.addRemote(RemoteSpec(
                        name: name.trimmingCharacters(in: .whitespaces),
                        sshDestination: destination.trimmingCharacters(in: .whitespaces),
                        remotePath: remotePath.trimmingCharacters(in: .whitespaces)))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
```

- [ ] **Step 2: Turn the sidebar footer button into a menu and attach the sheet**

In `SidebarView.swift`, replace the footer `Button { state.pickFolders() } label: { ... }` (lines ~83-96) with a `Menu`:

```swift
                Menu {
                    Button("Add Folder…") { state.pickFolders() }
                    Button("Add Remote Folder…") { state.showAddRemote = true }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                        Text("Add Folder")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add a local or remote folder")
```

Then attach the sheet to the outer `VStack` — add next to the existing `.onChange(of: state.focusSearch)` modifier (line ~103):

```swift
        .sheet(isPresented: $state.showAddRemote) {
            AddRemoteView().environmentObject(state)
        }
```

- [ ] **Step 3: Verify it builds and the flow works**

Run: `swift run`
Steps: click the footer **Add Folder** menu → **Add Remote Folder…** → fill Name / `user@host` / `/path` for a reachable SSH host with `.md` files → **Add**.
Expected: sheet dismisses; a new root with your name appears under FOLDERS; after the background sync finishes its markdown files populate the tree and open/read normally. (Sync status/badge polish comes in Task 8.)

- [ ] **Step 4: Commit**

```bash
git add Sources/ReaderMd/Views/AddRemoteView.swift Sources/ReaderMd/Views/SidebarView.swift
git commit -m "feat: Add Remote Folder sheet and sidebar menu"
```

---

### Task 8: Remote root row — badge, re-sync button, error surfacing

**Files:**
- Modify: `Sources/ReaderMd/Views/SidebarView.swift` (the `RootSectionView` header `HStack`, lines ~176-196)

**Interfaces:**
- Consumes: `RootFolder.isRemote` / `remote` / `syncStatus` (Task 5), `AppState.syncRemote` (Task 6).
- Produces: nothing new (UI only).

**Behavior:** Remote roots show a cloud badge. While syncing → a small spinner. On the header, a re-sync button (`arrow.clockwise`) triggers a **user-initiated** sync that surfaces failures in an **alert** (loud). A failed launch sync shows a quiet inline red indicator with the message as tooltip (no alert).

- [ ] **Step 1: Add local state to `RootSectionView`**

In `struct RootSectionView`, add next to the existing `@State private var hovering = false`:

```swift
    @State private var syncError: String?
```

- [ ] **Step 2: Add the remote badge, status, and re-sync button to the header HStack**

In the header `HStack(spacing: 5)`, insert **after** the `Text(root.name)` line (line ~186) and **before** `Spacer(minLength: 4)`:

```swift
                if root.isRemote {
                    Image(systemName: "cloud")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .help("Remote folder")
                    switch root.syncStatus {
                    case .syncing:
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    case .failed(let msg):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .help(msg)
                    case .idle:
                        EmptyView()
                    }
                }
```

Then, inside the existing `if hovering { ... }` block, **before** the remove (`xmark`) button, add a re-sync button for remotes:

```swift
                    if let spec = root.remote {
                        Button {
                            Task {
                                await state.syncRemote(spec)
                                if case .failed(let msg) = root.syncStatus { syncError = msg }
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Re-sync")
                    }
```

- [ ] **Step 3: Attach the failure alert to the header HStack**

After the header `HStack`'s existing modifiers (after `.onDrop(...)` at line ~208), add:

```swift
            .alert("Sync failed", isPresented: Binding(
                get: { syncError != nil },
                set: { if !$0 { syncError = nil } }
            )) {
                Button("OK") { syncError = nil }
            } message: {
                Text(syncError ?? "")
            }
```

- [ ] **Step 4: Verify it builds and behaves**

Run: `swift run`
Steps:
1. With a remote added (Task 7), hover its header → cloud badge visible, `arrow.clockwise` + `xmark` appear.
2. Click re-sync → spinner shows while syncing, disappears on success; open doc reloads if it was under this root.
3. Break it: edit the remote's path to something invalid via a fresh Add, or disconnect network, then click re-sync → an **alert** appears with the rsync error tail.
4. Relaunch while offline → remote root shows the quiet orange warning triangle (tooltip = error), **no** alert; cached files still readable.

Expected: all four behave as described.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderMd/Views/SidebarView.swift
git commit -m "feat: remote root badge, re-sync button, and error surfacing"
```

---

## Self-Review Notes

**Spec coverage** — every spec section maps to a task:
- rsync sync-to-cache data flow → Tasks 2, 3, 6
- `RemoteSpec` + stable cache path (marks survive) → Task 1
- `RootFolder.remote` tag → Task 5
- `RemoteSync` builder + runner → Tasks 2, 3
- `Settings` persistence → Task 4
- `AddRemoteView` (3 fields) → Task 7
- Sidebar "Add Remote Folder…" + badge/re-sync → Tasks 7, 8
- rsync include/exclude mirroring FileScanner → Task 2
- Auto-sync on launch (quiet) + manual re-sync (loud) + first-add (loud) → Tasks 6, 8
- Error handling (stderr tail; retained-on-failure) → Tasks 3, 6, 8
- Marks local & stable → Task 1 (cache path) — no code change needed downstream
- Precondition rsync/ssh present → Global Constraints (verified `/usr/bin/rsync` openrsync)

**Deferred (not in any task, by design):** scheduled auto-poll, git-native clone/pull, in-app credentials, write-back/editing, per-file lazy fetch, dedicated port field.

**Type consistency:** `RemoteSpec`, `RemoteSyncStatus`, `RemoteSyncResult`, `RemoteSync.arguments(for:)`, `RemoteSync.run(_:)`, `AppState.addRemote(_:)`/`syncRemote(_:)`/`showAddRemote`, `RootFolder(url:remote:)`/`isRemote`/`syncStatus` — names used identically across Tasks 1–8.
