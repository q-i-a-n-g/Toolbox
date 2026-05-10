# 任务计划：将 check.app 集成到 Toolbox

此计划旨在将原先独立的 `Check_App` 功能作为 `Toolbox` 的一个内置工具（“周检制表”）引入。

## User Review Required

> [!IMPORTANT]
> 这是根据 `修改21.txt` 编写的详细计划，请审阅以下各项步骤及兼容策略。如果没有问题，请回复“同意”或提供修改意见，之后我将开始编写代码。

## Proposed Changes

### 1. 修改 Toolbox 配置与界面层
#### [MODIFY] Toolbox/Resources/tool_config.json
- 新增 `weekly-check` 工具的配置字典。
- `title` 设为 "周检制表"。
- `usesTextInput` 设为 `false`，由专属的拖拽面板接管输入。

#### [NEW] Toolbox/Views/WeeklyCheckPane.swift
- 创建新的 SwiftUI 视图，布局类似 `FileRenamerPane`，但专门用于“周检制表”。
- 包含上半部分大尺寸拖拽区域（Drop Zone），文字提示为 `“每日任务分配表（AI、答题卡） 拖到这里”`。
- 支持接收多个 `.xlsx` 格式的文件拖入，并以列表/图标形式展示被拖入的文件。
- 下半部分放置 `开始` 按钮。

#### [MODIFY] Toolbox/Views/ContentView.swift
- 增加条件渲染逻辑：当用户在侧边栏选中 `weekly-check` 时，上部加载 `WeeklyCheckPane` 接收文件，下半部分加载 `TerminalPaneView`。

#### [MODIFY] Toolbox/ViewModels/RootViewModel.swift
- 增加一个专属状态 `weeklyCheckState`，保存用户拖入的文件路径列表 `[URL]`。
- 开始执行时，构建特定的环境变量（包含拖入的文件路径集合、系统的默认下载路径 `~/Downloads`，以及输出结果路径 `Bundle.main.bundleURL.deletingLastPathComponent()`）。
- 将这些环境变量通过 `PTYTerminalService` 传给 Python 打包后的脚本。

---

### 2. 重构 Python 核心逻辑
#### [MODIFY] Check_App/check_main.py
需要将原先硬编码路径改为依赖命令行参数传递：
- **引入 `argparse`**:
  - `--base-files`: 接收一个或多个文件路径作为**基础任务文件**。
  - `--download-dir`: 接收系统默认下载目录。
  - `--output-file`: 接收生成文件 `result.xlsx` 的存放路径（为 App 的同级目录）。
- **`scan_data_dir` 函数改造**:
  - 不再全盘扫描 `data/` 目录。
  - 将 `--base-files` 传入的文件直接作为 `base_info` 解析对象。
  - 对于下载产生的 `AI.xlsx`、`分数.xlsx` 等明细文件，处理时直接去 `--download-dir` 读取。
- **`auto_download_files` 函数改造**:
  - `page.expect_download()` 中保存文件的路径从原 `data_dir` 修改为 `--download-dir` 传入的目录。
- **去除原有的重命名干预**:
  - 原先 `handle_renaming` 为修复手动下载命名错误，现在已全自动化且指定到下载目录，可考虑移除或只在 `--download-dir` 中针对性检查重命名。

---

### 3. 集成与通信胶水代码
#### [NEW] Toolbox/Resources/Scripts/周检制表.command
- 作为一个中间胶水脚本，主要负责将 `RootViewModel` 传过来的环境变量转化为命令行参数传递给 `check_main_bin` 二进制文件。
- 例如：`"$BIN_DIR/check_main_bin" --base-files "$BASE_FILES" --download-dir "$DOWNLOAD_DIR" --output-file "$OUTPUT_FILE"`

#### [MODIFY] Check_App 打包指令
- 本次集成会将修改后的 `check_main.py` 使用 PyInstaller 重新打包出二进制文件 `check_main_bin`，然后放入 `Toolbox/Resources/Binaries` 下，跟随 Swift 工程一起被打包发布。

## Verification Plan

### Automated Tests
- 不涉及独立的单元测试。通过 Swift UI 与终端调试器检查参数是否正常传递。

### Manual Verification
- 运行修改后的 Toolbox App。
- 确认左侧出现“周检制表”菜单。
- 拖入独立的答题卡和 AI 表（拆分文件或单个多 Sheet 文件），点击“开始”。
- 观察控制台输出，确认 Playwright 能正确唤起 Chrome 且能将文件保存至系统的“下载”文件夹。
- 确认最终的 `result.xlsx` 被生成在当前 App 文件所在的同级目录中。
