#!/bin/bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_NAME="MOSA.xcodeproj"
SCHEME="MOSA"
CONFIGURATION="Release"
DESTINATION="generic/platform=iOS"
# 默认保持正式发布工具链，TestFlight 特殊构建可通过环境变量显式覆盖。
EXPECTED_XCODE_VERSION="${MOSA_EXPECTED_XCODE_VERSION:-26.6}"
EXPECTED_XCODE_BUILD="${MOSA_EXPECTED_XCODE_BUILD:-17F113}"

RELEASE_DIR="$PROJECT_DIR/.release"
ARCHIVES_DIR="$RELEASE_DIR/archives"
EXPORTS_DIR="$RELEASE_DIR/exports"
LOGS_DIR="$RELEASE_DIR/logs"
DERIVED_DATA_PATH="$RELEASE_DIR/DerivedData"
LATEST_ARCHIVE_FILE="$RELEASE_DIR/latest-archive"
EXPORT_OPTIONS_PATH="$RELEASE_DIR/ExportOptions.plist"
CONFIG_PATH="$PROJECT_DIR/release-config"
PROJECT_PATH="$PROJECT_DIR/$PROJECT_NAME"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
RUN_TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"

CURRENT_STEP="初始化"
CURRENT_LOG=""
BUILD_SETTINGS=""
APP_NAME=""
BUNDLE_ID=""
MARKETING_VERSION=""
BUILD_NUMBER=""
TEAM_ID=""
SIGNING_STYLE=""
SDK_VERSION=""
ARCHIVE_PATH=""
AUTH_MODE="Xcode Account authentication"
MOSA_XCODE_APP_PATH_ENV="${MOSA_XCODE_APP_PATH:-}"
UPLOAD_BYPASS_PROXY_ENV="${UPLOAD_BYPASS_PROXY:-}"
MOSA_XCODE_APP_PATH="${MOSA_XCODE_APP_PATH:-}"
SELECTED_XCODE_VERSION=""
SELECTED_XCODE_BUILD=""
ASC_KEY_ID="${ASC_KEY_ID:-}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
ASC_KEY_PATH="${ASC_KEY_PATH:-}"
EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-}"
EXPECTED_TEAM_ID="${EXPECTED_TEAM_ID:-}"
YES_FLAG="false"
UPLOAD_BYPASS_PROXY="${UPLOAD_BYPASS_PROXY:-true}"

usage() {
  cat <<'EOF'
用法：
  ./scripts/ios-release.sh
  ./scripts/ios-release.sh <命令> [--yes]

无参数时默认执行 release：自动检测、归档、验证并上传。

命令：
  doctor   检查 Xcode、工程、签名和上传配置
  info     显示当前主应用发布信息
  clean    清理 Release 构建产物和 DerivedData
  build    执行不上传的 Release 真机构建
  archive  创建并记录 xcarchive
  export   从最新 Archive 导出 IPA
  upload   验证并上传最新 Archive 到 App Store Connect
  release  依次执行 doctor、archive、verify 和 upload
  verify   验证最新 Archive 的应用、Xcode Build 和签名
  open     在 Xcode 中打开最新 Archive（不存在时打开工程）
  schemes  显示工程中的 Schemes

选项：
  --yes    upload/release 跳过交互确认，适用于明确授权的 CI
EOF
}

print_error_hints() {
  local log_path="${1:-}"
  [ -n "$log_path" ] || return 0
  [ -f "$log_path" ] || return 0

  if grep -Eiq 'No signing certificate|requires a development team|certificate.*not found' "$log_path"; then
    echo "提示：未找到可用签名证书，请在钥匙串安装有效的 Apple Distribution 证书。"
  fi
  if grep -Eiq 'No profiles.*found|provisioning profile.*not found' "$log_path"; then
    echo "提示：未找到 Provisioning Profile，请检查 Xcode Accounts 和 Automatic Signing。"
  fi
  if grep -Eiq 'Provisioning profile.*(doesn.t match|mismatch|does not include)' "$log_path"; then
    echo "提示：Provisioning Profile 与 Bundle Identifier、证书或能力不匹配。"
  fi
  if grep -Eiq 'Bundle Identifier.*(mismatch|does not match)|bundle identifier.*already' "$log_path"; then
    echo "提示：Bundle Identifier 不匹配，请核对工程与 App Store Connect 记录。"
  fi
  if grep -Eiq 'Authentication failed|Unable to authenticate|not authenticated' "$log_path"; then
    echo "提示：App Store Connect 认证失败，请检查 Xcode 账号登录状态。"
  fi
  if grep -Eiq 'Invalid API key|authentication key.*invalid|issuer.*invalid' "$log_path"; then
    echo "提示：API Key 无效，请核对 Key ID、Issuer ID、密钥文件和密钥状态。"
  fi
  if grep -Eiq 'build.*already.*used|bundle version.*must be higher|CFBundleVersion.*higher' "$log_path"; then
    echo "提示：该 Build Number 可能已上传，请先在工程中递增 CURRENT_PROJECT_VERSION。"
  fi
  if grep -Eiq 'SDK.*(not found|unsupported)|Unsupported SDK|iOS [0-9.]+ (Platform Not Installed|is not installed)|Unable to find a destination|No simulator runtime version' "$log_path"; then
    echo "提示：iPhoneOS SDK 不可用或不受支持，请确认当前 Xcode 的 iOS 平台组件安装完整。"
  fi
}

