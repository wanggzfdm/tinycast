# 剪切板历史布局切换（List / Cards）实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 新增用户可选的剪切板历史布局偏好（`list` 现有列表 / `cards` 横向卡片），`cards` 为类似 Clipaste 的横向滚动卡片、占满面板、不保留右侧大预览，默认保持 `list`。

**架构：** 新增 `ClipboardHistoryLayout` 枚举并持久化到 `AppSettings`；`ClipboardScreen` 根据设置分发到现有 `ClipboardList + ClipboardPreview` 或新增的 `ClipboardCardsView`。`ClipboardCardsView` 用 `ScrollView(.horizontal)` + `LazyHStack`，通过 `ScrollViewReader` + `onChange(of: selectedID)` 让选中卡片自动居中，复用现有 `ClipboardItem`、`ClipboardStore`、`ClipboardCoordinator` 的取数、激活、拖拽、右键与快捷键逻辑。

**技术栈：** Swift 6（严格并发），SwiftUI + AppKit，Observation，XcodeGen；零第三方依赖。

---

## 文件结构

### 新增文件

| 文件 | 职责 |
| --- | --- |
| `Tinycast/Features/Clipboard/UI/ClipboardCardsView.swift` | cards 布局的横向滚动容器：`ScrollView(.horizontal)` + `LazyHStack`，通过 `ScrollViewReader` 让选中卡片居中，承载 `ClipboardCard`，并组装 Header/Body/Footer。 |
| `Tinycast/Features/Clipboard/UI/ClipboardCard.swift` | 单张卡片的视觉：选中态描边、hover、按 `item.kind` 分发 Body（文本/图片/文件缩略图），Footer 显示类型标签。 |

### 修改文件

| 文件 | 改动 |
| --- | --- |
| `Tinycast/Features/Clipboard/Model/ClipboardStore.swift` | 新增 `ClipboardHistoryLayout` 枚举（`String, CaseIterable, Identifiable, Sendable`，含 `title`）。 |
| `Tinycast/Features/Settings/AppSettingsKey.swift` | 新增 `case clipboardHistoryLayout = "clipboardHistoryLayout"`。 |
| `Tinycast/Features/Settings/AppSettings.swift` | 新增 `clipboardHistoryLayout` 存储属性（`didSet` 写 defaults、`init()` 读取、缺失回退 `.list`）。 |
| `Tinycast/Features/Settings/Model/SettingsFileKey.swift` | 新增 `case clipboardHistoryLayout = "clipboard.historyLayout"`（放在 `clipboardDisabledApps` 之后）。 |
| `Tinycast/Features/Settings/SettingsFileSchema.swift` | 新增 `case .clipboardHistoryLayout: return bind(settings, \.clipboardHistoryLayout)`，并在底部新增 `extension ClipboardHistoryLayout: SettingsFileRawValue {}`。 |
| `Tinycast/Features/Clipboard/Settings/ClipboardSettingsView.swift` | 在 `SettingsSectionHeader(.clipboardHistory)` 分组的 Default action picker 之后新增 segmented picker。 |
| `Tinycast/Features/Clipboard/UI/ClipboardScreen.swift` | `content(selection:scroll:)` 中按 `core.settings.clipboardHistoryLayout` 分发到 cards 或现有 list。 |
| **`Tests/settings-file-test.swift`** | 新增 case 会触发 `SettingsFileKey.sections` 顺序断言更新（`clipboard` 段整体顺序不变，但需确认断言仍通过）。 |

> **XcodeGen 约定：** `project.yml` 用 `- path: Tinycast` 按目录纳入 source，新增 `UI/*.swift` 文件**不需要**改 `project.yml`。每个任务改完文件后，最后统一运行 `xcodegen generate` 重新生成 `Tinycast.xcodeproj` 并提交。

---

## 任务 1：新增 `ClipboardHistoryLayout` 枚举

**文件：**
- 修改：`Tinycast/Features/Clipboard/Model/ClipboardStore.swift`
- 测试：`Tests/clipboard-test.swift`

`ClipboardHistoryLayout` 定义在 `ClipboardStore.swift` 中、`ClipboardDefaultAction` 定义处（约 115 行）附近，遵循 `ClipboardDefaultAction` 的 `String, CaseIterable, Identifiable, Sendable` + `title` 模式。

