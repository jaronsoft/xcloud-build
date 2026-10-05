# PixaRivo App Store Connect 资料包

<!-- markdownlint-disable MD013 -->

> 更新时间：2026-09-30
>
> 当前工程营销版本：`1.2.12`；`1.2.11 (Build 133)` 已发布
>
> Bundle ID：`com.wekarepartners.pixarivo`
>
> 开发者：`WeKare Partners LLC`

本目录用于准备 PixaRivo 在 App Store Connect、TestFlight 和正式送审时需要填写的中英文资料。文案以 `App/IOS/PixaRivo` 当前代码为准，不包含 AIS 主应用的自由提示词创作、视频和项目 Agent；PixaRivo 已支持 Apple 登录、APNs、App Store 消耗型积分和 Plus/Pro 自动续费订阅。

PixaRivo 独立官网已上线，App Store Connect 的 Marketing URL 使用 `https://pixarivo.get-free.net/`。官网产品、部署与 SEO 维护说明见 [PixaRivo 官网文档](../../../../../documents/PixaRivo/PixaRivo-官网/README.md)。

## 当前发布基准

| 项目 | 记录 |
| --- | --- |
| 工程配置 | `MARKETING_VERSION = 1.2.12`，本地 `CURRENT_PROJECT_VERSION = 58` |
| 最近已发布版本 | `1.2.11 (Build 133)` |
| 审核中版本 | 无 |
| 历史已发布版本 | `1.2.6 (Build 112)` |
| 待发布版本 | `1.2.12 (Build 待自动生成)` |
| 更新说明 | 见 [`RELEASE_NOTES.md`](../../RELEASE_NOTES.md) |
| 送审状态 | 见 [截图脚本与提交清单](./06-截图脚本与提交清单.md) |

App Store Connect 中已记录的历史状态见 [版本时间核对](./08-版本时间核对.md)。1.2.11 (Build 133) 已发布。线上发布流程自动生成 Build；本地 `CURRENT_PROJECT_VERSION = 58` 仅为工程默认值，不代表下一次线上编号。

## 当前版本准备

| 项目 | 记录 |
| --- | --- |
| 版本 | `1.2.12 (Build 待自动生成)` |
| 状态 | 待发布 |
| 更新说明 | 见 [`RELEASE_NOTES.md`](../../RELEASE_NOTES.md) |

`1.2.11 (Build 133)` 已发布；`1.2.12` 已设为当前工程营销版本，线上 Build 由发布流程自动生成。

版本上传完成后，应将实际时间、构建环境和上传结果补充到本文件，并继续递增后续 Build。

## 官网与合规页面状态

以下页面已于 2026-08-12 部署并完成未登录访问、中英文切换和 HTTPS 检查：

| 用途 | 简体中文 | English (U.S.) |
| --- | --- | --- |
| 官网 / Marketing URL | `https://pixarivo.get-free.net/` | `https://pixarivo.get-free.net/` |
| 隐私政策 | `https://pixarivo.get-free.net/privacy/?lang=zh-CN` | `https://pixarivo.get-free.net/privacy/?lang=en-US` |
| 用户隐私选择 / 删除请求 | `https://pixarivo.get-free.net/privacy/?lang=zh-CN#rights` | `https://pixarivo.get-free.net/privacy/?lang=en-US#rights` |
| 服务条款 | `https://pixarivo.get-free.net/terms/?lang=zh-CN` | `https://pixarivo.get-free.net/terms/?lang=en-US` |
| 素材上传与合规提示 | `https://pixarivo.get-free.net/upload-compliance/?lang=zh-CN` | `https://pixarivo.get-free.net/upload-compliance/?lang=en-US` |
| 案例内容与知识产权声明 | `https://pixarivo.get-free.net/gallery-ip/?lang=zh-CN` | `https://pixarivo.get-free.net/gallery-ip/?lang=en-US` |
| 技术支持 | `https://pixarivo.get-free.net/support/?lang=zh-CN` | `https://pixarivo.get-free.net/support/?lang=en-US` |

公开支持与隐私联系邮箱统一为 `ais@get-free.net`。页面可直接用于 App Store Connect 元数据；App 内已接入全部合规文件。登录后，当前协议集合未确认的用户必须停留至少 3 秒并滚动到底部后才能同意继续；同意版本和时间由服务端记录。

## 文件索引

