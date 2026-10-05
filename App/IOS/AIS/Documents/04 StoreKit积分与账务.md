# StoreKit 积分与账务

## 1. 结论

AIS 的积分用于购买 App 内图片、视频、Skill 和数字创作服务，属于数字商品。iOS 用户充值使用 StoreKit 2 消耗型 In-App Purchase，不使用 Apple Pay。

美国发行主体的付费协议、税务、银行、App Store Connect 操作和分阶段实施责任见 [iOS 合规支付与美国公司配合指引](./20%20iOS合规支付与美国公司配合指引.md)。

本文只定义**消耗型积分充值**。自动续费订阅采用独立商品、周期权益和到期账务，详见 [iOS 自动续费订阅与区域定价策略](./21%20iOS自动续费订阅与区域定价策略.md)。两者可以共用会员等级，但不得共用商品类型、积分有效期或恢复购买语义。

分工如下：

- **App Store Connect / StoreKit**：商品可售状态、用户所在 storefront、本地币种、实际价格、税务和 Apple 交易。
- **AIS 后台定价**：稳定档位、基础积分、注册赠送、首充赠送、促销赠送、规则版本和区域适用性。
- **AIS 服务端账本**：验单、幂等到账、冻结/结算、退款冲正和对账。
- **iOS 客户端**：展示 StoreKit 价格与后台积分规则，发起购买和提交交易；不决定到账积分。

Apple 依据：

