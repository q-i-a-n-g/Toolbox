#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILE="$SCRIPT_DIR/links.txt"
BATCH_SIZE="${BATCH_SIZE:-10}"
DEDUPE_LINKS="${DEDUPE_LINKS:-1}"

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

collect_urls() {
    local dedupe_flag="$1"
    LC_ALL=C /usr/bin/awk -v dedupe="$dedupe_flag" '
    {
      if (match($0, /(https?:\/\/[A-Za-z0-9._~:\/?#\[\]@!$&()*+,;=%-]+)/)) {
        u = substr($0, RSTART, RLENGTH)
        if (dedupe == "1") {
          if (!(u in seen)) {
            seen[u] = 1
            print u
          }
        } else {
          print u
        }
      }
    }' "$FILE"
}

urls=()
while IFS= read -r u; do
    [ -n "$u" ] && urls+=("$u")
done < <(collect_urls "$DEDUPE_LINKS")

if [ "${#urls[@]}" -eq 0 ]; then
    echo
    echo "👉 未找到有效链接。"
    exit 1
fi

total_count=0
index=0
while [ "$index" -lt "${#urls[@]}" ]; do
    remaining=$(( ${#urls[@]} - index ))
    batch_count="$BATCH_SIZE"
    if [ "$remaining" -lt "$BATCH_SIZE" ]; then
        batch_count="$remaining"
    fi

    batch=("${urls[@]:index:batch_count}")
    open "${batch[@]}"
    total_count=$((total_count + batch_count))
    index=$((index + batch_count))

    if [ "$index" -lt "${#urls[@]}" ]; then
        echo
        echo "✅ 已打开 $total_count 个链接"
        echo "👉 按 回车 继续打开下一批..."
        if ! read -r; then
            exit 0
        fi
    fi
done

echo
echo "🎉 全部完成：共打开 $total_count 个链接"
echo "👉 任务已完成"