| 文件 | 用途 |
| --- | --- |
| [01-应用记录与基础设置.md](./01-应用记录与基础设置.md) | 新建 App、类别、价格、地区、版权、版本和 URL |
| [02-中英文商店文案.md](./02-中英文商店文案.md) | 名称、副标题、推广文本、描述、关键词和版本更新说明 |
| [03-隐私问卷与数据披露.md](./03-隐私问卷与数据披露.md) | App Privacy、权限、隐私政策和数据类型逐项填写 |
| [04-年龄分级与合规问卷.md](./04-年龄分级与合规问卷.md) | 年龄分级、内容权利、加密、广告标识符和出口合规 |
| [05-审核信息与审核备注.md](./05-审核信息与审核备注.md) | 审核账号、审核步骤、联系方式及中英文 Review Notes |
| [06-截图脚本与提交清单.md](./06-截图脚本与提交清单.md) | iPhone 截图脚本、规格和最终送审检查 |
| [07-辅助功能与账户级合规.md](./07-辅助功能与账户级合规.md) | Accessibility Nutrition Labels、DSA、韩国和主体级信息 |
| [08-版本时间核对.md](./08-版本时间核对.md) | App Store Connect 审核与可分发时间核对 |

## 当前工程事实

- SwiftUI、Swift 6，最低 iOS 17，当前仅支持 iPhone。
- 支持简体中文和英语，可在 App 内即时切换或选择跟随系统，无需重新启动。
- 静态 Launch Screen 后衔接约 1.1 秒的本地 SwiftUI 品牌动效；开启系统“减少动态效果”时自动缩短为淡入淡出，不阻塞底层数据加载。
- 未登录用户可以浏览模板、模板详情和只读精选案例。
- 首页顶部共用 AIS 后台运营文案池，以本地缓存优先、每日静默刷新方式获取，并在每次进入首页时随机展示一组本地化文案。
- 首页精选卡片和模板详情优先显示服务端 `DescriptionZh / DescriptionEn`，并按当前语言自动回退。
- 支持邮箱验证码注册/登录、密码登录、Sign in with Apple 和已有账号绑定 Apple；当前 App 不提供找回密码或 App 内账号删除。
- 注册流程会处理昵称、邮箱、验证码、国家/地区，以及用户可选填的手机号和邀请码。
- 登录用户可以从系统照片选择器选择图片、编辑模板允许修改的文字、查看所需积分、提交合成任务并查看作品。
- 创作表单提供“允许添加平台宣传标识”和“允许推荐到公开案例库”选项；标识选项会参与本地核价，公开展示仍须平台审核。
- 首页、模板、案例、作品和账户相关页面在首次无内容加载时显示带说明的加载状态；已有内容刷新不清空页面，作品详情以非遮挡提示同步进度。
- 用户图片、模板文字、任务和作品会发送至 PixaRivo/AIS 服务端以完成核心功能。
- 当前 App 不含广告、Google/Facebook/微信等其他社交登录、定位、相机、麦克风或跨 App 跟踪；登录后可由用户选择开启账户、积分和作品状态推送，并始终可在 App 内消息中心查看历史通知。
- 诊断日志默认仅保存在设备中；入口只在 Debug 或 TestFlight 环境连续点击版本号 5 次后显示，并由用户主动导出。

## 填写前必须替换的内容

全文仅保留以下无法从仓库安全推断的占位符，提交前应统一替换：

- `[REVIEW_FIRST_NAME]`、`[REVIEW_LAST_NAME]`：Apple 可联系的审核联系人姓名；
- `[REVIEW_PHONE]`、`[REVIEW_EMAIL]`：审核联系人电话和邮箱；
- `[DEMO_EMAIL]`、`[DEMO_PASSWORD]`：长期有效的专用审核账号；
- `[SUBMITTED_VERSION]`、`[SUBMITTED_BUILD]`：本次在 App Store Connect 实际选中的版本与构建；
- App Store Connect Apple ID：`6800612526`；
- 当前工程营销版本为 `1.2.12`；`1.2.11 (Build 133)` 已发布。正式送审以自动流程生成并由 App Store Connect 实际处理的 Build 为准同步版本记录。
- `[DSA_ADDRESS]`、`[DSA_PHONE]`、`[DSA_EMAIL]`：欧盟 DSA trader 公示并由 Apple 验证的公司联系信息；
- `[KOREA_CONTACT_*]`：如在韩国销售，由组织开发者提交的当地法规联系信息。

审核账号必须使用非敏感演示数据并预置足够积分，不能写入源代码、截图、公开 README 或 Git 提交历史。只在 App Store Connect 的“App 审核信息”中填写。

## 送审状态

送审完成度、阻断项和提交后动作统一维护在 [截图脚本与提交清单](./06-截图脚本与提交清单.md)，本页不再重复记录状态，避免已完成事项在多个文件中分别更新。

## Apple 官方依据

- [App 信息字段](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
- [版本信息字段](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [管理 App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [年龄分级值和定义](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
