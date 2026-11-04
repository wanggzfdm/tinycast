import SwiftUI

/// ZTools-style tool chrome: a compact pill docked where the search field sits — badge, name, ✕.
/// Shared by the palette's tool screens and the standalone tool windows, so both read alike.
struct ToolTitleBar: View {
    let title: String
    let onClose: () -> Void

    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.Colors.controlHover))
            Text(title)
                .font(metrics.typography.searchField.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            Capsule()
                .fill(Theme.Colors.rowHover)
                .frame(width: 1, height: 14)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hovered ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.Colors.controlHover.opacity(hovered ? 1 : 0)))
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
            .help("Close")
        }
        .padding(.leading, 6)
        .padding(.trailing, 5)
        .frame(height: 32)
        .background(Capsule().fill(Theme.Colors.controlSurface))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// A standalone tool window's surface: the palette's glass behind the tool's translucent fills,
/// so a detached tool keeps the palette's material. The window's own titlebar carries the close.
struct ToolWindowChrome<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The palette's own glass behind translucent tool fills; ignores the titlebar's
            // safe-area inset, or the window's own dark fill shows as a strip above the tool.
            .background(GlassEffectView().ignoresSafeArea())
    }
}
