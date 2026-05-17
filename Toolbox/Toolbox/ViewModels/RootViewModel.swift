import Foundation
import Combine

enum PaneZoomTarget {
    case none
    case text
    case terminal
}

enum EditorMode {
    case hidden
    case input
    case help
    case config
}

struct RenamerPreviewItem: Identifiable {
    let id = UUID()
    let oldName: String
    let newName: String
    let oldURL: URL
    let newURL: URL
}

struct RenameHistory {
    let folderURL: URL
    let operations: [(old: URL, new: URL)]
}

struct RenamerState {
    var folderURL: URL?
    var prefix: String = ""
    var startNumber: Int = 1
    var step: Int = 1
    var padding: String = ""
    var previewItems: [RenamerPreviewItem] = []
    var history: RenameHistory?
}

@MainActor
final class RootViewModel: ObservableObject {
    @Published var tools: [ScriptTool]
    @Published var selectedTool: ScriptTool
    @Published var terminalText = ""
    @Published var zoomTarget: PaneZoomTarget = .none
    @Published var isRunning = false
    @Published var editorMode: EditorMode
    @Published var editorText = ""
    @Published var isTerminalFocused = false
    @Published var isEditorFocused = false
    @Published var isRenamerFocused = false
    @Published var renamerState = RenamerState()
    @Published var weeklyCheckFiles: [URL] = []
    @Published var dailyAssignFiles: [URL] = []
    @Published var dailyAssignSettings = DailyAssignSettings()
    @Published var isSidebarVisible: Bool = true
    @Published private(set) var hiddenToolIDs: Set<String> = []
    @Published private(set) var sidebarOrder: [String] = []

    private let terminalService = PTYTerminalService()
    private let defaults: UserDefaults
    private let textStorageKeyPrefix = "Toolbox.savedInput."
    private let hiddenToolIDsKey = "Toolbox.sidebar.hiddenToolIDs"
    private let sidebarOrderKey = "Toolbox.sidebar.order"
    private let fileStore = ToolFileStore()
    private var inputDraftByTool: [String: String] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let loadedTools = ScriptTool.loadConfiguredTools()
        let initialTool = loadedTools.first ?? ScriptTool.fallbackTools[0]
        
        self.tools = loadedTools
        self.selectedTool = initialTool
        self.editorMode = initialTool.usesTextInput ? .input : .hidden
        self.sidebarOrder = loadedTools.map(\.id)
        
