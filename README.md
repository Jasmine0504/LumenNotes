# 流明笔记 · LumenNotes

一款面向 **iOS 26** 的 SwiftUI 备忘录 App。核心差异是**可逐条覆盖的字体/字号系统**与**严格分层的 Liquid Glass**：玻璃只服务导航和控制，正文、列表行、附件卡片、表格单元格永远是安静的实色纸张。

> **重要：当前环境无法完成模拟器验收。**
> 本会话运行在 Windows（`Microsoft Windows NT 10.0.26200.0`），没有 `xcodebuild`、`swift`、`xcrun simctl`，DSH 本身也没有 SwiftUI 预览热重载/模拟器桥接。因此：
> - 已做：tree-sitter Swift 语法解析、plist/JSON/资源校验、79 项静态预检；
> - 未做：Xcode 编译、iOS 26 模拟器运行、Face ID/相机/麦克风真机验收。
>
> 请在一台装有 **Xcode 26 + iOS 26 SDK** 的 Mac 上按下方步骤构建。不要把本文的“静态通过”误解为“编译通过”。

---

## 1. 快速开始

```bash
brew install xcodegen
cd LumenNotes
xcodegen generate
open LumenNotes.xcodeproj
```

### 没有 Mac？用 Codemagic 远程编译

仓库已包含 [codemagic.yaml](codemagic.yaml) 和 [docs/CODEMAGIC.md](docs/CODEMAGIC.md)：

- `ios-simulator-ci`：Xcode 26.6 + iPhone 17 模拟器，先跑通编译和单测（不需要证书）
- `ios-testflight`：签名、打包 IPA、上传 TestFlight

这是当前 Windows 环境下最现实的“真编译”路径。它不提供 DSH 插件的实时模拟器面板；交互验收仍需本机 Mac 或 Codemagic 上的 UI 测试。

选择 iOS 26 模拟器或真机运行。首次运行会写入一组示例备忘录，便于直接检查核对清单、智能文件夹、字体和玻璃边界。

### 签名 / App Group

App 与 Widget 共享 `group.com.lumen.notes`（控制中心快速新建需要）。如果使用自己的开发者账号：

1. 同时修改 `project.yml` 里的 `PRODUCT_BUNDLE_IDENTIFIER`（App 与 Widget 两处）；
2. 在 Xcode 的 Signing & Capabilities 中给两个 target 都添加 **App Groups**；
3. 把两处 entitlements 与 `SharedCapture.appGroup` 改成你的 group；
4. 若只跑主 App、不跑 Widget，可先删除 `LumenNotesWidgets` target 依赖。

### 前置

- macOS + Xcode 26（iOS 26 SDK）
- XcodeGen 2.44+
- 真机体验完整 Liquid Glass、Face ID、相机扫描、SpeechAnalyzer；模拟器只能覆盖部分 UI 与持久化

---

## 2. 静态验证（Windows 可跑）

```powershell
python .\Tools\preflight.py

# 可选：tree-sitter 语法解析（需要 pip install tree-sitter tree-sitter-swift）
python .\Tools\parse_swift.py
```

`preflight.py` 检查：

- 所有 Swift 文件括号配平；
- Info.plist / entitlements / Assets JSON 合法；
- 五项隐私用途说明、URL Scheme、NSUserActivity 类型；
- 源码中不存在硬编码 `.system(size:)`；
- Liquid Glass 没有进入 `BlockViews.swift` / `AttachmentViews.swift`；
- 玻璃降级（`ultraThinMaterial` + 高对比度不透明背景）存在；
- 六个字体族、`Font.custom(_:size:relativeTo:)`、Dynamic Type 开关存在；
- SpeechAnalyzer 与 SFSpeechRecognizer 双路径、Vision OCR、VisionKit 扫描、PencilKit、PDF 标注、ControlWidget、AppShortcuts 均存在；
- 部署目标为 iOS 26.0，Widget extension target 已声明。

本次结果：**79/79 通过**；tree-sitter：**33 个 Swift 文件 0 语法错误**。这两个结果都不等于编译通过。

---

## 3. 功能地图（11 个模块）

