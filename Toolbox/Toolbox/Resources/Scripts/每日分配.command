#!/bin/bash
set -euo pipefail

FILES="${DAILY_ASSIGN_FILES:-}"
if [ -z "$FILES" ]; then
  echo "E001：未检测到 有效 报名截图"
  exit 1
fi

RES_DIR="${BASH_SOURCE[0]%/*}/.."
PY_ENTRY="$RES_DIR/Binaries/daily_assign_main.py"

if [ ! -f "$PY_ENTRY" ]; then
  echo "E005：写出 分配表 失败"
  echo "错误：未找到每日分配执行程序 daily_assign_main.py"
  exit 1
fi

exec /usr/bin/python3 "$PY_ENTRY"
