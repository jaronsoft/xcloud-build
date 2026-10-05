# AIS iOS 开发文档索引

本目录集中维护 AIS iOS 产品的总计划、工程、接口、支付、订阅、合规、发行和 App Store 文案，直接指导 `App/IOS/AIS/` 的实际开发。AIS 跨端、服务端和业务级文档继续归档在 `documents/AIS/`。

AIS 原生 App 使用 Bundle ID `com.wekarepartners.studio`，覆盖完整视觉生产能力。PixaRivo 是独立的仅 iPhone 模板合成 App，使用 Bundle ID `com.wekarepartners.pixarivo`；两个 App 共用部分 AIS 服务端能力，但 StoreKit 商品、订阅组、发布记录和审核资料必须分别维护。PixaRivo 文档见 [PixaRivo 文档中心](../../PixaRivo/Documents/README.md)。

## 状态说明

- `📘 基线规范`：长期有效的产品或工程约束，不按单次开发任务关闭。
- `🚧 部分完成`：已有部分能力落地，仍有明确开发或交付事项。
- `🔄 持续维护`：随开发、验证和发布进度持续更新。
- `✅ 已完成`：本文档约定的功能代码已经落地；文档中注明的真机、生产或 TestFlight 回归仍需按发布批次执行。
- `📝 TODO`：已完成方案设计，尚未开始实现。

## 文档清单

