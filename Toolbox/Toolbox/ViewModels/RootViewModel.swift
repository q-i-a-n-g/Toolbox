import Foundation
import Combine
import AppKit

enum PaneZoomTarget: Equatable {
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
    var selectedFileURLs: [URL] = []
    var prefix: String = ""
    var startNumber: Int = 1
    var step: Int = 1
    var padding: String = ""
    var previewItems: [RenamerPreviewItem] = []
    var history: RenameHistory?
}

enum DailyAssignStage {
    case idle
    case confirming
    case readyToRun
}

struct DailyAssignSignupRow: Identifiable {
    let id = UUID()
    var name: String
    var count: Int
    var matched: Bool
    var originalOrder: Int
    var originalName: String
    var originalCount: Int
    var isUserAdded: Bool
}

struct OpenLinksConfig {
    var batchSize: Int = 10
    var dedupeLinks: Bool = true
}

struct StitchImagesState {
    var folderURL: URL?
    var mode: String = "1"
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
    @Published var dailyAssignStage: DailyAssignStage = .idle
    @Published var dailyAssignRows: [DailyAssignSignupRow] = []
    @Published var dailyAssignNames: [String] = []
    @Published var dailyAssignConfigNames: [String] = []
    @Published var openLinksConfig = OpenLinksConfig()
    @Published var stitchImagesState = StitchImagesState()
    @Published var isDailyAssignConfirmPaneZoomed = false
    @Published var isSidebarVisible: Bool = true
    @Published private(set) var hiddenToolIDs: Set<String> = []
    @Published private(set) var sidebarOrder: [String] = []

    private let terminalService = PTYTerminalService()
    private let defaults: UserDefaults
    private let textStorageKeyPrefix = "Toolbox.savedInput."
    private let hiddenToolIDsKey = "Toolbox.sidebar.hiddenToolIDs"
    private let sidebarOrderKey = "Toolbox.sidebar.order"
    private let canonicalDailyAssignNames = [
        "李橙橙", "符于娜", "刘雨菲", "阎思宇", "王哲",
        "崔雅琪", "李旻羲", "汪哲锐", "李梦洁", "来晨",
        "王国通", "马壮", "郭小雨", "李梦园", "段凯莉",
        "韩正", "郝佳益", "李迪", "蹇文慧", "王子怡"
    ]
    private let fileStore = ToolFileStore()
    private var inputDraftByTool: [String: String] = [:]
    private var dailyAssignPreviewRowsBackup: [DailyAssignSignupRow] = []

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

    var defaultDailyAssignNames: [String] {
        canonicalDailyAssignNames
    }

    var dailyAssignCanConfirm: Bool {
        dailyAssignConfirmIssue == nil
    }

    var dailyAssignConfirmIssue: String? {
        guard !dailyAssignRows.isEmpty else { return "还没有报名人" }
        let validCounts = Set([2, 3, 5])
        var seen = Set<String>()
        var total = 0
        for (index, row) in dailyAssignRows.enumerated() {
            let n = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.isEmpty {
                return "第 \(index + 1) 行姓名为空"
            }
            if !dailyAssignNames.contains(n) {
                return "\(n) 不在校准名单中"
            }
            if !validCounts.contains(row.count) {
                return "\(n) 的报名数量不是 2、3 或 5"
            }
            if seen.contains(n) {
                return "已经有 \(n) 了"
            }
            seen.insert(n)
            total += row.count
        }
        if total <= 0 {
            return "报名数量不能为 0"
        }
        return nil
    }

    var dailyAssignStartButtonTitle: String {
        dailyAssignStage == .confirming ? "继续" : "开始"
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
        if tool.id != "open-links", zoomTarget == .terminal {
            zoomTarget = .none
        }
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
            } else if tool.id != "daily-assign" && tool.id != "stitch-images" {
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
        if target == .terminal && selectedTool.id != "open-links" {
            return
        }
        // Selection state should be fast
        zoomTarget = zoomTarget == target ? .none : target
    }

    func refocusTerminalAfterActivationIfNeeded() {
        guard shouldRefocusTerminalForBrowserReturn(toolID: selectedTool.id) else { return }
        requestTerminalFocus()
    }

