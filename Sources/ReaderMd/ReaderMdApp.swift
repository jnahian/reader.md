import SwiftUI
import AppKit

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
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
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
        }
    }
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