- [ ] **步骤 1：编写失败的测试**

在 `Tests/clipboard-test.swift` 的 `main()` 方法（`defaultActionChords()` 之后）改为调用 `layoutEnum()`，并新增静态方法。文件内已有 `expect(_ condition: Bool, _ label: String)` 辅助（第 775 行），直接复用：

```swift
/// 枚举的 title 是可读的，且 rawValue 是持久化的句柄（不随界面文案变）。
static func layoutEnum() {
    expect(ClipboardHistoryLayout.allCases == [.list, .cards], "enum exposes list then cards")
    expect(ClipboardHistoryLayout.list.rawValue == "list", "list spells its raw value")
    expect(ClipboardHistoryLayout.cards.rawValue == "cards", "cards spells its raw value")
    expect(!ClipboardHistoryLayout.list.title.isEmpty, "list has a title")
    expect(!ClipboardHistoryLayout.cards.title.isEmpty, "cards has a title")
    expect(ClipboardHistoryLayout(rawValue: "nonsense") == nil, "unknown raw value is rejected")
}
```

> `expect` 已存在于 `clipboard-test.swift` 中，只调用、不重复定义。

- [ ] **步骤 2：运行测试验证失败**

```bash
./Scripts/run-tests.sh clipboard-test
```

预期：编译失败，报 "cannot find 'ClipboardHistoryLayout' in scope"。

- [ ] **步骤 3：编写最少实现代码**

在 `ClipboardStore.swift` 的 `ClipboardDefaultAction` 附近新增：

```swift
/// How the history is presented; Cards is the horizontal Clipaste-style layout.
enum ClipboardHistoryLayout: String, CaseIterable, Identifiable, Sendable {
    case list
    case cards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return String(localized: "List")
        case .cards: return String(localized: "Cards")
        }
    }
}
```

- [ ] **步骤 4：运行测试验证通过**

```bash
./Scripts/run-tests.sh clipboard-test
```

预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add Tinycast/Features/Clipboard/Model/ClipboardStore.swift Tests/clipboard-test.swift
git commit -m "feat(clipboard): add ClipboardHistoryLayout enum"
```

---

## 任务 2：`AppSettings` 持久化

**文件：**
- 修改：`Tinycast/Features/Settings/AppSettingsKey.swift`
- 修改：`Tinycast/Features/Settings/AppSettings.swift`
- 测试：`Tests/settings-backup-test.swift`（覆盖 `AppSettingsKey` `CaseIterable` 自动纳入备份）

`AppSettingsKey` 是 `CaseIterable`，backup harness 会遍历它，所以新增 case 自动进入备份/恢复，`settings-backup-test` 无需改断言（它会验证新 key 被覆盖）。本任务验证通过编译 + `settings-backup-test` 通过来完成。

- [ ] **步骤 1：在 `AppSettingsKey.swift` 新增 case**

在 `clipboardDefaultAction` 之后、`clipboardAutoFillLauncher` 之前新增：

```swift
case clipboardHistoryLayout = "clipboardHistoryLayout"
```

- [ ] **步骤 2：在 `AppSettings.swift` 新增存储属性**

在 `clipboardDefaultAction` 属性（约 152 行）之后新增：

```swift
/// List is the classic split list; Cards is the horizontal Clipaste-style row.
var clipboardHistoryLayout: ClipboardHistoryLayout {
    didSet {
        defaults.set(
            clipboardHistoryLayout.rawValue, forKey: Key.clipboardHistoryLayout.rawValue)
    }
}
```

- [ ] **步骤 3：在 `AppSettings.init()` 读取**

在 `clipboardDefaultAction` 读取（约 644 行）之后新增：

```swift
clipboardHistoryLayout =
    defaults.string(forKey: Key.clipboardHistoryLayout.rawValue)
    .flatMap(ClipboardHistoryLayout.init) ?? .list
