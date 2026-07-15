import SwiftUI

/// Native NSPopover content shown over the WKWebView: color swatches for a
/// highlight (#1), plus a message thread (#2/#3) — an annotation is a mark
/// with one message, a comment thread is a mark with more, so the same
/// popover covers all three. Shown on a fresh selection or on tapping an
/// existing highlight.
struct MarkPopoverView: View {
    var color: HighlightColor?      // nil on a fresh selection, no color chosen yet
    var comments: [Comment]         // [] = no thread yet
    var resolved: Bool
    var onPickColor: (HighlightColor) -> Void
    var onReply: (String) -> Void           // appends a message (first one or a reply)
    var onDeleteThread: (() -> Void)?
    var onToggleResolved: (() -> Void)?
    var onRemoveMark: (() -> Void)?

    @State private var replyText: String = ""
    @State private var showThread: Bool

    init(color: HighlightColor?, comments: [Comment], resolved: Bool,
         onPickColor: @escaping (HighlightColor) -> Void,
         onReply: @escaping (String) -> Void,
         onDeleteThread: (() -> Void)?,
         onToggleResolved: (() -> Void)?,
         onRemoveMark: (() -> Void)?) {
        self.color = color
        self.comments = comments
        self.resolved = resolved
        self.onPickColor = onPickColor
        self.onReply = onReply
        self.onDeleteThread = onDeleteThread
        self.onToggleResolved = onToggleResolved
        self.onRemoveMark = onRemoveMark
        _showThread = State(initialValue: !comments.isEmpty)
    }

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

                // "No color" swatch — removes the highlight. Only on an existing
                // mark (nil onRemoveMark on a fresh selection, nothing to remove).
                if let onRemoveMark {
                    Button(action: onRemoveMark) {
                        ZStack {
                            Circle()
                                .fill(Color.clear)
                                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1))
                            Path { p in
                                p.move(to: CGPoint(x: 4, y: 16))
                                p.addLine(to: CGPoint(x: 16, y: 4))
                            }
                            .stroke(Color.secondary, lineWidth: 1.5)
                        }
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .dockTooltip("Remove highlight")
                }

                Divider().frame(height: 18)

                Button {
                    showThread.toggle()
                } label: {
                    Image(systemName: comments.isEmpty ? "note.text.badge.plus" : "bubble.left.and.text.bubble.right")
                        .font(.system(size: 13))
                        .foregroundStyle(comments.isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .dockTooltip(comments.isEmpty ? "Add a note" : "Show comments")
            }

            if showThread {
                threadBody
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var threadBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if resolved {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Resolved").font(.system(size: 11, weight: .medium))
                    Spacer()
                    if let onToggleResolved {
                        Button("Reopen", action: onToggleResolved).font(.system(size: 11))
                    }
                }
            }

            if !comments.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(comments) { comment in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(comment.author.isEmpty ? "Me" : comment.author)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(comment.text)
                                    .font(.system(size: 11))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(width: 230, height: min(CGFloat(comments.count) * 40 + 8, 140))
            }

            if !resolved {
                HStack(spacing: 6) {
                    TextField(comments.isEmpty ? "Add a note…" : "Reply…", text: $replyText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.1)))
                        .onSubmit(sendReply)

                    Button(action: sendReply) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            HStack {
                if !comments.isEmpty, let onDeleteThread {
                    Button("Delete", role: .destructive, action: onDeleteThread)
                        .font(.system(size: 10))
                }
                Spacer()
                if !comments.isEmpty, !resolved, let onToggleResolved {
                    Button("Resolve", action: onToggleResolved)
                        .font(.system(size: 11))
                }
            }
        }
        .frame(width: 230)
    }

    private func sendReply() {
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onReply(replyText)
        replyText = ""
    }
}