| 编号 | 状态 | 文档 | 说明 |
| --- | --- | --- | --- |
| 00 | 🚧 部分完成 | [AIS iOS 原生端与全球发行计划](./00%20AIS%20iOS原生端与全球发行计划.md) | iOS 产品边界、主体、全球发行、StoreKit、区域和阶段性交付总计划。 |
| 01 | 📘 基线规范 | [产品范围与信息架构](./01%20产品范围与信息架构.md) | 产品定位、用户路径、首版页面、聊天边界和延后范围。 |
| 02 | 📘 基线规范 | [工程架构与目录规范](./02%20工程架构与目录规范.md) | SwiftUI 工程结构、依赖方向、状态管理、环境、存储和通知架构。 |
| 03 | 🚧 部分完成 | [API 与区域数据契约](./03%20API与区域数据契约.md) | capabilities、Apple 登录、双 App StoreKit 和主要业务接口已落地；AIS 客户端 APNs、统一错误码和异步删除接口仍待完成。 |
| 04 | 🚧 部分完成 | [StoreKit 积分与账务](./04%20StoreKit积分与账务.md) | 双 App 商品隔离、客户端购买、服务端 JWS 验签、幂等到账、订阅周期、Notifications V2 和退款冲正代码已完成；AIS 商品发布、Sandbox/TestFlight、主动查询和每日对账尚未闭环。 |
| 05 | 🚧 部分完成 | [Apple 能力、隐私与审核](./05%20Apple能力隐私与审核.md) | Apple 登录、账号删除第一版和隐私清单已接入；推送、内容安全、隐私审计和送审材料仍待完成。 |
| 06 | 🚧 部分完成 | [测试、发布与中国区发行](./06%20测试发布与中国区发行.md) | Archive 与多次 App Store Connect 上传已完成；内部/外部 TestFlight、海外发布门禁和中国区前置事项未闭环。 |
| 07 | 🔄 持续维护 | [开发任务清单](./07%20开发任务清单.md) | iOS 总任务来源；包含已完成、部分完成和未开始事项。 |
| 08 | 🔄 持续维护 | [首版实施记录](./08%20首版实施记录.md) | 持续记录工程、接口、构建、TestFlight 进度和送审阻塞项。 |
| 09 | ✅ 已完成 | [iOS 体验优化与 H5 功能对齐计划](./09%20iOS体验优化与H5功能对齐计划.md) | 视觉、缓存、任务创作闭环、登录与账户相关代码已落地，后续随 TestFlight 批次回归。 |
| 10 | ✅ 已完成 | [iOS 登录、案例、分享与协议修复实施](./10%20iOS登录案例分享与协议修复实施.md) | 独立认证、案例、分享、Universal Link 和应用内协议代码已完成，保留生产与真机验收。 |
| 11 | ✅ 已完成 | [腾讯云图片缩略图接入实施](./11%20腾讯云图片缩略图接入实施.md) | 动态图片规格、URL 生成和缓存接入已完成，保留真机网络与内存回归。 |
| 12 | ✅ 已完成 | [iPad 创作、原生案例与付费策划实施](./12%20iPad创作原生案例与付费策划实施.md) | iPad 自适应、原生案例、模型权限、付费识图和生成前策划代码已完成，保留真机回归。 |
| 13 | ✅ 已完成 | [产品智造配置与全屏图片浏览实施](./13%20产品智造配置与全屏图片浏览实施.md) | 产品智造配置和共享全屏图片浏览已完成并通过专项测试，保留 TestFlight 回归。 |
| 14 | ✅ 已完成 | [iOS 任务详情优化开发计划](./14%20iOS任务详情优化开发计划.md) | 任务成果预览关闭、操作区布局、分享案例、完整任务编号和成果规格已完成并上传 TestFlight，保留真机交互回归。 |
| 15 | ✅ 已完成 | [iOS 任务列表、创作选项与缓存诊断优化](./15%20iOS任务列表创作选项与缓存诊断优化.md) | 任务卡片、取消错误、创作选择器、原图预览、分模块缓存与诊断日志代码已完成，保留真机及 TestFlight 回归。 |
| 16 | ✅ 已完成 | [iOS 自适应图片交付与诊断查看器实施](./16%20iOS自适应图片交付与诊断查看器实施.md) | 图片按实际显示尺寸选择 CDN 档位，网络与图片缓存查看器已拆分，“我的”页面已重排，保留真机及 TestFlight 回归。 |
| 17 | ✅ 已完成 | [iOS 任务列表轮询与服务端缓存优化](./17%20iOS任务列表轮询与服务端缓存优化.md) | 空闲轮询降频、活动任务实时刷新、可选分页统计和 Redis 媒体快照缓存已完成，保留 TestFlight 与生产日志观察。 |
| 18 | ✅ 已完成 | [iOS 本地计价缓存与规格倍率优化](./18%20iOS本地计价缓存与规格倍率优化.md) | 产品与模板使用持久价格规则在本地即时算价，提交时由服务端复算并在规则变化后要求重新确认。 |
| 19 | ✅ 已完成 | [iOS 案例用户叠加修改预览实施](./19%20iOS案例用户叠加修改预览实施.md) | 公开案例完整展示来源资料，并将鼠标标记、文字和 LOGO 按原坐标合成到来源图。 |
| 20 | 📝 TODO | [iOS 合规支付与美国公司配合指引](./20%20iOS合规支付与美国公司配合指引.md) | 明确 IAP-only 合规方案、WeKare Partners 商务与财税配合、App Store Connect 操作、服务端账务边界和分阶段开发计划。 |
| 21 | 📝 TODO | [iOS 自动续费订阅与区域定价策略](./21%20iOS自动续费订阅与区域定价策略.md) | 明确中美四档月付、逐国人工定价、共用会员等级、订阅点数到期、首月七折和毛利门禁。 |
| 22 | ✅ 已完成 | [iOS 启动预加载与用户积分刷新实施](./22%20iOS启动预加载与用户积分刷新实施.md) | 启动预加载、用户快照、生成门禁和任务或充值后的积分刷新代码已完成。 |
| 23 | ✅ 已完成 | [Apple 登录生产配置与账号绑定实施](./23%20Apple登录生产配置与账号绑定实施.md) | 私钥文件挂载、原生登录、登录态绑定和 credential state 代码已完成，等待生产 API 与真机联调。 |
| 24 | 🔄 持续维护 | [App Store 发布文案（中英文）](./24%20App%20Store发布文案（中英文）.md) | AIS App Store Connect 的中英文名称、副标题、推广文本、关键词、长描述和上架核对清单。 |

## 未开发与未闭环事项

以下内容按当前文档记录汇总；详细任务状态以 [开发任务清单](./07%20开发任务清单.md) 为准。

### iOS 产品与体验

