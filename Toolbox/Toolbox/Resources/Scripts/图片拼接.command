#!/bin/bash

set -u

check_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "未找到命令：$1"
    echo "请先安装后再运行。"
    exit 1
  fi
}

normalize_path() {
  local p="$1"
  p="${p%$'\r'}"

  if [[ "$p" == \"*\" && "$p" == *\" ]]; then
    p="${p:1:${#p}-2}"
  fi
  if [[ "$p" == \'*\' && "$p" == *\' ]]; then
    p="${p:1:${#p}-2}"
  fi

  if [[ "$p" == "~/"* ]]; then
    p="$HOME/${p#~/}"
  fi

  p="${p//\\ / }"
  p="${p//\\(/(}"
  p="${p//\\)/)}"
  p="${p//\\[/[}"
  p="${p//\\]/]}"

  printf '%s' "$p"
}

get_width() {
  sips -g pixelWidth "$1" 2>/dev/null | awk '/pixelWidth:/ {print $2; exit}'
}

get_height() {
  sips -g pixelHeight "$1" 2>/dev/null | awk '/pixelHeight:/ {print $2; exit}'
}

max_width_in_group() {
  local max_w=0
  local w
  local img
  for img in "$@"; do
    w="$(get_width "$img")"
    [[ -z "$w" ]] && w=0
    if (( w > max_w )); then
      max_w=$w
    fi
  done
  echo "$max_w"
}

max_height_in_group() {
  local max_h=0
  local h
  local img
  for img in "$@"; do
    h="$(get_height "$img")"
    [[ -z "$h" ]] && h=0
    if (( h > max_h )); then
      max_h=$h
    fi
  done
  echo "$max_h"
}

is_image_file() {
  local name="$1"
  local lower
  lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.jpg|*.jpeg|*.png|*.webp|*.bmp|*.tif|*.tiff) return 0 ;;
    *) return 1 ;;
  esac
}

collect_images_natural_sorted() {
  local dir="$1"

  # 大小写不敏感 + 数字自然排序
  while IFS= read -r name; do
    local full="$dir/$name"
    [[ -f "$full" ]] || continue
    if is_image_file "$name"; then
      printf '%s\n' "$full"
    fi
  done < <(
    ls -1A "$dir" | perl -e '
      sub nkey {
        my ($s) = @_;
        my @parts = split(/(\d+)/, lc($s));
        my $k = "";
        for my $p (@parts) {
          next if $p eq "";
          if ($p =~ /^\d+$/) { $k .= sprintf("0%020d", $p); }
          else { $k .= "1" . $p; }
        }
        return $k;
      }
      my @items = <STDIN>;
      chomp @items;
      print "$_\n" for sort { nkey($a) cmp nkey($b) } @items;
    '
  )
}

create_group_report_xlsx() {
  local report_tsv="$1"
  local report_xlsx="$2"
  local tmp_dir
  local row_num
  local rows_xml
  local dimension
  local name
  local pos
  local shaded
  local style
  local row_attr
  local name_escaped
  local pos_escaped

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/stack_group_xlsx.XXXXXX")" || return 1
  mkdir -p "$tmp_dir/_rels" "$tmp_dir/xl/_rels" "$tmp_dir/xl/worksheets" || {
    rm -rf "$tmp_dir"
    return 1
  }

  row_num=1
  rows_xml='<row r="1"><c r="A1" t="inlineStr"><is><t>图片名称</t></is></c><c r="B1" t="inlineStr"><is><t>位置</t></is></c></row>'
  while IFS=$'\t' read -r name pos shaded; do
    [[ -z "${name}${pos}${shaded}" ]] && continue
    row_num=$((row_num + 1))
    style=""
    row_attr=""
    if [[ "$shaded" == "1" ]]; then
      style=' s="1"'
      row_attr=' s="1" customFormat="1"'
    fi
    name_escaped="$(printf '%s' "$name" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
    pos_escaped="$(printf '%s' "$pos" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
    rows_xml="${rows_xml}<row r=\"${row_num}\"${row_attr}><c r=\"A${row_num}\"${style} t=\"inlineStr\"><is><t>${name_escaped}</t></is></c><c r=\"B${row_num}\"${style} t=\"inlineStr\"><is><t>${pos_escaped}</t></is></c></row>"
  done < "$report_tsv"

  dimension="A1:B${row_num}"

  cat > "$tmp_dir/[Content_Types].xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
EOF

  cat > "$tmp_dir/_rels/.rels" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
EOF

  cat > "$tmp_dir/xl/workbook.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="分组结果" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>
EOF

  cat > "$tmp_dir/xl/_rels/workbook.xml.rels" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
EOF

  cat > "$tmp_dir/xl/styles.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="1">
    <font><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/></font>
  </fonts>
  <fills count="3">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFE6E6E6"/><bgColor rgb="FFE6E6E6"/></patternFill></fill>
  </fills>
  <borders count="1">
    <border><left/><right/><top/><bottom/><diagonal/></border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="2">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="0" fillId="2" borderId="0" xfId="0" applyFill="1"/>
  </cellXfs>
  <cellStyles count="1">
    <cellStyle name="Normal" xfId="0" builtinId="0"/>
  </cellStyles>
</styleSheet>
EOF

  cat > "$tmp_dir/xl/worksheets/sheet1.xml" <<EOF
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <dimension ref="${dimension}"/>
  <sheetViews><sheetView workbookViewId="0"/></sheetViews>
  <sheetFormatPr defaultRowHeight="15"/>
  <cols><col min="1" max="1" width="36" customWidth="1"/><col min="2" max="2" width="12" customWidth="1"/></cols>
  <sheetData>${rows_xml}</sheetData>
</worksheet>
EOF

  rm -f "$report_xlsx"
  (
    cd "$tmp_dir" || exit 1
    zip -q -r "$report_xlsx" "[Content_Types].xml" "_rels" "xl"
  )
  local rc=$?
  rm -rf "$tmp_dir"
  return $rc
}

run_stack_group() {
  local mode="$1"
  local out_file="$2"
  shift 2
  local group=("$@")
  local max_w
  local max_h
  local ext
  local lower_ext
  local ffmpeg_args=()

  ext="${out_file##*.}"
  lower_ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
  case "$lower_ext" in
    jpg|jpeg) ffmpeg_args=(-q:v 3) ;;
    png) ffmpeg_args=(-compression_level 1) ;;
    webp) ffmpeg_args=(-compression_level 0 -q:v 80) ;;
    *) ffmpeg_args=() ;;
  esac

  if [[ "$mode" == "v2" ]]; then
    max_w="$(max_width_in_group "${group[@]}")"
    (( max_w > 0 )) || return 1
    ffmpeg -hide_banner -loglevel error -y -threads 1 \
      -i "${group[0]}" -i "${group[1]}" \
      -filter_complex "[0:v]scale=${max_w}:-2:flags=fast_bilinear[v0];[1:v]scale=${max_w}:-2:flags=fast_bilinear[v1];[v0][v1]vstack=inputs=2[out]" \
      -map "[out]" \
      "${ffmpeg_args[@]}" \
      "$out_file"
    return $?
  fi

  if [[ "$mode" == "v3" ]]; then
    max_w="$(max_width_in_group "${group[@]}")"
    (( max_w > 0 )) || return 1
    ffmpeg -hide_banner -loglevel error -y -threads 1 \
      -i "${group[0]}" -i "${group[1]}" -i "${group[2]}" \
      -filter_complex "[0:v]scale=${max_w}:-2:flags=fast_bilinear[v0];[1:v]scale=${max_w}:-2:flags=fast_bilinear[v1];[2:v]scale=${max_w}:-2:flags=fast_bilinear[v2];[v0][v1][v2]vstack=inputs=3[out]" \
      -map "[out]" \
      "${ffmpeg_args[@]}" \
      "$out_file"
    return $?
  fi

  if [[ "$mode" == "h2" ]]; then
    max_h="$(max_height_in_group "${group[@]}")"
    (( max_h > 0 )) || return 1
    ffmpeg -hide_banner -loglevel error -y -threads 1 \
      -i "${group[0]}" -i "${group[1]}" \
      -filter_complex "[0:v]scale=-2:${max_h}:flags=fast_bilinear[v0];[1:v]scale=-2:${max_h}:flags=fast_bilinear[v1];[v0][v1]hstack=inputs=2[out]" \
      -map "[out]" \
      "${ffmpeg_args[@]}" \
      "$out_file"
    return $?
  fi

  return 1
}

