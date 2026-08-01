import Foundation

/// Lightweight persistence via UserDefaults.
enum Settings {
    private static let foldersKey = "reader.md.folders"
    private static let remotesKey = "reader.md.remotes"
    private static let themeKey = "reader.md.theme"
    private static let showTOCKey = "reader.md.showTOC"
    private static let fontScaleKey = "reader.md.fontScale"
    private static let wideKey = "reader.md.wideReading"   // legacy Bool; read once for migration
    private static let contentWidthKey = "reader.md.contentWidth"
    private static let showSidebarKey = "reader.md.showSidebar"
    private static let sidebarWidthKey = "reader.md.sidebarWidth"
    private static let recentsKey = "reader.md.recents"
    private static let showResolvedThreadsKey = "reader.md.showResolvedThreads"
    private static let readingThemeKey = "reader.md.readingTheme"
    private static let positionsKey = "reader.md.positions"
    private static let diffModeKey = "reader.md.diffMode"
    private static let diffScopeKey = "reader.md.diffScope"
    private static let editorBundleIDKey = "reader.md.editorBundleID"

    private static var defaults: UserDefaults { .standard }

    // Folders
    static func loadFolderPaths() -> [String] {
        defaults.stringArray(forKey: foldersKey) ?? []
    }
    static func saveFolderPaths(_ paths: [String]) {
        defaults.set(paths, forKey: foldersKey)
    }

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

    // Theme
    static func loadTheme() -> AppearanceMode {
        // First launch (or an unrecognized value): follow the system appearance.
        AppearanceMode(rawValue: defaults.string(forKey: themeKey) ?? "") ?? .system
    }
    static func saveTheme(_ theme: AppearanceMode) {
        defaults.set(theme.rawValue, forKey: themeKey)
    }

    // Reading theme (content-pane palette + fonts + syntax stylesheet)
    static func loadReadingTheme() -> ReadingTheme {
        ReadingTheme.named(defaults.string(forKey: readingThemeKey))
    }
    static func saveReadingTheme(_ theme: ReadingTheme) {
        defaults.set(theme.rawValue, forKey: readingThemeKey)
    }

    // Outline
    static func loadShowTOC() -> Bool {
        defaults.object(forKey: showTOCKey) as? Bool ?? false
    }
    static func saveShowTOC(_ value: Bool) {
        defaults.set(value, forKey: showTOCKey)
    }

    // Typography
    static func loadFontScale() -> Double {
        let v = defaults.double(forKey: fontScaleKey)
        return v == 0 ? 1.0 : v
    }
    static func saveFontScale(_ value: Double) {
        defaults.set(value, forKey: fontScaleKey)
    }

    /// Falls back to the old boolean `wideReading` key so an upgrade keeps the
    /// user's column choice.
    static func loadContentWidth() -> ContentWidth {
        if let raw = defaults.string(forKey: contentWidthKey),
           let w = ContentWidth(rawValue: raw) { return w }
        return (defaults.object(forKey: wideKey) as? Bool ?? false) ? .wide : .narrow
    }
    static func saveContentWidth(_ value: ContentWidth) {
        defaults.set(value.rawValue, forKey: contentWidthKey)
    }

    // Sidebar
    static func loadShowSidebar() -> Bool {
        defaults.object(forKey: showSidebarKey) as? Bool ?? true
    }
    static func saveShowSidebar(_ value: Bool) {
        defaults.set(value, forKey: showSidebarKey)
    }

    static func loadSidebarWidth() -> Double {
        let v = defaults.double(forKey: sidebarWidthKey)
        return v == 0 ? 260 : v
    }
    static func saveSidebarWidth(_ value: Double) {
        defaults.set(value, forKey: sidebarWidthKey)
    }

    // Recents
    static func loadRecents() -> [String] {
        defaults.stringArray(forKey: recentsKey) ?? []
    }
    static func saveRecents(_ paths: [String]) {
        defaults.set(paths, forKey: recentsKey)
    }

    // Reading positions: path -> scroll fraction (0...1)
    static func loadPositions() -> [String: Double] {
        defaults.dictionary(forKey: positionsKey) as? [String: Double] ?? [:]
    }
    static func savePositions(_ positions: [String: Double]) {
        defaults.set(positions, forKey: positionsKey)
    }

    // Comment threads (#3)
    static func loadShowResolvedThreads() -> Bool {
        defaults.object(forKey: showResolvedThreadsKey) as? Bool ?? true
    }
    static func saveShowResolvedThreads(_ value: Bool) {
        defaults.set(value, forKey: showResolvedThreadsKey)
    }

    // Diff mode: a sticky view mode, remembered across launches like the
    // other view preferences.
    static func loadDiffMode() -> Bool {
        defaults.object(forKey: diffModeKey) as? Bool ?? false
    }
    static func saveDiffMode(_ value: Bool) {
        defaults.set(value, forKey: diffModeKey)
    }

    /// Falls back to `.all` for an absent or unrecognized value, so a scope
    /// removed in a future version can't break startup.
    static func loadDiffScope() -> DiffScope {
        DiffScope(persisted: defaults.string(forKey: diffScopeKey) ?? "") ?? .all
    }
    static func saveDiffScope(_ value: DiffScope) {
        defaults.set(value.persisted, forKey: diffScopeKey)
    }

    /// External editor for "Open in Editor", stored as a bundle id so it survives
    /// the app being moved or updated. Set from Set Default Editor… or the
    /// Always Open With submenu.
    static func loadEditorBundleID() -> String? {
        defaults.string(forKey: editorBundleIDKey)
    }
    static func saveEditorBundleID(_ id: String?) {
        defaults.set(id, forKey: editorBundleIDKey)
    }
}
