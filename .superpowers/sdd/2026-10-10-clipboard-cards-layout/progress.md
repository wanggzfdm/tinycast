# SDD ledger — plan: docs/superpowers/plans/2026-10-10-clipboard-cards-layout.md

## Task 1: complete (no commit — 全局约束禁止 commit)

状态: DONE
改动文件:
- Tinycast/Features/Clipboard/Model/ClipboardStore.swift — 新增 enum ClipboardHistoryLayout(String, CaseIterable, Identifiable, Sendable), cases list/cards, id=rawValue, title 用 String(localized:)（与工作区现有 ClipboardRetention/ClipboardDefaultAction 的 String(localized:) 风格一致）。定义在 ClipboardDefaultAction 之后、ClipboardChord 之前。
- Tests/clipboard-test.swift — main() 在 defaultActionChords() 之后调用 layoutEnum()；新增 layoutEnum() 静态方法，断言 allCases == [.list,.cards]、rawValue、title 非空、未知 rawValue 拒绝。复用现有 expect()。

测试命令与结果:
- ./Scripts/run-tests.sh clipboard-test → PASSED (1 harness, 1.7s run)
- ./Scripts/run-tests.sh clipboard-search-test → PASSED
- ./Scripts/run-tests.sh pasteboard-test → PASSED
- Model 纯净性: grep -rln 'import AppKit|import SwiftUI|import Cocoa' Tinycast/Features/Clipboard/Model/ 无输出

风险:
- 未 commit（按要求）。工作区存在先前未提交改动（ClipboardRetention/ClipboardDefaultAction 的 String(localized:) 改写），与我的增量在同文件;review 需区分。
- 后续任务 2/3（AppSettings/SettingsFileKey/SettingsFileSchema 绑定）尚未执行。
## Task 2: complete (no commit — 全局约束禁止 commit)
状态: DONE
计划事实更正: 计划任务2步骤4声称"AppSettingsKey 是 CaseIterable，backup harness 自动遍历，新增 case 自动进入备份/恢复，settings-backup-test 无需改断言"。实测 FAIL：settings-backup-test 强断言"every AppSettings key is backed up or deliberately excluded"，新增 key 两者皆非则报错。supervisor 裁定选 A（纳入备份 mirrored，纯 UI 偏好应携带，不加入 deliberatelyExcluded），归入当前任务2。

改动文件:
- Tinycast/Features/Settings/AppSettingsKey.swift — 在 clipboardDefaultAction 之后新增 case clipboardHistoryLayout = "clipboardHistoryLayout"
- Tinycast/Features/Settings/AppSettings.swift — 属性（clipboardDefaultAction 之后）clipboardHistoryLayout didSet 写 defaults；init()（clipboardDefaultAction 读取之后）读取缺失回退 .list
- Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift — mirrored 新增 "clipboardHistoryLayout": .clipboardHistoryLayout
- Tinycast/Features/Backup/Model/SettingsBackup.swift — SettingsData 新增 var clipboardHistoryLayout: String?；gather 写 s.clipboardHistoryLayout.rawValue；applySettings 读 raw→ClipboardHistoryLayout(rawValue:)，重新绑定并 count+=1

测试命令与结果:
- ./Scripts/run-tests.sh settings-backup-test → PASSED (1 harness, 1.0s run; 修复前 FAIL 于 "every AppSettings key is backed up or deliberately excluded — clipboardHistoryLayout")

未 staging: 是（git diff --cached --name-only 输出为空）;保留既有未提交改动。