check_bin ffmpeg
check_bin sips
check_bin ls
check_bin zip

echo "======================================"
echo "[1] 上下 两两 拼接"
echo "[2] 上下 三三 拼接"
echo "[3] 左右 两两 拼接"
choice="${STACK_MODE_CHOICE:-}"
if [[ -z "$choice" ]]; then
  read -r -p "请输入选项 1 / 2 / 3，然后回车： " choice
else
  echo "使用配置中的模式：$choice"
fi

mode=""
group_size=0
position_labels=()

case "$choice" in
  1) mode="v2"; group_size=2; position_labels=("上" "下") ;;
  2) mode="v3"; group_size=3; position_labels=("上" "中" "下") ;;
  3) mode="h2"; group_size=2; position_labels=("左" "右") ;;
  *) echo "输入无效，程序退出。"; exit 1 ;;
esac

target_input="${TARGET_DIR:-}"
if [[ -z "$target_input" ]]; then
  echo "把待处理 图片 文件夹拖入此终端，并 回车 :"
  read -r target_input
else
  echo "使用配置中的图片文件夹：$target_input"
fi
target_dir="$(normalize_path "$target_input")"

if [[ ! -d "$target_dir" ]]; then
  echo "待处理 图片 文件夹不存在：$target_dir"
  exit 1
