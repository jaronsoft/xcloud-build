# MOSA iOS 同步约定

- `App/IOS/Mosa/` 是 iOS 工程的唯一修改源；统一 GitHub 目标为 `https://github.com/jaronsoft/xcloud-build.git`，镜像路径保持为 `App/IOS/Mosa/`。
- 每次在本目录新增、修改、移动或删除文件后，必须在结束当前任务前从仓库根目录运行 `Scripts/sync-ios-to-xcloud-build.sh`。该入口会同步 `App/IOS/` 下所有独立工程，按 App 分别提交并推送到 `main`，从而触发对应 Xcode Cloud workflow。
- 预览变更时运行 `Scripts/sync-ios-to-xcloud-build.sh --dry-run`。脚本会先检查目标工作树并快进拉取远端；不要直接修改目标镜像。
- `MOSA.xcodeproj`、共享 Scheme 与 Xcode Cloud 工程元数据都属于必须同步的工程文件。
- `xcuserdata/`、`*.xcuserstate`、`DerivedData/`、`build/`、`.release/`、本机配置和签名文件属于本地状态或敏感产物，不得复制到目标仓库。
- 同步命令失败时，必须先解决失败原因；不得声称目标目录或远端已同步。
