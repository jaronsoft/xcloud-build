# AIS iOS 原生端

> 项目关系：[项目关联与上下文检索索引](../../../documents/项目关联索引.md)

`App/IOS/AIS/` 是 AIS 原生 iOS 客户端的固定构建目录。客户端使用 SwiftUI 构建，共用现有 AIS WebAPI，不复制计费、模型调度、Skill、区域和内容安全规则。

## 当前状态

- 文档基线日期：`2026-09-01`
- 当前阶段：AIS/PixaRivo 双 App StoreKit 商品映射、AIS 服务端验单与原生购买链路已完成代码接入；新 API 与管理端尚待发布，发布后需开启 AIS 总开关并完成 Sandbox/TestFlight 真机购买回归
- Xcode 工程：已创建 `AIS.xcodeproj`
- 开发工作名：`AIS`
- App Store 名称：`AIS Visual Studio by WeKare`
- App Store 版本：`1.2.6`
- Bundle ID：`com.wekarepartners.studio`
- Apple Team ID：`R3622MSZJ7`
- 海外发行主体：`WeKare Partners LLC`
- 中国大陆运营主体：`扬州市佳融信息技术有限公司`
- 首发区域：海外 TestFlight 与已准备完成的 App Store 国家和地区；中国大陆在备案、登记和区域部署验收完成后单独开放
- 当前待发布构建：`1.2.6 (Build 18)`，尚未 Archive 或上传

## 文档入口

- [iOS 文档索引](./Documents/README.md)
- [iOS 原生端与全球发行总计划](./Documents/00%20AIS%20iOS原生端与全球发行计划.md)
- [AIS Agent、记忆与 Skill 生态计划](../../../documents/AIS/开发计划/0722%20AIS垂直创作Agent记忆与Skill创作者生态.md)
- [AIS 生成内容标识与追溯计划](../../../documents/AIS/开发计划/0711%20AIS%20生成内容标识与追溯合规计划.md)
- [区域部署与中国区能力计划](../../../documents/AIS/开发计划/0625%20区域部署与中国区能力.md)

## 已确认的产品边界

- 产品不是早期“产品智造”的简单移动版，而是覆盖快速创作、风格模板、项目 Agent 与 Skill 的 AI 视觉创作平台。
- 首版使用原生 SwiftUI，不以 WebView 包装 AIS 网站。
- 聊天入口只服务创作任务，不提供开放式通用聊天。
- App 内积分购买使用 StoreKit 2 消耗型 In-App Purchase；不使用 Apple Pay，也不提供网页、微信、支付宝、Stripe 或 PayPal 充值入口。
- 首版不提供自动续费订阅。
- 首版不提供创作者现金收益、收款资料或提现。
- 公开案例和 Skill 必须由后台审核后展示，不开放自由发布社区。

## 第一版已完成

- SwiftUI 原生工程、iPhone/iPad target 和中英文资源。
- AIS 品牌 App Icon、浅色系统启动页和支持“减少动态效果”的短时动态启动页。
- 首页、模板、项目占位页和账号四个一级入口。
- 公共风格模板双列瀑布流、搜索、下拉刷新和服务异常状态；模板案例在 iPad 竖屏使用三列、横屏使用四列。
- 分层登录界面、邮箱密码表单、原生 Sign in with Apple、nonce 和 Keychain 会话保存。
- App 内账号删除入口。
- 后端 Apple JWS/nonce 校验、authorization code 交换、加密 refresh token 和外部身份表。
- 后端账号删除时撤销 Apple 授权、匿名化身份并清理主要 AIS 私有内容。
- `PrivacyInfo.xcprivacy`、Sign in with Apple 和 Associated Domains entitlement。
- Debug 与 Release 均使用生产 API `https://ais.get-free.net`。
- Debug、开发签名与 TestFlight 包在“我的”中提供内存级脱敏网络诊断；正式 App Store 包隐藏入口且不采集请求日志。
- 版本采用 `主版本.次版本.修订版本 (Build 递增整数)`，当前工程版本为 `1.2.6 (Build 18)`；Build 全局递增且不随日期或营销版本重置，下一次发行构建至少使用 `19`。
- `1.2.5 (Build 16)` 优先使用当前 App Store storefront 请求服务端定价，按服务端确认的区域筛选积分包，并对 StoreKit 目录执行批量重试与逐项补查；商品展示不再依赖账户令牌接口，购买前仍强制取得 `appAccountToken`。
- `1.2.5 (Build 12)` 将 capabilities、会员推荐套餐和验单请求固定为 AIS `appCode`，使用 `appAccountToken` 绑定账户，并在商品为空或不可用时显示可重试的明确状态；后端同时按 AIS/PixaRivo 的 Bundle ID 和 Product ID 独立映射及验单。
- `1.2.5 (Build 4)` 已完成完整 `AISTests`、Release Archive、包体版本与签名能力核对，并于 `2026-08-13 22:53` 上传 App Store Connect 成功。
- `1.2.3 (260729.13)` 统一输入页面的键盘焦点退出行为，生成运行及完成状态主动收起键盘，并为产品智造和风格模板补充成果详情入口。
- `1.2.3 (260729.15.3)` 将产品智造与模板创作切换为持久规则本地即时算价，补齐全部规格倍率展示，并在服务端价格变化时更新缓存和要求再次确认。
- `1.2.3 (260729.16.4)` 修复服务端规则缺少 4K/8K 键值时规格切换不更新点数的问题，隐藏基准 `×1` 标签，并分别展示会员优惠、宣传标识优惠、原价和总优惠。
- `1.2.3 (260729.17.5)` 完整展示公开案例的来源图、参考图和 LOGO，并将用户鼠标标记、文字与 LOGO 图层合成为“标记与文字预览”供 iOS 与 H5 统一浏览。
- `1.2.3 (260729.18.6)` 在 App 启动时后台预加载持久化的分类、用户与计费策略；激活 App、创建任务和充值到账后静默刷新用户积分，余额与会员加载期间展示缓存值和加载状态，创作所需数据未就绪前禁用生成。
- `1.2.3 (260729.20.8)` 优化原生记忆中心的用户化编辑和状态展示，增加历史候选直达、来源标题/描述/关键词与无持久缓存的成果预览。
- `1.2.3 (260731.24.2)` 在双区媒体隔离基础上增加 Cloudflare 受控图片档位、供应商兼容和规则版本缓存隔离；已完成完整测试、Release Archive 并上传 App Store Connect。
- `1.2.3 (260806.26)` 修复任务时间被重复增加 8 小时、预计剩余时间异常和任务元信息字号不一致；完整 `AISTests`、Release Archive、包体权限核对与 App Store Connect 上传通过。
- AIS 使用独立 JWT 与 30 天滑动 Refresh Token，iOS 会话保存在独立 Keychain Service，网络故障不会误退出。
- 首页“模板案例”和“生图案例”均进入原生列表；模板案例仅展示风格模板任务，生图案例展示图片生成、图片再编辑和视频生成任务，并支持原生详情、分享和制作同款。
- “添加 AIS 宣传标识折扣”使用 `ais.promo_mark_enabled` 作为跨创作流程的唯一默认值，页面切换立即同步，旧草稿不再覆盖全局设置。
- 账号页展示会员等级图标，并提供不含返现、提现和代理认证内容的独立“邀请有礼”页面。
- 邀请和作品分享仅向系统分享面板传递合成后的完整海报；作品海报包含 AIS 标识、标题、描述和二维码，不显示明文链接，并按成果原图比例生成，输出前统一重绘为无 Alpha 通道的位图。
- 精选案例与成功任务支持原生分享卡片和 Universal Link；用户协议和隐私政策在 App 内离线展示。