    private func refocusToolboxAfterAutomatedBrowserRun(for toolID: String) {
        guard shouldRefocusTerminalForBrowserReturn(toolID: toolID) else { return }

        bringToolboxWindowToFront()
        requestTerminalFocus(after: 0)
        requestTerminalFocus(after: 0.15)
        requestTerminalFocus(after: 0.4)
        requestTerminalFocus(after: 0.8)
    }

    private func shouldRefocusTerminalForBrowserReturn(toolID: String) -> Bool {
        toolID == "open-links" || toolID == "daily-assign" || toolID == "weekly-check"
    }

    private func bringToolboxWindowToFront() {
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func requestTerminalFocus(after delay: TimeInterval = 0) {
        let focus = { [weak self] in
            guard let self = self else { return }
            self.isEditorFocused = false
            self.isRenamerFocused = false
            self.isTerminalFocused = false
            DispatchQueue.main.async { [weak self] in
                self?.isTerminalFocused = true
            }
        }

        if delay <= 0 {
            focus()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                focus()
            }
        }
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
            editorText = [
                "- 全自动：只拖入 报名截图 ，则 `自动下载` 今日的任务表（AI、答题卡），并自动生成 分配表.xlsx",
                "",
                "- 半自动：拖入 `报名截图 + 手动下载的表格`，适用于需要 `手动下载` 任务表的情况",
                "",
                "- AI、答题卡独立分配：区分AI、答题卡，每个报名人都分到AI、答题卡（按比例）",
                "",
                "- AI+答题卡一起分配：不区分AI、答题卡，合在一起分，有些人只分到AI，有些人只分到答题卡",
                ""
            ].joined(separator: "\n")
        } else if selectedTool.id == "weekly-check" {
            editorText = [
                "## 功能",
                "",
                "    - 自动打开统计详情页，下载 `AI、答题卡` 的统计详情表",
                "",
                "    - 自动处理下载的表格，生成 `AI&答题卡_check.xlsx` 供检查。",
                "",
                "## 使用",
                "",
                "    - 把线上每日任务表（ `AI` 或 `AI+答题卡` ）复制一份，拖到拖拽区，点 [开始] 按钮",
                "",
                "## Tips",
                "",
                "    - 首次运行，自动下载时，`需要登录`，之后就不用了",
                "",
                "    - 无需手动删除旧文件（下载的、生成的），可`自动覆盖`",
                ""
            ].joined(separator: "\n")
        } else {
            editorText = fileStore.loadHelpText(for: selectedTool)
        }
    }

    func handleConfigButton() {
        if editorMode == .config {
            do {
                if selectedTool.id == "daily-assign" {
                    try saveDailyAssignConfigNames(dailyAssignConfigNames)
                } else if selectedTool.id == "open-links" {
                    try saveOpenLinksConfig()
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
            dailyAssignConfigNames = loadDailyAssignNames()
            editorText = ""
        } else if selectedTool.id == "open-links" {
            openLinksConfig = loadOpenLinksConfig()
            editorText = ""
        } else {
            editorText = fileStore.loadConfigText(for: selectedTool)
        }
    }

    func restoreDefaultDailyAssignConfigNames() {
        dailyAssignConfigNames = canonicalDailyAssignNames
    }

    private var runSessionID = UUID()

    func startSelectedTool() {
        if isRunning {
            stopSelectedTool()
        }

        if selectedTool.id == "daily-assign", dailyAssignFiles.isEmpty {
            terminalText += "E001：未检测到 有效 报名截图\n"
            return
        }
        if selectedTool.id == "weekly-check", weeklyCheckFiles.isEmpty {
            terminalText += "[检查] 请先拖入线上每日任务表\n"
            return
        }

        if selectedTool.id == "daily-assign", dailyAssignStage != .readyToRun {
            if dailyAssignStage == .confirming {
                if let issue = dailyAssignConfirmIssue {
                    terminalText += "[识别] \(issue)\n"
                    return
                }
                dailyAssignStage = .readyToRun
            } else {
                startDailyAssignPreview()
                return
            }
        }

        // Ensure input ends with a newline to prevent shell reading issues (missing last line)
        var inputText = editorText
        if !inputText.isEmpty && !inputText.hasSuffix("\n") {
            inputText += "\n"
        }
        
        let configURL = fileStore.configURL(for: selectedTool)

        let currentToolID = selectedTool.id
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
            extraEnv["TOOLBOX_APP_PATH"] = Bundle.main.bundleURL.path
            
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
            let aiMax = min(max(1, dailyAssignSettings.aiMaxPages), 20_000)
            let cardMax = min(max(1, dailyAssignSettings.cardMaxPages), 20_000)
            let confirmedSignup = dailyAssignRows
                .map { "\($0.name):\($0.count)" }
                .joined(separator: "|")
            extraEnv["DAILY_ASSIGN_FILES"] = filesPath
            extraEnv["DAILY_ASSIGN_METHOD"] = dailyAssignSettings.allocationMethod
            extraEnv["DAILY_ASSIGN_AI_MAX"] = "\(aiMax)"
            extraEnv["DAILY_ASSIGN_CARD_MAX"] = "\(cardMax)"
            extraEnv["DAILY_ASSIGN_MODE"] = dailyAssignSettings.allocationMode
            extraEnv["DAILY_ASSIGN_DOWNLOAD_MODE"] = "real"
            extraEnv["DAILY_ASSIGN_PREVIEW_ONLY"] = "0"
            extraEnv["DAILY_ASSIGN_CONFIRMED_SIGNUP"] = confirmedSignup
            extraEnv["TOOLBOX_APP_PATH"] = Bundle.main.bundleURL.path
            extraEnv["DOWNLOAD_DIR"] = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
            extraEnv["OUTPUT_DIR"] = Bundle.main.bundleURL.deletingLastPathComponent().path
            addDailyAssignRuntimePaths(to: &extraEnv)
            inputText = ""
        } else if selectedTool.id == "stitch-images" {
            guard let folderURL = stitchImagesState.folderURL else {
                terminalText += "[图片拼接] 请先拖入目标文件夹\n"
                isRunning = false
                return
            }
            extraEnv["TARGET_DIR"] = folderURL.path
            extraEnv["STACK_MODE_CHOICE"] = stitchImagesState.mode
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
                    
                    let filteredChunk = chunk
                    for pattern in noisePatterns {
                        if filteredChunk.contains(pattern) {
                            return 
                        }
                    }
                    
                    let cleaned = self.handleDailyAssignPreviewOutputIfNeeded(filteredChunk)
                    if !cleaned.isEmpty {
                        self.terminalText += cleaned
                    }
                }
            },
            onExit: { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    let isCurrentRun = self.isRunning && self.runSessionID == currentSessionID
                    if isCurrentRun {
                        self.isRunning = false
                        self.refocusToolboxAfterAutomatedBrowserRun(for: currentToolID)
                    }
                }
            }
        )
    }

    func resetDailyAssignRowsToOCR() {
        dailyAssignRows = dailyAssignPreviewRowsBackup
    }

    func addDailyAssignRow() {
        let first = dailyAssignNames.first ?? ""
        let nextOrder = (dailyAssignRows.map(\.originalOrder).max() ?? -1) + 1
        dailyAssignRows.append(DailyAssignSignupRow(
            name: first,
            count: 5,
            matched: false,
            originalOrder: nextOrder,
            originalName: first,
            originalCount: 5,
            isUserAdded: true
        ))
    }

    func removeDailyAssignRow(_ id: UUID) {
        dailyAssignRows.removeAll { $0.id == id }
    }

    func mergeDuplicateDailyAssignRows() {
        var merged: [String: (count: Int, matched: Bool, order: Int)] = [:]
        for row in dailyAssignRows {
            guard !row.name.isEmpty else { continue }
            if let old = merged[row.name] {
                merged[row.name] = (old.count + row.count, old.matched && row.matched, min(old.order, row.originalOrder))
            } else {
                merged[row.name] = (row.count, row.matched, row.originalOrder)
            }
        }
        dailyAssignRows = merged.map { key, val in
            let snapped = [2, 3, 5].min(by: { abs($0 - val.count) < abs($1 - val.count) }) ?? 5
            return DailyAssignSignupRow(
                name: key,
                count: snapped,
                matched: val.matched,
                originalOrder: val.order,
                originalName: key,
                originalCount: snapped,
                isUserAdded: false
            )
        }.sorted { $0.originalOrder < $1.originalOrder }
    }

    func sortDailyAssignRowsByOCR() {
        dailyAssignRows.sort { $0.originalOrder < $1.originalOrder }
    }

    func sortDailyAssignRowsByNameList() {
        let index = Dictionary(uniqueKeysWithValues: dailyAssignNames.enumerated().map { ($1, $0) })
        dailyAssignRows.sort { (index[$0.name] ?? Int.max) < (index[$1.name] ?? Int.max) }
    }

    func toggleDailyAssignConfirmPaneZoom() {
        isDailyAssignConfirmPaneZoomed.toggle()
    }

    func stopSelectedTool() {
        if selectedTool.id == "daily-assign", dailyAssignStage == .confirming {
            terminalText += "\nE006：[已停止]\n"
            if isRunning {
                terminalService.stop()
                isRunning = false
            }
            dailyAssignStage = .idle
            dailyAssignRows = []
            dailyAssignPreviewRowsBackup = []
            isDailyAssignConfirmPaneZoomed = false
            objectWillChange.send()
            requestTerminalFocus()
            return
        }

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
        
        var namesToUse = canonicalDailyAssignNames
        if let namesLine = lines.first(where: { $0.hasPrefix("NAMES=") }) {
            let savedNames = namesLine.replacingOccurrences(of: "NAMES=", with: "")
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
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

    private func loadOpenLinksConfig() -> OpenLinksConfig {
        let raw = fileStore.loadConfigText(for: selectedTool)
        var config = OpenLinksConfig()
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if key == "BATCH_SIZE", let intValue = Int(value) {
                config.batchSize = max(1, min(intValue, 200))
            } else if key == "DEDUPE_LINKS" {
                config.dedupeLinks = value != "0"
            }
        }
        return config
    }

    private func saveOpenLinksConfig() throws {
        let batch = max(1, min(openLinksConfig.batchSize, 200))
        let dedupe = openLinksConfig.dedupeLinks ? "1" : "0"
        let text = """
        # 每次打开几个链接
        BATCH_SIZE=\(batch)

        # 打开前先去重：1 = 去重，0 = 不去重
        DEDUPE_LINKS=\(dedupe)
        """
        try fileStore.saveConfigText(text, for: selectedTool)
        openLinksConfig.batchSize = batch
    }

    private func saveDailyAssignConfig(from text: String) throws {
        var names: [String] = []
        if let left = text.firstIndex(of: "{"),
           let right = text[left...].firstIndex(of: "}") {
            let content = text[text.index(after: left)..<right]
            names = content
                .components(separatedBy: CharacterSet(charactersIn: ",，、;\n\r\t"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { $0.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "") }
                .filter { !$0.isEmpty }
        }

        if names.isEmpty {
            throw NSError(
                domain: "DailyAssignConfig",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "名单为空，请在大括号内填写至少 1 个姓名"]
            )
        }

        var unique: [String] = []
        var seen = Set<String>()
        for name in names {
            if seen.insert(name).inserted {
                unique.append(name)
            }
        }

        let current = fileStore.loadConfigText(for: selectedTool)
        let kept = current.components(separatedBy: .newlines).filter { !$0.hasPrefix("NAMES=") }
        let merged = (["NAMES=" + unique.joined(separator: ",")] + kept).joined(separator: "\n")
        try fileStore.saveConfigText(merged, for: selectedTool)
    }

    private func saveDailyAssignConfigNames(_ rawNames: [String]) throws {
        let names = rawNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if names.isEmpty {
            throw NSError(
                domain: "DailyAssignConfig",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "名单为空，请至少填写 1 个姓名"]
            )
        }

        var unique: [String] = []
        var seen = Set<String>()
        for name in names {
            if seen.insert(name).inserted {
                unique.append(name)
            }
        }

        let current = fileStore.loadConfigText(for: selectedTool)
        let kept = current.components(separatedBy: .newlines).filter { !$0.hasPrefix("NAMES=") }
        let merged = (["NAMES=" + unique.joined(separator: ",")] + kept).joined(separator: "\n")
        try fileStore.saveConfigText(merged, for: selectedTool)
        dailyAssignNames = unique
        dailyAssignConfigNames = unique
    }

    func updateStitchImagesFolder(_ url: URL) {
        stitchImagesState.folderURL = url
        isTerminalFocused = true
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
            dailyAssignStage = .idle
            dailyAssignRows = []
            dailyAssignPreviewRowsBackup = []
            dailyAssignNames = loadDailyAssignNames()
            isDailyAssignConfirmPaneZoomed = false
        }
        if tool.id == "stitch-images" {
            stitchImagesState = StitchImagesState()
        }
    }

    func clearAllToolInputs() {
        guard !isRunning else { return }
        terminalText = ""
        weeklyCheckFiles = []
        dailyAssignFiles = []
        dailyAssignStage = .idle
        dailyAssignRows = []
        dailyAssignPreviewRowsBackup = []
        isDailyAssignConfirmPaneZoomed = false
        renamerState = RenamerState()
        stitchImagesState = StitchImagesState()
        
        if editorMode != .config && editorMode != .help {
            editorText = ""
            inputDraftByTool[selectedTool.id] = ""
            if selectedTool.usesTextInput {
                defaults.set("", forKey: storageKey(for: selectedTool.id))
            }
        }
    }

    // MARK: - File Renamer Logic

    func updateRenamerTargets(_ urls: [URL]) {
        let fm = FileManager.default
        var folders: [URL] = []
        var files: [URL] = []

        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                folders.append(url)
            } else {
                files.append(url)
            }
        }

        if folders.count == 1 && files.isEmpty {
            renamerState.folderURL = folders[0]
            renamerState.selectedFileURLs = []
        } else if folders.isEmpty && !files.isEmpty {
            renamerState.folderURL = nil
            renamerState.selectedFileURLs = files
        } else {
            terminalText += "\n[重命名] 只能拖入单个文件夹，或拖入一个/多个文件；不能混合文件和文件夹，也不能拖入多个文件夹\n"
            return
        }

        refreshRenamerPreview()
        isRenamerFocused = true
    }

    func updateRenamerFolder(_ url: URL) {
        updateRenamerTargets([url])
    }

    func refreshRenamerPreview() {
        let fm = FileManager.default
        let sourceURLs: [URL]

        if !renamerState.selectedFileURLs.isEmpty {
            sourceURLs = renamerState.selectedFileURLs.filter { url in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
            }
        } else if let folderURL = renamerState.folderURL {
            do {
                let urls = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)
                sourceURLs = urls.filter { url in
                    var isDir: ObjCBool = false
                    return fm.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
                }.sorted {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
            } catch {
                terminalText += "\n[重命名] 读取目录失败: \(error.localizedDescription)\n"
                return
            }
        } else {
            renamerState.previewItems = []
            return
        }

        let paddingWidth = Int(renamerState.padding) ?? 0
        renamerState.previewItems = sourceURLs.enumerated().map { index, oldURL in
            let number = renamerState.startNumber + (index * renamerState.step)
            let numberStr = paddingWidth > 0 ? String(format: "%0\(paddingWidth)d", number) : String(number)
            let ext = oldURL.pathExtension
            let newName = renamerState.prefix + numberStr + (ext.isEmpty ? "" : "." + ext)
            let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)

            return RenamerPreviewItem(oldName: oldURL.lastPathComponent, newName: newName, oldURL: oldURL, newURL: newURL)
        }
    }

    func executeRename() {
        let items = renamerState.previewItems
        guard !items.isEmpty else { return }
        
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
        
        if let historyFolder = renamerState.folderURL ?? completedOps.first?.old.deletingLastPathComponent() {
            renamerState.history = RenameHistory(folderURL: historyFolder, operations: completedOps)
        }
        if !renamerState.selectedFileURLs.isEmpty {
            renamerState.selectedFileURLs = completedOps.map(\.new)
        }
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
        if !renamerState.selectedFileURLs.isEmpty {
            renamerState.selectedFileURLs = history.operations.map(\.old)
        }
        terminalText += "👉 撤销完成\n"
        refreshRenamerPreview()
    }

    private func startDailyAssignPreview() {
        dailyAssignNames = loadDailyAssignNames()
        terminalText += "[识别] 正在识别 报名信息...\n"
        let configURL = fileStore.configURL(for: selectedTool)
        let currentSessionID = UUID()
        self.runSessionID = currentSessionID
        isRunning = true
        isTerminalFocused = true

        let filesPath = dailyAssignFiles.map { $0.path }.joined(separator: "|")
        var extraEnv: [String: String] = [
            "DAILY_ASSIGN_FILES": filesPath,
            "DAILY_ASSIGN_PREVIEW_ONLY": "1"
        ]
        addDailyAssignRuntimePaths(to: &extraEnv)

        terminalService.start(
            tool: selectedTool,
            inputText: "",
            configURL: configURL,
            extraEnv: extraEnv,
            onOutput: { [weak self] chunk in
                guard let self = self else { return }
                Task { @MainActor in
                    let cleaned = self.handleDailyAssignPreviewOutputIfNeeded(chunk)
                    if !cleaned.isEmpty {
                        self.terminalText += cleaned
                    }
                }
            },
            onExit: { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    if self.runSessionID == currentSessionID {
                        self.isRunning = false
                    }
                }
            }
        )
    }

    private func handleDailyAssignPreviewOutputIfNeeded(_ chunk: String) -> String {
        guard selectedTool.id == "daily-assign" else { return chunk }
        if !chunk.contains("__OCR_PREVIEW__") {
            return chunk
        }
        var kept: [String] = []
        for line in chunk.components(separatedBy: .newlines) {
            if line.hasPrefix("__OCR_PREVIEW__") {
                if dailyAssignStage == .readyToRun {
                    continue
                }
                let payload = String(line.dropFirst("__OCR_PREVIEW__".count))
                if let data = payload.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let rows = json["rows"] as? [[String: Any]] {
                    var parsed: [DailyAssignSignupRow] = []
                    for (idx, row) in rows.enumerated() {
                        let name = (row["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let matched = row["matched"] as? Bool ?? true
                        let count = row["count"] as? Int ?? 5
                        let safeCount = [2, 3, 5].contains(count) ? count : 5
                        parsed.append(DailyAssignSignupRow(
                            name: name,
                            count: safeCount,
                            matched: matched,
                            originalOrder: idx,
                            originalName: name,
                            originalCount: safeCount,
                            isUserAdded: false
                        ))
                    }
                    dailyAssignRows = parsed
                    dailyAssignPreviewRowsBackup = parsed
                    dailyAssignStage = .confirming
                }
            } else {
                kept.append(line)
            }
        }
        return kept.joined(separator: "\n")
    }

    private func addDailyAssignRuntimePaths(to extraEnv: inout [String: String]) {
        guard let binariesURL = Bundle.main.resourceURL?
            .appendingPathComponent("Binaries", isDirectory: true)
        else { return }

        let ocrBin = binariesURL.appendingPathComponent("ocr_vision_bin")
        if FileManager.default.isExecutableFile(atPath: ocrBin.path) {
            extraEnv["OCR_VISION_BIN"] = ocrBin.path
        }

        let ocrScript = binariesURL.appendingPathComponent("ocr_vision.swift")
        if FileManager.default.fileExists(atPath: ocrScript.path) {
            extraEnv["OCR_VISION_SCRIPT"] = ocrScript.path
        }

        let assignBin = binariesURL
            .appendingPathComponent("check_main_pkg", isDirectory: true)
            .appendingPathComponent("daily_assign_main_bin")
        if FileManager.default.isExecutableFile(atPath: assignBin.path) {
            extraEnv["DAILY_ASSIGN_BIN"] = assignBin.path
        }
    }

    private func loadDailyAssignNames() -> [String] {
        guard let tool = tools.first(where: { $0.id == "daily-assign" }) else { return [] }
        let raw = fileStore.loadConfigText(for: tool)
        for line in raw.components(separatedBy: .newlines) {
            if line.hasPrefix("NAMES=") {
                let names = line.replacingOccurrences(of: "NAMES=", with: "")
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !names.isEmpty {
                    if containsCorruptDailyAssignNames(names) {
                        repairDailyAssignNamesConfig(tool: tool)
                        return canonicalDailyAssignNames
                    }
                    return names
                }
            }
        }
        repairDailyAssignNamesConfig(tool: tool)
        return canonicalDailyAssignNames
    }

    private func containsCorruptDailyAssignNames(_ names: [String]) -> Bool {
        let knownBadFragments = ["校准名单", "可编辑", "英文逗号", "名单中没", "不会分配", "新增姓名", "分隔"]
        return names.contains { name in
            knownBadFragments.contains { name.contains($0) }
        }
    }

    private func repairDailyAssignNamesConfig(tool: ScriptTool) {
        let current = fileStore.loadConfigText(for: tool)
        let kept = current.components(separatedBy: .newlines).filter { !$0.hasPrefix("NAMES=") }
        let merged = (["NAMES=" + canonicalDailyAssignNames.joined(separator: ",")] + kept).joined(separator: "\n")
        try? fileStore.saveConfigText(merged, for: tool)
    }
}
