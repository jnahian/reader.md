import Foundation
import Sparkle

/// Sparkle's updater, wrapped so **Check for Updates…** can't become a dead menu
/// item after the first prompt is dismissed.
///
/// `-[SPUUpdater checkForUpdates]` gives up silently whenever the updater still
/// believes a session is open. It returns early on `sessionInProgress`, and on
/// `driver.showingUpdate` it hands off to `-showUpdateInFocus`, whose standard
/// implementation falls through to nothing once the user driver has torn its
/// windows down. Cancelling the first prompt can leave exactly that state
/// behind — session still flagged, no window left to focus — and from then on
/// every click of the menu item did nothing at all: no check, no window, no
/// error, just a line in the system log.
///
/// AppKit normally hides this, because `SPUStandardUpdaterController` implements
/// `validateMenuItem:` and greys the item out while a check can't be made.
/// SwiftUI menus never validate, so the item stayed enabled and the app
/// inherited the silent failure. Hence the two halves below: ``canCheck``
/// mirrors Sparkle's own `canCheckForUpdates` for `.disabled`, and
/// ``checkForUpdates()`` rebuilds the controller when it finds a session that
/// outlived its UI — releasing the old updater aborts the stuck driver in
/// `-[SPUUpdater dealloc]`, which is the only way back from outside Sparkle.
@MainActor
final class Updater: NSObject, ObservableObject {
    /// Whether the menu item should be clickable. False while a check is in
    /// flight — and always false with no feed to check.
    @Published private(set) var canCheck = false

    /// Only the packaged `.app` has a feed (`SUFeedURL` in Info.plist). Under
    /// `swift run` there's nothing to check and starting Sparkle would error, so
    /// the updater is never built and the menu item stays disabled.
    private let hasFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil

    private var controller: SPUStandardUpdaterController?
    private var canCheckObserver: NSKeyValueObservation?

    /// Whether Sparkle currently owns update UI — the alert, a download, an
    /// install. Set between the two user-driver callbacks in the extension
    /// below. A session in progress while this is false is a session with
    /// nothing on screen, which is the wedge ``checkForUpdates()`` recovers from.
    private var showingUpdate = false

    override init() {
        super.init()
        guard hasFeed else { return }
        start()
    }

    /// The **Check for Updates…** action.
    func checkForUpdates() {
        guard let current = controller?.updater else { return }
        // A session that no longer has UI behind it will never be handed to a new
        // check, and Sparkle exposes no way to clear one — `resetUpdateCycle()`
        // deliberately does nothing while a session is in progress. Rebuilding
        // does clear it: the outgoing updater aborts its driver as it deallocates.
        //
        // Guarded on `showingUpdate` so a real update session is left alone: with
        // the alert up or a download running, the call below reaches Sparkle's
        // `-showUpdateInFocus` and just brings that window forward, which is the
        // right answer and much better than restarting a download.
        if current.sessionInProgress && !showingUpdate {
            start()
        }
        // Re-read through `controller` rather than reusing `current`: `start()`
        // just replaced it, and the check has to reach the new updater rather
        // than the wedged one it dropped.
        controller?.updater.checkForUpdates()
    }

    /// Builds a fresh updater, replacing — and so aborting — any previous one.
    private func start() {
        // Released before the replacement starts, so two updaters never share the
        // same host bundle, and so the old one's driver is aborted in its dealloc.
        canCheckObserver = nil
        controller = nil
        showingUpdate = false

        let fresh = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        // `.initial` seeds `canCheck`, which starts false so the item is disabled
        // for the tick before Sparkle reports in.
        canCheckObserver = fresh.updater.observe(
            \.canCheckForUpdates, options: [.initial, .new]
        ) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
        }
        controller = fresh
    }
}

// Sparkle calls these on the main thread (its user driver asserts as much), but
// the protocol itself carries no isolation — so they're `nonisolated` and hop
// back explicitly rather than making the whole conformance non-`@MainActor`.
extension Updater: SPUStandardUserDriverDelegate {
    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated { self.showingUpdate = true }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { self.showingUpdate = false }
    }
}