- 补齐 Camera、Files 素材选择和逐文件上传进度。
- 完成独立局部图片编辑工具、案例参数复用和 Skill 示例独立展示。
- 根据 capabilities 正式开放视频入口，并为任务状态接入 SignalR。
- 完成单个 Agent 成果继续修改和开放式越界话题验证。

### StoreKit 与账务

- 由 `WeKare Partners LLC` 完成 Paid Applications Agreement、W-9、公司银行账户、Apple 合规审查和责任人分工。
- 完成 WeKare Partners 与佳融公司的海外发行、数据处理和 IAP 净收入结算协议。
- PixaRivo 已独立维护其消耗型商品和 Plus/Pro 月付；AIS 继续完成自身 consumable 商品的本地化、审核提交与 Sandbox/TestFlight 验收，不复用 PixaRivo Product ID。
- 创建一个自动续费订阅组和 `starter / creator / pro / max` 四档月付商品。
- 完成中国、美国月度额度测算，以及其他目标 storefront 的逐国人工定价和毛利审批。
- 配置首个计费月约七折的 introductory offer，不启用免费试用、年付和 Billing Grace Period。
- 为 AIS App Store Connect 记录创建并安全交付 IAP Key，配置 Sandbox/Production App Store Server Notifications V2。
- 双 App iOS 商品映射、交易验证、交易同步和 Apple 订单代码已完成；继续完成生产发布与回归。
- Notifications V2 接收、JWS 验单、幂等到账、首充原子占用、退款冲正和订阅周期代码已完成；继续接入 App Store Server API 主动查询并完成生产验证和每日对账。
- 完成启动时未结束交易同步、消耗型积分“同步购买记录”、自动续费“恢复订阅”和 StoreKit Sandbox/TestFlight 验收。

### APNs、安全与审核

- 服务端 APNs 设备、通知和投递能力已完成，PixaRivo 客户端已接入；AIS App 继续完成设备注册、注销、通知偏好和通知深链。
- 完成输入/输出内容安全、举报、AI 第三方处理告知和生成内容标识。
- 审计权限用途、第三方 SDK 隐私清单、required-reason API 和 App Privacy。
- 准备年龄分级、出口合规、审核截图、长期审核账号、IAP 说明和 Review Notes。

### 生产联调与发行

- 完成独立生产 JWT、Redis Refresh Token 并发轮换，以及 Apple 登录生产 API 和真机联调；四节点 `.p8` 挂载、账号绑定与客户端 credential state 代码已完成。
- 完成 Universal Link、相册、弱网、分享卡片及 iPhone/iPad 真机回归。
- 完成内部与外部 TestFlight 的设备、语言、区域和弱网测试。
- 完成海外发布门禁，以及中国大陆 APP 备案、AI 应用登记、境内基础设施和运营协议。

## 当前结论

