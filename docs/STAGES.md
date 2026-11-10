# 分阶段交付清单

> 由于本机是 Windows 且没有 DSH SwiftUI 模拟器桥接，下面的阶段是**代码分层与验收路径**，不是“已逐阶段在模拟器跑过”的记录。所有阶段文件在最终仓库中同时存在；请按阶段顺序在 Mac 上逐段构建、逐段验收。

## 阶段 1：项目骨架 + SwiftData + 列表/编辑器 + 纯文本

### 新增
- `project.yml`
- `Resources/Info.plist`
- `Resources/LumenNotes.entitlements`
- `Resources/Assets.xcassets/**`
- `Sources/App/LumenNotesApp.swift`
- `Sources/App/AppContainer.swift`
- `Sources/App/RootView.swift`
- `Sources/Models/Note.swift`
- `Sources/Models/NoteDocument.swift`
- `Sources/Persistence/Persistence.swift`
- `Sources/DesignSystem/Theme.swift`
- `Sources/Features/NotesList/NotesListView.swift`
- `Sources/Features/NotesList/FolderBrowserView.swift`
- `Sources/Features/Editor/NoteEditorView.swift`
- `Sources/Features/Editor/BlockViews.swift`（初版纯文本段落）

### 验收
1. `xcodegen generate`，选择 iOS 26 模拟器运行。
2. 新建、输入标题/正文、返回列表、删除、移动到文件夹。
3. 强杀重开，正文仍在（SwiftData 落盘）。

### 已知限制
- 纯文本 `TextEditor` 在阶段 1 可用；阶段 2 替换为 RTF 块编辑器。
- 示例数据会写入 4 条笔记 + 4 个文件夹；删除 `Persistence.seedIfNeeded` 可清空。

### 需补充的 Info.plist 键
- 无新增；阶段 1 已有 URL Scheme 和 `NSUserActivityTypes`。

---

## 阶段 2：核对清单 + 富文本样式 + 折叠

### 新增 / 修改
- 修改 `Sources/Models/NoteDocument.swift`：`ChecklistItem`、`ParagraphStyle`、`TableData`、`isCollapsed`、`hiddenBlockIDs()`
- 新增 `Sources/Features/Editor/RichTextEditor.swift`
- 修改 `Sources/Features/Editor/BlockViews.swift`
- 新增 `Sources/Features/Editor/EditorToolbar.swift`
- 修改 `Sources/Features/Editor/NoteEditorView.swift`

### 验收
1. 点击工具栏 `textformat` 设置 H1/H2/H3、正文、项目符号、编号、引用、高亮段落。
2. 标题左侧 V 箭头折叠该区域，直到下一个同级/更高级标题。
3. 核对清单勾选后出现删除线；可增删项目。
4. 选中文本后 B/I/高亮按钮生效。

### 已知限制
- 折叠是视觉隐藏，不删除块；导出时仍包含折叠内容。
- 富文本使用 RTF + `UITextView`，不是完整排版引擎。

### Info.plist
- 无新增。

---

## 阶段 3：附件系统（照片 / PDF / 链接 / 地图）

### 新增 / 修改
- 修改 `Sources/Models/Note.swift`：`Attachment`、`AttachmentKind`、`AttachmentMetadata`
- 新增 `Sources/Features/Attachments/AttachmentServices.swift`
- 新增 `Sources/Features/Attachments/AttachmentViews.swift`
- 新增 `Sources/Features/Attachments/PDFAnnotator.swift`
- 修改 `Sources/Features/Editor/NoteEditorView.swift`、`BlockViews.swift`

### 验收
1. 工具栏 `+` → 照片，选一张，正文出现内联缩略图，点击全屏预览。
2. 文件 App 选 PDF，正文出现 PDF 卡片，可预览。
3. 链接/地点卡片可插入并打开。
4. PDF 右上角“标注”，用 Pencil 画一笔，退出重进仍在。

### 已知限制
- PDF 标注是覆盖层，不是逐页 PDF 注释对象；缩放/翻页后坐标不随页面重排。
- 链接卡片不抓取 Open Graph 元数据；显示标题/域名。
- 大 PDF/照片建议后续改为附件文件外置存储管理（当前 `@Attribute(.externalStorage)`）。

### Info.plist
- `NSCameraUsageDescription`（扫描/相机）
- `NSPhotoLibraryUsageDescription`（PhotosPicker 读取用户选择项）

---

## 阶段 4：录音 + 实时转写 + 文档扫描