风险:
- AppSettings.swift 中的 46 行 diff 含本任务前既存的 String(localized:) 改写，非本轮引入；review 需区分。
- 后续任务3（SettingsFileKey/SettingsFileSchema）尚未执行。
## Task 3: complete (no commit — 全局约束禁止 commit)
状态: DONE
改动文件:
- Tinycast/Features/Settings/Model/SettingsFileKey.swift — clipboardDisabledApps 之后新增 case clipboardHistoryLayout = "clipboard.historyLayout"
- Tinycast/Features/Settings/SettingsFileSchema.swift — binding switch 新增 case .clipboardHistoryLayout: return bind(settings, \.clipboardHistoryLayout)；底部 ClipboardDefaultAction 之后新增 extension ClipboardHistoryLayout: SettingsFileRawValue {}（String raw enum 由 SettingsFileValue.String 满足）
测试命令与结果:
- ./Scripts/run-tests.sh settings-file-test → PASSED (1 harness; sections 断言不受影响, clipboard 段不新增 section)
- ./Scripts/run-tests.sh settings-backup-test → PASSED (1 harness, 与任务2 mirrored/gather/apply 联动一致)
未 staging: 是（git diff --cached --name-only 无输出）；保留既有未提交改动。
风险:
- settings-file-test 未新增专门断言（沿用现成 exhaustive switch + RawValue 绑定, sections 断言已通过）
- 后续任务4-7 未执行。
## Task 4: complete (no commit — 全局约束禁止 commit)
状态: DONE
改动文件:
- Tinycast/Features/Clipboard/Settings/ClipboardSettingsView.swift — 在 ClipboardDefaultAction picker 之后、.settingsEnabled(settings.clipboardEnabled) 之前新增 ClipboardHistoryLayout picker（ForEach(ClipboardHistoryLayout.allCases) + tag + SettingsRowTitle(.clipboardHistory,"Layout") + 说明文案），位于 SettingsSectionHeader(.clipboardHistory) 分组内。
测试命令与结果:
- ./Scripts/run-tests.sh clipboard-test -> PASSED (1 harness)
- ./Scripts/run-tests.sh settings-backup-test -> PASSED (1 harness)
- ./Scripts/run-tests.sh settings-file-test -> PASSED (1 harness)
- ./Scripts/lint.sh -> 不可运行（swiftlint 未安装，环境限制，非改动引入）。ClipboardSettingsView 为纯 SwiftUI view，不参与任何 harness 编译（依赖 AppCore/Settings 上下文）；编译验证留给任务5/7 的 Debug build。
未 staging: 是（git diff --cached --name-only 无输出）；保留既有未提交改动。
风险:
- 纯 UI 层无独立 harness；layout picker 的实际渲染/绑定由任务7 目视验收覆盖。
- 后续任务5/6（ClipboardCardsView/ClipboardCard/ClipboardScreen 分发）未执行。
## Task 5: complete (no commit — 全局约束禁止 commit)
状态: DONE
改动文件:
- 创建 Tinycast/Features/Clipboard/UI/ClipboardCard.swift — 单张卡片，Header/Body/Footer 三段，220x240，圆角 metrics.radius.card，选中 accent 描边、hover rowHover，onRowClick(select/activate/drag)+onRightClick+armedHover；按 item.kind 分发（text 含 colorValue ColorSwatch / image 缩略图 / file 文件名+缩略图）；私有 AsyncThumbnail/ThumbnailSource 镜像 ClipboardView 的字节受限加载，复用 ImageThumbnail/FilePreviewThumbnail.cached/loadAsync 共享缓存。
- 创建 Tinycast/Features/Clipboard/UI/ClipboardCardsView.swift — ScrollView(.horizontal)+LazyHStack+ScrollViewReader，onChange(of: selectedID) 与 onAppear 滚动选中卡片到 .center，edgeDissolve+thinScrollbar+hideNativeScrollers，接收 results/selectedID/onSelect/onActivate/onActions/onDragPayload/onDragDropped。
- Tinycast.xcodeproj/project.pbxproj — 运行 xcodegen generate 将两个新文件纳入 target（不 commit）。
编译验证:
- xcodebuild Debug build — 修复 onRightClick 参数标签(.onRightClick { onActions() })后 quiet build 无 Swift 编译错误；全量 build 被既有 Localizable.xcstrings 尾逗号格式错误阻塞(资源解析,非本任务引入,文件 untracked 且任务1-4 ledger 未涉及)。
未 staging: 是(git diff --cached --name-only 无输出)；保留既有未提交改动。
风险:
- 完整 Debug build 的 BUILD SUCCEEDED 待处理 Localizable.xcstrings 后确认(先前生成脚本遗留的尾逗号)。
- 任务6(ClipboardScreen 分发与 <-/> 映射)未执行。

