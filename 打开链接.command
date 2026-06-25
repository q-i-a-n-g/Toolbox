#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILE="$SCRIPT_DIR/links.txt"
BATCH_SIZE=10

if [ ! -f "$FILE" ]; then
    echo "❌ 文件不存在: $FILE"
    exit 1
fi

if ! grep -q '[^[:space:]]' "$FILE"; then
    exit 1
fi

extract_url() {
    printf '%s\n' "$1" | LC_ALL=C /usr/bin/perl -ne 'if (m{(https?://[A-Za-z0-9._~:/?#\[\]@!$&()*+,;=%-]+)}) { print "$1\n"; exit }'
}

exec 3< "$FILE"

batch_count=0
total_count=0

while IFS= read -r line <&3 || [ -n "$line" ]; do

    trimmed=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    [ -z "$trimmed" ] && continue
    url="$(extract_url "$trimmed")"
    [ -z "$url" ] && continue

    open "$url" &

    # 极短顺序节流，保证浏览器按顺序接收
    sleep 0.02

    batch_count=$((batch_count + 1))
    total_count=$((total_count + 1))

    if [ "$batch_count" -eq "$BATCH_SIZE" ]; then
        echo
        echo "✅ 已打开 $total_count 个链接"
        echo "👉 按回车继续打开下一批..."
        read -r
        batch_count=0
    fi

done

exec 3<&-

echo
echo "🎉 全部完成：共打开 $total_count 个链接"
echo
