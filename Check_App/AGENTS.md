# Check_App (check.app) - Agent Documentation

## Project Overview
`check.app` is a MacOS desktop application built with Python. Its primary purpose is to automate the downloading and processing of evaluation task data (Excel files) for weekly quality checks. It generates a comprehensive `AI_check.xlsx` report highlighting various errors, bad cases, and statistics for different task types.

## Tech Stack
- **Core Logic**: Python (`check_main.py`)
- **Excel Processing**: `openpyxl`
- **Browser Automation**: Playwright (connecting to the local Google Chrome profile for authentication state)
- **Packaging**: PyInstaller (packaged as a `.app` MacOS application)

## Architecture & Workflow
The application operates in a multi-stage workflow:

1. **Initialization & Base Data Scanning**: 
   - Reads base assignment files (e.g., `答+周.xlsx`, `寒假.xlsx`) placed by the user in the `data/` directory.
   - Identifies files via column headers (e.g., matching the "负责人" column).
   - Generates a "拼链接" sheet containing constructed URLs for data downloading.

2. **Automated Data Downloading**:
   - Uses Playwright to connect to a local Chrome profile (`~/.gemini/NewApp_chrome_profile`) to bypass login requirements.
   - Navigates to the constructed links on `mapi.yuanfudao.com`.
   - Simulates clicks to download detailed evaluation data files (`AI.xlsx`, `分数.xlsx`, `答题卡-AI.xlsx`, `答题卡-分数.xlsx`) into the `data/` folder.

3. **Data Transformation & Reporting (`AI_check.xlsx`)**:
   - Matches the downloaded data with base assignment data to assign owners ("负责人").
   - Filters, deduplicates, and formats data into specific sheets based on precise business rules:
     - **Sheet 1**: 拼链接
     - **Sheet 2**: 分数识别错误或忽略
     - **Sheet 3**: 固定批改错误或忽略
     - **Sheet 4**: 题目框错误+忽略超过3个
     - **Sheet 5**: BadCase
     - **Sheet 6**: 答题卡_分数识别错误或忽略
     - **Sheet 7**: 答题卡_AI_BadCase
     - **Sheet 8**: 答题卡_AI_错误次数≥3（星标参考）
     - **Sheet 9**: AI_错误次数≥3（星标参考）
   - Applies specific Excel formatting (e.g., column widths, cell background colors like yellow for headers and gray/green for visual grouping).

4. **File Normalization**:
   - Automatically detects misnamed Excel files in `data/` by inspecting their headers and renames them to standard names (e.g., `AI.xlsx`).

5. **Terminal UI**:
   - The app outputs real-time scanning, downloading, and generation progress to the terminal, and keeps the terminal window open upon completion for user verification.

## Core Files & Directories
- `check_main.py`: The entry point and main logic file. Contains all scanning, Playwright automation, and Excel generation code.
- `check.app/`: The final MacOS application bundle. The executable logic resides at `check.app/Contents/Resources/check_main`.
- `data/`: The working directory for input and intermediate Excel files.
- `AI_check.xlsx`: The final generated output report.
- `需求文档.txt`, `修改*.txt`, `新界面*.txt`: Product Requirements Documents (PRD) and modification history dictating the business logic for each sheet.

## Guidelines for AI Agents

1. **Modifying Sheet Logic**:
   - Simple sheets are typically generated using the `generic_build` function in `check_main.py`.
   - Complex sheets (like BadCase, AI_错误次数≥3) have custom procedural logic in the `main()` function. 
   - When modifying logic, ensure you strictly follow the column matching by name (using the `col()` function) rather than hardcoded indices, as the column positions in the source files are subject to change.

2. **Playwright Automation**:
   - The Playwright script (`auto_download_files`) relies on specific DOM elements (e.g., `button:has-text('导出Excel')`). If the upstream website updates its UI, these locators will need adjustment.
   - Playwright uses a local Chrome context to preserve login cookies. Avoid headless operations if they break the auth state.

3. **Packaging Updates**:
   - If you make changes to `check_main.py` or `daily_assign_main.py`, rebuild the shared onedir package with PyInstaller on the current Mac architecture and refresh only the matching Toolbox resource zip: `Toolbox/Resources/Binaries/check_main_pkg_arm64.zip` on Apple Silicon, or `Toolbox/Resources/Binaries/check_main_pkg_x86_64.zip` on Intel.
   - Do not overwrite the other architecture's zip when rebuilding. The Toolbox package script selects the correct zip at build time, so both Macs can share identical source code without repeatedly dirtying architecture-specific artifacts.
   - Do not run `lipo -thin` on PyInstaller executables after build. PyInstaller appends its archive to the Mach-O file, and post-build thinning breaks that archive. Only Playwright's embedded `driver/node` may be thinned inside the final Toolbox app bundle.

4. **Formatting Constraints**:
   - Ensure the terminal output strictly aligns with the PRD (using `pad_display` for precise UI alignment).
   - Do **not** write any log files (e.g., `app.log`) to the disk, as per the user's explicit requirement in the PRD.