### 新增 / 修改
- 新增 `Sources/Features/Speech/VoiceRecorder.swift`
- 新增 `Sources/Features/Speech/RecordingPanel.swift`
- 修改 `Sources/Features/Attachments/AttachmentServices.swift`：OCR、PDFBuilder、DocumentScannerView、扫描附件
- 修改 `Sources/Features/Editor/NoteEditorView.swift`：录音块、时间标记、音频附件、扫描入口

### 验收
1. 工具栏麦克风，首次授权麦克风和语音识别。
2. 说 5 秒，正文出现 `[00:00] …` 转写；面板有波形。
3. 暂停/继续不丢文本；停止后插入音频附件。
4. 工具栏 `+` → 扫描，相机扫描一页，生成 PDF 附件；搜索 OCR 词可命中。
5. 无相机时（模拟器）走“照片 → OCR → PDF”回退。

### 已知限制
- SpeechAnalyzer 首次使用需系统共享模型；离线且未安装会回退 `SFSpeechRecognizer`。
- 模拟器通常无麦克风/语音识别，需真机。
- 转写是逐句追加；不做说话人分离、时间轴逐词对齐。
- 扫描多页 PDF 由图片合成，不做透视裁剪/增强。

### Info.plist
- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`
- `NSCameraUsageDescription`（扫描）
- `NSPhotoLibraryUsageDescription`（扫描回退/照片）

---

## 阶段 5：PencilKit 速绘 + 表格

### 新增 / 修改
- 新增 `Sources/Features/Editor/DrawingCanvas.swift`
- 修改 `Sources/Features/Editor/BlockViews.swift`：`TableBlockView`、速绘卡片
- 修改 `Sources/Features/Editor/NoteEditorView.swift`：速绘 sheet、OCR 手写文本回写

### 验收
1. `+` → 表格，编辑单元格，增删行/列。
2. `+` → 速绘，切换空白/网格/横线，选笔刷/颜色/橡皮，画一笔完成。
3. 返回编辑器看到缩略图；重开 App 仍在。
4. 在速绘上写字，退出后搜索该手写词可命中（Vision OCR 回退）。

### 已知限制
- 手写搜索在 iOS 26 用 Vision OCR，不是 `PKStrokeRecognizer`（后者 iOS 27）。
- 表格为简单二维网格，无合并单元格/公式。
- 速绘以 `PKDrawing.dataRepresentation()` 存块内；超大画布建议落外部文件。

### Info.plist
- 无新增。

---

## 阶段 6：标签 / 搜索 / 智能文件夹 / 内部链接

### 新增 / 修改
- 新增 `Sources/Features/Search/SearchService.swift`
- 新增 `Sources/Models/SmartFolderRule.swift`
- 新增 `Sources/Features/SmartFolders/SmartFolderEditor.swift`
- 新增 `Sources/Features/Editor/InternalLinkPicker.swift`
- 修改 `Sources/Features/NotesList/NotesListView.swift`
- 修改 `Sources/Models/NoteDocument.swift`（内部链接字段）

### 验收
1. 正文输入 `#设计`，列表出现标签；标签可筛选。
2. 搜索标题、正文、扫描 OCR、PDF 文本、手写 OCR。
3. 新建“含核对清单且本周创建”智能文件夹，只显示符合项。
4. 输入 `>>` 弹出备忘录选择器，插入内部链接卡片，点击跳转。
5. 文件夹支持嵌套、移动、重命名、删除（子项不删除）。

### 已知限制
- `SmartFolderRule` 用真实 NSPredicate block，但只在内存过滤，不下推 SwiftData；大数据量需 FTS。
- 内部链接目前是块卡片，不是行内富文本链接。
- `#标签` 只在保存/停止输入 500ms 后同步，编辑中有短暂延迟。

### Info.plist
- 无新增。

---

## 阶段 7：锁定 + 快速备忘录 / App Intents

### 新增 / 修改
- 新增 `Sources/Features/Lock/LockService.swift`
- 新增 `Sources/Features/Lock/LockGateView.swift`
- 新增 `Sources/Features/System/SharedCapture.swift`
- 新增 `Sources/Features/System/QuickCaptureIntent.swift`
- 新增 `Sources/Features/System/AppShortcuts.swift`
- 新增 `Widgets/LumenNotesWidgets.swift`
- 新增 `Resources/LumenNotesWidgets/Info.plist`
- 新增 `Resources/LumenNotesWidgets.entitlements`
- 修改 `Sources/App/LumenNotesApp.swift`、`RootView.swift`、`project.yml`