fail() {
  local message="$1"
  local status="${2:-1}"
  local log_path="${3:-$CURRENT_LOG}"
  trap - ERR
  echo
  echo "失败步骤：$CURRENT_STEP"
  echo "退出码：$status"
  echo "错误：$message"
  if [ -n "$log_path" ]; then
    echo "相关日志：$log_path"
    if [ -f "$log_path" ]; then
      echo "日志最后 80 行："
      tail -n 80 "$log_path"
      print_error_hints "$log_path"
    fi
  fi
  exit "$status"
}

unexpected_error() {
  local status="$1"
  local line="$2"
  fail "脚本在第 $line 行发生未处理错误。" "$status" "$CURRENT_LOG"
}

trap 'unexpected_error $? "$LINENO"' ERR

ensure_release_dirs() {
  mkdir -p "$ARCHIVES_DIR" "$EXPORTS_DIR" "$LOGS_DIR" "$DERIVED_DATA_PATH"
}

run_logged() {
  local step="$1"
  local log_path="$2"
  shift 2
  local status

  CURRENT_STEP="$step"
  CURRENT_LOG="$log_path"
  ensure_release_dirs
  echo "日志：$log_path"
  if "$@" 2>&1 | tee "$log_path"; then
    status=0
  else
    status=${PIPESTATUS[0]}
  fi
  if [ "$status" -ne 0 ]; then
    fail "$step 执行失败。" "$status" "$log_path"
  fi
  CURRENT_LOG=""
}

select_xcode() {
  local developer_dir
  local candidate
  local candidate_version
  local candidate_build

  CURRENT_STEP="选择 Xcode"
  if [ -n "$MOSA_XCODE_APP_PATH" ]; then
    case "$MOSA_XCODE_APP_PATH" in
      *.app) developer_dir="$MOSA_XCODE_APP_PATH/Contents/Developer" ;;
      */Contents/Developer) developer_dir="$MOSA_XCODE_APP_PATH" ;;
      *) fail "MOSA_XCODE_APP_PATH 必须指向 Xcode.app 或其 Contents/Developer 目录：$MOSA_XCODE_APP_PATH" ;;
    esac
  else
    for candidate in "/Applications/Xcode-26.6.app" "/Applications/Xcode-26.6.0.app" "/Applications/Xcode.app"; do
      [ -d "$candidate/Contents/Developer" ] || continue
      candidate_version="$(DEVELOPER_DIR="$candidate/Contents/Developer" /usr/bin/xcodebuild -version 2>/dev/null | sed -n '1s/^Xcode //p')"
      candidate_build="$(DEVELOPER_DIR="$candidate/Contents/Developer" /usr/bin/xcodebuild -version 2>/dev/null | sed -n '2s/^Build version //p')"
      if [ "$candidate_version" = "$EXPECTED_XCODE_VERSION" ] && [ "$candidate_build" = "$EXPECTED_XCODE_BUILD" ]; then
        developer_dir="$candidate/Contents/Developer"
        break
      fi
    done
  fi

  if [ -z "$developer_dir" ] || [ ! -d "$developer_dir" ]; then
    fail "找不到 Xcode ${EXPECTED_XCODE_VERSION} (${EXPECTED_XCODE_BUILD})。请先执行 ./scripts/setup-xcode-26.6.sh，或配置 MOSA_XCODE_APP_PATH。"
  fi
  export DEVELOPER_DIR="$developer_dir"
}

check_xcode_version() {
  local version_output
  local selected_path
  local swift_path
  local sdk_path

  CURRENT_STEP="检查 Xcode"
  if [ ! -d "$DEVELOPER_DIR" ]; then
    fail "指定的 Xcode Developer 目录不存在：$DEVELOPER_DIR"
  fi

  selected_path="$(/usr/bin/xcode-select -p 2>&1 || true)"
  version_output="$(/usr/bin/xcodebuild -version 2>&1 || true)"
  swift_path="$(/usr/bin/xcrun --find swift 2>&1 || true)"
  sdk_path="$(/usr/bin/xcrun --sdk iphoneos --show-sdk-path 2>&1 || true)"

  echo "xcode-select -p"
  echo "$selected_path"
  echo "xcodebuild -version"
  echo "$version_output"
  echo "xcrun --find swift"
  echo "$swift_path"
  echo "xcrun --sdk iphoneos --show-sdk-path"
  echo "$sdk_path"

  SELECTED_XCODE_VERSION="$(printf '%s\n' "$version_output" | sed -n '1s/^Xcode //p')"
  SELECTED_XCODE_BUILD="$(printf '%s\n' "$version_output" | sed -n '2s/^Build version //p')"
  if [ -z "$SELECTED_XCODE_VERSION" ] || [ -z "$SELECTED_XCODE_BUILD" ]; then
    fail "无法解析当前 Xcode 的版本或 Build：$version_output"
  fi
  if [ "$SELECTED_XCODE_VERSION" != "$EXPECTED_XCODE_VERSION" ] || [ "$SELECTED_XCODE_BUILD" != "$EXPECTED_XCODE_BUILD" ]; then
    fail "Xcode 版本不匹配：实际 ${SELECTED_XCODE_VERSION} (${SELECTED_XCODE_BUILD})，要求 ${EXPECTED_XCODE_VERSION} (${EXPECTED_XCODE_BUILD})。"
  fi
  if [ -z "$swift_path" ] || [ ! -x "$swift_path" ]; then
    fail "无法从 Xcode ${SELECTED_XCODE_VERSION} 找到 Swift 工具链。"
  fi
  if [ -z "$sdk_path" ] || [ ! -d "$sdk_path" ]; then
    fail "无法从 Xcode ${SELECTED_XCODE_VERSION} 找到 iPhoneOS SDK。"
  fi
}

