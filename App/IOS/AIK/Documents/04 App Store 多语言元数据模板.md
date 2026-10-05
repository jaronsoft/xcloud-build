# AIK App Store 多语言元数据模板

> 最后更新：2026-07-28
>
> 适用平台：App Store Connect / iOS
>
> 当前支持语言：简体中文、英语（美国）

## 1. 使用说明

App Store Connect 的产品页元数据需要按语言分别维护，不要在同一个字段中混排中英文。

首发及后续版本建议至少配置：

- 简体中文；
- 英语（美国）。

只有 App 内已经完整支持的语言才能添加到产品页。当前 AIK 支持简体中文和英文，未完成其他语言的界面、错误提示和审核路径验证前，不添加更多商店语言。

元数据位置：

- App 名称、副标题：App 信息；
- 推广文本、描述、关键词、技术支持网址、营销网址：对应 iOS App 版本页面；
- 审核账号、联系方式和审核备注：App 审核信息；
- 截图：对应版本的“预览和截屏”；
- 构建版本：对应版本的“构建版本”。

## 2. 品牌名称

| 场景 | 简体中文 | 英语（美国） |
| --- | --- | --- |
| App Store 名称 | `AIK by WeKare` | `AIK by WeKare` |
| 安装后的 App 名称 | `AIK企业知识库` | `AIK` |
| 副标题 | `企业专属智能知识助手` | `Enterprise Knowledge Assistant` |

App Store 名称受全局唯一性约束。若当前名称已经通过 App Store Connect 创建，不要在发版时随意修改。安装后的英文显示名称保持为 `AIK`，避免主屏幕名称被截断。

## 3. 简体中文元数据

### 3.1 推广文本

字符数：69 / 170。

```text
连接企业专属知识空间，通过自然语言快速查询产品资料、制度文档与业务知识。支持多企业空间切换、邀请与匿名访问、历史会话、流式回答及语音提问。
```

### 3.2 描述

```text
AIK 是面向企业知识服务的 iPhone 原生客户端。

连接获得授权的企业知识空间后，用户可以使用自然语言查询产品资料、技术文档、制度规范和业务知识，减少在大量文件中反复查找信息的时间。

主要功能：

• 企业空间
浏览、搜索、选择和切换可访问的企业知识空间。

• 智能知识问答
围绕企业提供的知识内容进行提问，通过流式方式持续展示回答。

• 多种访问方式
根据企业空间配置，支持系统账号、企业成员账号、邀请码或匿名验证访问。

• 会话管理
查看最近会话和历史消息，支持新建对话、复制回答、提交反馈及清空历史。

• 语音提问
在企业启用语音能力且用户授权麦克风后，可将语音转换为文字并继续提问。

• 多语言与多设备
支持简体中文和英文，适配 iPhone、深色模式、动态字体及 VoiceOver。

AIK 仅展示当前企业空间授权用户访问的内容。不同企业空间提供的功能、访问方式和知识范围可能有所不同。

AI 生成内容仅供参考。对于重要的业务、技术、安全或决策事项，请结合企业原始资料和专业人员意见进行核实。
```

### 3.3 关键词

字符数：49 / 100。

```text
企业知识库,智能问答,知识检索,RAG,文档问答,企业AI,语音提问,业务助手,资料查询,知识管理
```

### 3.4 技术支持网址

```text
https://www.jaronsoft.com/solutions/enterprise/knowledge-base/
```

### 3.5 营销网址

```text
https://www.jaronsoft.com/solutions/enterprise/knowledge-base/
```

## 4. 英语（美国）元数据

### 4.1 Promotional Text

字符数：153 / 170。

```text
Connect to your organization’s knowledge spaces. Ask across technical documents, policies, and business knowledge with streaming answers and voice input.
```

### 4.2 Description

```text
AIK is a native enterprise knowledge client for iPhone.

After connecting to an authorized organizational knowledge space, users can ask questions about product materials, technical documents, policies, procedures, and other business knowledge.

KEY FEATURES

• Knowledge Spaces
Browse, search, select, and switch between the organizational knowledge spaces available to you.

• Knowledge-Based Q&A
Ask questions using natural language and receive streaming answers based on the content provided by the selected organization.

• Flexible Access
Depending on the organization’s configuration, AIK supports system accounts, member accounts, invitation codes, and verified guest access.

• Conversation History
Access recent conversations and previous messages, start a new conversation, copy answers, submit feedback, or clear conversation history.

• Voice Questions
When enabled by the organization, users can record a question and convert it to text after granting microphone permission.

• Multilingual and Accessible
AIK supports Simplified Chinese and English, iPhone layouts, Dark Mode, Dynamic Type, VoiceOver, and Reduce Motion.

AIK only displays content authorized by the selected organization. Available features, access methods, and knowledge content may vary between organizations.

AI-generated content is provided for reference. Important business, technical, safety, or decision-making information should be verified against the organization’s original materials or with a qualified professional.
```

