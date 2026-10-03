# MOSA iOS

MOSA iOS 是基于当前 `MOSA/H5/` 功能构建的原生 SwiftUI 客户端，不使用 WebView。新构建通过公司 Cloudflare 中转入口 `https://api.wekarepartners.com` 复用现有 MOSA API，并使用正式官网 `https://mosa.wekarepartners.com`；已安装旧版继续使用原入口，各入口共享相同的独立账号、资料、标签、记录、删除恢复和游客数据导入接口。

## 技术基线

- iOS 17+
- SwiftUI
- URLSession + async/await
- Keychain 保存访问令牌与刷新令牌
- Application Support JSON 保存本地资料和离线记录
- Bundle ID：`com.wekarepartners.mosa.app`，与 App Store Connect 现有 App 记录一致。
- 当前软件版本：`1.1 (Build 10)`。版本采用 `主版本.次版本[.修订版本] (Build 递增整数)`；Build Number 在每次上传前加 1，不再使用日期或小数后缀，已上传的数字不得复用。`V2.1/V2.4` 是产品文档和研发基线版本，不作为 App Store 软件版本。
- 发布设备范围：仅 iPhone。工程不包含 Apple Watch target，也不向 App Store 声明 iPad 支持。

## 打开与运行

1. 使用 Xcode 打开 `MOSA.xcodeproj`。
2. 在 Target `MOSA` 的 Signing & Capabilities 中选择你的 Apple Developer Team。
3. 选择 iPhone Simulator 或已连接设备。
4. 运行共享 Scheme `MOSA`。

如 Xcode 安装在非标准位置，可以只为当前命令设置开发目录：

```bash
DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer" \
  xcodebuild -project MOSA.xcodeproj -scheme MOSA \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## GitHub 仓库自动同步

`App/IOS/Mosa` 是 iOS 工程的唯一修改源。首次镜像前先确认目标仓库没有未提交改动，执行 `git -C /Users/jaron/Projects/Github/mosa pull --ff-only`，并使用 `./scripts/sync-to-github.sh --dry-run --delete` 核对变更。开发时运行以下命令，脚本会先完成一次同步，随后持续监听变更并同步到 `/Users/jaron/Projects/Github/mosa`：

```bash
./scripts/sync-to-github.sh --watch
```

监听模式会镜像删除已从源目录移除的文件，但始终保护目标仓库的 `.git` 元数据。`MOSA.xcodeproj` 及其共享配置会同步；个人 Xcode 状态（`xcuserdata`、`*.xcuserstate`）和构建、签名产物不会同步。同步只更新本地 GitHub 镜像工作树，不会自动提交或推送。可先使用 `./scripts/sync-to-github.sh --dry-run --delete` 查看镜像变更。

不要把令牌、密码或邮件验证码写入工程配置。API 地址集中定义在 `MOSA/App/AppConfiguration.swift`；App 启动后异步读取 `https://api.wekarepartners.com/config/v1/mosa` 的公共配置，失败时使用最后一次有效缓存或内置默认值，API 地址不会通过远程配置下发。

## 当前范围

- 英文启动、欢迎和本机初始化
- 邮箱登录、注册、重置密码和验证码冷却
- 本地离线资料与每日记录
- 登录后 JWT 自动刷新和云端记录同步
- 登录、冷启动、回到前台和网络恢复时触发同步；MOSA 独立 access token 默认 60 分钟，refresh token 按 30 天不活跃窗口静默轮换，与管理端有效期配置分离
- 游客记录登录后确认导入
- 首页、每日记录、月历画布、年度概览和资料页
- Home、月度 Canvas、年度概览、Gallery 与年度统计只使用真实每日记录；未记录日期保持空白，阶段颜色仅在 `Color your past` 专用预览显示
- Gallery 轮询原画校验、Story、独立 `SHARE_CARD_VISUAL_LAYER`、Layout/Brand 与 Export 完整 Workflow；视觉层失败明确显示 `FAILED · CARD VISUAL`，不再把原画小图误当成最终卡片。最终分享卡会按账号保存在本地：优先展示最近一次成功版本，启动同步后静默预热；仅新图完整下载并校验成功后才原子覆盖缓存。首次 401 会单飞刷新 Token 并自动重试一次，图片就绪后可通过 iOS 系统分享面板仅分享 PNG 图片
- 首页和年度概览的密集马赛克作为整块入口，点击后进入大尺寸月历选日与日期摘要
- 系统 LaunchScreen 使用单一透明马赛克产品图，浅色/夜间模式自动切换 MOSA 背景色并衔接动态 Splash
- 原生 Splash 马赛克错峰聚拢、轻微呼吸并轮播三条品牌标语；“减少动态效果”开启时静态降级
- Debug 构建在 `Profile → Developer Tools → Network logs` 提供脱敏请求日志；点击单条日志即可复制，并支持立即重试、整体分享与清空；Release 不采集且不展示入口
- 诊断共享默认关闭；只有用户在 Profile 主动开启后才订阅 Apple `MetricKit`、采集受控运行错误并创建本地队列。关闭后立即停止订阅、清空队列且不再上报
- 开启后，Release 使用 Apple `MetricKit` 接收系统延迟交付的 crash、hang 与 watchdog/CPU exception；受控运行错误进入最多 20 条、保留 7 天的独立队列，登录后每批最多 10 条上报
- 每日记录必须至少包含 Note、Color 或 intentional blank；空记录和本机写盘失败会保留编辑页并显示原因，云端失败不阻塞本机保存，历史无效空记录会在启动或同步前自动清理
- 每日记录先原子写入 Application Support，再等待云端响应并可靠写回 `serverVersion`；409 冲突会拉取远端最新记录，相同内容直接确认成功，不同内容基于最新版本重试一次。写盘失败保留草稿并回滚内存，损坏记录文件不会被空数组覆盖
- 浅色/暗色系统主题和 iPhone 自适应布局

MOSA App Icon 已配置为 1024×1024 不透明母图，并由 Asset Catalog 生成各设备所需尺寸。正式签名与首轮商店元数据已配置；包含 Gallery `SUBMITTING`、`QUEUED`、`RUNNING` 分阶段反馈的 `1.0 (20260802)` 已使用正式 Xcode 26.6 上传 App Store Connect，Apple 已接收并开始处理；真机通知和后台刷新尚未配置。

此前 `1.0 (20260810)` 已使用正式 Xcode 26.6（`17F113`）和 iPhoneOS 26.5 SDK 完成 iOS 17 目标的 XCTest 27/27、Release Archive、签名及 Entitlements 校验和 App Store Connect 上传。Archive 为 `.release/archives/MOSA-1.0-20260810-20260810-081355.xcarchive`；当前工程已切换到新的版本规则与 `1.1 (Build 10)` 基线，后续上传必须继续使用未占用的递增整数。

开发日志只记录请求时间、HTTP 方法、包含域名的完整 API URL、允许公开的日期查询、状态码、耗时、响应字节数及错误码/消息；不会记录 Authorization、Token、密码、验证码、请求正文、响应正文或其他查询参数，最多保留当前进程内最近 200 条。

正式诊断与 Debug 开发日志相互独立。正式诊断在客户端和 API 两次移除 Bearer/JWT、邮箱和邀请 Token，不包含每日 Note、情绪、颜色、标签、画布、联系人、精确位置或请求/响应正文。MetricKit 由系统在后续启动交付，因此崩溃不会在发生瞬间联网发送。
