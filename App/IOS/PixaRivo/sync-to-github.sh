#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$(basename "$SCRIPT_DIR")" == "scripts" ]]; then
    SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    SOURCE_DIR="$SCRIPT_DIR"
fi
DEFAULT_TARGET_DIR="/Users/jaron/Projects/Github/PixaRivo"
TARGET_DIR="${PIXARIVO_GITHUB_DIR:-$DEFAULT_TARGET_DIR}"
DRY_RUN=false
DELETE_EXTRA_FILES=false
WATCH=false
WATCH_INTERVAL=2

usage() {
    printf '%s\n' \
        "用法：$0 [--dry-run] [--delete] [--watch] [--interval 秒数]" \
        "" \
        "将当前 PixaRivo iOS 工程同步复制到 GitHub 仓库：$DEFAULT_TARGET_DIR" \
        "可通过 PIXARIVO_GITHUB_DIR 覆盖目标目录。" \
        "" \
        "选项：" \
        "  --dry-run  仅显示将要发生的变更，不写入文件" \
        "  --delete   同时删除目标中源目录不存在的文件（默认保留）" \
        "  --watch    持续监听源目录；检测到变更后自动同步，并同步删除" \
        "  --interval 监听轮询间隔（秒），默认 2"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --delete)
            DELETE_EXTRA_FILES=true
            shift
            ;;
        --watch)
            WATCH=true
            shift
            ;;
        --interval)
            [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || { usage >&2; exit 1; }
            WATCH_INTERVAL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
done

if ! command -v rsync >/dev/null 2>&1; then
    printf '%s\n' '❌ 未检测到 rsync，无法执行同步。' >&2
    exit 1
fi

if [[ ! -d "$TARGET_DIR/.git" ]]; then
    printf '❌ 目标目录不是 Git 仓库，已取消同步：%s\n' "$TARGET_DIR" >&2
    exit 1
fi

if [[ "$SOURCE_DIR" == "$TARGET_DIR" ]]; then
    printf '%s\n' '❌ 源目录与目标目录相同，已取消同步。' >&2
    exit 1
fi

# 目标仓库以当前目录为唯一来源；监听模式需要同步删除，才能使两个工作树保持一致。
if [[ "$WATCH" == true ]]; then
    DELETE_EXTRA_FILES=true
fi

RSYNC_ARGS=(
    --archive
    --human-readable
    --itemize-changes
    --exclude='.git/'
    --exclude='.DS_Store'
    --exclude='.release/'
    --exclude='DerivedData/'
    --exclude='build/'
    --exclude='xcuserdata/'
    --exclude='*.xcuserstate'
    --exclude='release-config'
    --exclude='AuthKey_*.p8'
    --exclude='*.p12'
)

if [[ "$DRY_RUN" == true ]]; then
    RSYNC_ARGS+=(--dry-run)
fi

if [[ "$DELETE_EXTRA_FILES" == true ]]; then
    # 始终保护目标仓库元数据，避免镜像同步影响 Git 历史和配置。
    RSYNC_ARGS+=(--delete --filter='P .git/')
fi

sync_once() {
    rsync "${RSYNC_ARGS[@]}" "$SOURCE_DIR/" "$TARGET_DIR/"
}

source_snapshot() {
    find "$SOURCE_DIR" \
        -path "$SOURCE_DIR/.release" -prune -o \
        -path '*/DerivedData' -prune -o \
        -path '*/build' -prune -o \
        -path '*/xcuserdata' -prune -o \
        -name '.DS_Store' -prune -o \
        -exec stat -f '%m:%z:%N' {} + 2>/dev/null | cksum
}

printf '📦 源目录：%s\n🎯 目标目录：%s\n' "$SOURCE_DIR" "$TARGET_DIR"
if [[ "$DRY_RUN" == true ]]; then
    printf '%s\n' '🔎 演练模式：不会写入文件。'
fi
if [[ "$DELETE_EXTRA_FILES" == true ]]; then
    printf '%s\n' '⚠️ 镜像模式：会删除目标中的额外文件。'
fi

sync_once
printf '%s\n' '✅ PixaRivo iOS 工程同步完成。'

if [[ "$WATCH" != true ]]; then
    exit 0
fi

printf '👀 正在监听变更（每 %s 秒检查一次）；按 Ctrl+C 停止。\n' "$WATCH_INTERVAL"
LAST_SNAPSHOT="$(source_snapshot)"
while true; do
    sleep "$WATCH_INTERVAL"
    CURRENT_SNAPSHOT="$(source_snapshot)"
    if [[ "$CURRENT_SNAPSHOT" == "$LAST_SNAPSHOT" ]]; then
        continue
    fi

    printf '%s\n' '🔄 检测到 PixaRivo iOS 工程变更，正在同步...'
    sync_once
    LAST_SNAPSHOT="$CURRENT_SNAPSHOT"
    printf '%s\n' '✅ 自动同步完成。'
done
