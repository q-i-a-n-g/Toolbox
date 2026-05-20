#!/usr/bin/env python3
from __future__ import annotations
import os
import re
import shutil
import sys
import json
import subprocess
import warnings
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


def normalize_task_text(text: str) -> str:
    if not text:
        return ""
    t = str(text).strip()
    t = re.sub(r"\s+", "", t)
    t = t.replace("（", "(").replace("）", ")")
    return t.lower()


def _query_visible_task_names(page) -> List[str]:
    try:
        data = page.evaluate(
            """() => {
              const out = [];
              // Check menu items
              const menu = Array.from(document.querySelectorAll('ul.ant-menu h5, ul.ant-menu .ant-typography'));
              for (const n of menu) {
                const t = (n?.innerText || '').trim();
                if (t) out.push(t);
              }
              // Check all table cells
              const cells = Array.from(document.querySelectorAll('.ant-table-tbody tr td'));
              for (const n of cells) {
                const t = (n?.innerText || '').trim();
                if (t) out.push(t);
              }
              // Check all links (especially encoded ones in URLs)
              const links = Array.from(document.querySelectorAll('.ant-table-tbody tr a'));
              for (const n of links) {
                try {
                    const href = n?.href || '';
                    if (href) {
                        out.push(href);
                        out.push(decodeURIComponent(href));
                    }
                } catch(e) {}
              }
              return out.slice(0, 200);
            }"""
        )
        return data if isinstance(data, list) else []
    except Exception:
        return []


def _take_screenshot(page, name: str):
    try:
        path = Path("screenShot") / f"{name}_{int(time.time())}.png"
        path.parent.mkdir(parents=True, exist_ok=True)
        page.screenshot(path=str(path))
        print(f"[截图] 已保存: {path.name}")
    except Exception as e:
        print(f"[截图] 失败: {e}")


def _wait_search_match(page, task_name: str, timeout_ms: int = 20000) -> tuple[bool, List[str]]:
    expect = normalize_task_text(task_name)
    elapsed = 0
    sample: List[str] = []
    while elapsed <= timeout_ms:
        rows = _query_visible_task_names(page)
        if rows:
            sample = rows[:8]
            if any(expect and expect in normalize_task_text(r) for r in rows):
                return True, sample
        page.wait_for_timeout(500)
        elapsed += 500
    return False, sample


def _visible_button_by_text(page, wanted: str):
    locs = page.locator("button")
    for i in range(min(locs.count(), 80)):
        try:
            btn = locs.nth(i)
            txt = re.sub(r"\s+", "", btn.inner_text(timeout=300) or "")
            if txt == wanted and btn.is_visible() and btn.is_enabled():
                return btn
        except Exception:
            continue
    return None


def _close_open_modals(page):
    try:
        page.evaluate(
            """() => {
              for (const btn of document.querySelectorAll('.ant-modal-close')) {
                const modal = btn.closest('.ant-modal');
                if (modal && getComputedStyle(modal).display !== 'none') btn.click();
              }
            }"""
        )
    except Exception:
        pass


def _click_export_button(page) -> bool:
    try:
        btn = _visible_button_by_text(page, "导出")
        if btn is None:
            return False
        btn.scroll_into_view_if_needed()
        btn.click(timeout=8000, force=True)
        return True
    except Exception:
        return False


