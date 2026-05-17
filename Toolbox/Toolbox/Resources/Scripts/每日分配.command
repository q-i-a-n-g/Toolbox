#!/bin/bash
set -euo pipefail

FILES="${DAILY_ASSIGN_FILES:-}"
if [ -z "$FILES" ]; then
  echo "E001：未检测到 有效 报名截图"
  exit 1
fi

RES_DIR="${BASH_SOURCE[0]%/*}/.."
PY_ENTRY="${DAILY_ASSIGN_BIN:-$RES_DIR/Binaries/check_main_pkg/daily_assign_main_bin}"

if [ ! -f "$PY_ENTRY" ]; then
  echo "E005\uff1a\u5199\u51fa \u5206\u914d\u8868 \u5931\u8d25"
  echo "\u9519\u8bef\uff1a\u672a\u627e\u5230\u6bcf\u65e5\u5206\u914d\u6267\u884c\u7a0b\u5e8f $PY_ENTRY"
  exit 1
fi

exec "$PY_ENTRY"