| 模块 | 实现 | 主要文件 |
|---|---|---|
| 1 基础备忘录 | 新建/删除/移动/文件夹，标题与正文分离，`@Query` 列表 | `Models/Note.swift`、`Persistence/Persistence.swift`、`Features/NotesList/NotesListView.swift`、`Features/NotesList/FolderBrowserView.swift` |
| 2 核对清单/富文本/折叠 | RTF `UITextView` 富文本（粗体/斜体/高亮）、H1/H2/H3、项目符号/编号/引用/高亮段落、标题 V 折叠 | `Features/Editor/RichTextEditor.swift`、`BlockViews.swift`、`Models/NoteDocument.swift` |
| 3 附件系统 | 照片、PDF、扫描 PDF、链接卡片、地图卡片、内联卡片、全屏预览、PDF + PencilKit 标注层 | `AttachmentServices.swift`、`AttachmentViews.swift`、`PDFAnnotator.swift` |
| 4 录音/实时转写 | AVAudioEngine 波形、SpeechAnalyzer 设备端逐句结果、SFSpeechRecognizer 回退、暂停/继续、音频附件 | `Speech/VoiceRecorder.swift`、`RecordingPanel.swift` |
| 5 文档扫描 | `VNDocumentCameraViewController` 多页扫描、PDF 合成、Vision OCR、OCR 进入搜索 | `AttachmentServices.swift`、`NotesListView` 搜索链 |
| 6 表格/速绘 | 可编辑 `TableData` 行列增删、PencilKit 画布、笔刷/颜色/橡皮（系统 PKToolPicker）、空白/网格/横线背景、`PKDrawing.dataRepresentation()` 持久化 | `BlockViews.swift`、`DrawingCanvas.swift` |
| 7 整理/搜索/智能文件夹 | 嵌套文件夹、`#标签` 自动建 Tag、`>>` 内部链接、标题/正文/OCR/手写文本搜索、条件构建器 + NSPredicate | `SearchService.swift`、`SmartFolderEditor.swift`、`InternalLinkPicker.swift`、`SmartFolderRule.swift` |
| 8 锁定 | Face ID/Touch ID/Optic ID/设备密码、AES-GCM 正文加密、列表隐藏摘要、后台立即重锁、启动时强制重锁、超时重锁 | `Features/Lock/LockService.swift`、`LockGateView.swift` |
| 9 快速备忘录/系统集成 | Control Center `ControlWidget`、App Intents、App Shortcuts、NSUserActivity、桌面快捷项、Fn-Q 命令 | `Features/System/*`、`Widgets/LumenNotesWidgets.swift`、`App/RootView.swift` |
| 10 字体字号 | 6 个字体族、标题/正文/辅助三档 12–32pt、A-/A+、Dynamic Type 开关、Note 级覆盖、即时重渲染 | `DesignSystem/FontTheme.swift`、`Features/Settings/FontSettingsView.swift` |
| 11 Liquid Glass | `.buttonStyle(.glass)`、`.glassEffect`、`GlassEffectContainer`、`glassEffectID` 形变、降级材质、高对比度回退 | `DesignSystem/Glass.swift`、`EditorToolbar.swift`、`NotesListView.swift` |

---

## 4. 字体系统（核心差异化）

### 4.1 六个字体族

`FontFamily`：SF Pro、SF Mono、New York、Georgia、Palatino、PingFang SC。

- 每一项都用对应字体渲染 `备忘录 Aa 123`；
- 优先 `Font.custom(_:size:relativeTo:)`；
- SF Pro / New York / SF Mono 属于系统隐藏族时，通过 `UIFont` + `UIFontMetrics` 回退，仍保持 Dynamic Type；
- PingFang SC 提供 `PingFangSC-Light/Regular/Semibold` 四档；
- Georgia / Palatino 使用系统自带族名。

### 4.2 三档字号

- 标题 `titleSize` 默认 28；
- 正文 `bodySize` 默认 17；
- 辅助 `captionSize` 默认 13；
- 全部滑块 `12...32`，step 1，同时有 A-/A+；
- 所有尺寸从 `FontTheme` 读取，全局无硬编码 `.system(size:)`。

### 4.3 Dynamic Type 语义