```

- [ ] **步骤 4：运行测试验证**

```bash
./Scripts/run-tests.sh settings-backup-test
```

预期：PASS——`AppSettingsKey.allCases` 遍历自动把新增 key 纳入备份覆盖，无需改动测试断言。

- [ ] **步骤 5：Commit**

```bash
git add Tinycast/Features/Settings/AppSettingsKey.swift Tinycast/Features/Settings/AppSettings.swift
git commit -m "feat(clipboard): persist clipboardHistoryLayout in AppSettings"
```

---

## 任务 3：settings.json 镜像（`SettingsFileKey` + `SettingsFileSchema`）

**文件：**
- 修改：`Tinycast/Features/Settings/Model/SettingsFileKey.swift`
- 修改：`Tinycast/Features/Settings/SettingsFileSchema.swift`
- 测试：`Tests/settings-file-test.swift`、`Tests/settings-backup-test.swift`

`SettingsFileSchema` 的 switch 是 exhaustive 的，新增 `SettingsFileKey` case 会强制编译期补齐绑定；若漏掉会编译失败，正好作为校验。`settings-file-test.swift` 有 `SettingsFileKey.sections` 顺序断言（`clipboard` 段在 windowManagement 之后、emoji 之前），需确认新增 key 不破坏该顺序。

- [ ] **步骤 1：在 `SettingsFileKey.swift` 新增 case**

在 `clipboardDisabledApps`（`case clipboardDisabledApps = "clipboard.disabledApps"`）之后新增：

```swift
case clipboardHistoryLayout = "clipboard.historyLayout"
```

- [ ] **步骤 2：在 `SettingsFileSchema.swift` 新增绑定**

在 `case .clipboardDisabledApps: return bind(settings, \.clipboardDisabledApps)` 之后新增：

```swift
case .clipboardHistoryLayout: return bind(settings, \.clipboardHistoryLayout)
```

- [ ] **步骤 3：在 `SettingsFileSchema.swift` 底部新增 RawValue 扩展**

在 `extension ClipboardDefaultAction: SettingsFileRawValue {}` 之后新增：

```swift
extension ClipboardHistoryLayout: SettingsFileRawValue {}
```

- [ ] **步骤 4：更新 `settings-file-test.swift` 的 sections 断言**

运行 `settings-file-test`；若 `SettingsFileKey.sections` 顺序断言失败（因为新 key 的 section 仍是 `clipboard`，`sections` 由相邻 key 归并，新增不新增独立段落），多数情况下无需改动。若编译器仍报 order 相关失败，按此处理：

```swift
// sections 顺序保持：
// … "windowManagement", "clipboard", "emoji", "calendar", "extensions"
```

（实际 add case 到 clipboard section 中间不产生新 section，`sections` 数组不变。若失败，只检查 `clipboard` 段内 key 是否仍连续声明。）

- [ ] **步骤 5：运行测试验证**

```bash
./Scripts/run-tests.sh settings-file-test
./Scripts/run-tests.sh settings-backup-test
```

预期：均 PASS。

- [ ] **步骤 6：Commit**

```bash
git add Tinycast/Features/Settings/Model/SettingsFileKey.swift Tinycast/Features/Settings/SettingsFileSchema.swift Tests/settings-file-test.swift
git commit -m "feat(clipboard): mirror clipboardHistoryLayout in settings.json"
```

---

## 任务 4：设置 UI（Layout picker）

**文件：**
- 修改：`Tinycast/Features/Clipboard/Settings/ClipboardSettingsView.swift`

`ClipboardSettingsView` 的 `SettingsSectionHeader(.clipboardHistory)` 分组已有 `ClipboardRetention` 与 `ClipboardDefaultAction` picker，参照其 `Picker(selection:)` + `ForEach(SomeEnum.allCases)` + `tag` 模式在 Default action picker 之后新增 layout picker。

- [ ] **步骤 1：新增 layout picker**

在 `ClipboardSettingsView.swift` 的 `ClipboardDefaultAction` picker（label 结尾 `Text("↵ does this, and Paste takes its shortcut.")`）之后、`.settingsEnabled(settings.clipboardEnabled)` 之前新增（`SettingsRowTitle` / `SettingsSectionHeader` 已在文件内使用，直接复用）：

```swift
Picker(selection: $settings.clipboardHistoryLayout) {
    ForEach(ClipboardHistoryLayout.allCases) { layout in
        Text(layout.title).tag(layout)
    }
} label: {
    SettingsRowTitle(.clipboardHistory, "Layout")
    Text("List shows a preview beside rows; Cards fills the panel with a horizontal row.")
}
```

- [ ] **步骤 2：运行测试与编译验证**

```bash
./Scripts/run-tests.sh clipboard-test
```

预期：PASS（编译包含该 view 的 harness 会验证设置视图仍可编译；若 clipboard-test 未包含该 view，则以任务 5 的 Debug build 验证为准）。

- [ ] **步骤 3：Commit**

```bash
git add Tinycast/Features/Clipboard/Settings/ClipboardSettingsView.swift
git commit -m "feat(clipboard): add layout picker to clipboard settings"
```

---

## 任务 5：新增 `ClipboardCardsView` 与 `ClipboardCard`

**文件：**
- 创建：`Tinycast/Features/Clipboard/UI/ClipboardCardsView.swift`
- 创建：`Tinycast/Features/Clipboard/UI/ClipboardCard.swift`

cards 视图是纯视觉层，无独立逻辑单测；验证依托 Debug build 编译 + 目视验收（详见任务 7）。它复用现有：
- `ClipboardItem`（`kind`/`text`/`imagePath`/`createdAt`/`sourceBundleID`/`isPinned`/`colorValue`）
- `ClipboardStore.imageURL(for:)`（图片/文件缩略图）
- `AsyncThumbnail`/`ImageThumbnail`/`FilePreviewThumbnail`（`ClipboardView.swift` 内的私有 `AsyncThumbnail` 与 `ThumbnailSource` 为 `private`，cards 需自建同款缩略图加载，参照 `ClipboardView.swift` 的 `AsyncThumbnail`/`ThumbnailSource` 模式）
- `ImageThumbnail.cached/loadAsync` 与 `FilePreviewThumbnail.cached/loadAsync` 的 byte-bounded 缓存与 `purgePreviews` 生命周期（见 `ThumbnailCache.swift`）

> **关键：** `ClipboardView.swift` 的 `AsyncThumbnail` 与 `ThumbnailSource` 是 `private`，cards 不能直接复用，需在`ClipboardCard.swift` 内重建一份同等字节上限的缩略图加载（复用 `ImageThumbnail`/`FilePreviewThumbnail` 的共享缓存，不新增第二份无上限缓存）。

- [ ] **步骤 1：创建 `ClipboardCard.swift`**

单张卡片，三段结构（Header / Body / Footer），用 `InterfaceMetrics` 的 `metrics`、`Theme.Colors`、`Theme.Spacing`。尺寸参照规格：宽 220、高 240、圆角 `metrics.radius.card`。

```swift
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
        .onRightClick(onActions)
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
```

> `metrics.typography.chip` / `menuRow` 均为 `InterfaceMetrics` 现有成员；`Theme.Colors.cardStroke` 存在，选中态描边用 `Color.accentColor`（与 `WindowLayoutNumberField` 的 focused stroke 一致）。若任务执行时发现其余字体成员名不符，以 `InterfaceMetrics.swift` 中现有成员名为准。

- [ ] **步骤 2：创建 `ClipboardCardsView.swift`**

横向滚动容器，用 `ScrollViewReader` + `onChange(of: selectedID)` 让选中卡片自动居中到面板中心。`PaletteScreen` 的 `scroll` 仅描述垂直滚动意图，横向滚动下不可靠，因此 cards 不依赖它，改由选中态驱动显式居中。

```swift
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
```

> - 卡片 `id` 用 `item.id`（`ClipboardItem.ID == UUID`），`proxy.scrollTo(_:anchor:)` 以 `anchor: .center` 让选中卡片贴近面板中心，对应 `ScrollIntent.Kind.center` 的语义。
> - `metrics` 来自 `@Environment(\.metrics)`；若该环境键在当前视图树不可用，改用 `core.settings.interfaceSize.metrics` 传入，但优先复用 `@Environment(\.metrics)`（项目已有该环境值）。

- [ ] **步骤 3：编译验证**

```bash
# Debug build 编译整个 app，验证新增视图无编译错误
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug build | tail -30
```

预期：BUILD SUCCEEDED，无新增 warning。

- [ ] **步骤 4：Commit**

```bash
git add Tinycast/Features/Clipboard/UI/ClipboardCardsView.swift Tinycast/Features/Clipboard/UI/ClipboardCard.swift
git commit -m "feat(clipboard): add horizontal Cards layout views"
```

---

## 任务 6：`ClipboardScreen` 分发与键盘/滚动

**文件：**
- 修改：`Tinycast/Features/Clipboard/UI/ClipboardScreen.swift`

`ClipboardScreen.content(selection:scroll:)` 是唯一分发点。`ClipboardScreen` 已经通过 `PaletteScreen` 协议的 `move(_:axis:from:)` 支持横向移动映射；cards 模式的 `←/→` 由 `RootPaletteView` 调 `screen.move(_:axis:.horizontal:from:)` 驱动。

**行为目标：**
- `←/→`：cards 模式移动选中卡片（水平轴）。
- `↑/↓`：保持现有回退（线性步进）。
- `Enter` / `⌘↵` / `⌃⌘↵` / `⌥↵` / `⌘⌫` / `⌃X` / `⌃⇧X` / `⌘.`：全部复用现有 `activate` / `secondary` / `tertiary` / `pasteKeepingWindowOpen` / `perform` 逻辑，不重复实现。
- 右键菜单复用 `ClipboardActionsMenu`（现有 `actions(at:)` 已接线）。
- 拖拽复用 `core.clipboardCoordinator.dragPayload(for:)`。

`move` 现有实现：需确认 `ClipboardScreen` 是否已实现 `move`。若没有，默认由 `RootPaletteView` 的 `move(delta, in:)` 回退（垂直时按线性步进；水平时 cards 应处理）。

- [ ] **步骤 1：在 `content(selection:scroll:)` 中按布局分发**

在 `ClipboardScreen.swift` 的 `content` 中，`let rows = rows` 之后、现有 `HStack` list 分支之前，插入 cards 分支（保留 list 分支原样）：

```swift
if rows.isEmpty {
    EmptyResults(text: vm.clipboardFilter.emptyMessage)
} else if core.settings.clipboardHistoryLayout == .cards {
    ClipboardCardsView(
        results: rows,
        selectedID: item(at: selection)?.id,
        onSelect: { item in vm.selection = rows.firstIndex(of: item) ?? 0 },
        onActivate: { activate(at: vm.selection) },
        onActions: { item in
            if let index = rows.firstIndex(of: item) { vm.selection = index }
            openActions()
        },
        onDragPayload: { core.clipboardCoordinator.dragPayload(for: $0) },
        onDragDropped: { core.paletteCoordinator.dragLanded() })
} else {
    // 现有 HStack(ClipboardList + separator + ClipboardPreview) 保持不变
}
```

（现有 `EmptyResults` 分支已在代码中，合并进本 if/else-if 即可。注意 `onDragDropped` 参数贯穿 `ClipboardScreen → ClipboardCardsView → ClipboardCard → RowDrag.dropped`，与 `ClipboardList` 的 `onDropped` 一致。）

- [ ] **步骤 2：实现 cards 水平移动映射**

在 `ClipboardScreen` 中新增 `move(_:axis:from:)`（若已存在则扩展现有实现，仅在 axis 为 horizontal 且布局为 cards 时特殊处理）：

```swift
// cards 模式：←/→ 线性步进；list 模式保持默认回退。
func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
    guard core.settings.clipboardHistoryLayout == .cards, axis == .horizontal else {
        return nil
    }
    let rows = rows
    let target = selection + delta
    guard rows.indices.contains(target) else { return selection }
    return target
}
```

- [ ] **步骤 3：编译验证**

```bash
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug build | tail -30
```

预期：BUILD SUCCEEDED，无新增 warning。

- [ ] **步骤 4：Commit**

```bash
git add Tinycast/Features/Clipboard/UI/ClipboardScreen.swift
git commit -m "feat(clipboard): dispatch clipboard layout and map card movement"
```

---

## 任务 7：测试与验证收尾

**文件：**
- 无新生产文件；验证性测试见下。

对 UI 视觉层无现成单测；设置持久化与 schema 的测试已在任务 2、3 覆盖。本任务做全量验证与 lint。

- [ ] **步骤 1：跑全量测试**

```bash
./Scripts/run-tests.sh
```

预期：所有 harness PASS。

- [ ] **步骤 2：Debug 编译验证**

```bash
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug build | tail -30
```

预期：BUILD SUCCEEDED，无新增 warning。

- [ ] **步骤 3：lint**

```bash
./Scripts/lint.sh
```

预期：clean。

- [ ] **步骤 4：Model 纯净性校验**

```bash
grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/
```

预期：无输出（`ClipboardHistoryLayout` 定义在 Model/ClipboardStore.swift，不能 import AppKit/SwiftUI）。

- [ ] **步骤 5：XcodeGen 重新生成**

```bash
xcodegen generate
```

预期：`Tinycast.xcodeproj` 重新生成，新文件纳入 source。

- [ ] **步骤 6：目视验收清单**

人工在 Debug build 中验证：

- [ ] 剪切板设置页出现 Layout picker，默认 `List`。
- [ ] 切换 `Cards` 后剪切板面板只显示横向卡片行，无右侧大预览。
- [ ] 卡片显示 Header（来源 app / 时间 / pin）、Body（文本/图片/文件缩略图）、Footer（类型）。
- [ ] 选中卡片有 accent 描边；←/→ 移动选中；选中项接近面板中心。
- [ ] `Enter` / `⌘↵` / `⌃⌘↵` / `⌥↵` / `⌘⌫` / `⌃X` / `⌃⇧X` / `⌘.` 在 cards 模式行为与 list 一致。
- [ ] 右键卡片弹出 `ClipboardActionsMenu`。
- [ ] 拖拽卡片执行 copy-only 拖出（参照 `docs/features/clipboard.md#dragging-out`）。
- [ ] 搜索后选中卡片自动贴近中心。
- [ ] 空历史时显示 `EmptyResults` 居中提示。
- [ ] 切换回 `List` 后恢复原有列表+预览布局。

