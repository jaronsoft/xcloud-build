# PixaRivo iOS 文档中心

<!-- markdownlint-disable MD013 -->

> 更新时间：2026-09-30
>
> 适用范围：PixaRivo iOS App 开发与 App Store Connect

当前工程营销版本为 `1.2.12`，本地 `CURRENT_PROJECT_VERSION = 58`，仅支持
iPhone。`1.2.11 (Build 133)` 已发布，线上 Build 由发布流程自动生成。工程事实以
[iOS 工程说明](../README.md) 为准，版本更新
中英文内容与发布状态维护在 [`RELEASE_NOTES.md`](../RELEASE_NOTES.md)，其他四种语言维护在
[其他语言发布说明](../RELEASE_NOTES_OTHER_LANGUAGES.md)；送审进度统一维护在
[提交前清单](./PixaRivo-App-Store-Connect/06-截图脚本与提交清单.md)。

本目录只维护 PixaRivo iOS App 专属资料。官网、市场推广、宣传视频等非 iOS 文档统一从 [PixaRivo 产品文档中心](../../../../documents/PixaRivo/README.md) 进入。

## 快速入口

| 分类 | 入口 | 主要内容 |
| --- | --- | --- |
| iOS App 开发 | [PixaRivo iOS 工程说明](../README.md) | 产品范围、工程配置、图片缓存、网络调试、积分支付、接口、账户资料与构建方式 |
| 版本记录 | [PixaRivo Release Notes](../RELEASE_NOTES.md) | 中英文推广文本、待发布与历史版本更新内容 |
| 其他语言版本记录 | [其他语言发布说明](../RELEASE_NOTES_OTHER_LANGUAGES.md) | 日语、西班牙语、巴西葡萄牙语和繁体中文推广文本与更新内容 |
| 早期版本时间线 | [1.1 时间线](../ReleaseNotes/1.1.md) | 按主版本和次版本归档的历史中英文更新说明 |
| App Store 版本时间 | [版本时间核对](./PixaRivo-App-Store-Connect/08-版本时间核对.md) | 按 App Store Connect 分发历史核对审核与可分发时间 |
| App Store Connect | [PixaRivo App Store Connect 资料包](./PixaRivo-App-Store-Connect/README.md) | 应用记录、商店文案、隐私披露、年龄分级、审核资料、截图与合规清单 |
| 产品与推广资料 | [PixaRivo 产品文档中心](../../../../documents/PixaRivo/README.md) | 官网、宣传视频、X 推广文案及跨端产品资料 |

## 按任务查找

| 要完成的任务 | 建议阅读 |
| --- | --- |
| 了解 PixaRivo 的产品能力与 App 工程现状 | [iOS 工程说明](../README.md) |
| 查看版本内容与发布状态 | [PixaRivo Release Notes](../RELEASE_NOTES.md) |
| 判断送审完成度和下一步优先级 | [截图脚本与提交清单](./PixaRivo-App-Store-Connect/06-截图脚本与提交清单.md) |
| 在 App Store Connect 新建应用 | [应用记录与基础设置](./PixaRivo-App-Store-Connect/01-应用记录与基础设置.md) |
| 填写中英文商店元数据 | [中英文商店文案](./PixaRivo-App-Store-Connect/02-中英文商店文案.md) |
| 填写 App Privacy 或核对权限 | [隐私问卷与数据披露](./PixaRivo-App-Store-Connect/03-隐私问卷与数据披露.md) |
| 填写年龄分级、内容版权或出口合规 | [年龄分级与合规问卷](./PixaRivo-App-Store-Connect/04-年龄分级与合规问卷.md) |
| 准备审核账号和 Review Notes | [审核信息与审核备注](./PixaRivo-App-Store-Connect/05-审核信息与审核备注.md) |
| 制作截图或执行送审前检查 | [截图脚本与提交清单](./PixaRivo-App-Store-Connect/06-截图脚本与提交清单.md) |
| 填写辅助功能、DSA 或地区合规资料 | [辅助功能与账户级合规](./PixaRivo-App-Store-Connect/07-辅助功能与账户级合规.md) |
| 核对版本审核与发布日期 | [版本时间核对](./PixaRivo-App-Store-Connect/08-版本时间核对.md) |

## 文档维护约定

- 产品能力、接口与工程事实以当前代码和 [iOS 工程说明](../README.md) 为依据。
- 已完成能力直接整合到工程说明，不再单独维护完成记录；未闭环事项写入对应专项清单，不再新增综合状态文档。
- 工程版本以 `PixaRivo.xcodeproj` 为准，中英文更新内容以 [`RELEASE_NOTES.md`](../RELEASE_NOTES.md) 为准，其他四种语言以 [其他语言发布说明](../RELEASE_NOTES_OTHER_LANGUAGES.md) 为准，送审状态以 [提交前清单](./PixaRivo-App-Store-Connect/06-截图脚本与提交清单.md) 为准，避免在多个文件重复维护。
- 官网、推广和其他非 iOS 资料只在 `documents/PixaRivo/` 维护，本目录不保存副本。
- App 功能、数据处理、权限或商业模式发生变化时，应同步复核 App Store Connect 的文案、隐私、分级、审核和截图资料。
- 新增分类时使用独立目录，并在分类目录中提供 `README.md`；新增文档后同步更新分类索引和本页“按任务查找”。
- 文档中的账号、密码、Token、证书和密钥一律使用占位符，不得提交真实敏感信息。

## 与 AIS 的关系

- PixaRivo 是独立 App，不是 AIS 原生端的营销名称；Bundle ID、StoreKit 商品、订阅组、App Store Connect 资料和版本记录分别维护。
- 两个 App 共用 AIS 账号、积分、模板、任务、通知和媒体交付等服务端能力，因此共享接口变化需同时评估两个客户端。
- AIS 完整产品包含自由生图、图片编辑、视频和项目 Agent；PixaRivo 当前只提供模板化图片与文字合成。

## 相关源码

```text
App/IOS/PixaRivo/                    PixaRivo iOS 工程
H5/PixaRivo/                         PixaRivo 官网源码与部署配置
App/IOS/PixaRivo/Documents/          PixaRivo iOS 与 App Store Connect 文档
documents/PixaRivo/                  PixaRivo 产品、官网与推广文档
```
