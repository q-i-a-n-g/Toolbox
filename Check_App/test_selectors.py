import os
import asyncio
from playwright.async_api import async_playwright
from pathlib import Path

async def test_selectors():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        
        # Test AI Page
        ai_path = Path("每日分配/AI批改评测.htm")
        with open(ai_path, "r", encoding="utf-8") as f:
            content = f.read()
        await page.set_content(content)
        
        print("Testing AI Selectors:")
        # 1. Task Name Input
        input_name = await page.query_selector('input#name')
        print(f"  - input#name: {'OK' if input_name else 'MISSING'}")
        
        # 2. Search Button
        search_btn = await page.query_selector('button:has-text("搜 索")')
        print(f"  - button:has-text('搜 索'): {'OK' if search_btn else 'MISSING'}")
        
        # 3. Export Button
        export_btn = await page.query_selector('button:has-text("导 出")')
        print(f"  - button:has-text('导 出'): {'OK' if export_btn else 'MISSING'}")
        
        # Test Card Page
        card_path = Path("每日分配/答题卡评测——首页.htm")
        with open(card_path, "r", encoding="utf-8") as f:
            content_card = f.read()
        await page.set_content(content_card)
        
        print("\nTesting Card Selectors:")
        input_name_card = await page.query_selector('input#name')
        print(f"  - input#name: {'OK' if input_name_card else 'MISSING'}")
        
        search_btn_card = await page.query_selector('button:has-text("搜 索")')
        print(f"  - button:has-text('搜 索'): {'OK' if search_btn_card else 'MISSING'}")
        
        export_btn_card = await page.query_selector('button:has-text("导 出")')
        print(f"  - button:has-text('导 出'): {'OK' if export_btn_card else 'MISSING'}")
        
        await browser.close()

if __name__ == "__main__":
    asyncio.run(test_selectors())