- Xcode 工程与 App Store Connect 已建立；当前仓库工程版本为 `1.2.6 (Build 18)`，包含 StoreKit storefront 区域对齐、商品目录分阶段重试、AIS/PixaRivo 双 App StoreKit 隔离及账户绑定修复。
- App Store 名称为 `AIS Visual Studio by WeKare`，Bundle ID 为 `com.wekarepartners.studio`，Team ID 为 `R3622MSZJ7`。
- 海外版可以先开发和 TestFlight，但首发不选择 China mainland storefront。
- 中国大陆发行需要佳融公司作为实际运营主体，另行完成 APP 备案、AI 应用登记、区域后端和内容安全验收。
- 用户充值不是 Apple Pay：数字积分采用 StoreKit 2 消耗型 In-App Purchase。
- 自动续费订阅已形成下一阶段方案，采用中美四档月付、逐国人工定价、地区独立额度和共用会员等级；当前尚未实施或在 App Store Connect 开放。
- 现有后台定价继续管理积分与赠送规则，App Store Connect 管理 iOS 实际价格与币种。
- 创作者收益和提现保持关闭，不进入首版开发。
- 模板、案例、任务和素材小图根据实际显示宽度与屏幕倍率选择 capabilities 下发的最小可用缩略图档位，列表最大 900px；详情使用 1200px，全屏预览与文件交付使用原图。图片缓存支持内存解码复用、磁盘去重、分模块统计，以及独立网络/图片缓存查看器和诊断导出。
- 模板分类、详情、动态字段、素材槽位、报价生成、快速创作动态属性、提示词优化、任务成果交付、项目 Agent、会员积分流水和邀请有礼已完成代码接入；AIS StoreKit 生产发布、Sandbox/TestFlight、每日对账、AIS 客户端 APNs 和送审材料仍未闭环。
- iOS 版本采用 `主版本.次版本.修订版本 (Build 递增整数)`，当前工程版本为 `1.2.6 (Build 18)`；Build 全局递增且不随日期或营销版本重置，下一次发行构建至少使用 `19`。
- `1.2.5 (17)` 于 `2026-09-03` 因 6.7 英寸截图过期、IAP 商品不可购买及 iPad 模板页持续加载被拒绝；`1.2.5 (18)` 已将模板目录首屏从 50 条缩小为 12 条并提供分页加载，等待 App Store Connect 商品、Paid Apps Agreement、当前版本截图及 Sandbox/TestFlight 购买闭环复核。
- `1.2.5 (11)` 于 `2026-08-24` 因 iPad Buy Points 页面无内容被 Guideline 2.1(a) 拒绝；`1.2.5 (12)` 已完成双 App 映射、AIS 购买链路和空状态修复，等待发布与重新提交。
- `1.2.5 (4)` 已于 `2026-08-13 22:51` 完成 Release Archive，并于 `22:53` 通过命令行上传 App Store Connect，返回 `Uploaded package is processing`、`Upload succeeded` 和 `Uploaded AIS`；当前等待 Apple 处理。
- `1.2.3 (260729.15.3)` 已于 `2026-07-29 12:59` 完成 Release Archive，并于 `13:04` 通过 Xcode Organizer 上传 App Store Connect，界面返回 `App upload complete`；当前等待 Apple 处理。
- `1.2.3 (260729.16.4)` 已于 `2026-07-29 14:16` 完成 Release Archive，并于 `14:19` 通过 Xcode Organizer 上传 App Store Connect，界面返回 `App upload complete`；当前等待 Apple 处理。
- `1.2.3 (260729.17.5)` 已于 `2026-07-29 16:51` 完成 Release Archive，并于 `16:55` 通过 Xcode Organizer 上传 App Store Connect，界面返回 `App upload complete`；当前等待 Apple 处理。
- `1.2.3 (260729.19.7)` 已于 `2026-07-29 21:45` 完成 Release Archive，并于 `21:51` 通过命令行上传 App Store Connect，返回 `Upload succeeded`；当前等待 Apple 处理。
- `1.2.3 (260731.24.2)` 已于 `2026-07-31 21:55` 完成 Release Archive，并于 `21:57` 通过命令行上传 App Store Connect，返回 `Upload succeeded`；当前等待 Apple 处理。配套腾讯云 H5 与 Cloudflare Workers 已完成生产发布，生产 API 的国际图片开关仍保持关闭。
- `1.2.3 (260806.26)` 已于 `2026-08-06 08:28` 完成 Release Archive，并于 `08:30` 通过命令行上传 App Store Connect，返回 `Upload succeeded`；当前等待 Apple 处理。
- 当前 TestFlight 基准已包含任务时间时区与元信息字号修复、媒体区域请求透传、响应与图片缓存按区隔离、同源图片代理区域头，以及混合媒体查看器、计价缓存、启动预加载、积分静默刷新和生成门禁。

## 维护规则

- 产品、主体、Bundle ID、支付或区域决策变化时，先更新本目录的 iOS 总计划，再同步相关专项文档和 `documents/AIS` 中受影响的跨端说明。
- 接口落地后，在相应章节把“待新增”改为真实路由、请求与响应字段。
- 每次完成可运行迭代后，同步更新“首版实施记录”和开发任务清单。
- 每次 App Store 提交前重新核对 Apple 官方要求，文档中的日期性要求不能替代当期规则。