### 4.3 Keywords

字符数：96 / 100。

```text
enterprise knowledge,AI assistant,RAG,document search,knowledge base,voice questions,business AI
```

### 4.4 Support URL

```text
https://www.jaronsoft.com/solutions/enterprise/knowledge-base/
```

### 4.5 Marketing URL

```text
https://www.jaronsoft.com/solutions/enterprise/knowledge-base/
```

## 5. 版权

App Store Connect 的版权字段通常作为版本级公共信息维护，建议填写：

```text
© 2026 Yangzhou Jaron Information Technology Co., Ltd.
```

正式提交前必须确认版权主体与软件权利证明、开发者账号授权关系及 App Store Connect 中的销售方信息一致。若改由 `WeKare Partners LLC` 持有或提交相关权利材料，应同步调整版权字段。

## 6. App 审核信息

### 6.1 登录信息

优先为 Apple 审核准备独立的非敏感演示企业空间。若审核可以通过匿名访问完成主要功能验证：

- 不勾选“需要登录”；
- 在审核备注中提供明确的企业空间名称和用户编号；
- 确保验证码、匿名会话和问答额度在审核期间可用。

若匿名路径不能覆盖全部待审功能，则必须提供长期有效的审核专用账号。禁止提供员工账号、真实客户账号或包含敏感业务数据的空间。

### 6.2 英文审核备注模板

提交前必须替换方括号中的内容。

```text
AIK is a multi-tenant enterprise knowledge client.

Review steps:
1. Launch the app and open the Knowledge Space selection page.
2. Select the review workspace:
   Workspace: [REVIEW WORKSPACE NAME]
   User ID: [REVIEW WORKSPACE ID]
3. Select Guest Access and enter the CAPTCHA displayed on the screen.
4. Enter the workspace to test knowledge-based Q&A, streaming responses, conversation history, new conversations, copy, and feedback.
5. Voice input is only displayed when enabled for the selected workspace. Microphone permission is requested when the feature is used.

No username or password is required for the guest review flow. The review workspace contains demonstration content only and does not include real customer or sensitive business data.
```

### 6.3 中文审核备注模板

```text
AIK 是多租户企业知识库的原生访问客户端。

审核步骤：
1. 启动 App，进入“选择企业空间”页面。
2. 选择审核专用企业空间：
   空间名称：[填写审核空间名称]
   用户编号：[填写审核空间编号]
3. 选择“匿名访问”，输入页面显示的图形验证码。
4. 进入企业空间后，可测试知识问答、流式回答、历史会话、新建对话、复制及反馈功能。
5. 语音输入仅在审核空间启用语音功能时显示，首次使用会请求麦克风权限。

匿名审核路径不需要用户名和密码。审核空间仅包含演示资料，不包含真实客户或敏感业务数据。
```

审核备注建议以英文为主；如需降低沟通歧义，可以在英文后附中文版本。

## 7. 截图本地化

首发可以暂时复用同一组截图，但建议分别准备：

- 简体中文商店：中文界面截图；
- 英语（美国）商店：英文界面截图。

截图必须来自当前提交构建，不得展示尚未实现的功能。建议覆盖：

1. 企业空间选择；
2. 匿名或授权访问；
3. 知识问答及流式回答；
4. 历史会话；
5. 语音提问；
6. 深色模式与辅助功能。

截图中不得包含真实客户资料、手机号、邮箱、账号、邀请码、访问 Token、内部域名参数或其他敏感信息。

## 8. 每次提交检查表

- [ ] App 名称、副标题与实际品牌一致。
- [ ] 简体中文和英语（美国）元数据均已保存。
- [ ] 推广文本不超过 170 个字符。
- [ ] 描述不超过 4,000 个字符。
- [ ] 关键词不超过 100 个字符。
- [ ] 技术支持网址和营销网址可通过 HTTPS 正常访问。
- [ ] 版权年份和权利主体正确。
- [ ] 截图来自当前构建且不包含敏感信息。
- [ ] 审核空间为非敏感演示空间。
- [ ] 审核备注中的占位符已经全部替换。
- [ ] 审核期间匿名验证码、测试账号、问答额度和语音能力可用。
- [ ] 已选择本次发布的正确构建版本。
- [ ] App 隐私、出口合规和内容权利声明与当前功能一致。
- [ ] 发布方式已确认使用手动发布或自动发布。

## 9. 后续维护规则

- 新增、删除或调整功能时，同步更新中文和英文描述。
- 修改访问流程时，同步更新审核备注和审核截图。
- 修改技术支持域名时，先验证线上页面，再更新全部语言。
- 增加新的 App 内语言后，再为对应语言添加商店本地化。
- 每次正式提交前重新核对字符数，不依赖本文档中的历史统计。
- 已通过审核的文案发生重大调整时，在发布记录中注明原因和版本。
