#!/bin/bash
echo "[系统] 开始执行周检制表..."

if [ -z "$BASE_FILES" ]; then
    echo "错误：请至少拖入一个基础任务分配表。"
    exit 1
fi

# 基础文件用 | 分隔
IFS='|' read -ra FILES <<< "$BASE_FILES"

echo "参数校验："
echo " - 基础文件数: ${#FILES[@]}"
echo " - 下载目录: $DOWNLOAD_DIR"
echo " - 输出目录: $OUTPUT_DIR"
echo "--------------------------------"

# 获取二进制路径 (相对于资源目录)
BIN_DIR="$(cd "$(dirname "$0")/../Binaries" && pwd)"
CHECK_BIN="$BIN_DIR/check_main_bin"

# 执行二进制，将分隔符 | 转换为空格传给 argparse
# 注意：这里我们通过 tr 把 | 换成空格，以便 argparse 接收多个文件
exec "$CHECK_BIN" \
    --base-files $(echo "$BASE_FILES" | tr '|' ' ') \
    --download-dir "$DOWNLOAD_DIR" \
    --output-file "$OUTPUT_DIR/result.xlsx"
