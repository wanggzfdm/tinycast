import AppKit
import SwiftUI

/// One item in the horizontal Cards layout: header, content and a type footer.
struct ClipboardCard: View {
    @Environment(\.metrics) private var metrics
    let item: ClipboardItem
    let selected: Bool
    let imageURL: URL?
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onActions: () -> Void
    /// Nil when the entry has nothing left to hand over, reported rather than dragged.
    let onDragPayload: () -> ClipDragPayload?
    let onDragDropped: () -> Void
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            bodyContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(metrics.spacing.md)
        .frame(width: 220, height: 240, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                .strokeBorder(
                    selected ? Color.accentColor : Theme.Colors.cardStroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onRightClick { onActions() }
        .onRowClick(
            select: onSelect,
            activate: {
                onSelect()
                onActivate()
            },
            drag: RowDrag(item: { onDragPayload()?.dragItem }, dropped: onDragDropped))
        .armedHover($hovered)
    }

    private var header: some View {
        HStack(spacing: metrics.spacing.sm) {
            Text(sourceName)
                .font(metrics.typography.chip)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(Self.timeFormatter.string(from: item.createdAt))
                .font(metrics.typography.chip)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch item.kind {
        case .text:
            if let color = item.colorValue {
                ColorSwatch(color: color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(item.text ?? "")
                    .font(metrics.typography.menuRow)
                    .lineLimit(6)
                    .truncationMode(.tail)
            }
        case .image:
            AsyncThumbnail(url: imageURL, maxPixel: 160) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(
                        RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous))
            } placeholder: {
                Image(systemName: "photo")
                    .font(.system(.largeTitle))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
            }
        case .file:
            fileContent
        }
    }

    private var fileContent: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            if let fileURL {
                AsyncThumbnail(url: fileURL, maxPixel: 120, source: .file) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 90)
                        .clipShape(
                            RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous))
                } placeholder: {
                    Image(nsImage: IconCache.symbolIcon(named: fileKind.systemImage))
                        .resizable()
                        .frame(width: 44, height: 44)
                }
            }
            Text(fileName)
                .font(metrics.typography.menuRow)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: metrics.spacing.sm) {
            Text(typeTitle)
                .font(metrics.typography.chip)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(typeMeta)
                .font(metrics.typography.chip)
                .foregroundStyle(.tertiary)
        }
    }

    private var fileURL: URL? {
        item.filePath.map { URL(filePath: $0, directoryHint: .inferFromPath) }
    }

    private var fileKind: ClipboardFileKind {
        item.filePath.map { ClipboardFileKind.of(path: $0) } ?? .other
    }

    private var fileName: String {
        item.filePath.map { URL(filePath: $0, directoryHint: .inferFromPath).lastPathComponent } ?? "File"
    }

    private var sourceName: String {
        guard let bundleID = item.sourceBundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return String(localized: "Clipboard") }
        return url.deletingPathExtension().lastPathComponent
    }

    private var typeTitle: String {
        switch item.kind {
        case .text: return item.colorValue != nil ? "Color" : "Text"
        case .image: return "Image"
        case .file: return fileKind.title
        }
    }

    private var typeMeta: String {
        switch item.kind {
        case .text:
            guard item.colorValue == nil, let text = item.text else { return "" }
            return String(localized: "\(text.count) characters")
        case .image:
            guard let url = imageURL, let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else { return "" }
            return Int64(bytes).formatted(.byteCount(style: .file))
        case .file:
            return (item.filePath as NSString?)?.lastPathComponent ?? ""
        }
    }

    @MainActor private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

/// ImageIO for a blob we hold; QuickLook for a referenced file, which may be any type.
private enum ThumbnailSource {
    case image
    case file

    func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        switch self {
        case .image: return ImageThumbnail.cached(url, maxPixel: maxPixel)
        case .file: return FilePreviewThumbnail.cached(url, maxPixel: maxPixel)
        }
    }

    func loadAsync(_ url: URL, maxPixel: CGFloat) async -> NSImage? {
        switch self {
        case .image: return await ImageThumbnail.loadAsync(url, maxPixel: maxPixel)
        case .file: return await FilePreviewThumbnail.loadAsync(url, maxPixel: maxPixel)
        }
    }
}

/// A downsampled thumbnail, decoding misses off the main thread; mirrors ClipboardView's private one.
private struct AsyncThumbnail<Content: View, Placeholder: View>: View {
    let url: URL?
    let maxPixel: CGFloat
    var source: ThumbnailSource = .image
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                content(Image(nsImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let hit = source.cached(url, maxPixel: maxPixel) {
                image = hit
                return
            }
            image = nil
            image = await source.loadAsync(url, maxPixel: maxPixel)
        }
    }
}