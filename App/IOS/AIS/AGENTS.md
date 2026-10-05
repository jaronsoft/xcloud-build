# AIS iOS 开发规范

## 适用范围

- 本文件适用于 `App/IOS/AIS/` 下的原生 iOS 工程、测试、配置和文档。
- 同时遵循仓库根目录 `AGENTS.md`；冲突时采用更严格的安全、支付和隐私约束。

## GitHub 仓库同步

- `App/IOS/AIS/` 是 AIS iOS 工程的唯一修改源；`/Users/jaron/Projects/Github/ais` 是同步目标，不应直接在目标目录修改业务或工程文件。
- 每次在本目录新增、修改、移动或删除文件后，必须在结束当前任务前执行：

  ```bash
  App/IOS/AIS/scripts/sync-to-github.sh --delete
  ```

  该命令会将源目录镜像同步至目标仓库，并保护目标目录的 `.git` 元数据。
- `AIS.xcodeproj` 及其中的共享配置属于必须同步的工程文件；不得为避免同步而排除它们。
- `xcuserdata/`、`*.xcuserstate`、`DerivedData/`、`build/`、`.release/` 与签名文件属于本地状态或敏感产物，沿用同步脚本的排除规则，不得复制到目标仓库。
- 同步命令失败时，必须先解决失败原因；不得声称目标目录已同步。

## 技术与工程

- 使用 Swift、SwiftUI、Swift Concurrency 和 StoreKit 2。
- 最低支持 iOS 17；App Store 提交使用 Apple 当期要求的正式版 Xcode 与 iOS SDK。
- 优先使用系统框架，第三方 SDK 必须说明用途、维护状态、隐私清单和移除成本。
- 采用 Feature-first 模块结构；共享网络、鉴权、设计系统和持久化能力放在 `Core/`，业务页面不得复制公共实现。
- 新增 Swift 注释使用中文并解释设计意图，代码标识保持英文。
- 后端雪花 ID 一律建模为 `String`，不得解析为 `Double`；只有明确需要数值比较且可安全转换时才使用 `Int64`。
- 并发代码使用 `async/await`；UI 状态更新由 `@MainActor` 管理，不在 View 中直接编排长网络流程。

## 身份与安全

- JWT、refresh token 和敏感登录凭证存入 Keychain；`UserDefaults` 只保存非敏感偏好。
- Sign in with Apple 必须把 identity token、authorization code 和 nonce 交给后端校验，客户端不得自行认定登录成功。
- 不在源码、配置包、日志或测试数据中写入 API Key、支付密钥和 APNs 私钥。
- 生产 API 必须使用 HTTPS；生产环境不提供任意 API 地址输入。
- 日志不得包含完整 token、提示词、用户图片 URL、支付签名、邮箱或设备 token。

## 支付与积分

- App 内数字商品只使用 StoreKit In-App Purchase，不使用 Apple Pay。
- 只展示后台启用档位与 StoreKit 有效商品的交集，不提供自定义充值金额。
- StoreKit 返回的本地化价格是 iOS 展示和成交价格；后台规则决定基础积分和赠送积分。
- 客户端不得提交或计算可信到账积分，必须由服务端验签、匹配历史规则并幂等入账。
- 购买积分不得过期；退款、撤销和重复通知必须由服务端账务处理。
- App 内不得出现微信、支付宝、Stripe、PayPal 或网页充值引导。

## 产品边界

- 聊天是受控创作 Agent，不扩展为开放式通用聊天。
- 付费任务必须遵循“服务端报价 → 用户确认 → 幂等启动”。
- Skill 只能调用后端已发布、已审核和已声明能力。
- 不提供创作者现金收益、收款资料和提现。
- 不默认公开项目消息、上传素材和生成结果。
- 中国区只能显示中国区能力配置允许且已完成合规准备的模型和功能。

## UI、可访问性与本地化

- 用户界面至少提供简体中文和英文。
- 不在 View 中硬编码面向用户的文案、价格、积分档位或区域规则。
- 支持 Dynamic Type、VoiceOver、深色模式、Reduce Motion 和 iPhone/iPad 自适应布局。
- 权限申请在功能触发时说明用途；相册、相机和通知被拒绝后提供不依赖该权限的可行路径。
- 生成式 AI 内容需要明确说明能力边界，付费前展示积分、成果数量、预计时间和失败处理。

## 验证

- 新业务至少覆盖 ViewModel/服务层单元测试；支付、登录、账号删除、报价确认和区域能力必须有集成测试。
- StoreKit 使用 `.storekit` 配置和 Sandbox/TestFlight 分层验证。
- 任何新增第三方 SDK 都要检查 `PrivacyInfo.xcprivacy`、App Privacy 和 required-reason API 影响。
- 文档改动无需执行 Xcode 构建；代码改动按风险执行目标单元测试、模拟器运行或 Archive 验证，并在交付时说明。

## 版本与构建号

- `MARKETING_VERSION` 使用 `主版本.次版本.修订版本` 三段格式，当前为 `1.2.6`；只有用户明确决定新的营销版本时才允许修改。
- `CURRENT_PROJECT_VERSION` 当前为本地工程默认值 `18`；线上发行使用 Xcode Cloud 自动生成并递增的 Build 号，不得为追赶线上编号手动修改工程默认值。
- 待发布说明写作 `1.2.6 (Build 待自动生成)`；云构建完成后，以 App Store Connect 中实际 Build 号为准。
- 已上传或已被 App Store Connect 接收的构建号不得复用；若 Xcode Cloud 报编号冲突，应检查云构建工作流与 Apple 提供的下一构建号设置，不应凭猜测改工程默认值。
