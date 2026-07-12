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

    /// Where this binary actually lives. `Bundle.main.executableURL` is dyld-backed
    /// (not argv[0]), so it survives the case that matters: Homebrew puts a symlink
    /// on PATH, and the shell then passes argv[0] as the bare word "reader" — which
    /// `URL(fileURLWithPath:)` would resolve against the cwd, giving nonsense.
    /// Not `Bundle.main.bundleURL`: bundle-climbing from a *secondary* executable is
    /// an assumption we don't make. This only reports the Mach-O's own path.
    static func selfExecutable(bundleExecutable: URL?, argv0: String) -> URL {
        (bundleExecutable ?? URL(fileURLWithPath: argv0)).resolvingSymlinksInPath()
    }

    /// Hand the URL to the app. Returns false if no Reader.md could be launched.
    static func send(_ url: URL) -> Bool {
        let executable = selfExecutable(
            bundleExecutable: Bundle.main.executableURL,
            argv0: CommandLine.arguments[0]
        )

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