check_project() {
  CURRENT_STEP="检查 Xcode 工程"
  if [ ! -d "$PROJECT_PATH" ]; then
    fail "Xcode 工程不存在：$PROJECT_PATH"
  fi
}

project_list_output() {
  (
    cd "$PROJECT_DIR"
    /usr/bin/xcodebuild -project "$PROJECT_NAME" -list
  )
}

scheme_names() {
  project_list_output 2>/dev/null | awk '
    /^[[:space:]]*Schemes:/ { in_schemes = 1; next }
    in_schemes && /^[[:space:]]+[^[:space:]]/ {
      value = $0
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      print value
    }
  '
}

check_scheme() {
  local schemes
  CURRENT_STEP="检查 Scheme"
  schemes="$(scheme_names)"
  if ! printf '%s\n' "$schemes" | grep -Fqx "$SCHEME"; then
    echo "工程实际 Schemes："
    if [ -n "$schemes" ]; then
      printf '  %s\n' "$schemes"
    else
      echo "  （未检测到共享 Scheme）"
    fi
    fail "未找到要求的 Scheme：$SCHEME"
  fi
}

load_release_config() {
  CURRENT_STEP="读取发布配置"
  if [ -f "$CONFIG_PATH" ]; then
    # 配置文件只保存非密钥内容和密钥路径；脚本不会读取或输出密钥正文。
    set -a
    # shellcheck disable=SC1090
    . "$CONFIG_PATH"
    set +a
  fi

  ASC_KEY_ID="${ASC_KEY_ID:-}"
  ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
  ASC_KEY_PATH="${ASC_KEY_PATH:-}"
  EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-}"
  EXPECTED_TEAM_ID="${EXPECTED_TEAM_ID:-}"
  MOSA_XCODE_APP_PATH="${MOSA_XCODE_APP_PATH:-}"
  UPLOAD_BYPASS_PROXY="${UPLOAD_BYPASS_PROXY:-true}"
  if [ -n "$MOSA_XCODE_APP_PATH_ENV" ]; then
    MOSA_XCODE_APP_PATH="$MOSA_XCODE_APP_PATH_ENV"
  fi
  if [ -n "$UPLOAD_BYPASS_PROXY_ENV" ]; then
    UPLOAD_BYPASS_PROXY="$UPLOAD_BYPASS_PROXY_ENV"
  fi

  case "$ASC_KEY_PATH" in
    "~/"*) ASC_KEY_PATH="$HOME/${ASC_KEY_PATH:2}" ;;
  esac

  if [ -n "$ASC_KEY_ID$ASC_ISSUER_ID$ASC_KEY_PATH" ]; then
    AUTH_MODE="App Store Connect API Key (${ASC_KEY_ID:-未填写 Key ID})"
  else
    AUTH_MODE="Xcode Account authentication"
  fi
}

validate_api_key() {
  local strict="${1:-true}"
  local mode
  local mode_value

  if [ -z "$ASC_KEY_ID$ASC_ISSUER_ID$ASC_KEY_PATH" ]; then
    return 0
  fi

  if [ -z "$ASC_KEY_ID" ] || [ -z "$ASC_ISSUER_ID" ] || [ -z "$ASC_KEY_PATH" ]; then
    if [ "$strict" = "true" ]; then
      fail "API Key 配置不完整，ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_PATH 必须同时填写。"
    fi
    return 1
  fi
  case "$ASC_KEY_PATH" in
    *.p8) ;;
    *)
      if [ "$strict" = "true" ]; then
        fail "ASC_KEY_PATH 必须指向 .p8 文件。"
      fi
      return 1
      ;;
  esac
  if [ ! -f "$ASC_KEY_PATH" ] || [ ! -r "$ASC_KEY_PATH" ]; then
    if [ "$strict" = "true" ]; then
      fail "API Key 文件不存在或不可读：$ASC_KEY_PATH"
    fi
    return 1
  fi

  mode="$(stat -f '%Lp' "$ASC_KEY_PATH")"
  mode_value=$((8#$mode))
  if [ $((mode_value & 0044)) -ne 0 ]; then
    if [ "$strict" = "true" ]; then
      fail "API Key 文件权限过宽（$mode），请执行 chmod 600 \"$ASC_KEY_PATH\"。"
    fi
    return 1
  fi
  return 0
}

fetch_build_settings() {
  CURRENT_STEP="读取 MOSA 主应用 Build Settings"
  if BUILD_SETTINGS="$(
      cd "$PROJECT_DIR"
      /usr/bin/xcodebuild \
        -project "$PROJECT_NAME" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -showBuildSettings 2>/dev/null
    )"; then
    return 0
  fi

  # Xcode 平台组件不完整时 Scheme 无法解析 destination；仍通过主 Target 的实际 Build Settings 提供诊断信息。
  echo "警告：Scheme Build Settings 因没有可用 destination 而无法读取，改用主 Target $SCHEME 的 Build Settings。" >&2
  BUILD_SETTINGS="$(
    cd "$PROJECT_DIR"
    /usr/bin/xcodebuild \
      -project "$PROJECT_NAME" \
      -target "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -showBuildSettings
  )"
}

