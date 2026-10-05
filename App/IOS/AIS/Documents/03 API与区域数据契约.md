# API 与区域数据契约

## 1. 原则

- iOS 共用现有 AIS WebAPI，不在客户端复制计费、积分、模型、会员、区域和内容安全规则。
- 后端继续返回 `MessageModel<T>` 或 `MessageModel<PageModel<T>>`。
- 所有雪花 ID 在 JSON 和 Swift 中使用字符串。
- 客户端提交稳定 key、用户输入和幂等凭证，不提交可信价格、积分、权限或任务状态。
- iOS 新接口沿用 `/api/ais/...` 路由，生产请求路径由客户端统一 API Client 处理。

## 2. 统一响应建议

Swift 侧统一解码：

```json
{
  "success": true,
  "status": 200,
  "msg": "获取成功",
  "response": {}
}
```

实际字段名以现有 `MessageModel<T>` 序列化结果为准，创建工程时用测试环境抓包锁定。不要在多个 Feature 分别定义不同包装类型。

建议后端补充稳定的业务错误码，例如：

- `AUTH_REQUIRED`
- `TOKEN_EXPIRED`
- `REGION_UNAVAILABLE`
- `CAPABILITY_DISABLED`
- `QUOTE_EXPIRED`
- `INSUFFICIENT_POINTS`
- `STORE_PRODUCT_MISMATCH`
- `TRANSACTION_ALREADY_PROCESSED`
- `CONTENT_REJECTED`

`msg` 用于展示兜底，客户端流程分支依赖稳定错误码而非中文文本。

## 3. 现有接口盘点

下表来自当前代码，实施时仍需通过真实响应和鉴权测试确认字段。

| 领域 | 现有接口 | iOS 用途 |
| --- | --- | --- |
| 能力 | `GET /api/ais/capabilities` | 匿名获取图片、视频、规格及 iOS 最低版本、区域、登录、StoreKit、视频、公开内容和推送门禁 |
| Nonce | `GET /api/ais/nonce` | 现有一次性凭证，不能直接等同 Apple 登录 nonce |
| 余额 | `GET /api/ais/balance` | 余额、冻结积分、首充和会员信息 |
| 邮箱登录 | `POST /api/ais/auth/email/code`、`email/register`、`email/login`、`email/password-login`、`refresh` | 注册、登录与刷新 |
| OAuth | `GET /api/ais/auth/oauth/providers` 及 authorize/callback | 现有 Web OAuth |
| 原生 Apple 登录 | `POST /api/ais/auth/apple/native` | 已实现 identity token、authorization code 与 nonce 交换 |
| 账号删除 | `POST /api/ais/account/deletion/confirm` | 已实现确认删除；准备、状态和取消接口按异步流程需要补充 |
| 模板 | `GET /api/ais/style-templates`、`categories`、`home`、`{id}` | 模板列表、筛选、首页与详情 |
| 模板执行 | `POST /api/ais/style-templates/{id}/quote`、`preview-intent`、`generate` | 报价、意图预览和生成 |
| 项目 Agent | `/api/ais/agent/projects`、messages、memories、skill quote、`runs/confirm`、runs 查询 | 项目、消息、记忆、报价确认与运行 |
| Skill | `/api/ais/skills`、详情、app-manifest、examples、sessions、install | 官方及审核 Skill 浏览和会话 |
| 素材 | `GET/POST /api/ais/assets`、`GET /api/ais/assets/{id}`、delete | 素材列表、上传、详情和删除 |
| 图片任务 | `POST /api/ais/images/jobs`、`POST /api/ais/images/edit/jobs` | 图片生成和编辑 |
| 视频任务 | `POST /api/ais/videos/jobs`、download | 区域允许时的视频生成 |
| 任务 | `GET /api/ais/jobs`、`{id}`、`{id}/status`、delete | 任务列表、详情、状态和删除 |
| 公开分享 | `POST /api/ais/jobs/{id}/share`、`GET /api/ais/jobs/shared/{id}` | 开启分享、读取经过安全裁剪的公开详情和 Universal Link |
| 交易 | `GET /api/ais/billing/transactions` | 积分流水 |
| 定价快照 | `GET /api/ais/billing/pricing-snapshot` | 返回带签名和有效期的本地预估规则，服务端创建任务前重新复算 |
| 预计耗时 | `GET /api/ais/usage/duration-estimates` | 返回按任务类型和模型样本聚合的预计耗时 |
| 邀请 | `GET /api/ais/promotion/overview`、`inviteqrcode`、`referrals` | 邀请码、二维码、邀请概览和推荐名单分页 |
| Web 充值规则 | `GET /api/ais/recharge/getpricing` | 当前后台地区定价；iOS 需要专用过滤响应 |

