# PixaRivo iOS 开发规范

<!-- markdownlint-disable MD013 -->

## 版本与 Build

- `MARKETING_VERSION` 使用 `主版本.次版本.修订版本` 三段格式，只有用户明确决定新版本时才修改。
- 线上发布 Build 由仓库外的自动流程分配，App Store Connect 中已处理或已发布的实际编号是唯一事实来源；不得根据本地工程值自行推算或承诺下一个线上 Build。
- `CURRENT_PROJECT_VERSION` 仅作为本地工程默认值，线上流程可能覆盖它；准备新版本时不得为了追赶线上编号而手动修改。发布说明中的待发布版本必须写“Build 待自动生成”，完成线上构建后再回填实际编号。
- 自动流程生成的新 Build 必须高于 App Store Connect 已存在的最高编号，不得回退或复用。
- 修改版本或 Build 信息时，必须同步核对 `PixaRivo.xcodeproj/project.pbxproj`、`RELEASE_NOTES.md`、`RELEASE_NOTES_OTHER_LANGUAGES.md`、根 `README.md` 和 `Documents/PixaRivo-App-Store-Connect/` 下的发布资料。
