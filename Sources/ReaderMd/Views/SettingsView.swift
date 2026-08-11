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
        .frame(width: 420)
    }
}