def _download_one_table(page, url: str, task_name: str, target: Path, label: str) -> bool:
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(1200)
    except Exception as e:
        print(f"E002：{label} 页面打开失败 ({e})")
        return False
    
    page.bring_to_front()
    _close_open_modals(page)
    
    # 1. Input Task Name
    try:
        input_sel = 'input#name, input[placeholder*="任务名"]'
        page.wait_for_selector(input_sel, timeout=20000)
        page.fill(input_sel, "")
        page.type(input_sel, task_name, delay=8)
    except Exception:
        print(f"E002：无法在 {label} 页面输入任务名")
        _take_screenshot(page, f"{label}_input_fail")
        return False
            
    # 2) 搜索
    try:
        search_btn = _visible_button_by_text(page, "搜索")
        if search_btn is not None:
            search_btn.click()
        else:
            page.keyboard.press("Enter")
        
        page.wait_for_timeout(800)
        try:
            loading = page.locator('.ant-spin-spinning, .ant-loading, .ant-table-loading')
            if loading.count() > 0:
                loading.first.wait_for(state="hidden", timeout=15000)
        except: pass
    except: pass
    
    ok_filter, _ = _wait_search_match(page, task_name, timeout_ms=20000)
    if not ok_filter:
        print(f"E002：{label} 搜索结果匹配失败（期望：{task_name}）")
        _take_screenshot(page, f"{label}_search_fail")
        return False
    
    # 3) 导出
    if not _click_export_button(page):
        print(f"E002：{label} 点击导出按钮失败")
        _take_screenshot(page, f"{label}_export_fail")
        return False
        
    # 4) 确认弹窗并下载
    try:
        modal = page.locator(".ant-modal:visible").last
        modal.wait_for(state="visible", timeout=10000)
        page.wait_for_timeout(300)
        
        with page.expect_download(timeout=60000) as download_info:
            confirm = modal.locator('.ant-modal-footer button.ant-btn-primary').last
            if confirm.count() > 0 and confirm.is_visible(timeout=3000):
                confirm.click(force=True, timeout=5000)
            else:
                page.keyboard.press("Enter")
        
        download = download_info.value
        tmp_target = target.with_suffix(target.suffix + ".download")
        if tmp_target.exists():
            tmp_target.unlink()
        download.save_as(str(tmp_target))
        if not tmp_target.exists() or tmp_target.stat().st_size < 500:
            print(f"E002：{label} 下载文件不完整")
            return False
        if target.exists():
            target.unlink()
        tmp_target.replace(target)
        
        # Strict content check to ensure it's not the "wrong" file
        if not validate_downloaded_task(target, task_name):
            print(f"E002：{label} 下载内容与目标任务不符（可能下载了全部数据或缓存数据）")
            return False
            
        print(f"[下载] {label} 任务下载成功 ✅")
        return True
    except Exception as e:
        print(f"E002：{label} 下载确认超时或失败 ({e})")
        _take_screenshot(page, f"{label}_final_fail")
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
                headless=False, no_viewport=True, accept_downloads=True,
                args=["--remote-debugging-port=9222", "--start-maximized"]
            )
            page = browser_context.pages[0] if browser_context.pages else browser_context.new_page()

            def download_with_retry(url: str, task: str, target: Path, label: str) -> bool:
                for attempt in range(1, 4):
                    ok = _download_one_table(page, url, task, target, label)
                    if ok:
                        return True
                    print(f"[下载] {label} 第{attempt}次失败，准备重试...")
                    page.wait_for_timeout(2000)
                return False

            ok1 = download_with_retry("https://mapi.yuanfudao.com/evaluation/#/admin/evaluation/holepage", ai_task, ai_target, "AI")
            ok2 = download_with_retry("https://mapi.yuanfudao.com/evaluation/#/admin/evaluation/card", card_task, card_target, "答题卡")
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


