# Toolbox AI Agent Guidelines

本文档为开发代理（AI Agent）提供关于 `Toolbox` 项目的核心架构说明、开发规范及构建指南。

## 1. 项目概览 (Project Overview)
Toolbox 是一个原生的 macOS 应用程序，旨在为常用的 Bash 脚本提供一个图形化（GUI）外壳。它集成了终端输出视图、文本输入框以及脚本管理逻辑。

- **目标系统**: macOS 12.3 及以上版本。
- **架构支持**: Universal Binary (Intel + Apple Silicon)。
- **核心逻辑**: 通过 PTY (Pseudo-terminal) 环境执行本地脚本，并将输出实时重定向到 SwiftUI 视图。

## 2. 技术栈 (Tech Stack)
- **UI 框架**: SwiftUI (主要) + AppKit (`NSTextView` 封装用于高性能终端输出)。
- **语言**: Swift 5.5+。
- **后台服务**: 
    - `PTYTerminalService`: 管理终端会话。
    - `PTYProcess`: 使用 `/usr/bin/script` 产生伪终端。
- **脚本语言**: Bash / Shell。
- **外部依赖**: `ffmpeg` (静态内嵌于 App Bundle)。

## 3. 项目结构 (Project Structure)
- `/Toolbox/Views/`: 包含所有 UI 视图（Sidebar, Terminal, TextInput）。
- `/Toolbox/ViewModels/`: `RootViewModel` 负责核心业务流转。
- `/Toolbox/Services/`: 负责进程管理和 IO 拦截。
- `/Toolbox/Resources/Scripts/`: 存放所有 `.command` 业务脚本。
- `/Toolbox/Resources/Binaries/`: 存放 `ffmpeg` (拆分为针对不同架构的 **`ffmpeg_arm.zip`** 与 **`ffmpeg_intel.zip`**) 等二进制工具；周检制表使用 **`check_main_pkg.zip`**（约 48MB，可上 GitHub）与解压后的 `check_main_pkg/`。解压目录内 Playwright 自带的 **`node` 约 112MB**，超过 GitHub 单文件 100MB 限制，**不得**将 `check_main_pkg/` 提交到 Git。Xcode 在 **Resources 阶段前** 会运行 *Unpack check_main_pkg* 脚本：在编译/打包时自动检测目标架构，并解压对应的 zip 到本地 `ffmpeg` 二进制，若 zip 更新、或目标架构改变、或 `check_main_bin` 不存在，则执行解压。更新周检逻辑后：在 `Check_App` 执行 `python3 -m PyInstaller --noconfirm check_main_bin.spec`，再在仓库根执行：
```bash
REPO="$(git rev-parse --show-toplevel)"
cd "$REPO/Toolbox/Toolbox/Resources/Binaries"
rm -rf check_main_pkg check_main_pkg.zip
cp -R "$REPO/Check_App/dist/check_main_bin" ./check_main_pkg
zip -rq check_main_pkg.zip check_main_pkg -x "*.DS_Store"
```
  然后提交 **`check_main_pkg.zip`**。每日分配逻辑与 `check_main_bin` 共用该 onedir 包，更新 `Check_App/daily_assign_main.py` 后也必须按同一流程重新生成 `check_main_pkg.zip`。
- `/Toolbox/Resources/tool_config.json`: 工具注册中心。

## 4. 开发规范 (Development Conventions)

### 4.1 脚本路径定位
**必须**使用 `Bundle.main.resourceURL` 配合 `appendingPathComponent` 来定位脚本和二进制文件。严禁使用 `Bundle.main.url(forResource:...)` 的简写形式，因为在 App 被移动或处于隔离模式（Translocation）时，简写形式可能失效。

### 4.2 增加新功能流程
1. 将新的 `.command` 脚本放入 `Resources/Scripts/`。
2. 在 `Resources/tool_config.json` 中添加新项，定义其 `id`, `title`, `scriptRelativePath` 等。
3. 如果脚本需要文本框输入，请设置 `usesTextInput: true`。

