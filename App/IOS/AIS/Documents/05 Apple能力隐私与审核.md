# Apple 能力、隐私与审核

## 1. 审核定位

首版应向 Apple 清晰描述为“原生 AI 视觉创作工具”，核心是模板、项目 Agent、Skill、图片/视频生成和编辑。审核说明不要再只写“工业产品智造”，也不要把受控创作 Agent 描述成无限制聊天机器人。

主要审核风险：

- 数字商品支付是否全部使用 IAP；
- AI/用户内容的过滤、举报和处理；
- 第三方 AI 是否接收个人数据且是否取得明确同意；
- 是否具备足够原生功能，而非网站包装；
- Apple 登录和其他登录方式是否符合 4.8；
- 账号删除是否能在 App 内发起；
- 隐私政策、App Privacy 和实际数据流是否一致；
- 中国大陆所需备案信息是否齐全。

官方总依据：[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)。

## 2. Sign in with Apple

客户端：

- 使用 `ASAuthorizationAppleIDProvider`。
- 每次登录生成高熵 raw nonce，提交其 SHA-256 值给 Apple。
- 把 identity token、authorization code、raw nonce 和首次返回的姓名/邮箱发送服务端。
- 姓名只在首次授权返回，取得后立即安全提交；后续不能假设 Apple 继续返回。
- 监听 credential state；账号被撤销或转移时清除本地会话并要求重新登录。

服务端：

- 校验签名、issuer、audience、expiration、nonce 和授权码。
- 使用 Apple `sub` 作为稳定身份键。
- 保存 refresh token 以支持撤销和状态处理。
- 处理隐藏邮箱、已有邮箱冲突和账号绑定。
- 账号删除时调用 Apple REST API 撤销 token。

官方依据：[Authenticating users with Sign in with Apple](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple)。

### 2.1 当前配置状态

- App ID：`com.wekarepartners.studio`
- Team ID：`R3622MSZJ7`
- App Store 名称：`AIS Visual Studio by WeKare`
- Sign in with Apple capability：已在 App ID 和 Xcode entitlement 中启用
- 服务端交换接口：`POST /api/ais/auth/apple/native`
- 登录态绑定接口：`GET /api/ais/account/apple/status`、`POST /api/ais/account/apple/bind`
- 服务端配置：非敏感 Team/Key/Client ID 和 `PrivateKeyPath` 已入库；`.p8` 已在 YZ1、YZ2、SH2 通过 1Panel Compose 只读挂载，不进入 Git、镜像或环境变量
- 客户端状态：邮箱登录后绑定 Apple、Apple 会话 credential state 检查和旧 Keychain 会话兼容代码已完成
- 发布状态：生产 API 和新 iOS 构建尚待发布，真实首次授权、隐藏邮箱、重复登录、绑定冲突和授权撤销仍待真机验收
- Server-to-Server Notification Endpoint：首版可暂不填写；启用账号变更通知前必须先实现并验证专用 HTTPS 接口

Apple 登录与邮箱密码登录在界面中必须明确分层。当前设计将 Apple 登录作为推荐入口，邮箱密码作为已有 AIS 账号的独立表单，不把输入框做成无标签文本行。

部署与验收细节见 [Apple 登录生产配置与账号绑定实施](./23%20Apple登录生产配置与账号绑定实施.md)。

## 3. App 内账号删除

只要支持账号创建，就必须让所有地区用户在 App 内发起完整账号删除。入口建议：

`我的 → 设置 → 账号与安全 → 删除账号`

流程：

1. 展示将删除的项目、消息、记忆、素材、成果和公开内容。
2. 说明必须依法保留的最小支付/风控记录及期限。
3. 重新认证或邮箱验证码。
4. 明确二次确认。
5. 创建删除请求并使旧 token 失效。
6. 展示处理状态和预计完成时间。
7. 删除完成后通知用户并撤销 Apple token。

不能只提供停用、客服邮箱或要求普通用户打电话。若需要网页完成，必须深链到具体删除页面，但首版优先 App 内闭环。

官方依据：[Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/)。

## 4. 隐私政策和第三方 AI

隐私政策必须在 App Store Connect 和 App 内均可访问，至少说明：

- 账号、设备、素材、提示词、项目消息、生成结果、交易和诊断数据的收集方式与用途；
- 使用的 AI 模型/服务类别、可能的数据接收方和处理地区；
- 是否用于模型训练；若不用于训练应明确；
- 存储位置、保留期限、删除和撤回同意方式；
- 中国区与海外区的数据边界；
- 联系方式和投诉渠道；
- 未成年人处理；
- 公开案例的授权与撤回；
- 法定义务下的保留项。

把个人图片、品牌素材、提示词或可能识别个人的信息发送第三方 AI 前，界面应明确说明并取得许可。拒绝许可时，不发送数据，并提供退出或本地可用替代路径。

## 5. PrivacyInfo.xcprivacy

工程创建时加入 `AIS/Resources/PrivacyInfo.xcprivacy`，记录：

- App 自身收集的数据类型和用途；
- 是否用于跟踪；
- 使用 required-reason API 的类别与 Apple 批准理由。

每次引入或升级 SDK 后：

