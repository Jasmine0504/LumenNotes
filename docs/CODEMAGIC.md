# 用 Codemagic 构建「流明笔记」

本文按 **先跑通模拟器编译，再上 TestFlight** 的顺序写。Codemagic 是远程 macOS CI，**不是** DSH iOS 插件的实时模拟器面板；它适合编译、单测、打包、签名和上传 TestFlight，不适合在对话里点按 UI。

当前仓库已包含：

- [codemagic.yaml](../codemagic.yaml)
- [project.yml](../project.yml)（已加 `VERSIONING_SYSTEM: apple-generic`）

---

## 0. 先理解两种 Workflow

| Workflow | 需要 Apple 账号？ | 作用 |
|---|---|---|
| `ios-simulator-ci` | 不需要 | Xcode 26.6 + iPhone 17 模拟器编译、跑单测、产出 `.app` 和 `.xcresult` |
| `ios-testflight` | 需要 | 签名、打包 IPA、上传 App Store Connect / TestFlight |

建议顺序：

1. 先跑 `ios-simulator-ci`，把编译错误修掉；
2. 再配置签名，跑 `ios-testflight`。

---

## 1. 把项目放进 Git 仓库

Codemagic 从 GitHub / GitLab / Bitbucket 拉代码。**建议把 `LumenNotes` 目录本身作为仓库根目录**，这样 `codemagic.yaml` 和 `project.yml` 都在根目录。

```bash
cd LumenNotes
git init
git add .
git commit -m "Initial LumenNotes iOS 26 app"
git branch -M main
git remote add origin <你的仓库地址>
git push -u origin main
```

不要把以下文件提交到仓库：

- `*.p8`（App Store Connect API 私钥）
- `*.p12` / `*.cer`（签名证书）
- `*.mobileprovision`（描述文件）
- `build/`、`DerivedData/`

当前 [.gitignore](../.gitignore) 已忽略构建产物。

> 如果你的仓库根目录是整个工作区（包含 `LumenNotes/` 子目录），请在 Codemagic 的 App 设置里把 **Project path** 指到 `LumenNotes`；否则它找不到 `codemagic.yaml`。

---

## 2. 在 Codemagic 添加 App

