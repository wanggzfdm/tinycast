import SwiftUI

/// The horizontal Cards layout: one row of cards, selected one centred.
struct ClipboardCardsView: View {
    @Environment(\.metrics) private var metrics
    let results: [ClipboardItem]
    let selectedID: ClipboardItem.ID?
    let onSelect: (ClipboardItem) -> Void
    let onActivate: () -> Void
    let onActions: (ClipboardItem) -> Void
    let onDragPayload: (ClipboardItem) -> ClipDragPayload?
    let onDragDropped: () -> Void
    @Environment(ClipboardStore.self) private var store

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: metrics.spacing.md) {
                    ForEach(results) { item in
                        ClipboardCard(
                            item: item,
                            selected: item.id == selectedID,
                            imageURL: store.imageURL(for: item),
                            onSelect: { onSelect(item) },
                            onActivate: onActivate,
                            onActions: { onActions(item) },
                            onDragPayload: { onDragPayload(item) },
                            onDragDropped: onDragDropped)
                        .id(item.id)
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.vertical, metrics.spacing.md)
                .hideNativeScrollers()
            }
            .edgeDissolve()
            .thinScrollbar()
            .onChange(of: selectedID) { _, newID in
                guard let newID else { return }
                withAnimation(.snappy) { proxy.scrollTo(newID, anchor: .center) }
            }
            .onAppear {
                if let selectedID { proxy.scrollTo(selectedID, anchor: .center) }
            }
        }
    }
}