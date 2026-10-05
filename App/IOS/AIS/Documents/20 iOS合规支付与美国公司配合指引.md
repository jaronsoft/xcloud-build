# iOS 合规支付与美国公司配合指引

> 状态：📝 方案已确认，Apple 商务配置、服务端账务与联调待完成
> 规则核对日期：2026-07-29
> 海外发行与 Apple 收款主体：`WeKare Partners LLC`

## 1. 决策结论

AIS 在 iOS 内出售积分和自动续费订阅，两者用于图片、视频、Skill 和其他数字创作服务，均属于 App 内数字商品。消耗型积分的账务规范见 [StoreKit 积分与账务](./04%20StoreKit积分与账务.md)；四档自动续费订阅、逐国定价、会员映射和首月优惠见 [iOS 自动续费订阅与区域定价策略](./21%20iOS自动续费订阅与区域定价策略.md)。

首个支付闭环统一采用：

- StoreKit 2；
- Consumable In-App Purchase；
- App Store Connect 本地价格；
- AIS 服务端验单、幂等入账、退款冲正与对账；
- `WeKare Partners LLC` 作为 Apple Developer、Paid Applications Agreement、收款和美国税务主体。

首版 iOS App 内不展示或引导：

- Apple Pay；
- Stripe、PayPal、微信、支付宝；
- 网页充值、客服代充、银行转账；
- 外部购买链接、二维码、价格对比或“去官网更便宜”等文案；
- 自定义充值金额。

Apple 当前允许美国 storefront 的 App 在一定条件下加入外部购买引导，但该规则具有地区差异，且会增加支付主体、退款、税务、客服、价格披露和跨区审核复杂度。AIS 首版不使用该能力；如未来评估，必须另立项目，由美国律师、财税和 Apple 审核负责人重新核对当期规则，不能直接复用 Web 充值页面。

官方依据：

