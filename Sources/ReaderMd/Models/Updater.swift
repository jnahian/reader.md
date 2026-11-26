import AppKit

/// Tells the user when a newer release is out and links to its page on GitHub.
/// It never downloads or installs anything. Reader.md updated itself through
/// Sparkle until 1.24.0; its signing key was lost, and an ad-hoc-signed app can't
/// rotate one, so the update is now the user's to download.
@MainActor
enum Updater {
    /// Only the packaged `.app` has a version in its Info.plist. Under `swift run`
    /// there's nothing to compare, so no check runs and the menu item is disabled.
    static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    private static let latestRelease = URL(string: "https://api.github.com/repos/jnahian/reader.md/releases/latest")!
    private static let interval: TimeInterval = 24 * 60 * 60
    private static var checking = false

    /// At launch and on each return to the app: checks at most once a day, and
    /// says nothing unless there is an update. The time is saved when a check
    /// starts, so a failed check waits a day too instead of retrying on every
    /// return to the app.
    static func checkIfDue() {
        if let last = Settings.loadLastUpdateCheck(), Date().timeIntervalSince(last) < interval { return }
        check(userInitiated: false)
    }

    /// **Check for Updates…**: also says when there's nothing new, or the check failed.
    static func checkNow() {
        check(userInitiated: true)
    }

    private static func check(userInitiated: Bool) {
        guard let current = currentVersion, !checking else { return }
        checking = true
        Settings.saveLastUpdateCheck(Date())
        Task {
            defer { checking = false }
            do {
                let release = try await fetchLatest()
                if isNewer(release.tagName, than: current) {
                    offer(release, current: current)
                } else if userInitiated {
                    alert("Reader.md is up to date", "\(current) is the newest version.")
                }
            } catch {
                if userInitiated {
                    alert("Couldn't check for updates", error.localizedDescription)
                }
            }
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlUrl: URL
    }

    private static func fetchLatest() async throws -> Release {
        var request = URLRequest(url: latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Release.self, from: data)
    }

    private static func offer(_ release: Release, current: String) {
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        let panel = NSAlert()
        panel.messageText = "Reader.md \(version) is available"
        panel.informativeText = "You have \(current). Download the new version from its release page and replace the app in Applications. As with the first install, macOS asks you to approve it the first time it opens."
        panel.addButton(withTitle: "Download…")
        panel.addButton(withTitle: "Later")
        if panel.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlUrl)
        }
    }

    private static func alert(_ title: String, _ message: String) {
        let panel = NSAlert()
        panel.messageText = title
        panel.informativeText = message
        panel.runModal()
    }

    /// Whether a release tag (`v1.24.0`) names a later version than `current`
    /// (`1.23.0`), compared part by part as numbers, so 1.10 is later than 1.9. A
    /// tag that isn't plain dotted numbers is never newer.
    nonisolated static func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int]? {
            let trimmed = version.hasPrefix("v") ? version.dropFirst() : Substring(version)
            let numbers = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
            guard !numbers.isEmpty, !numbers.contains(nil) else { return nil }
            return numbers.compactMap { $0 }
        }
        guard let new = parts(tag), let old = parts(current) else { return false }
        for i in 0..<max(new.count, old.count) {
            let a = i < new.count ? new[i] : 0
            let b = i < old.count ? old[i] : 0
            if a != b { return a > b }
        }
        return false
    }
}
