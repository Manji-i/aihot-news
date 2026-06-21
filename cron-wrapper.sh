#!/bin/bash
# cron wrapper — 加载 config.sh 后执行 poll.sh
# 用于 crontab 定时任务，确保 lark-cli 能在 cron PATH 中找到
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "⚠️  未找到 config.sh，请先复制 config.sh.example 并填入你的配置："
    echo "   cp $SCRIPT_DIR/config.sh.example $SCRIPT_DIR/config.sh"
    exit 1
fi

# 确保常用工具路径在 cron 环境中可用
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

exec "$SCRIPT_DIR/poll.sh"
