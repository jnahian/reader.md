import SwiftUI

struct TOCView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var reading: ReadingState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OUTLINE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    // Rail + sliding marker realized per-row via a leading capsule.
                    VStack(alignment: .leading, spacing: 2) {
                        // Suppresses a stale outline left over from the mode just
                        // exited (e.g. hunk rows lingering after diff mode turns
                        // off) until the fresh entries for the new mode arrive.
                        if state.tocIsDiffOutline == state.canShowDiff {
                            ForEach(state.toc) { entry in
                                TOCRow(entry: entry, active: entry.id == reading.activeHeadingID)
                                    .id(entry.id)
                                    .onTapGesture { state.requestScroll(to: entry.id) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.trailing, 8)
                }
                .onChange(of: reading.activeHeadingID) { id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(GlassPanel())
    }
}

private struct TOCRow: View {
    let entry: TOCEntry
    let active: Bool

    var body: some View {
        HStack(spacing: 0) {
            // sliding rail marker: a capsule that only appears on the active row
            RoundedRectangle(cornerRadius: 2)
                .fill(active ? Color.accentColor : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 2)

            Text(entry.text)
                .font(.system(size: 12.5, weight: entry.level == 1 ? .semibold : .regular))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .lineLimit(1)
                .padding(.leading, CGFloat(entry.level - 1) * 12 + 10)
                .padding(.vertical, 3)

            Spacer(minLength: 6)

            if let detail = entry.detail {
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 8)
            }
        }
        .padding(.leading, 6)
        .background(
            // faint static rail behind everything
            HStack {
                Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 2)
                    .padding(.leading, 6)
                Spacer()
            }
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.18), value: active)
    }
}
