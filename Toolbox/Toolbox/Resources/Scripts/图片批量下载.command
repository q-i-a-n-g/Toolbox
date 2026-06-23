#!/bin/bash

# Default input: links.txt in the same folder as this script
# Default output directory: $HOME/Downloads
#   links.txt文件内容：
#       http://...
#       http://...
#       http://...
#       ...
#   或者是这样的：
#   11  http://...
#   23  http://...
#   35  http://...
#   ...
#   也支持：
#   http://...  34
#   http://...  67
#   http://...  abc
#   ...
# 说明：链接前后的数字或文字都可作为重命名，若两边同时存在则优先使用链接前内容。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT_FILE="${1:-$SCRIPT_DIR/links.txt}"
OUTPUT_DIR="${2:-${OUTPUT_DIR:-$HOME/Downloads}}"

if [ ! -f "$INPUT_FILE" ]; then
  echo "未找到文件: $INPUT_FILE"
  exit 1
fi

if [ "$INPUT_FILE" = "$SCRIPT_DIR/links.txt" ] && ! grep -q '[^[:space:]]' "$INPUT_FILE"; then
  echo ""
  echo " 👉  上方的 文本框 是空的，给它添加一些链接。"
  exit 1
fi

mkdir -p "$OUTPUT_DIR" 2>/dev/null || {
  echo "无法创建下载目录: $OUTPUT_DIR"
  exit 1
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

sanitize_name() {
  local name="$1"
  name="$(printf '%s' "$name" | sed 's#[/:*?"<>|]#_#g')"
  name="$(printf '%s' "$name" | sed 's/[[:space:]]\+/_/g')"
  name="$(printf '%s' "$name" | sed 's/^\.*//')"
  [ -z "$name" ] && name="image"
  printf '%s' "$name"
}

extract_url() {
  # Extract first URL and tolerate surrounding garbage text.
  # Use perl for better compatibility on macOS default tools.
  printf '%s\n' "$1" | LC_ALL=C /usr/bin/perl -ne 'if (m{(https?://[A-Za-z0-9._~:/?#\[\]@!$&()*+,;=%-]+)}) { print "$1\n"; exit }'
}

url_basename() {
  local url="$1"
  local no_q="${url%%\?*}"
  no_q="${no_q%%\#*}"
  local base="${no_q##*/}"
  [ -z "$base" ] && base="image"
  printf '%s' "$base"
}

contains_url() {
  local target="$1"
  local i
  for ((i = 0; i < ${#UNIQUE_URLS[@]}; i++)); do
    if [ "${UNIQUE_URLS[$i]}" = "$target" ]; then
      return 0
    fi
  done
  return 1
}

build_unique_path() {
  local dir="$1"
  local filename="$2"
  local name="$filename"
  local ext=""
  local n=1
  local candidate

  if [[ "$filename" == *.* && "$filename" != .* ]]; then
    ext=".${filename##*.}"
    name="${filename%.*}"
  fi

  candidate="$dir/$filename"
  while [ -e "$candidate" ]; do
    candidate="$dir/${name}_$n$ext"
    n=$((n + 1))
  done
  printf '%s' "$candidate"
}

terminal_link_path() {
  local path="$1"
  local rest
  if [[ "$path" == "$HOME/Downloads" || "$path" == "$HOME/Downloads/"* ]]; then
    rest="${path#$HOME/Downloads}"
    rest="${rest#/}"
    if [ -n "$rest" ]; then
      printf 'Download/%s' "$rest"
    else
      printf 'Download/'
    fi
    return
  fi
  if [[ "$path" == "$HOME/Desktop" || "$path" == "$HOME/Desktop/"* ]]; then
    rest="${path#$HOME/Desktop}"
    rest="${rest#/}"
    if [ -n "$rest" ]; then
      printf 'Desktop/%s' "$rest"
    else
      printf 'Desktop/'
    fi
    return
  fi
  if command -v /usr/bin/python3 >/dev/null 2>&1; then
    /usr/bin/python3 - "$path" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).expanduser().resolve().as_uri())
PY
  else
    printf '%s' "$path"
  fi
}

UNIQUE_URLS=()
FAILED_URLS=()
ALL_URLS=()
ALL_NAME_TAGS=()
SKIPPED_COUNT=0

while IFS= read -r line || [ -n "$line" ]; do
  [ -z "$(trim "$line")" ] && continue

  url="$(extract_url "$line")"
  [ -z "$url" ] && continue

  left_part="$(printf '%s\n' "$line" | awk -v u="$url" '{p=index($0,u); if (p > 1) print substr($0,1,p-1)}')"
  left_part="$(trim "$left_part")"
  right_part="$(printf '%s\n' "$line" | awk -v u="$url" '{p=index($0,u); if (p > 0) print substr($0,p+length(u))}')"
  right_part="$(trim "$right_part")"

  name_tag="$left_part"
  if [ -z "$name_tag" ]; then
    name_tag="$right_part"
  fi

  ALL_URLS+=("$url")
  ALL_NAME_TAGS+=("$name_tag")
done < "$INPUT_FILE"

TOTAL=${#ALL_URLS[@]}
if [ "$TOTAL" -eq 0 ]; then
  echo "未找到可下载的有效链接。"
  exit 0
fi

SUCCESS=0
DONE=0

for ((i = 0; i < TOTAL; i++)); do
  url="${ALL_URLS[$i]}"
  name_tag="${ALL_NAME_TAGS[$i]}"

  if contains_url "$url"; then
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    DONE=$((DONE + 1))
    echo "已下载：$DONE/$TOTAL"
    continue
  fi

  UNIQUE_URLS+=("$url")

  original_name="$(url_basename "$url")"

  if [ -n "$name_tag" ]; then
    safe_prefix="$(sanitize_name "$name_tag")"
    if [[ "$safe_prefix" == *.* ]]; then
      filename="$safe_prefix"
    else
      if [[ "$original_name" == *.* && "$original_name" != .* ]]; then
        filename="$safe_prefix.${original_name##*.}"
      else
        filename="$safe_prefix"
      fi
    fi
  else
    filename="$original_name"
  fi

  save_path="$(build_unique_path "$OUTPUT_DIR" "$filename")"

  if curl -fL --connect-timeout 15 --max-time 120 --retry 2 -o "$save_path" "$url" >/dev/null 2>&1; then
    SUCCESS=$((SUCCESS + 1))
  else
    FAILED_URLS+=("$url")
    [ -f "$save_path" ] && rm -f "$save_path"
  fi

  DONE=$((DONE + 1))
  echo "已下载：$DONE/$TOTAL"
done

echo "=============================="
echo "👉 下载目录：$(terminal_link_path "$OUTPUT_DIR")"
echo "成功：$SUCCESS"
echo "失败：${#FAILED_URLS[@]}"
echo "跳过重复的：$SKIPPED_COUNT"
echo "=============================="

if [ "${#FAILED_URLS[@]}" -gt 0 ]; then
  echo "下载失败的链接："
  for url in "${FAILED_URLS[@]}"; do
    echo "$url"
  done
fi

echo "👉 任务已完成"