### 4.3 终端交互规范
- **结束标识**: 脚本执行完毕时，务必输出 `👉 任务已完成`，以便 UI 逻辑识别任务状态。
- **路径处理**: 脚本中处理用户拖入的路径时，应使用内置的 `normalize_path` 逻辑处理空格、引号和转义符。
- **防误触**: 在脚本运行期间，UI 的“开始”按钮应处于 `disabled` 状态。

## 5. 编译与打包指南 (Build & Packaging)

### 5.1 部署目标
- **macOS Deployment Target**: 12.3。
- **Xcode 设置**: 确保 `ONLY_ACTIVE_ARCH=NO`。

### 5.2 构建指令
使用 Xcode 命令行（需先 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`，若默认指向 CommandLineTools 会找不到 `xcodebuild`）。工程内 **Scheme 名为 `ScriptToolbox`**（Target 仍为 `Toolbox`）。

分别生成针对 Apple 芯片和 Intel 芯片的精简包，可直接运行仓库内脚本：
```bash
cd Toolbox   # 即包含 Toolbox.xcodeproj 的目录
./package.sh
```
在打包时，Xcode 运行脚本会分别自动将对应的架构版本 `ffmpeg_arm.zip` 或 `ffmpeg_intel.zip` 解压为 `Binaries/ffmpeg`。这避免了使用庞大的 Universal 合并架构，并可直接在不同架构的 Mac 上一键打包，同时大幅缩小安装包的体积。
可选环境变量：`TOOLBOX_SCHEME`（默认 `ScriptToolbox`）、`TOOLBOX_PACKAGE_OUTPUT_DIR`（若设置且为已存在目录，则额外复制 zip 到该路径）。

手动示例：
```bash
xcodebuild -project Toolbox.xcodeproj -scheme ScriptToolbox -configuration Release ARCHS="arm64" ONLY_ACTIVE_ARCH=NO ...
# 瘦身二进制 (重要)
# 使用 lipo 剥离 ffmpeg 中多余的架构代码以大幅减小体积
lipo -extract arm64 ffmpeg -output ffmpeg_thin
```

- **架构分发**: 以后**不再使用**单一的 Universal 包，必须分别打包 `Apple 芯片版` 和 `Intel 芯片版`。
- **二进制瘦身**: 打包前必须使用 `lipo` 对内置的二进制文件（如 `ffmpeg`）进行提纯（Thinning），仅保留当前安装包所需的单一架构，以减小体积。
- **PyInstaller 包瘦身边界**: `check_main_pkg` 内的 PyInstaller 启动器（`check_main_bin`、`daily_assign_main_bin`）不能在打包后再 `lipo -thin`，因为 PyInstaller 归档附在 Mach-O 后面，瘦身会破坏归档偏移。只允许瘦身 Playwright 自带的 `check_main_pkg/_internal/playwright/driver/node`。Xcode 解包脚本必须按目标架构校验已解开的 `check_main_pkg`，避免把上一次构建残留的 Intel/Apple 单架构文件复制进另一版安装包。
- **零依赖**: 所有的外部工具必须包含在资源包内。
- **签名**: 即使是 Ad-hoc 签名 (`-`) 也必须存在。若打包过程中删除 App Bundle 内的 zip 或其他资源以瘦身，必须在删除后重新执行 `codesign --force --deep --sign - --timestamp=none Toolbox.app`，否则资源封印会引用已删除文件，`codesign --verify --deep --strict` 会失败。

## 6. UI 设计原则 (UI Design Principles)
- **窗口大小**: 默认约为 `550x360`，侧边栏宽度约为 `120`。
- **颜色倾向**: 终端视图使用深色背景 (`Color.black.opacity(0.92)`) 和绿色文本。
- **交互**: 
    - 优先支持拖拽文件夹/文件到终端视图以获取路径。
    - **自动聚焦与启动**:
        - **带文本框的脚本**: 切换时立即将焦点锁定到**上方文本输入区域**。
        - **无文本框的脚本**: 切换时**自动启动脚本**，并立即将焦点锁定到**下方终端输入区域**。
        - **例外**: `weekly-check`（周检制表）需先在上方拖入 Excel，再由用户点击「开始」；切换到此工具时**不**自动启动。
        - **切换即停止**: 切换工具时，必须自动停止当前正在运行的脚本。
