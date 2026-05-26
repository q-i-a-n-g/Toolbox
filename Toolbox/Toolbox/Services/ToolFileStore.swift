import Foundation

final class ToolFileStore {
    private let fileManager = FileManager.default

    func loadHelpText(for tool: ScriptTool) -> String {
        if
            let url = Bundle.main.resourceURL?
                .appendingPathComponent("Help", isDirectory: true)
                .appendingPathComponent(tool.helpFileName),
            let text = try? String(contentsOf: url, encoding: .utf8),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        if let helpText = tool.helpText, !helpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return helpText
        }

        return "未找到帮助文档。"
    }

    func loadConfigText(for tool: ScriptTool) -> String {
        let url = ensureConfigFile(for: tool)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func saveConfigText(_ text: String, for tool: ScriptTool) throws {
        let url = ensureConfigFile(for: tool)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func configURL(for tool: ScriptTool) -> URL {
        ensureConfigFile(for: tool)
    }

 
    private func ensureConfigFile(for tool: ScriptTool) -> URL {
        let directory = appSupportConfigDirectory()
        let url = directory.appendingPathComponent(tool.configFileName)

        if !fileManager.fileExists(atPath: url.path) {
            if let bundled = Bundle.main.resourceURL?
                .appendingPathComponent("Configs", isDirectory: true)
                .appendingPathComponent(tool.configFileName) {
                try? fileManager.copyItem(at: bundled, to: url)
            } else {
                try? "".write(to: url, atomically: true, encoding: .utf8)
            }
        } else {
            migrateConfigIfNeeded(for: tool, configURL: url)
        }

        return url
    }

    private func migrateConfigIfNeeded(for tool: ScriptTool, configURL: URL) {
        guard let bundledURL = Bundle.main.resourceURL?
                .appendingPathComponent("Configs", isDirectory: true)
                .appendingPathComponent(tool.configFileName),
              let bundledText = try? String(contentsOf: bundledURL, encoding: .utf8),
              let currentText = try? String(contentsOf: configURL, encoding: .utf8)
        else {
            return
        }

        // If files are already identical, skip.
        if currentText == bundledText { return }

        let currentValues = parseEnvValues(from: currentText)
        let bundledLines = bundledText.components(separatedBy: .newlines)

        var migratedLines: [String] = []
        for line in bundledLines {
            if let key = envKey(from: line), let existingValue = currentValues[key] {
                migratedLines.append("\(key)=\(existingValue)")
            } else {
                migratedLines.append(line)
            }
        }

        let migratedText = migratedLines.joined(separator: "\n")
        if migratedText != currentText {
            try? migratedText.write(to: configURL, atomically: true, encoding: .utf8)
        }
    }

    private func parseEnvValues(from text: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eqIndex = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[..<eqIndex]).trimmingCharacters(in: .whitespaces)
            let valueStart = line.index(after: eqIndex)
            let value = String(line[valueStart...])
            if !key.isEmpty {
                values[key] = value
            }
        }
        return values
    }

    private func envKey(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let eqIndex = trimmed.firstIndex(of: "=") else {
            return nil
        }
        let key = String(trimmed[..<eqIndex]).trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : key
    }

    private func appSupportConfigDirectory() -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base
            .appendingPathComponent("Toolbox", isDirectory: true)
            .appendingPathComponent("Configs", isDirectory: true)

        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }

        return directory
    }
}
