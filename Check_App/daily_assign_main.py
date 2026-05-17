#!/usr/bin/env python3
from __future__ import annotations
import os
import re
import shutil
import sys
import random
import urllib.request
import subprocess
import warnings
import zipfile
import time
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path
from typing import List, Dict, Tuple

# Suppress openpyxl UserWarning
warnings.filterwarnings("ignore", category=UserWarning, module='openpyxl')

from openpyxl import load_workbook, Workbook
from openpyxl.styles import PatternFill

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    sync_playwright = None

IMG_EXT = {"png", "jpg", "jpeg", "webp", "heic"}
XLS_EXT = {"xlsx", "xls"}
REQ_HEADERS = {"子任务ID", "总页数", "总评测数量"}


@dataclass
class TaskRow:
    order: int
    cols: List
    subtask_id: str
    pages: float
    tags: float


def split_files(raw: str) -> list[Path]:
    out = []
    seen = set()
    for part in raw.split("|"):
        p = Path(part.strip())
        if not part.strip() or part in seen:
            continue
        seen.add(part)
        if p.exists() and p.is_file():
            out.append(p)
    return out


def has_required_headers(path: Path) -> bool:
    try:
        if path.stat().st_size < 1000: return False
        wb = load_workbook(path, data_only=True)
        ws = wb.worksheets[0]
        for r in range(1, min(20, ws.max_row) + 1):
            for c_start in range(1, 10):
                vals = {str(ws.cell(r, c).value or "").strip() for c in range(c_start, c_start + 11)}
                if REQ_HEADERS.issubset(vals):
                    return True
    except Exception:
        return False
    return False


def classify(files: list[Path]):
    shots = []
    ai = None
    card = None
    others = []
    for f in files:
        ext = f.suffix.lower().lstrip(".")
        name = f.name
        if ext in IMG_EXT:
            shots.append(f)
        elif ext in XLS_EXT:
            if ai is None and "AI_待分配" in name:
                ai = f
            elif card is None and "答题卡_待分配" in name:
                card = f
            else:
                others.append(f)

    valid_others = [x for x in others if has_required_headers(x)]
    if ai is None and valid_others:
        ai = valid_others.pop(0)
    if card is None and valid_others:
        card = valid_others.pop(0)
    return shots, ai, card


def mock_download(ai_target: Path, card_target: Path) -> bool:
    ai_src = os.environ.get("DAILY_ASSIGN_MOCK_AI_SOURCE", "").strip()
    card_src = os.environ.get("DAILY_ASSIGN_MOCK_CARD_SOURCE", "").strip()
    if not ai_src or not card_src:
        return False
    ai_s, card_s = Path(ai_src), Path(card_src)
    if not ai_s.exists() or not card_s.exists():
        return False
    shutil.copy2(ai_s, ai_target)
    shutil.copy2(card_s, card_target)
    return True


def _download_one_table(page, url: str, task_name: str, target: Path, label: str) -> bool:
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=30000)
    except:
        return False
    
    page.bring_to_front()
    
    # 1. Input Task Name
    input_sel = 'input#name'
    try:
        page.wait_for_selector(input_sel, timeout=10000)
        page.fill(input_sel, task_name)
    except Exception:
        try: page.fill('input[placeholder*="任务名"]', task_name)
        except:
            print(f"E002：无法在 {label} 页面输入任务名")
            return False
            
    # 2. Click Search (搜 索)
    try:
        page.click('button:has-text("搜 索")', timeout=5000)
        page.wait_for_timeout(1500)
    except:
        pass 
        
    # 3. Click Export (导 出)
    try:
        page.click('button:has-text("导 出")', timeout=10000)
    except:
        print(f"E002：{label} 未找到导出按钮")
        return False
        
    # 4. Click Confirm (确 定) in Modal and trigger download
    try:
        page.wait_for_timeout(1500) 
        confirm_sel = '.ant-modal-footer button.ant-btn-primary'
        with page.expect_download(timeout=30000) as download_info:
            try:
                page.wait_for_selector(confirm_sel, timeout=5000)
                page.click(confirm_sel, force=True)
            except:
                try: page.click('button:has-text("确 定")', force=True)
                except: page.click('button:has-text("确定")', force=True)
        
        download = download_info.value
        new_file = download.path()
        
        # Settle period to ensure OS completes write
        time.sleep(1)
        
        # Verify file integrity and size
        if not zipfile.is_zipfile(new_file) or os.path.getsize(new_file) < 2000:
            time.sleep(2) # Final retry wait
            if not zipfile.is_zipfile(new_file):
                print(f"E002：{label} 表格下载损坏或内容为空 (Invalid Zip)")
                return False
                
        # Save result
        if os.path.exists(str(target)): os.remove(str(target))
        shutil.copy(new_file, str(target))
        print(f"[下载] {label} 任务表格下载成功 ✅")
        return True
    except Exception as e:
        print(f"E002：{label} 触发下载或保存失败 ({e})")
        return False


