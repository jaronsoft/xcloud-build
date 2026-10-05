# App Store Connect 创建与发布

App Store 产品页的简体中文、英语（美国）文案及审核备注模板统一维护在 [04 App Store 多语言元数据模板](04%20App%20Store%20多语言元数据模板.md)。

## 1. 创建前：注册 App ID

先进入 Apple Developer 的 **Certificates, Identifiers & Profiles → Identifiers**：

1. 点击 `+`，选择 `App IDs`。
2. 类型选择 `App`。
3. Description 填写 `AIK Enterprise Knowledge`。
4. Bundle ID 类型选择 `Explicit`。
5. Bundle ID 填写 `com.wekarepartners.aik`。
6. 已启用 `Associated Domains`，暂不启用 `Sign in with Apple`、`In-App Purchase` 或 `Push Notifications`。
7. 确认注册。

Bundle ID 必须与 Xcode 的 `PRODUCT_BUNDLE_IDENTIFIER` 完全一致，包括大小写和标点。

## 2. “新建 App”逐字段填写

在 App Store Connect 的 **App → + → 新建 App** 中填写：

| 字段 | 填写值 | 说明 |
| --- | --- | --- |
| 平台 | 仅勾选 `iOS` | 当前工程不发布 macOS、tvOS 或 visionOS |
| 名称 | `AIK 企业知识库` | 最多 30 个字符；若已被占用，使用 `AIK 企业智能知识库` |
| 主要语言 | `简体中文` | 后续仍可添加英文商店本地化 |
| 套装 ID | `com.wekarepartners.aik` | 从已注册的 Explicit App ID 下拉选择 |
| SKU | `AIK-IOS-20260727` | 内部唯一标识，用户不可见，创建后不可修改 |
| 用户访问权限 | `完全访问权限` | 允许 App Store Connect 团队中的全部用户访问此 App |

点击“创建”前，再次核对名称、Bundle ID 和 SKU。特别注意：SKU 创建后不可修改；如填错只能重新创建 App 记录。

Apple 官方字段说明：

