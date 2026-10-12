# 剪切板历史布局切换（List / Cards）

**日期:** 2026-10-10
**状态:** 已批准设计
**范围:** Tinycast 剪切板历史呈现形式

## 背景

Tinycast 当前的剪切板历史是左右分栏：左侧 `ClipboardList` 列表 + 右侧 `ClipboardPreview` 大预览
（见 `Tinycast/Features/Clipboard/UI/ClipboardScreen.swift`）。用户希望参考 Clipaste 这类
剪切板工具，提供一种**横向卡片**呈现形式：卡片占满整个剪切板面板，每张卡片自身承担内容预览，
不再保留右侧的大预览区域。

用户在讨论中明确选择了方案 A：**横向卡片占满整个剪切板面板，不保留右侧预览**。

## 目标

1. 提供一个用户可选的布局偏好：现有 `list`（竖向列表 + 右侧预览）与新增 `cards`（横向卡片）。
2. `cards` 布局为类似 Clipaste 的横向滚动卡片，占满面板，不保留右侧大预览。
3. 保留现有剪切板数据流、搜索、类型过滤、固定（pin）、拖拽、动作快捷键与右键菜单，不重写底层。
4. 设置持久化到 `UserDefaults` 与 `settings.json` 镜像。

## 非目标

- 不重写 `ClipboardStore`、搜索、OCR / 文本识别、保留策略等底层逻辑。
- 不引入 Space 大预览浮层（后续可作为独立增强）。
- 不改动现有 `list` 布局的交互与视觉（除设置入口外）。
- 不将 `cards` 设为默认值——默认保持 `list`，避免改变现有用户体验。
- 不新增第三方依赖。

## 布局偏好

新增枚举，定义两种布局：

```swift
enum ClipboardHistoryLayout: String, CaseIterable {
    case list
    case cards
}
```

- 默认值：`list`。
- `cards` 等价于用户口头描述的“横向布局”。

### 持久化层级

遵循项目“新增 preference 也同步 `SettingsFileKey` 与 `SettingsFileSchema`”的约定
（见 `docs/features/settings-file.md`）。需要改动的点：

| 位置 | 现有示例 | 新增 |
| --- | --- | --- |
| `Tinycast/Features/Settings/AppSettingsKey.swift` | `clipboardDefaultAction = "clipboardDefaultAction"` | `clipboardHistoryLayout = "clipboardHistoryLayout"` |
| `Tinycast/Features/Settings/AppSettings.swift` | `var clipboardDefaultAction: ClipboardDefaultAction` | `var clipboardHistoryLayout: ClipboardHistoryLayout`（含 `didSet` 写 defaults 与 `init()` 读取，`rawValue` 解析，缺失回退 `.list`） |
| `Tinycast/Features/Settings/Model/SettingsFileKey.swift` | `case clipboardDefaultAction = "clipboard.defaultAction"` | `case clipboardHistoryLayout = "clipboard.historyLayout"` |
| `Tinycast/Features/Settings/SettingsFileSchema.swift` | `case .clipboardDefaultAction: return bind(settings, \.clipboardDefaultAction)` | `case .clipboardHistoryLayout: return bind(settings, \.clipboardHistoryLayout)` |

`AppSettingsKey` 是 `CaseIterable`，backup harness 会遍历它，因此新增 case 自动进入备份/恢复。
`SettingsFileSchema` 的 exhaustive switch 会因新增 case 编译失败，正好强制补齐绑定。

### 设置 UI

在 `Tinycast/Features/Clipboard/Settings/ClipboardSettingsView.swift` 的 clipboard history 分组
（`SettingsSectionHeader(.clipboardHistory)`）中新增 segmented picker：

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

- `ClipboardHistoryLayout` 参照 `ClipboardRetention` 的模式，提供 `title`（如 "List" / "Cards"）。
- 该设置不需要 `FeatureCommandsSection` 绑定（不是命令），且不随“Enable Clipboard History”开关启用
  之外额外控制——沿用同一 section 的 `.settingsEnabled(settings.clipboardEnabled)`，功能关闭时灰显即可。

## 视图结构

`ClipboardScreen` 继续作为入口，根据设置分发：

- `list`：保留现有 `ClipboardList + ClipboardPreview`（不动）。
- `cards`：渲染新增 `ClipboardCardsView`。

```swift
@ViewBuilder
private func content(selection: Int, scroll: ScrollIntent) -> some View {
    let rows = rows
    if rows.isEmpty {
        EmptyResults(text: vm.clipboardFilter.emptyMessage)
    } else if core.settings.clipboardHistoryLayout == .cards {
        ClipboardCardsView(
            results: rows,
            selectedID: item(at: selection)?.id,
            scroll: scroll,
            onSelect: { item in vm.selection = rows.firstIndex(of: item) ?? 0 },
            onActivate: { activate(at: vm.selection) },
            onActions: { item in
                if let index = rows.firstIndex(of: item) { vm.selection = index }
                openActions()
            },
            onDragPayload: { core.clipboardCoordinator.dragPayload(for: $0) }
        )
    } else {
        // 现有 ClipboardList + 分隔线 + ClipboardPreview 保持不变
    }
}
```

新增文件：

```text
Tinycast/Features/Clipboard/UI/ClipboardCardsView.swift
Tinycast/Features/Clipboard/UI/ClipboardCard.swift
```

不改现有 `ClipboardList` / `ClipboardRow` / `ClipboardPreview` 文件，降低回归风险。

> 注：空历史时仍使用现有 `EmptyResults(text: vm.clipboardFilter.emptyMessage)` 居中提示，cards
> 与 list 共用，不引入第二条空状态文案路径。

