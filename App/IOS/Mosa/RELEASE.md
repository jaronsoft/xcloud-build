# MOSA iOS 自动构建与上传

## 版本编号规则

MOSA iOS 版本采用 `主版本.次版本[.修订版本] (Build 递增整数)`，当前基线为 `1.2 (Build 21)`。`MARKETING_VERSION` 表示用户可见的软件版本；`CURRENT_PROJECT_VERSION` 表示 App Store Connect Build Number，必须使用从 1 开始连续递增的正整数。每次上传前递增 Build Number，已上传的数字不得复用；不再使用 `YYYYMMDD`、`YYYYMMDD.N` 等日期型构建号。

发布脚本会在归档和上传前校验这两项格式，但不会自动修改工程版本。产品版本发生变化时人工更新 `MARKETING_VERSION`，每次生成新的上传构建时人工递增 `CURRENT_PROJECT_VERSION`，并保持 Debug 与 Release 配置一致。

2026-10-04，App Store Connect 拒绝 `1.1 (Build 20)`，提示 1.1 预发布列车已关闭，且 `CFBundleShortVersionString` 必须高于已批准的 1.1。工程已更新为 `1.2 (Build 21)`，供下一次 Xcode Cloud 上传使用。

2026-08-10，Gallery 分享卡新增按账号隔离的本地持久缓存：优先展示最近一次成功版本，启动同步后静默预热，且仅在新图完整下载、解码校验成功后原子覆盖旧缓存。iOS `1.0 (20260810)` 已使用正式 Xcode 26.6（`17F113`）和 iPhoneOS 26.5 SDK 完成 iPhone 17 / iOS 27 Simulator XCTest 27/27、Release Archive、Bundle/Team/版本、代码签名和 Entitlements 校验，并上传 App Store Connect。Archive 为 `.release/archives/MOSA-1.0-20260810-20260810-081355.xcarchive`。本次只上传 Build，未提交审核、修改测试组或商店元数据。

2026-08-05，包含 `SHARE_CARD_VISUAL_LAYER` 独立阶段及 `FAILED · CARD VISUAL` 失败定位的 iOS `1.0 (20260805)` 已上传 App Store Connect。按用户明确的 TestFlight 目标使用 Xcode 27 Beta（`27A5228h`）特殊流程；iPhone 17 / iOS 27 Simulator XCTest 26/26、Release Archive、Bundle/Team/版本、代码签名和 Entitlements 校验通过，Apple 返回 `Upload succeeded` 并开始处理。Archive 为 `.release/archives/MOSA-1.0-20260805-20260805-123053.xcarchive`。本次只上传 Build，未提交审核、修改测试组或商店元数据；该 Beta 构建不作为正式审核候选。

2026-08-04，V1.2 分享卡复用 AnnualArtwork 上游、生成等待提示和鉴权图片静默刷新修复已重新上传为 iOS `1.0 (20260804.1)`。本机未安装默认正式工具链 Xcode 26.6，因此按用户明确的 TestFlight 目标使用 Xcode 27 Beta（`27A5228h`）特殊流程；iPhone 17 / iOS 27 Simulator XCTest 26/26、Release Archive、Bundle/Team/版本、代码签名和 Entitlements 校验通过，Apple 返回 `Upload succeeded` 并开始处理。Archive 为 `.release/archives/MOSA-1.0-20260804.1-20260804-165419.xcarchive`。本次只上传 Build，未提交审核、修改测试组或商店元数据；该 Beta 构建不作为正式审核候选。

2026-08-03，H5/iOS Gallery 的年度原画现会在 `SUCCEEDED` 后显示真实下载进度（未知长度时显示加载动画）、失败重试和仅 PNG 分享；H5 不支持文件分享的浏览器会下载 PNG。iOS `1.0 (20260803)` 使用 Xcode 27 Beta（`27A5228h`）完成 XCTest 24/24、Release Archive、签名校验和 App Store Connect 上传，Apple 返回 `Upload succeeded` 并开始处理。Archive 为 `.release/archives/MOSA-1.0-20260803-20260803-162155.xcarchive`。本次只上传 Build，未提交审核、修改测试组或商店元数据。

2026-08-02，Gallery 生图生命周期现在区分提交中 `SUBMITTING`、等待图像服务器 `QUEUED` 与绘制中 `RUNNING`。构建 `1.0 (20260802)` 已使用正式 Xcode 26.6（`17F113`）和 iPhoneOS 26.5 SDK 完成 XCTest 22/22、Release Archive、签名与 Entitlements 校验，并通过 Xcode Account authentication 上传 App Store Connect；Apple 返回 `Upload succeeded` 并开始处理。Archive 为 `.release/archives/MOSA-1.0-20260802-20260802-210455.xcarchive`。本次只上传 Build，未提交审核、修改测试组或调整商店元数据。

