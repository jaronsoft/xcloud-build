# AIK 企业知识库 iOS

> 项目关系：[项目关联与上下文检索索引](../../../documents/项目关联索引.md)

AIK 是 RAG 知识库项目的产品名称，本目录是该项目面向企业知识空间的原生 SwiftUI 客户端。应用支持 SaaS 系统账号登录、多租户选择、邀请/匿名访问、历史会话、SSE 流式问答、评价及语音提问，并复用现有线上接口，不修改服务端和数据库。

## 工程信息

- Xcode 工程：`AIK.xcodeproj`
- Target / Module：`AIK`
- Bundle ID：`com.wekarepartners.aik`
- Apple Team ID：`R3622MSZJ7`
- 版本：`1.0.1`；本地工程默认 Build：`100`
- 技术基线：Swift 6、SwiftUI、Swift Concurrency、iOS 17+
- 设备：仅 iPhone
- 生产 API：`https://app.jaronsoft.com/api`
- 依赖：仅 Apple 系统框架

## 当前发布状态

- `1.0.0 (260727.2)` 已于 `2026-07-27 19:49` 上传 App Store Connect。
- Apple 已处理完成，构建状态为 `Ready to Submit`，并已加入内部测试分组 `Developer`。
- 后续上传 Build 由外部自动流程分配，必须高于 App Store Connect 已存在的最高编号；本地工程使用递增整数默认值，不再使用日期加小数格式。
- 本次更新包含多入口访问、扫码与 Universal Link、Markdown/SSE 修复、租户 Logo、网络诊断和缓存管理。

## 本地运行

1. 使用完整 Xcode 打开 `AIK.xcodeproj`。
2. 选择 `AIK` Scheme 和 iOS 17 或更高版本的模拟器/真机。
3. 真机运行前确认开发团队为 `R3622MSZJ7`，且 Apple Developer 已注册 Explicit App ID `com.wekarepartners.aik`。

命令行验证：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project AIK.xcodeproj -scheme AIK \
  -configuration Debug -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO build
```

TestFlight 上传使用 [ExportOptions-TestFlight.plist](./Configuration/ExportOptions-TestFlight.plist)，实际发布记录见 App Store Connect 文档。

## 文档

- [AIK / RAG 知识库项目文档中心](../../../documents/RAG/README.md)
- [产品与工程配置](./Documents/01%20产品与工程配置.md)
- [接口与登录租户流程](./Documents/02%20接口与登录租户流程.md)
- [App Store Connect 创建与发布](./Documents/03%20App%20Store%20Connect%20创建与发布.md)

## GitHub 镜像同步

- 源目录：`/Users/jaron/Projects/NET/app.jaronsoft.com/App/IOS/AIK`
- 目标仓库：`/Users/jaron/Projects/Github/aik`
- 默认分支：`main`

先演练并检查变更：

```bash
App/IOS/AIK/sync-to-github.sh --dry-run --delete
```

确认后执行镜像同步：

```bash
App/IOS/AIK/sync-to-github.sh --delete
```

需要持续同步时可执行 `App/IOS/AIK/sync-to-github.sh --watch`。也可通过 `AIK_GITHUB_DIR` 临时覆盖目标目录。

目标仓库只是镜像，不应直接修改；所有业务、工程和文档变更均应先在本目录完成，再同步到 GitHub 仓库。同步脚本始终保留目标仓库的 `.git/`，并排除 Xcode 用户状态、构建产物和签名文件。

## 安全边界

JWT、refresh token 和用户信息保存在 Keychain；租户选择和最近访问等非敏感偏好保存在 `UserDefaults`；密码不落盘。普通账号只能选择线上接口返回的租户，客户端不推断或绕过服务端权限。