以下现有接口不进入 iOS 首版：

- `GET /api/ais/creator/earnings` 等创作者收益接口；
- 创作者提现接口；
- Web 支付创建订单和微信、支付宝、Stripe、PayPal 支付入口。

## 4. capabilities 扩展（已落地第一版）

当前响应已增加顶层 `ios` 安全白名单字段：

```json
{
  "ios": {
    "enabled": true,
    "minimumVersion": "1.0",
    "allowedRegions": ["US"],
    "loginMethods": ["apple", "email"],
    "storeKitEnabled": false,
    "videoEnabled": false,
    "publicContentEnabled": true,
    "pushNotificationsEnabled": false,
    "rulesVersion": "20260725.1"
  }
}
```

客户端启动时缓存该配置；读取失败时采用关闭支付、视频、推送和公开内容的最小安全能力集，不能用本地覆盖扩大能力。

## 5. Apple 原生登录接口

已实现：

`POST /api/ais/auth/apple/native`

请求：

```json
{
  "identityToken": "<JWS>",
  "authorizationCode": "<single-use code>",
  "nonce": "<raw nonce or server session id>",
  "givenName": "Jaron",
  "familyName": "Chen",
  "email": "private@privaterelay.appleid.com",
  "locale": "zh-CN"
}
```

后端必须：

1. 校验签名、`iss`、`aud`、`exp`、nonce 和授权码。
2. 以 Apple `sub` 作为稳定外部身份键。
3. 只在首次授权时接受客户端转发的姓名，并防止覆盖现有资料。
4. 明确隐藏邮箱与现有邮箱账号的绑定/冲突规则。
5. 返回 AIS JWT、refresh token、用户和首次登录标记。
6. 账号删除时撤销 Apple token。

已有邮箱账号登录后可使用以下登录态接口绑定 Apple，不允许仅因邮箱相同就自动合并账号：

- `GET /api/ais/account/apple/status`
- `POST /api/ais/account/apple/bind`

Apple 依据：[Authenticating users with Sign in with Apple](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple)。

Apple 登录使用容器只读挂载的 `.p8` 文件，不在环境变量或 Git 中保存私钥：

```json
{
  "Enabled": true,
  "ClientId": "com.wekarepartners.studio",
  "TeamId": "R3622MSZJ7",
  "KeyId": "D32U3TPA33",
  "PrivateKeyPath": "/run/secrets/ais-apple-signin.p8",
  "PrivateKey": ""
}
```

YZ1、YZ2、SH2 已完成挂载验证；详细部署、绑定和验收流程见 [Apple 登录生产配置与账号绑定实施](./23%20Apple登录生产配置与账号绑定实施.md)。生产 API 尚待发布和真机联调。

## 6. 账号删除接口

当前已实现 `POST /api/ais/account/deletion/confirm`，iOS 首版使用固定确认文本发起删除。若后续改为异步删除工作流，再补充：

- `POST /api/ais/account/deletion/prepare`：返回影响、法定保留项和二次验证方式。
- `POST /api/ais/account/deletion/confirm`：提交验证码/重新认证并创建删除请求。
- `GET /api/ais/account/deletion/status`：查询处理状态。
- `POST /api/ais/account/deletion/cancel`：仅在业务允许且尚未执行前取消。

删除范围至少覆盖：

- 登录身份和第三方身份绑定；
- 项目、消息、记忆、素材和生成成果；
- 公开内容的下架/删除；
- APNs token 和本地会话；
- 不需要法定保留的业务数据。

支付、风控或监管要求保留的记录应最小化、脱敏并说明期限，不能把“停用账号”作为删除。

## 7. StoreKit 待新增接口

建议：

- `GET /api/ais/storekit/products?storefront=USA`
  - 返回后台启用档位、productId、packageKey、基础/赠送积分、规则版本和展示说明。
- `POST /api/ais/storekit/transactions/verify`
  - 接收 StoreKit 签名交易或 transaction JWS，服务端验证并幂等入账。
- `POST /api/ais/storekit/transactions/sync`
  - 批量同步未完成/历史 entitlement 交易，主要用于断网恢复。
- `POST /api/ais/storekit/notifications/v2`
  - 接收 App Store Server Notifications V2；必须验证 signedPayload。
- `GET /api/ais/storekit/orders`
  - 返回 Apple 交易与积分到账状态。

所有到账响应返回最终账务快照，不接受客户端传入积分数。

