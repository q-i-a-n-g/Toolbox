#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PY="$ROOT/Toolbox/Resources/Binaries/daily_assign_main.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$ROOT/../每日分配/AI_待分配.xlsx" "$TMP/AI_待分配.xlsx"
cp "$ROOT/../每日分配/答题卡_待分配.xlsx" "$TMP/答题卡_待分配.xlsx"
cp "$ROOT/../每日分配/AI.png" "$TMP/王哲12.png"

# case1: only screenshot + mock download success
OUT1="$TMP/out1"
mkdir -p "$OUT1" "$TMP/dl1"
set +e
DAILY_ASSIGN_FILES="$TMP/王哲12.png" \
NAMES="王哲,李橙橙" \
DAILY_ASSIGN_DOWNLOAD_MODE=mock \
DAILY_ASSIGN_MOCK_AI_SOURCE="$TMP/AI_待分配.xlsx" \
DAILY_ASSIGN_MOCK_CARD_SOURCE="$TMP/答题卡_待分配.xlsx" \
DOWNLOAD_DIR="$TMP/dl1" \
OUTPUT_DIR="$OUT1" \
/usr/bin/python3 "$PY" >"$TMP/case1.log" 2>&1
RC1=$?
set -e
[ $RC1 -eq 0 ]
[ -f "$OUT1/分配表.xlsx" ]
rg -n "任务已完成" "$TMP/case1.log" >/dev/null

# case2: only screenshot + disabled download => E002
OUT2="$TMP/out2"
mkdir -p "$OUT2" "$TMP/dl2"
set +e
DAILY_ASSIGN_FILES="$TMP/王哲12.png" \
NAMES="王哲,李橙橙" \
DAILY_ASSIGN_DOWNLOAD_MODE=disabled \
DOWNLOAD_DIR="$TMP/dl2" \
OUTPUT_DIR="$OUT2" \
/usr/bin/python3 "$PY" >"$TMP/case2.log" 2>&1
RC2=$?
set -e
[ $RC2 -ne 0 ]
rg -n "E002" "$TMP/case2.log" >/dev/null

echo "daily-assign tests passed"
