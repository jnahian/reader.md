import Foundation
import Sparkle

/// Sparkle's updater, wrapped so **Check for Updates…** can't become a dead menu
/// item after an update session outlives the window it was showing.
///
/// `-[SPUUpdater checkForUpdates]` gives up silently whenever its driver still
/// reports `showingUpdate`: the call is handed to `-showUpdateInFocus`, whose
/// standard implementation falls through to nothing once the user driver has
/// torn its windows down. The session stays flagged, so from then on every click
/// of the menu item does nothing at all — no check, no window, no error, just a
/// line in the system log.
///
/// ``checkForUpdates()`` recovers by rebuilding the controller: releasing the old
/// updater aborts the stuck driver in `-[SPUUpdater dealloc]`, which is the only
/// way back from outside Sparkle. The rebuild is gated on ``userDriverFinished``
/// so a live alert, download, or install is left alone and simply refocused.
@MainActor
final class Updater: NSObject, ObservableObject {
    /// Only the packaged `.app` has a feed (`SUFeedURL` in Info.plist). Under
    /// `swift run` there's nothing to check and starting Sparkle would error, so
    /// the updater is never built and the menu item stays disabled.
    ///
    /// That is the *only* thing the menu item is disabled on. Sparkle's own
    /// `canCheckForUpdates` — what `SPUStandardUpdaterController.validateMenuItem:`
    /// greys AppKit menus out on — stays false for the whole of a silent
    /// background download, which would leave the item dead with nothing on
    /// screen to explain it.
    let hasFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil

    private var controller: SPUStandardUpdaterController?

    /// Whether the user driver has announced the end of its session. Together
    /// with a session Sparkle still believes is running, that's the wedge: the
    /// windows are gone, so there is nothing left for `-showUpdateInFocus` to
    /// bring forward. A healthy session only passes through the pair for the hop
    /// between the teardown and the driver's completion handler.
    private var userDriverFinished = false
    private var sessionObserver: NSKeyValueObservation?

    override init() {
        super.init()
        guard hasFeed else { return }
        start()
    }

    /// The **Check for Updates…** action.
    func checkForUpdates() {
        // Sparkle exposes no way to clear a stuck session — `resetUpdateCycle()`
        // deliberately does nothing while one is in progress — so the recovery is
        // to drop the updater holding it and check on its replacement.
        if isWedged { start() }
        controller?.updater.checkForUpdates()
    }

    /// Kept in its own scope rather than bound in ``checkForUpdates()``, so the
    /// updater it reads isn't named by a live local while ``start()`` drops the
    /// controller out from under it.
    private var isWedged: Bool {
        guard let updater = controller?.updater else { return false }
        return updater.sessionInProgress && userDriverFinished
    }

    /// Builds a fresh updater, replacing — and so aborting — any previous one.
    private func start() {
        sessionObserver = nil
        controller = nil
        userDriverFinished = false

        let fresh = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        // A session ending is the one thing that clears ``userDriverFinished``;
        // without it the first dismissal would mark every later session wedged.
        sessionObserver = fresh.updater.observe(\.sessionInProgress, options: [.new]) {
            [weak self] updater, _ in
            MainActor.assumeIsolated {
                if !updater.sessionInProgress { self?.userDriverFinished = false }
            }
        }
        controller = fresh
    }
}

// Sparkle calls this on the main thread (its user driver asserts as much), but
// the protocol itself carries no isolation — so it's `nonisolated` and hops back
// explicitly rather than making the whole conformance non-`@MainActor`.
extension Updater: SPUStandardUserDriverDelegate {
    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { self.userDriverFinished = true }
    }
}