### 验收
1. 编辑器右上角锁 → 列表隐藏摘要 → 重开 App → 打开要求 Face ID/设备密码。
2. 解锁后切后台立即重锁；30s/1m/5m/不自动 计时重锁。
3. 锁定时正文 AES-GCM 加密，`contentData` 清空。
4. 控制中心添加“新建备忘录”控件，点击创建。
5. Siri/快捷指令“用流明笔记新建备忘录”；iPad 硬件键盘 Fn-Q 创建。
6. 桌面长按 App 图标“新建备忘录”。

### 已知限制
- Widget/Control Center 需要 App Group + 签名；模拟器可跑但共享容器可能需重新签名。
- Apple Pencil 右下角上滑是系统手势，App 无法编程触发；已提供 PencilKit 和 Fn-Q。
- 自动重锁是前台计时 + 后台立即锁；不监控设备闲置。
- 标题不加密，正文/纯文本/预览清空；如需标题保密，需扩展密文范围。

### Info.plist
- `NSFaceIDUsageDescription`
- `NSUserActivityTypes`（capture / note）
- `CFBundleURLTypes`（`lumen`）
- `UIApplicationShortcutItems`
- Widget extension 的 `NSExtensionPointIdentifier`

---

## 阶段 8：字体字号自定义 + 编辑器集成

### 新增 / 修改
- 新增 `Sources/DesignSystem/FontTheme.swift`
- 新增 `Sources/Features/Settings/FontSettingsView.swift`
- 修改 `Sources/Features/Editor/RichTextEditor.swift`（主题重排）
- 修改 `Sources/Features/Editor/NoteEditorView.swift`（Note 覆盖、字体 sheet）
- 修改 `Sources/DesignSystem/Theme.swift`（TagChip 字体）
- 修改所有正文渲染处，统一走 `FontTheme`

### 验收
1. 设置 Georgia 22pt，返回任意备忘录，正文即时以 Georgia 22pt 重排。
2. 六种字体每项以自身字形显示 “备忘录 Aa 123”。
3. 标题/正文/辅助三档分别 12–32pt，A-/A+ 与滑块同步。
4. 开/关“跟随系统动态字体”，系统设置放大字体时行为不同。
5. 打开“仅此备忘录”，改字体；返回列表再进，仍保留；关闭后回退全局。
6. 已有文本的粗体/斜体/高亮不因换字体丢失。

### 已知限制
- 系统隐藏字体（SF Pro/New York/SF Mono）可能无法用 PostScript 名解析，回退到同设计系统字体；不会崩溃但字形可能略变。
- 字号只影响笔记内容、标题与辅助文本；系统导航栏/菜单仍遵循系统 Dynamic Type。
- RTF 中显式字体在换主题时被重写；如果未来引入“逐字字体”需扩展。

### Info.plist
- 无新增。

---

## 阶段 9：Liquid Glass UI 层改造

### 新增 / 修改
- 新增 `Sources/DesignSystem/Glass.swift`
- 修改 `Sources/Features/Editor/EditorToolbar.swift`（`GlassEffectContainer` + `glassEffectID` 形变）
- 修改 `Sources/Features/Speech/RecordingPanel.swift`
- 修改 `Sources/Features/Settings/FontSettingsView.swift`
- 修改 `Sources/Features/NotesList/NotesListView.swift`（搜索栏/FAB 玻璃；行/卡片不玻璃）
- 修改 `Sources/Features/Lock/LockGateView.swift`（仅内容表面）

### 验收
1. 编辑器工具栏按钮有玻璃质感；相邻按钮融合；`+` 展开时形变。
2. 备忘录列表行、正文、附件卡片、表格单元格、标签 Chip、智能文件夹卡片**无玻璃**。
3. 低版本/iOS 26 以下回退 `.ultraThinMaterial` + 描边，不崩溃、可点击。
4. 开启“增强对比度”时回退不透明背景。
5. 导航栏、sheet、搜索栏、FAB、录音面板为玻璃。

### 已知限制
- 玻璃效果依赖 iOS 26 SDK 与模拟器/真机渲染；静态检查只能确认代码路径。
- 系统导航栏本身由 UIKit/SwiftUI 自动玻璃化，本项目不强行重绘。
- `buttonStyle(.glass)` 只用于按钮；`Menu` 用 `.lumenGlass` 手动包裹。
- 低版本回退不会获得 iOS 26 的形变融合，这是预期。

### Info.plist
- 无新增。

---

## 最终验收的硬门槛

在 Mac 上必须完成以下三条，才能把状态从“静态通过”改为“验收通过”：

```bash
xcodegen generate
xcodebuild build -scheme LumenNotes -destination 'generic/platform=iOS'
xcodebuild test -scheme LumenNotes -destination 'platform=iOS Simulator,name=iPhone 17'
```

然后再按 `docs/ACCEPTANCE.md` 做 11 个模块的手动验收。