def validate_downloaded_task(path: Path, expected_task_name: str) -> bool:
    try:
        wb = load_workbook(path, data_only=True)
        ws = wb.worksheets[0]
        header_row, task_col = None, None
        for r in range(1, min(20, ws.max_row) + 1):
            for c in range(1, min(20, ws.max_column) + 1):
                if str(ws.cell(r, c).value or "").strip() == "任务名称":
                    header_row, task_col = r, c
                    break
            if header_row is not None:
                break
        if header_row is None or task_col is None:
            return False
        names = []
        for r in range(header_row + 1, ws.max_row + 1):
            v = str(ws.cell(r, task_col).value or "").strip()
            if v:
                names.append(v)
        if not names:
            return False
        expect = normalize_task_text(expected_task_name)
        if any(expect and expect in normalize_task_text(n) for n in names):
            return True
        hits = sum(1 for n in names if expected_task_name in n)
        return hits > 0
    except Exception:
        return False


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
    if cap <= 0:
        return source_headers, []
    # DP subset near cap; allow slight overflow to find better balance
    weights = [max(1, int(round(r.pages))) for r in out]
    # Allow more overflow in search to find more precise target
    limit = max(1, int(round(cap * 1.05)))
    prev_sum = [-1] * (limit + 1)
    prev_idx = [-1] * (limit + 1)
    prev_sum[0] = -2
    for i, w in enumerate(weights):
        for s in range(limit, w - 1, -1):
            if prev_sum[s] == -1 and prev_sum[s - w] != -1:
                prev_sum[s] = s - w
                prev_idx[s] = i

    target = int(round(cap))
    best_s = 0
    best_key = (10**9, 10**9)
    for s in range(limit + 1):
        if prev_sum[s] == -1:
            continue
        # Favor small overflow if it's closer to target
        diff = abs(s - target)
        # If error < 2%, it's already quite good
        key = (diff, max(0, s - target)) 
        if key < best_key:
            best_key = key
            best_s = s

    picked_idx = set()
    s = best_s
    while s > 0 and prev_idx[s] != -1:
        i = prev_idx[s]
        picked_idx.add(i)
        s = prev_sum[s]
    picked = [out[i] for i in sorted(picked_idx, key=lambda x: out[x].order)]
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


def parse_confirmed_signup(raw: str, names: List[str]) -> Dict[str, int]:
    out: Dict[str, int] = {}
    if not raw.strip():
        return out
    for part in raw.split("|"):
        item = part.strip()
        if not item or ":" not in item:
            continue
        n, c = item.split(":", 1)
        name = n.strip()
        if not name or name not in names:
            continue
        try:
            cnt = int(c.strip())
        except Exception:
            continue
        if cnt not in (2, 3, 5):
            continue
        out[name] = cnt
    return out