fi

out_dir="${OUTPUT_DIR:-${target_dir}_OUT}"
mkdir -p "$out_dir"

images=()
while IFS= read -r f; do
  images+=("$f")
done < <(collect_images_natural_sorted "$target_dir")

total=${#images[@]}
if (( total < group_size )); then
  echo "图片数量不足，至少需要 ${group_size} 张。"
  exit 1
fi

report_tsv="$(mktemp "${TMPDIR:-/tmp}/stack_group_report.XXXXXX.tsv")"
report_xlsx="${out_dir}/${REPORT_FILE_NAME:-图片分组结果.xlsx}"

processed=0
failed=0
skipped=0
i=0
batch_pids=()
batch_out_files=()
batch_groups=()
cpu_cores="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"
if ! [[ "$cpu_cores" =~ ^[0-9]+$ ]] || (( cpu_cores < 1 )); then
  cpu_cores=4
fi
max_jobs="${STACK_JOBS:-$cpu_cores}"
if ! [[ "$max_jobs" =~ ^[0-9]+$ ]] || (( max_jobs < 1 )); then
  max_jobs="$cpu_cores"
fi

flush_batch() {
  local idx
  local pid
  for idx in "${!batch_pids[@]}"; do
    pid="${batch_pids[$idx]}"
    if wait "$pid"; then
      echo "已生成：${batch_out_files[$idx]}"
      processed=$((processed + 1))
    else
      echo "拼接失败：${batch_groups[$idx]}"
      failed=$((failed + 1))
    fi
  done
  batch_pids=()
  batch_out_files=()
  batch_groups=()
}

while (( i < total )); do
  group=("${images[@]:i:group_size}")

  if (( ${#group[@]} < group_size )); then
    skipped=$((skipped + ${#group[@]}))
    break
  fi

  group_index=$((i / group_size))
  shade_flag=0
  if (( group_index % 2 == 0 )); then
    shade_flag=1
  fi

  for idx in "${!group[@]}"; do
    img_name="$(basename "${group[$idx]}")"
    pos_label="${position_labels[$idx]}"
    printf '%s\t%s\t%s\n' "$img_name" "$pos_label" "$shade_flag" >> "$report_tsv"
  done

  first_name="$(basename "${group[0]}")"
  base="${first_name%.*}"
  ext="${first_name##*.}"
  out_file="${out_dir}/${base}_LONG.${ext}"

  run_stack_group "$mode" "$out_file" "${group[@]}" &
  batch_pids+=("$!")
  batch_out_files+=("$out_file")
  batch_groups+=("${group[*]}")
  if (( ${#batch_pids[@]} >= max_jobs )); then
    flush_batch
  fi

  i=$((i + group_size))
done
if (( ${#batch_pids[@]} > 0 )); then
  flush_batch
fi

report_ok=0
if create_group_report_xlsx "$report_tsv" "$report_xlsx"; then
  report_ok=1
fi
rm -f "$report_tsv"

echo "======================================"
echo "处理完成"
echo "已生成 ${processed} 张图片"
if (( failed > 0 )); then
  echo "拼接失败 ${failed} 组"
fi
echo "输出文件夹：$out_dir"
if (( report_ok == 1 )); then
  echo "分组结果表：$report_xlsx"
else
  echo "提示：分组结果表生成失败。"
fi

if (( skipped > 0 )); then
  echo "提示：末尾不足 ${group_size} 张的 ${skipped} 张图片已跳过。"
fi

echo "👉 任务已完成"