- 开启：`Font.custom(name, size: base, relativeTo: style)`，手动字号作为基准叠加系统缩放；
- 关闭：`Font.custom(name, fixedSize:)`，严格使用手动字号；
- 富文本编辑器同步用 `UIFontMetrics` 缩放，并在主题变更时**重新应用字体到已有 attributed string**，不会丢粗体/斜体/高亮。

### 4.4 Note 级覆盖

`Note.fontOverrideData` 存 `NoteFontOverride`：

- 打开“仅此备忘录”时复制全局主题到本条；
- 未设置的字段逐项回退全局；
- 关闭时清空，回到全局；
- 编辑器通过 `theme.font(for:override:)` / `theme.uiFont(...)` 即时重渲染。

---

## 5. Liquid Glass 边界

### 允许玻璃

- 顶部/底部导航栏（系统原生）
- 编辑器浮动工具栏、录音面板
- 搜索栏（浮动控制）
- 新建 FAB、快速备忘录入口
- 字体调节面板容器
- 模态 sheet 内控件（系统原生）

### 禁止玻璃

- 备忘录列表行：`NoteListRow` 只用 `ContentSurface` 实色
- 编辑器正文：`LumenBackground` + 不透明纸面，无 glass
- 附件卡片：`AttachmentCard` 只用 `ContentSurface`
- 表格单元格：`tertiarySystemFill`
- 内容态标签 Chip：`TagChip` 实色 tint
- 智能文件夹列表行/卡片：`contentSurface`

### 降级

`GlassSurfaceModifier`：

- iOS 26+：`.glassEffect(.regular.interactive(), in:)` / `.glassEffect(.regular, in:)`
- 旧系统：`.ultraThinMaterial` + `separator` 描边
- `accessibilityContrast == .increased`：不透明 `secondarySystemBackground` + 描边

`GlassGroup` 在 iOS 26 用 `GlassEffectContainer` 包裹相邻玻璃控件；`GlassMorphID` 用 `glassEffectID` 做插入面板的形变过渡。所有玻璃入口都经过 `if #available(iOS 26.0, *)`。

---

## 6. 数据与安全

### SwiftData 模型

- `Note`：标题、`contentData`、`plainText`、时间、锁定/保护标记、字体覆盖、文件夹、标签、附件
- `Folder`：自引用父子、notes
- `Tag`：唯一名称、notes
- `SmartFolder`：`ruleData`、`predicate` 描述
- `Attachment`：kind、data（externalStorage）、OCR 文本、元数据、PDF 标注层

`NoteDocument` 是版本化 JSON：`heading` / `paragraph` / `checklist` / `table` / `drawing` / `attachment` / 内部链接。段落用 `RichText` 存 RTF + 纯文本镜像。

### 加密

- `NoteCipher`：CryptoKit AES-GCM；
- 256 位密钥存 Keychain，`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`；
- 锁定时加密 `contentData` 到 `lockedContentData`，清空 `contentData` 与 `plainText`；
- 列表只显示锁图标；
- `isProtected` 记录“曾经锁定”，App 冷启动时即使上次处于解锁状态也会强制重新上锁；
- 退到后台立即重锁所有受保护且打开的备忘录；
- 解锁后按 30s/1m/5m/不自动 计时重锁。

### 智能文件夹

`SmartFolderRule` 生成**真实 `NSPredicate`**（block 形式）并在已加载的 `[Note]` 上实时求值。SwiftData 对关系条件（tags/attachments）的下推不可靠，所以不把该 predicate 塞进 `FetchDescriptor`；UI 同时展示谓词字符串。条件包含：日期、核对清单状态、附件类型、标签、锁定状态。

### 搜索

`SearchService` 归一化后按 token 全匹配：

- 标题、正文纯文本
- 手写图 OCR 文本（`drawingSearchText`）
- 扫描 PDF OCR
- PDF 文本
- 附件文件名
- 链接标题/域名、地图名、标签

---

## 7. 工具链命令

### Mac

```bash
xcodegen generate
xcodebuild build -scheme LumenNotes -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -scheme LumenNotes -destination 'platform=iOS Simulator,name=iPhone 17'
```

### Windows

```powershell
python .\Tools\preflight.py

# 可选：tree-sitter 语法解析（需要 pip install tree-sitter tree-sitter-swift）
python .\Tools\parse_swift.py
```