        restoreSidebarState()
        applySidebarOrderToTools()
        restoreEditorForSelectedTool(clearText: true)
    }

    var visibleTools: [ScriptTool] {
        tools.filter { !hiddenToolIDs.contains($0.id) }
    }



    var shouldShowTextPane: Bool {
        editorMode != .hidden
    }

    var isEditorEditable: Bool {
        editorMode != .help
    }

    var helpButtonTitle: String {
        editorMode == .help ? "关闭" : "帮助"
    }

    var configButtonTitle: String {
        editorMode == .config ? "保存" : "配置"
    }

    var editorTitle: String {
        switch editorMode {
        case .hidden:
            return selectedTool.title
        case .input:
            return selectedTool.title
        case .help:
            return "帮助"
        case .config:
            return "配置"
        }
    }

    func select(_ tool: ScriptTool) {
        guard selectedTool.id != tool.id else { return }

        // Stop current tool when switching away
        if isRunning {
            stopSelectedTool()
        }

        if selectedTool.id == "weekly-check" && tool.id != "weekly-check" {
            weeklyCheckFiles = []
        }
        if selectedTool.id == "daily-assign" && tool.id != "daily-assign" {
            dailyAssignFiles = []
        }

        selectedTool = tool
        terminalText = ""
        resetToolSpecificState(for: tool)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.restoreEditorForSelectedTool(clearText: true)
            
            // Auto-focus logic
            if tool.id == "file-renamer" {
                self.isRenamerFocused = true
            } else if tool.id == "weekly-check" {
                // 需先拖入表格，再由用户点「开始」
                self.isTerminalFocused = true
            } else if tool.usesTextInput {
                self.isEditorFocused = true
            } else if tool.id != "daily-assign" {
                // If it's a terminal-only tool, auto-start it (which also focuses terminal)
                self.startSelectedTool()
            }
        }
    }

    func toggleSidebarVisibility() {
        isSidebarVisible.toggle()
    }

    func isToolHidden(_ toolID: String) -> Bool {
        hiddenToolIDs.contains(toolID)
    }

    func toggleToolVisibility(_ toolID: String) {
        if hiddenToolIDs.contains(toolID) {
            hiddenToolIDs.remove(toolID)
        } else {
            hiddenToolIDs.insert(toolID)
            if selectedTool.id == toolID, let fallback = visibleTools.first(where: { $0.id != toolID }) {
                select(fallback)
            }
        }
        defaults.set(Array(hiddenToolIDs), forKey: hiddenToolIDsKey)
    }

    func moveVisibleTools(from source: Int, to destination: Int) {
        var visibleIDs = visibleTools.map(\.id)
        guard source >= 0, source < visibleIDs.count else { return }
        let moving = visibleIDs.remove(at: source)
        let to = min(max(destination, 0), visibleIDs.count)
        visibleIDs.insert(moving, at: to)

        let hiddenIDs = tools.map(\.id).filter { hiddenToolIDs.contains($0) }
        sidebarOrder = visibleIDs + hiddenIDs.filter { !visibleIDs.contains($0) }
        applySidebarOrderToTools()
        defaults.set(sidebarOrder, forKey: sidebarOrderKey)
    }

    func toggleZoom(for target: PaneZoomTarget) {
        if target == .text && !shouldShowTextPane {
            return
        }
        // Selection state should be fast
        zoomTarget = zoomTarget == target ? .none : target
    }

    func updateEditorText(_ newValue: String) {
        editorText = newValue

        if editorMode == .input {
            inputDraftByTool[selectedTool.id] = newValue
            defaults.set(newValue, forKey: storageKey(for: selectedTool.id))
        }
    }

    func toggleHelp() {
        if editorMode == .help {
            restoreEditorForSelectedTool(clearText: false)
            return
        }

        if editorMode == .input {
            inputDraftByTool[selectedTool.id] = editorText
        }
        editorMode = .help
        if selectedTool.id == "daily-assign" {
            editorText = """
                - 全自动：只拖入 报名截图 ，则 `自动下载` 今日的任务表（AI、答题卡），并自动生成 分配表.xlsx

                - 半自动：拖入 `报名截图 + 手动下载的表格`，适用于需要 `手动下载` 任务表的情况

                - AI、答题卡独立分配：区分AI、答题卡，每个报名人都分到AI、答题卡（按比例）

                - AI+答题卡一起分配：不区分AI、答题卡，合在一起分，有些人只分到AI，有些人只分到答题卡
"""
        } else if selectedTool.id == "weekly-check" {
            editorText = """
                ## 功能

                    - 自动打开统计详情页，下载 `AI、答题卡` 的统计详情表

                    - 自动处理下载的表格，生成 `result.xlsx` 供检查。

                ## 使用

                    - 把已分配的线上任务表(`AI`或`AI+答题卡`)，复制一份，拖到拖拽区，点 [开始] 按钮

                ## Tips

                    - 首次运行，自动下载时，`需要登录`，之后就不用了

                    - 无需手动删除旧文件（下载的、生成的），可`自动覆盖`
"""
        } else {
            editorText = fileStore.loadHelpText(for: selectedTool)
        }
    }

    func handleConfigButton() {
        if editorMode == .config {
            do {
                if selectedTool.id == "daily-assign" {
                    try saveDailyAssignConfig(from: editorText)
                } else {
                    try fileStore.saveConfigText(editorText, for: selectedTool)
                }
            } catch {
                terminalText += "\n[配置] 保存失败: \(error.localizedDescription)\n"
            }
            restoreEditorForSelectedTool(clearText: false)
            return
        }

        if editorMode == .input {
            inputDraftByTool[selectedTool.id] = editorText
        }
        editorMode = .config
        if selectedTool.id == "daily-assign" {
            editorText = loadDailyAssignConfigTemplate()
        } else {
            editorText = fileStore.loadConfigText(for: selectedTool)
        }
    }

    private var runSessionID = UUID()

    func startSelectedTool() {
        if isRunning {
            stopSelectedTool()
        }

        // Ensure input ends with a newline to prevent shell reading issues (missing last line)
        var inputText = editorText
        if !inputText.isEmpty && !inputText.hasSuffix("\n") {
            inputText += "\n"
        }
        
        let configURL = fileStore.configURL(for: selectedTool)

        let currentSessionID = UUID()
        self.runSessionID = currentSessionID
        
        isRunning = true
        isTerminalFocused = true
        
        // Force UI update to ensure 'Stop' button is enabled immediately
        objectWillChange.send()

        var extraEnv: [String: String] = [:]
        if selectedTool.id == "weekly-check" {
            let baseFilesPath = weeklyCheckFiles.map { $0.path }.joined(separator: "|")
            extraEnv["BASE_FILES"] = baseFilesPath
            
            let downloadDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
            extraEnv["DOWNLOAD_DIR"] = downloadDir
            
            let outputDir = Bundle.main.bundleURL.deletingLastPathComponent().path
            extraEnv["OUTPUT_DIR"] = outputDir

            // 脚本在临时目录执行，不能用相对路径找 Resources/Binaries
            if let checkMainURL = Bundle.main.resourceURL?
                .appendingPathComponent("Binaries", isDirectory: true)
                .appendingPathComponent("check_main_pkg", isDirectory: true)
                .appendingPathComponent("check_main_bin") {
                extraEnv["CHECK_MAIN_BIN"] = checkMainURL.path
            }
            
            // clear input
            inputText = ""
        } else if selectedTool.id == "daily-assign" {
            let filesPath = dailyAssignFiles.map { $0.path }.joined(separator: "|")
            extraEnv["DAILY_ASSIGN_FILES"] = filesPath
            extraEnv["DAILY_ASSIGN_METHOD"] = dailyAssignSettings.allocationMethod
            extraEnv["DAILY_ASSIGN_AI_MAX"] = "\(max(1, dailyAssignSettings.aiMaxPages))"
            extraEnv["DAILY_ASSIGN_CARD_MAX"] = "\(max(1, dailyAssignSettings.cardMaxPages))"
            extraEnv["DAILY_ASSIGN_MODE"] = dailyAssignSettings.allocationMode
            extraEnv["DAILY_ASSIGN_DOWNLOAD_MODE"] = "real"
            extraEnv["DOWNLOAD_DIR"] = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
            extraEnv["OUTPUT_DIR"] = Bundle.main.bundleURL.deletingLastPathComponent().path
            if let ocrScript = Bundle.main.resourceURL?
                .appendingPathComponent("Binaries", isDirectory: true)
                .appendingPathComponent("ocr_vision.swift") {
                extraEnv["OCR_VISION_SCRIPT"] = ocrScript.path
            }
            if let assignBin = Bundle.main.resourceURL?
                .appendingPathComponent("Binaries", isDirectory: true)
                .appendingPathComponent("check_main_pkg", isDirectory: true)
                .appendingPathComponent("daily_assign_main_bin") {
                extraEnv["DAILY_ASSIGN_BIN"] = assignBin.path
            }
            inputText = ""
        }

        terminalService.start(
            tool: selectedTool,
            inputText: inputText,
            configURL: configURL,
            extraEnv: extraEnv,
            onOutput: { [weak self] chunk in
                guard let self = self else { return }
                Task { @MainActor in
                    // More robust filtering of system noise
                    let noisePatterns = [
                        "XPC connection interrupted",
                        "sharedfilelistd.xpc",
                        "No error handler for XPC error",
                        "Connection invalid"
                    ]
                    
                    var filteredChunk = chunk
                    for pattern in noisePatterns {
                        if filteredChunk.contains(pattern) {
                            return 
                        }
                    }
                    
                    self.terminalText += filteredChunk
                }
            },
            onExit: { [weak self] status in
                guard let self = self else { return }
                Task { @MainActor in
                    // Only set to false if it was actually running (avoid race with manual stop)
                    if self.isRunning && self.runSessionID == currentSessionID {
                        self.isRunning = false
                    }
                }
            }
        )
    }

    func stopSelectedTool() {
        guard isRunning else { return }
        if selectedTool.id == "daily-assign" {
            terminalText += "\nE006：[已停止]\n"
        } else {
            terminalText += "\n[已停止]\n"
        }
        terminalService.stop()
        isRunning = false
        objectWillChange.send()
    }

    func sendTerminalInput(_ text: String) {
        terminalService.send(text)
    }

    private func restoreEditorForSelectedTool(clearText: Bool) {
        if selectedTool.usesTextInput {
            editorMode = .input
            if clearText {
                editorText = ""
                inputDraftByTool[selectedTool.id] = ""
            } else {
                editorText = inputDraftByTool[selectedTool.id] ?? ""
            }
        } else {
            editorMode = .hidden
            editorText = ""
            if zoomTarget == .text {
                zoomTarget = .none
            }
        }
    }

    private func storageKey(for toolID: String) -> String {
        textStorageKeyPrefix + toolID
    }

    private func loadDailyAssignConfigTemplate() -> String {
        let raw = fileStore.loadConfigText(for: selectedTool)
        let lines = raw.components(separatedBy: .newlines)
        
        let defaultNames = [
            "李橙橙", "符于娜", "刘雨菲", "阎思宇", "王哲",
            "崔雅琪", "李旻羲", "汪哲锐", "李梦洁", "来晨",
            "王国通", "马壮", "郭小雨", "李梦园", "段凯莉",
            "韩@“”正", "郝佳益", "李迪", "蹇文慧", "王子怡"
        ]

        let buggyKeywords = Set(["校准名单", "可编辑", "英文逗号", "分隔", "名单中没", "有的", "不会分配", "任务"])

        var namesToUse = defaultNames
        if let namesLine = lines.first(where: { $0.hasPrefix("NAMES=") }) {
            let savedNames = namesLine.replacingOccurrences(of: "NAMES=", with: "")
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !buggyKeywords.contains($0) }
            
            if !savedNames.isEmpty {
                namesToUse = savedNames
            }
        }
        
        var resultLines: [String] = [
            "--------------------------------------------------",
            "",
            "                # 校准名单（可编辑，英文逗号分隔）",
            "",
            "                # 名单中没有的，不会分配任务",
            "",
            "                {",
            ""
        ]
        
        for i in stride(from: 0, to: namesToUse.count, by: 5) {
            let chunk = namesToUse[i..<min(i + 5, namesToUse.count)]
            resultLines.append("                    " + chunk.joined(separator: ",") + (i + 5 < namesToUse.count ? "," : ""))
            resultLines.append("")
        }
        
        resultLines.append("                }")
        resultLines.append("")
        resultLines.append("--------------------------------------------------")
        return resultLines.joined(separator: "\n")
    }

    private func saveDailyAssignConfig(from text: String) throws {
        let pattern = "\\{(.*?)\\}"
        let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let range = NSRange(location: 0, length: text.utf16.count)
        
        var names: [String] = []
        if let match = regex.firstMatch(in: text, options: [], range: range),
           let contentRange = Range(match.range(at: 1), in: text) {
            let content = text[contentRange]
            names = content
                .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            // Updated regex to include special characters in 韩@“”正
            let nameRegex = try NSRegularExpression(pattern: "[\\u4e00-\\u9fa5@“”]{1,10}")
            names = nameRegex.matches(in: text, options: [], range: range).compactMap { match in
                Range(match.range, in: text).map { String(text[$0]) }
            }
        }
        
        let unique = Array(NSOrderedSet(array: names)) as? [String] ?? names
        let current = fileStore.loadConfigText(for: selectedTool)
        let kept = current.components(separatedBy: .newlines).filter { !$0.hasPrefix("NAMES=") }
        let merged = (["NAMES=" + unique.joined(separator: ",")] + kept).joined(separator: "\n")
        try fileStore.saveConfigText(merged, for: selectedTool)
    }

    private func restoreSidebarState() {
        if let hidden = defaults.array(forKey: hiddenToolIDsKey) as? [String] {
            hiddenToolIDs = Set(hidden)
        }
        if let savedOrder = defaults.array(forKey: sidebarOrderKey) as? [String], !savedOrder.isEmpty {
            let existingIDs = Set(tools.map(\.id))
            let known = savedOrder.filter { existingIDs.contains($0) }
            let missing = tools.map(\.id).filter { !known.contains($0) }
            sidebarOrder = known + missing
        }
    }

    private func applySidebarOrderToTools() {
        let indexByID = Dictionary(uniqueKeysWithValues: sidebarOrder.enumerated().map { ($1, $0) })
        tools.sort { lhs, rhs in
            let li = indexByID[lhs.id] ?? Int.max
            let ri = indexByID[rhs.id] ?? Int.max
            return li < ri
        }
    }

    private func resetToolSpecificState(for tool: ScriptTool) {
        if tool.id == "file-renamer" {
            renamerState = RenamerState()
        }
        if tool.id == "daily-assign" {
            dailyAssignSettings = DailyAssignSettings()
        }
    }

    func clearAllToolInputs() {
        guard !isRunning else { return }
        terminalText = ""
        weeklyCheckFiles = []
        dailyAssignFiles = []
        renamerState = RenamerState()
        
        if editorMode != .config && editorMode != .help {
            editorText = ""
            inputDraftByTool[selectedTool.id] = ""
            if selectedTool.usesTextInput {
                defaults.set("", forKey: storageKey(for: selectedTool.id))
            }
        }
    }

    // MARK: - File Renamer Logic

    func updateRenamerFolder(_ url: URL) {
        renamerState.folderURL = url
        refreshRenamerPreview()
        isRenamerFocused = true
    }

    func refreshRenamerPreview() {
        guard let folderURL = renamerState.folderURL else { return }
        
        let fm = FileManager.default
        do {
            let urls = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)
            
            // Filter: only regular files, no subdirs
            let fileURLs = urls.filter { url in
                var isReg: ObjCBool = false
                return fm.fileExists(atPath: url.path, isDirectory: &isReg) && !isReg.boolValue
            }.sorted { 
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            
            var items: [RenamerPreviewItem] = []
            let paddingWidth = Int(renamerState.padding) ?? 0
            
            for (index, oldURL) in fileURLs.enumerated() {
                let number = renamerState.startNumber + (index * renamerState.step)
                let numberStr = paddingWidth > 0 ? String(format: "%0\(paddingWidth)d", number) : String(number)
                
                let ext = oldURL.pathExtension
                let newName = renamerState.prefix + numberStr + (ext.isEmpty ? "" : "." + ext)
                let newURL = folderURL.appendingPathComponent(newName)
                
                items.append(RenamerPreviewItem(oldName: oldURL.lastPathComponent, newName: newName, oldURL: oldURL, newURL: newURL))
            }
            
            renamerState.previewItems = items
        } catch {
            terminalText += "\n[重命名] 读取目录失败: \(error.localizedDescription)\n"
        }
    }

    func executeRename() {
        let items = renamerState.previewItems
        guard !items.isEmpty, let folderURL = renamerState.folderURL else { return }
        
        terminalText += "\n开始重命名 \(items.count) 个文件...\n"
        let fm = FileManager.default
        var completedOps: [(old: URL, new: URL)] = []
        
        for item in items {
            do {
                try fm.moveItem(at: item.oldURL, to: item.newURL)
                completedOps.append((old: item.oldURL, new: item.newURL))
                terminalText += "成功: \(item.oldName) -> \(item.newName)\n"
            } catch {
                terminalText += "失败: \(item.oldName) -> \(item.newName) (\(error.localizedDescription))\n"
            }
        }
        
        renamerState.history = RenameHistory(folderURL: folderURL, operations: completedOps)
        terminalText += "👉 任务已完成\n"
        
        // Refresh preview after operation (it will likely be empty or show new names if we re-read)
        refreshRenamerPreview()
    }

    func undoRename() {
        guard let history = renamerState.history else { 
            terminalText += "\n[撤销] 没有可撤销的历史记录\n"
            return 
        }
        
        terminalText += "\n正在撤销上一次操作...\n"
        let fm = FileManager.default
        
        // Reverse the operations
        for op in history.operations.reversed() {
            do {
                try fm.moveItem(at: op.new, to: op.old)
                terminalText += "已还原: \(op.new.lastPathComponent) -> \(op.old.lastPathComponent)\n"
            } catch {
                terminalText += "还原失败: \(op.new.lastPathComponent) (\(error.localizedDescription))\n"
            }
        }
        
        renamerState.history = nil
        terminalText += "👉 撤销完成\n"
        refreshRenamerPreview()
    }
}