1. 检查 SDK 自带隐私清单和签名。
2. 用 Xcode Privacy Report 检查合并结果。
3. 核对 `UserDefaults`、文件时间戳、磁盘空间、系统启动时间等 required-reason API。
4. 核对 App Store Connect App Privacy 问卷与实际网络数据。
5. Archive 后检查最终 App bundle 中清单有效。

Apple 会拒绝包含无效隐私清单的提交；常用第三方 SDK 还可能要求独立有效清单与签名。

官方依据：[Adding a privacy manifest](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)、[TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)。

## 6. 权限最小化

| 能力 | 申请时机 | 用途文案重点 | 拒绝后的路径 |
| --- | --- | --- | --- |
| 相机 | 用户点击拍摄 | 拍摄创作素材 | PhotosPicker / Files |
| 相册读取 | 尽量使用 PhotosPicker | 选择创作素材 | Files |
| 相册写入 | 用户点击保存到相册 | 保存生成成果 | 保存到 Files / Share Sheet |
| 通知 | 用户启动长任务后或设置中主动开启 | 通知任务完成、失败或需处理 | App 内任务列表 |
| 麦克风 | 首版不申请 | 无 | 无 |
| 定位 | 首版不申请 | 区域不依赖 GPS | 服务端区域配置 |
| 跟踪 | 首版不申请 ATT | 不做跨 App 跟踪 | 无 |

权限说明不能用笼统文案；只在功能触发时请求，不能在首次启动集中索取无关权限。

## 7. APNs 与通知内容

- 先解释通知价值，再调用系统授权。
- 通知只包含任务状态、安全摘要和不可猜测的内部路由标识。
- 不包含完整提示词、用户图片、产品机密、余额或支付详情。
- 服务端使用 token-based APNs、HTTP/2 与 TLS。
- sandbox 与 production token 隔离；失效 token 及时清理。
- 用户可在 App 内管理任务完成/失败通知偏好。

官方依据：[Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)。

## 8. AI 内容和用户内容安全

后端必须同时检查输入和输出，客户端拦截不能代替服务端安全：

- 违法、色情、暴力、仇恨和自伤内容；
- 冒充真人、未经同意的人脸和欺骗性内容；
- 侵犯商标、版权和肖像权；
- 个人敏感信息；
- 中国区监管要求的内容。

App 内提供：

- 举报/投诉入口；
- 内容删除或下架申请；
- 客服联系方式；
- 生成内容标识说明；
- 被拒绝时的原因类别和申诉路径。

若未来开放用户自由发布、评论或社交，必须在开发前重新评审 Guideline 1.2 所需的过滤、举报、屏蔽和联系机制。

## 9. 生成式 AI 体验

- AI 生成开始前说明可能不准确和需要复核。
- 付费前展示成果数量、积分、预计时间和失败退款。
- 显示哪些素材将提交给 AI。
- 输出提供继续修改、删除、举报和来源/标识说明。
- 不把 AI 输出伪装为真人、官方声明或专业结论。

设计参考：[Human Interface Guidelines — Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai)。

## 10. App Store Connect 材料

海外首发至少准备：

- App 名称、副标题、描述、关键词、分类、年龄分级；
- 隐私政策 URL、支持 URL、营销 URL；
- iPhone/iPad 截图和 App Preview（如使用）；
- Sign in with Apple 配置；
- IAP 商品名称、描述、审核截图和区域价格；
- App Privacy 问卷；
- 加密出口合规信息；
- 内容权利声明；
- 审核测试账号与操作步骤；
- 后端长期可用的审核环境；
- Review Notes 中的 AI、积分、区域和账号删除说明。

当前 App Store Connect 已创建 `1.0` 版本记录，主语言为英语（美国）。正式送审前仍需：

- 上传与真实功能一致的 iPhone 截图；保留 iPad target 时同步提供 iPad 截图；
- 建立独立的隐私政策和技术支持页面，不能让 `/privacy`、`/contact` 回落到产品首页；
- 完成核心生成和 StoreKit 后再定稿描述，不能宣称尚未实现的能力；
- 上传 Archive 并选择构建版本。

## 11. Review Notes 建议内容

说明：

- App 是原生 AI 视觉创作工具；
- 模板、项目 Agent 和 Skill 的核心流程；
- Agent 只执行审核后的声明式 Skill；
- 数字积分只通过 StoreKit 购买；
- 购买入口、测试商品和测试账号；
- 用户创建内容默认私有，公开案例经过后台审核；
- 举报和账号删除入口路径；
- 视频或某些模型受区域 capabilities 控制；
- 首次提交不包含中国大陆 storefront。

不要要求审核员联系人工后才能体验核心流程，也不要让演示账号依赖一次性验证码失效。

## 12. 审核前检查

- 无崩溃、占位页、测试文案和不可用按钮。
- 所有链接、协议、客服和删除账号可用。
- 审核账号有足够积分，或 Sandbox IAP 能完成购买。
- 后端模型和任务队列在审核期间稳定。
- App 内没有外部支付引导。
- App Privacy、隐私政策、隐私清单和实际网络请求一致。
- 所有第三方素材、模板和字体有授权。
- AI 输入输出安全、举报和下架链路可验证。
