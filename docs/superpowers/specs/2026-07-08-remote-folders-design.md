# Remote Folders — Design

**Date:** 2026-07-08
**Status:** Approved, ready for planning
**Scope:** Read-only viewing of markdown that lives on a remote host (e.g. a VPS), via rsync-to-local-cache.

## Goal

Let a user add a remote folder (an SSH destination + a path on that host) to Reader.md and read its markdown as if it were local. Reader.md syncs the remote tree down to a stable local cache directory and registers that directory as an ordinary root, so the entire existing rendering/navigation/marks stack works unchanged.

Read-only. Reader.md never writes back to the remote.

## Why sync-to-cache (not mount, not native SFTP)

Three ways to reach remote files were considered:

1. **SSHFS / FUSE mount** — near-zero app code, but depends on macFUSE/FUSE-T, which on macOS 26 / Apple Silicon needs kext approval + reduced security + reboots. Fragile external dependency pushed onto the user's machine.
2. **Native SSH/SFTP in-app** — no external mount, but requires a full async rewrite of the foundation (every file read, `FolderWatcher`, image `file://` resolution, marks path-keys are synchronous and local today) plus in-app credential handling.
3. **Sync-to-cache via rsync** ✅ — the chosen approach.

The decisive point: **freshness is pull/poll for all three.** You cannot get FSEvents-style live change notification over SSH; detecting remote edits means polling no matter what. So native SFTP's implied "live browsing" advantage evaporates, while it still costs the entire async rewrite. Sync-to-cache keeps every downstream component untouched and reuses the user's existing SSH setup for credentials.

## Data flow

```
VPS:/srv/docs  ──rsync -e ssh──▶  <cacheDir>  ──▶  RootFolder (ordinary, tagged as remote)
                                       │
                                       └─ FileScanner, String(contentsOfFile:), image file:// ,
                                          FolderWatcher (FSEvents), quick-open, marks — all unchanged
```

`<cacheDir>` = `~/Library/Application Support/Reader.md/remotes/<id>/`, where `<id>` is stable per remote. A stable cache path matters because marks are keyed by `sha256(absolute path)` (see `MarkStore`), so a stable path means **marks survive every re-sync**.

Credentials: **none in-app.** `rsync -e ssh` reuses the user's `~/.ssh/config`, keys, and agent.

## Components

### `RemoteSpec` (new, `Codable, Identifiable`)
- `id: String` — stable identifier; derives `cacheURL`.
- `name: String` — display name in the sidebar.
- `sshDestination: String` — `user@host` (optionally with a port handled via ssh config or an appended field).
- `remotePath: String` — absolute path on the remote.
- `cacheURL: URL` — computed: `.../remotes/<id>/`.

Persisted as `[RemoteSpec]` (JSON) in `UserDefaults` via `Settings`, alongside the existing local folder paths.

### `RootFolder` (modified — `FileNode.swift`)
- Gains an optional `remote: RemoteSpec?` (nil = local; existing behavior unchanged).
- `name` prefers `remote?.name` when set.
- No change to scanning — it still scans `cacheURL` as a plain directory.

### `RemoteSync` (new helper)
- Builds and runs the `rsync` invocation as an async `Process`.
- Returns success or a failure carrying the tail of `rsync` stderr.
- Serializes concurrent syncs of the same remote (a second sync request while one is running is a no-op or queued).

### `AppState` (modified)
- `addRemote(_:)`, `syncRemote(_:)`, `removeRemote(_:)`.
- Persists `[RemoteSpec]`; recreates remote roots on launch and triggers background sync for each.
- Tracks per-remote sync status (idle / syncing / error) for the sidebar UI.

### `AddRemoteView` (new SwiftUI sheet)
- Fields: **Name**, **`user@host`**, **Remote path**. Nothing else.
- "Add" saves the spec and kicks off the first (user-initiated, loud-on-error) sync.

