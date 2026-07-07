import SwiftUI

/// Native NSPopover content shown over the WKWebView: color swatches for a
/// highlight (#1), plus a note editor (#2) — an annotation is just a mark
/// with one note, so the same popover covers both. Shown on a fresh
/// selection or on tapping an existing highlight.
struct MarkPopoverView: View {
    var color: HighlightColor?      // nil on a fresh selection, no color chosen yet
    var existingNote: String?
    var onPickColor: (HighlightColor) -> Void
    var onSaveNote: (String) -> Void
    var onDeleteNote: (() -> Void)?
    var onRemoveMark: (() -> Void)?

    @State private var noteText: String
    @State private var showNoteField: Bool

    init(color: HighlightColor?, existingNote: String?,
         onPickColor: @escaping (HighlightColor) -> Void,
         onSaveNote: @escaping (String) -> Void,
         onDeleteNote: (() -> Void)?,
         onRemoveMark: (() -> Void)?) {
        self.color = color
        self.existingNote = existingNote
        self.onPickColor = onPickColor
        self.onSaveNote = onSaveNote
        self.onDeleteNote = onDeleteNote
        self.onRemoveMark = onRemoveMark
        _noteText = State(initialValue: existingNote ?? "")
        _showNoteField = State(initialValue: existingNote != nil)
    }

    private var trimmedNote: String { noteText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(HighlightColor.allCases, id: \.self) { c in
                    Button { onPickColor(c) } label: {
                        Circle()
                            .fill(c.swiftUIColor)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: color == c ? 2 : 0)
                                    .padding(-2)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Divider().frame(height: 18)

                Button {
                    showNoteField.toggle()
                } label: {
                    Image(systemName: existingNote == nil ? "note.text.badge.plus" : "note.text")
                        .font(.system(size: 13))
                        .foregroundStyle(existingNote == nil ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)

                if let onRemoveMark {
                    Button(action: onRemoveMark) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showNoteField {
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: $noteText)
                        .font(.system(size: 12))
                        .frame(width: 230, height: 64)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.1)))

                    HStack {
                        if existingNote != nil, let onDeleteNote {
                            Button("Delete", role: .destructive, action: onDeleteNote)
                                .font(.system(size: 11))
                        }
                        Spacer()
                        Button("Save") { onSaveNote(noteText) }
                            .font(.system(size: 11))
                            .disabled(trimmedNote.isEmpty)
                    }
                }
                .frame(width: 230)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
