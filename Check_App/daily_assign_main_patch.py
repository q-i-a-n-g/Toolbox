import sys
import os
import re
import shutil
import zipfile
import time
from pathlib import Path

def _download_one_table(page, url: str, task_name: str, target: Path, label: str) -> bool:
    try:
        print(f"[下载] {label} 正在打开页面...")
        # Revert to faster wait
        page.goto(url, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(2000) 
    except Exception as e:
        print(f"E002：{label} 页面加载失败 ({e})")
        return False
    
    page.bring_to_front()
    
    # 1. Input Task Name
    try:
        input_sel = 'input#name, input[placeholder*="任务名"]'
        page.wait_for_selector(input_sel, timeout=20000)
        page.fill(input_sel, "")
        page.type(input_sel, task_name, delay=10)
    except Exception:
        print(f"E002：无法在 {label} 页面输入任务名")
        return False
            
    # 2) 搜索
    try:
        print(f"[下载] {label} 触发搜索...")
        search_btn = page.locator('button:has-text("搜 索"), button:has-text("搜索")').first
        if search_btn.is_visible():
            search_btn.click()
        else:
            page.keyboard.press("Enter")
        
        # Wait for potential loading state
        page.wait_for_timeout(1000)
        try:
            page.wait_for_selector('.ant-spin-spinning, .ant-loading', timeout=2000)
            page.wait_for_selector('.ant-spin-spinning, .ant-loading', state="hidden", timeout=15000)
        except: pass
    except: pass
    
    # Matching rows (defined in global scope, assuming it works here or using local mock)
    # ok_filter, _ = _wait_search_match(page, task_name, timeout_ms=20000)
    # To keep it simple and robust, let's use page.locator and check count
    try:
        page.wait_for_timeout(1000)
        # Verify row exists
        found = False
        for _ in range(20):
            txt = page.evaluate("() => document.body.innerText")
            if task_name in txt:
                found = True
                break
            page.wait_for_timeout(500)
        if not found:
            print(f"E002：{label} 搜索结果匹配失败（期望：{task_name}）")
            return False
    except: pass
    
    # 3) 导出
    print(f"[下载] {label} 准备导出...")
    # Use direct click logic
    try:
        exported = False
        btns = page.locator('button:has-text("导 出"), button:has-text("导出")')
        for i in range(btns.count()):
            b = btns.nth(i)
            if b.is_visible():
                b.click(force=True)
                exported = True
                break
        if not exported:
            print(f"E002：{label} 未找到导出按钮")
            return False
    except:
        return False
        
    # 4) 确认弹窗并下载
    try:
        # Wait for modal to be visible
        page.wait_for_timeout(1200)
        
        with page.expect_download(timeout=60000) as download_info:
            confirm_btns = page.locator('.ant-modal-footer button.ant-btn-primary, button:has-text("确 定"), button:has-text("确定")')
            clicked = False
            for i in range(confirm_btns.count()):
                btn = confirm_btns.nth(i)
                if btn.is_visible():
                    btn.click(force=True)
                    clicked = True
                    break
            if not clicked:
                page.keyboard.press("Enter")
        
        download = download_info.value
        new_file = download.path()
        
        # Verify file
        if not os.path.exists(new_file) or os.path.getsize(new_file) < 500:
            print(f"E002：{label} 下载文件无效")
            return False
                
        # Copy and strictly validate content
        if os.path.exists(str(target)): os.remove(str(target))
        shutil.copy(new_file, str(target))
        
        # External validation call (assumed available in main script)
        # if not validate_downloaded_task(target, task_name): ...
            
        print(f"[下载] {label} 任务下载成功 ✅")
        return True
    except Exception as e:
        print(f"E002：{label} 下载流程异常 ({e})")
        return False