def real_download(ai_target: Path, card_target: Path, ai_task: str, card_task: str) -> bool:
    user_data_dir = os.path.expanduser("~/.gemini/NewApp_chrome_profile")
    chrome_path = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if sync_playwright is None:
        print("E002：Playwright 未安装。")
        return False
    if not os.path.exists(chrome_path):
        print(f"E002：找不到 Chrome 路径: {chrome_path}")
        return False
    if not os.path.exists(user_data_dir): os.makedirs(user_data_dir, exist_ok=True)

    try:
        with sync_playwright() as p:
            browser_context = p.chromium.launch_persistent_context(
                user_data_dir=user_data_dir, executable_path=chrome_path,
                headless=False, no_viewport=True, args=["--remote-debugging-port=9222", "--start-maximized"]
            )
            page = browser_context.pages[0] if browser_context.pages else browser_context.new_page()
            ok1 = _download_one_table(page, "https://mapi.yuanfudao.com/evaluation/#/admin/evaluation/holepage", ai_task, ai_target, "AI")
            ok2 = _download_one_table(page, "https://mapi.yuanfudao.com/evaluation/#/admin/evaluation/card", card_task, card_target, "答题卡")
            browser_context.close()
            return ok1 and ok2
    except Exception as e:
        print(f"E002：自动下载过程异常 ({e})")
        return False


def to_num(v) -> float:
    try:
        if v is None: return 0.0
        return float(v)
    except: return 0.0


def read_tasks(path: Path, cap: int) -> Tuple[List[str], List[TaskRow]]:
    wb = load_workbook(path, data_only=True)
    ws = wb.worksheets[0]
    header_row, start_col = None, 3
    header_idx, source_headers = {}, []
    for r in range(1, min(50, ws.max_row) + 1):
        found = False
        for c_start in [3, 1, 2, 4, 5]:
            vals = [str(ws.cell(r, c).value or "").strip() for c in range(c_start, c_start + 11)]
            if REQ_HEADERS.issubset(set(vals)):
                header_row, start_col, source_headers = r, c_start, vals
                for i, v in enumerate(vals, start=c_start):
                    if v: header_idx[v] = i
                found = True
                break
        if found: break
    if header_row is None:
        header_row, start_col = 1, 3
        source_headers = [str(ws.cell(1, c).value or "").strip() for c in range(3, 14)]
        for i, v in enumerate(source_headers, start=3):
            if v: header_idx[v] = i
    out: List[TaskRow] = []
    order = 0
    idx_id = header_idx.get("子任务ID", start_col + 1)
    idx_pages = header_idx.get("总页数", start_col + 7)
    idx_tags = header_idx.get("总评测数量", start_col + 8)
    for r in range(header_row + 1, ws.max_row + 1):
        subtask = str(ws.cell(r, idx_id).value or "").strip()
        pages = to_num(ws.cell(r, idx_pages).value)
        tags = to_num(ws.cell(r, idx_tags).value)
        if not subtask or (pages <= 0 and tags <= 0): continue
        cols = [ws.cell(r, c).value for c in range(start_col, start_col + 11)]
        out.append(TaskRow(order=order, cols=cols, subtask_id=subtask, pages=pages, tags=tags))
        order += 1
    rnd = random.Random(int(date.today().strftime("%Y%m%d")))
    rnd.shuffle(out)
    picked, s = [], 0.0
    for row in out:
        if not picked:
            picked.append(row); s += row.pages; continue
        if s + row.pages <= cap:
            picked.append(row); s += row.pages
        if cap > 0 and s / cap >= 0.98: break
    return source_headers, picked