2026-08-01，合并远端首页窄屏横向溢出修复与阶段预览/每日 Canvas 隔离修复后，最终一致构建 `1.0 (20260801.1)` 已使用正式 Xcode 26.6（`17F113`）和 iPhoneOS 26.5 SDK 完成 XCTest 22/22、Release Archive、签名校验和 App Store Connect 上传，Apple 返回 `Upload succeeded` 并开始处理。Archive 为 `.release/archives/MOSA-1.0-20260801.1-20260801-093652.xcarchive`。该构建来自正式工具链，可在处理与真机验收通过后作为正式审核候选；此前上传的 `20260801` 仅保留为过渡构建。

2026-07-31，修复 iOS 首页窄屏横向溢出的 `1.0 (20260731.1)` 已按 TestFlight 特殊构建流程使用 Xcode 27 Beta（`27A5228h`）完成 XCTest 22/22、Release Archive、签名校验和 App Store Connect 上传，Apple 返回 `Upload succeeded` 并开始处理。Archive 为 `.release/archives/MOSA-1.0-20260731.1-20260731-162513.xcarchive`。该构建仅用于 TestFlight，不用于正式审核。

2026-07-31，包含 AI 年度作品六主题、人生阶段全年视觉底色、H5/iOS 同步统计对齐的 `1.0 (20260731)` 已按 TestFlight 特殊构建流程使用 Xcode 27 Beta（`27A5228h`）完成 XCTest 22/22、Release Archive、签名校验和 App Store Connect 上传，Apple 返回 `Upload succeeded` 并开始处理。Archive 为 `.release/archives/MOSA-1.0-20260731-20260731-155939.xcarchive`。该构建仅用于 TestFlight，不用于正式审核。

## 发布架构

发布入口是 `scripts/ios-release.sh`。脚本从自身位置推导工程目录，只操作 `MOSA.xcodeproj` 的共享 Scheme `MOSA`，并把 Archive、IPA、日志和 DerivedData 统一写入 `.release/`。`release` 的流程为 `doctor → archive → verify → upload`，只把 Build 上传到 App Store Connect，不会提交审核、自动发布或修改商店元数据。

脚本从 `MOSA` 主应用 Target 的 `xcodebuild -showBuildSettings` 结果读取 Bundle ID、Team、版本号和 Build Number，不猜测或自动修改 `project.pbxproj`。预检要求 `MARKETING_VERSION` 为两段或三段数字版本号，并要求 `CURRENT_PROJECT_VERSION` 为正整数。

## 多机器 Xcode 选择策略

MOSA 的正式审核归档和上传默认固定为 Xcode `26.6 (17F113)`。其他开发机可以继续保留 Xcode 27 做日常开发；发布脚本只有在调用方同时显式覆盖 Xcode 路径、版本和 Build 时才允许使用其他工具链。

脚本按以下顺序查找完全匹配的 Xcode 26.6：

1. 本机 `release-config` 或环境变量中的 `MOSA_XCODE_APP_PATH`。
2. `/Applications/Xcode-26.6.app`。
3. `/Applications/Xcode-26.6.0.app`。
4. `/Applications/Xcode.app`。

没有找到精确版本时会停止并提示执行环境安装脚本，不会自动退回 Xcode 27。项目中的 `.xcode-version` 也声明为 `26.6`，供 `xcodes` 和兼容工具识别团队约定。

如果 Xcode 26.6 安装在其他位置，可在本机不提交的 `release-config` 中指定：

```bash
MOSA_XCODE_APP_PATH=/Applications/Developer/Xcode-26.6.app
```

该值可以指向 `Xcode.app`，也可以直接指向其 `Contents/Developer`。脚本只为自身进程设置 `DEVELOPER_DIR`，不会执行 `sudo xcode-select --switch`，不会改变 Xcode 27 的全局配置。

每次启动都会校验 Xcode 版本和 Build，Archive 中的 `DTXcodeBuild` 也必须为 `17F113`。脚本还会在导出或上传前动态检查 ExportOptions 的 `method` 和 `destination=export|upload` 支持情况。

仅在用户明确要求 TestFlight 特殊构建时，可以临时覆盖工具链，例如：

```bash
MOSA_XCODE_APP_PATH=/Applications/Xcode-beta.app \
MOSA_EXPECTED_XCODE_VERSION=27.0 \
MOSA_EXPECTED_XCODE_BUILD=27A5228h \
./scripts/ios-release.sh release --yes
```

