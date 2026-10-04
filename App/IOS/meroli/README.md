# Meroli iOS

Meroli 原生 iOS 客户端工程，使用 SwiftUI + URLSession，目录与配置分层参考 `App/IOS/Mosa`。

## 工程标识

- Xcode 工程与 Scheme：`Meroli`
- Swift module：`Meroli`
- Bundle ID：`com.wekarepartners.meroli.app`
- 最低系统版本：iOS 17

## Apple Developer 与 App Store Connect

开发团队、App ID、SKU、Apple ID 与发布状态见 [Meroli iOS 发布记录](../../../Documents/开发计划/Meroli/iOS发布记录.md)。

## 开发 API

Debug 与 Release 默认都使用正式 HTTPS 地址 `https://api.wekarepartners.com`，与 MOSA 共用 API 服务器。只有明确需要连接本地 API 时，才将 `Configuration/Debug.Local.xcconfig.example` 复制为 `Configuration/Debug.Local.xcconfig`，并改为运行 API 的开发机局域网 IP，例如 `http://192.168.1.20:8980`。本地覆盖文件已加入忽略规则，不会进入版本库。

Meroli API 通过 `/api/v1` 下的独立 Meroli 路由访问，不会覆盖 MOSA 的业务路由。

## 打开运行

使用 Xcode 打开 `Meroli.xcodeproj`，选择 `Meroli` Scheme 和 iOS Simulator 后运行。命令行构建：

```bash
xcodebuild -project Meroli.xcodeproj -scheme Meroli \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

API 请求路径统一相对于 API origin，包含后端前缀，例如 `/api/v1/auth/login`。
