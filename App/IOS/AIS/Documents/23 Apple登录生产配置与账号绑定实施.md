# Apple 登录生产配置与账号绑定实施

## 1. 当前状态

- 实施日期：`2026-08-01`
- App ID：`com.wekarepartners.studio`
- Team ID：`R3622MSZJ7`
- Key ID：`D32U3TPA33`
- 服务端原生登录、登录态绑定、账号删除撤销和 iOS credential state 检查代码已完成。
- YZ1、YZ2、SH2 的 `.p8` 已完成宿主机保存、容器只读挂载和 SHA-256 一致性验证。
- 当前仍待用户发布生产 API、制作新的 iOS TestFlight 构建并完成真实 Apple 账号联调；不得提前标记为生产验收完成。

## 2. 私钥部署

私钥不得提交 Git、写入镜像、部署产物或环境变量。四个节点统一使用：

```text
宿主机：/opt/1panel/secrets/ais/AuthKey_D32U3TPA33.p8
容器内：/run/secrets/ais-apple-signin.p8
挂载模式：只读
```

后端非敏感配置：

```json
{
  "AppleSignIn": {
    "Enabled": true,
    "ClientId": "com.wekarepartners.studio",
    "TeamId": "R3622MSZJ7",
    "KeyId": "D32U3TPA33",
    "PrivateKeyPath": "/run/secrets/ais-apple-signin.p8",
    "PrivateKey": ""
  }
}
```

统一安装和验证：

```bash
bash ServerConfig/install-ais-apple-signin.sh --all --key-file /path/to/AuthKey_D32U3TPA33-AIS.p8
bash ServerConfig/install-ais-apple-signin.sh --verify
```

脚本自动读取 1Panel 容器的 Compose 标签、备份并校验 `docker-compose.yml`、写入持久只读挂载并核对宿主机与容器文件摘要。SH2 的 GitLab CI 以及 `yz.sh` 仅更新 `/mnt/www/app.jaronsoft.com` 并停止/启动既有容器，不会覆盖 `/opt/1panel/secrets/ais` 或 Compose 挂载。若以后在 1Panel 中删除运行环境、覆盖 Compose 或轮换 Apple Key，必须重新执行脚本。

四节点运行中的 Redis 配置文件摘要已核对一致；现有 `AddDataProtectionSetup()` 使用统一应用名和 Redis `DataProtection-Keys` 密钥环，因此一个节点加密保存的 Apple refresh token 可以由其他节点在账号删除或撤销授权时解密。发布验收仍需实际执行一次跨节点登录与删除测试。

## 3. 登录与绑定规则

### Apple 登录

- `POST /api/ais/auth/apple/native` 接收 identity token、单次 authorization code、raw nonce 和首次姓名/邮箱。
- 服务端验证 Apple 签名、issuer、audience、expiration、nonce 和授权码，以 Apple `sub` 作为稳定身份键。
- 首次 Apple 登录自动创建 AIS 用户，重复登录返回同一用户；姓名只在首次授权时使用。
- Apple 邮箱已属于普通邮箱账号时禁止按邮箱自动合并，并引导用户先使用邮箱登录后再绑定。

### 登录态绑定

- `GET /api/ais/account/apple/status` 返回当前登录用户是否已绑定 Apple 及邮箱快照。
- `POST /api/ais/account/apple/bind` 必须携带 AIS access token，并重新完成 Apple 授权和服务端验证。
- 同一 Apple `sub` 已属于其他 AIS 用户时拒绝绑定；当前 AIS 用户已绑定另一个 Apple 身份时拒绝替换；重复绑定同一身份幂等更新 refresh token。
- 本阶段不提供解绑，避免 Apple-only 用户失去唯一登录方式。

## 4. iOS 会话规则

- 邮箱注册、验证码登录和密码登录将 Keychain 会话标记为 `email`。
- Apple 登录将会话标记为 `apple`，并保存 Apple 返回的 opaque `user` 标识。
- App 启动和恢复前台时，仅对 Apple 登录建立的会话调用 `credentialState(forUserID:)`；`.revoked`、`.notFound` 和 `.transferred` 会清除本地会话。
- 邮箱会话即使绑定了 Apple，也不会因 Apple 授权撤销而退出邮箱会话。
- 旧版 Keychain 会话没有新增字段时保持兼容，不会因升级而误退出。

## 5. 发布与验收

发布顺序：

1. SH2 通过 GitLab CI 发布后端。
2. YZ1、YZ2 通过 `scripts/yz.sh` 发布。
3. 执行 `install-ais-apple-signin.sh --verify`，确认四节点容器运行且挂载一致。
4. 完成新 Apple 用户共享邮箱、隐藏邮箱、重复登录、邮箱账号绑定、跨账号冲突、错误 nonce、重复授权码、授权撤销和账号删除测试。
5. 后端生产验证通过后再制作新的 iOS TestFlight 构建。

代码提交前已通过 Apple 私钥解析与绑定策略后端测试，以及 iPhone 17 Pro（iOS 26.5）完整 `AISTests`。真实 Apple 授权无法由模拟器单元测试替代，仍必须使用真机和 Sandbox/TestFlight 验收。