def lev(a: str, b: str) -> int:
    if a == b: return 0
    if not a: return len(b)
    if not b: return len(a)
    dp = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        prev = dp[0]; dp[0] = i
        for j, cb in enumerate(b, 1):
            cur = dp[j]
            dp[j] = min(dp[j] + 1, dp[j - 1] + 1, prev + (0 if ca == cb else 1))
            prev = cur
    return dp[-1]


def normalize_name(raw: str, names: List[str]) -> str | None:
    # 1. Basic cleaning
    raw = raw.replace(" ", "").strip()
    if not raw: return None
    if raw in names: return raw
    
    # 2. Hardcode common OCR misreadings
    ocr_map = {"符手娜": "符于娜", "刘兩菲": "刘雨菲", "阎思宇": "阎思宇"}
    if raw in ocr_map:
        mapped = ocr_map[raw]
        if mapped in names: return mapped

    # 3. Clean symbols and normalize
    raw_clean = "".join(re.findall(r"[\u4e00-\u9fa5]", raw))
    if "兩" in raw_clean: raw_clean = raw_clean.replace("兩", "雨")
    if "手" in raw_clean and len(raw_clean) == 3 and raw_clean.startswith("符"): 
        raw_clean = raw_clean.replace("手", "于")

    target_clean, spec_target = "韩正", "韩@“”正"
    if raw_clean == target_clean:
        if spec_target in names: return spec_target
        if target_clean in names: return target_clean
        
    # 4. Levenshtein edit distance
    cands = []
    for n in names:
        n_clean = n.replace("@“”", "")
        d = lev(raw_clean, n_clean)
        if d <= 1: cands.append((d, n))
    cands.sort(key=lambda x: x[0])
    if cands:
        if len(cands) == 1 or cands[1][0] > cands[0][0]: return cands[0][1]
    return None


def run_vision_ocr(image_path: Path) -> str:
    script_env = os.environ.get("OCR_VISION_SCRIPT", "").strip()
    script = Path(script_env) if script_env else Path(__file__).with_name("ocr_vision.swift")
    if not script.exists(): return ""
    try:
        p = subprocess.run(["/usr/bin/swift", str(script), str(image_path)], capture_output=True, text=True, timeout=30)
        return p.stdout if p.returncode == 0 else ""
    except: return ""


def parse_signup_from_shots(shots: List[Path], names: List[str]) -> Tuple[Dict[str, int], List[str], List[str]]:
    out, unmatched, order = {}, [], []
    noise = {"所有人", "完成", "周五", "周一", "周二", "周三", "周四", "周六", "周日", "评测", "比例", "请大家", "今天", "任务", "表格", "下载", "报名", "自动", "👉", "人数", "约有", "需在"}
    for shot in shots:
        text_file = shot.with_suffix(".txt")
        text = text_file.read_text(encoding="utf-8", errors="ignore") if text_file.exists() else run_vision_ocr(shot)
        for raw_name, cnt_s in re.findall(r"([\u4e00-\u9fa5@\u201c\u201d\u2018\u2019\u0022\u0027\s]{2,12})[^\d\u4e00-\u9fa5]{0,10}(\d+)", text):
            norm = normalize_name(raw_name, names)
            if not norm:
                pure = "".join(re.findall(r"[\u4e00-\u9fa5]", raw_name))
                if len(pure) < 2 or len(pure) > 6 or any(n in pure for n in noise): continue
                if not any(lev(pure, n.replace("@“”", "")) <= 2 for n in names): continue
                if pure not in unmatched and pure not in out: unmatched.append(pure)
                continue
            cnt = int(cnt_s)
            if cnt > 0:
                if norm not in out: order.append(norm)
                out[norm] = cnt
                if norm in unmatched: unmatched.remove(norm)
    return out, unmatched, order