- [ ] **步骤 7：Commit**

```bash
git add Tinycast.xcodeproj
git commit -m "chore: regenerate Xcode project for clipboard cards layout"
```

---

## 自检

### 1. 规格覆盖度

- 布局偏好（`list`/`cards` 枚举、默认 `list`）→ 任务 1。
- 持久化层级（`AppSettingsKey` / `AppSettings` / `SettingsFileKey` / `SettingsFileSchema`）→ 任务 2、3。
- 设置 UI（Layout picker）→ 任务 4。
- 视图结构（`ClipboardScreen` 分发、新增 `ClipboardCardsView`/`ClipboardCard`）→ 任务 5、6。
- 横向卡片布局（横向滚动、居中、三段卡片、尺寸、选中态、hover）→ 任务 5。
- 交互（`←/→` 移动、`Enter` 等快捷键、右键、拖拽、搜索后居中、空状态共用 `EmptyResults`）→ 任务 6。
- 测试与验证（`run-tests.sh`、Debug build、`lint.sh`、目视验收）→ 任务 7。

### 2. 占位符扫描

- 无 "待定"/"TODO"/"TBD" 残留；每个步骤都有明确代码或命令。
- `AsyncThumbnail` / `ThumbnailSource` 在 `ClipboardCard.swift` 中重建（因为 `ClipboardView.swift` 版本是 `private`），不引用未定义的类型。
- `ScrollViewReader` / `proxy.scrollTo(_:anchor:)` / `.center` 均引用真实存在的 SwiftUI 能力，与 `ScrollIntent.Kind.center` 语义一致（`.center` 精神由 `proxy.scrollTo(_:anchor: .center)` 落实）。
- 卡片用 `metrics.typography.chip`/`menuRow`、`Theme.Colors`（`selection`/`rowHover`/`cardStroke`）、`Theme.Spacing`、`metrics.radius.card`/`thumbnail`，均经真实代码核对存在；选中态描边用 `Color.accentColor`。

### 3. 类型/文件名一致性

- 全计划统一 `ClipboardHistoryLayout`（enum）、`ClipboardCardsView`、`ClipboardCard`。
- `SettingsFileKey` 用 `clipboardHistoryLayout` case、`rawValue "clipboard.historyLayout"`；`AppSettingsKey` 用同 case、`rawValue "clipboardHistoryLayout"`（两层命名不同，符合现有 `clipboardDefaultAction` / `clipboard.defaultAction` 约定）。
- `ClipboardScreen` / `ClipboardStore` / `ClipboardCoordinator` / `ClipboardItem` / `ClipboardFilter` / `ClipboardDefaultAction` / `ClipboardRetention` 均与真实文件一致。