## 横向卡片布局

`ClipboardCardsView`：

- `ScrollView(.horizontal)`。
- 内部 `LazyHStack(spacing: Theme.Spacing…)`。
- 通过 `ScrollViewReader` 让选中项自动滚动到面板中心（`ScrollIntent` 的 `.center` 语义，参照 `land()`）。
- 搜索框、空状态、快捷键容器仍由 `ClipboardScreen` / 外层 palette 提供，`ClipboardCardsView` 只负责卡片行本身。

卡片视觉（`ClipboardCard`）：

```text
┌────────────────────────────────────────────────────────┐
│ Search clipboard history...                            │
├────────────────────────────────────────────────────────┤
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐     │
│ │ App · 12:30  │ │ Safari       │ │ Finder       │     │
│ │              │ │              │ │              │     │
│ │ Text preview │ │ Image thumb  │ │ File summary │     │
│ │              │ │              │ │              │     │
│ │ Text · 42 ch │ │ Image        │ │ 3 files      │     │
│ └──────────────┘ └──────────────┘ └──────────────┘     │
└────────────────────────────────────────────────────────┘
```

卡片建议尺寸：

- 宽：`220` pt
- 高：`240` pt
- 圆角：`metrics.radius.card`（`InterfaceMetrics`）
- 选中态：accent 描边 + 轻背景
- hover：轻微背景提升，不做复杂动画

### 卡片内容规则（`ClipboardCard`，三段结构）

1. **Header**
   - 来源 app 图标 / app 名（现有 `ClipboardItem` 可提供的来源信息）
   - 时间（复用现有时间格式化）
   - pinned 标识（`item.isPinned`）

2. **Body**（按 `item.kind` 分发）
   - `text`：多行摘要（行数上限，超出裁剪）
   - `image`：`ImageThumbnail` / 现有缩略图逻辑居中裁切
   - `file`：文件名 / 数量 / 类型摘要，参照 `ClipboardFileKind` 与 `FilePreviewThumbnail`
   - 其他派生情况：复用现有 `ClipboardPreview` 的文案策略

3. **Footer**
   - 类型标签（`ClipboardFilter` 的标题语义，或 `ClipboardItem.kind`）
   - 可选轻量 metadata：字符数、文件数等

不引入新的数据模型，直接消费现有 `ClipboardItem`、`ClipboardStore` 与 `ClipboardCoordinator` 状态。

## 交互行为

保持现有剪切板屏幕语义。`RootPaletteView` 已通过 `PaletteScreen` 协议的
`move(delta:axis:from:)` 抽象出水平移动（`moveHorizontally` 调 `screen.move(delta, axis: .horizontal, from:)`），
cards 布局可借此把 `←/→` 映射为卡片间移动，无需改动 `RootPaletteView`。

- `←/→`：cards 模式下移动选中卡片（通过 `screen.move(_:axis:.horizontal:from:)`）。
- `↑/↓`：保持现有回退逻辑（线性步进）。`ClipboardScreen` 若不覆盖该轴，`RootPaletteView` 的
  `move(delta, in:)` 会做回退，行为与 list 一致。
- `Enter`：默认动作（`activate(item)`）。
- `⌘Enter` / `⌃⌘Enter` / `⌥Enter`：复用现有 `secondary` / `tertiary` / `pasteKeepingWindowOpen`。
- `⌘⌫` / `⌃X` / `⌃⇧X`：删除 / 删除所有，沿用 `perform` 与现有 coordinator。
- `⌘.`：pin / unpin，沿用 `togglePinnedClip`。
- 右键菜单：继续使用 `ClipboardActionsMenu`。
- 拖拽：沿用 `ClipboardCoordinator.dragPayload` 与 RowClick 的 AppKit 拖拽机制
  （参照 `docs/features/clipboard.md#dragging-out` 的 copy-only 约定）。
- 搜索后选中项自动滚动居中，参照现有 `land()` / `follow` 的 `.center` / `.follow` `ScrollIntent`。

## 测试与验证

生产逻辑改动点：布局枚举、设置持久化（`AppSettings` / `SettingsFileKey` / `SettingsFileSchema`）。
UI 分发与卡片渲染为纯视觉层。

需要新增/更新测试：

- `AppSettings` 布局默认值（缺失回退 `.list`）、持久化读写。
- settings backup / schema 绑定是否覆盖新 key（`AppSettingsKey` `CaseIterable` 遍历由 backup harness 覆盖）。
- `ClipboardScreen` 布局分发（若存在可编译 harness；若不可，明确说明依赖编译期验证 + 目视验收）。

验证命令：

- `./Scripts/run-tests.sh`
- Debug build 编译（无新增 warning）
- `./Scripts/lint.sh`
- 目视验收：切换 List/Cards，检查选中态、自动居中、空状态、右键菜单、拖拽。

## 风险

- **视觉层无现成单测**：卡片渲染细节依赖目视验收，回归依托人工检查。
- **键盘语义**：cards 模式的 `←/→` 依赖 `PaletteScreen.move(_:axis:.horizontal:from:)`，若实现时该
  协议路径与现有 list 的横向行为冲突，需在实现阶段小范围调整；不改变 `RootPaletteView` 的按键分发。
- **设置迁移**：新增 `clipboard.historyLayout`，旧用户无该 key，回退 `.list`；空 key 处理需在
  `AppSettings.init` 中体现（与 `clipboardDefaultAction` 模式一致）。
- **卡片内图片缩略图**：需要复用现有 byte-bounded 缓存与 `purgePreviews` 生命周期，避免新增第二份
  无上限缓存（参照 `FilePreviewThumbnail` / `ImageThumbnail`）。