## 8. APNs 待新增接口

建议：

- `POST /api/ais/devices`：注册或更新 token、environment、region、appVersion 和 device installation ID。
- `DELETE /api/ais/devices/{installationId}`：退出登录或停用设备。
- `PUT /api/ais/devices/{installationId}/preferences`：任务完成/失败等通知偏好。

设备 token 是敏感标识，日志中只保存截断或哈希值。生产和 sandbox token 不可混用。

## 9. 区域判定

服务端综合以下信息确定区域：

- 账号注册/运营区域；
- App 构建渠道；
- App Store storefront；
- 请求来源和服务端区域配置；
- 合规能力白名单。

客户端不得仅用 `Locale.current.region` 或 GPS 决定支付、模型和数据落区。用户旅行或 Apple ID storefront 变化时，由服务端返回可用能力和商品映射。

### 9.1 区域图片交付（已落地区域隔离）

- 中国区继续使用腾讯云 COS、`cdn.jaronsoft.com` 和 `imageMogr2`/`imageView2` 图片规则。
- 中国以外区域使用 Cloudflare R2、Cloudflare Images Transformations 和独立域名 `cdn.get-free.net`；国际配置默认关闭，等待生产 API 动态开启。
- 海外原图优先使用 Cloudflare R2 副本并通过 `www.get-free.net` 交付；缩略图开启后通过 `cdn.get-free.net` 的受控 `preset` 参数交付。
- `/api/ais/capabilities` 按当前媒体区域返回单一活动图片交付配置；iOS 使用用户选择、App Store storefront、账号区域和 Locale 依次确定请求区域，并在 API 请求中发送 `X-Client-Platform: ios` 与 `X-AIS-Media-Region: cn|global`。
- Cloudflare Worker 仅为合法 iOS 请求保留客户端媒体区域；Web 等其他客户端继续由访问入口域名决定区域，非法区域值回退到入口区域。
- 接口响应缓存、图片交付配置缓存、图片内存/磁盘缓存和并发请求合并键均包含媒体区域；切换区域时等待缓存清理和交付配置刷新完成后再刷新界面。
- 同源 API 图片代理请求携带当前媒体区域，第三方图片请求不发送内部区域头，避免向外部站点泄露路由信息。
- 服务端列表、模板、详情、公开分享和图片代理只解析目标区域存储；目标区域副本暂不可用时返回同源代理或明确失败，不使用另一地区副本作为显示回退。
- 列表、详情和原图使用独立最终 URL 与缓存键；全屏预览、相册保存、文件导出和用户主动下载始终使用原图。
- 双区镜像完成后同时清理资产快照及案例、模板、任务和公开分享展示缓存，避免旧国际区 URL 继续命中。
- 中国区不得因海外 Cloudflare 故障静默跨境回源，海外也不得把腾讯云作为默认图片链路。

完整规划见 [AIS 双区域图片交付与 Cloudflare 转换](../../../../documents/AIS/开发计划/0726%20AIS双区域图片交付与Cloudflare转换.md)。

## 10. 区域数据边界

| 数据 | 海外区 | 中国区 | 是否跨区合并 |
| --- | --- | --- | --- |
| 基础身份 | 海外身份服务 | 中国身份服务 | 可按明确规则关联 |
| 积分/余额 | 海外账本 | 中国账本 | 不合并 |
| Apple/Web 订单 | 对应区域账本 | 对应区域账本 | 不合并 |
| 原始素材/提示词/成果 | 海外存储 | 境内存储 | 默认不跨境 |
| 项目消息/记忆 | 海外数据库 | 境内数据库 | 默认不合并 |
| 审计与合规日志 | 海外策略 | 境内留存策略 | 不直接共享原文 |

若跨区身份冲突，返回明确状态并由用户选择或联系客服，不自动覆盖。

## 11. 缓存与离线

- 公开模板和 capabilities 可短期缓存，启动后后台刷新。
- 余额、报价、购买状态和任务状态不可长期离线信任。
- 离线可查看最近项目和成果缩略图，但启动生成、购买和删除账号必须联网。
- 缓存记录所属用户与区域，退出账号或切换区域时清除。

## 12. 接口落地验收

- OpenAPI/Swagger 能描述所有 iOS 新接口。
- DTO 中 ID 使用字符串，时间使用带时区的 ISO 8601。
- 错误码稳定且中英文 `msg` 可用。
- 所有创建、确认、验单接口具备幂等约束。
- 中国与海外环境使用同一契约但返回不同能力和数据。
- 日志不记录 token、支付 JWS、图片原文或完整个人信息。