- [StoreKit](https://developer.apple.com/storekit/)
- [Consumable product](https://developer.apple.com/documentation/storekit/product/producttype/consumable)
- [Choosing a StoreKit API](https://developer.apple.com/documentation/storekit/choosing-a-storekit-api-for-in-app-purchases)
- [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)
- [App Review Guidelines 3.1.1](https://developer.apple.com/app-store/review/guidelines/)

## 2. 当前后台收费基线

以下数据来自 `2026-07-24` 后台“分地区充值价格”配置截图，只作为接入基线；运行时必须读取后台，不能硬编码进 App。

| 地区 | 基础套餐 | 最低充值 | 自定义换算 | 注册赠送 | 首充赠送 |
| --- | --- | --- | --- | --- | --- |
| 中国大陆/CNY | `¥10 = 1000 点` | `¥2` | `100 点/元` | `300 点` | 首次充值达到 `¥10` 赠送 `200 点` |
| 美国及默认/USD | `$4.99 = 1000 点` | `$4.99` | `100 点/美元` | `0 点` | 首次充值达到 `$10` 赠送 `200 点` |

后台还维护多档优惠套餐与折扣，两个地区当前限时促销均未开启。iOS 不支持 Web 的自定义充值金额，只把后台固定套餐映射为 StoreKit 商品。

注意：

- 后台的 CNY/USD 金额不能直接作为 iOS 成交价格。
- iOS 显示 `Product.displayPrice`，用户实际支付由 storefront 对应的 App Store 价格决定。
- Apple 佣金影响平台净收入，不减少用户已展示的积分。

## 3. 双 App 后台档位模型

AIS 与 PixaRivo 共用充值金额、积分、首充和促销规则，但 StoreKit 商品身份必须按 App 隔离。`AisRechargePackageOptions` 保留 `Amount`、`Points`、`PackageKey` 等公共档位字段，并通过 `StoreKitProducts` 为每个 iOS App 保存独立映射。

| 层级 | 字段 | 说明 |
| --- | --- | --- |
| App | `AppCode` | `ais` 或 `pixarivo` |
| App | `BundleId` | 签名交易必须匹配的 Bundle ID |
| App | `Enabled` | App 级售卖总开关 |
| App | `AllowedRegions` | App 级 storefront 区域门禁 |
| 档位 | `PackageKey` | 跨端稳定档位键 |
| 映射 | `AppleProductId` | 当前 App 在 App Store Connect 中的 Product ID |
| 映射 | `Enabled` | 当前 App 的当前档位是否可售 |
| 映射 | `Regions` | 当前商品允许的区域 |
| 映射 | `Sort` | 客户端展示顺序 |
| 映射 | `RuleVersion` | 验单时必须匹配的积分规则版本 |

App 级开关和档位级开关必须同时开启。旧版顶层 `AppleProductId`、`IosEnabled` 等字段只作为 PixaRivo 存量配置兼容入口；新代码读取和验单以 `StoreKitProducts` 为准。后台保存时同时校验 `AppCode`、Bundle ID、Product ID、区域、档位键和规则版本，禁止两个 App 误用同一商品身份。

当前 App 配置：

| AppCode | Bundle ID | 消耗型商品 |
| --- | --- | --- |
| `ais` | `com.wekarepartners.studio` | CN/US 各 3 档 |
| `pixarivo` | `com.wekarepartners.pixarivo` | CN/US 各 3 档 |

## 4. Product ID 规范

两款 App 的格式分别为：

```text
com.wekarepartners.studio.points.<region>.<package>.v1
com.wekarepartners.pixarivo.points.<region>.<package>.v1
```

当前商品后缀统一为：

```text
points.cn.starter.v1
points.cn.plus.v1
points.cn.pro.v1
points.us.starter.v1
points.us.plus.v1
points.us.pro.v1
```

截至 `2026-08-24`，AIS 六个消耗型商品均为“可供审核”，PixaRivo 六个消耗型商品均为“已批准”。后台映射必须与这些 Product ID 完全一致。

规则：

- 不把金额、币种或积分数写入 Product ID。
- Product ID 创建后不可编辑且删除后不能复用，因此必须使用稳定档位键。
- 同一 Product ID 不应静默改变基础积分。确需调整基础积分时创建新 `PackageKey` 和 Product ID，旧商品停止新购但保留历史验单。
- 促销赠送和首充赠送可通过有版本的后台规则变化，不改变 Apple 商品身份。

Apple 依据：[In-App Purchase information](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/)。

## 5. 商品展示合并

购买页加载流程：

1. AIS 客户端调用 `/api/ais/account/membership-progress?appCode=ais` 获取当前账号、区域和 AIS 专属推荐档位；PixaRivo 使用 `appCode=pixarivo`。
2. 用返回的 Product ID 调用 `Product.products(for:)`。
3. 以 Product ID 取两边交集。
4. 过滤后台未启用、Apple 未返回、区域不匹配或规则失效的商品。
5. 使用 StoreKit 的名称/价格，加上后台的基础积分和赠送明细展示。
6. 对配置缺失记录诊断事件，但不向用户展示不可购买的档位。

展示示例：

```text
1,000 点
$4.99
首次充值再赠 200 点
积分永久有效
```

禁止：

- 用后台金额替代 StoreKit 价格；
- 按价格计算积分；
- 展示未从 StoreKit 获取到的商品；
- 让用户输入自定义金额；
- 用折扣文案暗示 Apple 未配置的划线价。

## 6. 购买状态机

客户端状态：

`idle → loadingProducts → ready → purchasing → pending/verifying → credited → failed/cancelled`

流程：

1. 用户选择商品并查看最终积分明细。
2. 调用 `product.purchase()`。
3. `.userCancelled`：结束，不创建失败订单。
4. `.pending`：展示“等待 Apple/家长批准”，保留监听。
5. `.success(.verified(transaction))`：把签名交易提交 AIS 服务端。
6. 服务端通过 Apple 信息验证交易、匹配商品与历史规则、幂等入账。
7. 客户端收到到账快照后刷新余额，再调用 `transaction.finish()`。
8. 若服务端暂不可达，不 finish；后台重试并在下次启动继续同步。
9. 未验证交易不入账，记录安全事件并提示稍后重试。

`Transaction.updates` 必须在 App 生命周期内持续监听，处理待处理完成和跨设备交易。

## 7. 服务端验单

服务端不能只信任客户端 `verificationResult`。验单至少校验：

- JWS 签名与 Apple 证书链；
- `appCode` 与 bundle ID 的组合；
- environment；
- product ID；
- transaction ID / original transaction ID；
- purchase date、revocation date 和 storefront；
- 商品类型为预期 consumable；
- 当前用户与服务端订单/应用账号 token 的关联；
- 历史规则版本；
- 是否已处理。

客户端购买时必须传入服务端生成的 StoreKit `appAccountToken`，服务端以该不可逆 UUID 绑定 AIS 用户，不直接暴露雪花用户 ID。验单请求还必须携带当前 App 的 `appCode`、`PackageKey` 和 `RuleVersion`；服务端以签名交易中的 Bundle ID 为最终边界，不能只信任客户端参数。

幂等唯一键至少包含：

- `environment + transactionId`；
- 保留 `originalTransactionId` 用于链路追踪；
- 服务端业务订单 ID；
- Apple notification UUID。

## 8. 到账规则

服务端根据交易 `productId + storefront + purchaseDate` 查找历史有效规则，计算：

```text
TotalPoints =
  BasePoints
  + FirstRechargeBonusPoints
  + PromotionBonusPoints
```

并保存不可变快照：

- Product ID、PackageKey、RuleVersion；
- Apple storefront、currency、price（能从可信 Apple 数据获取时）；
- BasePoints；
- FirstRechargeBonusPoints；
- PromotionBonusPoints；
- TotalPoints；
- transactionId、originalTransactionId、purchaseDate；
- 入账流水 ID 和处理时间。

注册赠送在注册链路发放，不在 StoreKit 交易中再次发放。

首充规则：

- 以账户所有渠道的首次成功充值为准；
- Web 与 iOS 并发时由服务端原子占用；
- 失败、取消和待处理不占用首充；
- 退款后是否恢复首充资格必须由运营规则明确，默认不自动恢复。

## 9. 积分有效期和消费

- Apple IAP 购买的积分属于永久充值积分，不设置过期时间。
- 赠送积分是否有期限必须在购买前明确；首版建议同一笔 IAP 的赠送积分也不设置短期过期，减少审核和用户理解风险。
- 任务仍使用现有“报价 → 冻结 → 成功结算/失败退回”账务模型。
- iOS 购买和 Web 购买可以进入同一账号账本并跨端消费，但 iOS 不宣传或引导外部购买。

## 10. 退款、撤销与争议

接入 App Store Server Notifications V2 和 App Store Server API：

- 验证 `signedPayload`；
- 幂等记录通知；
- 对退款或撤销定位原交易和积分流水；
- 未消费余额优先扣回；
- 已消费导致余额不足时进入负余额/受限状态或风险流程，不能删除历史流水；
- 禁止简单修改余额而不产生冲正流水；
- 用户看到退款处理状态和客服联系入口。

具体通知类型在接入时按 consumable 当前可用事件核对 Apple 文档，不能照搬订阅通知逻辑。

## 11. 恢复购买的说明

消耗型商品不存在传统“恢复已消费权益”的用户体验。首版“同步购买”入口的含义是：

- 重新扫描当前设备未 finish 的交易；
- 向服务端同步未成功入账的已验证交易；
- 查询服务端 Apple 订单；
- 不重复发放已经幂等处理的积分。

界面文案使用“同步购买记录”，不要承诺像非消耗型商品一样恢复已花完积分。

## 12. 对账

每日对账至少关联：

1. Apple 交易；
2. AIS StoreKit 订单；
3. AIS 积分入账流水；
4. 后续退款/撤销冲正；
5. 用户当前余额变化。

告警场景：

- Apple 有交易，AIS 无订单；
- AIS 已入账，缺少有效 Apple 交易；
- 同一 transaction 多个用户；
- 商品/区域/规则版本不匹配；
- 退款后未冲正；
- 订单积分与流水不一致；
- App Store 商品下架但后台仍启用。

## 13. 测试矩阵

- Xcode StoreKit Configuration：商品加载、成功、取消、pending、未验证、断网。
- Sandbox：真实 Apple 账号购买、重复回调、跨设备和价格本地化。
- TestFlight：生产签名环境、服务端通知和 App Review 测试账号。
- Web/iOS 并发首充。
- 购买成功后立即杀进程、断网、服务端超时、重复启动。
- 商品在后台启用但 Apple 下架，或 Apple 有商品但后台禁用。
- 规则在购买前后更新，按 `purchaseDate` 选择正确历史版本。
- 退款前积分未使用、部分使用和全部使用。

## 14. 上线门禁

- App Store Connect 商品元数据和审核截图齐全。
- 所有可售商品都能从 StoreKit 拉取并和后台档位匹配。
- 验单、幂等、通知 V2、退款冲正和对账通过测试。
- App 内不存在外部支付入口和 Apple Pay 误用。
- 购买页清晰展示本地价格、基础积分、赠送积分、有效期和客服。
- 新 API、管理端和 iOS 构建完成发布后才开启对应 App 的售卖总开关；禁止“新配置 + 旧服务”混用。
- AIS 与 PixaRivo 分别探测 capabilities，确认 `storeKitEnabled`、开放区域和商品列表互不串用。
- 清洁安装和从上一版本更新两种路径都要在 iPad 上打开 Buy Points；加载失败或无商品时必须显示说明与重试入口，不能出现空白页面。

## 15. 与自动续费订阅的边界

| 事项 | 消耗型积分充值 | 自动续费订阅 |
| --- | --- | --- |
| StoreKit 类型 | Consumable | Auto-Renewable Subscription |
| 用户动作 | 单次主动购买 | 按周期自动续费 |
| 积分有效期 | 永久有效 | 当前订阅周期有效，到期清零 |
| 会员等级 | 按累计实际充值金额形成长期等级 | 有效订阅期间授予临时等级 |
| 购买恢复 | 同步未完成交易和服务端订单 | 恢复当前有效订阅状态 |
| 促销来源 | 后台积分赠送规则或 Apple 对应 IAP 能力 | Apple introductory、promotional 和 offer code |
| Product ID | `com.wekarepartners.studio.points.<区域>.<档位>` | `com.wekarepartners.studio.subscription.<套餐>.monthly` |

共同规则：

- 客户端只展示 StoreKit 本地价格，不决定到账积分或会员等级。
- 服务端按 Apple 交易、storefront 和历史规则验单并幂等入账。
- 用户消费时先使用即将到期的订阅点数，再使用永久积分。
- 任务冻结、结算和退回必须保留原积分来源，不能把过期订阅点数转换为永久积分。
- iOS 内不得展示或引导 H5、微信、支付宝、Stripe、PayPal、代充或 Apple Pay。
