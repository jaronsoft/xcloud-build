# iOS 登录、案例、分享与协议修复实施

## 1. 实施范围

本轮于 `2026-07-25` 完成以下开发工作；本节最初不包含 TestFlight 上传，后续相关能力已纳入 `20260725.1` 与 `20260725.2` 构建：

- AIS 独立 JWT、Refresh Token 会话和 iOS Keychain 存储。
- 未登录图片选择拦截与确认生成后上传。
- 精选案例自适应布局、公开详情和结构化规格。
- 精选案例与成功任务的分享卡片、链接和 Universal Link。
- H5 与 iOS 中英文用户协议、隐私政策的应用内展示。

## 2. 独立认证

- 配置仅放在 `API/WebAPI/custom.ais.json`：
  - `AIS:Authentication:Session:AccessTokenExpireMinutes = 60`
  - `AIS:Authentication:Session:RefreshTokenIdleExpireDays = 30`
  - `AIS:Authentication:Jwt:Issuer`
  - `AIS:Authentication:Jwt:Audience`
  - `AIS:Authentication:Jwt:SecretFile`
- 不修改全局 `Audience:KeepLoginRefreshTokenExpireIn`，管理后台继续使用原 JWT 配置。
- AIS 使用命名 JWT Scheme 和 `token_scope=ais`。普通 AIS 接口拒绝管理后台 Token，AIS Token 也不能访问管理后台或 AIS 管理接口。
- 生产环境必须通过 `AIS__Authentication__Jwt__Secret` 或 `SecretFile` 提供独立签名密钥；密钥不进入仓库。开发环境未配置时可使用全局密钥派生的隔离子密钥，方便本地启动。
- Refresh Token 使用 `AIS:RefreshToken:` Redis 命名空间，记录用户、客户端、Token Family、签发、最后活动和过期时间；成功刷新立即轮换，旧 Token 不可复用。
- 旧 AIS Refresh Token 可通过刷新接口兑换一次新 AIS Token；旧全局 Access Token 访问普通 AIS 接口返回 `401`，客户端自动刷新迁移。管理后台 Token 不迁移。
- iOS 使用 Keychain Service `com.wekarepartners.studio.session` 保存组合会话，并迁移旧版分散凭据。连续活动可滑动续期；超过 30 天未活动或服务端明确拒绝刷新时才退出。断网、超时和服务异常不会清理本地会话。

## 3. 图片、案例与分享

- 创作和模板页面在未登录时点击图片选择直接打开登录页，不唤起相册。
- 首次选择素材前展示与 H5 对齐的中英文合规确认；用户需确认拥有合法权利或必要授权，并承诺不上传违反当地法律、侵害他人权益或包含秘密及非必要敏感信息的内容。协议按版本记忆，版本升级后可重新确认。
- 选中图片只驻留内存；确认生成且会话有效后才上传。取消、退出或页面释放时清理待上传图片。
- iPhone 精选案例使用单列，iPad 和宽屏双列；图片按真实比例完整显示。
- 案例详情读取公开分享 DTO，仅展示标题、描述、参考图、成果、比例、实际尺寸、文件大小、生成耗时和点数。
- 公开 DTO 不返回 Prompt、模型内部配置、供应商信息和原始输入/输出 JSON。
- 精选案例和成功任务可生成带 AIS 标识、二维码、缩略图和链接的分享卡片；链接自动复制后打开系统分享面板，卡片失败时降级为纯链接。

## 4. Universal Link 与协议

- Universal Link 为 `https://ais.jaronsoft.com/share/{jobId}`。
- AASA 限定 `/share/*`，App ID 为 `R3622MSZJ7.com.wekarepartners.studio`。
- 已安装时支持冷启动、后台恢复和运行中跳转到公开案例；未安装时停留 H5 分享页，并通过 Smart App Banner 或下载按钮前往 App Store `id6794249680`。
- iOS “我的”内原生展示版本化中英文协议和隐私政策，离线可读；客服入口仍独立打开。
- H5 新增 `/privacy`，与 iOS 同步说明登录、素材、AI 服务商、本地缓存、诊断、支付、公开分享、跨境处理和用户权利。

## 5. 验证结果与遗留验收

已完成：

- `dotnet build API/WebAPI/JaronSoft.SiteServer.csproj --no-restore`：0 警告、0 错误。
- AIS JWT 密钥专项测试：3/3 通过，覆盖独立密钥、生产缺失拒绝和开发隔离派生。
- iOS Debug 通用模拟器构建：`BUILD SUCCEEDED`。
- `AIS/` 生产构建、SSR/预渲染和 bundle 体积门禁：通过。
- Cloudflare Worker：5/5 通过，包含 AASA App ID 与 `/share/*` 范围测试。
- `git diff --check`：通过。

API 全量测试共 166 项，其中 160 项通过；6 项既有内容标识图片测试因本机字体文件缺少 `loca` 表失败，与本轮认证、案例、分享和协议改动无关。

仍需在部署或 TestFlight 环境验证：

- 配置独立生产 JWT 密钥并执行 AIS/管理后台 Token 交叉访问集成测试。
- Redis Refresh Token 并发轮换、跨用户和跨客户端复用测试。
- 真机相册拦截、30 天滑动会话和弱网恢复。
- AASA 线上 MIME、CDN 缓存、已安装/未安装及三种 App 生命周期深链。
- 分享卡片在中英文、长标题和不同图片比例下的视觉回归。