setting_value() {
  local key="$1"
  printf '%s\n' "$BUILD_SETTINGS" | awk -v target="$SCHEME" -v wanted="$key" '
    $0 == "Build settings for action build and target " target ":" {
      in_target = 1
      next
    }
    /^Build settings for action / {
      in_target = 0
    }
    in_target {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      prefix = wanted " = "
      if (index(line, prefix) == 1) {
        print substr(line, length(prefix) + 1)
        exit
      }
    }
  '
}

load_project_info() {
  fetch_build_settings
  APP_NAME="$(setting_value PRODUCT_NAME)"
  BUNDLE_ID="$(setting_value PRODUCT_BUNDLE_IDENTIFIER)"
  MARKETING_VERSION="$(setting_value MARKETING_VERSION)"
  BUILD_NUMBER="$(setting_value CURRENT_PROJECT_VERSION)"
  TEAM_ID="$(setting_value DEVELOPMENT_TEAM)"
  SIGNING_STYLE="$(setting_value CODE_SIGN_STYLE)"
  SDK_VERSION="$(/usr/bin/xcrun --sdk iphoneos --show-sdk-version)"
  ARCHIVE_PATH="$ARCHIVES_DIR/${APP_NAME:-MOSA}-${MARKETING_VERSION:-unknown}-${BUILD_NUMBER:-unknown}-$RUN_TIMESTAMP.xcarchive"
}

print_info() {
  echo "App 名称：${APP_NAME:-（空）}"
  echo "Bundle Identifier：${BUNDLE_ID:-（空）}"
  echo "Marketing Version：${MARKETING_VERSION:-（空）}"
  echo "Build Number：${BUILD_NUMBER:-（空）}"
  echo "Development Team：${TEAM_ID:-（空）}"
  echo "Signing Style：${SIGNING_STYLE:-（空）}"
  echo "Xcode 版本：Xcode ${SELECTED_XCODE_VERSION} (${SELECTED_XCODE_BUILD})"
  echo "Developer 目录：$DEVELOPER_DIR"
  echo "SDK 版本：${SDK_VERSION:-（空）}"
  echo "Archive 路径：$ARCHIVE_PATH"
  echo "上传认证模式：$AUTH_MODE"
}

check_required_settings() {
  [ -n "$TEAM_ID" ] || fail "DEVELOPMENT_TEAM 为空，请在 Xcode Signing & Capabilities 中配置 Team。"
  [ -n "$BUNDLE_ID" ] || fail "PRODUCT_BUNDLE_IDENTIFIER 为空。"
  [ -n "$MARKETING_VERSION" ] || fail "MARKETING_VERSION 为空。"
  [ -n "$BUILD_NUMBER" ] || fail "CURRENT_PROJECT_VERSION 为空。"

  if ! printf '%s\n' "$MARKETING_VERSION" | grep -Eq '^[0-9]+(\.[0-9]+){1,2}$'; then
    fail "MARKETING_VERSION 必须使用两段或三段数字版本号，例如 1.1 或 1.1.1；当前为 ${MARKETING_VERSION}。"
  fi
  if ! printf '%s\n' "$BUILD_NUMBER" | grep -Eq '^[1-9][0-9]*$'; then
    fail "CURRENT_PROJECT_VERSION 必须使用从 1 开始连续递增的整数，不再使用日期或小数后缀；当前为 ${BUILD_NUMBER}。"
  fi

  if printf '%s\n' "$BUNDLE_ID" | grep -Eiq 'example|placeholder|yourcompany|your-company|changeme|com\.company'; then
    fail "Bundle Identifier 看起来仍是示例值或占位值：$BUNDLE_ID"
  fi
  if [ -n "$EXPECTED_BUNDLE_ID" ] && [ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]; then
    fail "Bundle Identifier 与 release-config 不一致：实际 ${BUNDLE_ID}，预期 ${EXPECTED_BUNDLE_ID}。"
  fi
  if [ -n "$EXPECTED_TEAM_ID" ] && [ "$TEAM_ID" != "$EXPECTED_TEAM_ID" ]; then
    fail "Development Team 与 release-config 不一致：实际 ${TEAM_ID}，预期 ${EXPECTED_TEAM_ID}。"
  fi
}

is_automatic_signing() {
  [ "$SIGNING_STYLE" = "Automatic" ] || [ "$SIGNING_STYLE" = "automatic" ]
}

append_provisioning_args() {
  PROVISIONING_ARGS=()
  if is_automatic_signing; then
    PROVISIONING_ARGS+=("-allowProvisioningUpdates")
    if [ -n "$ASC_KEY_ID$ASC_ISSUER_ID$ASC_KEY_PATH" ]; then
      validate_api_key true
      PROVISIONING_ARGS+=("-allowProvisioningDeviceRegistration")
    fi
  fi
}

