import XCTest
@testable import ReaderMd

/// Favorites are the sidebar's pinned list: ordered by the user, persisted, and
/// closed to the documents that aren't really the user's (bundled help, piped stdin).
@MainActor
final class FavoritesTests: XCTestCase {
    private var saved: [String] = []
    private var savedRecents: [String] = []

    override func setUp() async throws {
        // These tests share the app's real UserDefaults — put the user's own
        // favorites (and the recents that opening a file writes) back afterwards.
        saved = Settings.loadFavorites()
        savedRecents = Settings.loadRecents()
        Settings.saveFavorites([])
    }

    override func tearDown() async throws {
        Settings.saveFavorites(saved)
        Settings.saveRecents(savedRecents)
    }

    func testPinningAppendsAndSurvivesARelaunch() {
        let state = AppState()
        state.addFavorite("/notes/a.md")
        state.addFavorite("/notes/b.md")

        // Appended, not inserted: pinning must not reshuffle the list.
        XCTAssertEqual(state.favoriteFiles, ["/notes/a.md", "/notes/b.md"])
        // A fresh AppState is what a relaunch actually sees.
        XCTAssertEqual(AppState().favoriteFiles, ["/notes/a.md", "/notes/b.md"])
    }

    func testPinningTwiceIsANoOp() {
        let state = AppState()
        state.addFavorite("/notes/a.md")
        state.addFavorite("/notes/a.md")
        XCTAssertEqual(state.favoriteFiles, ["/notes/a.md"])
    }

    func testToggleAddsThenRemoves() {
        let state = AppState()
        state.toggleFavorite("/notes/a.md")
        XCTAssertTrue(state.isFavorite("/notes/a.md"))
        state.toggleFavorite("/notes/a.md")
        XCTAssertFalse(state.isFavorite("/notes/a.md"))
        XCTAssertEqual(AppState().favoriteFiles, [])
    }

    /// The drag-reorder delegate passes an insertion index in the pre-move list,
    /// the way `move(fromOffsets:toOffset:)` counts — moving down has to land
    /// after the target, not before it.
    func testReorderMovesInBothDirections() {
        let state = AppState()
        ["a", "b", "c"].forEach { state.addFavorite("/notes/\($0).md") }

        state.moveFavorite(from: 0, to: 2)   // a between b and c
        XCTAssertEqual(state.favoriteFiles, ["/notes/b.md", "/notes/a.md", "/notes/c.md"])

        state.moveFavorite(from: 2, to: 0)   // c to the front
        XCTAssertEqual(state.favoriteFiles, ["/notes/c.md", "/notes/b.md", "/notes/a.md"])
        XCTAssertEqual(AppState().favoriteFiles, state.favoriteFiles)
    }

    func testOutOfRangeReorderIsIgnored() {
        let state = AppState()
        state.addFavorite("/notes/a.md")
        state.moveFavorite(from: 5, to: 0)
        state.moveFavorite(from: 0, to: 9)
        XCTAssertEqual(state.favoriteFiles, ["/notes/a.md"])
    }

    /// Same rule that keeps them out of Recents: a bundled help doc ships with the
    /// app and a piped document is reaped after a day — neither is pinnable.
    func testBundledDocsAndStdinTemporariesCannotBePinned() throws {
        let faq = try XCTUnwrap(
            Bundle.resources.url(forResource: "FAQ", withExtension: "md", subdirectory: "docs"))
        let caches = try XCTUnwrap(
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let piped = caches
            .appendingPathComponent("com.nahian.reader-md/stdin/piped.md")

        XCTAssertFalse(AppState.canFavorite(faq))
        XCTAssertFalse(AppState.canFavorite(piped))
        XCTAssertTrue(AppState.canFavorite(URL(fileURLWithPath: "/Users/someone/notes/a.md")))

        let state = AppState()
        state.addFavorite(faq.path)
        state.addFavorite(piped.path)
        XCTAssertEqual(state.favoriteFiles, [])
    }

    /// Opening a pinned file still records its recency (⌘P ranks by it), but the
    /// sidebar lists it under Favorites only — Recents sits above Favorites, so a
    /// row in both reads as the pin having jumped out of the list.
    func testOpeningAPinnedFileKeepsItOutOfTheRecentsSection() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("favorites-\(UUID().uuidString).md")
        try "# Doc".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let state = AppState()
        state.addFavorite(url.path)
        state.open(FileNode(url: url, isDirectory: false))

        XCTAssertEqual(state.favoriteFiles, [url.path])
        XCTAssertEqual(state.recentFiles.first, url.path, "recency is still recorded for ⌘P")
        XCTAssertFalse(state.unpinnedRecents.contains(url.path))

        // Unpinning puts it back in Recents where it left off.
        state.removeFavorite(url.path)
        XCTAssertEqual(state.unpinnedRecents.first, url.path)
    }

    func testMenuTitleFollowsTheOpenDocument() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("favorites-\(UUID().uuidString).md")
        try "# Doc".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let state = AppState()
        XCTAssertFalse(state.canFavoriteCurrentFile, "nothing open — the menu item stays disabled")

        state.open(FileNode(url: url, isDirectory: false))
        XCTAssertTrue(state.canFavoriteCurrentFile)
        XCTAssertEqual(state.favoriteMenuTitle, "Add to Favorites")

        state.toggleFavoriteCurrentFile()
        XCTAssertTrue(state.currentFileIsFavorite)
        XCTAssertEqual(state.favoriteMenuTitle, "Remove from Favorites")
    }
}