1. 登录 [codemagic.io](https://codemagic.io)，用 GitHub/GitLab/Bitbucket 授权。
2. **Add application** → 选择仓库。
3. 构建配置选择 **Codemagic YAML**（不要选 Workflow Editor）。
4. Codemagic 会自动读取根目录的 `codemagic.yaml`。
5. 打开 **ios-simulator-ci**，点 **Start new build**。

第一次建议先手动跑，不要开 push 自动触发；等编译通过后再启用 `main` 分支触发。

---

## 3. 第一轮：只跑模拟器编译

`ios-simulator-ci` 做的事：

```text
xcodebuild -version
xcrun simctl list runtimes
python3 Tools/preflight.py
brew install xcodegen（如果不存在）
xcodegen generate
xcodebuild build  -destination "platform=iOS Simulator,name=iPhone 17,OS=latest"
xcodebuild test   -destination "platform=iOS Simulator,name=iPhone 17,OS=latest"
```

Codemagic 当前的 Xcode 26.6 镜像包含 **iOS 26.6 模拟器运行时** 和 **iPhone 17 / iPhone 17 Pro** 设备。参考 [Codemagic Xcode 26.0 规格](https://docs.codemagic.io/specs-macos/xcode-26-0/)（26.6 镜像同样提供 iPhone 17 系列）。

如果日志里提示找不到设备，把 `codemagic.yaml` 的：

```yaml
SIM_NAME: "iPhone 17"
```

改成日志中存在的设备名，例如 `iPhone 17 Pro` 或 `iPhone 16`。也可以把目标写成：

```bash
-destination "platform=iOS Simulator,name=iPhone 17,OS=latest"
```

### 这一轮看什么

- `xcodebuild build` 是否零错误；
- `LumenNotesTests` 是否通过；
- `build/TestResults.zip` 是否出现在 Artifacts；
- 如果失败，先看 **Build for iOS Simulator** 或 **Run unit tests** 步骤最后 100 行。

这一轮不需要证书，也不需要 Apple Developer Program。**这是当前 Windows 环境下最值得先做的事**：它能真正替代我们之前无法做的编译验证。

---

## 4. 第二轮：TestFlight 前置配置

### 4.1 Bundle ID 必须改成你自己的

当前模板用的是：

```text
com.lumen.notes
com.lumen.notes.widgets
group.com.lumen.notes
```

大概率已被占用，而且 App Group 需要在你的开发者账号下注册。请统一替换成你自己的反向域名，例如：

```text
com.yourname.lumennotes
com.yourname.lumennotes.widgets
group.com.yourname.lumennotes
```

不要只改 `project.yml`。Bundle ID、App Group、App Intents 类型、ControlWidget kind、Keychain service、URL Scheme 的 activity 类型都从 `com.lumen.notes` 派生；建议一次性全局替换源码/资源里的前缀：

```bash
OLD=com.lumen.notes
NEW=com.yourname.lumennotes

# macOS：只改代码/工程/资源，不改 README 和 docs
grep -rl --include='*.swift' --include='*.yml' --include='*.plist' \
  --include='*.entitlements' --include='*.xcprivacy' --include='*.py' "$OLD" . \
  | grep -v '^./docs/' | grep -v '^./README.md' \
  | xargs sed -i '' "s/$OLD/$NEW/g"

# 同步 codemagic.yaml 的占位符
sed -i '' "s/com.yourcompany.lumennotes/$NEW/g" codemagic.yaml
```

这会同时更新：

- `project.yml` 的 App / Widget / Tests Bundle ID
- `Resources/LumenNotes.entitlements` 和 Widget entitlements 的 App Group
- `Resources/Info.plist` 的 `NSUserActivityTypes` / `CFBundleURLTypes` / 快捷项
- `Sources/Features/System/SharedCapture.swift` 的 `appGroup`
- `Widgets/LumenNotesWidgets.swift` 的 ControlWidget kind
- `Sources/Features/Lock/LockService.swift` 的 Keychain service
- `codemagic.yaml` 的 `BUNDLE_ID`、`ios_signing.bundle_identifier`、`APP_GROUP`

改完在本地重新：

```bash
xcodegen generate
```

> Widget 扩展必须有**自己的 App ID、自己的描述文件**；它的 Bundle ID 必须是主 App 的前缀（`com.yourname.lumennotes.widgets`）。Codemagic 会按 `bundle_identifier` 前缀匹配扩展的描述文件。

### 4.2 在 Apple Developer 配好 App Group

1. 登录 [developer.apple.com](https://developer.apple.com/account)。
2. **Identifiers** → 新建 App ID：
   - 主 App：`com.yourname.lumennotes`
   - Widget：`com.yourname.lumennotes.widgets`
3. 给两个 App ID 都启用 **App Groups**。
4. 在 **App Groups** 里创建 `group.com.yourname.lumennotes`，并勾选给两个 App ID。
5. 创建 **App Store** 类型的 Provisioning Profile：
   - 主 App
   - Widget
   - 两者都要包含 App Groups capability
6. 在 App Store Connect 创建 App 记录，Bundle ID 选主 App。

没有 App Group 的 profile，构建会在签名/安装阶段失败，常见报错是：

```text
Provisioning profile doesn't include the App Groups entitlement
```

### 4.3 创建 App Store Connect API Key

1. App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API**。
2. 生成一个 Key，权限选 **App Manager**。
3. 记下 **Issuer ID**、**Key ID**，下载 `.p8`（只能下载一次）。
4. 不要把 `.p8` 提交进 Git。

### 4.4 在 Codemagic 配置 Developer Portal 集成

1. Codemagic → **Team settings** → **Team integrations** → **Developer Portal**。
2. 添加 key：
   - **Name**：`lumennotes-appstore`（要和 `codemagic.yaml` 的 `integrations.app_store_connect` 一致）
   - Issuer ID
   - Key ID
   - 上传 `.p8`
3. 在 **Code signing identities** 里：
   - 上传/生成 **Apple Distribution** 证书；
   - 上传/获取主 App 和 Widget 的 **App Store** 描述文件。
4. 如果使用 `xcode-project use-profiles`，Codemagic 会自动把匹配的 profile 应用到工程。

### 4.5 修改 `codemagic.yaml` 里的占位符

把：

```yaml
integrations:
  app_store_connect: lumennotes-appstore
...
bundle_identifier: com.yourcompany.lumennotes
...
BUNDLE_ID: "com.yourcompany.lumennotes"
APP_GROUP: "group.com.yourcompany.lumennotes"
```

换成你自己的值。`ios_signing.bundle_identifier` 只写主 App；Codemagic 会自动带出 `.widgets` 扩展 profile。

---

## 5. 跑 TestFlight Workflow

在 Codemagic 里打开 **ios-testflight** → **Start new build**。

流程：

```text
Validate bundle identifiers and App Group
xcodegen generate
agvtool new-version -all $(($BUILD_NUMBER + 1))
xcode-project use-profiles
xcode-project build-ipa --project LumenNotes.xcodeproj --scheme LumenNotes
upload IPA to App Store Connect
submit to TestFlight
```

### 构建号

`project.yml` 已设置：

```yaml
VERSIONING_SYSTEM: apple-generic
CURRENT_PROJECT_VERSION: 1
```

`agvtool new-version -all $(($BUILD_NUMBER + 1))` 会用 Codemagic 的 `BUILD_NUMBER` 递增 `CFBundleVersion`。同一个 `CFBundleShortVersionString` 下，每次上传 TestFlight 的 Build 号必须不同。

如果构建号冲突，可把 step 换成从 TestFlight 查最新号：

```bash
LATEST=$(app-store-connect get-latest-testflight-build-number "$APP_APPLE_ID")
agvtool new-version -all $(($LATEST + 1))
```

需要配置 `APP_APPLE_ID`（App Store Connect 里的 Apple ID，不是 Bundle ID）。

### 上传后

- 内部测试员通常很快可见；
- 外部测试员需要 Beta App Review；
- 第一次上传仍需要在 App Store Connect 手动补截图、隐私政策、分类等信息；
- `submit_to_testflight: true` 只是上传并提交 TestFlight，不会自动提交 App Store 审核。

---

## 6. Codemagic 不能替你做什么

| 事情 | Codemagic | 本机 Mac + DSH iOS 插件 |
|---|---|---|
| 编译 / 单测 | ✅ | ✅ |
| 打包 IPA / TestFlight | ✅ | ✅ |
| 交互式点按模拟器 | ❌（无实时面板） | ✅ `ios_sim_interact` / `ios_sim_tap_*` |
| SwiftUI 预览热重载 | ❌ | ✅ `ios_sim_preview` |
| 真机 USB 调试 | ❌（云端无 USB） | ✅ `ios_real_start_wda` |
| 运行 UI 测试 | ✅（需添加 UITest target） | ✅ |

所以：**Codemagic 用来做“真编译 + 真测试 + 真上架”，DSH iOS 插件用来做“真机/模拟器交互验收”。** 两者互补，不要互相替代。

---

## 7. 常见失败与处理

### `xcodegen: command not found`

Codemagic 的 step 已自动 `brew install xcodegen`。如果 Homebrew 权限/网络失败，改用 CocoaPods 无关；直接重跑，或在 `codemagic.yaml` 里换成 `brew install xcodegen` 的固定版本。

### `Unable to find a destination matching ... iPhone 17`

在 `Show toolchain and simulator runtimes` 日志里看实际设备名，修改 `SIM_NAME`。

### `No signing certificate "iOS Distribution" found`

Codemagic 的 Code signing identities 里没有 Apple Distribution 证书。上传 `.p12` 或让 Codemagic 生成。

### `Provisioning profile doesn't include the App Groups entitlement`

App Group 没有配到 App ID / profile。回到 Apple Developer 修 App ID，再重新生成 profile，重新上传 Codemagic。

### `No profile for team ... matching 'com.yourname.lumennotes.widgets'`

Widget 扩展也需要 App ID 和 App Store profile。只配主 App 不够。

### `Invalid Bundle Identifier` / `The App Store Connect API key does not have permission`

检查 Bundle ID 是否和 App Store Connect App 记录一致，API Key 是否有 App Manager 权限。

### TestFlight 一直 processing

Codemagic 的 post-processing 有 15 分钟查找超时；如果 App Store Connect 邮件提示二进制无效，按邮件修。常见原因是缺少隐私清单、App Group 权限、或 `CFBundleVersion` 冲突。

---

## 8. 建议的第一次执行顺序

1. `ios-simulator-ci` → 修编译错误。
2. 修完后再改 Bundle ID / App Group。
3. 本地 `xcodegen generate`，`xcodebuild build` 再确认一次。
4. 配 Apple Developer App ID / App Group / profiles。
5. 配 Codemagic Developer Portal + Code signing identities。
6. `ios-testflight`。
7. 内部 TestFlight 安装，按 [ACCEPTANCE.md](ACCEPTANCE.md) 做真机验收。

---

## 9. 参考

- [Codemagic: App Store Connect publishing](https://docs.codemagic.io/yaml-publishing/app-store-connect/)
- [Codemagic: Signing iOS apps](https://docs.codemagic.io/yaml-code-signing/signing-ios/)
- [Codemagic: Automatic build versioning](https://docs.codemagic.io/knowledge-codemagic/build-versioning/)
- [Codemagic Xcode 26.0 specs（含 iOS 26 模拟器设备清单）](https://docs.codemagic.io/specs-macos/xcode-26-0/)
