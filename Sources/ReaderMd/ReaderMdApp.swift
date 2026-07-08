import SwiftUI
import AppKit
import Sparkle

// Auto-update via Sparkle. Only starts in the packaged .app (SUFeedURL in
// Info.plist); nil under `swift run` so dev launches don't error on a missing feed.
private let updaterController: SPUStandardUpdaterController? = {
    guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return nil }
    return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
}()

@main
struct ReaderMdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Reader.md") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 720, minHeight: 460)
                .preferredColorScheme(state.theme.colorScheme)
                .onOpenURL { url in
                    if url.isFileURL { state.open(FileNode(url: url, isDirectory: false)) }
                }
                .onAppear { state.checkWhatsNew() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Reader.md") { showAboutPanel() }
                Button("Check for Updates…") { updaterController?.checkForUpdates(nil) }
                    .disabled(updaterController == nil)
            }

            CommandGroup(replacing: .newItem) {
                Button("Open File…") { state.pickFile() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Add Folder…") { state.pickFolders() }
                Button("Quick Open…") { state.showQuickOpen = true }
                    .keyboardShortcut("p", modifiers: .command)
                Divider()
                Button("Export as PDF…") { state.triggerExport() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(state.selectedFile == nil)
                Button("Reload") { state.triggerReload() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(state.selectedFile == nil)
            }

            CommandMenu("Find") {
                Button("Find in Page") {
                    state.showFind = true
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Find Next") { state.triggerFindNext() }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(!state.showFind)
                Button("Find Previous") { state.triggerFindPrev() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(!state.showFind)
                Divider()
                Button("Filter Files") { state.focusSearch.toggle() }
                    .keyboardShortcut("f", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") { state.toggleSidebar() }
                    .keyboardShortcut("\\", modifiers: .command)
                Button("Toggle Outline") { state.setShowTOC(!state.showTOC) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("Increase Text") { state.adjustFontScale(0.1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Decrease Text") { state.adjustFontScale(-0.1) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { state.resetFontScale() }
                    .keyboardShortcut("0", modifiers: .command)
                Button(state.wideReading ? "Narrow Column" : "Wide Column") { state.toggleWideReading() }
                Divider()
            }

            CommandMenu("Go") {
                Button("Back") { state.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!state.canGoBack)
                Button("Forward") { state.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!state.canGoForward)
            }

            CommandGroup(replacing: .help) {
                Button("Reader.md FAQ") { state.openBundledDoc("FAQ") }
                Button("Keyboard Shortcuts") { state.openBundledDoc("SHORTCUTS") }
                    .keyboardShortcut("/", modifiers: .command)
                Button("Release Notes") { state.openBundledDoc("CHANGELOG") }
                Divider()
                Button("Report an Issue…") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/jnahian/reader.md/issues/new")!)
                }
                Button("View on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/jnahian/reader.md")!)
                }
            }
        }
    }
}

// ponytail: fallback version for `swift run` (no Info.plist); keep in sync with make-app.sh.
private func showAboutPanel() {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "1.4.0"
    let build = info?["CFBundleVersion"] as? String ?? "dev"
    let credits = NSAttributedString(
        string: "A native macOS markdown viewer.\nMermaid & LaTeX, live reload, PDF export.",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: "Reader.md",
        .applicationVersion: version,
        .version: build,
        .credits: credits,
    ])
    NSApp.activate(ignoringOtherApps: true)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.resources.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