def assign(tasks: List[TaskRow], signup: Dict[str, int], weight_key: str, carry: Dict[str, float] | None = None):
    names = sorted(signup.keys())
    total_signup = sum(signup.values())
    target_ratio = {n: signup[n] / total_signup for n in names}
    assigned_weight = {n: 0.0 for n in names}
    assigned_count = {n: 0 for n in names}
    if carry:
        for n in names: assigned_weight[n] += carry.get(n, 0.0)
    result, total_w = [], 0.0
    tasks_sorted = sorted(tasks, key=lambda t: (t.pages if weight_key == "page" else t.tags, -t.order), reverse=True)
    for t in tasks_sorted:
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
    for i, (_, owner) in enumerate(result):
        owner_tasks[owner].append(i)

    def score() -> tuple[float, float]:
        total = max(sum(assigned_weight.values()), 1.0)
        # Use relative error to target ratio for better precision on different weights
        devs = []
        for n in names:
            target = target_ratio[n]
            if target > 0:
                devs.append(abs(assigned_weight[n] / total - target) / target)
        if not devs: return 0.0, 0.0
        return max(devs), sum(d * d for d in devs)

    cur_score = score()
    # Increase iterations and breadth for better convergence to < 2% relative error
    for iter_idx in range(8000):
        improved = False
        total = max(sum(assigned_weight.values()), 1.0)
        
        # Sort by relative deviation
        signed = []
        for n in names:
            target = target_ratio[n]
            if target > 0:
                signed.append((assigned_weight[n] / total / target - 1.0, n))
        signed.sort()
        
        under = [n for d, n in signed if d < 0]
        over = [n for d, n in reversed(signed) if d > 0]
        
        # Target relative error threshold 2% (0.02)
        if cur_score[0] <= 0.02: 
            break

        # Move: check more candidates
        for o in over[:8]:
            for u in under[:8]:
                best_i = None
                best_local = cur_score
                # Look deeper into task list
                for i in owner_tasks[o][:200]:
                    task, _ = result[i]
                    w = task.pages if weight_key == "page" else task.tags
                    assigned_weight[o] -= w
                    assigned_weight[u] += w
                    new_score = score()
                    assigned_weight[o] += w
                    assigned_weight[u] -= w
                    if new_score < best_local:
                        best_local = new_score
                        best_i = i
                if best_i is not None:
                    task, _ = result[best_i]
                    w = task.pages if weight_key == "page" else task.tags
                    assigned_weight[o] -= w
                    assigned_weight[u] += w
                    result[best_i][1] = u
                    owner_tasks[o].remove(best_i)
                    owner_tasks[u].append(best_i)
                    cur_score = best_local
                    improved = True
                    break
            if improved: break
        if improved: continue

        # Swap: check more pairs
        for o in over[:6]:
            for u in under[:6]:
                best_pair = None
                best_local = cur_score
                for i in owner_tasks[o][:100]:
                    t1, _ = result[i]
                    w1 = t1.pages if weight_key == "page" else t1.tags
                    for j in owner_tasks[u][:100]:
                        t2, _ = result[j]
                        w2 = t2.pages if weight_key == "page" else t2.tags
                        if abs(w1 - w2) < 0.001: continue
                        assigned_weight[o] += (w2 - w1)
                        assigned_weight[u] += (w1 - w2)
                        new_score = score()
                        assigned_weight[o] += (w1 - w2)
                        assigned_weight[u] += (w2 - w1)
                        if new_score < best_local:
                            best_local = new_score
                            best_pair = (i, j, w1, w2)
                if best_pair is not None:
                    i, j, w1, w2 = best_pair
                    result[i][1], result[j][1] = result[j][1], result[i][1]
                    assigned_weight[o] += (w2 - w1)
                    assigned_weight[u] += (w1 - w2)
                    owner_tasks[o].remove(i); owner_tasks[o].append(j)
                    owner_tasks[u].remove(j); owner_tasks[u].append(i)
                    cur_score = best_local
                    improved = True
                    break
            if improved: break
        if not improved: break
    grouped = {n: [] for n in names}
    for item in result: grouped[item[1]].append(tuple(item))
    final = []
    for n in names: final.extend(grouped[n])
    return final, assigned_weight


def task_weight_sum(tasks: List[TaskRow], weight_key: str) -> float:
    total = 0.0
    for t in tasks:
        w = t.pages if weight_key == "page" else t.tags
        total += w if w > 0 else 1.0
    return total


def split_signup_for_linked_mode(ai_tasks: List[TaskRow], card_tasks: List[TaskRow], signup: Dict[str, int], weight_key: str) -> tuple[Dict[str, int], Dict[str, int]]:
    names = sorted(signup.keys())
    if len(names) <= 1 or not ai_tasks or not card_tasks:
        return signup, signup

    ai_total = task_weight_sum(ai_tasks, weight_key)
    card_total = task_weight_sum(card_tasks, weight_key)
    if ai_total <= 0 or card_total <= 0:
        return signup, signup

    total_signup = sum(signup.values())
    target_ai_signup = total_signup * ai_total / (ai_total + card_total)

    best_subset: set[str] | None = None
    best_key = (float("inf"), float("inf"), float("inf"))
    n = len(names)
    # The signup list is small in practice; exhaustive search gives a stable owner partition.
    for mask in range(1, (1 << n) - 1):
        subset = {names[i] for i in range(n) if mask & (1 << i)}
        subset_signup = sum(signup[name] for name in subset)
        key = (
            abs(subset_signup - target_ai_signup),
            abs(len(subset) - n * ai_total / (ai_total + card_total)),
            len(subset),
        )
        if key < best_key:
            best_key = key
            best_subset = subset

    if not best_subset:
        return signup, signup

    ai_signup = {name: signup[name] for name in names if name in best_subset}
    card_signup = {name: signup[name] for name in names if name not in best_subset}
    return ai_signup, card_signup


