# MOSA iOS 同步约定

- `App/IOS/Mosa/` 是 iOS 工程的唯一修改源；`/Users/jaron/Projects/Github/mosa` 是同步目标，不应直接在目标目录修改业务或工程文件。
- 每次在本目录新增、修改、移动或删除文件后，必须在结束当前任务前执行：

  ```bash
  App/IOS/Mosa/scripts/sync-to-github.sh --delete
  ```

  该命令会将源目录镜像同步至目标仓库，并保护目标目录的 `.git` 元数据。
- `MOSA.xcodeproj` 及其中的共享配置属于必须同步的工程文件；不得为避免同步而排除它们。
- `xcuserdata/`、`*.xcuserstate`、`DerivedData/`、`build/`、`.release/` 与签名文件属于本地状态或敏感产物，沿用同步脚本的排除规则，不得复制到目标仓库。
- 同步命令失败时，必须先解决失败原因；不得声称目标目录已同步。
- 镜像前先检查目标仓库工作树并执行 `git pull --ff-only`，再运行 `App/IOS/Mosa/scripts/sync-to-github.sh --dry-run --delete` 核对删除清单。镜像脚本只更新本地目标工作树；提交和推送 GitHub 需单独核验与执行。
