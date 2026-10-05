# PixaRivo 图漾 iOS

<!-- markdownlint-disable MD013 -->

> 项目关系：[项目关联与上下文检索索引](../../../documents/项目关联索引.md)

PixaRivo 是 WeKare Partners LLC 推出的模板化视觉合成应用。用户从现有模板开始，替换图片、编辑允许修改的文字，预览后提交合成并管理作品。

文档入口、发布资料和未闭环事项统一维护在 [PixaRivo iOS 文档中心](./Documents/README.md)。

非 iOS 的官网、宣传视频和推广资料统一维护在 [PixaRivo 产品文档中心](../../../documents/PixaRivo/README.md)。

## 工程

- SwiftUI、Swift 6、最低 iOS 17
- Bundle ID：`com.wekarepartners.pixarivo`
- API：`https://ais.get-free.net`
- 支持在“我的 → 语言”中选择跟随系统、简体中文或 English；应用内界面立即切换，无需重新启动，选择会在本机持久保存
- 应用内语言只影响本地界面和本地化内容，不改变 API 基址、接口区域策略或静态图片 CDN；素材区域仍由独立的“素材区域”设置控制
- 桌面名称按系统语言本地化：简体中文显示“图漾”，英文及默认语言显示“PixaRivo”
- 版本采用 `主版本.次版本.修订版本`；当前工程营销版本为 `1.2.12`，本地
  `CURRENT_PROJECT_VERSION = 58`。线上 Build 由发布流程自动生成；`1.2.11 (Build 133)` 和 `1.2.9 (Build 125)` 已发布，
  `1.2.6 (Build 112)` 已发布，不从本地值推算
- 简体中文和 English (U.S.) 更新说明记录在 [`RELEASE_NOTES.md`](./RELEASE_NOTES.md)，日语、西班牙语、巴西葡萄牙语和繁体中文记录在 [其他语言发布说明](./RELEASE_NOTES_OTHER_LANGUAGES.md)；上传完成后补充实际构建与发布时间
- `1.2.0` 以前的中英文版本记录按主版本和次版本归档，现有记录见 [1.1 时间线](./ReleaseNotes/1.1.md)
- 原生 Launch Screen 延续官网暖米白、朱红与炭黑视觉，复用品牌图标，并按系统语言显示中文或英文品牌文案
- 静态 Launch Screen 后无缝衔接约 0.5 秒的轻量 SwiftUI 品牌动效；仅保留品牌图标与字标的淡入缩放，支持系统“减少动态效果”，不阻塞底层数据静默加载
- 登录态启动时并行预加载并缓存图片计费规则；模板编辑器在本地即时计算预计积分，生成时携带规则版本与积分交由后端复核
- 仅支持 iPhone，模板与案例使用双列瀑布流
- 模板与案例严格使用服务端画幅比例，支持横图、竖图与方图混排

## 产品范围

- 用户从现有模板开始制作，不提供文生图、通用图生图或视频生成入口
- 用户只能替换模板允许修改的图片和文字，服务端负责报价、合成、任务与作品管理
- 创作时可自主选择是否允许添加平台宣传标识以享受规则优惠，以及是否允许推荐到公开案例库
- 首页、模板、案例、作品及账户相关页面在首次无内容加载时显示明确反馈；已有内容刷新保持非遮挡式静默更新
- 首页展示编辑精选和模板瀑布流；案例展示公开作品；作品页展示当前用户的合成任务
- 首页顶部共用 AIS 后台运营文案池，优先读取本地有效缓存，按天静默刷新，并在进入首页时随机展示眉题、主标题和副标题
- 用户可在“我的”页面修改昵称和头像，资料与 AIS 账户保持同步
- 登录与注册使用独立页面；支持邮箱验证码注册、邮箱验证码登录及已有账户密码登录，注册成功后直接建立可刷新会话
- 支持充值码、邀请链接和会员等级进度，相关规则全部读取 AIS 服务端系统配置

## 图片交付与缓存

- 启动时读取 `GET /api/ais/capabilities` 的 `imageDelivery`，不在客户端硬编码 CDN 域名或转换参数
- 中国区与国际区分别遵循服务端下发的 Tencent/Cloudflare 图片规则
- 列表根据实际渲染宽度乘以屏幕倍率选择可用的小图档位，详情页使用服务端 detail 档位
- 图片通过 URLSession 请求并写入磁盘缓存，相同 URL 的并发请求会合并；调试记录区分网络与磁盘来源，不把普通加载标成 `memory-image`
- 磁盘缓存有效期为 7 天，上限 512 MB，超过后回收到 384 MB
- 横图、竖图和方图均由固定容器约束，避免图片原始尺寸撑破 SwiftUI 布局

## 网络调试

