import SwiftUI

/// The ⌘, window. A second face on preferences that already round-trip through
/// AppState — every control here has a twin in the toolbar or a menu, except
/// the PDF layout default, which had no home before.
struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: Binding(
                    get: { state.theme },
                    set: { state.setTheme($0) }
                )) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("Reading theme", selection: Binding(
                    get: { state.readingTheme },
                    set: { state.setReadingTheme($0) }
                )) {
                    ForEach(ReadingTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }

            Section("Reading") {
                // Continuous and already clamped to 0.7...1.6 by setFontScale;
                // a stepper would just be ⌘± with more clicks.
                LabeledContent("Text size") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { state.fontScale },
                                set: { state.setFontScale($0) }
                            ),
                            in: 0.7...1.6, step: 0.1
                        )
                        Text("\(Int((state.fontScale * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                Picker("Canvas width", selection: Binding(
                    get: { state.contentWidth },
                    set: { state.setContentWidth($0) }
                )) {
                    ForEach(ContentWidth.allCases, id: \.self) { width in
                        Text(width.displayName).tag(width)
                    }
                }
            }

            Section("Focus Mode") {
                Toggle("Enter fullscreen", isOn: Binding(
                    get: { state.focusFullscreen },
                    set: { state.setFocusFullscreen($0) }
                ))
                Toggle("Dim other sections", isOn: Binding(
                    get: { state.focusDimSections },
                    set: { state.setFocusDimSections($0) }
                ))
                Toggle("Narrow the canvas", isOn: Binding(
                    get: { state.focusNarrowCanvas },
                    set: { state.setFocusNarrowCanvas($0) }
                ))
                Toggle("Hide the toolbar", isOn: Binding(
                    get: { state.focusHideToolbar },
                    set: { state.setFocusHideToolbar($0) }
                ))

                // Every switch off is allowed rather than forbidden — but ⌥⌘F then
                // does nothing visible, which reads as a broken shortcut without a
                // word of explanation.
                if state.focusModeDoesNothing {
                    Text("With all four off, Focus Mode (⌥⌘F) has no visible effect.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Editing & Export") {
                LabeledContent("External editor") {
                    HStack {
                        // Falls back to the raw bundle id, not "None": an editor
                        // that has been uninstalled still has a stored id, and
                        // ⇧⌘E is still enabled off it. Saying "None" there would
                        // hide a setting the user can — and should — clear.
                        Text(state.editorDisplayName ?? state.editorBundleID ?? "None")
                            .foregroundStyle(state.editorDisplayName == nil ? .secondary : .primary)
                        Spacer()
                        if state.editorBundleID != nil {
                            Button("Clear") { state.clearEditor() }
                        }
                        Button("Choose…") { state.pickDefaultEditor() }
                    }
                }

                Picker("PDF layout", selection: Binding(
                    get: { state.exportLayout },
                    set: { state.setExportLayout($0) }
                )) {
                    ForEach(ExportLayout.allCases, id: \.self) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }
            }
        }
        .formStyle(.grouped)
        // A `Settings` scene's NSWindow autosaves its frame under a fixed key, so
        // a window last closed before this section existed reopens at its old
        // (shorter) height and clips it. minHeight floors AppKit's restore.
        .frame(minWidth: 420, maxWidth: 420, minHeight: 640)
    }
}