append_authentication_args() {
  AUTHENTICATION_ARGS=()
  if [ -n "$ASC_KEY_ID$ASC_ISSUER_ID$ASC_KEY_PATH" ]; then
    validate_api_key true
    AUTHENTICATION_ARGS+=(
      "-authenticationKeyPath" "$ASC_KEY_PATH"
      "-authenticationKeyID" "$ASC_KEY_ID"
      "-authenticationKeyIssuerID" "$ASC_ISSUER_ID"
    )
  fi
}

do_schemes() {
  CURRENT_STEP="列出 Schemes"
  project_list_output
}

do_info() {
  load_project_info
  print_info
}

do_doctor() {
  local identities
  local git_changes
  local destinations
  local problems=0

  CURRENT_STEP="发布预检"
  echo
  echo "发布信息："
  print_info
  echo
  echo "预检项目："
  echo "✓ Xcode ${SELECTED_XCODE_VERSION} (${SELECTED_XCODE_BUILD})"
  echo "✓ 工程存在：$PROJECT_PATH"
  echo "✓ Scheme 存在：$SCHEME"
  destinations="$(/usr/bin/xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -showdestinations 2>&1 || true)"
  if printf '%s\n' "$destinations" | grep -Eq 'Any iOS Device, error:|generic/platform=iOS.*error:|iOS [0-9.]+ is not installed'; then
    echo "✗ Xcode ${SELECTED_XCODE_VERSION} 的 iOS ${SDK_VERSION} 平台组件不可用"
    problems=$((problems + 1))
  else
    echo "✓ iPhoneOS SDK：$SDK_VERSION"
  fi

  if [ -n "$TEAM_ID" ]; then echo "✓ DEVELOPMENT_TEAM：$TEAM_ID"; else echo "✗ DEVELOPMENT_TEAM 为空"; problems=$((problems + 1)); fi
  if [ -n "$BUNDLE_ID" ]; then echo "✓ PRODUCT_BUNDLE_IDENTIFIER：$BUNDLE_ID"; else echo "✗ PRODUCT_BUNDLE_IDENTIFIER 为空"; problems=$((problems + 1)); fi
  if printf '%s\n' "$MARKETING_VERSION" | grep -Eq '^[0-9]+(\.[0-9]+){1,2}$'; then
    echo "✓ MARKETING_VERSION：$MARKETING_VERSION"
  else
    echo "✗ MARKETING_VERSION 必须是两段或三段数字版本号：${MARKETING_VERSION:-（空）}"
    problems=$((problems + 1))
  fi
  if printf '%s\n' "$BUILD_NUMBER" | grep -Eq '^[1-9][0-9]*$'; then
    echo "✓ CURRENT_PROJECT_VERSION：$BUILD_NUMBER"
  else
    echo "✗ CURRENT_PROJECT_VERSION 必须是连续递增的正整数：${BUILD_NUMBER:-（空）}"
    problems=$((problems + 1))
  fi

  if printf '%s\n' "$BUNDLE_ID" | grep -Eiq 'example|placeholder|yourcompany|your-company|changeme|com\.company'; then
    echo "✗ Bundle Identifier 看起来是示例值或占位值：$BUNDLE_ID"
    problems=$((problems + 1))
  else
    echo "✓ Bundle Identifier 不是明显占位值"
  fi

  identities="$(security find-identity -v -p codesigning 2>&1 || true)"
  if printf '%s\n' "$identities" | grep -q '"Apple Distribution:'; then
    echo "✓ 钥匙串中存在 Apple Distribution 证书"
  elif is_automatic_signing; then
    echo "警告：钥匙串中未找到 Apple Distribution 证书，将由 Automatic Signing 在归档/导出时处理。"
  else
    echo "✗ 钥匙串中未找到 Apple Distribution 证书"
    problems=$((problems + 1))
  fi

  git_changes="$(git -C "$PROJECT_DIR" status --porcelain -- . 2>/dev/null || true)"
  if [ -n "$git_changes" ]; then
    echo "警告：项目存在未提交的 Git 修改（不阻止发布）。"
  else
    echo "✓ 项目目录没有未提交的 Git 修改"
  fi

  if [ -f "$CONFIG_PATH" ]; then
    echo "✓ release-config 存在"
  else
    echo "警告：release-config 不存在，将使用 Xcode Account authentication。"
  fi

  if [ -n "$ASC_KEY_ID$ASC_ISSUER_ID$ASC_KEY_PATH" ]; then
    if validate_api_key false; then
      echo "✓ API Key 配置完整且文件权限未向组或其他用户开放读取"
    else
      echo "✗ API Key 配置、路径、扩展名、可读性或权限不符合要求"
      problems=$((problems + 1))
    fi
  else
    echo "提示：未配置 API Key，上传时依赖 Xcode 已登录的 Apple 账号。"
  fi

  if [ -n "$EXPECTED_BUNDLE_ID" ] && [ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]; then
    echo "✗ Bundle Identifier 与 EXPECTED_BUNDLE_ID 不一致"
    problems=$((problems + 1))
  fi
  if [ -n "$EXPECTED_TEAM_ID" ] && [ "$TEAM_ID" != "$EXPECTED_TEAM_ID" ]; then
    echo "✗ Development Team 与 EXPECTED_TEAM_ID 不一致"
    problems=$((problems + 1))
  fi

  if [ "$problems" -ne 0 ]; then
    fail "doctor 发现 $problems 个阻止发布的问题，请修复后重试。"
  fi
  echo
  echo "doctor 检查通过。"
}