## 当前阻塞项

以下项目完成前不得提交审核：

1. Apple `.p8` 已在四个 API 节点完成只读挂载，后端文件读取、登录态绑定和 iOS credential state 代码已完成；继续发布生产 API 和新 iOS 构建，并完成真机首次授权、隐藏邮箱、重复登录、邮箱账号绑定与撤销验证。
2. 完成项目创建、模板详情、素材上传、报价、生成、任务恢复和成果保存，移除项目占位页。
3. StoreKit 双 App 商品映射、服务端验单、积分到账代码已完成；继续发布新 API/管理端，开启 AIS 总开关，并完成 Sandbox/TestFlight 购买、通知 V2、退款冲正和对账验证。
4. `/privacy` 和 App 内隐私政策已经建立；仍需补齐正式客服 `/contact` 页面和法务终审。
5. 完成 App Privacy、年龄分级、出口合规、截图、Review Notes 和长期有效审核账号。
6. `1.2.3 (260731.24.2)` 完成 Apple 处理且生产 API 发布后，重点验证中国区与国际区切换、封面/案例成果/任务详情/公开分享图片、冷启动旧缓存与目标区副本缺失场景，并继续覆盖记忆、iPhone/iPad、弱网、Dynamic Type、VoiceOver、相册权限和公开分享；配套 H5 与 Workers 已完成生产发布。
7. 在生产环境配置独立 `AIS__Authentication__Jwt__Secret` 或密钥文件，并部署验证 AASA、Universal Link 和 App Store 回落。

Apple 登录服务端配置使用容器只读文件，不使用环境变量保存 `.p8`：

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

部署和绑定说明见 [Apple 登录生产配置与账号绑定实施](./Documents/23%20Apple登录生产配置与账号绑定实施.md)。AIS JWT 仍应通过独立密钥文件或安全配置管理。

## 文档优先级

实现冲突时按以下顺序处理：

1. Apple 当前有效的 App Review Guidelines、StoreKit 和隐私要求。
2. 仓库根目录及本目录的 `AGENTS.md`。
3. `App/IOS/AIS/Documents/00 AIS iOS原生端与全球发行计划.md` 的产品与发行决策。
4. 本目录 `Documents/` 中的详细工程规范。
5. 现有 Web 页面仅作为交互和接口参考，不作为 iOS 业务规则来源。

## 图片 CDN 约定

原生端启动时从 `/api/ais/capabilities` 下载 `imageDelivery`，并在展示图片时统一使用 `AISImageURLBuilder`；Swift 代码不硬编码域名或腾讯云规则。当前服务端配置的模板和案例列表为 600px，任务与素材小预览为 200px，详情及分享卡片为 1200px；非白名单图片、已处理 URL、视频和需要原始文件的链路保持原样。完整规则见 [AIS 腾讯云图片缩略图接入指南](../../../documents/AIS/AIS-腾讯云图片缩略图接入指南.md)，iOS 落地记录见 [腾讯云图片缩略图接入实施](./Documents/11%20腾讯云图片缩略图接入实施.md)。
