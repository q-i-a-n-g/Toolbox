# 项目依赖管理和构建指南

## 快速开始

### 前置要求
- Node.js 18+ 和 npm
- Python 3.8+
- macOS 11+ （用于 Toolbox/Xcode 构建）

### 一键安装依赖

```bash
# 从项目根目录运行
./scripts/install.sh
```

此脚本会自动：
1. 安装 Check_App Node 依赖 (package.json)
2. 安装 Check_App Python 依赖 (requirements.txt)
3. 安装 Playwright 浏览器

---

## 项目结构

### 📂 Check_App （Node.js + Python）

**依赖文件：**
- `Check_App/package.json` - Node.js 依赖（Playwright、MCP 工具等）
- `Check_App/package-lock.json` - Node.js 依赖锁定 ✅ 已上传
- `Check_App/requirements.txt` - Python 依赖（openpyxl、playwright）✅ 新增

**依赖清单：**
```
Python:
  - openpyxl >= 3.10.0  (Excel 处理)
  - playwright >= 1.40.0 (浏览器自动化)

Node.js:
  - @google/gemini-cli
  - @openai/codex
  - @playwright/mcp
  - chrome-devtools-mcp
  - playwright
```

**构建工具：**
- PyInstaller (check_main_bin.spec)
- 生成二进制：`Check_App/dist/check_main_bin`

---

### 📂 Toolbox （Swift + Xcode）

**特点：**
- 纯 Xcode 项目（Toolbox.xcodeproj）
- 无 CocoaPods / SPM 依赖
- Python 脚本仅使用标准库，无外部依赖

**构建：**
```bash
cd Toolbox
./build.sh           # 完整自动化构建
./automate.sh        # 构建 + 测试流程
```

---

## 哪些文件已上传到 GitHub？

✅ **已上传**：
- `Check_App/package.json`
- `Check_App/package-lock.json`
- `Check_App/*.py` 源文件
- `Toolbox/Toolbox.xcodeproj/` Xcode 项目配置
- `scripts/install.sh` 安装脚本 ✨ 新增

❌ **不上传**（.gitignore 已配置）：
- `Check_App/node_modules/` - Node 依赖包（40MB+）
- `Check_App/dist/` - PyInstaller 生成的二进制
- `Check_App/build/` - PyInstaller 临时文件
- `Toolbox/build/` - Xcode 构建输出
- `Toolbox/DerivedData/` - Xcode 缓存

---

## 常见操作

### 安装依赖
```bash
./scripts/install.sh
```

### 运行 Check_App
```bash
# 方式1：运行 Python 脚本直接
python Check_App/check_main.py --help

# 方式2：运行编译后的二进制（需要先构建）
Check_App/dist/check_main_bin/check_main_bin --help
```

### 更新依赖

**Check_App Node 依赖：**
```bash
cd Check_App
npm install package_name  # 安装新包
npm update                # 更新所有包
npm ci                    # CI 环境精确安装（使用 package-lock.json）
```

**Check_App Python 依赖：**
```bash
# 添加新依赖
pip install package_name
pip freeze > Check_App/requirements.txt

# 或直接编辑 requirements.txt 后
pip install -r Check_App/requirements.txt
```

### 构建 Check_App 二进制

```bash
cd Check_App
pip install -r requirements.txt
pip install pyinstaller
pyinstaller check_main_bin.spec
```

### 构建 Toolbox

```bash
cd Toolbox
./build.sh
```

---

## 版本控制策略

| 文件 | 上传 | 说明 |
|------|-----|------|
| package.json | ✅ | 依赖声明，必须上传 |
| package-lock.json | ✅ | 依赖锁定，保证一致性 |
| requirements.txt | ✅ | Python 依赖声明 ✨ |
| node_modules/ | ❌ | 生成的包文件 |
| venv/ 或类似 | ❌ | Python 虚拟环境 |
| 二进制文件 | ❌ | dist/, build/ 输出 |
| build/ | ❌ | 构建临时文件 |

---

## 遇到问题？

**node_modules 无法删除**
```bash
rm -rf Check_App/node_modules Check_App/package-lock.json
npm install
```

**Python 依赖冲突**
```bash
pip cache purge
pip install -r Check_App/requirements.txt --force-reinstall
```

**Xcode 构建错误**
```bash
cd Toolbox
xcode-select --install       # 安装 Xcode Command Line Tools
xcode-select --reset         # 重置工具链
```
