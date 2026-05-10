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

    private let terminalService = PTYTerminalService()
    private let defaults: UserDefaults
    private let textStorageKeyPrefix = "Toolbox.savedInput."
    private let fileStore = ToolFileStore()
    private var inputDraftByTool: [String: String] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let loadedTools = ScriptTool.loadConfiguredTools()
        let initialTool = loadedTools.first ?? ScriptTool.fallbackTools[0]
        self.tools = loadedTools
        self.selectedTool = initialTool
        self.editorMode = initialTool.usesTextInput ? .input : .hidden
        // seedDefaultTextsIfNeeded()
        restoreEditorForSelectedTool(clearText: true)
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

        selectedTool = tool
        terminalText = ""
        resetToolSpecificState(for: tool)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.restoreEditorForSelectedTool(clearText: true)
            
            // Auto-focus logic
            if tool.id == "file-renamer" {
                self.isRenamerFocused = true
            } else if tool.usesTextInput {
                self.isEditorFocused = true
            } else {
                // If it's a terminal-only tool, auto-start it (which also focuses terminal)
                self.startSelectedTool()
            }
        }
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
        editorText = fileStore.loadHelpText(for: selectedTool)
        if zoomTarget == .none {
            zoomTarget = .none
        }
    }

    func handleConfigButton() {
        if editorMode == .config {
            do {
                try fileStore.saveConfigText(editorText, for: selectedTool)
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
        editorText = fileStore.loadConfigText(for: selectedTool)
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
            
            // clear input
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
                        "Toolbox",
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
        terminalText += "\n[已停止]\n"
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

    private func resetToolSpecificState(for tool: ScriptTool) {
        if tool.id == "file-renamer" {
            renamerState = RenamerState()
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