三个值必须与实际 Xcode 完全一致，脚本仍会校验 Archive 的 `DTXcodeBuild`。Beta Xcode 构建只用于 TestFlight 验证，不得记录为可提交正式审核的构建；正式审核仍使用默认固定工具链或 Apple 当前允许的正式版/GM Xcode。

## 在 Xcode 27 开发机安装 Xcode 26.6

Xcode 26.6 要求 macOS Tahoe 26.2 或更高，包含 iOS 26.5 SDK。先在 MOSA iOS 目录执行只读检测：

```bash
./scripts/setup-xcode-26.6.sh --check
```

未安装时执行：

```bash
./scripts/setup-xcode-26.6.sh
```

安装脚本会：

1. 保留现有 Xcode 27。
2. 如果系统已有 `xcodes` 则直接使用；否则在已有 Homebrew 的机器上安装 `xcodes`。
3. 通过 Apple Developer 登录下载 Xcode 26.6，并以版本化名称并存到 `/Applications`。
4. 执行 Xcode 26.6 的首次启动组件安装。
5. 检测并安装与 Xcode 26.6 匹配的 iOS Runtime。
6. 不修改系统全局 `xcode-select`。

安装过程需要较大磁盘空间、Apple Developer 登录、管理员密码和较长下载时间。本项目脚本不会读取或输出 Apple 密码；登录、双重认证及钥匙串凭据由 `xcodes` 自身管理。非交互执行可添加 `--yes`，只想安装 Xcode 本体可添加 `--skip-runtime`。

