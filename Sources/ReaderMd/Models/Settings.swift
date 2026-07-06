import Foundation
import AppKit

/// Lightweight persistence via UserDefaults.
enum Settings {
    private static let foldersKey = "reader.md.folders"
    private static let themeKey = "reader.md.theme"
    private static let showTOCKey = "reader.md.showTOC"
    private static let fontScaleKey = "reader.md.fontScale"
    private static let wideKey = "reader.md.wideReading"
    private static let showSidebarKey = "reader.md.showSidebar"
    private static let sidebarWidthKey = "reader.md.sidebarWidth"
    private static let recentsKey = "reader.md.recents"

    private static var defaults: UserDefaults { .standard }

    // Folders
    static func loadFolderPaths() -> [String] {
        defaults.stringArray(forKey: foldersKey) ?? []
    }
    static func saveFolderPaths(_ paths: [String]) {
        defaults.set(paths, forKey: foldersKey)
    }

    // Theme
    static func loadTheme() -> AppTheme {
        if let raw = defaults.string(forKey: themeKey), let theme = AppTheme(rawValue: raw) {
            return theme
        }
        // First launch: match the current system appearance.
        let isDark = NSApp?.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? .dark : .light
    }
    static func saveTheme(_ theme: AppTheme) {
        defaults.set(theme.rawValue, forKey: themeKey)
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

    static func loadWideReading() -> Bool {
        defaults.object(forKey: wideKey) as? Bool ?? false
    }
    static func saveWideReading(_ value: Bool) {
        defaults.set(value, forKey: wideKey)
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
}
