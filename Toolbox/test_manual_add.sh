#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PY="$ROOT/Toolbox/Resources/Binaries/daily_assign_main.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$ROOT/../每日分配/AI_待分配.xlsx" "$TMP/AI_待分配.xlsx"
cp "$ROOT/../每日分配/答题卡_待分配.xlsx" "$TMP/答题卡_待分配.xlsx"
cp "$ROOT/../每日分配/AI.png" "$TMP/test.png"

# We simulate that OCR found 1 person, but confirmed_signup has 2 people.
OUT="$TMP/out"
mkdir -p "$OUT" "$TMP/dl"

DAILY_ASSIGN_FILES="$TMP/test.png" \
NAMES="王哲,李橙橙" \
DAILY_ASSIGN_DOWNLOAD_MODE=mock \
DAILY_ASSIGN_MOCK_AI_SOURCE="$TMP/AI_待分配.xlsx" \
DAILY_ASSIGN_MOCK_CARD_SOURCE="$TMP/答题卡_待分配.xlsx" \
DOWNLOAD_DIR="$TMP/dl" \
OUTPUT_DIR="$OUT" \
DAILY_ASSIGN_PREVIEW_ONLY="0" \
DAILY_ASSIGN_CONFIRMED_SIGNUP="王哲:5|李橙橙:3" \
/usr/bin/python3 "$PY" > "$TMP/test.log" 2>&1

cat "$TMP/test.log"