def assign(tasks: List[TaskRow], signup: Dict[str, int], weight_key: str, carry: Dict[str, float] | None = None):
    names = sorted(signup.keys())
    total_signup = sum(signup.values())
    target_ratio = {n: signup[n] / total_signup for n in names}
    assigned_weight = {n: 0.0 for n in names}
    assigned_count = {n: 0 for n in names}
    if carry:
        for n in names: assigned_weight[n] += carry.get(n, 0.0)
    result, total_w = [], 0.0
    for t in tasks:
        w = t.pages if weight_key == "page" else t.tags
        if w <= 0: w = 1.0
        total_w += w
        best, best_key = None, None
        for n in names:
            debt = target_ratio[n] * max(total_w, 1.0) - assigned_weight[n]
            key = (debt, -assigned_count[n], n)
            if best is None or key > best_key: best, best_key = n, key
        assigned_weight[best] += w
        assigned_count[best] += 1
        result.append([t, best])
    owner_tasks = {n: [] for n in names}
    for i, (t, owner) in enumerate(result): owner_tasks[owner].append(i)
    for _ in range(2000):
        changed = False
        current_total_w = sum(assigned_weight.values())
        if current_total_w <= 0: break
        devs = []
        for n in names:
            ratio = assigned_weight[n] / current_total_w
            devs.append((ratio - target_ratio[n], n))
        devs.sort()
        if all(abs(d[0]) <= 0.02 for d in devs): break
        min_p, max_p = devs[0][1], devs[-1][1]
        best_move_idx, best_reduction = -1, 0
        for i in owner_tasks[max_p]:
            task, _ = result[i]
            w = task.pages if weight_key == "page" else task.tags
            old_dist = abs(assigned_weight[max_p]/current_total_w - target_ratio[max_p]) + abs(assigned_weight[min_p]/current_total_w - target_ratio[min_p])
            new_dist = abs((assigned_weight[max_p]-w)/current_total_w - target_ratio[max_p]) + abs((assigned_weight[min_p]+w)/current_total_w - target_ratio[min_p])
            if new_dist < old_dist:
                reduction = old_dist - new_dist
                if reduction > best_reduction: best_reduction, best_move_idx = reduction, i
        if best_move_idx != -1:
            task, old_owner = result[best_move_idx]
            w = task.pages if weight_key == "page" else task.tags
            assigned_weight[old_owner] -= w; assigned_weight[min_p] += w
            result[best_move_idx][1] = min_p
            owner_tasks[old_owner].remove(best_move_idx); owner_tasks[min_p].append(best_move_idx)
            changed = True
        if not changed: break
    grouped = {n: [] for n in names}
    for item in result: grouped[item[1]].append(tuple(item))
    final = []
    for n in names: final.extend(grouped[n])
    return final, assigned_weight


def ai_task_name(today: date) -> str:
    return "260511-260512"


def card_task_name(today: date) -> str:
    return "0507-0513答题卡周期评测"


def delivery_text(today: date) -> str:
    tomorrow = today + timedelta(days=1)
    if today.weekday() == 4: tomorrow = today + timedelta(days=3)
    text = f"{tomorrow.month}月{tomorrow.day}日"
    if tomorrow.weekday() == 3: text += " 14:00"
    return text


def period_text(today: date) -> str:
    if today.day >= 25:
        start = today.replace(day=25)
        end = date(today.year + (1 if today.month == 12 else 0), (today.month % 12) + 1, 24)
    else:
        start = date(today.year - (1 if today.month == 1 else 0), 12 if today.month == 1 else today.month - 1, 25)
        end = today.replace(day=24)
    return f"{start.month:02d}{start.day:02d}-{end.month:02d}{end.day:02d}"


def write_sheet(ws, source_headers: List[str], rows, today: date):
    headers = ["周期"] + source_headers + ["负责人", "交付日期", "完成情况", "特殊备注", "检查人", "问责", "是否已修改", "报名截图"]
    ws.append(headers)
    yellow = PatternFill(fill_type="solid", fgColor="FFF4B084")
    for c in "EJK": ws[f"{c}1"].fill = yellow
    ws.auto_filter.ref = f"A1:{chr(64+len(headers))}1"
    period, delivery = period_text(today), delivery_text(today)
    for task, owner in rows:
        excel_owner = owner.replace("韩@“”正", "韩正")
        ws.append([period] + task.cols + [excel_owner, delivery, "", "", "", "", "", ""])