def ai_task_name(today: date) -> str:
    yesterday = today - timedelta(days=1)
    return f"{yesterday:%y%m%d}-{today:%y%m%d}"


def card_task_name(today: date) -> str:
    # The saved production examples use Thursday-Wednesday cycles:
    # 2026-05-07..2026-05-13 and 2026-05-14..2026-05-20.
    days_since_thursday = (today.weekday() - 3) % 7
    start = today - timedelta(days=days_since_thursday)
    end = start + timedelta(days=6)
    return f"{start:%m%d}-{end:%m%d}答题卡周期评测"


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

    names_env = os.environ.get("NAMES", "").strip()
    names = [x.strip() for x in names_env.split(",") if x.strip()]
    signup_ocr, unmatched, ocr_order = parse_signup_from_shots(shots, names)
    preview_rows = [{"name": n, "count": int(signup_ocr.get(n, 0)), "matched": True} for n in ocr_order if signup_ocr.get(n, 0) > 0]
    preview_rows.extend([{"name": n, "count": 5, "matched": False} for n in unmatched])
    print("__OCR_PREVIEW__" + json.dumps({"rows": preview_rows}, ensure_ascii=False))

    if os.environ.get("DAILY_ASSIGN_PREVIEW_ONLY", "0").strip() == "1":
        if not preview_rows:
            print("E004：OCR识别 - 无有效报名数量")
            return 1
        print(f"[识别] 已识别 {len(preview_rows)} 人，请在上方查看/调整后 继续")
        print("（点 金银花，可以返回，重新OCR）")
        return 0

    confirmed_signup = parse_confirmed_signup(os.environ.get("DAILY_ASSIGN_CONFIRMED_SIGNUP", ""), names)
    signup = confirmed_signup if confirmed_signup else signup_ocr
    if sum(signup.values()) <= 0:
        print("E004：OCR识别 - 无有效报名数量"); return 1
    print(f"[确认] 报名结果已确认：{len(signup)} 人")

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
            print("E002：自动下载失败，请重试（或 手动下载 今天的任务表格）"); return 1
        ai, card = ai_path, card_path
    
    print("\n\n\n[分配] 开始分配...")
    print("------------------------------")

    method, mode = os.environ.get("DAILY_ASSIGN_METHOD", "page"), os.environ.get("DAILY_ASSIGN_MODE", "linked")
    ai_cap, card_cap = int(os.environ.get("DAILY_ASSIGN_AI_MAX", "200")), int(os.environ.get("DAILY_ASSIGN_CARD_MAX", "300"))
    ai_headers = ["任务名称", "子任务顺序", "任务ID", "子任务ID", "线上学生作业ID", "老师作业ID", "题单ID", "未测评页数", "总页数", "总评测数量", "任务链接"]
    card_headers = ai_headers[:]
    ai_rows, card_rows = [], []
    ai_tasks, card_tasks = [], []
    if ai: ai_headers, ai_tasks = read_tasks(ai, ai_cap)
    if card: card_headers, card_tasks = read_tasks(card, card_cap)
    if mode == "linked":
        ai_signup, card_signup = split_signup_for_linked_mode(ai_tasks, card_tasks, signup, method)
        if ai_tasks: ai_rows, _ = assign(ai_tasks, ai_signup, method)
        if card_tasks: card_rows, _ = assign(card_tasks, card_signup, method)
    else:
        if ai_tasks: ai_rows, _ = assign(ai_tasks, signup, method)
        if card_tasks: card_rows, _ = assign(card_tasks, signup, method)
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
    display_order = list(ocr_order) if ocr_order else []
    for n in signup:
        if n not in display_order:
            display_order.append(n)
    for n in display_order:
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
    print(f"\n\n------------------------------\n👉 已生成：{display_path}\n\n\n")
    print("👉 任务已完成")
    return 0

if __name__ == "__main__": sys.exit(main())