- [App Review Guidelines 3.1.1](https://developer.apple.com/app-store/review/guidelines/)
- [StoreKit](https://developer.apple.com/storekit/)
- [Configure In-App Purchases](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/)

## 2. 当前基础与缺口

### 2.1 已具备

- Apple Developer Organization：`WeKare Partners LLC`。
- Team ID：`R3622MSZJ7`。
- Bundle ID：`com.wekarepartners.studio`。
- App Store Connect App：`AIS Visual Studio by WeKare`。
- iOS 已有 `.storekit` 本地配置和 StoreKit 2 购买页。
- 客户端已实现商品交集、购买、pending、已验证交易提交、`Transaction.updates` 监听。
- 客户端只在服务端确认到账后调用 `transaction.finish()`。
- AIS 后台档位已具备 `PackageKey`、`AppleProductId`、`IosEnabled`、区域、排序和 `RuleVersion`。

### 2.2 仍缺失

- 未证实 Paid Applications Agreement、W-9、美国银行账户和 Apple 合规审查均为有效状态。
- App Store Connect 尚未创建并送审首批 consumable 商品。
- `.storekit` 当前示例 Product ID `com.wekarepartners.studio.points1000` 与既定稳定 Product ID 规范不一致。
- 客户端购买时尚未传入 `appAccountToken`。
- 尚无 StoreKit 专用服务端订单、历史积分规则、JWS 验证、Apple Server API、通知 V2、退款冲正和每日对账闭环。
- 尚未完成 Sandbox、TestFlight、退款和异常场景的端到端证据。
- App Store Connect 尚未创建自动续费订阅组和 `starter / creator / pro / max` 四档月付商品。
- 尚未完成中国、美国月度点数测算，以及其他目标 storefront 的逐国人工定价和毛利审批。
- 尚未实现订阅周期、会员来源合并、订阅点数到期、升级降级和恢复购买账务。

在上述缺口关闭前，`storeKitEnabled` 不得在生产环境对用户开放。

## 3. 美国公司必须配合的事项

### 3.1 主体与账号

`WeKare Partners LLC` 负责人需要确认并留档：

- LLC 法定名称、注册地址、公司状态与 Apple Developer Membership 完全一致；
- D-U-N-S 信息与公司注册信息一致；
- Account Holder 是公司授权人员，Apple Account 已启用双重认证；
- Apple Developer Program 年费续费方式和负责人；
- App Store 卖方名称、客服主体、隐私政策中的海外运营主体一致；
- Team ID、Bundle ID 和 App 归属不存在个人账号代持。

组织账号必须由可与 Apple 签约的法律实体持有，Apple 使用 D-U-N-S 核验组织身份。参考：

- [Apple Developer Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment)
- [D-U-N-S Number](https://developer.apple.com/help/account/membership/D-U-N-S)

### 3.2 人员与权限

建议最小权限分工：

| 角色 | 建议持有人 | 必须完成 |
| --- | --- | --- |
| Account Holder | 美国公司授权负责人 | 签署协议、续费、批准银行变更、处理主体核验 |
| Finance | 美国公司财务或 CPA | W-9、银行资料、月度结算和税务报表 |
| Admin | 受控的平台管理员 | 创建 IAP Key、配置通知地址、必要的账号管理 |
| App Manager | 产品发行负责人 | 商品、价格、地区、元数据、审核提交和 TestFlight |
| Developer | iOS 开发负责人 | Bundle、StoreKit、Sandbox 和构建联调 |
| Customer Support | 海外客服 | 订单查询、退款解释、用户投诉和 App Store 评价 |

不得共享 Account Holder 密码或双重认证验证码。通过 App Store Connect 邀请成员并分配最小角色。Account Holder 是唯一可代表公司签署法律协议的角色；Admin 或 Finance 发起银行变更后仍可能需要 Account Holder 批准。参考：

- [App Store Connect role permissions](https://developer.apple.com/help/app-store-connect/reference/account-management/role-permissions)
- [Apple Developer Program roles](https://developer.apple.com/help/account/access/roles/)

### 3.3 Paid Applications Agreement

Account Holder 必须在 App Store Connect 的 `Business → Agreements`：

1. 接受最新 Paid Applications Agreement；
2. 确认状态为有效，不存在 `New`、`Pending User Info`、`Pending Bank Info`、`Pending Tax Info` 或主体更新待处理；
3. 保存协议 PDF、接受日期、协议版本和签署人；
4. 指定每月检查人，Apple 更新条款时及时处理。

没有有效付费协议，IAP 不能正常销售和结算。参考：[View agreements status](https://developer.apple.com/help/app-store-connect/manage-agreements/view-agreements-status)。

### 3.4 美国税务

Finance/CPA 需要：

- 使用 `WeKare Partners LLC` 的正确税务分类和 EIN 填写 W-9；
- 确认 legal name、EIN、地址与 IRS 和 Apple 记录一致；
- 评估 LLC 是 disregarded entity、partnership 还是 corporation，并由 CPA 决定 W-9 的正确填写方式；
- 保留 Apple 月度财务报告、税务报告、调整和退款记录；
- 明确 IAP 收入在美国公司账上的收入确认、Apple 佣金、税费、退款及向中国合作方结算的会计处理；
- 如公司地址、税务分类或 EIN 变化，先由 CPA 和 Account Holder 制定更新方案。

本文不是美国税务意见，W-9 和跨境结算必须由美国 CPA/税务律师复核。Apple 要求美国主体为付费协议提交 W-9，企业使用 EIN。参考：[Provide tax information](https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information)。

### 3.5 银行与收款

Finance 需要在 `Business → Agreements → Bank Accounts`：

- 绑定与 Apple Developer 法律主体一致的美国公司银行账户；
- 确认 routing number、account number、账户名、账户类型和币种准确；
- 不使用员工个人账户或无法证明归属的第三方代收账户；
- 完成 Apple 或银行合作方要求的补充 KYC/公司文件；
- 由 Account Holder 审批新增或变更；
- 完成一笔 Apple 实际结算后的到账核验。

银行信息必须与登记主体一致，且税务表单需完成后 Apple 才能处理银行资料。参考：

- [Enter banking information](https://developer.apple.com/help/app-store-connect/manage-banking-information/enter-banking-information/)
- [Compliance review](https://developer.apple.com/help/app-store-connect/reference/account-management/compliance-review)

### 3.6 Small Business Program

美国公司应评估并留档是否符合 App Store Small Business Program：

- Account Holder 已接受最新 Paid Applications Agreement；
- 公司及所有 Associated Developer Accounts 的相关收益满足 Apple 当期门槛；
- 如符合，由 Account Holder 申请；
- 财务模型同时保留标准佣金和 15% 佣金两种情景，不把获批前的较低佣金视为确定收入；
- 每年复核资格和关联开发者账号。

Apple 当前公布的计划对符合条件的付费 App 和 IAP 提供 15% 佣金率。参考：[App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/)。

### 3.7 与佳融公司的合同和结算

美国公司与扬州市佳融信息技术有限公司至少签署并留档：

- AIS 软件和品牌在海外 App Store 的发行授权；
- iOS 用户协议、隐私政策和客服责任；
- Apple IAP 总收入、Apple 佣金、销售税/间接税、退款、拒付、汇兑和银行费用的口径；
- 可结算净收入公式、币种、汇率来源、结算周期、发票/凭证和争议期；
- 退款或 Apple 追索跨月发生时的后续调整；
- 用户积分负债、赠送积分成本和未消费余额的会计责任；
- 数据控制者/处理者角色、跨境数据、子处理者、安全事件和删除请求；
- 内容合规、知识产权投诉、制裁与出口管制责任；
- 合同终止、App 转移、用户余额和历史订单继续服务安排。

建议结算基线：

```text
可结算净收入
= Apple 财务报告中归属于 AIS 的 Proceeds
+ 后续期间归属于历史 AIS 交易的 Apple 调整
- 美国公司另行实际承担且合同约定可扣除的银行、税务与合规成本
```

Apple 报告中的 Proceeds 已经反映相应佣金、税费或退款调整时，不得再次重复扣除。也不得直接使用“用户支付金额 × 固定分成比例”，否则 Apple 税费、佣金、退款和汇兑差异无法对平。

## 4. App Store Connect 操作指引

### 4.1 创建首批商品

首版建议只建立 3 个稳定档位，具体积分由产品和财务确认后再创建：

| PackageKey | Product ID | 类型 | 用途 |
| --- | --- | --- | --- |
| `starter` | `com.wekarepartners.studio.points.global.starter` | Consumable | 入门积分包 |
| `plus` | `com.wekarepartners.studio.points.global.plus` | Consumable | 常用积分包 |
| `pro` | `com.wekarepartners.studio.points.global.pro` | Consumable | 专业积分包 |

创建前必须确认：

- Product ID 一旦使用不得按新积分基线复用；
- 不把金额、币种或积分数写入 Product ID；
- 后台 `PackageKey`、`AppleProductId` 与 `.storekit` 完全一致；
- 首版只开已经完成服务和客服准备的 storefront；
- China mainland 继续排除，直到中国区发行门禁完成。

每个商品配置：

- Reference Name；
- Product ID；
- Consumable 类型；
- 英文（美国）和简体中文显示名、描述；
- Apple 价格点和 storefront 可用性；
- 正确的 tax category；
- 审核截图；
- Review Notes，说明积分用途、购买入口和测试步骤。

Apple 的税种选择会影响税务计算和预计收益，必须由产品、财务共同确认，不由开发人员猜测。参考：

- [Set a tax category](https://developer.apple.com/help/app-store-connect/manage-app-information/set-a-tax-category)
- [App pricing and availability](https://developer.apple.com/help/app-store-connect/reference/pricing-and-availability/app-pricing-and-availability)

### 4.2 创建自动续费订阅

自动续费订阅首发建立一个 subscription group，并按 Apple 权益等级从高到低配置：

| PlanCode | Product ID | 中国大陆 | 美国 | 会员等级 | Apple Level |
| --- | --- | ---: | ---: | --- | ---: |
| `max` | `com.wekarepartners.studio.subscription.max.monthly` | `¥199.9/月` | `$99.99/月` | `Max` | 1 |
| `pro` | `com.wekarepartners.studio.subscription.pro.monthly` | `¥99.9/月` | `$69.99/月` | `Pro` | 2 |
| `creator` | `com.wekarepartners.studio.subscription.creator.monthly` | `¥49.9/月` | `$19.99/月` | `Plus` | 3 |
| `starter` | `com.wekarepartners.studio.subscription.starter.monthly` | `¥19.9/月` | `$9.99/月` | `VIP` | 4 |

配置要求：

- Product ID 不包含价格、币种、国家或月度点数。
- 中国、美国分别配置月度点数；其他国家逐国人工配置价格和额度，未审批的 storefront 不开放。
- 四档均设置首个计费月约七折的 `Pay As You Go` introductory offer，使用 Apple 可选的最接近价格点。
- 购买页必须展示促销持续时间、后续标准月费、自动续费、点数到期和取消方式。
- 首发不配置免费试用、年付、Billing Grace Period 或点数结转。
- 升级、降级、退款、恢复购买和周期续费必须通过服务端订阅状态与 Apple 通知验收后才能开放。

### 4.3 IAP Key

Account Holder 或 Admin 在：

`Users and Access → Integrations → In-App Purchase`

创建专用 IAP Key，并把以下信息通过密钥管理系统交给服务端负责人：

- Key ID；
- Issuer ID；
- `.p8` 私钥文件；
- 创建人、创建时间、用途、保管位置和轮换负责人。

`.p8` 只能下载一次，禁止写入仓库、App 包、聊天记录或普通网盘。Sandbox 与 Production 必须使用不同的 Apple API 地址、配置作用域和日志标签；IAP Key 是否拆分由密钥数量、权限边界和运维能力决定，不把“同一 Key 可访问两个环境”误当成同一业务环境。泄露时立即吊销并轮换。参考：[Generate keys for In-App Purchases](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/generate-keys-for-in-app-purchases)。

### 4.4 App Store Server Notifications V2

App Manager/Admin 在 App 信息中分别配置：

- Production Server URL；
- Sandbox Server URL；
- Version 2。

服务端接口上线并通过签名验证、幂等和重放测试后才能填写生产地址。若未配置 Sandbox URL，Apple 可能把 Sandbox 通知发送到 Production URL，因此两个环境必须显式隔离。参考：[Enter server URLs for App Store Server Notifications](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications)。

### 4.5 审核材料

美国公司和产品负责人提供：

- 长期有效的审核账号；
- 购买入口路径；
- 每个积分包的用途和到账说明；
- 审核期间可用的后端、模型、队列和测试数据；
- “积分永久有效”的购买页文案；
- 购买失败、pending、退款和客服说明；
- App 内不存在外部支付入口的检查记录；
- 商品审核截图和 Review Notes；
- 支持邮箱、隐私政策、用户协议和退款咨询流程。

IAP 可以随 App 版本一并提交审核。参考：[Submitting for review](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review)。

## 5. 服务端与客户端安全边界

### 5.1 客户端只负责

- 从 StoreKit 获取商品和本地价格；
- 展示后台返回的基础积分、赠送积分和规则版本；
- 调用 `product.purchase(options:)`；
- 提交 StoreKit 已验证交易的 JWS；
- 监听 `Transaction.updates`；
- 在服务端确认幂等入账后 `finish()`；
- 展示余额、订单和同步状态。

客户端不能决定可信积分、价格、首充资格或退款结果。

### 5.2 服务端必须负责

- 验证 Apple JWS 签名和证书链；
- 校验 bundle ID、environment、product ID、商品类型、购买时间、撤销状态和 storefront；
- 使用 App Store Server API 复核交易；
- 用不可逆 UUID `appAccountToken` 绑定 AIS 账号；
- 按 `productId + storefront + purchaseDate` 匹配不可变历史规则；
- 使用 `environment + transactionId` 唯一约束幂等入账；
- 原子处理首充资格；
- 保存 Apple 订单、积分流水和规则快照；
- 验证并幂等处理 Notifications V2；
- 对退款/撤销生成冲正流水；
- 每日对账并告警。

### 5.3 密钥规则

- IAP `.p8`、Issuer ID、Key ID 仅存服务端 Secret Manager/环境变量；
- 不进入 Git、客户端、数据库明文字段和日志；
- 日志只保留 transaction ID 的必要审计信息，不记录完整 JWS；
- Sandbox 与 Production 订单、通知和密钥配置显式区分；
- 密钥至少每年复核一次，并支持双密钥无停机轮换；
- 离职、权限变化或疑似泄露时立即轮换。

## 6. 待开发计划

### P0：美国公司商务门禁

- [ ] 核验 `WeKare Partners LLC` 法定名称、地址、D-U-N-S、Team ID 和 Account Holder。
- [ ] 确认 Apple Developer Membership 续费正常。
- [ ] 接受最新 Paid Applications Agreement 并归档。
- [ ] 由美国 CPA 完成并复核 W-9、EIN 和税务分类。
- [ ] 绑定美国公司银行账户并完成 Account Holder 审批。
- [ ] 完成 Apple KYC/Compliance Review。
- [ ] 评估并申请 Small Business Program。
- [ ] 签署 WeKare Partners 与佳融的发行、数据和 IAP 结算协议。
- [ ] 指定 Finance、App Manager、Developer、Customer Support 负责人。

验收：Apple `Business` 页面无待处理项；付费协议、税务和银行均有效；责任人和合同归档完成。

### P1：商品与密钥配置

- [ ] 由产品确认首批 3 个档位的基础积分和赠送规则。
- [ ] 由财务根据 Apple 实际净收入测算价格点，确认标准佣金和 15% 两种情景。
- [ ] 创建 Product ID、Consumable 商品、价格、地区、本地化和 tax category。
- [ ] 创建一个自动续费订阅组和四档月付商品，按 `Max → Pro → Creator → Starter` 设置 Apple Level。
- [ ] 配置中国、美国价格和首个计费月约七折的 introductory offer。
- [ ] 完成中国、美国订阅额度测算，以及其他目标 storefront 的逐国价格、额度和毛利审批。
- [ ] 更新 `.storekit`，移除旧 `points1000` 示例标识。
- [ ] 更新 AIS 后台固定档位，使两端 Product ID 和 `RuleVersion` 一致。
- [ ] 创建 Sandbox 测试账号。
- [ ] 创建并安全交付 IAP Key。
- [ ] 预留 Sandbox/Production Notifications V2 地址，服务端验收后再启用。

验收：App Store Connect、`.storekit` 和 AIS 后台三方配置逐项一致，商品可从 StoreKit Sandbox 拉取。

### P2：服务端账务闭环

- [ ] 新增不可变的 StoreKit 商品规则历史表。
- [ ] 新增 Apple StoreKit 订单表、通知表和对账结果表。
- [ ] 为雪花 ID 增加 `StringJsonConverter`，更新模型 `MigrateVersion` 和 `Database/` 脚本。
- [ ] 新增专用 `GET /api/ais/storekit/products`。
- [ ] 实现 `POST /api/ais/storekit/transactions/verify`。
- [ ] 实现 `POST /api/ais/storekit/transactions/sync`。
- [ ] 实现 `GET /api/ais/storekit/orders` 和单笔状态查询。
- [ ] 接入 App Store Server API。
- [ ] 实现 Notifications V2 接口、JWS 验签、通知幂等和重放保护。
- [ ] 实现 `appAccountToken` 映射，不直接暴露用户雪花 ID。
- [ ] 实现 `environment + transactionId` 数据库唯一约束。
- [ ] 实现商品、区域、历史规则匹配和首充原子占用。
- [ ] 实现积分入账、退款/撤销冲正、负余额或受限状态。
- [ ] 实现每日 Apple 订单、AIS 订单和积分流水对账。
- [ ] 新增不可变订阅周期、地区额度和促销规则快照，处理续费、取消、升级、降级、Billing Retry、过期、退款和撤销。
- [ ] 统一合并充值、有效订阅和管理员授权会员等级，并在订阅结束后回落到仍有效的最高来源。
- [ ] 实现订阅点数优先消耗、周期到期清零和永久积分保留。
- [ ] 管理端 `vite/` 与 `www/` 同步增加 Apple 订单、通知、对账和异常处理页面。
- [ ] 增加验单、重复提交、并发首充、退款和伪造 JWS 自动测试。

验收：同一交易重复提交只入账一次；退款生成冲正流水；订单、积分和 Apple 数据可对账。

### P3：iOS 完整购买体验

- [ ] 为每个 AIS 用户生成并持久化不可逆 `appAccountToken`。
- [ ] 使用 `product.purchase(options: [.appAccountToken(...)])` 发起购买。
- [ ] 商品页展示基础积分、各类赠送、总到账和“积分永久有效”。
- [ ] 增加启动时 `Transaction.unfinished` 同步。
- [ ] 增加“同步购买记录”入口，不使用误导性的“恢复积分”。
- [ ] 增加 Apple 订单列表、pending、到账、退款和冲正状态。
- [ ] 增加四档订阅购买、当前套餐、自动续费状态、升级降级和“恢复订阅”入口。
- [ ] 展示首月优惠期限、后续标准价、订阅点数到期时间和取消方式。
- [ ] 服务端暂不可用时保留未 finish 交易并自动重试。
- [ ] 账号切换时隔离交易提交和 UI 状态。
- [ ] 审计所有 iOS 页面、WebView、协议和客服文案，移除外部支付引导。
- [ ] 增加中英文 VoiceOver、Dynamic Type、弱网和错误恢复测试。

验收：购买、杀进程恢复、断网恢复、pending、跨设备同步和退款状态均可解释、可恢复、可审计。

### P4：Sandbox、TestFlight 与上线

- [ ] Xcode StoreKit Configuration 覆盖成功、取消、pending、未验证和断网。
- [ ] Sandbox 覆盖真实购买、重复交易、账号切换和本地价格。
- [ ] 触发 Sandbox 通知并验证签名、幂等和退款冲正。
- [ ] TestFlight 验证真实签名环境、商品加载和服务端入账。
- [ ] 提供审核账号、Review Notes、商品截图和操作视频。
- [ ] 确认 App 内无 Apple Pay、第三方支付、外链充值和自定义金额。
- [ ] 首发继续排除 China mainland storefront。
- [ ] 小范围发布，监控支付成功率、入账延迟、重复率、退款率和对账差异。
- [ ] 完成首个 Apple 结算周期的银行到账和财务对账。

验收：App Review 通过；首批真实订单可从用户、Apple、AIS 账本和银行结算四层追溯。

## 7. 上线硬门禁

以下任一项未完成，不开放生产 IAP：

- Paid Applications Agreement、W-9、银行或 Apple 合规审查不是有效状态；
- Product ID 在 App Store Connect、AIS 后台和 iOS 配置中不一致；
- 服务端只信任客户端结果，未独立验证 Apple 交易；
- 没有数据库幂等唯一约束；
- 没有历史规则快照；
- 没有退款/撤销冲正；
- 没有 Notifications V2 或补偿性查询机制；
- 没有每日对账与异常告警；
- 消耗型充值积分会过期，或订阅点数到期规则未在购买前明确披露；
- App 内存在外部支付、代充或 Apple Pay 入口；
- Sandbox 和 TestFlight 没有形成可复核记录。

## 8. 待业务确认

开发开始前由产品、美国公司和财务共同确认：

1. 首批 3 个消耗型积分包分别包含多少基础积分。
2. 首充和促销赠送是否对消耗型 iOS 积分包开放，赠送积分是否同样永久有效。
3. 中国、美国四档订阅的月度点数和典型生成次数。
4. 除中国、美国外的首发 storefront 清单及逐国人工定价。
5. 每个商品的 Apple 价格点和可接受毛利底线。
6. 退款导致已消费积分不足时采用负余额还是限制新任务。
7. 海外客服邮箱、服务时区、响应时限和退款说明模板。
8. WeKare Partners 与佳融的净收入结算公式、周期和汇率来源。
9. 美国 CPA、Account Holder、Finance、App Manager 和密钥保管人的姓名与备份人。

## 9. 维护规则

- 每次送审前重新核对 Apple 当期支付规则，不能把本文件的日期性判断永久化。
- Apple 协议、税务、银行、主体、Product ID 或服务器通知地址变化时，必须同步更新本文件和变更记录。
- 商品基础积分变更时创建新 Product ID；旧商品只停止新购，不删除历史规则。
- 所有商务状态只在美国公司提供 App Store Connect 截图或导出凭证后标记完成。
- 技术任务状态同步维护到 [开发任务清单](./07%20开发任务清单.md)。
