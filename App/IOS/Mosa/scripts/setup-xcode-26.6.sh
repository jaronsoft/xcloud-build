#!/bin/bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_VERSION="26.6"
EXPECTED_BUILD="17F113"
DEFAULT_INSTALL_DIR="/Applications"
CHECK_ONLY="false"
INSTALL_RUNTIME="true"
YES_FLAG="false"

usage() {
  cat <<'EOF'
用法：
  ./scripts/setup-xcode-26.6.sh
  ./scripts/setup-xcode-26.6.sh --check
  ./scripts/setup-xcode-26.6.sh [--yes] [--skip-runtime]

用途：
  在保留 Xcode 27 的同时，检测或并存安装 Xcode 26.6 (17F113)。

选项：
  --check         只检测，不安装或修改环境
  --yes           跳过安装前确认
  --skip-runtime  不下载 Xcode 26.6 对应的 iOS Simulator Runtime
EOF
}

check_macos_version() {
  local product_version
  local major
  local minor

  product_version="$(/usr/bin/sw_vers -productVersion)"
  major="${product_version%%.*}"
  minor="${product_version#*.}"
  minor="${minor%%.*}"
  if [ "$major" -lt 26 ] || { [ "$major" -eq 26 ] && [ "$minor" -lt 2 ]; }; then
    echo "错误：Xcode 26.6 要求 macOS 26.2 或更高，当前为 $product_version。" >&2
    exit 1
  fi
  echo "macOS 版本：$product_version"
}

xcode_version_at() {
  local app_path="$1"
  DEVELOPER_DIR="$app_path/Contents/Developer" /usr/bin/xcodebuild -version 2>/dev/null || true
}

is_expected_xcode() {
  local app_path="$1"
  local output
  local version
  local build

  [ -d "$app_path/Contents/Developer" ] || return 1
  output="$(xcode_version_at "$app_path")"
  version="$(printf '%s\n' "$output" | sed -n '1s/^Xcode //p')"
  build="$(printf '%s\n' "$output" | sed -n '2s/^Build version //p')"
  [ "$version" = "$EXPECTED_VERSION" ] && [ "$build" = "$EXPECTED_BUILD" ]
}

find_expected_xcode() {
  local candidate

  if [ -n "${MOSA_XCODE_APP_PATH:-}" ] && is_expected_xcode "$MOSA_XCODE_APP_PATH"; then
    printf '%s\n' "$MOSA_XCODE_APP_PATH"
    return 0
  fi

  for candidate in \
    "$DEFAULT_INSTALL_DIR/Xcode-26.6.app" \
    "$DEFAULT_INSTALL_DIR/Xcode-26.6.0.app" \
    "$DEFAULT_INSTALL_DIR/Xcode.app"; do
    if is_expected_xcode "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  while IFS= read -r candidate; do
    if is_expected_xcode "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(/usr/bin/find "$DEFAULT_INSTALL_DIR" -maxdepth 1 -type d -name 'Xcode*.app' -print 2>/dev/null)
  return 1
}

confirm_install() {
  local answer
  if [ "$YES_FLAG" = "true" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    echo "错误：非交互环境请添加 --yes。" >&2
    exit 1
  fi
  echo "将通过 xcodes 下载并安装 Xcode ${EXPECTED_VERSION}，保留现有 Xcode 27。"
  echo "安装过程需要 Apple Developer 登录、较长下载时间、足够磁盘空间和管理员密码。"
  printf '继续吗？[y/N] '
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "已取消。"; exit 1 ;;
  esac
}

ensure_xcodes() {
  if command -v xcodes >/dev/null 2>&1; then
    return 0
  fi
  if ! command -v brew >/dev/null 2>&1; then
    echo "错误：未安装 xcodes，且未找到 Homebrew。" >&2
    echo "请从 Apple Developer Downloads 手动下载 Xcode 26.6，解压为 /Applications/Xcode-26.6.app，随后重新运行本脚本。" >&2
    echo "Apple 下载页：https://developer.apple.com/download/all/" >&2
    exit 1
  fi
  echo "正在通过 Homebrew 安装 xcodes..."
  brew install xcodesorg/made/xcodes
}

finish_xcode_setup() {
  local app_path="$1"
  local developer_dir="$app_path/Contents/Developer"
  local architecture
  local runtime_list

  echo "正在完成 Xcode 首次启动组件安装..."
  sudo /usr/bin/env DEVELOPER_DIR="$developer_dir" /usr/bin/xcodebuild -runFirstLaunch

  if [ "$INSTALL_RUNTIME" != "true" ]; then
    return 0
  fi

  runtime_list="$(DEVELOPER_DIR="$developer_dir" /usr/bin/xcrun simctl list runtimes 2>/dev/null || true)"
  if printf '%s\n' "$runtime_list" | grep -E 'iOS 26\.5 ' | grep -vq 'unavailable'; then
    echo "iOS 26.5 Simulator Runtime 已安装。"
    return 0
  fi

  if [ "$(/usr/bin/uname -m)" = "arm64" ]; then
    architecture="arm64"
  else
    architecture="universal"
  fi
  echo "正在下载并安装 Xcode 26.6 对应的 iOS Runtime..."
  DEVELOPER_DIR="$developer_dir" /usr/bin/xcodebuild \
    -downloadPlatform iOS \
    -architectureVariant "$architecture"
}

parse_arguments() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --check) CHECK_ONLY="true" ;;
      --yes) YES_FLAG="true" ;;
      --skip-runtime) INSTALL_RUNTIME="false" ;;
      -h|--help) usage; exit 0 ;;
      *) echo "错误：未知参数 $1" >&2; usage; exit 2 ;;
    esac
    shift
  done
}

main() {
  local app_path

  parse_arguments "$@"
  check_macos_version
  if app_path="$(find_expected_xcode)"; then
    echo "已找到 Xcode ${EXPECTED_VERSION} (${EXPECTED_BUILD})：$app_path"
  else
    if [ "$CHECK_ONLY" = "true" ]; then
      echo "未找到 Xcode ${EXPECTED_VERSION} (${EXPECTED_BUILD})。" >&2
      exit 1
    fi
    confirm_install
    ensure_xcodes
    echo "正在安装 Xcode ${EXPECTED_VERSION} 到 $DEFAULT_INSTALL_DIR..."
    xcodes install "$EXPECTED_VERSION" --directory "$DEFAULT_INSTALL_DIR"
    if ! app_path="$(find_expected_xcode)"; then
      echo "错误：安装完成后仍未找到 Xcode ${EXPECTED_VERSION} (${EXPECTED_BUILD})。" >&2
      exit 1
    fi
  fi

  if [ "$CHECK_ONLY" = "true" ]; then
    exit 0
  fi

  finish_xcode_setup "$app_path"
  echo
  echo "Xcode 26.6 环境准备完成：$app_path"
  echo "未修改全局 xcode-select，也未删除或覆盖 Xcode 27。"
  echo "现在可执行：./scripts/ios-release.sh doctor"
}

main "$@"
