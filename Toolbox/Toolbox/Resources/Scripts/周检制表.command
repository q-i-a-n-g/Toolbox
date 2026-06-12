#!/bin/bash

if [ -z "$BASE_FILES" ]; then
    echo "错误：请至少拖入一个上传文件。"
    exit 1
fi

IFS='|' read -ra FILES <<< "$BASE_FILES"

echo " - 上传文件数: ${#FILES[@]}"
echo "=================================================="

CHECK_BIN="${CHECK_MAIN_BIN:-}"
if [ -z "$CHECK_BIN" ] || [ ! -x "$CHECK_BIN" ]; then
    echo "错误：未找到周检程序。请确认 App 内 Resources/Binaries/check_main_pkg/check_main_bin 存在。"
    exit 1
fi

if [ ${#FILES[@]} -eq 0 ]; then
    echo "错误：未能解析上传文件路径。"
    exit 1
fi

exec "$CHECK_BIN" \
    --base-files "${FILES[@]}" \
    --download-dir "$DOWNLOAD_DIR" \
    --output-file "$OUTPUT_DIR/AI&答题卡_check.xlsx"
