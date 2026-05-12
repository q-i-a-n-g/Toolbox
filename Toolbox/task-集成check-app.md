# 集成周检制表功能到 Toolbox 任务清单

- [x] 更新 `tool_config.json` 添加 `weekly-check` 配置
- [x] 创建 `WeeklyCheckPane.swift` 实现界面及拖拽逻辑
- [x] 修改 `ContentView.swift` 和 `RootViewModel.swift` 处理相关 UI 状态
- [x] 修改 `Check_App/check_main.py` 以接收参数，并重构相关的路径管理
- [x] 使用 PyInstaller 将修改后的 Python 脚本打包为二进制 `check_main_bin`
- [x] 创建调度脚本 `Toolbox/Resources/Scripts/周检制表.command` 桥接 Swift 传参
- [x] 验证整体工作流（选择工具、拖入文件、开始执行、结果输出）
