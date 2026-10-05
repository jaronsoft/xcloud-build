# AIK iOS 开发规范

## 适用范围

- 本文件适用于 `App/IOS/AIK/` 下的原生 iOS 工程、测试、资源和文档。
- 同时遵循仓库根目录 `AGENTS.md`，冲突时采用更严格的安全与隐私约束。

## GitHub 仓库同步

- `App/IOS/AIK/` 是 AIK iOS 工程的唯一修改源；`/Users/jaron/Projects/Github/aik` 是同步目标，不应直接在目标目录修改业务或工程文件。
- 每次在本目录新增、修改、移动或删除文件后，必须在结束当前任务前从仓库根目录执行：

  ```bash
  App/IOS/AIK/sync-to-github.sh --delete
  ```

  该命令会将源目录镜像同步至目标仓库，并保护目标目录的 `.git` 元数据。
- 首次同步或需要核对范围时，先执行 `App/IOS/AIK/sync-to-github.sh --dry-run --delete`。
- `AIK.xcodeproj`、共享 Scheme、源码、资源、测试和项目文档属于必须同步的文件，不得为减少差异而排除。
- `xcuserdata/`、`*.xcuserstate`、`DerivedData/`、`build/`、`.release/` 与签名文件属于本地状态、构建产物或敏感配置，沿用同步脚本的排除规则，不得复制到目标仓库。
- 同步命令失败时，必须先解决失败原因；不得声称目标目录已同步。

## 技术与架构

- 使用 Swift 6、SwiftUI、Swift Concurrency，最低支持 iOS 17，仅支持 iPhone。
- 不引入第三方 SDK；新增依赖前必须说明用途、隐私影响和移除成本并取得确认。
- 采用 Feature-first 结构；网络、模型、鉴权、安全、持久化和共享状态放入 `Core/`。
- UI 状态及 Store 使用 `@MainActor` 管理，网络流程不得直接堆叠在 View 中。
- 新增代码注释使用中文并说明设计意图。

## 多租户与数据安全

- 所有雪花 ID、用户 ID、成员 ID、租户 ID 和消息 ID 均按字符串解码与保存，禁止经 `Double` 中转。
- 系统 JWT、refresh token、邀请凭据及用户关联数据存入 Keychain；`UserDefaults` 只保存非敏感偏好和租户摘要。
- 密码只参与当前登录请求，不保存、不记录。
- 选定租户后的业务请求必须同时携带 `Authorization`、`X-Knowledge-Tenant-Id`、`x-tenantid` 和 `x-lang`。
- 租户权限以线上 `KnowledgeTenant/GetList` 返回结果为准，不在客户端构造、缓存或绕过额外权限。
- 生产 API 固定为 `https://app.jaronsoft.com/api`，不得提供面向用户的任意环境切换。
- 日志和测试数据不得包含真实账号、密码、完整 token 或企业知识内容。

## 产品边界

- AIK 是 RAG 知识库项目的产品名称，iOS 工程是该项目的原生访问客户端，不作为独立于 RAG 的另一条产品线维护。
- 首版提供登录、租户选择、邀请/匿名访问、知识问答、会话历史、评价及租户允许时的语音提问。
- 首版不提供知识库后台管理、文档上传、租户配置修改、付费、注册、找回密码、Apple 登录或推送通知。
- 不修改线上 API、数据库、部署配置或租户数据。

## UI 与验证

- 用户界面至少提供简体中文和英文，支持 Dynamic Type、VoiceOver、深色模式、Reduce Motion 和键盘避让。
- 权限必须在功能触发时申请；当前仅麦克风权限。
- 业务协议解析至少覆盖响应包、大整数 ID、邀请链接、SSE 分包/粘包/错误包及 Markdown 图片链接。
- 交付代码前执行 AIK Debug 构建和 `AIKTests`；若完整 Xcode 不在默认路径，显式设置 `DEVELOPER_DIR`。
- 仅修改文档或同步脚本时无需执行 Xcode 构建，但必须运行 Shell 语法检查、同步演练和差异检查。

## 版本与构建号

- `MARKETING_VERSION` 使用 `主版本.次版本.修订版本` 三段格式；当前主版本为 `1.0.1`，只有用户明确决定新版本时才修改。
- `CURRENT_PROJECT_VERSION` 使用从 `100` 开始的递增整数；当前默认值为 `100`，不使用日期加小数格式。正式上传时仍需满足 App Store Connect 对版本内 Build 唯一性和递增性的校验。
- 正式上传 Build 沿用本地递增整数规则，不得回退或复用；若 App Store Connect 对新版本提出历史编号约束，应以 Apple 校验结果为准调整。
- 发布说明中的待发布版本写 `Build 待自动生成`；完成归档和上传并确认 App Store Connect 编号后，再回填实际 Build。