do_clean() {
  local log_path="$LOGS_DIR/clean-$RUN_TIMESTAMP.log"
  local command=(
    /usr/bin/xcodebuild
    -project "$PROJECT_NAME"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
    clean
  )
  run_logged "清理 Release 构建" "$log_path" bash -c 'cd "$1" && shift && exec "$@"' _ "$PROJECT_DIR" "${command[@]}"
}

do_build() {
  local log_path="$LOGS_DIR/build-$RUN_TIMESTAMP.log"
  local command
  check_required_settings
  append_provisioning_args
  append_authentication_args
  command=(
    /usr/bin/xcodebuild
    -project "$PROJECT_NAME"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -destination "$DESTINATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
    ${PROVISIONING_ARGS[@]+"${PROVISIONING_ARGS[@]}"}
    ${AUTHENTICATION_ARGS[@]+"${AUTHENTICATION_ARGS[@]}"}
    build
  )
  run_logged "Release 构建" "$log_path" bash -c 'cd "$1" && shift && exec "$@"' _ "$PROJECT_DIR" "${command[@]}"
}

do_archive() {
  local log_path="$LOGS_DIR/archive-$RUN_TIMESTAMP.log"
  local command
  check_required_settings
  append_provisioning_args
  append_authentication_args
  command=(
    /usr/bin/xcodebuild
    -project "$PROJECT_NAME"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -destination "$DESTINATION"
    -archivePath "$ARCHIVE_PATH"
    -derivedDataPath "$DERIVED_DATA_PATH"
    ${PROVISIONING_ARGS[@]+"${PROVISIONING_ARGS[@]}"}
    ${AUTHENTICATION_ARGS[@]+"${AUTHENTICATION_ARGS[@]}"}
    clean archive
  )
  run_logged "创建 Archive" "$log_path" bash -c 'cd "$1" && shift && exec "$@"' _ "$PROJECT_DIR" "${command[@]}"
  if [ ! -d "$ARCHIVE_PATH" ]; then
    fail "xcodebuild 已返回成功，但 Archive 目录不存在：$ARCHIVE_PATH" 1 "$log_path"
  fi
  printf '%s\n' "$ARCHIVE_PATH" > "$LATEST_ARCHIVE_FILE"
  echo "Archive 已创建：$ARCHIVE_PATH"
  echo "最新 Archive 已记录：$LATEST_ARCHIVE_FILE"
}