- Debug 和 TestFlight sandbox 环境默认隐藏“网络与图片缓存”入口；在“我的”页面连续点击版本号 5 次后仅在本机解锁
- 可查看 API 状态、耗时、图片 preset、目标像素宽度及内存/磁盘/网络来源
- 支持清除图片缓存和导出脱敏日志；Token、邮箱和 URL 查询参数不会写入导出内容

## 积分与支付

- 积分中心包含 Apple 积分套餐、充值码和邀请功能
- 充值规则通过 `GET /api/ais/recharge/getpricing` 按账户、App Store storefront 和地区读取，CN 与 US 不共用客户端写死价格
- iOS 内数字积分只能通过 StoreKit 购买，实际成交金额和币种仅使用 Apple 返回的 `Product.displayPrice`
- 商品是否开放由 `/api/ais/capabilities` 的 `ios.storeKitEnabled`、允许地区和后台套餐的 `IosEnabled/Regions` 共同决定
- StoreKit 交易必须经服务端验签和幂等入账后才调用 `finish()`；微信、支付宝、Stripe 和 PayPal 仅用于网页端
- 自动续费月付通过 PixaRivo 独立 App Store Connect 订阅组提供；当前配置 Plus 与 Pro 两档月度商品，并已接入服务端订阅周期账务、Notifications V2、交易恢复及订阅管理
- PixaRivo 使用独立 Bundle ID，不能直接复用归属于 AIS App 的 StoreKit Product ID

## 接口

- `GET /api/ais/style-templates`
- `GET /api/ais/style-templates/{id}`
- `GET /api/ais/jobs/gallery`
- `POST /api/ais/assets`
- `POST /api/ais/style-templates/{id}/quote`
- `POST /api/ais/style-templates/{id}/generate`（客户端统一称为“合成”）
- `GET /api/ais/jobs`
- `POST /api/ais/auth/email/password-login`
- `POST /api/ais/auth/email/code`
- `POST /api/ais/auth/email/register`
- `POST /api/ais/auth/email/login`
- `GET /api/ais/account`
- `POST /api/ais/account/profile`
- `GET /api/ais/capabilities`
- `GET /api/ais/recharge/getpricing`
- `POST /api/ais/recharge/redeem`
- `POST /api/ais/storekit/transactions/verify`（服务端上线后由系统开关启用）
- `GET /api/ais/promotion/overview`
- `GET /api/ais/promotion/inviteqrcode`
- `GET /api/ais/account/membership-progress`
- `GET /api/ais/push-devices/config`
- `POST /api/ais/push-devices`
- `DELETE /api/ais/push-devices/current`
- `GET /api/ais/notifications`
- `GET /api/ais/notifications/unread-count`
- `POST /api/ais/notifications/{id}/read`
- `POST /api/ais/notifications/read-all`

## 远程通知配置

- 服务端通过环境变量配置 `AIS__IOS__PushNotificationsEnabled=true`、`AIS__APNs__TeamId`、`AIS__APNs__KeyId`、`AIS__APNs__BundleId` 和 `AIS__APNs__PrivateKey`
- `AIS__APNs__PrivateKey` 使用 Apple Developer 下载的 `.p8` 内容；密钥仅存放在部署环境的 Secret 中，不提交到仓库
- Apple Developer 后台需为 `com.wekarepartners.pixarivo` 启用 Push Notifications，并分别更新 Development、Ad Hoc 与 App Store provisioning profile
- Debug 构建使用 APNs sandbox，Release/TestFlight 使用 APNs production；消息记录不依赖 APNs 投递结果

## 账户资料

- 昵称与头像使用 AIS 现有账户资料接口，不维护 PixaRivo 私有副本
- 头像从照片库选取后先在本机正方形裁剪，可拖动和缩放；确认后输出最多 `512×512` 的 JPEG，再通过 `POST /api/ais/assets` 上传，原始大图不会发送到服务器
- 头像展示遵循与模板、案例相同的小图 CDN 规则和磁盘缓存策略
- 更新资料时会保留手机号、公司、税号与地区等既有字段，避免覆盖用户在 AIS 网页端维护的数据
- 更新成功后立即写回加密会话，重新打开 App 或静默刷新 Token 后仍显示最新资料

## App Store 信息

- 公司：WeKare Partners LLC
- 技术支持：<https://pixarivo.get-free.net/support/>
- 用户服务协议：<https://pixarivo.get-free.net/terms/>
- 素材上传与合规提示：<https://pixarivo.get-free.net/upload-compliance/>
- 案例内容与知识产权声明：<https://pixarivo.get-free.net/gallery-ip/>
- 登录后按服务端协议集合版本检查同意状态；未同意时需等待 3 秒并滚动到底部，同意记录由服务端保存

## 构建

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild \
  -project PixaRivo.xcodeproj \
  -scheme PixaRivo \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```