如果机器没有 Homebrew，可从 [Apple Developer Downloads](https://developer.apple.com/download/all/) 手动下载 Xcode 26.6，解压为 `/Applications/Xcode-26.6.app`，再重新执行检测。版本与系统要求参见 [Apple Xcode 支持页](https://developer.apple.com/support/xcode/)，平台组件命令参见 [Apple 官方组件安装文档](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)。

## 准备 Apple Developer 证书

1. 在 Apple Developer 后台确认账号具有发布权限。
2. 在钥匙串中安装包含私钥的有效 `Apple Distribution` 证书。
3. 在 Xcode 的 `Settings → Accounts` 登录 Apple 账号。
4. 在 Target `MOSA → Signing & Capabilities` 确认 Team、Bundle Identifier 和 Automatic Signing。
5. 不要由脚本自动改 Team 或 Bundle ID；它们必须与 App Store Connect 中的 App 记录一致。

可用以下命令查看签名身份：

```bash
security find-identity -v -p codesigning
```

## 配置 App Store Connect API Key

在 App Store Connect 的 `Users and Access → Integrations → App Store Connect API` 创建具有所需上传权限的 Key，记录 Key ID 与 Issuer ID，并只下载一次 `.p8` 私钥。把私钥保存在仓库外，例如：

```bash
mkdir -p "$HOME/private_keys"
chmod 700 "$HOME/private_keys"
chmod 600 "$HOME/private_keys/AuthKey_XXXXXX.p8"
```

不要输出、复制或提交密钥正文。若不配置 API Key，脚本会退回 Xcode 已登录 Apple 账号的认证模式。

## 创建 release-config

```bash
cd App/IOS/Mosa
cp scripts/release-config.example release-config
```

填写：

```bash
MOSA_XCODE_APP_PATH=
UPLOAD_BYPASS_PROXY=true
ASC_KEY_ID=你的_Key_ID
ASC_ISSUER_ID=你的_Issuer_ID
ASC_KEY_PATH=~/private_keys/AuthKey_XXXXXX.p8
EXPECTED_BUNDLE_ID=com.wekarepartners.mosa.app
EXPECTED_TEAM_ID=R3622MSZJ7
```

`MOSA_XCODE_APP_PATH` 留空时自动查找精确匹配的 Xcode 26.6。API Key 三项必须同时填写；若全部留空则使用 Xcode Account authentication。`EXPECTED_*` 用于防止误传到错误 App 或 Team。

## 常用命令

所有命令先进入真实工程路径：

```bash
cd App/IOS/Mosa
```

检查发布环境：

```bash
./scripts/ios-release.sh doctor
```

显示主应用版本、签名与上传模式：

```bash
./scripts/ios-release.sh info
```

执行不上传的 Release 真机构建：

```bash
./scripts/ios-release.sh build
```

创建 Archive，并把绝对路径记录到 `.release/latest-archive`：

```bash
./scripts/ios-release.sh archive
```

验证最新 Archive：

```bash
./scripts/ios-release.sh verify
```

只导出 IPA，不上传：

```bash
./scripts/ios-release.sh export
```

验证并上传最新 Archive，默认要求人工确认：

```bash
./scripts/ios-release.sh upload
```

无参数执行完整发布流程（自动检测、归档、验证，确认后上传）：

```bash
./scripts/ios-release.sh
```

也可以显式使用 `release` 子命令。在已明确授权的非交互 CI 中可加 `--yes`：

```bash
./scripts/ios-release.sh release --yes
```

`--yes` 只跳过上传确认，不会提交审核、自动发布、修改价格、年龄分级、隐私信息或测试人员。

## 验证使用 Xcode 26.6

运行 `info` 或 `doctor` 时，开头必须显示：

```text
Xcode 26.6
Build version 17F113
```

Archive 完成后执行：

```bash
./scripts/ios-release.sh verify
```

验证结果中的 `DTXcodeBuild` 必须为 `17F113`。脚本还会校验签名、保存 Entitlements，并要求其中存在 `application-identifier` 和 `team-identifier`；任何一项失败都会阻止上传。

## 新开发机器初始化

在另一台 Mac 上完成以下准备后，可以使用同一条无参数命令发布：

1. 拉取代码，在 `App/IOS/Mosa` 执行 `./scripts/setup-xcode-26.6.sh --check`。
2. 如果检测失败，执行 `./scripts/setup-xcode-26.6.sh`，与现有 Xcode 27 并存安装 26.6 和对应 iOS Runtime。
3. 在 Xcode `Settings → Accounts` 登录具备发布权限的 Apple 账号。
4. 确认钥匙串、Team、Automatic Signing 和 Bundle Identifier 可用。
5. 从示例创建本机 `release-config`；该文件被 Git 忽略，不要跨机器提交密钥。
6. 先执行 `./scripts/ios-release.sh doctor`，通过后执行 `./scripts/ios-release.sh`。

`.release/` 是每台机器的本地产物目录并已被 Git 忽略。不要跨机器复制 `latest-archive` 或 `.xcarchive`，应在目标机器使用 Xcode 26.6 重新 Archive。每次上传前还需将 `CURRENT_PROJECT_VERSION` 递增为未使用的整数，并确保它高于 App Store Connect 已使用的 Build Number。

## 上传后仍需手动完成

上传成功不等于上线。需要在 App Store Connect 等待 Build 处理完成，然后手动：

1. 将 Build 关联到对应 App 版本。
2. 完善截图、说明、关键词、支持网址等商店信息。
3. 核对隐私信息、出口合规、内容版权和年龄分级。
4. 选择发布方式并提交 App Review。
5. 审核通过后按既定方式手动发布。

## 常见错误

- `No signing certificate`：安装有效且包含私钥的 Apple Distribution 证书。
- `No profiles found`：检查 Xcode Accounts、Team、Bundle ID 和 Automatic Signing。
- `Provisioning profile mismatch`：核对证书、Team、Bundle ID 与 App Capabilities。
- `Bundle Identifier mismatch`：工程、`release-config` 和 App Store Connect 必须一致。
- `Authentication failed`：重新登录 Xcode 账号，或核对 API Key 权限与状态。
- `Invalid API key`：核对 Key ID、Issuer ID、`.p8` 路径和 `chmod 600` 权限。
- `Build number already used`：在工程中递增 `CURRENT_PROJECT_VERSION` 后重新 Archive。
- `Unsupported SDK`：执行 `./scripts/setup-xcode-26.6.sh`，确认 Xcode 26.6 对应的 iOS 平台组件安装完整。
- `Xcode version mismatch`：实际 Xcode 或 Archive 不是 `26.6 (17F113)`；请运行环境安装脚本，并重新执行 `archive`。
- `Platform Not Installed` 或 `No simulator runtime version`：执行环境安装脚本补齐 Xcode 26.6 对应的 iOS Runtime。
- `Checksums do not match` 且持续重试：Apple Content Delivery 的分片校验受本地 HTTP 代理影响。脚本在上传阶段默认绕过 `HTTP_PROXY`、`HTTPS_PROXY` 和 `ALL_PROXY`；确需通过代理上传时可设置 `UPLOAD_BYPASS_PROXY=false`。
- `Archive contains no application`：检查 Scheme 的 Archive Action 是否构建主应用。
- `Validation failed` 或 `Upload failed`：查看 `.release/logs/` 对应日志最后 80 行和脚本给出的针对性提示。

## API Key 泄露后的撤销与轮换

若怀疑 `.p8` 泄露，立即在 App Store Connect 的 API Key 页面撤销该 Key，创建新 Key，替换仓库外的私钥文件，并更新本地 `release-config`。删除旧文件前先确认没有 CI 或其他安全环境仍依赖它。Git 历史中若曾出现密钥，仅删除当前文件并不足够，还应按组织安全流程清理历史、轮换凭据并审计访问记录。

`.p8`、`.p12`、`release-config` 和 `.release/` 均不得提交到 Git；项目 `.gitignore` 已包含对应规则。