## Task 7: complete (no commit — 全局约束禁止 commit)
状态: DONE（验证收尾，无新生产代码改动）

验证命令与结果:
- ./Scripts/run-tests.sh 全量 95 harness → 93 PASS / 2 FAIL。与剪切板/设置/备份相关 harness 全部 PASS：clipboard-test、clipboard-search-test、clipboard-text-test、pasteboard-test、settings-file-test、settings-backup-test。
- 2 个 FAIL 均非本任务引入：codex-turn-test（300s 超时被杀）、installed-ai-test（OpenCode stream failed，外部 CLI 网络失败）。均为 AI/OpenCode 网络 harness，与剪切板无关。
- Debug build → BUILD SUCCEEDED（需临时移走损坏的 untracked Localizable.xcstrings；尾随重复 JSON 片段 ,"version":"1.0"\n}，JSON.parse 报 Unexpected non-whitespace char at pos 302313；构建后已原样恢复，与 /tmp 备份逐字节一致）。
- Model 纯净性 grep → 无输出（含新增 ClipboardHistoryLayout）。
- ./Scripts/lint.sh → 跳过（swiftlint 未安装，brew install swiftlint；环境限制，非改动引入）。
- xcodegen generate → 成功，两个新 UI 文件已纳入 project（ClipboardCard/ClipboardCardsView）。

未 staging: 是（git diff --cached --name-only 无输出）；保留既有未提交改动（206 文件）。

剩余风险:
- Localizable.xcstrings 损坏未修复（untracked、范围外，阻塞完整资源编译，需独立处理）。
- AI 相关 2 个 harness 失败为既有环境问题。
- lint 未运行（swiftlint 缺失）。
- 目视验收未执行：卡片渲染/选中态/居中滚动/右键/拖拽需人工在 Tinycast Dev.app 中按计划任务 7 清单确认。

## Task 6: complete (no commit — 全局约束禁止 commit)
状态: DONE
改动文件:
- Tinycast/Features/Clipboard/UI/ClipboardScreen.swift — (1) content(selection:scroll:) 在 rows.isEmpty 分支后新增 `else if core.settings.clipboardHistoryLayout == .cards` 分发到 ClipboardCardsView（results/selectedID/onSelect/onActivate/onActions/onDragPayload/onDragDropped 接 line 与 list 一致，onSelect 用 rows.firstIndex(of:)，onDragDropped 用 core.paletteCoordinator.dragLanded()）；(2) 新增 func move(_:axis:from:)：仅当 layout==.cards 且 axis==.horizontal 时返回 selection+delta（越界返回 selection），否则返回 nil 交由 RootPaletteView 默认。
验证:
- ./Scripts/run-tests.sh clipboard-test → PASSED (1 harness, 1.3s)
- xcodebuild Debug build → BUILD SUCCEEDED（无 Swift 编译错误、无新增 warning）。注：完整 build 需临时移走既有损坏的 untracked Localizable.xcstrings（尾随重复 "version" 段致 xcstringstool 报 1:1 格式错误，非本次引入），验证后已原样恢复。
未 staging: 是 (git diff --cached --name-only 无输出)
风险:
- ClipboardScreen.swift 含大量任务前既存 String(localized:) 改写（非本任务引入，ledger 任务1/2 已注明）。
- Localizable.xcstrings 损坏仍阻塞 xcodebuild 完整资源编译，需独立修复（范围外）。