load_latest_archive() {
  CURRENT_STEP="读取最新 Archive"
  if [ ! -f "$LATEST_ARCHIVE_FILE" ]; then
    fail "找不到 ${LATEST_ARCHIVE_FILE}，请先执行 archive。"
  fi
  ARCHIVE_PATH="$(sed -n '1p' "$LATEST_ARCHIVE_FILE")"
  case "$ARCHIVE_PATH" in
    "$ARCHIVES_DIR"/*.xcarchive) ;;
    *) fail "latest-archive 指向项目发布目录之外，已拒绝使用：$ARCHIVE_PATH" ;;
  esac
  if [ ! -d "$ARCHIVE_PATH" ]; then
    fail "latest-archive 指向的 Archive 不存在：$ARCHIVE_PATH"
  fi
}

archive_app_path() {
  local app_dir="$ARCHIVE_PATH/Products/Applications"
  local count
  local found
  [ -d "$app_dir" ] || fail "Archive contains no application：$app_dir 不存在。"
  count="$(find "$app_dir" -maxdepth 1 -type d -name '*.app' | wc -l | awk '{print $1}')"
  if [ "$count" -ne 1 ]; then
    fail "Archive/Products/Applications 下必须且只能有一个 .app，实际为 $count 个。"
  fi
  found="$(find "$app_dir" -maxdepth 1 -type d -name '*.app' -print | sed -n '1p')"
  printf '%s\n' "$found"
}

plist_value() {
  local plist="$1"
  local key="$2"
  "$PLIST_BUDDY" -c "Print :$key" "$plist" 2>/dev/null || true
}

do_verify() {
  local app_path
  local info_plist
  local verify_log
  local entitlements_log
  local archive_bundle
  local archive_version
  local archive_build
  local dt_xcode
  local dt_xcode_build
  local dt_sdk
  local dt_platform
  local minimum_os
  local status

  load_latest_archive
  app_path="$(archive_app_path)"
  info_plist="$app_path/Info.plist"
  [ -f "$info_plist" ] || fail "Archive 应用缺少 Info.plist：$info_plist"

  archive_bundle="$(plist_value "$info_plist" CFBundleIdentifier)"
  archive_version="$(plist_value "$info_plist" CFBundleShortVersionString)"
  archive_build="$(plist_value "$info_plist" CFBundleVersion)"
  dt_xcode="$(plist_value "$info_plist" DTXcode)"
  dt_xcode_build="$(plist_value "$info_plist" DTXcodeBuild)"
  dt_sdk="$(plist_value "$info_plist" DTSDKName)"
  dt_platform="$(plist_value "$info_plist" DTPlatformName)"
  minimum_os="$(plist_value "$info_plist" MinimumOSVersion)"

  echo "Archive App：$app_path"
  echo "CFBundleIdentifier：$archive_bundle"
  echo "CFBundleShortVersionString：$archive_version"
  echo "CFBundleVersion：$archive_build"
  echo "DTXcode：$dt_xcode"
  echo "DTXcodeBuild：$dt_xcode_build"
  echo "DTSDKName：$dt_sdk"
  echo "DTPlatformName：$dt_platform"
  echo "MinimumOSVersion：$minimum_os"

  if [ "$dt_xcode_build" != "$SELECTED_XCODE_BUILD" ]; then
    fail "Xcode version mismatch：Archive 的 DTXcodeBuild 为 ${dt_xcode_build}，当前 Xcode Build 为 ${SELECTED_XCODE_BUILD}。请使用创建该 Archive 的 Xcode 上传，或重新执行 archive。"
  fi
  if [ "$archive_bundle" != "$BUNDLE_ID" ]; then
    fail "Bundle Identifier mismatch：Archive 为 ${archive_bundle}，工程为 ${BUNDLE_ID}。"
  fi

  verify_log="$LOGS_DIR/verify-$RUN_TIMESTAMP.log"
  CURRENT_STEP="验证 Archive 签名"
  CURRENT_LOG="$verify_log"
  if {
      echo "codesign --verify --deep --strict --verbose=2"
      /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"
      status=$?
      if [ "$status" -eq 0 ]; then
        echo
        echo "codesign -dv --verbose=4"
        /usr/bin/codesign -dv --verbose=4 "$app_path"
      fi
      exit "$status"
    } 2>&1 | tee "$verify_log"; then
    status=0
  else
    status=${PIPESTATUS[0]}
  fi
  if [ "$status" -ne 0 ]; then
    fail "签名验证失败，不允许上传。" "$status" "$verify_log"
  fi

  entitlements_log="$LOGS_DIR/entitlements-$RUN_TIMESTAMP.plist"
  CURRENT_STEP="检查 Archive Entitlements"
  /usr/bin/codesign -d --entitlements :- "$app_path" > "$entitlements_log" 2>/dev/null
  if ! "$PLIST_BUDDY" -c 'Print :application-identifier' "$entitlements_log" >/dev/null 2>&1; then
    fail "Entitlements 缺少 application-identifier。" 1 "$entitlements_log"
  fi
  if ! "$PLIST_BUDDY" -c 'Print :com.apple.developer.team-identifier' "$entitlements_log" >/dev/null 2>&1; then
    fail "Entitlements 缺少 team-identifier。" 1 "$entitlements_log"
  fi
  CURRENT_LOG=""
  echo "Entitlements 已保存：$entitlements_log"
  echo "Archive 验证通过，DTXcodeBuild=${SELECTED_XCODE_BUILD}。"
}

detect_export_method() {
  local help_output
  CURRENT_STEP="确认 Xcode ExportOptions 支持项"
  help_output="$(/usr/bin/xcodebuild -help 2>&1)"
  if printf '%s\n' "$help_output" | grep -q 'app-store-connect'; then
    EXPORT_METHOD="app-store-connect"
  elif printf '%s\n' "$help_output" | grep -q 'app-store'; then
    EXPORT_METHOD="app-store"
  else
    fail "Xcode ${SELECTED_XCODE_VERSION} 帮助中未找到 app-store-connect 或 app-store 导出方式。"
  fi
  if ! printf '%s\n' "$help_output" | grep -Eq 'Options are export or upload|export or upload'; then
    fail "Xcode ${SELECTED_XCODE_VERSION} 帮助中未确认 destination 支持 export/upload。"
  fi
}

generate_export_options() {
  local destination="$1"
  detect_export_method
  cp "$SCRIPT_DIR/ExportOptions.plist.example" "$EXPORT_OPTIONS_PATH"
  "$PLIST_BUDDY" -c "Set :method $EXPORT_METHOD" "$EXPORT_OPTIONS_PATH"
  "$PLIST_BUDDY" -c "Set :destination $destination" "$EXPORT_OPTIONS_PATH"
  "$PLIST_BUDDY" -c "Set :teamID $TEAM_ID" "$EXPORT_OPTIONS_PATH"
  plutil -lint "$EXPORT_OPTIONS_PATH" >/dev/null
  echo "ExportOptions：method=$EXPORT_METHOD, destination=$destination, signingStyle=automatic, teamID=$TEAM_ID"
}

do_export() {
  local export_path
  local log_path="$LOGS_DIR/export-$RUN_TIMESTAMP.log"
  local command
  local ipa_count
  load_latest_archive
  do_verify
  generate_export_options export
  append_provisioning_args
  append_authentication_args
  export_path="$EXPORTS_DIR/${APP_NAME}-${MARKETING_VERSION}-${BUILD_NUMBER}-$RUN_TIMESTAMP"
  command=(
    /usr/bin/xcodebuild
    -exportArchive
    -archivePath "$ARCHIVE_PATH"
    -exportPath "$export_path"
    -exportOptionsPlist "$EXPORT_OPTIONS_PATH"
    ${PROVISIONING_ARGS[@]+"${PROVISIONING_ARGS[@]}"}
    ${AUTHENTICATION_ARGS[@]+"${AUTHENTICATION_ARGS[@]}"}
  )
  run_logged "导出 IPA" "$log_path" "${command[@]}"
  ipa_count="$(find "$export_path" -maxdepth 2 -type f -name '*.ipa' | wc -l | awk '{print $1}')"
  if [ "$ipa_count" -lt 1 ]; then
    fail "导出完成但未找到 IPA：$export_path" 1 "$log_path"
  fi
  echo "IPA 已导出到：$export_path"
}

print_upload_summary() {
  echo
  echo "发布摘要："
  echo "Bundle ID：$BUNDLE_ID"
  echo "Version：$MARKETING_VERSION"
  echo "Build Number：$BUILD_NUMBER"
  echo "Team ID：$TEAM_ID"
  echo "Archive 路径：$ARCHIVE_PATH"
  echo "使用的 Xcode：${SELECTED_XCODE_VERSION} (${SELECTED_XCODE_BUILD})"
  echo "认证模式：$AUTH_MODE"
  echo
  echo "本操作只上传 Build，不会提交审核、自动发布或修改 App Store Connect 元数据。"
}

confirm_upload() {
  local answer
  if [ "$YES_FLAG" = "true" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    fail "非交互环境必须显式传入 --yes 才能上传。"
  fi
  printf '即将上传到 App Store Connect，继续吗？[y/N] '
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) fail "用户取消上传。" ;;
  esac
}

perform_upload() {
  local export_path
  local log_path="$LOGS_DIR/upload-$RUN_TIMESTAMP.log"
  local command
  generate_export_options upload
  append_provisioning_args
  append_authentication_args
  export_path="$EXPORTS_DIR/upload-${APP_NAME}-${MARKETING_VERSION}-${BUILD_NUMBER}-$RUN_TIMESTAMP"
  command=(
    /usr/bin/env
  )
  if [ "$UPLOAD_BYPASS_PROXY" = "true" ]; then
    # Apple Content Delivery 会校验每个上传分片；本地 HTTP 代理可能改写响应并触发无限重试。
    command+=(
      -u HTTP_PROXY
      -u HTTPS_PROXY
      -u ALL_PROXY
      -u http_proxy
      -u https_proxy
      -u all_proxy
    )
    echo "上传网络：已绕过 HTTP/HTTPS 代理（可设置 UPLOAD_BYPASS_PROXY=false 关闭）。"
  fi
  command+=(
    /usr/bin/xcodebuild
    -exportArchive
    -archivePath "$ARCHIVE_PATH"
    -exportPath "$export_path"
    -exportOptionsPlist "$EXPORT_OPTIONS_PATH"
    ${PROVISIONING_ARGS[@]+"${PROVISIONING_ARGS[@]}"}
    ${AUTHENTICATION_ARGS[@]+"${AUTHENTICATION_ARGS[@]}"}
  )
  run_logged "上传到 App Store Connect" "$log_path" "${command[@]}"
  echo "Build 已上传到 App Store Connect。请等待 Apple 处理完成后手动配置版本并提交审核。"
}

do_upload() {
  load_latest_archive
  do_verify
  print_upload_summary
  confirm_upload
  perform_upload
}

do_release() {
  do_doctor
  do_archive
  do_verify
  print_upload_summary
  confirm_upload
  perform_upload
}

do_open() {
  if [ -f "$LATEST_ARCHIVE_FILE" ]; then
    load_latest_archive
    open "$ARCHIVE_PATH"
  else
    open "$PROJECT_PATH"
  fi
}

parse_arguments() {
  COMMAND=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --yes) YES_FLAG="true" ;;
      -h|--help) usage; exit 0 ;;
      doctor|info|clean|build|archive|export|upload|release|verify|open|schemes)
        if [ -n "$COMMAND" ]; then
          CURRENT_STEP="解析参数"
          fail "只能指定一个命令：$COMMAND 与 $1"
        fi
        COMMAND="$1"
        ;;
      *) CURRENT_STEP="解析参数"; fail "未知参数：$1" ;;
    esac
    shift
  done
  if [ -z "$COMMAND" ]; then
    COMMAND="release"
  fi
}

main() {
  parse_arguments "$@"
  load_release_config
  select_xcode
  check_xcode_version
  check_project
  check_scheme
  ensure_release_dirs

  case "$COMMAND" in
    schemes)
      do_schemes
      ;;
    info)
      do_info
      ;;
    doctor|clean|build|archive|export|upload|release|verify)
      load_project_info
      case "$COMMAND" in
        doctor) do_doctor ;;
        clean) do_clean ;;
        build) do_build ;;
        archive) do_archive ;;
        export) do_export ;;
        upload) do_upload ;;
        release) do_release ;;
        verify) do_verify ;;
      esac
      ;;
    open)
      do_open
      ;;
    *)
      usage
      CURRENT_STEP="解析命令"
      fail "未知命令：$COMMAND" 2
      ;;
  esac
}

main "$@"