- [新建 App 记录](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [App 信息字段与约束](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)

## 3. Xcode 归档前配置

在 `AIK` Target 的 Signing & Capabilities 中确认：

- Team：`R3622MSZJ7`
- Bundle Identifier：`com.wekarepartners.aik`
- Version：`1.0.0`
- Build：使用从 `100` 开始的递增整数；本地工程默认值为 `100`，正式上传时必须满足 App Store Connect 对版本内 Build 唯一性和递增性的校验
- Deployment Target：iOS 17.0
- Supported Destinations：仅 iPhone
- URL Scheme：`aik`
- 麦克风用途说明存在且与实际语音问答功能一致
- 包含 `applinks:ai.jaronsoft.com` Associated Domains entitlement，不包含 Push、Apple 登录或 IAP entitlement

首版使用 HTTPS 且无非豁免加密实现，`ITSAppUsesNonExemptEncryption` 为 `false`。正式上传使用 Apple 当前接受的正式版 Xcode 与 SDK；开发阶段的 beta Xcode 构建通过不等于可提交审核。

## 4. 商店资料准备

### 4.1 隐私政策与 App Privacy

- 隐私政策 URL：`https://ai.jaronsoft.com/privacy/`；英语页面：`https://ai.jaronsoft.com/privacy/?lang=en-US`。
- App Privacy 选择“不跟踪（No）”。数据均关联到用户、仅用于“App 功能（App Functionality）”：`User ID`（账号标识）、`Other User Content`（问答、反馈与会话内容）、`Audio Data`（用户主动发起语音提问时的录音）。
- 不申报广告、营销、跨 App/网站跟踪或出售数据。网页政策、`PrivacyInfo.xcprivacy`、实际网络请求与本表必须在每次提交前复核一致。
- 隐私咨询以及经核实的访问、更正、删除请求：`ais@get-free.net`。AIK 当前没有公共自助账号或数据删除入口；请求按照企业空间管理要求、必要安全审查与适用法律处理。

发布前准备：

- 简体中文名称、副标题、描述、关键词和支持 URL；
- 隐私政策 URL、客服/支持 URL；
- iPhone 要求尺寸的真实应用截图；
- App 图标；
- 年龄分级问卷；
- App Privacy：按上节的 URL 和数据类型完成保存；
- 出口合规问卷；
- 审核账号及至少一个可访问测试知识空间；
- Review Notes：说明“登录后必须选择企业空间”、测试路径、语音按钮只在租户开启时出现，以及邀请访问方式。

审核账号不得写入代码、README、截图或公开仓库。测试租户应使用非敏感演示知识，不向审核人员开放真实企业数据。

## 5. 构建与上传检查表

- [ ] Debug 构建成功。
- [ ] `AIKTests` 全部通过。
- [ ] 真机验证账号登录、租户为空、租户切换和退出账号。
- [ ] 验证 token 失效、无权限、会员到期和网络中断提示。
- [ ] 验证激活码有效/失效、匿名验证码及 `aik://`。
- [ ] 验证最近会话、历史消息、新对话、清空历史和评价。
- [ ] 验证 SSE 分包、长回复、Markdown 链接/代码/图片。
- [ ] 在启用语音的租户验证首次授权、拒绝权限、短录音及识别后问答。
- [ ] iPhone 横竖屏、键盘、深色模式、Dynamic Type、VoiceOver、Reduce Motion 回归。
- [ ] 核对归档产物 Bundle ID、版本、构建号、最低系统和隐私清单。
- [ ] 使用 Organizer 上传并等待 App Store Connect 处理完成。
- [ ] TestFlight 安装后复测生产登录和只读聊天，不执行线上管理或结构变更。

## 6. 当前已知限制

- 生产 API 固定为 `https://app.jaronsoft.com/api`，线上接口暂不改动。
- 已为 `ai.jaronsoft.com` 配置 AASA 与 `Associated Domains`，支持 Universal Link；同时保留 `aik://`。
- 首版无注册、找回密码、Apple 登录、付费、推送、文档上传和知识库后台管理。

## 7. 首次 TestFlight 发布记录

### 发布结果

| 项目 | 结果 |
| --- | --- |
| 版本 | `1.0.0 (260727.1)` |
| Bundle ID | `com.wekarepartners.aik` |
| Team ID | `R3622MSZJ7` |
| Release Archive | `2026-07-27 17:36` 成功 |
| App Store Connect 上传 | `2026-07-27 17:38` 成功 |
| Xcode 返回状态 | `Uploaded package is processing`、`Upload succeeded` |
| 当前状态 | 等待 Apple 处理并出现在 TestFlight |

归档验证结果：

- `arm64`、最低 iOS `17.0`；
- `CFBundleShortVersionString = 1.0.0`；
- `CFBundleVersion = 260727.1`；
- Bundle ID、Team ID、麦克风用途说明和隐私清单均已核对；
- 使用 `Configuration/ExportOptions-TestFlight.plist` 自动分发签名并直接上传。

本次上传完成的是 TestFlight 构建交付，不代表构建已经可安装。Apple 处理完成后仍需：

- [ ] 确认构建在 App Store Connect 的 TestFlight 页面无合规警告。
- [ ] 添加内部测试员并确认安装成功。
- [ ] 使用真实测试账号验证加密登录和登录图形验证码。
- [ ] 验证租户列表为空、租户搜索、选择、切换与退出清理。
- [ ] 验证邀请链接、激活码、匿名验证码和 `aik://`。
- [ ] 验证历史会话、SSE 中断恢复、Markdown 图片、评价与清空历史。
- [ ] 在启用语音的租户验证麦克风授权、拒绝和语音问答。
- [ ] 完成 iPhone、深色模式、Dynamic Type、VoiceOver、Reduce Motion 和弱网回归。

`260727.1` 已被 App Store Connect 接收，后续不得复用。若在同一天继续上传，使用 `260727.2`；跨日期按 `yyMMdd.1` 重新开始当日序号。

## 8. 第二次 TestFlight 发布记录

### 发布内容

- 新增公开租户选择、系统账号、租户会员、邀请码、匿名和扫码访问入口；
- 支持 `https://ai.jaronsoft.com/<tenantId>/<code>` Universal Link 与 `aik://tenant/<tenantId>/<code>`；
- 修复用户问题中语言提示词泄露以及 Markdown、换行和 SSE 分包渲染；
- 聊天页统一使用租户 `AgentLogo`；
- 右上角菜单新增脱敏网络诊断、日志导出及缓存管理。

### 发布结果

| 项目 | 结果 |
| --- | --- |
| 版本 | `1.0.0 (260727.2)` |
| Bundle ID | `com.wekarepartners.aik` |
| Team ID | `R3622MSZJ7` |
| 自动化测试 | `2026-07-27 19:46`，20 项全部通过 |
| Release Archive | `2026-07-27 19:47` 成功 |
| App Store Connect 上传 | `2026-07-27 19:49` 成功 |
| Xcode 返回状态 | `Uploaded package is processing`、`Upload succeeded` |
| TestFlight 分组 | 已加入内部测试分组 `Developer`（1 名测试员、2 个构建） |

归档验证结果：

- `arm64`、最低 iOS `17.0`；
- `CFBundleShortVersionString = 1.0.0`；
- `CFBundleVersion = 260727.2`；
- Bundle ID 为 `com.wekarepartners.aik`；
- 包含 `applinks:ai.jaronsoft.com` Associated Domains entitlement；
- 使用 `Configuration/ExportOptions-TestFlight.plist` 自动分发签名并直接上传。

App Store Connect 于 `2026-07-27 19:52` 确认：

- 构建 `260727.2` 状态为 `Ready to Submit`，有效期剩余 90 天；
- 已关联内部测试分组 `Developer`；
- 分组当前包含 1 名内部测试员和 2 个构建，分组推送已生效。

`260727.2` 已被 App Store Connect 接收，后续不得复用。若在同一天继续上传，使用 `260727.3`；跨日期按 `yyMMdd.1` 重新开始当日序号。

## 9. 第三次 TestFlight 发布记录

### 发布内容

- 匿名租户访问时不再显示会员账号和邀请码入口，仅保留匿名验证码；
- 手机端空间列表使用智能体外部显示名称，并显示用户编号；
- 原生问答底部不再显示建议内容，改为显示首字响应耗时。

### 发布结果

| 项目 | 结果 |
| --- | --- |
| 版本 | `1.0.0 (260728.1)` |
| Bundle ID | `com.wekarepartners.aik` |
| Team ID | `R3622MSZJ7` |
| 自动化测试 | 发布前 20 项全部通过 |
| Release Archive | `2026-07-28 11:37` 成功 |
| App Store Connect 上传 | `2026-07-28 11:38` 成功 |
| Xcode 返回状态 | `Uploaded package is processing`、`Upload succeeded` |
| 当前状态 | Apple 正在处理 TestFlight 构建 |

归档验证结果：

- `CFBundleShortVersionString = 1.0.0`；
- `CFBundleVersion = 260728.1`；
- Bundle ID 为 `com.wekarepartners.aik`；
- 使用 `Configuration/ExportOptions-TestFlight.plist` 自动分发签名并直接上传。

`260728.1` 已被 App Store Connect 接收，后续不得复用。若在同一天继续上传，使用 `260728.2`；跨日期按 `yyMMdd.1` 重新开始当日序号。

## 10. 第四次 TestFlight 发布记录

### 发布内容

- 未登录或匿名会话缺少空间信息时，首页默认进入企业空间选择；
- 系统账号登录调整为用户主动触发的次级入口；
- 系统账号登录成功后自动进入第一个可用企业空间；
- 恢复系统账号会话时优先沿用上次选择的企业空间。

### 发布结果

| 项目 | 结果 |
| --- | --- |
| 版本 | `1.0.0 (260728.2)` |
| Bundle ID | `com.wekarepartners.aik` |
| Team ID | `R3622MSZJ7` |
| Debug 构建 | `2026-07-28 12:17` 成功 |
| 自动化测试 | `2026-07-28 12:17`，20 项全部通过 |
| Release Archive | `2026-07-28 12:18` 成功 |
| App Store Connect 上传 | `2026-07-28 12:20` 成功 |
| Xcode 返回状态 | `Uploaded package is processing`、`Upload succeeded` |
| 当前状态 | Apple 正在处理 TestFlight 构建 |

归档验证结果：

- `CFBundleShortVersionString = 1.0.0`；
- `CFBundleVersion = 260728.2`；
- Bundle ID 为 `com.wekarepartners.aik`；
- 使用 `Configuration/ExportOptions-TestFlight.plist` 自动分发签名并直接上传。

`260728.2` 已被 App Store Connect 接收，后续不得复用。若在同一天继续上传，使用 `260728.3`；跨日期按 `yyMMdd.1` 重新开始当日序号。