def main() -> int:
    try: sys.stdout.reconfigure(encoding='utf-8')
    except: pass
    files = split_files(os.environ.get("DAILY_ASSIGN_FILES", ""))
    shots, ai, card = classify(files)
    if not shots:
        print("E001：未检测到 有效 报名截图"); return 1
    dl_dir = Path(os.environ.get("DOWNLOAD_DIR", str(Path.home() / "Downloads")))
    dl_dir.mkdir(parents=True, exist_ok=True)
    if ai is None and card is None:
        print("[下载] 检测到仅上传截图，开始自动下载今日任务表...")
        print(f"[下载] AI任务名: {ai_task_name(date.today())}")
        print(f"[下载] 答题卡任务名: {card_task_name(date.today())}")
        ai_path, card_path = dl_dir / "AI_待分配.xlsx", dl_dir / "答题卡_待分配.xlsx"
        mode = os.environ.get("DAILY_ASSIGN_DOWNLOAD_MODE", "disabled").strip().lower()
        ok = False
        if mode == "mock": ok = mock_download(ai_path, card_path)
        elif mode == "real": ok = real_download(ai_path, card_path, ai_task_name(date.today()), card_task_name(date.today()))
        if not ok:
            print("E002：自动下载失败 且 缺少 今天任务的表格"); return 1
        ai, card = ai_path, card_path
    
    print("\n[分配] 开始分配...")
    print("------------------------------")
    
    names_env = os.environ.get("NAMES", "").strip()
    names = [x.strip() for x in names_env.split(",") if x.strip()]
    signup, unmatched, ocr_order = parse_signup_from_shots(shots, names)
    if sum(signup.values()) <= 0:
        print("E004：OCR识别 - 无有效报名数量"); return 1
    method, mode = os.environ.get("DAILY_ASSIGN_METHOD", "page"), os.environ.get("DAILY_ASSIGN_MODE", "linked")
    ai_cap, card_cap = int(os.environ.get("DAILY_ASSIGN_AI_MAX", "200")), int(os.environ.get("DAILY_ASSIGN_CARD_MAX", "300"))
    ai_headers = ["任务名称", "子任务顺序", "任务ID", "子任务ID", "线上学生作业ID", "老师作业ID", "题单ID", "未测评页数", "总页数", "总评测数量", "任务链接"]
    card_headers = ai_headers[:]
    ai_rows, card_rows, carry = [], [], None
    if ai: ai_headers, ai_tasks = read_tasks(ai, ai_cap); ai_rows, carry = assign(ai_tasks, signup, method)
    if card: card_headers, card_tasks = read_tasks(card, card_cap); card_rows, _ = assign(card_tasks, signup, method, carry if mode == "linked" else None)
    output_dir = Path(os.environ.get("OUTPUT_DIR", str(Path.cwd())))
    output, tmp = output_dir / "分配表.xlsx", (output_dir / "分配表.xlsx").with_suffix(".tmp.xlsx")
    try:
        wb = Workbook(); wb.remove(wb.active)
        if ai_rows: write_sheet(wb.create_sheet("AI"), ai_headers, ai_rows, date.today())
        if card_rows: write_sheet(wb.create_sheet("答题卡"), card_headers, card_rows, date.today())
        wb.save(tmp); os.replace(tmp, output)
    except Exception as e:
        print(f"E005：写出 分配表 失败 ({e})"); return 1
    print("[分配] 实际分配数量、比例：")
    total_signup_all = sum(signup.values())
    assigned_w = {}
    for t, owner in ai_rows + card_rows:
        w = t.pages if method == "page" else t.tags
        assigned_w[owner] = assigned_w.get(owner, 0) + w
    total_weight_all = sum(assigned_w.values())
    for n in ocr_order:
        signup_n = signup.get(n, 0)
        if signup_n == 0: continue
        signup_ratio = (signup_n / max(total_signup_all, 1) * 100.0)
        assign_w_n = assigned_w.get(n, 0)
        assign_ratio = (assign_w_n / max(total_weight_all, 1) * 100.0)
        warn = " ⚠️" if assign_w_n == 0 else ""
        print(f"- {n}: 报名 {signup_n}/{signup_ratio:.1f}% | 分配 {assign_w_n:g}/{assign_ratio:.1f}%{warn}")
    for bad in sorted(set(unmatched)): print(f"- {bad}: 报名 无法匹配 ⚠️")
    try: display_path = str(output.relative_to(Path.home()))
    except Exception: display_path = f"{output_dir.name}/{output.name}"
    print(f"\n[下载] 👉 已生成：{display_path}\n")
    print("👉 任务已完成")
    return 0

if __name__ == "__main__": sys.exit(main())