---

## 8. 已知限制（请按优先级阅读）

1. **没有编译/模拟器验证**：本机无 Xcode，无法声称“可编译/验收通过”。请先在 Mac 跑 `xcodebuild`；最可能的首轮问题是 iOS 26 API 名称或 SwiftData 关系配置。
2. **SpeechAnalyzer 资产**：首次使用可能需要下载系统共享模型；离线且未安装时会回退 `SFSpeechRecognizer`。`SFSpeechRecognizer` 在模拟器上常常不可用，需真机。
3. **`PKStrokeRecognizer` 是 iOS 27 API**（Apple 文档 `introducedAt: 27.0`），不在 iOS 26 可用范围。本项目用手写图 → Vision OCR 作为 iOS 26 的手写搜索路径；iOS 27 可替换为 `PKStrokeRecognizer.indexableContent`。
4. **PaperKit**：`PaperMarkupViewController` 是 iOS 26，但本项目速绘/PDF 标注采用 PencilKit `PKCanvasView`（更稳定、可控）；PaperKit 未接入。
5. **PDF 标注坐标系**：当前是屏幕覆盖层，不是逐页 `PDFPageOverlayViewProvider`；缩放/翻页后标注不会随页面重排。生产版应改为逐页 overlay。
6. **扫描仪**：模拟器没有相机；代码检测 `VNDocumentCameraViewController.isSupported`，不支持时改为“照片 → OCR → PDF”回退。
7. **Widget/Control Center**：需要 App Group 和正确的签名；如果不想配置，可先删掉 Widget target，仅保留 App Intents / Shortcuts。
8. **Apple Pencil 右下角上滑**：这是系统级 Quick Note 手势，App 无法编程触发。已提供 PencilKit 画布与 Fn-Q 命令；iPad 系统手势需在系统设置中开启。
9. **富文本边界**：块级样式 + 行内粗体/斜体/高亮；不是完整文档排版引擎，暂无表格合并单元格、脚注、协作。
10. **搜索规模**：当前对 SwiftData 已加载对象做内存过滤；十万条以上应改 FTS5/Spotlight 索引。
11. **字体回退**：如果系统不暴露某个 PostScript 名，会回退到同设计风格的系统字体；这不会崩溃，但字形可能与设计稿略有差异。
12. **单测未运行**：`Tests/LumenNotesTests/DomainTests.swift` 只是可执行规格，需在 Xcode 中运行。

---

## 9. 目录

```
LumenNotes/
├── project.yml
├── codemagic.yaml
├── README.md
├── docs/
│   ├── ACCEPTANCE.md
│   ├── CODEMAGIC.md
│   └── STAGES.md
├── Resources/
│   ├── Info.plist
│   ├── PrivacyInfo.xcprivacy
│   ├── LumenNotes.entitlements
│   ├── LumenNotesWidgets.entitlements
│   ├── Assets.xcassets/
│   └── LumenNotesWidgets/Info.plist
├── Sources/
│   ├── App/                 # @main、容器、根导航、命令
│   ├── Models/              # SwiftData + NoteDocument + SmartFolderRule
│   ├── Persistence/         # ModelContainer、seed
│   ├── DesignSystem/        # FontTheme、Glass、Theme
│   └── Features/
│       ├── NotesList/       # 列表、文件夹
│       ├── Editor/          # 编辑器、块、富文本、速绘、内链
│       ├── Attachments/     # 附件、OCR、扫描、PDF 标注
│       ├── Speech/          # 录音、SpeechAnalyzer、波形
│       ├── Search/          # 搜索与 #标签
│       ├── SmartFolders/    # 条件构建器
│       ├── Settings/        # 字体/字号/锁定时长
│       ├── Lock/            # 加密、Face ID、解锁门
│       └── System/          # App Intents、Shortcuts、共享队列
├── Widgets/                 # Control Center 扩展
├── Tests/                   # 领域/富文本测试
└── Tools/                   # preflight、tree-sitter parse、icon
```

---

## 10. 一句话设计原则

> 玻璃负责“去哪里”，纸负责“读什么”。字体负责“这是谁的笔记”。