### Sidebar (modified — `SidebarView.swift`)
- The **"+"** affordance gains **"Add Remote Folder…"** next to the existing "Add Folder…".
- Remote roots show a small badge (SF Symbol, e.g. `cloud` / `network`) and a **re-sync button** with a spinner while running, plus a stale/error indicator when the last sync failed.

## The rsync invocation

```
rsync -az --delete --prune-empty-dirs -e ssh \
  --include='*/' \
  --include='*.md' --include='*.markdown' --include='*.mdown' --include='*.mdx' \
  --include='*.png' --include='*.jpg' --include='*.jpeg' --include='*.gif' --include='*.svg' --include='*.webp' \
  --exclude='node_modules' --exclude='.git' --exclude='.svn' \
  --exclude='dist' --exclude='build' --exclude='.next' --exclude='.cache' \
  --exclude='*' \
  user@host:/remote/path/  <cacheDir>/
```

- The markdown include list mirrors `FileScanner.markdownExtensions`; the excludes mirror `FileScanner.ignoredDirs`. Keep them derived from those sets so the two never drift.
- Image extensions are included so markdown-referenced local images resolve via the WebView's `file://` access.
- `--include='*/'` before `--exclude='*'` lets rsync descend into directories; `--prune-empty-dirs` drops folders that end up with no matching files, mirroring `FileScanner`'s "skip empty" behavior.
- **Verify on macOS 26 before promising flags** — confirm the shipped `rsync` accepts this invocation (macOS has moved toward openrsync); adjust if a flag isn't supported.

## Freshness behavior

- **Auto-sync on launch.** On start, each saved remote kicks off a **background sync** — non-blocking. The app is immediately usable showing the last cached content. When a sync finishes, FSEvents on the cache auto-reloads the open document (existing `reloadToken` path).
- **Quiet on launch failure.** If a launch sync fails (offline, host down, auth), keep the existing cache readable and mark that root with a **stale/error indicator**. No modal at startup.
- **Manual re-sync** stays available per remote root and, being user-initiated, **surfaces errors loudly** (alert with stderr tail).
- **First sync of a newly added remote** shows a spinner and surfaces errors loudly (user-initiated).

## Error handling

- Sync failures (host unreachable, auth failure, bad remote path, non-zero rsync exit) are captured with the tail of `rsync` stderr.
- User-initiated syncs (add, manual re-sync) show the error in an alert / inline status.
- A remote whose first sync fails is still saved so it can be retried; it shows an error state, never a silently empty folder.

## Decisions called out

- **Marks** are local, keyed to the stable cache path. They persist across re-syncs and are never pushed to the remote — they are the user's own annotations.
- **No live remote watching** — impossible over SSH without polling; auto-sync-on-launch + manual re-sync is the freshness model.
- **Precondition:** `rsync` and `ssh` on the Mac (both ship with macOS). Verify the exact `rsync` invocation on macOS 26 during implementation.
- **App is not sandboxed** (existing convention) — direct paths, no security-scoped bookmarks; the cache dir is a normal local directory the app already has access to.

## Explicitly deferred (YAGNI)

- Scheduled / periodic auto-poll while running (only launch + manual for now).
- Git-native clone/pull (rsync handles git repos and loose folders alike; skip git-specific handling).
- In-app credential / password entry (rely on ssh config + agent).
- Write-back / editing / two-way sync.
- Per-file lazy fetch instead of full-tree sync.
- Port / advanced ssh options as dedicated fields (rely on `~/.ssh/config` first).

## Testing

- `RemoteSync` command construction is pure and unit-testable: given a `RemoteSpec` and the scanner's extension/ignore sets, assert the exact `rsync` argument array. This is the one piece of non-trivial logic worth a test (the money/security-adjacent path is the shell invocation).
- The rest is UI/Process/FSEvents — verify by running the app against a real remote (or a local `sshd`/loopback destination).
